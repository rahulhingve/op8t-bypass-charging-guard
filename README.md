# OnePlus 8T Smart Bypass Charging Guard (80% / 40% Cycle)

[![Android](https://img.shields.io/badge/Android-16%20(AOSP)-3DDC84?logo=android&logoColor=white)](https://android.com)
[![Device](https://img.shields.io/badge/Device-OnePlus%208T%20(kebab)-EB0028?logo=oneplus&logoColor=white)](https://oneplus.com)
[![Kernel](https://img.shields.io/badge/Root-KernelSU%20%2F%20Magisk-critical)](https://github.com/tiann/KernelSU)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

An automated battery protection daemon and CLI management suite for the **OnePlus 8T ("kebab")**. It implements true hardware pass-through / bypass charging with an automated **80% stop / 40% resume** smart charge cycle, complete with native Android status notifications and boot persistence.

---

> [!CAUTION]
> ### ⚠️ Hardware & Compatibility Disclaimer
> **This project was researched, developed, and verified exclusively on:**
> - **Device:** OnePlus 8T (KB2000 / KB2001, Snapdragon 865 / SM8250)
> - **ROM:** Lunaris AOSP (Android 16)
> - **Kernel / Boot Image:** Custom TouchFix kernel (compiled specifically for OnePlus 8T with replaced/aftermarket display touch controllers).
> - **Root Environment:** KernelSU / `su` root access.
> 
> *The author and contributors do not guarantee compatibility with other OnePlus devices, other ROMs, or stock OxygenOS kernels. Use this tool entirely at your own risk.*

---

## 📖 Background & Problem Statement

Modern smartphone lithium-ion batteries degrade rapidly when held at high charge states (100%) and elevated temperatures—conditions common during:
- Long mobile gaming sessions (e.g., PUBG/BGMI, Genshin Impact)
- Extended USB/Wi-Fi hotspot tethering
- Desk setups where the device remains plugged into a charger or PC for hours or days

Unlike some dedicated gaming phones, the OnePlus 8T does not expose an official "bypass charging" toggle in stock settings. However, the underlying Qualcomm power-management hardware **fully supports** power-path separation (NVDC architecture).

---

## 🔬 Hardware & Kernel Research

### 1. Power Architecture (Qualcomm PM8150B NVDC)
The OnePlus 8T utilizes the **Qualcomm PM8150B** primary charge controller alongside an auxiliary SMB1398 fast-charging pump. The PM8150B employs a **Narrow Voltage Direct Current (NVDC)** power-path management topology:
- **`VBUS`**: The 5V–10V USB power rail supplied by the charger.
- **`VSYS`**: The internal system power rail powering the motherboard, SoC, screen, and radios.
- **`VBAT`**: The internal lithium-ion battery cell rail.

Under NVDC architecture, `VSYS` is decoupled from direct battery float. The PM8150B can power `VSYS` directly from `VBUS` while isolating or turning off current flowing into `VBAT`.

```
                    [ USB Charger (VBUS) ]
                               │
                               ▼
                   ┌───────────────────────┐
                   │   Qualcomm PM8150B    │
                   │   Charge Controller   │
                   └───────────┬───────────┘
                               │
                ┌──────────────┴──────────────┐
                ▼                             ▼
       [ Motherboard (VSYS) ]        [ Battery Cell (VBAT) ]
       (Phone runs 100% stable)      (ISOLATED: ~0 mA current)
```

### 2. Why `input_suspend` Fails
Many generic battery-saver tools attempt to write to:
```bash
/sys/class/power_supply/battery/input_suspend -> 1
```
On Qualcomm SM8250 platforms, `input_suspend` isolates the entire USB `VBUS` input. As a consequence, the phone cannot draw electricity from the cable at all, forcing the device to run entirely on the battery—defeating the purpose of bypass charging.

### 3. The Working Hardware Node: `mmi_charging_enable`
In the OnePlus / OPlus kernel battery driver (`drivers/power/supply/qcom/` & `oplus_chg/`), the vendor provides a dedicated testing and factory charge-disable interface:
```bash
/sys/class/oplus_chg/battery/mmi_charging_enable
```
When `0` is written to this node:
1. The kernel invokes `oplus_chg_turn_off_charging()`.
2. The SMB charger driver votes to disable charging:
   ```c
   vote(chg_disable_votable, DEFAULT_VOTER, true, 0);
   ```
3. The PM8150B immediately stops current injection into the battery cells (`VBAT`).
4. **Result:** The system rail (`VSYS`) continues to draw operating current directly from the USB cable (`VBUS`). The battery cell current drops to **0 mA (30–100 µA idle flow)**, and the battery transitions to `Discharging`/Idle without powering down the device.

Writing `1` removes the disable vote, instantly resuming full fast-charging.

---

## ⚡ The Smart 80% / 40% Cycle Daemon

Rather than leaving the battery pinned permanently at 80% (which can cause micro-trickle strain over long periods), this daemon implements an intelligent **hysteresis cycle**:

```
                       [ Cable Connected ]
                                │
                                ▼
                       Battery charges to 80%
                                │
                                ▼
                 ⚡ 80% Reached: BYPASS ACTIVATED
                 (Phone runs 100% on USB cable power)
                 (Battery charging paused: ~0 mA flow)
                                │
                                ▼
              Natural ambient idle drain down to 40%
                                │
                                ▼
                🪫 40% Reached: CHARGING RESUMED
                 (Battery safely recharged up to 80%)
                                │
                                └───► Loops infinitely
```

### Native Android Notifications
Whenever a state transition occurs (80% bypass engaged, 40% charging resumed, cable connected/disconnected), the daemon triggers Android's native Notification Manager:
```bash
cmd notification post -S bigtext -t "TITLE" OP8T_BYPASS_GUARD "TEXT"
```
No third-party apps or Termux:API packages required—all alerts appear directly in the Android system notification drawer.

---

## 🚀 Features

- **True Hardware Pass-Through:** Device runs purely on cable power; battery current drops to ~0 mA.
- **Smart 80% / 40% Loop:** Automatically charges to 80%, engages bypass, and re-engages charging when dropping to 40%.
- **Customizable Thresholds:** Easily adjust high/low thresholds via `bypass set <high> <low>`.
- **Reboot Persistence:** Automatically starts at boot via KernelSU `/data/adb/service.d/`.
- **Failsafe Design:** If the daemon process is terminated, normal charging is automatically restored. Cable disconnects automatically reset the hardware registers.
- **Full CLI Suite:** Simple commands in Termux (`bypass status`, `bypass on`, `bypass off`, `bypass log`, etc.).

---

## 📦 Project Structure

```
op8t-bypass-charging-guard/
├── bin/
│   └── bypass                          # CLI controller (Termux / Root Shell)
├── daemon/
│   └── op8t_bypass_guard.sh            # Background monitoring daemon
├── service/
│   └── op8t_bypass_guard_service.sh    # KernelSU service.d boot script
├── install.sh                          # Universal 1-click installer (PC ADB or Termux)
├── uninstall.sh                        # Clean uninstaller
├── LICENSE                             # MIT License
└── README.md                           # Documentation & Research
```

---

## 🛠️ Installation

### Method 1: 1-Click Install from PC (via ADB)
Connect your rooted OnePlus 8T to your PC via USB with USB Debugging enabled:
```bash
git clone https://github.com/<your-username>/op8t-bypass-charging-guard.git
cd op8t-bypass-charging-guard
chmod +x install.sh
./install.sh
```

### Method 2: On-Device via Termux
Open Termux on your OnePlus 8T:
```bash
git clone https://github.com/<your-username>/op8t-bypass-charging-guard.git
cd op8t-bypass-charging-guard
chmod +x install.sh
su -c "./install.sh"
```

---

## 💻 CLI Usage Guide

Run `bypass` inside Termux at any time:

### Check Status
```bash
bypass status
# or simply:
bypass
```
**Example Output:**
```
==================================================
       OnePlus 8T Smart Bypass Charging Guard     
==================================================
 Daemon Status      : [● RUNNING] (PID: 14160)
 Power Source       : DIRECT USB CABLE (Bypass Active)
 Battery Charging   : PAUSED (0 mA Flow)
 State Tracker      : BYPASS
 Auto Loop Target   : Bypass >= 80%  |  Recharge <= 40%
--------------------------------------------------
 Battery Level      : 94%
 Battery Status     : Discharging
 USB Connected      : Yes
 Battery Current    : 0 mA (35 µA)
 Battery Voltage    : 4.25 V
 Battery Temp       : 38.7 °C
==================================================
```

### Change Thresholds
```bash
# Set stop at 85% and resume at 35%
bypass set 85 35
```

### Manual Overrides
```bash
# Force bypass charging on immediately (draw cable power only)
bypass on

# Restore normal battery charging immediately
bypass off
```

### Service Controls
```bash
bypass stop       # Stop automated daemon & restore normal charging
bypass start      # Start automated daemon
bypass restart    # Restart daemon
bypass log        # View recent daemon logs
```

---

## 🗑️ Uninstallation

To restore all stock charging behaviors and remove installed scripts:
```bash
./uninstall.sh
```
Or from Termux:
```bash
su -c "rm -f /data/adb/service.d/op8t_bypass_guard.sh && rm -rf /data/adb/op8t_bypass_guard && rm -f /data/data/com.termux/files/usr/bin/bypass && echo 1 > /sys/class/oplus_chg/battery/mmi_charging_enable"
```

---

## 📄 License

This repository is licensed under the [MIT License](LICENSE).
Feel free to study, modify, and build upon this research.
