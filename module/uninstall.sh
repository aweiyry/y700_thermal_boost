#!/system/bin/sh
rm -f /data/adb/service.d/y700_thermal_boost.sh 2>/dev/null

LIST="/data/local/tmp/y700_thermal_boost/disabled_zones.list"
[ -f "$LIST" ] && while read -r z; do
    [ -z "$z" ] && continue
    [ -d "$z" ] || continue
    echo "enabled" > "${z}/mode" 2>/dev/null
    echo "0" > "${z}/emul_temp" 2>/dev/null
done < "$LIST"

rm -f "$LIST" 2>/dev/null
