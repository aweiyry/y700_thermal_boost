#!/system/bin/sh
# PPS 输入电流溯源采集: 遍历所有可能承载输入电流的节点
LOG=/data/local/tmp/pps_probe.log
echo "=== pps probe started $(date '+%F %T') ===" > $LOG
echo "ts|real_type|opmode|usb_v|usb_i|usb_ilim|usb_imax|ucsi2_online|ucsi2_v|ucsi2_i|ucsi2_imax|wls_v|wls_i|bat_v|bat_i|bat_status|bat_cap|bat_temp" >> $LOG

U=/sys/class/power_supply/usb
U2="/sys/class/power_supply/ucsi-source-psy-soc:pmic-glink:ucsi-glink2"
W=/sys/class/power_supply/wireless
B=/sys/class/power_supply/battery
i=0
while [ $i -lt 600 ]; do
  TS=$(date '+%H:%M:%S')
  RT=$(cat $U/real_type 2>/dev/null)
  OM=$(cat /sys/class/typec/port0/power_operation_mode 2>/dev/null)
  UV=$(cat $U/voltage_now 2>/dev/null)
  UI=$(cat $U/current_now 2>/dev/null)
  UIL=$(cat $U/input_current_limit 2>/dev/null)
  UIM=$(cat $U/current_max 2>/dev/null)
  U2O=$(cat "$U2/online" 2>/dev/null)
  U2V=$(cat "$U2/voltage_now" 2>/dev/null)
  U2I=$(cat "$U2/current_now" 2>/dev/null)
  U2M=$(cat "$U2/current_max" 2>/dev/null)
  WV=$(cat $W/voltage_now 2>/dev/null)
  WI=$(cat $W/current_now 2>/dev/null)
  BV=$(cat $B/voltage_now 2>/dev/null)
  BI=$(cat $B/current_now 2>/dev/null)
  BS=$(cat $B/status 2>/dev/null)
  BC=$(cat $B/capacity 2>/dev/null)
  BT=$(cat $B/temp 2>/dev/null)
  echo "$TS|$RT|$OM|$UV|$UI|$UIL|$UIM|$U2O|$U2V|$U2I|$U2M|$WV|$WI|$BV|$BI|$BS|$BC|$BT" >> $LOG
  i=$((i+1))
  sleep 2
done
echo "=== ended $(date '+%F %T') ===" >> $LOG
