#!/bin/bash
# ==============================================================================
# Installer for OnePlus 8T Bypass Charging Guard
# Supports execution from host PC (via ADB) or directly on-device (via Termux/Root)
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================================="
echo "    OnePlus 8T Smart Bypass Charging Guard Installer      "
echo "=========================================================="

# Check if running directly on Android device
if [ -d "/data/data/com.termux" ] || [ -f "/system/bin/sh" ] && [ -n "$ANDROID_ROOT" ]; then
    ON_DEVICE=1
    echo "[*] Detected execution directly on Android device."
else
    ON_DEVICE=0
    echo "[*] Detected execution from host PC via ADB."
fi

if [ "$ON_DEVICE" -eq 1 ]; then
    # Running directly on phone
    if [ "$(id -u)" -ne 0 ] && ! which su >/dev/null 2>&1; then
        echo "[✘] Error: Root access (su) is required to install."
        exit 1
    fi

    SUDO="su -c"
    [ "$(id -u)" -eq 0 ] && SUDO="sh -c"

    echo "[+] Creating /data/adb/op8t_bypass_guard..."
    $SUDO "mkdir -p /data/adb/op8t_bypass_guard /data/adb/service.d"

    echo "[+] Installing daemon script..."
    $SUDO "cp '$SCRIPT_DIR/daemon/op8t_bypass_guard.sh' /data/adb/op8t_bypass_guard/daemon.sh"
    $SUDO "chmod 755 /data/adb/op8t_bypass_guard/daemon.sh"

    echo "[+] Installing KernelSU boot service..."
    $SUDO "cp '$SCRIPT_DIR/service/op8t_bypass_guard_service.sh' /data/adb/service.d/op8t_bypass_guard.sh"
    $SUDO "chmod 755 /data/adb/service.d/op8t_bypass_guard.sh"

    if [ -d "/data/data/com.termux/files/usr/bin" ]; then
        echo "[+] Installing CLI tool to Termux (/data/data/com.termux/files/usr/bin/bypass)..."
        cp "$SCRIPT_DIR/bin/bypass" /data/data/com.termux/files/usr/bin/bypass
        chmod 755 /data/data/com.termux/files/usr/bin/bypass
    fi

    # Create default config if not exists
    $SUDO "[ -f /data/adb/op8t_bypass_guard/config.env ] || cat << 'EOF' > /data/adb/op8t_bypass_guard/config.env
HIGH_THRESHOLD=80
LOW_THRESHOLD=40
CHECK_INTERVAL=10
NOTIFY_ENABLED=1
EOF"

    echo "[+] Starting background daemon..."
    $SUDO "kill -TERM \$(cat /data/adb/op8t_bypass_guard/daemon.pid 2>/dev/null) 2>/dev/null || true"
    $SUDO "nohup /system/bin/sh /data/adb/op8t_bypass_guard/daemon.sh >/dev/null 2>&1 &"

else
    # Running from PC via ADB
    echo "[*] Checking ADB connection..."
    if ! command -v adb >/dev/null 2>&1; then
        echo "[✘] Error: ADB is not installed or not in PATH."
        exit 1
    fi

    DEVICE=$(adb devices | grep -w "device" | head -n1 | awk '{print $1}')
    if [ -z "$DEVICE" ]; then
        echo "[✘] Error: No rooted Android device found via ADB."
        echo "    Please connect your OnePlus 8T via USB and enable USB Debugging."
        exit 1
    fi
    echo "[✔] Connected to device: $DEVICE"

    echo "[+] Creating directories on device..."
    adb -s "$DEVICE" shell "su -c 'mkdir -p /data/adb/op8t_bypass_guard /data/adb/service.d /data/local/tmp/op8t_install && chmod 777 /data/local/tmp/op8t_install'"

    echo "[+] Pushing files to device..."
    adb -s "$DEVICE" push "$SCRIPT_DIR/daemon/op8t_bypass_guard.sh" /data/local/tmp/op8t_install/daemon.sh
    adb -s "$DEVICE" push "$SCRIPT_DIR/service/op8t_bypass_guard_service.sh" /data/local/tmp/op8t_install/service.sh
    adb -s "$DEVICE" push "$SCRIPT_DIR/bin/bypass" /data/local/tmp/op8t_install/bypass

    echo "[+] Setting permissions and moving to system locations..."
    adb -s "$DEVICE" shell "su -c '
        cp /data/local/tmp/op8t_install/daemon.sh /data/adb/op8t_bypass_guard/daemon.sh
        chmod 755 /data/adb/op8t_bypass_guard/daemon.sh

        cp /data/local/tmp/op8t_install/service.sh /data/adb/service.d/op8t_bypass_guard.sh
        chmod 755 /data/adb/service.d/op8t_bypass_guard.sh

        if [ -d /data/data/com.termux/files/usr/bin ]; then
            cp /data/local/tmp/op8t_install/bypass /data/data/com.termux/files/usr/bin/bypass
            chmod 755 /data/data/com.termux/files/usr/bin/bypass
            TERMUX_UID=\$(stat -c %u /data/data/com.termux/files/usr/bin)
            TERMUX_GID=\$(stat -c %g /data/data/com.termux/files/usr/bin)
            chown \${TERMUX_UID}:\${TERMUX_GID} /data/data/com.termux/files/usr/bin/bypass
        fi

        [ -f /data/adb/op8t_bypass_guard/config.env ] || cat << \"EOF\" > /data/adb/op8t_bypass_guard/config.env
HIGH_THRESHOLD=80
LOW_THRESHOLD=40
CHECK_INTERVAL=10
NOTIFY_ENABLED=1
EOF

        rm -rf /data/local/tmp/op8t_install

        # Stop existing instance if running
        PID=\$(cat /data/adb/op8t_bypass_guard/daemon.pid 2>/dev/null)
        if [ -n \"\$PID\" ]; then
            kill -TERM \"\$PID\" 2>/dev/null || true
            sleep 1
        fi

        # Start new daemon
        nohup /system/bin/sh /data/adb/op8t_bypass_guard/daemon.sh >/dev/null 2>&1 &
    '"
fi

sleep 1
echo ""
echo "=========================================================="
echo " [✔] OnePlus 8T Bypass Guard successfully installed!      "
echo "=========================================================="
echo " - Daemon is now active in background."
echo " - Boot service registered in KernelSU (/data/adb/service.d/)."
echo " - CLI tool available in Termux as: 'bypass'"
echo ""
echo " Try running in Termux:"
echo "   bypass status    -> Check live battery, current, & bypass state"
echo "   bypass on / off  -> Manually force bypass or stock charging"
echo "   bypass set 80 40 -> Customize thresholds"
echo "=========================================================="
