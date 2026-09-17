#!/system/bin/sh
echo "=== 搜索含 current/ibus 的节点(排除已知) ==="
find /sys -name "*current*" 2>/dev/null | grep -vE "power_supply/(battery|usb|wireless|ucsi)" | head -30
echo
echo "=== qti 充电相关内核模块参数 ==="
for m in qti_battery_charger qti_battery_debug charger_ulog_glink; do
  d="/sys/module/$m/parameters"
  if [ -d "$d" ]; then
    echo "--- $m ---"
    for f in "$d"/*; do echo "  $(basename $f) = $(cat "$f" 2>/dev/null | head -c 80)"; done
  fi
done
echo
echo "=== debugfs 顶层 ==="
ls /sys/kernel/debug/ 2>/dev/null | head -25
echo
echo "=== debugfs 里充电相关 ==="
ls /sys/kernel/debug/ 2>/dev/null | grep -iE "charg|pmic|batt|usb|power"
echo
echo "=== 当前 usb 电源完整 uevent ==="
cat /sys/class/power_supply/usb/uevent 2>/dev/null
