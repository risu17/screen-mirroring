# Screen Sharing 2.0 Security, Privacy & Known Limitations

## Security Guarantees

1. **Zero Phone Residue**:
   Screen Sharing never installs any application or service on the phone. The `scrcpy-server` binary is pushed to `/data/local/tmp` at connect time and deleted immediately upon disconnection via `adb shell rm -f /data/local/tmp/scrcpy-server*`.

2. **TLS 1.3 Wireless Debugging**:
   Android 11+ Wireless Debugging uses TLS 1.3 with client/server certificate exchange. All communications across your local Wi-Fi are fully encrypted.

3. **Keychain Key Storage**:
   Device credentials and pairing tokens are stored exclusively in macOS Keychain (`kSecClassGenericPassword`).

4. **FLAG_SECURE Compliance**:
   Screen Sharing strictly respects Android OS security boundaries. Apps with `FLAG_SECURE` (banking apps, authenticator apps, password managers) will appear as black screens in the mirror window. This is enforced at the Android compositor level and cannot be bypassed.

5. **Lock Screen & PIN Safety**:
   In Mirror Mode, if the phone is locked, the lock screen is displayed so the user can enter their PIN or password. Screen Sharing never intercepts, caches, or logs user passwords or PINs.

---

## Known Platform Limitations

1. **One-Time Wireless Debugging Setup**:
   Android requires Developer options and Wireless Debugging to be enabled manually once. Android does not allow external apps to enable developer options automatically without user intervention.

2. **Android 11+ Requirement for Wi-Fi**:
   Google introduced native TLS Wireless Debugging in Android 11 (API 30). Android 10 or older phones cannot pair over Wi-Fi without initially being connected via USB (`adb tcpip 5555`).

3. **Independent Mode (Virtual Displays) OEM Variations**:
   Virtual display creation (`--new-display`) is standard in Android 14+ (AOSP), but some OEM custom skins (such as older MIUI/EMUI or aggressively modified ROMs) may restrict secondary display creation. Screen Sharing detects this automatically, informs the user with a friendly notice, and falls back to standard Mirror Mode.
