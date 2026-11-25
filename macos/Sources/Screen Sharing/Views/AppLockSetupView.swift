import SwiftUI

public struct AppLockSetupView: View {
    @ObservedObject var lockManager: SecurityLockManager = .shared

    public init() {}

    public var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Header Icon
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 72, height: 72)
                Image(systemName: "lock.shield.fill")
                    .foregroundColor(.blue)
                    .font(.system(size: 34))
            }

            VStack(spacing: 6) {
                Text("Secure Phone Mirroring")
                    .font(.system(size: 20, weight: .bold))
                Text("Set up a master password to protect your phone screen, controls, and wireless debugging sessions.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            // Input Fields
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Master Password (min 6 characters)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    SecureField("Enter master password", text: $lockManager.setupPasswordInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 14))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Confirm Password")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    SecureField("Re-enter master password", text: $lockManager.setupConfirmInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 14))
                }

                if lockManager.isTouchIDAvailable {
                    Toggle(isOn: $lockManager.setupTouchIDToggle) {
                        HStack(spacing: 8) {
                            Image(systemName: "touchid")
                                .foregroundColor(.blue)
                                .font(.system(size: 16))
                            Text("Use Touch ID to unlock")
                                .font(.system(size: 13))
                        }
                    }
                    .toggleStyle(.checkbox)
                    .padding(.top, 4)
                }
            }
            .frame(width: 340)

            // Error display
            if let err = lockManager.setupErrorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.red)
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            // Submit Button
            Button(action: {
                _ = lockManager.setInitialPassword(
                    password: lockManager.setupPasswordInput,
                    confirm: lockManager.setupConfirmInput,
                    enableTouchID: lockManager.setupTouchIDToggle
                )
            }) {
                Text("Set Password & Continue")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 200, height: 32)
            }
            .buttonStyle(.borderedProminent)
            .disabled(lockManager.setupPasswordInput.count < 6 || lockManager.setupConfirmInput.isEmpty)

            Spacer()

            Text("Your password is never sent to the cloud. Salted PBKDF2 hash is stored securely in Keychain.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
                .padding(.bottom, 12)
        }
        .padding(32)
        .frame(minWidth: 500, minHeight: 480)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

