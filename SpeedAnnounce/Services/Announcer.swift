import AVFoundation

/// Speaks announcements through the current audio route (AirPods, CarPlay, speaker),
/// ducking other audio such as music or podcasts while speaking.
// Only used from the main thread; the delegate callbacks just schedule work on main.
final class Announcer: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let synthesizer = AVSpeechSynthesizer()
    private let session = AVAudioSession.sharedInstance()
    private var tonePlayer: AVAudioPlayer?
    private lazy var toneData = Self.makeWarningTone()

    var speechRate: Float = AVSpeechUtteranceDefaultSpeechRate
    var voice = AVSpeechSynthesisVoice(language: "da-DK") ?? AVSpeechSynthesisVoice(language: nil)

    override init() {
        super.init()
        synthesizer.delegate = self
        try? session.setCategory(.playback, mode: .voicePrompt,
                                 options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
    }

    func announce(_ event: AnnouncementPolicy.Event, withTone: Bool = false) {
        switch event {
        case .limitChanged(let limit):
            speak(Self.text(for: limit, prefix: "Fartgrænse"))
        case .periodic(let limit):
            speak(Self.text(for: limit, prefix: "Fartgrænsen er"))
        case .speeding(let limit, _):
            speak("For hurtigt. Grænsen er \(limit).", interrupt: true, tone: withTone)
        case .limitLost:
            break
        }
    }

    func speak(_ text: String, interrupt: Bool = false, tone: Bool = false) {
        if interrupt, synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .word)
        }
        try? session.setActive(true)

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = speechRate
        if tone, let player = try? AVAudioPlayer(data: toneData) {
            tonePlayer = player
            player.play()
            utterance.preUtteranceDelay = player.duration + 0.1
        }
        synthesizer.speak(utterance)
    }

    static func text(for limit: AnnouncementPolicy.Limit, prefix: String) -> String {
        switch limit {
        case .kmh(let value): return "\(prefix) \(value)"
        case .unlimited: return "Ingen fartgrænse"
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        deactivateIfIdle()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        deactivateIfIdle()
    }

    /// Lets music return to full volume once nothing is queued.
    private func deactivateIfIdle() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, !self.synthesizer.isSpeaking else { return }
            try? self.session.setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    /// Two short beeps as 16-bit mono WAV.
    private static func makeWarningTone() -> Data {
        let sampleRate = 22_050
        let beep = 0.15, gap = 0.08, frequency = 1_000.0
        var samples: [Int16] = []
        for index in 0..<2 {
            for n in 0..<Int(beep * Double(sampleRate)) {
                let t = Double(n) / Double(sampleRate)
                let envelope = min(1, min(t, beep - t) / 0.01)
                samples.append(Int16(sin(2 * .pi * frequency * t) * envelope * 0.6 * Double(Int16.max)))
            }
            if index == 0 {
                samples.append(contentsOf: repeatElement(0, count: Int(gap * Double(sampleRate))))
            }
        }

        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let byteCount = samples.count * 2
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + byteCount))
        data.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16))
        append(UInt16(1)); append(UInt16(1)); append(UInt32(sampleRate)); append(UInt32(sampleRate * 2))
        append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(UInt32(byteCount))
        samples.forEach { append($0) }
        return data
    }
}
