import SwiftUI

struct MainTabView: View {
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            ContentView()
                .tag(0)
                .tabItem { Label("Photos", systemImage: "photo.on.rectangle") }

            AIView()
                .tag(1)
                .tabItem { Label("IA", systemImage: "sparkles") }

            SettingsView()
                .tag(2)
                .tabItem { Label("Réglages", systemImage: "gearshape") }
        }
        .sensoryFeedback(trigger: tab) { _, _ in
            Haptics.enabled ? .selection : nil
        }
    }
}
