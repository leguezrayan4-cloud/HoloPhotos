import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var page = 0

    private let pages: [(icon: String, title: String, text: String)] = [
        ("photo.on.rectangle", "Ta galerie, rangée",
         "Parcours tes photos et vidéos. Pince l'écran pour changer le nombre de photos par ligne."),
        ("sparkles", "Une IA qui te connaît",
         "Dans l'onglet IA, pose tes questions. Ton PC peut faire tourner l'IA en local, sans rien envoyer ailleurs."),
        ("lock.fill", "Un coffre privé",
         "Crée un album protégé par Face ID ou le code de ton téléphone, pour tes photos les plus personnelles."),
    ]

    var body: some View {
        VStack(spacing: 24) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    VStack(spacing: 20) {
                        Image(systemName: pages[index].icon)
                            .font(.system(size: 64))
                            .foregroundStyle(.purple)
                        Text(pages[index].title)
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                        Text(pages[index].text)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .padding(32)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            Button {
                if page < pages.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    onFinish()
                }
            } label: {
                Text(page < pages.count - 1 ? "Continuer" : "Commencer")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 32)
            .padding(.bottom, 16)
        }
    }
}
