import SwiftUI

struct AIView: View {
    @AppStorage("aiMode") private var aiMode = "suggestion"

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "sparkles")
                    .font(.system(size: 48))
                    .foregroundStyle(.purple)
                Text("Assistant HoloPhotos")
                    .font(.title2.bold())
                Text(aiMode == "suggestion"
                     ? "Mode suggestion : l'IA proposera, tu valideras."
                     : "Mode automatique : l'IA rangera seule, quand l'app est ouverte.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Text("L'analyse de ta galerie arrive dans la prochaine version.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("IA")
        }
    }
}
