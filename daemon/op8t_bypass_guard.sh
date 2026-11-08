#!/system/bin/sh
# ==============================================================================
# OnePlus 8T Smart Bypass Charging Guard Daemon
#
# Hardware: OnePlus 8T ("kebab" / KB2000 / KB2001)
# PMIC: Qualcomm PM8150B (NVDC Architecture)
# Driver Node: /sys/class/oplus_chg/battery/mmi_charging_enable
#
# Power Detection: Checks AC Adapter (/sys/class/power_supply/ac/online),
#                  USB Port (/sys/class/power_supply/usb/online), and
#                  PC Port (/sys/class/power_supply/pc_port/online).
#
# Smart Cycle:
#   - Power connected + Battery >= 80% -> Enable Bypass (phone runs on cable power)
#   - Power connected + Battery <= 40% -> Resume Charging (charges back up to 80%)
#   - Power disconnected               -> Restore stock charging node
# ==============================================================================

CONFIG_DIR="/data/adb/op8t_bypass_guard"
CONFIG_FILE="$CONFIG_DIR/config.env"
PID_FILE="$CONFIG_DIR/daemon.pid"
LOG_FILE="$CONFIG_DIR/daemon.log"
STATE_FILE="$CONFIG_DIR/state"

MMI_NODE="/sys/class/oplus_chg/battery/mmi_charging_enable"
CAP_NODE="/sys/class/power_supply/battery/capacity"
STATUS_NODE="/sys/class/power_supply/battery/status"
CURRENT_NODE="/sys/class/power_supply/battery/current_now"
TEMP_NODE="/sys/class/power_supply/battery/temp"

# Default Thresholds
HIGH_THRESHOLD=80
LOW_THRESHOLD=40
CHECK_INTERVAL=10
NOTIFY_ENABLED=1

mkdir -p "$CONFIG_DIR"

# Ensure single running instance
for p in $(pgrep -f "op8t_bypass_guard/daemon.sh" 2>/dev/null); do
    if [ "$p" != "$$" ]; then
        kill -9 "$p" 2>/dev/null
    fi
done
echo "$$" > "$PID_FILE"

# Load custom config if present
if [ -f "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
fi

is_power_online() {
    local AC USB PC
    AC=$(cat /sys/class/power_supply/ac/online 2>/dev/null || echo 0)
    USB=$(cat /sys/class/power_supply/usb/online 2>/dev/null || echo 0)
    PC=$(cat /sys/class/power_supply/pc_port/online 2>/dev/null || echo 0)

    if [ "$AC" = "1" ] || [ "$USB" = "1" ] || [ "$PC" = "1" ]; then
        echo "1"
    else
        echo "0"
    fi
}

get_power_source_name() {
    local AC USB PC
    AC=$(cat /sys/class/power_supply/ac/online 2>/dev/null || echo 0)
    USB=$(cat /sys/class/power_supply/usb/online 2>/dev/null || echo 0)
    PC=$(cat /sys/class/power_supply/pc_port/online 2>/dev/null || echo 0)

    if [ "$AC" = "1" ]; then
        echo "AC Adapter / Charger"
    elif [ "$USB" = "1" ]; then
        echo "USB Cable"
    elif [ "$PC" = "1" ]; then
        echo "PC Port"
    else
        echo "Battery"
    fi
}

log() {
    local MSG="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$MSG"
    echo "$MSG" >> "$LOG_FILE"
    # Auto-rotate log if exceeds 200KB
    if [ -f "$LOG_FILE" ] && [ $(wc -c < "$LOG_FILE" 2>/dev/null || echo 0) -gt 204800 ]; then
        tail -n 150 "$LOG_FILE" > "$LOG_FILE.tmp" 2>/dev/null && mv "$LOG_FILE.tmp" "$LOG_FILE"
    fi
}

notify() {
    local TITLE="$1"
    local TEXT="$2"
    log "NOTIFICATION: $TITLE - $TEXT"
    if [ "$NOTIFY_ENABLED" -eq 1 ]; then
        # Post via UID 2000 (shell) because Android 14+ drops UID 0 (root) notifications
        # with PackageManager$NameNotFoundException: root
        su 2000 -c "cmd notification post -i @android:drawable/stat_sys_battery_charge -S bigtext -t '$TITLE' OP8T_BYPASS_GUARD '$TEXT'" >/dev/null 2>&1 || \
        su shell -c "cmd notification post -i @android:drawable/stat_sys_battery_charge -S bigtext -t '$TITLE' OP8T_BYPASS_GUARD '$TEXT'" >/dev/null 2>&1 || \
        cmd notification post -S bigtext -t "$TITLE" OP8T_BYPASS_GUARD "$TEXT" >/dev/null 2>&1
    fi
}

cleanup() {
    log "Shutdown signal received. Restoring stock charging mode..."
    if [ -f "$MMI_NODE" ]; then
        echo 1 > "$MMI_NODE"
    fi
    echo "STOPPED" > "$STATE_FILE"
    if [ "$(cat "$PID_FILE" 2>/dev/null)" = "$$" ]; then
        rm -f "$PID_FILE"
    fi
    notify "🛡️ Bypass Guard Stopped" "Daemon stopped. Normal charging restored."
    exit 0
}

trap cleanup INT TERM

# Ensure hardware node exists
if [ ! -f "$MMI_NODE" ]; then
    log "CRITICAL: Charging node $MMI_NODE not found on this kernel/device!"
    echo "ERROR_NO_NODE" > "$STATE_FILE"
    rm -f "$PID_FILE"
    exit 1
fi

log "=========================================================="
log "OnePlus 8T Bypass Charging Guard Daemon Started (PID: $$)"
log "Target Profile: Bypass at >= ${HIGH_THRESHOLD}%, Resume at <= ${LOW_THRESHOLD}%"
log "=========================================================="

LAST_POWER=$(is_power_online)
CURRENT_CAP=$(cat "$CAP_NODE" 2>/dev/null || echo 50)
CURRENT_MODE="UNKNOWN"

# Determine initial state on daemon launch
if [ "$LAST_POWER" = "1" ]; then
    PWR_SRC=$(get_power_source_name)
    if [ "$CURRENT_CAP" -ge "$HIGH_THRESHOLD" ]; then
        echo 0 > "$MMI_NODE"
        CURRENT_MODE="BYPASS"
        notify "⚡ Bypass Guard Active" "Battery at ${CURRENT_CAP}% (>= ${HIGH_THRESHOLD}%). Connected to $PWR_SRC. Bypass engaged (drawing cable power)."
    else
        echo 1 > "$MMI_NODE"
        CURRENT_MODE="CHARGING"
        notify "🔋 Bypass Guard Active" "Battery at ${CURRENT_CAP}%. Charging via $PWR_SRC towards ${HIGH_THRESHOLD}%."
    fi
else
    echo 1 > "$MMI_NODE"
    CURRENT_MODE="UNPLUGGED"
    notify "🛡️ Bypass Guard Active" "Battery at ${CURRENT_CAP}%. Running on battery."
fi
echo "$CURRENT_MODE" > "$STATE_FILE"

# Main Daemon Monitoring Loop
while true; do
    sleep "$CHECK_INTERVAL"

    # Reload config dynamically if modified
    if [ -f "$CONFIG_FILE" ]; then
        . "$CONFIG_FILE"
    fi

    POWER=$(is_power_online)
    CAP=$(cat "$CAP_NODE" 2>/dev/null || echo 50)
    NODE_VAL=$(cat "$MMI_NODE" 2>/dev/null || echo 1)

    # 1. Handle Plug / Unplug Events
    if [ "$POWER" != "$LAST_POWER" ]; then
        if [ "$POWER" = "1" ]; then
            PWR_SRC=$(get_power_source_name)
            log "Power connected via $PWR_SRC (Battery: ${CAP}%)"
            if [ "$CAP" -ge "$HIGH_THRESHOLD" ]; then
                echo 0 > "$MMI_NODE"
                CURRENT_MODE="BYPASS"
                notify "🔌 Connected: $PWR_SRC (${CAP}%)" "Bypass mode active. Powered directly from cable."
            else
                echo 1 > "$MMI_NODE"
                CURRENT_MODE="CHARGING"
                notify "🔌 Connected: $PWR_SRC (${CAP}%)" "Charging battery towards ${HIGH_THRESHOLD}%."
            fi
        else
            log "Power disconnected (Battery: ${CAP}%)"
            echo 1 > "$MMI_NODE"
            CURRENT_MODE="UNPLUGGED"
            notify "🔌 Charger Disconnected (${CAP}%)" "Running on battery power."
        fi
        LAST_POWER="$POWER"
        echo "$CURRENT_MODE" > "$STATE_FILE"
        continue
    fi

    # 2. Power Connected - Manage Smart Charge / Bypass Cycle
    if [ "$POWER" = "1" ]; then
        if [ "$CURRENT_MODE" = "CHARGING" ]; then
            if [ "$CAP" -ge "$HIGH_THRESHOLD" ]; then
                log "Battery reached ${CAP}% (>= ${HIGH_THRESHOLD}%). Switching to BYPASS mode."
                echo 0 > "$MMI_NODE"
                CURRENT_MODE="BYPASS"
                echo "$CURRENT_MODE" > "$STATE_FILE"
                notify "⚡ ${HIGH_THRESHOLD}% Reached: Bypass Engaged" "Battery at ${CAP}%. Phone running on cable power. Battery paused."
            elif [ "$NODE_VAL" != "1" ]; then
                # Ensure charging is enabled
                echo 1 > "$MMI_NODE"
            fi
        elif [ "$CURRENT_MODE" = "BYPASS" ]; then
            if [ "$CAP" -le "$LOW_THRESHOLD" ]; then
                log "Battery dropped to ${CAP}% (<= ${LOW_THRESHOLD}%). Resuming CHARGING mode."
                echo 1 > "$MMI_NODE"
                CURRENT_MODE="CHARGING"
                echo "$CURRENT_MODE" > "$STATE_FILE"
                notify "🪫 ${LOW_THRESHOLD}% Reached: Charging Resumed" "Battery at ${CAP}%. Charging resumed up to ${HIGH_THRESHOLD}%."
            elif [ "$NODE_VAL" != "0" ]; then
                # Prevent OS thermal-engine or fast charge daemon from re-enabling charging
                echo 0 > "$MMI_NODE"
            fi
        else
            # Transition from UNPLUGGED state
            if [ "$CAP" -ge "$HIGH_THRESHOLD" ]; then
                echo 0 > "$MMI_NODE"
                CURRENT_MODE="BYPASS"
            else
                echo 1 > "$MMI_NODE"
                CURRENT_MODE="CHARGING"
            fi
            echo "$CURRENT_MODE" > "$STATE_FILE"
        fi
    fi
done
