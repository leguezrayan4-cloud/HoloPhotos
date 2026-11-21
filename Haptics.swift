import UIKit

// Retours haptiques dosés : un délai minimal entre deux vibrations évite le spam
@MainActor
enum Haptics {
    private static var last = Date.distantPast
    private static let minInterval: TimeInterval = 0.3

    private static func allowed() -> Bool {
        let now = Date()
        guard now.timeIntervalSince(last) >= minInterval else { return false }
        last = now
        return true
    }

    // Action légère : favori, envoi d'un message
    static func light() {
        guard allowed() else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // Action importante : suppression
    static func medium() {
        guard allowed() else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    // Réussite : déverrouillage
    static func success() {
        guard allowed() else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
