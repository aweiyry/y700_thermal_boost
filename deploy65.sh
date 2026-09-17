#!/system/bin/sh
echo "=== 1. 语法检查 ==="
sh -n /data/local/tmp/service_v65.sh && echo SYNTAX_OK || { echo FAIL; exit 1; }
echo "=== 2. 停旧服务 ==="
for p in /proc/[0-9]*; do
  if grep -qa "y700_thermal_boost/service.sh" "$p/cmdline" 2>/dev/null; then
    kill -9 "${p##*/}" 2>/dev/null; echo "killed ${p##*/}"
  fi
done
rm -f /data/local/tmp/y700_thermal_boost.pid
sleep 2
echo "=== 3. 覆盖文件 ==="
cp /data/local/tmp/service_v65.sh /data/adb/modules/y700_thermal_boost/service.sh
chmod 755 /data/adb/modules/y700_thermal_boost/service.sh
cp /data/local/tmp/module_v65.prop /data/adb/modules/y700_thermal_boost/module.prop
chmod 644 /data/adb/modules/y700_thermal_boost/module.prop
echo "=== 4. 启动 ==="
nohup sh /data/adb/modules/y700_thermal_boost/service.sh > /data/local/tmp/y700_v65.log 2>&1 &
sleep 14
echo "=== 5. 验证 ==="
CNT=0
for p in /proc/[0-9]*; do
  if grep -qa "y700_thermal_boost/service.sh" "$p/cmdline" 2>/dev/null; then
    echo "svc pid=${p##*/}"; CNT=$((CNT+1))
  fi
done
echo "实例数=$CNT"
echo "--- 启动日志(应含输入电流节点) ---"
grep -E "V6.5|输入电流节点|运行中" /data/local/tmp/y700_v65.log 2>/dev/null | tail -4
echo "--- 该节点当前值 ---"
