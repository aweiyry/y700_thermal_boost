#!/system/bin/sh
echo "=== 已知参考: usb/current_now = $(cat /sys/class/power_supply/usb/current_now 2>/dev/null) uA ==="
echo "=== 已知参考: battery/current_now = $(cat /sys/class/power_supply/battery/current_now 2>/dev/null) uA ==="
echo
echo "=== IIO 输入电流节点 (iin) ==="
D1="/sys/devices/platform/soc/soc:pmic-glink-log/soc:pmic-glink-log:glink-adc/iio:device1"
for f in "$D1"/in_current_*; do
  [ -f "$f" ] && echo "  $(basename $f) = $(cat "$f" 2>/dev/null)"
done
echo
echo "=== IIO vadc (pmih010x) 电流节点 ==="
D2="/sys/devices/platform/soc/c400000.arbiter/spmi-0/0-00/c426000.spmi:pmk8850@0:vadc@9000/iio:device0"
for f in "$D2"/in_current_*; do
  [ -f "$f" ] && echo "  $(basename $f) = $(cat "$f" 2>/dev/null)"
done
echo
echo "=== IIO 电压节点(参考) ==="
for f in "$D2"/in_voltage_*iin* "$D2"/in_voltage_*vbus*; do
  [ -f "$f" ] && echo "  $(basename $f) = $(cat "$f" 2>/dev/null)"
done
echo
echo "=== qcom-battery 电流 ==="
echo "  fg1_current = $(cat /sys/class/qcom-battery/fg1_current 2>/dev/null)"
echo "  fg2_current = $(cat /sys/class/qcom-battery/fg2_current 2>/dev/null)"
