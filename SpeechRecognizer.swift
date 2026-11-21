import AVFoundation
import Speech
import SwiftUI

// Dictée vocale : parle, le texte apparaît dans la zone de message
final class SpeechRecognizer: ObservableObject {
    @Published var isRecording = false
    @Published var transcript = ""
    @Published var errorMessage: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "fr-FR"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func start() {
        errorMessage = nil
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else {
                    self.errorMessage = "Autorise la reconnaissance vocale dans Réglages > HoloPhotos."
                    return
                }
                AVAudioApplication.requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        guard granted else {
                            self.errorMessage = "Autorise le micro dans Réglages > HoloPhotos."
                            return
                        }
                        self.begin()
                    }
                }
            }
        }
    }

    func stop() {
        guard isRecording else { return }
        request?.endAudio()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        isRecording = false
    }

    private func begin() {
        guard let recognizer = self.recognizer, recognizer.isAvailable else {
            errorMessage = "La dictée vocale n'est pas disponible pour le moment."
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let newRequest = SFSpeechAudioBufferRecognitionRequest()
            newRequest.shouldReportPartialResults = true
            newRequest.addsPunctuation = true
            request = newRequest

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                newRequest.append(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()

            transcript = ""
            isRecording = true

            task = recognizer.recognitionTask(with: newRequest) { [weak self] result, error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                    }
                    if error != nil || (result?.isFinal ?? false) {
                        self.finish()
                    }
                }
            }
        } catch {
            errorMessage = "Impossible de démarrer le micro."
            finish()
        }
    }

    private func finish() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request = nil
        task = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
