import Flutter
import Speech
import AVFoundation

/// Flutter plugin for voice input (STT) and voice output (TTS).
///
/// MethodChannel   pintsize/voice       — startListening, stopListening,
///                                        speak, stopSpeaking, setRate, isSpeaking
/// EventChannel    pintsize/voice_text  — emits maps:
///                   {type:"transcript", text:String, isFinal:Bool}
///                   {type:"speaking_done"}
///                   {type:"listening_stopped"}
final class VoicePlugin: NSObject, AVSpeechSynthesizerDelegate {

    // Keep a strong ref to self so the plugin survives after register() returns
    private static var instance: VoicePlugin?

    static func register(with messenger: FlutterBinaryMessenger) {
        let plugin = VoicePlugin()
        instance = plugin
        plugin.synthesizer.delegate = plugin
        FlutterMethodChannel(name: "pintsize/voice", binaryMessenger: messenger)
            .setMethodCallHandler(plugin.handleMethod(_:result:))
        FlutterEventChannel(name: "pintsize/voice_text", binaryMessenger: messenger)
            .setStreamHandler(plugin)
    }

    // ── STT ───────────────────────────────────────────────────────────────────
    private let recognizer = SFSpeechRecognizer(locale: .current)
    private let audioEngine  = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var eventSink: FlutterEventSink?

    // Silence detection: SFSpeechRecognizer rarely fires isFinal on its own
    // when fed a continuous mic stream, so we finalize after a pause in speech.
    private var silenceTimer: Timer?
    private var lastTranscript: String = ""
    private var didFinalize: Bool = false
    private let silenceTimeout: TimeInterval = 1.6

    // ── TTS ───────────────────────────────────────────────────────────────────
    private let synthesizer = AVSpeechSynthesizer()
    private var speechRate: Float = AVSpeechUtteranceDefaultSpeechRate
    private var selectedVoiceId: String?

    // ── MethodChannel ─────────────────────────────────────────────────────────

    private func handleMethod(_ call: FlutterMethodCall,
                              result: @escaping FlutterResult) {
        switch call.method {
        case "startListening":
            requestSpeechPermission { [weak self] granted in
                if granted {
                    self?.startListening(result: result)
                } else {
                    result(FlutterError(code: "PERMISSION_DENIED",
                                        message: "Speech recognition permission denied",
                                        details: nil))
                }
            }

        case "stopListening":
            stopListening(sendEvent: true)
            result(nil)

        case "speak":
            guard let text = call.arguments as? String else {
                result(FlutterError(code: "BAD_ARGS", message: "speak requires String", details: nil))
                return
            }
            speak(text)
            result(nil)

        case "stopSpeaking":
            synthesizer.stopSpeaking(at: .immediate)
            result(nil)

        case "setRate":
            if let rate = call.arguments as? Double {
                speechRate = Float(rate.clamped(to: 0.1...1.0))
            }
            result(nil)

        case "isSpeaking":
            result(synthesizer.isSpeaking)

        case "listVoices":
            // English voices first, then the rest; higher quality first.
            let voices = AVSpeechSynthesisVoice.speechVoices()
                .sorted { a, b in
                    if a.quality.rawValue != b.quality.rawValue {
                        return a.quality.rawValue > b.quality.rawValue
                    }
                    return a.name < b.name
                }
                .map { v -> [String: Any] in
                    let q: String
                    switch v.quality {
                    case .premium:  q = "Premium"
                    case .enhanced: q = "Enhanced"
                    default:        q = "Standard"
                    }
                    return [
                        "id": v.identifier,
                        "name": v.name,
                        "lang": v.language,
                        "quality": q,
                    ]
                }
            result(voices)

        case "setVoice":
            // nil/empty clears back to the default system voice.
            selectedVoiceId = (call.arguments as? String)?.isEmpty == false
                ? (call.arguments as? String) : nil
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // ── STT implementation ────────────────────────────────────────────────────

    private func requestSpeechPermission(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                completion(status == .authorized)
            }
        }
    }

    private func startListening(result: @escaping FlutterResult) {
        stopListening(sendEvent: false)

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            result(FlutterError(code: "AUDIO_SESSION",
                                message: error.localizedDescription, details: nil))
            return
        }

        lastTranscript = ""
        didFinalize = false

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = false
        request = req

        let inputNode = audioEngine.inputNode
        let fmt = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak req] buf, _ in
            req?.append(buf)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            result(FlutterError(code: "AUDIO_ENGINE",
                                message: error.localizedDescription, details: nil))
            return
        }

        task = recognizer?.recognitionTask(with: req) { [weak self] res, err in
            guard let self = self else { return }
            if let res = res {
                let text = res.bestTranscription.formattedString
                let isFinal = res.isFinal
                DispatchQueue.main.async {
                    self.lastTranscript = text
                    // Stream the partial transcript (never final here — we
                    // decide finality via silence detection below).
                    self.eventSink?(["type": "transcript", "text": text, "isFinal": false])
                    if isFinal {
                        self.finalizeUtterance()
                    } else {
                        // Reset the silence countdown on every new partial.
                        self.restartSilenceTimer()
                    }
                }
            } else if let err = err {
                _ = err
                DispatchQueue.main.async {
                    // If we already captured speech, finalize it rather than
                    // dropping it on a recognizer error/timeout.
                    if !self.lastTranscript.isEmpty && !self.didFinalize {
                        self.finalizeUtterance()
                    } else {
                        self.eventSink?(["type": "listening_stopped"])
                        self.stopListening(sendEvent: false)
                    }
                }
            }
        }

        result(nil)
    }

    /// (Re)starts the silence countdown. Must run on the main thread.
    private func restartSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(
            withTimeInterval: silenceTimeout, repeats: false
        ) { [weak self] _ in
            self?.finalizeUtterance()
        }
    }

    /// Emits the captured transcript as final and stops the audio session.
    /// Idempotent — guarded by didFinalize.
    private func finalizeUtterance() {
        if didFinalize { return }
        didFinalize = true
        silenceTimer?.invalidate()
        silenceTimer = nil

        let text = lastTranscript
        if !text.isEmpty {
            eventSink?(["type": "transcript", "text": text, "isFinal": true])
        }
        stopListening(sendEvent: text.isEmpty)
    }

    private func stopListening(sendEvent: Bool) {
        silenceTimer?.invalidate()
        silenceTimer = nil
        audioEngine.stop()
        if audioEngine.inputNode.numberOfInputs > 0 {
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false,
              options: .notifyOthersOnDeactivation)
        if sendEvent {
            DispatchQueue.main.async { [weak self] in
                self?.eventSink?(["type": "listening_stopped"])
            }
        }
    }

    // ── TTS implementation ────────────────────────────────────────────────────

    private func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
        try? session.setActive(true)

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = speechRate
        utterance.pitchMultiplier = 1.0
        if let id = selectedVoiceId, let v = AVSpeechSynthesisVoice(identifier: id) {
            utterance.voice = v
        } else {
            utterance.voice = VoicePlugin.bestDefaultVoice()
        }
        synthesizer.speak(utterance)
    }

    /// Picks the most natural-sounding voice: highest quality first
    /// (Premium > Enhanced > Default), preferring Australian English on ties,
    /// then any English. This avoids defaulting to a robotic Standard voice
    /// when a better one is installed.
    private static func bestDefaultVoice() -> AVSpeechSynthesisVoice? {
        let all = AVSpeechSynthesisVoice.speechVoices()
        let english = all.filter { $0.language.lowercased().hasPrefix("en") }
        let pool = english.isEmpty ? all : english
        func score(_ v: AVSpeechSynthesisVoice) -> Int {
            var s = v.quality.rawValue * 10           // quality dominates
            if v.language.lowercased().hasPrefix("en-au") { s += 3 } // prefer AU
            else if v.language.lowercased().hasPrefix("en-gb") { s += 1 }
            return s
        }
        return pool.max { a, b in score(a) < score(b) }
            ?? AVSpeechSynthesisVoice(language: Locale.current.identifier)
    }

    // ── AVSpeechSynthesizerDelegate ───────────────────────────────────────────

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(["type": "speaking_done"])
        }
    }
}

// ── EventChannel stream handler ──────────────────────────────────────────────

extension VoicePlugin: FlutterStreamHandler {
    func onListen(withArguments arguments: Any?,
                  eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        stopListening(sendEvent: false)
        eventSink = nil
        return nil
    }
}

// ─────────────────────────────────────────────────────────────────────────────

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
