import GoogleSignIn
import SwiftUI

@main
struct HolophotoApp: App {
    @StateObject private var library = PhotoLibrary()
    @StateObject private var auth = AuthStore()
    @StateObject private var backup = BackupManager()
    @AppStorage("appearance") private var appearance = "system"
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("lockApp") private var lockApp = false
    @State private var locked = false
    @AppStorage("onboardingDone") private var onboardingDone = false

    private var colorScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                MainTabView()
                    .environmentObject(library)
                    .environmentObject(auth)
                    .environmentObject(backup)

                if locked {
                    AppLockView {
                        locked = false
                    }
                    .transition(.opacity)
                }
            }
            .preferredColorScheme(colorScheme)
            .onAppear {
                locked = lockApp
            }
            .fullScreenCover(isPresented: Binding(
                get: { !onboardingDone },
                set: { if !$0 { onboardingDone = true } }
            )) {
                OnboardingView {
                    onboardingDone = true
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background && lockApp {
                    locked = true
                }
                if phase == .active {
                    library.checkAccess()
                    library.purgeExpired()
                    backup.autoRunIfNeeded()
                }
            }
            .onOpenURL { url in
                GIDSignIn.sharedInstance.handle(url)
            }
        }
    }
}
