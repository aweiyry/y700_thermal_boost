#!/system/bin/sh
# ============================================================
#  Y700 温控模块 完整监控 / 诊断脚本
#  用途: 一次性检测模块全部作用点, 并做 1 分钟动态监控
#  用法: 终端中执行   su -c "sh y700_diag.sh"
#        可选参数:   采样时长秒数 (默认 60)
#  输出: /sdcard/Y700模块诊断_<时间>.txt
# ============================================================

MODDIR=/data/adb/modules/y700_thermal_boost
DURATION=${1:-60}
TS=$(date '+%Y%m%d_%H%M%S')
REPORT="/sdcard/Y700模块诊断_${TS}.txt"

# 电源节点
B=/sys/class/power_supply/battery
U=/sys/class/power_supply/usb
CCLP="$B/charge_control_limit"
CCLMAXP="$B/charge_control_limit_max"

out() { echo "$1" >> "$REPORT"; echo "$1"; }

PROBLEMS=""
add_problem() { PROBLEMS="${PROBLEMS}$1
"; }

find_zone() {
    for z in /sys/devices/virtual/thermal/thermal_zone*; do
        [ "$(cat "$z/type" 2>/dev/null)" = "$1" ] && { echo "$z"; return 0; }
    done
    return 1
}
zone_mode() { cat "$1/mode" 2>/dev/null; }
zone_temp() { cat "$1/temp" 2>/dev/null; }
v2() { awk "BEGIN{printf \"%.2f\", $1/1000000}" 2>/dev/null; }
v3() { awk "BEGIN{printf \"%.3f\", $1/1000000}" 2>/dev/null; }

# 读取配置
CFG_BYPASS=1; FAKE_CHG=25000; FAKE_BATT=28000; FAKE_USB=25000; FAKE_AP=30000
if [ -f "$MODDIR/config.prop" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        line=$(printf '%s' "$line" | tr -d '\r')
        case "$line" in ''|\#*) continue ;; esac
        case "${line%%=*}" in
            ENABLE_THERMAL_BYPASS) CFG_BYPASS=${line#*=} ;;
            FAKE_TEMP_CHG)  FAKE_CHG=${line#*=} ;;
            FAKE_TEMP_BATT) FAKE_BATT=${line#*=} ;;
            FAKE_TEMP_USB)  FAKE_USB=${line#*=} ;;
            FAKE_TEMP_AP)   FAKE_AP=${line#*=} ;;
        esac
    done < "$MODDIR/config.prop"
fi

: > "$REPORT"

out "============================================================"
out "        Y700 温控模块 完整监控报告"
out "============================================================"
out "生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
out "监控时长: ${DURATION} 秒"
out ""

# ============ 1. 环境与设备状态 ============
out "【1】环境与设备状态"
MODEL=$(getprop ro.product.model 2>/dev/null)
out "  设备型号:   $MODEL"
out "  Android:    $(getprop ro.build.version.release 2>/dev/null) (SDK $(getprop ro.build.version.sdk 2>/dev/null))"
out "  内核:       $(uname -r 2>/dev/null)"
out "  开机时长:   $(awk '{printf "%.0f 分钟", $1/60}' /proc/uptime 2>/dev/null)"
out "  Root:       $(id -u 2>/dev/null | grep -q '^0$' && echo '已获取(uid=0)' || echo '未获取(请用 su 执行)')"
out "  SELinux:    $(getenforce 2>/dev/null)"
out "  当前上下文: $(cat /proc/self/attr/current 2>/dev/null)"
case "$MODEL" in
    TB323FU*) GEN="五代 (TB323FU)" ;;
    TB322FC*) GEN="四代 (TB322FC)" ;;
    TB320FU*|TB321FU*) GEN="三代 ($MODEL)" ;;
    *) GEN="未知机型 ($MODEL) —— 本模块为 Y700 设计, 异机型仅供参考" ;;
esac
out "  机型识别:   $GEN"
out "  负载:       $(cat /proc/loadavg 2>/dev/null)"
FM=$(free -m 2>/dev/null | awk 'NR==2{printf "%s/%s MB", $3, $2}')
out "  内存使用:   ${FM:-未知}"
SCR=$(dumpsys power 2>/dev/null | grep -m1 -E "mWakefulness=" | sed 's/.*mWakefulness=//' | awk '{print $1}')
case "$SCR" in Awake) SCR="亮屏(Awake)";; Asleep) SCR="息屏(Asleep)";; Dozing) SCR="休眠(Dozing)";; "") SCR="未知";; esac
out "  屏幕状态:   $SCR"
FG=$(dumpsys window 2>/dev/null | grep -m1 -E "mCurrentFocus|mFocusedApp" | grep -oE "[a-z][a-z0-9_]*(\.[a-z0-9_]+)+/" | head -1 | tr -d '/')
[ -z "$FG" ] && FG=$(dumpsys activity top 2>/dev/null | grep -m1 "ACTIVITY" | awk '{print $2}')
[ -z "$FG" ] && FG=$(dumpsys activity activities 2>/dev/null | grep -m1 -E "mResumedActivity|topResumedActivity" | grep -oE "[a-z][a-z0-9_]*(\.[a-z0-9_]+)+/" | head -1 | tr -d '/')
out "  前台应用:   ${FG:-未知(可能息屏)}"
out "  CPU 占用TOP3:"
top -n 1 -b 2>/dev/null | grep -E "^ *[0-9]+ " | head -3 | while read -r l; do out "    $l"; done
out ""

# ============ 2. 模块安装与完整性 ============
out "【2】模块安装与完整性"
if [ -d "$MODDIR" ]; then
    out "  模块目录:   存在"
    out "  版本:       $(grep '^version=' "$MODDIR/module.prop" 2>/dev/null | cut -d= -f2)  (versionCode $(grep '^versionCode=' "$MODDIR/module.prop" 2>/dev/null | cut -d= -f2))"
    for f in service.sh config.prop module.prop uninstall.sh; do
        if [ -f "$MODDIR/$f" ]; then
            out "    $f: 存在 ($(wc -c < "$MODDIR/$f" 2>/dev/null) 字节)"
        else
            out "    $f: 缺失 !!"
            add_problem "模块文件缺失: $f (建议重新刷入)"
        fi
    done
    # customize.sh 只在安装时执行, 安装完成后会被管理器删除, 缺失属正常
    [ -f "$MODDIR/customize.sh" ] && out "    customize.sh: 存在(安装脚本)" || out "    customize.sh: 已由管理器移除(正常)"
    out "  service.sh 版本行: $(head -2 "$MODDIR/service.sh" 2>/dev/null | tail -1)"
    if [ -f "$MODDIR/disable" ]; then
        out "  启用状态:   已禁用 (存在 disable 文件) !!"
        add_problem "模块被禁用: 删掉 $MODDIR/disable 后重启"
    else
        out "  启用状态:   已启用"
    fi
else
    out "  模块目录:   不存在 !!"
    add_problem "模块未安装到 /data/adb/modules/y700_thermal_boost"
fi
out "  service.d:  $([ -f /data/adb/service.d/y700_thermal_boost.sh ] && echo 存在 || echo '缺失(开机不会自启)')"
MSU=$(ls /data/adb/modules_update/ 2>/dev/null | tr '\n' ' ')
out "  待更新暂存: ${MSU:-无}"
out "  温控开关:   ENABLE_THERMAL_BYPASS=$CFG_BYPASS"
out "  伪装温度:   CHG=$FAKE_CHG BATT=$FAKE_BATT USB=$FAKE_USB AP=$FAKE_AP (毫摄氏度)"
out ""

# ============ 3. 服务进程与实例 ============
out "【3】服务进程与实例"
SVC=""
for p in /proc/[0-9]*; do
    if grep -qa "y700_thermal_boost/service.sh" "$p/cmdline" 2>/dev/null; then
        SVC="${SVC} ${p##*/}"
    fi
done
if [ -n "$SVC" ]; then
    for pid in $SVC; do
        out "  运行中 pid=$pid 状态=$(awk '{print $3}' /proc/$pid/stat 2>/dev/null) cmd=$(cat /proc/$pid/cmdline 2>/dev/null | tr '\0' ' ')"
    done
    N=$(echo $SVC | wc -w)
    if [ "$N" -gt 1 ]; then
        out "  ⚠ 有 $N 个实例 (单实例保护失效)"
        add_problem "服务多实例运行($N 个) -> 充电日志会互相覆盖; 建议重启"
    fi
else
    out "  未运行 !!"
    add_problem "模块服务未运行 -> 温区禁用/伪装/日志全部不会生效; 重启平板或手动启动"
fi
LOCKP=$(cat /data/local/tmp/y700_thermal_boost.pid 2>/dev/null)
out "  锁文件 pid: ${LOCKP:-无}"
# ps 与 /proc 差异说明(常见的检测陷阱)
PSN=$(ps -A -o NAME 2>/dev/null | grep -c "service.sh")
out "  ps 显示数:  $PSN  (注意: toybox ps 的 NAME 列只有进程名, 不含脚本路径, 故用 /proc 扫描才准)"
out ""

# ============ 4. 温区检查 ============
out "【4】温区检查 (核心)"
ALLTYPES=$(for z in /sys/devices/virtual/thermal/thermal_zone*; do cat "$z/type" 2>/dev/null; done | tr '\n' ' ')
ZONEN=$(echo $ALLTYPES | wc -w)
out "  设备温区总数: $ZONEN"
out "  全部温区类型:"
out "  $ALLTYPES"
out ""
out "  --- 模块目标温区逐项对比 ---"
printf "  %-20s %-9s %-8s %-8s %s\n" "温区" "mode" "temp" "期望" "结论" >> "$REPORT"
printf "  %-20s %-9s %-8s %-8s %s\n" "温区" "mode" "temp" "期望" "结论"
CHECK="fast-chg-therm:$FAKE_CHG:disable top-chg-therm:$FAKE_CHG:disable usb:$FAKE_USB:disable usb1-conn-therm:$FAKE_USB:disable usb2-conn-therm:$FAKE_USB:disable ap-therm:$FAKE_AP:disable lcm-thermal:$FAKE_AP:disable battery:$FAKE_BATT:keep quiet-therm:$FAKE_BATT:keep batt-pack-therm:$FAKE_BATT:keep batt2-pack-therm:$FAKE_BATT:keep batt1-therm:$FAKE_BATT:keep batt2-therm:$FAKE_BATT:keep"
FOUND_N=0; MISS_N=0; BAD_N=0
for item in $CHECK; do
    t=${item%%:*}; rest=${item#*:}; exp=${rest%%:*}; want=${rest##*:}
    z=$(find_zone "$t")
    if [ -z "$z" ]; then
        printf "  %-20s %-9s %-8s %-8s %s\n" "$t" "-" "-" "$exp" "未找到(本机型无此温区)" >> "$REPORT"
        printf "  %-20s %-9s %-8s %-8s %s\n" "$t" "-" "-" "$exp" "未找到(本机型无此温区)"
        MISS_N=$((MISS_N+1)); continue
    fi
    FOUND_N=$((FOUND_N+1))
    m=$(zone_mode "$z"); tp=$(zone_temp "$z")
    if [ "$want" = "disable" ]; then
        if [ "$m" = "disabled" ] && [ "$tp" = "$exp" ]; then r="正常(已禁用+伪装)"
        elif [ "$m" = "disabled" ]; then r="已禁用但温度未伪装"; BAD_N=$((BAD_N+1))
        elif [ "$tp" = "$exp" ]; then r="温度已伪装但mode未禁用"; BAD_N=$((BAD_N+1))
        else r="未生效"; BAD_N=$((BAD_N+1)); fi
    else
        if [ "$tp" = "$exp" ]; then r="正常(已伪装)"
        else r="温度未伪装(temp=$tp)"; BAD_N=$((BAD_N+1)); fi
    fi
    printf "  %-20s %-9s %-8s %-8s %s\n" "$t" "$m" "$tp" "$exp" "$r" >> "$REPORT"
    printf "  %-20s %-9s %-8s %-8s %s\n" "$t" "$m" "$tp" "$exp" "$r"
done
out ""
out "  小结: 命中 $FOUND_N 个, 本机无 $MISS_N 个, 未生效 $BAD_N 个"
[ "$FOUND_N" -eq 0 ] && add_problem "一个目标温区都没匹配到 -> 温区命名不同, 模块需要适配本机型"
[ "$BAD_N" -gt 0 ] && add_problem "有 $BAD_N 个温区未生效(见上表)"
out ""

# ============ 5. 写入与伪装实测 ============
out "【5】写入权限与伪装实测"
if [ "$CFG_BYPASS" = "1" ]; then
    TZ=$(find_zone battery)
    if [ -n "$TZ" ]; then
        chmod 666 "$TZ/emul_temp" 2>/dev/null
        SAVE=$(zone_temp "$TZ")
        echo "$FAKE_BATT" > "$TZ/emul_temp" 2>/dev/null
        sleep 1
        RB=$(zone_temp "$TZ")
        if [ "$RB" = "$FAKE_BATT" ]; then
            out "  emul_temp 写入-回读: 通过 (写入 $FAKE_BATT 后读到 $RB)"
        else
            out "  emul_temp 写入-回读: 失败 (写入 $FAKE_BATT 后读到 $RB) !!"
            add_problem "emul_temp 写入无效 -> 温度伪装不可能生效(SELinux/权限)"
        fi
        # 恢复
        echo "$SAVE" > "$TZ/emul_temp" 2>/dev/null
    fi
    TZD=$(find_zone fast-chg-therm)
    if [ -n "$TZD" ]; then
        echo "$(zone_mode "$TZD")" > "$TZD/mode" 2>/dev/null && out "  mode 可写: 是" || { out "  mode 可写: 否 !!"; add_problem "无法写入温区 mode, 禁用不可能生效"; }
    fi
else
    out "  温控绕过已关闭 (ENABLE_THERMAL_BYPASS=0), 跳过"
fi
# CCL 可写性(必须写不同的值才能证明)
if [ -e "$CCLP" ] && [ -e "$CCLMAXP" ]; then
    CM=$(cat "$CCLMAXP" 2>/dev/null); CC=$(cat "$CCLP" 2>/dev/null)
    out "  CCL 当前: $CC / 上限 $CM"
    if [ -n "$CM" ] && [ "$CM" -gt 0 ] 2>/dev/null; then
        if [ "$CC" = "$CM" ]; then TV=$((CM / 2)); else TV="$CM"; fi
        echo "$TV" > "$CCLP" 2>/dev/null
        sleep 1
        C2=$(cat "$CCLP" 2>/dev/null)
        if [ "$C2" = "$TV" ]; then
            out "  CCL 可写: 是 (写入 $TV 生效 -> 模块解锁能起作用)"
        else
            out "  CCL 可写: 否 (写入 $TV 后读回 $C2 -> 平台自己管控 CCL)"
            if [ -n "$CC" ] && [ -n "$CM" ] && [ "$CC" -lt "$CM" ] 2>/dev/null; then
                out "    且当前 CCL 低于上限 -> 模块无法解锁, 是限流原因之一"
                add_problem "CCL 被平台压在 $CC(上限 $CM) 且模块无法解锁 -> 充电电流上不去"
            else
                out "    但当前 CCL 已等于上限, 不影响本次充电"
            fi
        fi
        [ -n "$CC" ] && echo "$CC" > "$CCLP" 2>/dev/null
        sleep 1
        out "  CCL 已恢复: $(cat "$CCLP" 2>/dev/null)"
    fi
fi
out ""

# ============ 6. 温控进程 ============
out "【6】温控进程 (模块按进程名通用匹配击杀)"
TP=$(ps -A -o PID,NAME 2>/dev/null | grep -i thermal)
if [ -n "$TP" ]; then
    echo "$TP" | while read -r l; do out "  $l"; done
    out "  (存在属正常: 被杀后 init 会重新拉起, 模块每 60 秒再杀一次)"
else
    out "  未发现温控进程 (已被杀掉或本机无)"
fi
out ""

# ============ 7. 充电与电源 ============
out "【7】充电与电源"
DST=$(cat $B/status 2>/dev/null)
DCAP=$(cat $B/capacity 2>/dev/null)
DBV=$(cat $B/voltage_now 2>/dev/null); DBV=${DBV#-}; DBV=${DBV:-0}
DBI=$(cat $B/current_now 2>/dev/null); DBI=${DBI#-}; DBI=${DBI:-0}
DBT=$(cat $B/temp 2>/dev/null); DBT=${DBT:-0}
DUV=$(cat $U/voltage_now 2>/dev/null); DUV=${DUV#-}; DUV=${DUV:-0}
DUI=$(cat $U/current_now 2>/dev/null); DUI=${DUI#-}; DUI=${DUI:-0}
DCCL=$(cat $CCLP 2>/dev/null); DCCL=${DCCL:-0}
DCCLM=$(cat $CCLMAXP 2>/dev/null); DCCLM=${DCCLM:-0}
DILIM=$(cat $U/input_current_limit 2>/dev/null); DILIM=${DILIM:-0}
BPW=$(awk "BEGIN{printf \"%.1f\", $DBV*$DBI/1e12}" 2>/dev/null)
UPW=$(awk "BEGIN{printf \"%.1f\", $DUV*$DUI/1e12}" 2>/dev/null)
DTC=$(awk "BEGIN{printf \"%.1f\", $DBT/10}" 2>/dev/null)
DPR=$(cat $U/real_type 2>/dev/null)

out "  状态:       $DST   电量: ${DCAP}%"
out "  协议:       $DPR"
out "  电池:       $(v3 $DBV)V / $(v2 $DBI)A / ${DTC}C  => ${BPW}W"
out "  输入:       $(v3 $DUV)V / $(v2 $DUI)A  => ${UPW}W"
out "  输入电流上限: $(v2 $DILIM)A"
out "  CCL 充电电流上限: $(v2 $DCCL)A / 上限 $(v2 $DCCLM)A"
out "  充电阶段:   $(cat $B/charge_type 2>/dev/null)"
out ""
out "  --- IIO 输入电流节点 ---"
for f in $(find /sys/devices/platform/soc -maxdepth 8 -name "in_current_*_iin_input" 2>/dev/null); do
    out "  $(basename $f) = $(cat "$f" 2>/dev/null)"
done
out ""
out "  --- 充电限流冷却设备 (state>0 = 正在限流) ---"
BATT_CD_ST=0
for c in /sys/class/thermal/cooling_device*; do
    [ -d "$c" ] || continue
    ty=$(cat "$c/type" 2>/dev/null)
    st=$(cat "$c/cur_state" 2>/dev/null)
    mx=$(cat "$c/max_state" 2>/dev/null)
    [ "$ty" = "battery" ] && BATT_CD_ST=${st:-0}
    case "$ty" in
        battery|cpufreq*|cpu-cluster*|gpu|kgsl|ddr-cdev|ufs)
            if [ -n "$st" ] && [ "$st" != "0" ]; then
                out "  ★ $(basename $c) type=$ty state=$st/$mx  <<< 正在限流"
            else
                out "    $(basename $c) type=$ty state=${st:-?}/${mx:-?}"
            fi ;;
    esac
done
out "  (battery 冷却设备 = 充电电流限流, state 越大限得越狠; 当前 state=$BATT_CD_ST)"
out ""
out "  --- 模块充电日志 ---"
LDIR=/sdcard/充电日志
if [ -d "$LDIR" ]; then
    LN=$(ls -1 "$LDIR"/*.log 2>/dev/null | wc -l)
    LT=$(ls -1t "$LDIR"/*.log 2>/dev/null | head -1)
    out "  目录存在, 共 $LN 个日志"
    out "  最新: $(basename "${LT:-无}")  修改时间 $(stat -c %y "$LT" 2>/dev/null | cut -d. -f1)"
    NOWMIN=$(date '+%Y-%m-%d %H:%M')
    LTMIN=$(stat -c %y "$LT" 2>/dev/null | cut -d: -f1-2)
    out "  当前时间: $NOWMIN"
    [ "$LN" -eq 0 ] && add_problem "充电日志目录为空 -> 模块的日志功能没在写"
else
    out "  目录不存在 !!"
    add_problem "充电日志目录 $LDIR 不存在 -> 日志功能异常"
fi
out ""

# ============ 8. 充电限流分析 ============
out "【8】充电限流分析"
IS_PPS=0
case "$DPR" in *PPS*|PD*) IS_PPS=1 ;; esac

if [ -n "$DBT" ] && [ "$DBT" -gt 400 ] 2>/dev/null; then
    out "  ⚠ 电池真实温度 ${DTC}C 偏高(>40C) -> 很可能触发充电温度保护(JEITA)而限流"
    out "    (模块只伪装 thermal 温区; 电池真实温度节点只读, 无法绕过)"
    add_problem "电池温度 ${DTC}C 偏高, 平台会因此降低充电电流(硬件保护, 模块绕不过)"
fi

CCL_LOW=0
if [ -n "$DCCL" ] && [ -n "$DCCLM" ] && [ "$DCCLM" -gt 0 ] 2>/dev/null; then
    PCT=$((DCCL * 100 / DCCLM))
    if [ "$PCT" -lt 60 ]; then
        CCL_LOW=1
        out "  ⚠ CCL 仅用到 ${PCT}% (${DCCL}/${DCCLM}) -> 电池充电电流被平台压着, 这是功率上不去的主因"
    else
        out "  √ CCL 未受限 (${PCT}%) —— 不是充电电流瓶颈"
    fi
fi

if [ "$IS_PPS" = "1" ]; then
    out "  ※ 协议为 PD/PPS: 本平台不暴露输入电流(实测), 故不做输入侧利用率判断"
else
    if [ -n "$DUI" ] && [ -n "$DILIM" ] && [ "$DILIM" -gt 0 ] 2>/dev/null; then
        IPCT=$((DUI * 100 / DILIM))
        [ "$IPCT" -lt 60 ] && out "  ⚠ 输入电流只用到 ${IPCT}% -> 瓶颈在设备端, 不是充电器不够" || out "  √ 输入电流利用率 ${IPCT}%"
    fi
fi

# 能量守恒校验(判断读数可信度)
if [ "$BPW" != "0.0" ] && [ -n "$UPW" ]; then
    CONS=$(awk "BEGIN{print ($UPW >= $BPW * 0.5) ? 1 : 0}" 2>/dev/null)
    [ "$CONS" = "0" ] && out "  ⚠ 输入功率(${UPW}W) < 电池功率(${BPW}W) -> 输入读数不可信(平台返回垃圾值)"
fi

# 非快充协议的说明(功率低属正常, 不应误判为问题)
case "$DPR" in
    SDP) out "  ※ 协议为 SDP(电脑/数据口): 输入上限仅 0.5A, 功率低是正常的, 不具备快充条件" ;;
    DCP|CDP) out "  ※ 协议为 $DPR (普通充电口, 非 PD/PPS): 功率受限属正常" ;;
esac

# 功率偏低综合判断 (仅当处于 PD/PPS 快充协议时才有意义)
if [ "$DST" = "Charging" ] && [ "$IS_PPS" = "1" ] && [ "$CCL_LOW" = "0" ] && [ "$DBT" -le 400 ] 2>/dev/null && [ "$BATT_CD_ST" = "0" ]; then
    LOW=$(awk "BEGIN{print ($BPW < 20) ? 1 : 0}" 2>/dev/null)
    if [ "$LOW" = "1" ]; then
        out "  ⚠ 电池功率仅 ${BPW}W (PD/PPS 下偏低), 但 CCL 满值 / 温度正常 / 无温控限流"
        out "    => 瓶颈不在模块(模块该做的都做到了)。可能原因:"
        out "       1) 充电器或线材不给力 (非原装 / 非 C-to-C / 老化)"
        out "       2) 充电器与设备协商出的 PPS 档位偏低"
        out "       3) 平台自身充电策略 (与本模块无关)"
        out "    建议: 换原装充电器 + 原装 C-to-C 线复测; 并做 A/B 对比"
        out "          (config.prop 里 ENABLE_THERMAL_BYPASS=0 重启)"
        add_problem "PD/PPS 下电池功率偏低(${BPW}W) 但模块各点正常 -> 瓶颈在充电器/线材或平台策略, 非本模块"
    fi
fi
out ""

# ============ 9. 动态监控 ============
out "【9】动态监控 (每 5 秒, 共 ${DURATION} 秒)"
out "  时间     状态       协议    电量  电池功率  电池温度  iin(pmih)  usb_i  限流  伪装维持"
SAMPLES=$((DURATION / 5)); [ "$SAMPLES" -lt 1 ] && SAMPLES=1
I1N=$(find /sys/devices/platform/soc -maxdepth 8 -name "in_current_pmih010x_iin_input" 2>/dev/null | head -1)
i=0; FAKE_OK=0; FAKE_BAD=0; THR_N=0; PMIN=999; PMAX=0; TMAX=0
while [ $i -lt $SAMPLES ]; do
    T=$(date '+%H:%M:%S')
    ST=$(cat $B/status 2>/dev/null)
    PR=$(cat $U/real_type 2>/dev/null)
    CP=$(cat $B/capacity 2>/dev/null)
    BV=$(cat $B/voltage_now 2>/dev/null); BV=${BV#-}; BV=${BV:-0}
    BI=$(cat $B/current_now 2>/dev/null); BI=${BI#-}; BI=${BI:-0}
    BT=$(cat $B/temp 2>/dev/null); BT=${BT:-0}
    PW=$(awk "BEGIN{printf \"%.1f\", $BV*$BI/1e12}" 2>/dev/null)
    TC=$(awk "BEGIN{printf \"%.1f\", $BT/10}" 2>/dev/null)
    I1=""; [ -n "$I1N" ] && I1=$(cat "$I1N" 2>/dev/null)
    UI=$(cat $U/current_now 2>/dev/null)
    LT=0
    for c in /sys/class/thermal/cooling_device*; do
        [ "$(cat $c/type 2>/dev/null)" = "battery" ] && { LT=$(cat $c/cur_state 2>/dev/null); break; }
    done
    LT=${LT:-0}
    [ "$LT" != "0" ] && THR_N=$((THR_N+1))
    awk "BEGIN{exit !($PW < $PMIN)}" 2>/dev/null && PMIN=$PW
    awk "BEGIN{exit !($PW > $PMAX)}" 2>/dev/null && PMAX=$PW
    awk "BEGIN{exit !($BT > $TMAX)}" 2>/dev/null && TMAX=$BT
    FZ=$(find_zone fast-chg-therm); OK="?"
    if [ -n "$FZ" ]; then
        if [ "$(zone_temp "$FZ")" = "$FAKE_CHG" ]; then OK="是"; FAKE_OK=$((FAKE_OK+1)); else OK="否($(zone_temp "$FZ"))"; FAKE_BAD=$((FAKE_BAD+1)); fi
    fi
    out "  $T  $ST  $PR  ${CP}%  ${PW}W  ${TC}C  ${I1:-空}  ${UI:-空}  $LT  $OK"
    i=$((i+1))
    [ $i -lt $SAMPLES ] && sleep 5
done
out ""
out "  功率范围: ${PMIN}W ~ ${PMAX}W"
out "  最高电池温度: $(awk "BEGIN{printf \"%.1f\", $TMAX/10}")C"
out "  伪装维持: 正常 $FAKE_OK 次 / 失效 $FAKE_BAD 次"
[ "$FAKE_BAD" -gt 0 ] && add_problem "监控中有 $FAKE_BAD 次温度伪装失效 -> 伪装不稳定(抓'有时有效有时无效')"
[ "$THR_N" -gt 0 ] && add_problem "监控中有 $THR_N 次 battery 冷却设备在限流(state>0)"
out ""

# ============ 10. 结论 ============
out "============================================================"
out "【10】监控结论"
out "============================================================"
if [ -z "$PROBLEMS" ]; then
    out "  ✅ 未发现明显问题, 模块各作用点正常。"
    out ""
    out "  若仍感觉'没效果', 请确认:"
    out "   1) 是否使用原装 / 支持 PD-PPS 的快充充电器 (SDP/DCP 无法高功率)"
    out "   2) 电池真实温度是否过高(>40C)触发充电IC硬件限流(模块无法绕过)"
    out "   3) 充电器与线材是否原装 (非 C-to-C 线无法走高功率 PPS)"
else
    out "  ❌ 发现以下问题:"
    echo "$PROBLEMS" | while read -r l; do [ -n "$l" ] && out "   - $l"; done
fi
out ""
out "============================================================"
out "  报告已保存: $REPORT"
out "  把此文件发出来即可定位问题 (不含隐私信息)"
out "============================================================"

chmod 644 "$REPORT" 2>/dev/null
echo ""
echo ">>> 报告文件: $REPORT"
