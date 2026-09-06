#!/system/bin/sh
echo "=====[1] service.d 开机脚本 ====="
ls -la /data/adb/service.d/ 2>/dev/null
echo
echo "=====[2] 禁用温区清单 disabled_zones.list ====="
cat /data/local/tmp/y700_thermal_boost/disabled_zones.list 2>/dev/null
echo
echo "=====[3] 温区状态 (type | mode | emul_temp) ====="
for z in /sys/devices/virtual/thermal/thermal_zone*; do
    t=$(cat "$z/type" 2>/dev/null)
    m=$(cat "$z/mode" 2>/dev/null)
    e=$(cat "$z/emul_temp" 2>/dev/null)
    echo "$t | mode=$m | emul=$e"
done
echo
echo "=====[4] 充电控制 CCL ====="
echo "ccl=$(cat /sys/class/power_supply/battery/charge_control_limit 2>/dev/null) max=$(cat /sys/class/power_supply/battery/charge_control_limit_max 2>/dev/null)"
echo
echo "=====[5] 电池实时状态 ====="
echo "status=$(cat /sys/class/power_supply/battery/status 2>/dev/null) cap=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null)% temp=$(cat /sys/class/power_supply/battery/temp 2>/dev/null)($(cat /sys/class/power_supply/battery/temp 2>/dev/null | head -c 2)°C)"
echo
echo "=====[6] 温控相关进程 ====="
ps -A 2>/dev/null | grep -E "thermal" | grep -v grep
echo
echo "=====[7] 充电日志目录 ====="
ls -lt /sdcard/充电日志/ 2>/dev/null | head -5
echo
echo "=====[8] 日志缓冲 ====="
ls -lt /data/local/tmp/charging_data/ 2>/dev/null | head -5
