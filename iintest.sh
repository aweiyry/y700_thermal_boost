#!/system/bin/sh
echo "=== 方式1: glob 匹配 (无外部进程) ==="
for f in /sys/devices/platform/soc/*/*/iio:device*/in_current_*_iin_input \
         /sys/devices/platform/soc/*/*/*/iio:device*/in_current_*_iin_input \
         /sys/devices/platform/soc/*/*/*/*/iio:device*/in_current_*_iin_input; do
  [ -r "$f" ] && echo "  $f = $(cat "$f" 2>/dev/null)"
done
echo
echo "=== 方式2: find (对比) ==="
find /sys/devices/platform/soc -maxdepth 7 -name "in_current_*_iin_input" 2>/dev/null
echo
echo "=== 耗时测试 ==="
S=$(date +%s%N 2>/dev/null)
for f in /sys/devices/platform/soc/*/*/iio:device*/in_current_*_iin_input /sys/devices/platform/soc/*/*/*/iio:device*/in_current_*_iin_input /sys/devices/platform/soc/*/*/*/*/iio:device*/in_current_*_iin_input; do
  [ -r "$f" ] && V=$(cat "$f" 2>/dev/null)
done
E=$(date +%s%N 2>/dev/null)
echo "glob方式耗时: $(( (E - S) / 1000000 )) ms"
echo
echo "=== 选定节点并验证 ==="
IIN=""
for f in /sys/devices/platform/soc/*/*/iio:device*/in_current_*_iin_input \
         /sys/devices/platform/soc/*/*/*/iio:device*/in_current_*_iin_input \
         /sys/devices/platform/soc/*/*/*/*/iio:device*/in_current_*_iin_input; do
  [ -r "$f" ] || continue
  case "$f" in *pmih010x_iin*) IIN="$f"; break ;; esac
done
echo "选定: $IIN"
echo "当前值: $(cat "$IIN" 2>/dev/null) uA"
