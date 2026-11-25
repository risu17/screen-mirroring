import SwiftUI

public struct AppLockScreenView: View {
    @ObservedObject var lockManager: SecurityLockManager = .shared
    @ObservedObject var appState: AppState = .shared

    public init() {}

    public var body: some View {
        VStack(spacing: 22) {
            Spacer()

            // Lock Icon
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 76, height: 76)
                Image(systemName: "lock.fill")
                    .foregroundColor(.blue)
                    .font(.system(size: 34))
            }

            VStack(spacing: 6) {
                Text("Phone Mirroring is Locked")
                    .font(.system(size: 20, weight: .bold))
                Text("Authenticate to access your Android screen and devices.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }

            // Password Field & Unlock Button
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    SecureField("Master password", text: $lockManager.passwordInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 14))
                        .frame(width: 240)
                        .disabled(lockManager.lockoutRemainingSeconds > 0)
                        .onSubmit {
                            lockManager.unlockWithPassword()
                        }

                    Button(action: {
                        lockManager.unlockWithPassword()
                    }) {
                        Text("Unlock")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(height: 24)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(lockManager.passwordInput.isEmpty || lockManager.lockoutRemainingSeconds > 0)
                }

                if let err = lockManager.errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                }
            }

            // Touch ID Action
            if lockManager.isTouchIDAvailable && lockManager.isTouchIDEnabled {
                Button(action: {
                    Task {
                        await lockManager.authenticateWithTouchID()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "touchid")
                            .font(.system(size: 16))
                        Text("Unlock with Touch ID")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(.blue)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(lockManager.lockoutRemainingSeconds > 0 || lockManager.isAuthenticating)
            }

            Spacer()

            // Bottom bar: Forgot Password (Reset)
            HStack {
                Spacer()
                Button("Forgot Password?") {
                    appState.showResetConfirmation = true
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.bottom, 12)
        }
        .padding(32)
        .frame(minWidth: 500, minHeight: 480)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            if lockManager.isTouchIDAvailable && lockManager.isTouchIDEnabled {
                Task {
                    await lockManager.authenticateWithTouchID()
                }
            }
        }
        .alert(isPresented: $appState.showResetConfirmation) {
            Alert(
                title: Text("Reset Phone Mirroring?"),
                message: Text("Because your password is never stored, it cannot be recovered. Resetting will erase your master password and forget all saved paired devices, returning to initial setup."),
                primaryButton: .destructive(Text("Reset App")) {
                    lockManager.resetApp()
                    appState.showResetConfirmation = false
                },
                secondaryButton: .cancel() {
                    appState.showResetConfirmation = false
                }
            )
        }
    }
}

