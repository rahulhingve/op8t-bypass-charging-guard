#!/system/bin/sh
# ==============================================================================
# KernelSU service.d Boot Script for OnePlus 8T Bypass Charging Guard
# Location: /data/adb/service.d/op8t_bypass_guard.sh
#
# Automatically starts the smart 80%/40% bypass charging guard upon boot completion.
# ==============================================================================

# Wait until Android has fully finished booting
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 2
done

# Wait for charging driver and HAL initialization
sleep 5

DAEMON_SCRIPT="/data/adb/op8t_bypass_guard/daemon.sh"

if [ -f "$DAEMON_SCRIPT" ]; then
    nohup /system/bin/sh "$DAEMON_SCRIPT" >/dev/null 2>&1 &
fi

