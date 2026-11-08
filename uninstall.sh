#!/bin/bash
# ==============================================================================
# Uninstaller for OnePlus 8T Bypass Charging Guard
# ==============================================================================

set -e

echo "=========================================================="
echo "    OnePlus 8T Smart Bypass Charging Guard Uninstaller    "
echo "=========================================================="

if [ -d "/data/data/com.termux" ] || [ -f "/system/bin/sh" ] && [ -n "$ANDROID_ROOT" ]; then
    ON_DEVICE=1
else
    ON_DEVICE=0
fi

if [ "$ON_DEVICE" -eq 1 ]; then
    SUDO="su -c"
    [ "$(id -u)" -eq 0 ] && SUDO="sh -c"

    echo "[-] Stopping daemon..."
    $SUDO "PID=\$(cat /data/adb/op8t_bypass_guard/daemon.pid 2>/dev/null); [ -n \"\$PID\" ] && kill -TERM \"\$PID\" 2>/dev/null || true"
    
    echo "[-] Restoring normal charging node..."
    $SUDO "echo 1 > /sys/class/oplus_chg/battery/mmi_charging_enable"

    echo "[-] Removing files..."
    $SUDO "rm -f /data/adb/service.d/op8t_bypass_guard.sh"
    $SUDO "rm -rf /data/adb/op8t_bypass_guard"
    [ -f /data/data/com.termux/files/usr/bin/bypass ] && rm -f /data/data/com.termux/files/usr/bin/bypass

    $SUDO "cmd notification post -S bigtext -t '🛡️ Bypass Guard' OP8T_BYPASS_GUARD 'Uninstalled. Normal charging restored.' >/dev/null 2>&1 || true"
else
    echo "[*] Connecting via ADB..."
    DEVICE=$(adb devices | grep -w "device" | head -n1 | awk '{print $1}')
    if [ -z "$DEVICE" ]; then
        echo "[✘] Error: No device found via ADB."
        exit 1
    fi

    echo "[-] Stopping daemon and removing service..."
    adb -s "$DEVICE" shell "su -c '
        PID=\$(cat /data/adb/op8t_bypass_guard/daemon.pid 2>/dev/null)
        if [ -n \"\$PID\" ]; then
            kill -TERM \"\$PID\" 2>/dev/null || true
        fi
        echo 1 > /sys/class/oplus_chg/battery/mmi_charging_enable
        rm -f /data/adb/service.d/op8t_bypass_guard.sh
        rm -rf /data/adb/op8t_bypass_guard
        rm -f /data/data/com.termux/files/usr/bin/bypass
        cmd notification post -S bigtext -t \"🛡️ Bypass Guard\" OP8T_BYPASS_GUARD \"Uninstalled. Normal charging restored.\" >/dev/null 2>&1 || true
    '"
fi

echo "[✔] OnePlus 8T Bypass Guard has been cleanly uninstalled."
echo "    Normal battery charging restored."
