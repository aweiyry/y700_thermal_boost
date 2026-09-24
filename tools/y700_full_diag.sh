#!/system/bin/sh
# ============================================================
#  Y700 温控模块 —— 深度定位测试 (配合模块 V7.1)
#
#  用途: 定位「模块明明全部生效, 充电却只有 ~10W」到底卡在哪一环
#
#  用法(平板终端, 需 root):
#     su -c "sh y700_full_diag.sh"          完整版(含自动 A/B, 约 4 分钟)
#     su -c "sh y700_full_diag.sh --no-ab"  只抓快照, 不做 A/B(约 40 秒)
#
#  前提:
#     1) 用原装(或确认支持 PD/PPS 的)充电器 + 原装 C-to-C 线, 插紧
#     2) 测试期间不要拔线、不要玩游戏; 屏幕状态会记录在报告里
#     3) A/B 需要模块 V7.1+(配置热重载); V7.0 及更早只能看快照部分
#
#  输出: /sdcard/Y700深度定位_<时间>.txt   (把这个文件发出来即可)
#
#  说明: A/B 会临时改写 config.prop 并在结束时自动还原(备份为 config.prop.diagbak)
# ============================================================

MODDIR=/data/adb/modules/y700_thermal_boost
CFG="$MODDIR/config.prop"
CFGBAK="$MODDIR/config.prop.diagbak"
RTL=/data/local/tmp/y700_thermal_boost/runtime.log
ABDIR=/data/local/tmp
TS=$(date '+%Y%m%d_%H%M%S')
REPORT="/sdcard/Y700深度定位_${TS}.txt"

B=/sys/class/power_supply/battery
U=/sys/class/power_supply/usb
CCLP="$B/charge_control_limit"
CCLMAXP="$B/charge_control_limit_max"

NOAB=0
[ "$1" = "--no-ab" ] && NOAB=1

PROBLEMS=""
out() { echo "$1" >> "$REPORT"; echo "$1"; }
add_problem() { PROBLEMS="${PROBLEMS}   - $1
"; }

v2() { awk "BEGIN{printf \"%.2f\", $1/1000000}" 2>/dev/null; }
v3() { awk "BEGIN{printf \"%.3f\", $1/1000000}" 2>/dev/null; }
pow() { awk "BEGIN{printf \"%.2f\", ($1*$2)/1000000000000}" 2>/dev/null; }

find_zone() {
    for z in /sys/devices/virtual/thermal/thermal_zone*; do
        [ "$(cat "$z/type" 2>/dev/null)" = "$1" ] && { echo "$z"; return 0; }
    done
}
ztemp() { cat "$1/temp" 2>/dev/null; }
zmode() { cat "$1/mode" 2>/dev/null; }

setcfg() {
    if grep -q "^$1=" "$CFG" 2>/dev/null; then
        sed -i "s/^$1=.*/$1=$2/" "$CFG" 2>/dev/null
    else
        # 旧配置(V7.0 及之前)可能没有这个键, 直接追加
        echo "$1=$2" >> "$CFG" 2>/dev/null
    fi
}
getcfg() { grep -m1 "^$1=" "$CFG" 2>/dev/null | sed "s/^$1=//"; }

restore_cfg() {
    if [ -f "$CFGBAK" ]; then
        cp -f "$CFGBAK" "$CFG" 2>/dev/null
        rm -f "$CFGBAK" 2>/dev/null
        echo "  (配置已还原)" >> "$REPORT"
    fi
}
trap 'restore_cfg; exit 0' INT TERM HUP

: > "$REPORT"

out "============================================================"
out "     Y700 温控模块 深度定位报告"
out "============================================================"
out "生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
out "模式:     $([ $NOAB = 1 ] && echo '快照(不做A/B)' || echo '完整(含自动A/B)')"
out ""

# ============ 1. 环境 ============
out "【1】环境"
MODEL=$(getprop ro.product.model 2>/dev/null)
case "$MODEL" in
    TB323FU*) GEN="五代" ;;
    TB322FC*) GEN="四代" ;;
    TB320FU*|TB321FU*) GEN="三代" ;;
    *) GEN="未知" ;;
esac
out "  机型:       $MODEL ($GEN)"
out "  Android:    $(getprop ro.build.version.release 2>/dev/null) (SDK $(getprop ro.build.version.sdk 2>/dev/null))"
out "  ZUI/系统:   $(getprop ro.build.display.id 2>/dev/null)"
out "  内核:       $(uname -r 2>/dev/null)"
out "  开机时长:   $(awk '{printf "%d 分钟", $1/60}' /proc/uptime 2>/dev/null)"
out "  Root:       $(id -u 2>/dev/null) / SELinux $(getenforce 2>/dev/null)"
out "  负载:       $(cat /proc/loadavg 2>/dev/null)"
SCR=$(dumpsys power 2>/dev/null | grep -m1 -E "mWakefulness=" | sed 's/.*mWakefulness=//' | awk '{print $1}')
case "$SCR" in Awake) SCR="亮屏";; Asleep) SCR="息屏";; Dozing) SCR="休眠";; *) SCR="${SCR:-未知}";; esac
out "  屏幕状态:   $SCR"
out ""

# ============ 2. 模块状态 ============
out "【2】模块状态"
if [ -d "$MODDIR" ]; then
    out "  版本:       $(grep -m1 '^version=' "$MODDIR/module.prop" 2>/dev/null | cut -d= -f2) (versionCode $(grep -m1 '^versionCode=' "$MODDIR/module.prop" 2>/dev/null | cut -d= -f2))"
    HAVERELOAD=0
    grep -q "reload_config" "$MODDIR/service.sh" 2>/dev/null && HAVERELOAD=1
    out "  热重载支持: $([ $HAVERELOAD = 1 ] && echo '支持(V7.1+, 改配置无需重启)' || echo '不支持(仅 V7.0 及更早, A/B 需手动重启)')"
    out "  配置:"
    grep -vE '^\s*$' "$CFG" 2>/dev/null | while read -r l; do out "    $l"; done
else
    out "  模块目录不存在 !!"
    add_problem "模块未安装"
    HAVERELOAD=0
fi
N=0
for p in /proc/[0-9]*; do
    grep -qa "y700_thermal_boost/service.sh" "$p/cmdline" 2>/dev/null && { N=$((N+1)); MPID=${p##*/}; }
done
out "  实例:       $N 个 (pid ${MPID:-无})"
[ "$N" -eq 0 ] && add_problem "模块进程未运行"
[ "$N" -gt 1 ] && add_problem "模块有 $N 个实例(异常, 日志会互相覆盖)"
out ""

# ============ 3. 充电链路全节点 (核心) ============
out "【3】充电链路全节点 (power_supply 全量 dump)"
out "  说明: 这一节是定位关键 —— 平台把真实协商结果(PDO/电流上限/充电阶段/JEITA)"
out "        都放在这些节点里, 模块日志看不到的答案往往在这里。"
for ps in /sys/class/power_supply/*; do
    [ -d "$ps" ] || continue
    PN=$(basename "$ps")
    out ""
    out "  ────── $PN ──────"
    # uevent 是平台规范输出, 最完整
    if [ -r "$ps/uevent" ]; then
        while IFS= read -r ev; do
            [ -n "$ev" ] && out "    $ev"
        done < "$ps/uevent"
    fi
    # 其余属性里挑出「有值且 uevent 没覆盖」的
    for f in "$ps"/*; do
        [ -f "$f" ] || continue
        fn=$(basename "$f")
        case "$fn" in uevent|uevent_*) continue ;; esac
        case "$fn" in
            voltage_now|current_now|voltage_max|current_max|input_current_limit|charge_control_limit|charge_control_limit_max|temp|capacity|status|type|online|present|real_type|usb_type|charge_type|health|constant_charge_current|constant_charge_current_max|charge_counter|charge_full|input_current_limited|step_charging_enabled|sw_jeita_enabled|jeita_*|pd_active|pd_voltage_min|pd_voltage_max|pd_current_max|typec_*|sdp_current_max|dcp_current_max|usb_suspend|system_temp_level|batt_profile|charge_done|charge_term_current|recharge_soc|soc_reporting_ready|cycle_count)
                v=$(cat "$f" 2>/dev/null)
                [ -n "$v" ] && out "    $(printf '%-28s' "$fn") = $v"
                ;;
        esac
    done
done
out ""

# 输入电流上限 vs 实际功率 的物理矛盾检查
DILIM=$(cat $U/input_current_limit 2>/dev/null)
DUV=$(cat $U/voltage_now 2>/dev/null); DUV=${DUV#-}; DUV=${DUV:-0}
DBV=$(cat $B/voltage_now 2>/dev/null); DBV=${DBV#-}; DBV=${DBV:-0}
DBI=$(cat $B/current_now 2>/dev/null); DBI=${DBI#-}; DBI=${DBI:-0}
BPW=$(pow "$DBV" "$DBI")
out "  ────── 关键矛盾检查 ──────"
out "  电池: ${BPW}W ($(v3 $DBV)V / $(v2 $DBI)A)"
if [ -n "$DILIM" ] && [ "$DILIM" != "0" ]; then
    ILW=$(awk "BEGIN{printf \"%.2f\", $DILIM*$DUV/1000000}" 2>/dev/null)
    out "  usb/input_current_limit = $(v2 $DILIM)A -> 上限功率仅 ${ILW}W"
    NEED=$(awk "BEGIN{print ($ILW>0 && $BPW>0 && $BPW>($ILW*1.3)) ? 1 : 0}" 2>/dev/null)
    if [ "$NEED" = "1" ]; then
        out "  ⚠ 电池实得 ${BPW}W 远高于该上限推算的 ${ILW}W"
        out "    => 这个节点不是 PPS 通路上的真实限制(电荷泵走的是另一条路), 不能作为限流依据"
    fi
fi
out ""

# ============ 4. 平台决策证据 ============
out "【4】平台决策证据 (谁在决定充电电流)"
out "  --- 4.1 内核充电日志 (dmesg, 关键字: pps/pd/jeita/aicl/cp/smb/thermal) ---"
DK=$(dmesg 2>/dev/null | grep -iE "charg|pps|pd_|jeita|aicl|cp_|smb|step_chg|thermal|batt" | tail -60)
if [ -n "$DK" ]; then
    echo "$DK" | while IFS= read -r l; do out "    $l"; done
    PPSL=$(echo "$DK" | grep -icE "pps")
    out "    (含 pps 的行数: $PPSL)"
else
    out "    (读不到 dmesg 或没有相关行)"
fi
out ""
out "  --- 4.2 系统热管理服务状态 (dumpsys thermalservice) ---"
TSV=$(dumpsys thermalservice 2>/dev/null | grep -iE "Thermal Status|Cooling Device|Temperature\{|mStatus|isThrottling|Current thermal" | head -30)
if [ -n "$TSV" ]; then
    echo "$TSV" | while IFS= read -r l; do out "    $l"; done
else
    out "    (无输出)"
fi
out ""
out "  --- 4.3 Android 电池状态 (dumpsys battery) ---"
dumpsys battery 2>/dev/null | grep -iE "level|status|health|present|AC powered|USB powered|temperature|voltage|charge" | while IFS= read -r l; do out "    $l"; done
out ""
out "  --- 4.4 系统里与充电相关的设置项 ---"
SG=$(settings list global 2>/dev/null | grep -iE "charg|batt" ; settings list secure 2>/dev/null | grep -iE "charg|batt" ; settings list system 2>/dev/null | grep -iE "charg|batt")
if [ -n "$SG" ]; then
    echo "$SG" | while IFS= read -r l; do out "    $l"; done
else
    out "    (无相关设置项)"
fi
out ""

# ============ 5. 温区与热源全景 ============
out "【5】温区与热源全景 (找出模块没覆盖、却可能参与限流的热源)"
FAKE_CHG=$(getcfg FAKE_TEMP_CHG); FAKE_BATT=$(getcfg FAKE_TEMP_BATT)
FAKE_USB=$(getcfg FAKE_TEMP_USB); FAKE_AP=$(getcfg FAKE_TEMP_AP)
out "  伪装目标值: CHG=${FAKE_CHG:-?} BATT=${FAKE_BATT:-?} USB=${FAKE_USB:-?} AP=${FAKE_AP:-?} (毫摄氏度)"
out ""
out "  温区名称              mode      temp     是否被模块伪装"
for z in /sys/devices/virtual/thermal/thermal_zone*; do
    t=$(cat "$z/type" 2>/dev/null)
    [ -n "$t" ] || continue
    tp=$(ztemp "$z"); m=$(zmode "$z")
    FU="否"
    case "$t" in
        fast-chg-therm|top-chg-therm) [ "$tp" = "$FAKE_CHG" ] && FU="✅已伪装(充电区)" ;;
        usb|usb1-conn-therm|usb2-conn-therm) [ "$tp" = "$FAKE_USB" ] && FU="✅已伪装(USB区)" ;;
        ap-therm|lcm-thermal) [ "$tp" = "$FAKE_AP" ] && FU="✅已伪装(AP区)" ;;
        battery|quiet-therm|batt-pack-therm|batt2-pack-therm|batt1-therm|batt2-therm)
            [ "$tp" = "$FAKE_BATT" ] && FU="✅已伪装(电池区)" ;;
    esac
    printf "  %-20s %-9s %-9s %s\n" "$t" "${m:-?}" "${tp:-?}" "$FU" >> "$REPORT"
    printf "  %-20s %-9s %-9s %s\n" "$t" "${m:-?}" "${tp:-?}" "$FU"
done
out ""
out "  高温热源 TOP8 (未被伪装的真实热源可能就是限流依据):"
for z in /sys/devices/virtual/thermal/thermal_zone*; do
    t=$(cat "$z/type" 2>/dev/null); tp=$(ztemp "$z")
    [ -n "$t" ] && [ -n "$tp" ] && echo "$tp $t"
done | sort -rn | head -8 | while read -r tv tn; do
    out "    $(awk "BEGIN{printf \"%.1f\", $tv/1000}" 2>/dev/null)C  $tn"
done
out ""

# ============ 6. 历史充电峰值 ============
out "【6】历史充电峰值 (判断这台机器到底有没有快充过)"
LDIR=/sdcard/充电日志
if [ -d "$LDIR" ]; then
    LN=$(ls -1 "$LDIR"/*.log 2>/dev/null | wc -l)
    out "  日志数量: $LN"
    out "    开始电量  峰值功率  协议      充电时长"
    HPK=0
    for f in $(ls -1t "$LDIR"/*.log 2>/dev/null | head -10); do
        h_cap=$(grep -m1 "开始电量:" "$f" 2>/dev/null | sed 's/.*: *//')
        h_pk=$(grep -m1 "电池峰值功率:" "$f" 2>/dev/null | sed 's/.*: *//')
        h_pr=$(grep -m1 "充电协议:" "$f" 2>/dev/null | sed 's/.*: *//')
        h_du=$(grep -m1 -E "充电时长:" "$f" 2>/dev/null | sed 's/.*: *//')
        [ -z "$h_pk" ] && continue
        printf "    %-9s %-8s %-9s %s\n" "${h_cap:-?}" "$h_pk" "${h_pr:-?}" "${h_du:-进行中}" >> "$REPORT"
        printf "    %-9s %-8s %-9s %s\n" "${h_cap:-?}" "$h_pk" "${h_pr:-?}" "${h_du:-进行中}"
        h_pkn=$(echo "$h_pk" | sed 's/W//')
        HPK=$(awk "BEGIN{print ($h_pkn>$HPK)?$h_pkn:$HPK}" 2>/dev/null)
    done
    out "  历史最高峰值: ${HPK}W"
    if awk "BEGIN{exit !($HPK < 20)}" 2>/dev/null; then
        out "  => 从未超过 20W: 这台机器在本模块下没跑出过快充, 重点查充电器/线材/平台策略"
        add_problem "历史所有充电峰值 <20W -> 从未快充过, 需排查充电器/线材/平台策略"
    else
        out "  => 有 20W+ 记录: 机器本身能快充; 当前功率低多半是电量/温度/充电器档位造成"
    fi
    # 最新一次完整日志的分阶段数据
    NEWLOG=""
    for f in $(ls -1t "$LDIR"/*.log 2>/dev/null | head -6); do
        grep -q "分阶段详情" "$f" 2>/dev/null && { NEWLOG="$f"; break; }
    done
    if [ -n "$NEWLOG" ]; then
        out ""
        out "  最近一次完整充电的分阶段数据 ($(basename "$NEWLOG")):"
        grep -A30 "分阶段详情" "$NEWLOG" 2>/dev/null | while IFS= read -r l; do out "    $l"; done
    fi
else
    out "  目录不存在 !!"
fi
out ""

# ============ 7. 自动 A/B ============
# 采样函数: $1=组名 $2=时长秒 ; 输出 "平均功率|峰值|最低|平均温度|平均CCL|平均输入电压"
measure() {
    _g=$1; _d=$2
    _tmp="$ABDIR/_y700_ab_${_g}.txt"
    : > "$_tmp"
    _t=0
    while [ "$_t" -lt "$_d" ]; do
        _bv=$(cat $B/voltage_now 2>/dev/null); _bv=${_bv#-}; _bv=${_bv:-0}
        _bi=$(cat $B/current_now 2>/dev/null); _bi=${_bi#-}; _bi=${_bi:-0}
        _bt=$(cat $B/temp 2>/dev/null); _bt=${_bt:-0}
        _cc=$(cat $CCLP 2>/dev/null); _cc=${_cc:-0}
        _uv=$(cat $U/voltage_now 2>/dev/null); _uv=${_uv#-}; _uv=${_uv:-0}
        _pw=$(awk "BEGIN{printf \"%.2f\", $_bv*$_bi/1e12}" 2>/dev/null)
        echo "${_pw:-0} ${_bt:-0} ${_cc:-0} ${_uv:-0}" >> "$_tmp"
        _t=$((_t + 2))
        [ "$_t" -lt "$_d" ] && sleep 2
    done
    awk '{n++; s+=$1; if($1>mx)mx=$1; if(mn==""||$1<mn)mn=$1; ts+=$2; cs+=$3; us+=$4}
         END{ if(n==0){print "0|0|0|0|0|0"; exit}
              printf "%.2f|%.2f|%.2f|%.1f|%.0f|%.2f", s/n, mx, mn, ts/n/10, cs/n, us/n/1000000 }' "$_tmp" 2>/dev/null
}

show_state() {
    out "    协议=$(cat $U/real_type 2>/dev/null) 状态=$(cat $B/status 2>/dev/null) 电量=$(cat $B/capacity 2>/dev/null)%"
    for t in fast-chg-therm usb battery; do
        z=$(find_zone "$t")
        [ -n "$z" ] && out "    $t: mode=$(zmode "$z") temp=$(ztemp "$z")"
    done
    out "    CCL=$(cat $CCLP 2>/dev/null)/$(cat $CCLMAXP 2>/dev/null)"
}

# 检查热重载是否真的生效: 返回 0=生效
hot_ok() {
    _z=$(find_zone fast-chg-therm)
    [ -n "$_z" ] || return 1
    [ "$(zmode "$_z")" = "$1" ]
}

out "【7】自动 A/B 对比 (改配置靠热重载, 不需要重启)"
DST=$(cat $B/status 2>/dev/null)
DPR=$(cat $U/real_type 2>/dev/null)
if [ "$DST" != "Charging" ]; then
    out "  ⚠ 当前未在充电(状态=$DST) -> 跳过 A/B"
    out "    请插上充电器后重新运行本脚本"
    add_problem "运行时未充电, A/B 未执行"
elif [ $NOAB = 1 ]; then
    out "  已按 --no-ab 跳过"
elif [ $HAVERELOAD = 0 ] && [ $N -gt 0 ]; then
    out "  ⚠ 当前模块不支持热重载(V7.0 及更早), 无法自动 A/B"
    out "    请先升级到 V7.1+ 再运行; 或手动做: 改配置 -> 重启 -> 再跑本脚本快照"
    add_problem "模块版本过低, 无法自动 A/B(建议升级 V7.1+)"
else
    out "  协议=$DPR 电量=$(cat $B/capacity 2>/dev/null)% (A/B 期间请勿拔线/勿玩游戏)"
    out "  每组采样 40 秒, 共 4 组, 约 3 分钟..."
    out ""
    # 备份配置
    cp -f "$CFG" "$CFGBAK" 2>/dev/null
    ORIG_BYPASS=$(getcfg ENABLE_THERMAL_BYPASS); ORIG_ZONE=$(getcfg ZONE_MODE)
    [ -z "$ORIG_BYPASS" ] && ORIG_BYPASS=1
    [ -z "$ORIG_ZONE" ] && ORIG_ZONE=1

    out "  ── A 组: 当前配置 (温控=$ORIG_BYPASS 温区模式=$ORIG_ZONE) ──"
    show_state
    A_SUM=$(measure A 40)

    out ""
    out "  ── B 组: 仅伪装温度 (ZONE_MODE=2, 不禁用温区) ──"
    setcfg ZONE_MODE 2
    sleep 10
    show_state
    HOTB=0; hot_ok enabled && HOTB=1
    [ "$HOTB" = "0" ] && out "    ⚠ 温区仍是 disabled -> 热重载没生效(检查模块是否 V7.1+ 且进程在运行)"
    B_SUM=$(measure B 40)

    out ""
    out "  ── C 组: 完全关闭模块作用 (ENABLE_THERMAL_BYPASS=0) ──"
    setcfg ENABLE_THERMAL_BYPASS 0
    sleep 10
    show_state
    HOTC=0
    _cz=$(find_zone fast-chg-therm)
    [ -n "$_cz" ] && [ "$(ztemp "$_cz")" != "$FAKE_CHG" ] && HOTC=1
    [ "$HOTC" = "0" ] && out "    ⚠ 伪装温度未被清除 -> 热重载没生效(检查模块是否 V7.1+)"
    C_SUM=$(measure C 40)

    out ""
    out "  ── D 组: 还原配置 (温控=$ORIG_BYPASS 温区模式=$ORIG_ZONE) ──"
    restore_cfg
    sleep 10
    show_state
    D_SUM=$(measure D 20)
    if [ "$HOTB" = "0" ] || [ "$HOTC" = "0" ]; then
        add_problem "热重载未完全生效(B=$HOTB C=$HOTC): A/B 结果仅供参考; 若模块非 V7.1+ 请先升级"
    fi

    out ""
    out "  ────── A/B 结果汇总 ──────"
    out "  组别  配置                     平均功率  峰值   最低   平均温度  平均CCL"
    printf "  A     基线(温控=%s 温区=%s)      %s\n" "$ORIG_BYPASS" "$ORIG_ZONE" "$(echo "$A_SUM" | awk -F'|' '{printf "%-9s %-6s %-6s %-9s %s", $1"W", $2"W", $3"W", $4"C", $5}')" >> "$REPORT"
    printf "  A     基线(温控=%s 温区=%s)      %s\n" "$ORIG_BYPASS" "$ORIG_ZONE" "$(echo "$A_SUM" | awk -F'|' '{printf "%-9s %-6s %-6s %-9s %s", $1"W", $2"W", $3"W", $4"C", $5}')"
    printf "  B     仅伪装(ZONE_MODE=2)       %s\n" "$(echo "$B_SUM" | awk -F'|' '{printf "%-9s %-6s %-6s %-9s %s", $1"W", $2"W", $3"W", $4"C", $5}')" >> "$REPORT"
    printf "  B     仅伪装(ZONE_MODE=2)       %s\n" "$(echo "$B_SUM" | awk -F'|' '{printf "%-9s %-6s %-6s %-9s %s", $1"W", $2"W", $3"W", $4"C", $5}')"
    printf "  C     模块全关(绕过=0)          %s\n" "$(echo "$C_SUM" | awk -F'|' '{printf "%-9s %-6s %-6s %-9s %s", $1"W", $2"W", $3"W", $4"C", $5}')" >> "$REPORT"
    printf "  C     模块全关(绕过=0)          %s\n" "$(echo "$C_SUM" | awk -F'|' '{printf "%-9s %-6s %-6s %-9s %s", $1"W", $2"W", $3"W", $4"C", $5}')"
    printf "  D     还原后                    %s\n" "$(echo "$D_SUM" | awk -F'|' '{printf "%-9s %-6s %-6s %-9s %s", $1"W", $2"W", $3"W", $4"C", $5}')" >> "$REPORT"
    printf "  D     还原后                    %s\n" "$(echo "$D_SUM" | awk -F'|' '{printf "%-9s %-6s %-6s %-9s %s", $1"W", $2"W", $3"W", $4"C", $5}')"

    AV=$(echo "$A_SUM" | cut -d'|' -f1)
    BV=$(echo "$B_SUM" | cut -d'|' -f1)
    CV=$(echo "$C_SUM" | cut -d'|' -f1)
    out ""
    out "  ────── 自动判读 ──────"
    # C 组 vs A 组: 关掉模块是否更快
    R1=$(awk "BEGIN{ if($AV<=0){print 0; exit} printf \"%d\", ($CV>$AV*1.25)?1:0 }" 2>/dev/null)
    R2=$(awk "BEGIN{ if($AV<=0){print 0; exit} printf \"%d\", ($CV<$AV*0.85)?1:0 }" 2>/dev/null)
    R3=$(awk "BEGIN{ if($AV<=0){print 0; exit} printf \"%d\", ($BV>$AV*1.20)?1:0 }" 2>/dev/null)
    if [ "$R1" = "1" ]; then
        out "  ★ 关掉模块后功率明显变高 (${AV}W -> ${CV}W)"
        out "    => 模块对这台机器有副作用; 请优先使用 B 组配置(ZONE_MODE=2), 或反馈给作者"
        add_problem "关闭模块后充电更快(${AV}W -> ${CV}W), 说明模块反而在限流, 需针对性适配"
    elif [ "$R2" = "1" ]; then
        out "  ★ 关掉模块后功率更低 (${AV}W -> ${CV}W)"
        out "    => 模块确实在帮忙(消除温控限流), 但平台还有别的限制卡着, 继续看第 4 节证据"
    else
        out "  ★ 开关模块功率几乎一样 (模块 ${AV}W / 关闭 ${CV}W)"
        out "    => 当前限流与模块无关, 是充电器/线材/平台策略; 按第 4/6 节证据继续排查"
        add_problem "限流与模块无关(开关模块功率基本一致), 瓶颈在充电器/线材/平台策略"
    fi
    if [ "$R3" = "1" ]; then
        out "  ★ 仅伪装模式(ZONE_MODE=2)功率更高 (${AV}W -> ${BV}W)"
        out "    => 这台四代应改用 ZONE_MODE=2 (禁用温区会被平台当成异常而回落小电流)"
        add_problem "建议把这台机器的 ZONE_MODE 改为 2 (仅伪装模式更快: ${AV}W -> ${BV}W)"
    fi
    out ""
    out "  (A/B 期间电量/温度会略有变化, 差值 <15% 视为噪声)"
fi
out ""

# ============ 8. 运行日志 & 结论 ============
out "【8】模块运行日志 (最近 30 行)"
if [ -f "$RTL" ]; then
    tail -30 "$RTL" 2>/dev/null | while IFS= read -r l; do out "  $l"; done
else
    out "  (无 $RTL)"
fi
out ""

out "============================================================"
out "【9】结论"
out "============================================================"
if [ -z "$PROBLEMS" ]; then
    out "  ✅ 未发现明确异常(但若充电功率仍偏低, 请把本报告发出, 重点看第 3/4/7 节)"
else
    out "  ❌ 发现以下问题/线索:"
    printf "%s" "$PROBLEMS" | while IFS= read -r l; do out "$l"; done
fi
out ""
out "  排查顺序建议:"
out "   1) 第 7 节: 若「模块全关」也一样慢 -> 与模块无关, 直接查充电器/线材"
out "   2) 第 3 节: 找 usb/current_max、pd_*、charge_type、sw_jeita_enabled、step_charging_enabled"
out "      - current_max 只有 1.5A/2A -> 充电器/线材只给到这么点(换原装 C-to-C 线复测)"
out "      - sw_jeita_enabled=1 且温度偏高 -> 软件 JEITA 限流(模块只能间接影响)"
out "      - charge_type=Standard/Trickle -> 平台没进入快充阶段"
out "   3) 第 4 节: dmesg 里搜 aicl / jeita / pps, 平台通常会打印限流原因"
out "   4) 第 6 节: 若历史上从未超过 20W -> 这台机器就没跑出过快充"
out "   5) 第 5 节: 若某个未被伪装的热源(如 front_temp/back_temp/pmih010x_tz)温度很高,"
out "      可能就是平台限流依据 -> 把该温区名称发给作者, 下一版可纳入伪装范围"
out ""
out "============================================================"
out "  报告已保存: $REPORT"
out "  请把这个文件发出来 (含充电器型号/线材是否原装 更好)"
out "============================================================"
