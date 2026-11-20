import SwiftUI

@main
struct HolophotoApp: App {
    @StateObject private var library = PhotoLibrary()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(library)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        library.checkAccess()
                        library.purgeExpired()
                    }
                }
        }
    }
}
