# Screen Sharing 2.0 Feature Matrix & Platform Support

| Feature | Implementation Status | OS Support / Limits | Details |
| :--- | :--- | :--- | :--- |
| **Zero Phone Install** | ✅ Implemented | Android 11+ (Wi-Fi), Android 5+ (USB) | No APK, no AccessibilityService, no MediaProjection prompt needed. |
| **Wi-Fi mDNS Discovery** | ✅ Implemented | macOS 13+, Android 11+ | Uses `NWBrowser` for `_adb-tls-connect._tcp` and `_adb-tls-pairing._tcp`. |
| **USB Hotplug** | ✅ Implemented | macOS 13+, Android 5+ | Automatic detection via `adb devices -l`. |
| **Wi-Fi Pairing Code** | ✅ Implemented | Android 11+ | 6-digit TLS pairing using `adb pair <host>:<port> <code>`. |
| **Trusted Reconnection** | ✅ Implemented | macOS 13+ Keychain | Paired devices stored in macOS Keychain. Auto-reconnect with no code. |
| **Forget Device** | ✅ Implemented | macOS 13+ | Clears trusted keys from Keychain and runs `adb disconnect`. |
| **Mirror Mode** | ✅ Implemented | Android 5+ | Mirrors physical display, including lock screen and PIN/pattern entry. |
| **Independent Mode** | ✅ Implemented (with fallback) | Android 11+ (Best on 14+) | Creates virtual display (`--new-display`). If unsupported on custom OEM ROMs, gracefully falls back to Mirror Mode. |
| **Mouse / Touch** | ✅ Implemented | All supported | Click = Tap, Drag = Swipe, Scroll wheel. |
| **Keyboard Typing** | ✅ Implemented | All supported | UTF-8 keyboard forwarding. |
| **Hardware Video** | ✅ Implemented | macOS 13+ VideoToolbox | Up to 1080p, 60 fps, low-latency H.264. |
| **FLAG_SECURE Compliance** | ✅ Implemented | Android OS standard | Banking and password screens are strictly blanked by the Android compositor. |
| **Local Perimeter** | ✅ Implemented | All | Zero cloud servers. All communication stays on local network. |
