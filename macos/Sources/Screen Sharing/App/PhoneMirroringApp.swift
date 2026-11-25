import SwiftUI
import AppKit

@main
struct PhoneMirroringApp: App {
    @ObservedObject var appState: AppState = .shared
    @ObservedObject var lockManager: SecurityLockManager = .shared

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup {
            RootLockContainerView()
                .preferredColorScheme(.dark)
                .frame(minWidth: 540, minHeight: 520)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandGroup(after: .appInfo) {
                Button("Settings...") {
                    appState.showSettingsSheet = true
                }
                .keyboardShortcut(",", modifiers: [.command])

                Button("Lock Phone Mirroring") {
                    lockManager.lockApp()
                }
                .keyboardShortcut("l", modifiers: [.command])
                .disabled(lockManager.lockState != .unlocked)
            }

            CommandMenu("Device") {
                Button("Discover Devices") {
                    appState.navigate(to: .devices)
                }
                .keyboardShortcut("d", modifiers: [.command])
                .disabled(lockManager.lockState != .unlocked)

                Button("Disconnect") {
                    Task { await appState.disconnect() }
                }
                .keyboardShortcut("w", modifiers: [.command])
                .disabled(appState.currentScreen != .mirror || lockManager.lockState != .unlocked)
            }
        }
    }
}

struct RootLockContainerView: View {
    @ObservedObject var lockManager: SecurityLockManager = .shared
    @ObservedObject var appState: AppState = .shared

    var body: some View {
        Group {
            switch lockManager.lockState {
            case .setupRequired:
                AppLockSetupView()
            case .locked:
                AppLockScreenView()
            case .unlocked:
                ContentView()
            }
        }
        .sheet(isPresented: $appState.showSettingsSheet) {
            SettingsSheetView(isPresented: $appState.showSettingsSheet)
        }
    }
}

struct ContentView: View {
    @ObservedObject var appState: AppState = .shared

    var body: some View {
        Group {
            switch appState.currentScreen {
            case .home:
                HomeView()
            case .devices:
                DeviceDiscoveryView()
            case .mirror:
                MirrorWindowView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.currentScreen)
    }
}

