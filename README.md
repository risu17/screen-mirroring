# Phone Mirroring (macOS)

**Phone Mirroring** is a native macOS application that mirrors and controls any Android phone directly over Wi-Fi (Wireless Debugging) or USB, similar to Apple's *iPhone Mirroring*.

> **Zero Installation on Phone**: Nothing is installed on your Android device. No companion app, no APK, and no Accessibility service required. Everything runs locally from the macOS app.

---

## Architecture & Features

- **Connection Protocol**: Android's built-in **Wireless Debugging** (Android 11+) and **USB Debugging** via `adb`.
- **Discovery**: Auto-discovers phones on the same Wi-Fi using Bonjour/mDNS (`_adb-tls-connect._tcp` and `_adb-tls-pairing._tcp` via Apple Network framework `NWBrowser`), and USB devices via `adb devices -l`.
- **Mirroring & Control Engine**: Bundled **Universal `adb`** and **Universal `scrcpy`** (`arm64` + `x86_64`, Apache-2.0 licensed). At connect time, `scrcpy-server` is pushed to a temporary location on the phone (`/data/local/tmp/scrcpy-server`) and removed immediately on disconnect.
- **Hardware Acceleration**: H.264 hardware encoding on the phone, VideoToolbox hardware decoding on macOS, 1080p up to 60 fps.
- **Mirror Mode**: Real-time phone mirroring. If the phone is locked, the lock screen PIN/password/pattern can be entered from the Mac or phone. Respects `FLAG_SECURE` (banking/sensitive apps appear black).
- **Independent Mode**: Launches on an isolated Android `VirtualDisplay` (Android 11+, best on Android 14+). Actions performed on the Mac do **not** appear on the phone's physical screen, and actions on the phone do not affect the Mac view.
- **Phone Screen Off (Privacy)**: Keeps the phone's physical screen dark and asleep while active and interactive on macOS via `--turn-screen-off` (`-S`) and `--stay-awake` (`-w`). Toggleable at any time from the mirror toolbar or settings.
- **App Lock (Touch ID + Password)**: Mandatory biometric and password protection. First-time setup configures a master password (salted PBKDF2 SHA-256 with 100,000 iterations in Keychain) with seamless Touch ID authentication, auto-lock on Mac sleep/screen lock, inactivity timeout, and exponential rate limiting against brute-force attempts.
- **Input Forwarding**: Mouse clicks (taps), drags (swipes), scroll wheel, full keyboard typing, right-click (Back).
- **Control Toolbar**: Back, Home, Recents, Rotate, Screen Power (Dark/On), Screenshot, Disconnect.

---

## Privacy & Security

- **100% Local**: All video, audio, and inputs stay on your local network perimeter. Zero cloud servers, zero analytics, zero accounts required.
- **Biometric Security**: Touch ID & salted PBKDF2 SHA-256 encryption protects access to Phone Mirroring.
- **Encrypted**: Android Wireless Debugging uses TLS 1.3 end-to-end authentication. Pairing keys are stored in macOS Keychain.
- **Ephemeral**: The temporary server process on the phone is killed and deleted on disconnect.
- **Physical Screen Privacy**: Phone display remains turned off while in use on Mac.
- **PIN Safety**: Screen unlock PINs/passwords are typed directly and never stored or logged anywhere.

---

## One-Time Phone Setup Guide

1. Open your Android phone's **Settings** > **About phone**.
2. Tap **Build number** 7 times to enable Developer options.
3. Open **Settings** > **System** > **Developer options**.
4. Scroll to **Debugging** and toggle **Wireless debugging** to **ON**.
5. Tap directly on **Wireless debugging** and choose either:
   - **"Pair device with pairing code"**: Enter the 6-digit code and port shown in the popup.
   - **"Pair device with QR code"**: Scan the QR code displayed on Phone Mirroring.
6. Once paired, your phone is stored as a trusted device and will reconnect automatically in the future.

*(For USB: Simply connect your phone with a USB cable and tap "Allow USB Debugging" on your phone screen).*

---

## Feature Matrix

| Feature | Status | Notes |
| :--- | :--- | :--- |
| **Zero Phone Install** | ✅ Complete | Runs purely through ADB Wireless/USB debugging. |
| **App Lock (Touch ID & Password)** | ✅ Complete | PBKDF2 SHA-256 (100k rounds), Keychain, Touch ID, rate limiting. |
| **Phone Screen Off (Privacy)** | ✅ Complete | Physical screen stays dark while interactive on Mac. |
| **mDNS Proximity Discovery** | ✅ Complete | Uses `_adb-tls-connect._tcp` & `_adb-tls-pairing._tcp` via `NWBrowser`. |
| **QR Code Pairing** | ✅ Complete | Dynamic QR code generation matching Android 11+ pairing format. |
| **USB Auto-Detection** | ✅ Complete | Discovers connected USB devices with device model info. |
| **One-Time Wi-Fi Pairing** | ✅ Complete | 6-digit TLS pairing handshake, keys stored in Keychain. |
| **Auto-Reconnect** | ✅ Complete | Returning paired devices connect with zero prompts. |
| **Mirror Mode** | ✅ Complete | Full screen mirror with lock screen PIN entry support. |
| **Independent Mode** | ✅ Complete | Isolated virtual display (`--new-display`). Auto-fallback if unsupported. |
| **Input Controls** | ✅ Complete | Click = Tap, Drag = Swipe, Scroll, Keyboard, Right-click = Back. |
| **Control Toolbar** | ✅ Complete | Back, Home, Recents, Rotate, Screen Power, Screenshot, Disconnect. |
| **FLAG_SECURE Compliance** | ✅ Complete | Banking & password screens are blanked by Android OS. |
| **Universal Binary** | ✅ Complete | Native `arm64` + `x86_64` targeting macOS 13.0+. |

---

## Building and Installing

```bash
# Build the universal macOS application
./macos/build_app.sh

# Install into ~/Applications and launch
./install_to_applications.sh
```

---

## Licenses & Attribution

- **scrcpy**: Copyright (C) 2018 Genymobile, Apache-2.0 License.
- **adb**: Copyright (C) 2005-2024 The Android Open Source Project, Apache-2.0 License.
- Full license text included in `macos/Resources/THIRD_PARTY_LICENSES.txt`.
