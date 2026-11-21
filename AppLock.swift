import SwiftUI

// Écran de verrouillage de l'app : Face ID ou code du téléphone
struct AppLockView: View {
    let onUnlock: () -> Void
    @State private var message: String?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("HoloPhotos est verrouillée")
                .font(.title3.bold())
            Button("Déverrouiller") {
                authenticate()
            }
            .buttonStyle(.borderedProminent)
            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground).ignoresSafeArea())
        .onAppear { authenticate() }
    }

    private func authenticate() {
        Vault.authenticate { ok in
            if ok {
                message = nil
                Haptics.success()
                onUnlock()
            } else {
                message = "Déverrouillage refusé."
            }
        }
    }
}
