import SwiftUI

struct ContentView: View {
    @StateObject private var library = PhotoLibrary()
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 2)]

    var body: some View {
        NavigationStack {
            Group {
                if library.authorized {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(library.assets, id: \.localIdentifier) { asset in
                                NavigationLink {
                                    FullPhotoView(asset: asset)
                                } label: {
                                    ThumbnailView(asset: asset)
                                }
                            }
                        }
                    }
                } else {
                    VStack(spacing: 16) {
                        Text("HoloPhotos a besoin d'accéder à tes photos.")
                        Button("Autoriser l'accès") {
                            library.requestAccess()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("HoloPhotos")
        }
        .onAppear {
            library.checkAccess()
        }
    }
}
