import SwiftUI

@main
struct HolophotoApp: App {
    @StateObject private var library = PhotoLibrary()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(library)
        }
    }
}
