#!/system/bin/sh
echo "=====[A] emul_temp 文件是否存在/权限 ====="
ls -la /sys/devices/virtual/thermal/thermal_zone*/emul_temp 2>&1 | head -20
echo
echo "=====[B] 关键温区当前实际温度 (temp) ====="
for z in /sys/devices/virtual/thermal/thermal_zone*; do
    t=$(cat "$z/type" 2>/dev/null)
    case "$t" in
        fast-chg-therm|top-chg-therm|battery|batt-pack-therm|batt2-pack-therm|quiet-therm|usb1-conn-therm|usb2-conn-therm|usb|ap-therm|lcm-thermal)
            v=$(cat "$z/temp" 2>/dev/null); m=$(cat "$z/mode" 2>/dev/null)
            echo "$t | temp=$v | mode=$m"
            ;;
    esac
done
echo
echo "=====[C] 电池充电电流电压 ====="
echo "current_now=$(cat /sys/class/power_supply/battery/current_now 2>/dev/null) uA"
echo "voltage_now=$(cat /sys/class/power_supply/battery/voltage_now 2>/dev/null) uV"
echo "ccl=$(cat /sys/class/power_supply/battery/charge_control_limit 2>/dev/null)"
echo "ccl_max=$(cat /sys/class/power_supply/battery/charge_control_limit_max 2>/dev/null)"
echo "real_temp=$(cat /sys/class/power_supply/battery/temp 2>/dev/null) (x0.1C)"
echo
echo "=====[D] 模块运行日志 (logcat) ====="
logcat -d -s Y700-ThermalBoost 2>/dev/null | tail -20
echo
echo "=====[E] 最新充电日志内容 ====="
cat "/sdcard/充电日志/$(ls -1t /sdcard/充电日志/ | head -1)" 2>/dev/null
