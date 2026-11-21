import SwiftUI

@main
struct HolophotoApp: App {
    @StateObject private var library = PhotoLibrary()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("lockApp") private var lockApp = false
    @State private var locked = false
    @AppStorage("onboardingDone") private var onboardingDone = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                MainTabView()
                    .environmentObject(library)

                if locked {
                    AppLockView {
                        locked = false
                    }
                    .transition(.opacity)
                }
            }
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
                }
            }
        }
    }
}
