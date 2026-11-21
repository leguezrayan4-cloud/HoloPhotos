import SwiftUI

struct BackupView: View {
    @EnvironmentObject private var backup: BackupManager

    @AppStorage("backupAuto") private var autoBackup = false
    @AppStorage("backupWiFiOnly") private var wifiOnly = true
    @AppStorage("backupVideos") private var includeVideos = true
    @AppStorage("backupQuality") private var quality = "original"

    @State private var confirmSignOut = false
    @State private var confirmRestore = false

    var body: some View {
        List {
            if !DriveConfig.isConfigured {
                notConfiguredSection
            } else if !backup.auth.isSignedIn {
                signInSection
            } else {
                accountSection
                statusSection
                optionsSection
                restoreSection
            }
        }
        .navigationTitle("Sauvegarde Google Drive")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { backup.dismissMessage() }
        .confirmationDialog("Se déconnecter de Google ?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Se déconnecter", role: .destructive) {
                Task { await backup.auth.signOut() }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Tes fichiers déjà envoyés restent dans ton Drive.")
        }
        .confirmationDialog("Restaurer sur cet iPhone ?", isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("Restaurer") { backup.restoreMissing() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Les photos et vidéos de ton Drive absentes de cet iPhone seront ajoutées à ta galerie.")
        }
    }

    // MARK: - Sections

    private var notConfiguredSection: some View {
        Section {
            ContentUnavailableView {
                Label("Google Drive non configuré", systemImage: "externaldrive.badge.exclamationmark")
            } description: {
                Text("Ajoute l'ID client Google dans DriveConfig.swift, puis recompile l'app.")
            }
        }
    }

    private var signInSection: some View {
        Group {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "icloud.and.arrow.up")
                        .font(.system(size: 44))
                        .foregroundStyle(.purple)
                    Text("Sauvegarde tes photos")
                        .font(.title3.bold())
                    Text("Connecte ton compte Google : HoloPhotos enverra une copie de tes photos et vidéos dans un dossier « \(DriveConfig.folderName) » de ton Google Drive. Tu pourras les retrouver sur un autre iPhone.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section {
                Button {
                    Task { await backup.auth.signIn() }
                } label: {
                    HStack {
                        Spacer()
                        if backup.auth.isBusy {
                            ProgressView()
                        } else {
                            Text("Se connecter avec Google").font(.headline)
                        }
                        Spacer()
                    }
                }
                .disabled(backup.auth.isBusy)

                if let error = backup.auth.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            } footer: {
                Text("Les fichiers utilisent l'espace de ton compte Google (15 Go gratuits, partagés avec Gmail et Drive). HoloPhotos ne voit que les fichiers qu'elle a elle-même envoyés.")
            }
        }
    }

    private var accountSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text(backup.auth.email ?? "Compte Google")
                        .font(.headline)
                    Text("Connecté à Google Drive")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Déconnexion") { confirmSignOut = true }
                    .font(.footnote)
                    .buttonStyle(.bordered)
            }
        }
    }

    private var statusSection: some View {
        Section {
            switch backup.state {
            case .scanning:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Analyse de ta galerie…")
                }
            case .uploading(let done, let total):
                progressRow(title: "Envoi en cours", done: done, total: total)
            case .restoring(let done, let total):
                progressRow(title: "Restauration en cours", done: done, total: total)
            case .finished(let message):
                Label(message, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            case .idle:
                if let last = backup.lastBackup {
                    LabeledContent("Dernière sauvegarde") {
                        Text(last, format: .dateTime.day().month().hour().minute())
                    }
                } else {
                    Text("Aucune sauvegarde pour l'instant.")
                        .foregroundStyle(.secondary)
                }
            }

            if backup.isRunning {
                Button("Arrêter", role: .destructive) { backup.cancel() }
            } else {
                Button {
                    backup.backupNow()
                } label: {
                    Label("Sauvegarder maintenant", systemImage: "icloud.and.arrow.up")
                }
            }
        } header: {
            Text("Sauvegarde")
        } footer: {
            Text("Garde l'app ouverte pendant l'envoi. Si tu la quittes, la sauvegarde reprend au prochain lancement.")
        }
    }

    private var optionsSection: some View {
        Section {
            Toggle("Sauvegarde automatique", isOn: $autoBackup)
            Toggle("Wi-Fi uniquement", isOn: $wifiOnly)
            Toggle("Inclure les vidéos", isOn: $includeVideos)
            Picker("Qualité des photos", selection: $quality) {
                Text("Originales").tag("original")
                Text("Optimisées").tag("optimized")
            }
        } header: {
            Text("Options")
        } footer: {
            Text("Optimisées : photos réduites (2048 px) pour économiser ton espace Google. Les vidéos sont toujours envoyées en version originale. Ton album privé et les éléments supprimés ne sont jamais envoyés.")
        }
    }

    private var restoreSection: some View {
        Section {
            Button {
                confirmRestore = true
            } label: {
                Label("Restaurer les photos manquantes", systemImage: "arrow.down.circle")
            }
            .disabled(backup.isRunning)
        } header: {
            Text("Restauration")
        } footer: {
            Text("Utile sur un nouvel iPhone : récupère depuis ton Drive les photos et vidéos qui ne sont pas déjà dans ta galerie.")
        }
    }

    private func progressRow(title: String, done: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text("\(done) / \(total)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(done), total: Double(max(total, 1)))
        }
    }
}
