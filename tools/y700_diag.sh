#!/system/bin/sh
# ============================================================
#  Y700 温控模块 诊断脚本
#  用途: 一键检测模块各作用点是否生效, 生成报告便于定位问题
#  用法: 终端中执行  su -c "sh y700_diag.sh"
#        可选参数: 采样时长秒数 (默认 60)
#  输出: /sdcard/Y700模块诊断_<时间>.txt
# ============================================================

MODDIR=/data/adb/modules/y700_thermal_boost
DURATION=${1:-60}
TS=$(date '+%Y%m%d_%H%M%S')
REPORT="/sdcard/Y700模块诊断_${TS}.txt"
WORK=/data/local/tmp/y700_diag
mkdir -p "$WORK" 2>/dev/null

out() { echo "$1" >> "$REPORT"; echo "$1"; }

# ---------- 结论收集 ----------
PROBLEMS=""
add_problem() { PROBLEMS="${PROBLEMS}$1
"; }

# ---------- 工具 ----------
find_zone() {
    for z in /sys/devices/virtual/thermal/thermal_zone*; do
        [ "$(cat "$z/type" 2>/dev/null)" = "$1" ] && { echo "$z"; return 0; }
    done
    return 1
}
zone_mode() { cat "$1/mode" 2>/dev/null; }
zone_temp() { cat "$1/temp" 2>/dev/null; }

# 读取配置
CFG_BYPASS=1; CFG_LOG=1; FAKE_CHG=25000; FAKE_BATT=28000; FAKE_USB=25000; FAKE_AP=30000
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

# ============================================================
out "============================================================"
out "        Y700 温控模块 诊断报告"
out "============================================================"
out "生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
out "采样时长: ${DURATION} 秒"
out ""

# ---------- 1. 环境 ----------
out "【1】环境信息"
MODEL=$(getprop ro.product.model 2>/dev/null)
out "  设备型号:   $MODEL"
out "  Android:    $(getprop ro.build.version.release 2>/dev/null) (SDK $(getprop ro.build.version.sdk 2>/dev/null))"
out "  内核:       $(uname -r 2>/dev/null)"
out "  Root:       $(id -u 2>/dev/null | grep -q '^0$' && echo '已获取(uid=0)' || echo '未获取(请用 su 执行本脚本)')"
out "  SELinux:    $(getenforce 2>/dev/null)"
out "  当前上下文: $(cat /proc/self/attr/current 2>/dev/null)"
case "$MODEL" in
    TB323FU*) GEN="五代 (TB323FU)" ;;
    TB322FC*) GEN="四代 (TB322FC)" ;;
    TB320FU*|TB321FU*) GEN="三代 ($MODEL)" ;;
    *) GEN="未知机型 ($MODEL)" ;;
esac
out "  机型识别:   $GEN"
out ""

# ---------- 2. 模块安装状态 ----------
out "【2】模块安装状态"
if [ -d "$MODDIR" ]; then
    out "  模块目录:   存在"
    out "  版本:       $(grep '^version=' "$MODDIR/module.prop" 2>/dev/null | cut -d= -f2)"
    out "  service.sh: $([ -f "$MODDIR/service.sh" ] && echo 存在 || echo '缺失!')"
    out "  config.prop:$([ -f "$MODDIR/config.prop" ] && echo 存在 || echo '缺失(用默认值)')"
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
out "  温控开关:   ENABLE_THERMAL_BYPASS=$CFG_BYPASS"
out "  伪装温度:   CHG=$FAKE_CHG BATT=$FAKE_BATT USB=$FAKE_USB AP=$FAKE_AP (毫摄氏度)"
out ""

# ---------- 3. 服务进程 ----------
out "【3】模块服务进程"
SVC=""
for p in /proc/[0-9]*; do
    if grep -qa "y700_thermal_boost/service.sh" "$p/cmdline" 2>/dev/null; then
        SVC="${SVC} ${p##*/}"
    fi
done
if [ -n "$SVC" ]; then
    for pid in $SVC; do
        out "  运行中 pid=$pid  状态=$(awk '{print $3}' /proc/$pid/stat 2>/dev/null)"
    done
    N=$(echo $SVC | wc -w)
    [ "$N" -gt 1 ] && { out "  警告: 有 $N 个实例 (单实例锁失效)"; add_problem "服务多实例运行($N 个), 建议重启"; }
else
    out "  未运行 !!"
    add_problem "模块服务未运行 -> 温区禁用/伪装/日志全部不会生效; 重启平板或手动启动"
fi
LOCKP=$(cat /data/local/tmp/y700_thermal_boost.pid 2>/dev/null)
out "  锁文件 pid: ${LOCKP:-无}"
out ""

# ---------- 4. 温区检查 ----------
out "【4】温区检查 (核心)"
out "  --- 设备上实际存在的全部温区 ---"
ALLTYPES=$(for z in /sys/devices/virtual/thermal/thermal_zone*; do cat "$z/type" 2>/dev/null; done | tr '\n' ' ')
out "  $ALLTYPES"
out ""
out "  --- 模块目标温区 ---"
printf "  %-20s %-6s %-8s %-8s %s\n" "温区" "mode" "temp" "期望" "结论" >> "$REPORT"
printf "  %-20s %-6s %-8s %-8s %s\n" "温区" "mode" "temp" "期望" "结论"
CHECK="fast-chg-therm:$FAKE_CHG:disable top-chg-therm:$FAKE_CHG:disable usb:$FAKE_USB:disable usb1-conn-therm:$FAKE_USB:disable usb2-conn-therm:$FAKE_USB:disable ap-therm:$FAKE_AP:disable lcm-thermal:$FAKE_AP:disable battery:$FAKE_BATT:keep quiet-therm:$FAKE_BATT:keep batt-pack-therm:$FAKE_BATT:keep batt2-pack-therm:$FAKE_BATT:keep batt1-therm:$FAKE_BATT:keep batt2-therm:$FAKE_BATT:keep"
FOUND_N=0; MISS_N=0; BAD_N=0
for item in $CHECK; do
    t=${item%%:*}; rest=${item#*:}; exp=${rest%%:*}; want=${rest##*:}
    z=$(find_zone "$t")
    if [ -z "$z" ]; then
        printf "  %-20s %-6s %-8s %-8s %s\n" "$t" "-" "-" "$exp" "未找到(本机型无此温区)" >> "$REPORT"
        printf "  %-20s %-6s %-8s %-8s %s\n" "$t" "-" "-" "$exp" "未找到(本机型无此温区)"
        MISS_N=$((MISS_N+1))
        continue
    fi
    FOUND_N=$((FOUND_N+1))
    m=$(zone_mode "$z"); tp=$(zone_temp "$z")
    if [ "$want" = "disable" ]; then
        if [ "$m" = "disabled" ] && [ "$tp" = "$exp" ]; then r="正常(已禁用+伪装)"
        elif [ "$m" = "disabled" ]; then r="已禁用但温度未伪装"
        elif [ "$tp" = "$exp" ]; then r="温度已伪装但mode未禁用"
        else r="未生效"; BAD_N=$((BAD_N+1)); fi
    else
        if [ "$tp" = "$exp" ]; then r="正常(已伪装)"
        else r="温度未伪装(temp=$tp)"; fi
    fi
    printf "  %-20s %-6s %-8s %-8s %s\n" "$t" "$m" "$tp" "$exp" "$r" >> "$REPORT"
    printf "  %-20s %-6s %-8s %-8s %s\n" "$t" "$m" "$tp" "$exp" "$r"
done
out ""
out "  小结: 命中 $FOUND_N 个, 本机无 $MISS_N 个, 未生效 $BAD_N 个"
[ "$FOUND_N" -eq 0 ] && add_problem "一个目标温区都没匹配到 -> 温区命名不同, 模块需要适配本机型"
[ "$BAD_N" -gt 0 ] && add_problem "有 $BAD_N 个温区未生效(见上表)"
out ""

# ---------- 5. 写入能力测试 ----------
out "【5】写入权限测试"
if [ "$CFG_BYPASS" = "1" ]; then
    TZ=$(find_zone battery)
    if [ -n "$TZ" ]; then
        chmod 666 "$TZ/emul_temp" 2>/dev/null
        CUR=$(zone_temp "$TZ")
        echo "$CUR" > "$TZ/emul_temp" 2>/dev/null
        RC=$?
        if [ $RC -eq 0 ]; then out "  emul_temp 可写: 是"; else out "  emul_temp 可写: 否 !! (SELinux/权限)"; add_problem "无法写入 emul_temp, 温度伪装不可能生效"; fi
    fi
    TZD=$(find_zone fast-chg-therm)
    if [ -n "$TZD" ]; then
        echo "$(zone_mode "$TZD")" > "$TZD/mode" 2>/dev/null && out "  mode 可写: 是" || { out "  mode 可写: 否 !!"; add_problem "无法写入温区 mode, 禁用不可能生效"; }
    fi
else
    out "  温控绕过已关闭, 跳过"
fi
out ""

# ---------- 6. 温控进程 ----------
out "【6】温控进程"
TP=$(ps -A 2>/dev/null | grep -E "thermal-engine|thermal-service" | grep -v grep)
if [ -n "$TP" ]; then
    echo "$TP" | while read -r l; do out "  $l"; done
else
    out "  未发现温控进程 (已被模块杀掉或本机无)"
fi
out ""

# ---------- 7. 充电与输入电流节点 ----------
out "【7】充电状态与输入电流节点"
B=/sys/class/power_supply/battery
U=/sys/class/power_supply/usb
out "  状态:       $(cat $B/status 2>/dev/null)   电量: $(cat $B/capacity 2>/dev/null)%"
out "  电池:       $(cat $B/voltage_now 2>/dev/null) uV / $(cat $B/current_now 2>/dev/null) uA / $(cat $B/temp 2>/dev/null) (0.1C)"
out "  协议:       $(cat $U/real_type 2>/dev/null)"
out "  输入电压:   $(cat $U/voltage_now 2>/dev/null) uV"
out "  输入电流:   $(cat $U/current_now 2>/dev/null) uA (PPS 下可能恒为 0)"
out "  充电阶段:   $(cat $B/charge_type 2>/dev/null)"
out "  CCL:        $(cat $B/charge_control_limit 2>/dev/null)/$(cat $B/charge_control_limit_max 2>/dev/null)"
echo "  --- IIO 输入电流节点 ---" >> "$REPORT"; echo "  --- IIO 输入电流节点 ---"
for f in $(find /sys/devices/platform/soc -maxdepth 8 -name "in_current_*_iin_input" 2>/dev/null); do
    out "  $(basename $f) = $(cat "$f" 2>/dev/null)"
done
for f in $(find /sys/devices/platform/soc -maxdepth 8 -name "in_current_*_ichg_input" 2>/dev/null); do
    out "  $(basename $f) = $(cat "$f" 2>/dev/null)"
done
out ""

# ---------- 8. 动态采样 ----------
out "【8】动态采样 (每 5 秒, 共 ${DURATION} 秒)"
out "  时间     状态       协议    电量  电池功率  iin(pmih)  iin(smb1)  iin(smb2)  usb_i  伪装维持"
SAMPLES=$((DURATION / 5))
[ "$SAMPLES" -lt 1 ] && SAMPLES=1
# 先解析节点路径(避免循环里反复 find)
I1N=$(find /sys/devices/platform/soc -maxdepth 8 -name "in_current_pmih010x_iin_input" 2>/dev/null | head -1)
I2N=$(find /sys/devices/platform/soc -maxdepth 8 -name "in_current_smb1501_1_iin_input" 2>/dev/null | head -1)
I3N=$(find /sys/devices/platform/soc -maxdepth 8 -name "in_current_smb1501_2_iin_input" 2>/dev/null | head -1)
i=0
FAKE_OK_N=0; FAKE_BAD_N=0
PPS_IIN_OK=0
while [ $i -lt $SAMPLES ]; do
    T=$(date '+%H:%M:%S')
    ST=$(cat $B/status 2>/dev/null)
    PR=$(cat $U/real_type 2>/dev/null)
    CP=$(cat $B/capacity 2>/dev/null)
    BV=$(cat $B/voltage_now 2>/dev/null); BI=$(cat $B/current_now 2>/dev/null); BI=${BI#-}
    PW=$(awk "BEGIN{printf \"%.1f\", $BV*$BI/1e12}" 2>/dev/null)
    # 三种输入电流来源
    I1=""; I2=""; I3=""
    [ -n "$I1N" ] && I1=$(cat "$I1N" 2>/dev/null)
    [ -n "$I2N" ] && I2=$(cat "$I2N" 2>/dev/null)
    [ -n "$I3N" ] && I3=$(cat "$I3N" 2>/dev/null)
    UI=$(cat $U/current_now 2>/dev/null)
    [ -n "$I2" ] && [ "$I2" != "0" ] && PPS_IIN_OK=$((PPS_IIN_OK+1))
    [ -n "$I3" ] && [ "$I3" != "0" ] && PPS_IIN_OK=$((PPS_IIN_OK+1))
    # 伪装是否维持: 检查 fast-chg-therm 与 battery
    FZ=$(find_zone fast-chg-therm); OK="?"
    if [ -n "$FZ" ]; then
        if [ "$(zone_temp "$FZ")" = "$FAKE_CHG" ]; then OK="是"; FAKE_OK_N=$((FAKE_OK_N+1)); else OK="否($(zone_temp "$FZ"))"; FAKE_BAD_N=$((FAKE_BAD_N+1)); fi
    fi
    out "  $T  $ST  $PR  $CP%  ${PW}W  ${I1:-空}  ${I2:-空}  ${I3:-空}  ${UI:-空}  $OK"
    i=$((i+1))
    [ $i -lt $SAMPLES ] && sleep 5
done
out ""
out "  伪装维持统计: 正常 $FAKE_OK_N 次 / 失效 $FAKE_BAD_N 次"
[ "$FAKE_BAD_N" -gt 0 ] && add_problem "采样中有 $FAKE_BAD_N 次温度伪装失效 -> 伪装不稳定"
out "  电荷泵输入电流节点(smb1501)有值次数: $PPS_IIN_OK"
out ""

# ---------- 9. 结论 ----------
out "============================================================"
out "【9】诊断结论"
out "============================================================"
if [ -z "$PROBLEMS" ]; then
    out "  未发现明显问题, 模块各作用点正常。"
    out "  若仍感觉'没效果', 请确认:"
    out "   1) 是否使用原装/支持 PD-PPS 的快充充电器 (SDP/DCP 无法高功率)"
    out "   2) 电池真实温度是否过高(>40C)触发充电IC硬件限流(模块无法绕过)"
else
    out "  发现以下问题:"
    echo "$PROBLEMS" | while read -r l; do [ -n "$l" ] && out "   - $l"; done
fi
out ""
out "============================================================"
out "  报告已保存: $REPORT"
out "============================================================"

chmod 644 "$REPORT" 2>/dev/null
echo ""
echo ">>> 报告文件: $REPORT"
