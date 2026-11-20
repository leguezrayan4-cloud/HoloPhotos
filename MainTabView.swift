import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            ContentView()
                .tabItem { Label("Photos", systemImage: "photo.on.rectangle") }

            AIView()
                .tabItem { Label("IA", systemImage: "sparkles") }

            SettingsView()
                .tabItem { Label("Réglages", systemImage: "gearshape") }
        }
    }
}
