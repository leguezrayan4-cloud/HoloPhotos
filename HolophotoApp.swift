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
    @AppStorage("offeredDriveFor") private var offeredDriveFor = ""
    @State private var offerDrive = false

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
            .sheet(isPresented: $auth.needsName) {
                NameSetupView()
                    .environmentObject(auth)
            }
            .alert("Connecter Google Drive ?", isPresented: $offerDrive) {
                Button("Connecter") {
                    Task { await backup.auth.signIn() }
                }
                Button("Plus tard", role: .cancel) {}
            } message: {
                Text("Pour sauvegarder tes photos sur Google Drive. Tu peux le faire plus tard dans Réglages.")
            }
            .onChange(of: auth.isSignedIn) { _, signedIn in
                // Proposé une fois par compte, seulement si Drive n'est pas déjà connecté
                guard signedIn, !backup.auth.isSignedIn, let uid = auth.user?.uid else { return }
                if offeredDriveFor != uid {
                    offeredDriveFor = uid
                    offerDrive = true
                }
            }
            .onOpenURL { url in
                GIDSignIn.sharedInstance.handle(url)
            }
        }
    }
}
