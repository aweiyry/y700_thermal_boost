#!/system/bin/sh
chmod 755 "$MODDIR/service.sh" 2>/dev/null
chmod 755 "$MODDIR/uninstall.sh" 2>/dev/null
if [ -f "$MODDIR/config.prop" ]; then
    tr -d '
' < "$MODDIR/config.prop" > "$MODDIR/config.prop.tmp" 2>/dev/null
    mv "$MODDIR/config.prop.tmp" "$MODDIR/config.prop" 2>/dev/null
    chmod 644 "$MODDIR/config.prop" 2>/dev/null
fi

mkdir -p /data/adb/service.d
cat > /data/adb/service.d/y700_thermal_boost.sh << 'EOF'
#!/system/bin/sh
MODDIR=/data/adb/modules/y700_thermal_boost
[ -f "$MODDIR/disable" ] && exit 0
export MODDIR
exec sh "$MODDIR/service.sh"
EOF
chmod 755 /data/adb/service.d/y700_thermal_boost.sh
