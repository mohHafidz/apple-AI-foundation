//
//  SpeechService.swift
//  sesi hackton
//
//  Created by Training-58 on 17/10/26.
//

import AVFoundation
import Combine
import Foundation

@MainActor
final class SpeechService: NSObject, ObservableObject,
    AVSpeechSynthesizerDelegate
{
    @Published var isSpeaking: Bool = false

    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speakIndonesian(_ text: String) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)

        // Mencari voice Bahasa Indonesia terbaik yang terpasang di macOS
        if let indoVoice = AVSpeechSynthesisVoice.speechVoices().first(where: {
            $0.language == "id-ID" && $0.quality == .enhanced
        }) {
            utterance.voice = indoVoice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "id-ID")
        }

        utterance.rate = 0.49
        utterance.pitchMultiplier = 1.03
        utterance.postUtteranceDelay = 0.1

        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }

    // MARK: - AVSpeechSynthesizerDelegate
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }
}
