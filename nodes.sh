#!/system/bin/sh
echo "=== 所有 power_supply 设备 ==="
ls /sys/class/power_supply/
echo
for d in /sys/class/power_supply/*/; do
  n=$(basename "$d")
  echo "--- $n ---"
  for f in type online voltage_now voltage_max current_now current_max input_current_limit power_now power real_type usb_type status; do
    [ -e "$d$f" ] && echo "  $f = $(cat "$d$f" 2>/dev/null)"
  done
done
echo
echo "=== 全局搜索含 current 的节点(排除battery/usb已知) ==="
for d in /sys/class/power_supply/*/; do
  n=$(basename "$d")
  case "$n" in battery|usb) continue ;; esac
  for f in "$d"*; do
    b=$(basename "$f")
    case "$b" in
      *current*|*power*|*voltage*) echo "  $n/$b = $(cat "$f" 2>/dev/null)" ;;
    esac
  done
done
echo
echo "=== typec 端口相关 ==="
for f in /sys/class/typec/port0/*; do
  [ -f "$f" ] && echo "  $(basename $f) = $(cat "$f" 2>/dev/null)"
done
