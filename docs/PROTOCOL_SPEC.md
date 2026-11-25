# Screen Sharing 2.0 Protocol & Discovery Specification

## Discovery Architecture

Screen Sharing discovers Android phones via two distinct channels:

### 1. Wi-Fi Wireless Debugging (Bonjour / mDNS)
Android 11+ announces its presence on the local subnet via mDNS:
- **Connect Service**: `_adb-tls-connect._tcp.local.`
  - Advertised when Wireless Debugging is enabled.
  - Resolves to `<IP>:<connectPort>`.
- **Pairing Service**: `_adb-tls-pairing._tcp.local.`
  - Advertised when "Pair device with pairing code" is opened on the phone.
  - Resolves to `<IP>:<pairingPort>`.

Discovery on macOS is performed using Apple's Network framework `NWBrowser(for: .bonjour(type: ...))`.

### 2. USB Debugging (Hotplug Polling)
- Polls USB devices via bundled `adb devices -l`.
- Device descriptors report product name, model, and hardware bus address.

---

## Pairing Handshake Flow

```
   macOS (Screen Sharing)                          Android Phone
   ───────────────────                             ─────────────
          │                                              │
          │ ── mDNS browse (_adb-tls-pairing._tcp) ────> │
          │ <── Service resolved (IP & Pairing Port) ─── │
          │                                              │
   User enters 6-digit code displayed on phone           │
          │                                              │
          │ ── adb pair <host>:<pairingPort> <code> ───> │
          │ <── TLS 1.3 Handshake & Key Exchange ─────── │
          │ <── "Successfully paired" ────────────────── │
          │                                              │
   Store trusted key in macOS Keychain                   │
          │                                              │
          │ ── adb connect <host>:<connectPort> ───────> │
          │ <── Connected to <host>:<connectPort> ────── │
```

---

## Mirroring Session & Cleanup Lifecycle

1. **Connect**:
   - `adb push scrcpy-server /data/local/tmp/scrcpy-server`
   - Spawns `scrcpy` with hardware acceleration arguments (`--video-codec=h264`, `--max-size=1920`, `--max-fps=60`, `--video-bit-rate=8M`).
   - If Independent Mode is selected: adds `--new-display=1920x1080/420`.
2. **Streaming**:
   - Video is hardware encoded by Android `MediaCodec` and hardware decoded on macOS via VideoToolbox.
   - Touch, clicks, drag, and keystrokes are forwarded directly through scrcpy's control channel.
3. **Disconnect & Cleanup**:
   - Terminates `scrcpy` process.
   - Executes `adb shell rm -f /data/local/tmp/scrcpy-server*` to remove temporary files from the phone.
   - Executes `adb kill-server` if no other devices are connected.
