import SwiftUI
import AppKit

public struct SettingsSheetView: View {
    @ObservedObject var appState: AppState = .shared
    @ObservedObject var lockManager: SecurityLockManager = .shared
    @Binding var isPresented: Bool

    public init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 16))
                    Text("Settings")
                        .font(.title3.weight(.bold))
                }
                Spacer()
                Button("Done") {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Scrollable Settings Content
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 22) {
                    
                    // MARK: - 1. Phone Screen
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Phone screen")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.primary)

                        VStack(alignment: .leading, spacing: 12) {
                            Toggle(isOn: $appState.turnPhoneScreenOff) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Start with phone screen off (Privacy mode)")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.primary)
                                    Text("Keeps the phone display dark when mirroring starts. While off, video, touch, and keyboard from your Mac keep working.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .toggleStyle(.checkbox)

                            Divider()

                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.blue)
                                    .font(.system(size: 13))
                                    .padding(.top, 1)

                                Text("By default, the phone screen stays ON and mirrors what you do on Mac, following its normal sleep timeout. You can turn the display on or off at any time using the toolbar button.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(16)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(10)
                    }

                    // MARK: - 2. Security
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Security")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.primary)

                        VStack(alignment: .leading, spacing: 14) {
                            if lockManager.isTouchIDAvailable {
                                Toggle(isOn: $lockManager.isTouchIDEnabled) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "touchid")
                                                .foregroundColor(.blue)
                                            Text("Unlock with Touch ID")
                                                .font(.system(size: 13, weight: .medium))
                                        }
                                        Text("Use Touch ID biometric sensor on your Mac to unlock Phone Mirroring.")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                .toggleStyle(.checkbox)

                                Divider()
                            }

                            Toggle(isOn: $lockManager.lockOnSleep) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Lock when Mac sleeps or screen locks")
                                        .font(.system(size: 13, weight: .medium))
                                    Text("Locks the app whenever macOS goes to sleep or the display is locked.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .toggleStyle(.checkbox)

                            Divider()

                            // Change Master Password Accordion
                            VStack(alignment: .leading, spacing: 10) {
                                Button(action: {
                                    appState.showChangePasswordSection.toggle()
                                }) {
                                    HStack {
                                        Image(systemName: "key.fill")
                                            .foregroundColor(.blue)
                                        Text(appState.showChangePasswordSection ? "Hide Change Password" : "Change Master Password")
                                            .font(.system(size: 13, weight: .medium))
                                        Spacer()
                                        Image(systemName: appState.showChangePasswordSection ? "chevron.up" : "chevron.down")
                                            .foregroundColor(.secondary)
                                            .font(.system(size: 11))
                                    }
                                }
                                .buttonStyle(.plain)

                                if appState.showChangePasswordSection {
                                    VStack(alignment: .leading, spacing: 10) {
                                        SecureField("Current master password", text: $appState.changeCurrentPassInput)
                                            .textFieldStyle(.roundedBorder)
                                        SecureField("New password (min 6 characters)", text: $appState.changeNewPassInput)
                                            .textFieldStyle(.roundedBorder)
                                        SecureField("Confirm new password", text: $appState.changeConfirmPassInput)
                                            .textFieldStyle(.roundedBorder)

                                        if let msg = appState.changePasswordMessage {
                                            Text(msg)
                                                .font(.caption)
                                                .foregroundColor(msg.contains("Successfully") ? .green : .red)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }

                                        Button("Update Password") {
                                            let res = lockManager.changePassword(
                                                current: appState.changeCurrentPassInput,
                                                newPass: appState.changeNewPassInput,
                                                confirmPass: appState.changeConfirmPassInput
                                            )
                                            if res.success {
                                                appState.changePasswordMessage = "Successfully updated master password!"
                                                appState.changeCurrentPassInput = ""
                                                appState.changeNewPassInput = ""
                                                appState.changeConfirmPassInput = ""
                                            } else {
                                                appState.changePasswordMessage = res.error ?? "Failed to change password."
                                            }
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .disabled(appState.changeCurrentPassInput.isEmpty || appState.changeNewPassInput.count < 6 || appState.changeConfirmPassInput.isEmpty)
                                    }
                                    .padding(12)
                                    .background(Color.black.opacity(0.04))
                                    .cornerRadius(8)
                                }
                            }
                        }
                        .padding(16)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(10)
                    }

                    // MARK: - 3. Auto-lock
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Auto-lock")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.primary)

                        VStack(alignment: .leading, spacing: 14) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Auto-lock after inactivity:")
                                        .font(.system(size: 13, weight: .medium))
                                    Spacer()
                                    Picker("", selection: $lockManager.autoLockMinutes) {
                                        Text("Immediately").tag(0)
                                        Text("1 minute").tag(1)
                                        Text("5 minutes").tag(5)
                                        Text("15 minutes (Recommended)").tag(15)
                                        Text("Never while a phone is mirrored").tag(-1)
                                    }
                                    .pickerStyle(.menu)
                                    .frame(minWidth: 230)
                                }

                                Text("While a phone is actively mirrored in the frontmost window, auto-lock from inactivity is automatically paused.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Divider()

                            Toggle(isOn: Binding(
                                get: { lockManager.disconnectWhenLocked },
                                set: { lockManager.disconnectWhenLocked = $0 }
                            )) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Disconnect mirroring when app locks")
                                        .font(.system(size: 13, weight: .medium))
                                    Text("Off by default: leaves the mirror stream running in the background behind the lock screen until you unlock.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .toggleStyle(.checkbox)

                            Divider()

                            Toggle(isOn: $lockManager.gracePeriodEnabled) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Grace period (1 minute)")
                                        .font(.system(size: 13, weight: .medium))
                                    Text("If the app locked less than 1 minute ago, Touch ID unlocks immediately without retyping your password.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                        .padding(16)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(10)
                    }

                    // MARK: - 4. Danger zone (Reset app)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Danger zone")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.red)

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Resetting the app erases your master password and forgets all paired phones. You will need to pair your phone again.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Button(action: {
                                appState.showResetConfirmation = true
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "trash.fill")
                                    Text("Reset App and Forget Devices")
                                }
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.red)
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(16)
                        .background(Color.red.opacity(0.06))
                        .cornerRadius(10)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
        }
        .frame(minWidth: 540, idealWidth: 580, maxWidth: 680, minHeight: 620, idealHeight: 700)
        .alert(isPresented: $appState.showResetConfirmation) {
            Alert(
                title: Text("Reset Phone Mirroring?"),
                message: Text("All saved paired devices and your master password will be erased immediately."),
                primaryButton: .destructive(Text("Reset Everything")) {
                    lockManager.resetApp()
                    isPresented = false
                    appState.showResetConfirmation = false
                },
                secondaryButton: .cancel() {
                    appState.showResetConfirmation = false
                }
            )
        }
    }
}
