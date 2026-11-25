# Screen Sharing End-to-End Verification & Test Plan

This document outlines the systematic verification checklist for Screen Sharing across macOS, Android, and Web clients.

---

## 1. Test Matrix Overview

| Test ID | Test Scenario | Expected Outcome | Pass/Fail Criteria |
|---|---|---|---|
| **TC-01** | First-Time Pairing Handshake | Phone displays "Allow [Mac Name]?", Mac & Phone display identical 6-digit SAS codes, credentials stored in Keychain/Keystore. | Both 6-digit codes match exactly. Stored tokens persist across app restarts. |
| **TC-02** | Returning Device Re-Connection | Quick reconnection (<200ms) without pairing prompts; automatic transition to Mirror view. | No prompts or user intervention required after pressing "Connect Devices". |
| **TC-03** | Connection Deny Flow | User taps "Deny" on Android companion prompt. | Mac cleanly cancels pairing, shows friendly "Connection declined by device" message without hanging or crashing. |
| **TC-04** | Bluetooth Disabled on Mac | User launches Mac app with Bluetooth switched off. | UI immediately displays "Bluetooth is Turned Off" screen with an actionable "Open Bluetooth Settings" button. |
| **TC-05** | Bluetooth Disabled on Android | User launches Android app with Bluetooth disabled. | Pre-permission card prompts user to enable Bluetooth with one-tap system switch. |
| **TC-06** | Out-of-Range Proximity Filter | Move Android device beyond 2 meters (or simulate RSSI < -75 dBm). | Device list greys out or filters out phone. Active session triggers 15-second countdown banner before safely terminating. |
| **TC-07** | Lock Screen Interaction | Lock Android device while streaming; enter PIN on Mac. | Lock screen visually rendered on Mac; keyboard input enters PIN, successfully unlocking the device. Never stores PIN in logs. |
| **TC-08** | FLAG_SECURE Protection | Open a banking app or Android Settings privacy screen with FLAG_SECURE. | Mac view renders black/privacy-guarded placeholder; no sensitive content leaked. Audio/video pipeline stays stable. |
| **TC-09** | Mouse Tap, Drag, & Scroll Input | Click UI buttons, swipe between home screen pages, scroll long web pages in Chrome. | Actions translate smoothly with <40ms perceived latency. |
| **TC-10** | Right-Click to Back | Right-click anywhere inside the mirror window. | Android triggers `GLOBAL_ACTION_BACK`, returning to previous screen or closing dialog. |
| **TC-11** | Keyboard Typing & Shortcut Dispatch | Type alphanumeric text into search bar, press Enter and Backspace. | Text injected accurately into focused input field. |
| **TC-12** | Independent Mode Isolation | Switch mode to "Independent Mode". Interact with apps on Mac. | Physical Android phone display remains unchanged or shows phone launcher while Mac operates secondary presentation workspace. |
| **TC-13** | Native macOS Full-Screen | Click green traffic light or press `Ctrl + Cmd + F`. | Window expands smoothly to native macOS space; phone screen scales with preserved aspect ratio and centered letterboxing. |
| **TC-14** | One-Tap Disconnect from Phone | Tap "Stop sharing" on Android status bar persistent notification. | Android MediaProjection stops immediately, Mac gracefully returns to Device Discovery screen. |
| **TC-15** | "Forget This Device" | Click "Forget" on Mac device card or Android settings. | Trust keys deleted from Keychain and Keystore; subsequent connection requires full 6-digit pairing. |
| **TC-16** | Web Client Fallback & Pairing | Open Web client in Chrome; connect via QR code or manual 6-digit PIN. | WebRTC stream initializes, rendering Android video on HTML5 canvas with working mouse clicks. |

---

## 2. Step-by-Step Test Execution Guide

### Test 1: First-Time Pairing (TC-01)
1. Ensure both devices have Screen Sharing installed and Wi-Fi enabled on the same local subnet.
2. Launch Screen Sharing on Android; enable Bluetooth and grant Foreground Service / Notification permissions.
3. Launch Screen Sharing on macOS; click **"Connect Devices"**.
4. Observe the discovery radar. Ensure the phone appears within 3 seconds with RSSI badge and "New Device" indicator.
5. Click on the phone in the Mac list.
6. **Verify**: Android displays sheet: *"Allow [Mac Name] to connect?"*.
7. Tap **Allow** on Android.
8. **Verify**: Both screens present a 6-digit numeric comparison code (e.g., `492104`).
9. Tap **Confirm** on Mac and Android.
10. **Verify**: Video streaming begins immediately. Check macOS Keychain for entry `com.screensharing.mac.trusted.<device-id>`.

### Test 2: Returning Device (TC-02)
1. Close the Screen Sharing macOS window or click **Disconnect**.
2. Relaunch macOS Screen Sharing and click **"Connect Devices"**.
3. **Verify**: The phone displays a **"Paired Before"** badge.
4. Click on the phone.
5. **Verify**: No pairing dialog or SAS code appears on either device. Cryptographic mutual challenge-response completes in $<200\text{ ms}$ and stream resumes directly.

### Test 3: Lock Screen & FLAG_SECURE (TC-07, TC-08)
1. During active mirror stream, press the Mac toolbar **Lock** button or phone power button.
2. **Verify**: The phone lock screen renders in the Mac window.
3. Using the Mac keyboard, type the phone PIN.
4. **Verify**: Phone unlocks. Check Mac system logs (`log stream --predicate 'subsystem == "com.screensharing"'`) to confirm zero logging of key codes or PIN values.
5. Open an app with `FLAG_SECURE` (e.g. 1Password or Android Developer Options > Demo Mode).
6. **Verify**: Screen content inside the app displays black, and an overlay indicates FLAG_SECURE protection.

### Test 4: Independent Mode (TC-12)
1. In the Mac mirror toolbar, toggle mode from **Mirror** to **Independent**.
2. **Verify**: If running on Android 14+ (or compatible API level), secondary VirtualDisplay initializes.
3. Interact with the secondary display from Mac.
4. **Verify**: Physical phone screen continues displaying its own home screen / foreground app independently.

