#!/system/bin/sh
# Y700 Unified Thermal Boost + Charge Log - V7.0
# V5.7 修复:
#   - 拔线后写0清除伪装温度, 恢复真实温度 (原版残留28度)
#   - 温控进程限频杀 (KILL_INTERVAL, 默认60s), 消除每5秒重启循环
#   - 伪装温度写回验证+重试, 保证持续生效
#   - 温区禁用状态在循环内始终维持, 防 HAL 复位
# V5.8 修复:
#   - 单实例锁: 防止 KSU 与 service.d 同时启动导致重复执行
# V5.9 修复:
#   - 温区发现改为按类型自适应扫描, 兼容各代 Y700 命名差异
# V6.0 修复:
#   - 三代(TB321FU)适配: batt1-therm/batt2-therm 纳入伪装
#   - 单实例锁改原子创建(O_EXCL), 消除开机并发竞态
#   - 机型识别: 三代TB321FU/四代TB322FC/五代TB323FU
# V6.1 修复:
#   - CCL解锁按µA量级判断, 三代单位不同不再写入(避免限流+PPS重协商)
# V6.2 修复:
#   - 单实例锁校验 pid 所属进程(防 pid 复用导致偶发失效)
# V6.3 新增:
#   - 充电日志增加"充电协议"行 (PD/PPS/DCP/SCP等)
# V6.4 新增:
#   - 充电日志增加"输入功率"(区分充电器输入 vs 电池实得, 便于诊断边充边玩)
#   - 修复充电协议在最终日志恒为"未识别"(改为充电期间捕获并留存)
# V6.5 修复:
#   - 输入电流改用 PMIC IIO ADC(in_current_*_iin_input): PPS 快充下
#     usb/current_now 恒为 0 导致输入功率恒为 0
#   - 未采集到有效输入电流时显示"不可读", 不再显示误导性的 0W
# V6.6 修复:
#   - 单实例保护改用 /proc 扫描 + pid 仲裁: 修复开机瞬间「锁文件内容尚未写入
#     就被读到空值」的竞态, 该竞态会导致两个实例同时运行(日志互相覆盖)
# V6.7 修复:
#   - 杀温控进程改为按进程名通用匹配, 兼容非 .qti 命名
#     (如 android.hardware.thermal-service@1.0), 提升异机型兼容性
# V6.8 修复:
#   - 输入功率增加「合理性校验」: 部分平台在 PPS 下返回极小垃圾值
#     (如 17637µA -> 0.1W), 会被当成有效样本。现按能量守恒剔除
# V6.9 修复:
#   - 上述校验收窄为「仅对 PPS/PD 生效」: SDP/DCP 下节点可靠,
#     避免电池读数尖峰把有效输入样本误剔除
# V7.0 新增(兼容性开关, 解决部分四代/五代机型充电被锁在 10W):
#   - ZONE_MODE=1|2  温区处理方式
#       1 = 禁用温区 + 伪装温度 (默认, 游戏性能最好)
#       2 = 仅伪装温度, 保持温区 mode=enabled
#     背景: 部分平台在温区被 disabled 后会回落到保护性小电流(实测约10W),
#     此时改用「仅伪装」即可骗过温控又不触发该保护逻辑
#   - KILL_THERMAL=0|1  是否周期击杀温控进程
#       0 = 不杀(默认, 交给平台自管)  1 = 杀
#   - 【重要修复】杀温控进程的实现原先用 `ps -A -o PID,NAME` 匹配进程名,
#     但模块运行上下文里 ps 无法列出其他进程名(实测温控行数恒为 0),
#     导致 V6.x 的「杀温控进程」一直是静默失效(等于没杀)。V7.0 改用
#     /proc/<pid>/cmdline 扫描(与单实例检测同源), 现已实测可命中。
#     因该功能直到本版才真正生效, 默认设为 0, 避免升级后行为被悄悄改变。
#   - ZONE_MODE=2 时会把此前禁用的温区重新写回 enabled
#   - 温区禁用清单改为按开机校验后重建(温区编号每次开机可能变化, 旧实现会
#     残留上百条脏数据, 且每 5 秒对每温区 grep 一次)
#   - 新增 runtime.log 运行日志(/data/local/tmp/y700_thermal_boost/runtime.log,
#     保留最近 200 行): 记录启动参数、温区模式、杀温控动作, 便于事后排查
# 温区命名: 五代/四代=batt-pack-therm/batt2-pack-therm; 三代=batt1-therm/batt2-therm

[ -z "$MODDIR" ] && MODDIR="/data/adb/modules/y700_thermal_boost"

# ---- 单实例保护 (KSU 与 service.d 会同时拉起, 只保留一个) ----
# 不用锁文件(存在「创建后内容尚未写入就被读到空值」的竞态 + pid 复用问题),
# 改为扫描 /proc 找同脚本实例, 并以 pid 大小仲裁: 只认比本进程更早启动(lower pid)的,
# 早启动者胜出, 后来者退出。
PID_FILE="/data/local/tmp/y700_thermal_boost.pid"
older_instance_running() {
    for p in /proc/[0-9]*; do
        _p=${p##*/}
        [ "$_p" = "$$" ] && continue
        [ "$_p" -lt "$$" ] 2>/dev/null || continue
        grep -qa "y700_thermal_boost/service.sh" "$p/cmdline" 2>/dev/null && return 0
    done
    return 1
}
if older_instance_running; then
    echo "y700_thermal_boost: 已有更早启动的实例, 退出"
    exit 0
fi
# 开机时两个实例几乎同时启动, 等 3 秒让对方的命令行可见后复查
sleep 3
if older_instance_running; then
    echo "y700_thermal_boost: 检测到更早实例, 退出"
    exit 0
fi
echo $$ > "$PID_FILE" 2>/dev/null
trap 'rm -f "$PID_FILE"' EXIT TERM INT

LOG_TAG="Y700-ThermalBoost"
LOG_DIR="/sdcard/充电日志"
TMP_DIR="/data/local/tmp/charging_data"
STATE_DIR="/data/local/tmp/y700_thermal_boost"
DISABLED_LIST="$STATE_DIR/disabled_zones.list"
RUNTIME_LOG="$STATE_DIR/runtime.log"

TEMP_PATH="/sys/class/power_supply/battery/temp"
CURRENT_PATH="/sys/class/power_supply/battery/current_now"
VOLTAGE_PATH="/sys/class/power_supply/battery/voltage_now"
STATUS_PATH="/sys/class/power_supply/battery/status"
CAPACITY_PATH="/sys/class/power_supply/battery/capacity"
CCL_PATH="/sys/class/power_supply/battery/charge_control_limit"
CCL_MAX_PATH="/sys/class/power_supply/battery/charge_control_limit_max"
PROTOCOL_PATH="/sys/class/power_supply/usb/real_type"
IN_VOLTAGE_PATH="/sys/class/power_supply/usb/voltage_now"
IN_CURRENT_PATH="/sys/class/power_supply/usb/current_now"
IN_LIMIT_PATH="/sys/class/power_supply/usb/input_current_limit"
# PMIC IIO ADC 的输入电流节点 (PPS 快充下 usb/current_now 恒为 0, 必须用这个)
# 启动时通过 find 解析, 兼容各代机型
IIN_NODE=""

resolve_iin_node() {
    IIN_NODE=""
    for f in $(find /sys/devices/platform/soc -maxdepth 8 -name "in_current_*_iin_input" 2>/dev/null); do
        case "$f" in
            *pmih010x_iin*) IIN_NODE="$f"; return 0 ;;
        esac
    done
    for f in $(find /sys/devices/platform/soc -maxdepth 8 -name "in_current_*_iin_input" 2>/dev/null); do
        if [ -n "$(cat "$f" 2>/dev/null)" ]; then IIN_NODE="$f"; return 0; fi
    done
    return 1
}

# 读取输入电流(µA): 优先 IIO ADC(iin), 回退 usb/current_now
read_input_current() {
    if [ -n "$IIN_NODE" ]; then
        v=$(cat "$IIN_NODE" 2>/dev/null)
        [ -n "$v" ] && echo "$v" && return 0
    fi
    cat "$IN_CURRENT_PATH" 2>/dev/null
}

ENABLE_THERMAL_BYPASS=1
ENABLE_CHARGE_LOG=1
SAMPLE_INTERVAL=5
FAKE_TEMP_CHG=25000
FAKE_TEMP_BATT=28000
FAKE_TEMP_USB=25000
FAKE_TEMP_AP=30000
LOG_KEEP_COUNT=30
KILL_INTERVAL=60
# 温区处理方式: 1=禁用+伪装(默认, 游戏性能最好)  2=仅伪装不禁用(部分平台需要, 兼容性更好)
ZONE_MODE=1
# 是否周期击杀温控进程: 0=不杀(默认, 与 V6.x 实际行为一致) 1=杀
# 注: V6.x 的实现依赖 ps 的 NAME 列, 在模块上下文里恒为空 -> 一直是静默失效(等于没杀)。
#     V7.0 改用 /proc/<pid>/cmdline 扫描后才真正生效, 因此默认改为 0(不引入新变量),
#     需要的人再显式开 1。
KILL_THERMAL=0

load_config() {
    [ -f "$MODDIR/config.prop" ] || return 0
    while IFS= read -r line || [ -n "$line" ]; do
        line=$(printf '%s' "$line" | tr -d '\r')
        case "$line" in ''|\#*) continue ;; esac
        key=${line%%=*}
        val=${line#*=}
        case "$key" in
            ENABLE_THERMAL_BYPASS|ENABLE_CHARGE_LOG|SAMPLE_INTERVAL|FAKE_TEMP_CHG|FAKE_TEMP_BATT|FAKE_TEMP_USB|FAKE_TEMP_AP|LOG_KEEP_COUNT|KILL_INTERVAL|ZONE_MODE|KILL_THERMAL)
                eval "$key=\"$val\""
                ;;
        esac
    done < "$MODDIR/config.prop"
}

load_config

# 参数合法性修正
case "$KILL_INTERVAL" in
    ''|*[!0-9]*) KILL_INTERVAL=60 ;;
esac
[ "$KILL_INTERVAL" -lt 5 ] 2>/dev/null && KILL_INTERVAL=5
[ "$SAMPLE_INTERVAL" -lt 1 ] 2>/dev/null && SAMPLE_INTERVAL=5
case "$ZONE_MODE" in 1|2) ;; *) ZONE_MODE=1 ;; esac
case "$KILL_THERMAL" in 0|1) ;; *) KILL_THERMAL=1 ;; esac

log_me() { log -t "$LOG_TAG" "$1"; echo "$1"; }

# 运行日志: log_me 走 logcat(会被刷掉), 这里落盘保留最近 200 行, 便于事后排查
# (/data/local/tmp/y700_thermal_boost/runtime.log)
rt_log() {
    echo "$(date '+%m-%d %H:%M:%S') $1" >> "$RUNTIME_LOG" 2>/dev/null
    _n=$(wc -l < "$RUNTIME_LOG" 2>/dev/null)
    if [ -n "$_n" ] && [ "$_n" -gt 200 ] 2>/dev/null; then
        tail -n 100 "$RUNTIME_LOG" > "${RUNTIME_LOG}.tmp" 2>/dev/null && mv "${RUNTIME_LOG}.tmp" "$RUNTIME_LOG" 2>/dev/null
    fi
}

zone_valid() { [ -n "$1" ] && [ -d "$1" ]; }

calc_power_w() {
    u=$1; i=$2
    i=${i#-}
    awk "BEGIN { printf \"%.1f\", $u * $i / 1000000000000 }"
}

detect_device_label() {
    model=$(getprop ro.product.model 2>/dev/null)
    case "$model" in
        TB323FU*) echo "Y700 五代 ($model)" ;;
        TB322FC*) echo "Y700 四代 ($model)" ;;
        TB320FU*|TB321FU*) echo "Y700 三代 ($model)" ;;
        *) echo "Y700 ($model)" ;;
    esac
}

# 读取当前充电协议 (real_type -> 友好名称)
get_charge_protocol() {
    rt=$(cat "$PROTOCOL_PATH" 2>/dev/null)
    case "$rt" in
        PD_PPS)                 echo "PD/PPS" ;;
        PD_DRP|PD)              echo "PD" ;;
        DCP)                    echo "DCP" ;;
        CDP)                    echo "CDP" ;;
        SDP)                    echo "SDP" ;;
        SCP)                    echo "SCP" ;;
        VOOC|SUPERVOOC)         echo "VOOC" ;;
        ACA|BrickID)            echo "$rt" ;;
        ''|Unknown)             echo "未识别" ;;
        *)                      echo "$rt" ;;
    esac
}

# 本机已禁用温区集合(内存, 避免每轮 grep 文件; 也能防止温区编号跨重启变化后残留脏数据)
DISABLED_SET=""
record_disabled() {
    z=$1
    case " $DISABLED_SET " in
        *" $z "*) return 0 ;;
    esac
    DISABLED_SET="$DISABLED_SET $z"
    DISABLED_N=$((DISABLED_N + 1))
    echo "$z" >> "$DISABLED_LIST"
}

disable_zone_mode() {
    z=$1
    zone_valid "$z" || return 1
    # 注意: 重定向失败的错误不受行尾 2>/dev/null 管, 必须用 { } 2>/dev/null 包住
    { echo "disabled" > "${z}/mode"; } 2>/dev/null || return 1
    record_disabled "$z"
}

# 启动时载入禁用清单并清理: 只保留「仍存在且当前确实是 disabled」的温区
# (温区编号每次开机都可能变化, 旧编号会指向别的温区 -> 必须校验后再用)
load_disabled_list() {
    DISABLED_SET=""
    DISABLED_N=0
    [ -f "$DISABLED_LIST" ] || return 0
    _tmp="${DISABLED_LIST}.tmp"
    : > "$_tmp" 2>/dev/null
    while IFS= read -r _z; do
        [ -n "$_z" ] || continue
        zone_valid "$_z" || continue
        [ "$(cat "${_z}/mode" 2>/dev/null)" = "disabled" ] || continue
        case " $DISABLED_SET " in
            *" $_z "*) continue ;;
        esac
        DISABLED_SET="$DISABLED_SET $_z"
        DISABLED_N=$((DISABLED_N + 1))
        echo "$_z" >> "$_tmp"
    done < "$DISABLED_LIST"
    mv "$_tmp" "$DISABLED_LIST" 2>/dev/null || : > "$DISABLED_LIST"
}

# 写入伪装温度/清除温度, 带写回验证+重试 (v=0 表示清除仿真)
write_emul() {
    z=$1; v=$2
    zone_valid "$z" || return 1
    chmod 666 "${z}/emul_temp" 2>/dev/null
    i=0
    while [ $i -lt 3 ]; do
        { echo "$v" > "${z}/emul_temp"; } 2>/dev/null
        r=$(cat "${z}/temp" 2>/dev/null)
        if [ "$v" = "0" ]; then
            [ -n "$r" ] && [ "$r" != "0" ] && return 0
        else
            [ "$r" = "$v" ] && return 0
        fi
        i=$((i+1))
        sleep 1
    done
    return 1
}

apply_fake_temps() {
    for z in $CHG_ZONES; do write_emul "$z" "$FAKE_TEMP_CHG"; done
    for z in $BATT_ZONES; do write_emul "$z" "$FAKE_TEMP_BATT"; done
    for z in $USB_ZONES; do write_emul "$z" "$FAKE_TEMP_USB"; done
    for z in $MISC_ZONES; do write_emul "$z" "$FAKE_TEMP_AP"; done
}

clear_fake_temps() {
    for z in $ALL_ZONES; do write_emul "$z" 0; done
}

apply_thermal_bypass() {
    # 仅禁用温区; 温度伪装由主循环按充电状态管理
    # ZONE_MODE=2 时不禁用温区(部分平台禁用后充电策略会回落到保护性小电流)
    if [ "$ZONE_MODE" != "1" ]; then
        restore_zone_mode
        return 0
    fi
    for z in $DISABLE_ZONES; do disable_zone_mode "$z"; done
}

# 恢复温区: ZONE_MODE=2 切回 1 时把之前禁用的温区重新启用
restore_zone_mode() {
    [ -n "$DISABLED_SET" ] || return 0
    for z in $DISABLED_SET; do
        zone_valid "$z" || continue
        { echo "enabled" > "${z}/mode"; } 2>/dev/null
    done
    DISABLED_SET=""
    DISABLED_N=0
    : > "$DISABLED_LIST" 2>/dev/null
}

unlock_ccl() {
    [ "$HAS_CCL" != "1" ] && return 0
    ccl_max=$(cat "$CCL_MAX_PATH" 2>/dev/null)
    # 仅在 µA 量级(ccl_max>100000, 如五代12400000)时解锁;
    # 三代TB321FU ccl_max=12 单位不同, 写入反而限流并引发PPS反复重协商, 跳过
    [ -n "$ccl_max" ] && [ "$ccl_max" -gt 100000 ] 2>/dev/null || return 0
    { echo "$ccl_max" > "$CCL_PATH"; } 2>/dev/null
}

kill_thermal_services() {
    # 通用匹配: 兼容各机型/各代热服务命名
    #   Y700 五代: android.hardware.thermal-service.qti / thermal-engine-v2
    #   其他机型:  android.hardware.thermal-service@1.0 / thermal_hal / vendor.thermal-hal 等
    # 实现: 扫描 /proc/<pid>/cmdline (与单实例检测同源, 已验证在模块上下文可用);
    #       不用 `ps` 的 NAME 列 —— 模块环境下 ps 输出不可靠, 曾导致本功能静默失效
    # 注意: 必须排除自身(脚本路径含 y700_thermal_boost, 会被 *thermal* 误匹配)
    _n=0
    for p in /proc/[0-9]*; do
        _pid=${p##*/}
        [ "$_pid" = "$$" ] && continue
        # 先判可读, 否则 tr 的重定向失败信息会打到 stderr(行尾 2>/dev/null 管不住)
        [ -r "$p/cmdline" ] || continue
        _cmd=$(cat "$p/cmdline" 2>/dev/null | tr '\0' ' ')
        [ -n "$_cmd" ] || continue
        case "$_cmd" in
            *y700_thermal_boost*|*y700_diag*) continue ;;
            *thermal*|*Thermal*) ;;
            *) continue ;;
        esac
        if kill "$_pid" 2>/dev/null; then
            rt_log "  已杀温控进程: $_cmd (pid $_pid)"
            _n=$((_n + 1))
        else
            rt_log "  杀失败(权限/上下文拦截): $_cmd (pid $_pid)"
        fi
    done
    [ "$_n" -eq 0 ] && rt_log "  未匹配到温控进程"
    return 0
}

prune_old_logs() {
    [ "$LOG_KEEP_COUNT" -gt 0 ] 2>/dev/null || return 0
    [ -d "$LOG_DIR" ] || return 0
    ls -1t "$LOG_DIR"/*.log 2>/dev/null | tail -n +$((LOG_KEEP_COUNT + 1)) | while read -r f; do
        rm -f "$f" 2>/dev/null
    done
}

until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 1; done
sleep 5

DEVICE_LABEL=$(detect_device_label)
ANDROID_VER=$(getprop ro.build.version.release 2>/dev/null)

log_me "========================================"
log_me "$DEVICE_LABEL 统一模块 V7.0 启动"
log_me "Android $ANDROID_VER"
log_me "========================================"

# ---- 温区发现: 按类型扫描, 兼容各代 Y700 的命名差异 ----
CHG_ZONES=""; BATT_ZONES=""; USB_ZONES=""; MISC_ZONES=""
for z in /sys/devices/virtual/thermal/thermal_zone*; do
    t=$(cat "$z/type" 2>/dev/null)
    case "$t" in
        fast-chg-therm|top-chg-therm)
            CHG_ZONES="$CHG_ZONES $z" ;;
        battery|quiet-therm|batt-pack-therm|batt2-pack-therm|batt1-therm|batt2-therm)
            BATT_ZONES="$BATT_ZONES $z" ;;
        usb1-conn-therm|usb2-conn-therm|usb)
            USB_ZONES="$USB_ZONES $z" ;;
        ap-therm|lcm-thermal)
            MISC_ZONES="$MISC_ZONES $z" ;;
    esac
done
ALL_ZONES="$CHG_ZONES $BATT_ZONES $USB_ZONES $MISC_ZONES"
DISABLE_ZONES="$CHG_ZONES $USB_ZONES $MISC_ZONES"

zone_count=0
for z in $ALL_ZONES; do zone_valid "$z" && zone_count=$((zone_count + 1)); done
[ $zone_count -eq 0 ] && log_me "! 未找到温区，模块退出" && exit 1

HAS_CCL=0
[ -r "$CCL_MAX_PATH" ] && [ -e "$CCL_PATH" ] && HAS_CCL=1

# 解析输入电流节点 (PPS 下 usb/current_now 恒为 0, 需用 PMIC IIO ADC)
resolve_iin_node && log_me "* 输入电流节点: $IIN_NODE" || log_me "! 未找到 IIO 输入电流节点, 回退 usb/current_now"

log_me "* 温区 ${zone_count} 个 | CCL=$([ "$HAS_CCL" = "1" ] && echo 支持 || echo 无) | 温控=$ENABLE_THERMAL_BYPASS | 温区模式=$( [ "$ZONE_MODE" = "1" ] && echo '禁用+伪装' || echo '仅伪装' ) | 杀进程=$([ "$KILL_THERMAL" = "1" ] && echo 开 || echo 关) | 日志=$ENABLE_CHARGE_LOG | 杀进程间隔=${KILL_INTERVAL}s"

mkdir -p "$TMP_DIR" "$LOG_DIR" "$STATE_DIR" 2>/dev/null
touch "$DISABLED_LIST" 2>/dev/null
load_disabled_list
[ "$DISABLED_N" -gt 0 ] 2>/dev/null && log_me "* 已保留上次禁用的温区 $DISABLED_N 个 (校验有效)"

if [ "$ENABLE_THERMAL_BYPASS" = "1" ]; then
    apply_thermal_bypass
    unlock_ccl
    [ "$KILL_THERMAL" = "1" ] && kill_thermal_services
    log_me "* 温控绕过已激活 (温区模式=$ZONE_MODE)"
    rt_log "温控绕过已激活: 温区模式=$ZONE_MODE 本机禁用温区=$DISABLED_N 个 CCL支持=$HAS_CCL"
fi

prune_old_logs
log_me "* 监控启动 (${SAMPLE_INTERVAL}s)"

flush_charging_log() {
    final=$1
    [ -z "$CHARGING_LOG_FILE" ] && return 0
    [ $POWER_COUNT -eq 0 ] && [ "$final" != "1" ] && {
        {
            echo "=========================================="
            echo "       $DEVICE_LABEL 充电日志"
            echo "=========================================="
            echo ""
            echo "【充电进行中】"
            echo "  模块版本:   V7.0 (温区模式 $ZONE_MODE)"
            echo "  设备:       $DEVICE_LABEL"
            echo "  充电协议:   $CHARGE_PROTOCOL"
            echo "  开始时间:   $CHARGING_START_TIME"
            echo "  开始电量:   ${CHARGING_START_CAP}%"
            echo "  当前电量:   ${CAPACITY}%"
            echo ""
            echo "  (充电结束后将更新完整统计)"
            echo "=========================================="
        } > "$CHARGING_LOG_FILE"
        return 0
    }
    [ $POWER_COUNT -eq 0 ] && return 0
    AVG_POWER=$(echo "$POWER_SUM $POWER_COUNT" | awk '{printf "%.1f", $1/$2}')
    AVG_TEMP=$(echo "$TEMP_SUM $TEMP_COUNT" | awk '{printf "%.1f", $1/$2}')
    if [ "$IN_COUNT" -gt 0 ] 2>/dev/null; then
        IN_AVG=$(echo "$IN_SUM $IN_COUNT" | awk '{printf "%.1f", $1/$2}')
    else
        IN_AVG=0
    fi
    ELAPSED_MIN=$((SAMPLE_INTERVAL * POWER_COUNT / 60))
    CHARGED=$((CAPACITY - CHARGING_START_CAP))
    [ $CHARGED -lt 0 ] && CHARGED=0
    {
        echo "=========================================="
        echo "       $DEVICE_LABEL 充电日志"
        echo "=========================================="
        echo ""
        if [ "$final" = "1" ]; then
            echo "【基本信息】"
        else
            echo "【充电进行中】"
        fi
        echo "  模块版本:   V7.0 (温区模式 $ZONE_MODE)"
        echo "  设备:       $DEVICE_LABEL"
        echo "  充电协议:   $CHARGE_PROTOCOL"
        echo "  系统:       Android $ANDROID_VER"
        echo "  开始时间:   $CHARGING_START_TIME"
        if [ "$final" = "1" ]; then
            echo "  结束时间:   $NOW"
            echo "  充电时长:   约 ${ELAPSED_MIN}分"
        else
            echo "  当前时间:   $NOW"
            echo "  已充时长:   约 ${ELAPSED_MIN}分"
        fi
        echo ""
        echo "  开始电量:   ${CHARGING_START_CAP}%"
        echo "  当前电量:   ${CAPACITY}%"
        echo "  已充入:     ${CHARGED}%"
        if [ "$HAS_CCL" = "1" ]; then
            echo "  充电电流上限: $(cat $CCL_PATH 2>/dev/null)/$(cat $CCL_MAX_PATH 2>/dev/null)"
        fi
        echo ""
        echo "【功率统计】"
        echo "  电池峰值功率: ${POWER_PEAK}W"
        echo "  电池平均功率: ${AVG_POWER}W"
        if [ "${IN_COUNT:-0}" -gt 0 ] 2>/dev/null; then
            echo "  输入峰值功率: ${IN_PEAK}W"
            echo "  输入平均功率: ${IN_AVG}W"
        else
            echo "  输入功率:   不可读(PPS快充下平台不提供输入电流)"
            [ "${IN_V_PEAK:-0}" -gt 0 ] 2>/dev/null && echo "  输入电压峰值: $(awk "BEGIN{printf \"%.2f\", $IN_V_PEAK/1000000}")V (PPS档位)"
        fi
        echo ""
        echo "【温度统计】"
        echo "  峰值温度:   ${TEMP_PEAK}C"
        echo "  平均温度:   ${AVG_TEMP}C"
        if [ "$final" = "1" ]; then
            echo ""
            echo "【分阶段详情】"
            echo "----------------------------------------"
            for STAGE in 0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95; do
                SF="$STAGE_DIR/s${STAGE}"
                RAWF="${SF}.raw"
                [ -f "$SF" ] || continue
                SS=0; PSUM=0; PPEAK=0; TSUM=0; TPEAK=0
                if [ -f "$RAWF" ]; then
                    while IFS='|' read -r TS PW TC; do
                        SS=$((SS + 1))
                        if [ -n "$PW" ] && [ "$PW" != "0.0" ]; then
                            PSUM=$(echo "$PSUM $PW" | awk '{printf "%.1f", $1+$2}')
                            [ "$(echo "$PW $PPEAK" | awk '{print ($1>$2)}')" = "1" ] && PPEAK=$PW
                        fi
                        if [ -n "$TC" ] && [ "$TC" -gt 0 ] 2>/dev/null && [ "$TC" -lt 100 ] 2>/dev/null; then
                            TSUM=$((TSUM + TC))
                            [ "$TC" -gt "$TPEAK" ] && TPEAK=$TC
                        fi
                    done < "$RAWF"
                fi
                [ $SS -eq 0 ] && continue
                PAVG=$(echo "$PSUM $SS" | awk '{printf "%.1f", $1/$2}')
                TAVG=$(echo "$TSUM $SS" | awk '{printf "%.0f", $1/$2}')
                echo "${STAGE}% | 采样=${SS} | 峰值=${PPEAK}W 均值=${PAVG}W | 峰温=${TPEAK}C 均温=${TAVG}C"
            done
        fi
        echo ""
        echo "=========================================="
        echo "  采样: ${POWER_COUNT}次 / ${SAMPLE_INTERVAL}秒"
        echo "=========================================="
    } > "$CHARGING_LOG_FILE"
}

PREV_STATUS="Unknown"
CHARGING_START_TIME=""
CHARGING_START_CAP=""
CHARGING_LOG_FILE=""
POWER_SUM=0
POWER_COUNT=0
POWER_PEAK=0
TEMP_SUM=0
TEMP_COUNT=0
TEMP_PEAK=0
IN_SUM=0
IN_COUNT=0
IN_PEAK=0
IN_V_PEAK=0
CHARGE_PROTOCOL="未识别"
STAGE_DIR="$TMP_DIR/stages"
mkdir -p "$STAGE_DIR"
log_me "* 模块运行中"

LAST_KILL=0
KILL_DEBUG_ONCE=0
rt_log "===== 启动: 模块 V7.0 pid=$$ 机型=$DEVICE_LABEL 温区模式=$ZONE_MODE 杀温控=$KILL_THERMAL 间隔=${KILL_INTERVAL}s ====="
rt_log "环境: PATH=$PATH"
while true; do
    STATUS=$(cat "$STATUS_PATH" 2>/dev/null)
    CAPACITY=$(cat "$CAPACITY_PATH" 2>/dev/null)
    CURRENT=$(cat "$CURRENT_PATH" 2>/dev/null)
    VOLTAGE=$(cat "$VOLTAGE_PATH" 2>/dev/null)
    TEMP_RAW=$(cat "$TEMP_PATH" 2>/dev/null)
    IN_V=$(cat "$IN_VOLTAGE_PATH" 2>/dev/null)
    IN_I=$(read_input_current)
    IN_LIMIT=$(cat "$IN_LIMIT_PATH" 2>/dev/null)
    POWER_W=$(calc_power_w "$VOLTAGE" "$CURRENT")
    IN_POWER_W=$(calc_power_w "$IN_V" "$IN_I")
    TEMP_C=$((${TEMP_RAW:-0} / 10))
    NOW=$(date '+%H:%M:%S')

    if [ "$ENABLE_CHARGE_LOG" = "1" ]; then
        if [ "$STATUS" = "Charging" ] && [ "$PREV_STATUS" != "Charging" ]; then
            CHARGING_START_TIME="$NOW ($(date '+%Y-%m-%d %H:%M:%S'))"
            CHARGING_START_CAP="$CAPACITY"
            CHARGING_LOG_FILE="$LOG_DIR/$(date '+%Y.%m.%d.%H.%M.%S').log"
            POWER_SUM=0; POWER_COUNT=0; POWER_PEAK=0
            TEMP_SUM=0; TEMP_COUNT=0; TEMP_PEAK=0
            IN_SUM=0; IN_COUNT=0; IN_PEAK=0; IN_V_PEAK=0
            CHARGE_PROTOCOL=$(get_charge_protocol)
            rm -f "$STAGE_DIR"/* "$STAGE_DIR"/*.raw 2>/dev/null
            log_me "* 充电开始 | ${CAPACITY}%"
            flush_charging_log 0
            [ "$ENABLE_THERMAL_BYPASS" = "1" ] && unlock_ccl
        fi

        if [ "$STATUS" != "Charging" ] && [ "$PREV_STATUS" = "Charging" ]; then
            if [ -n "$CHARGING_LOG_FILE" ]; then
                flush_charging_log 1
                log_me "* 充电结束 | ${CHARGING_START_CAP}%->${CAPACITY}% | 峰值${POWER_PEAK}W"
            fi
            CHARGING_LOG_FILE=""
        fi

        if [ "$STATUS" = "Charging" ]; then
            # 更新充电协议(协商可能滞后, 只取有效值)
            P=$(get_charge_protocol)
            [ -n "$P" ] && [ "$P" != "未识别" ] && CHARGE_PROTOCOL="$P"
            if [ -n "$POWER_W" ] && [ "$POWER_W" != "0.0" ]; then
                POWER_SUM=$(echo "$POWER_SUM $POWER_W" | awk '{printf "%.1f", $1+$2}')
                POWER_COUNT=$((POWER_COUNT + 1))
                [ "$(echo "$POWER_W $POWER_PEAK" | awk '{print ($1>$2)}')" = "1" ] && POWER_PEAK=$POWER_W
            fi
            # 输入功率合理性校验(仅对 PPS/PD 生效):
            #   这两种模式下部分平台会返回极小垃圾值(如 17637µA -> 0.1W),
            #   按能量守恒剔除(充电时输入功率必然 >= 电池功率)。
            #   SDP/DCP 下节点可靠, 不做此校验(避免电池读数尖峰误剔除有效样本)
            IN_OK=0
            if [ -n "$IN_POWER_W" ] && [ "$IN_POWER_W" != "0.0" ]; then
                case "$CHARGE_PROTOCOL" in
                    *PPS*|PD*)
                        IN_OK=$(awk "BEGIN{print ($IN_POWER_W >= $POWER_W * 0.5) ? 1 : 0}" 2>/dev/null)
                        ;;
                    *)
                        IN_OK=1
                        ;;
                esac
            fi
            if [ "$IN_OK" = "1" ]; then
                IN_SUM=$(echo "$IN_SUM $IN_POWER_W" | awk '{printf "%.1f", $1+$2}')
                IN_COUNT=$((IN_COUNT + 1))
                [ "$(echo "$IN_POWER_W $IN_PEAK" | awk '{print ($1>$2)}')" = "1" ] && IN_PEAK=$IN_POWER_W
            fi
            # 记录输入电压峰值(µV) - PPS 下输入电流不可读, 但电压可用, 可反映 PPS 档位
            if [ -n "$IN_V" ] && [ "$IN_V" -gt "$IN_V_PEAK" ] 2>/dev/null; then
                IN_V_PEAK=$IN_V
            fi
            if [ $TEMP_C -gt 0 ] && [ $TEMP_C -lt 100 ]; then
                TEMP_SUM=$((TEMP_SUM + TEMP_C))
                TEMP_COUNT=$((TEMP_COUNT + 1))
                [ $TEMP_C -gt $TEMP_PEAK ] && TEMP_PEAK=$TEMP_C
            fi
            STAGE=$((CAPACITY / 5 * 5))
            SF="$STAGE_DIR/s${STAGE}"
            [ ! -f "$SF" ] && touch "$SF"
            echo "$NOW|$POWER_W|$TEMP_C" >> "${SF}.raw"
            [ $((POWER_COUNT % 6)) -eq 0 ] && flush_charging_log 0
        fi
    fi

    if [ "$ENABLE_THERMAL_BYPASS" = "1" ]; then
        # 温区禁用始终维持 (防 HAL 复位); ZONE_MODE=2 仅伪装不解禁
        if [ "$ZONE_MODE" = "1" ]; then
            for z in $DISABLE_ZONES; do disable_zone_mode "$z"; done
        else
            restore_zone_mode
        fi
        if [ "$STATUS" = "Charging" ]; then
            # 充电中: 伪装温度 + 解锁CCL
            apply_fake_temps
            unlock_ccl
        else
            # 未充电: 清除伪装温度, 恢复真实温度
            clear_fake_temps
        fi
        # 温控进程限频杀, 避免频繁重启造成干扰 (KILL_THERMAL=0 时交给平台自管)
        NOW_EPOCH=$(date +%s 2>/dev/null)
        [ -z "$NOW_EPOCH" ] && NOW_EPOCH=0
        if [ "$KILL_THERMAL" = "1" ] && [ $((NOW_EPOCH - LAST_KILL)) -ge "$KILL_INTERVAL" ] 2>/dev/null; then
            rt_log "周期杀温控 (间隔 ${KILL_INTERVAL}s, now=$NOW_EPOCH)"
            kill_thermal_services
            LAST_KILL=$NOW_EPOCH
        elif [ "$KILL_THERMAL" = "1" ] && [ "$KILL_DEBUG_ONCE" != "1" ]; then
            KILL_DEBUG_ONCE=1
            rt_log "! 杀温控条件未满足: KILL_THERMAL=$KILL_THERMAL now=$NOW_EPOCH last=$LAST_KILL 间隔=$KILL_INTERVAL"
        fi
    fi

    PREV_STATUS="$STATUS"
    sleep "$SAMPLE_INTERVAL"
done
