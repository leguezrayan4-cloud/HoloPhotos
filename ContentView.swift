import SwiftUI

struct ContentView: View {
    let photos = ["Vacances 2025", "Captures d'écran", "Montage YouTube", "Corbeille"]

    var body: some View {
        NavigationStack {
            List(photos, id: \.self) { album in
                Text(album)
            }
            .navigationTitle("HoloPhotos")
        }
    }
}
