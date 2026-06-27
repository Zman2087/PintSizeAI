import Flutter
import Speech
import AVFoundation

/// Flutter plugin for voice input (STT) and voice output (TTS).
///
/// MethodChannel   pintsize/voice       — startListening, stopListening,
///                                        speak, stopSpeaking, setRate
/// EventChannel    pintsize/voice_text  — streams partial + final transcripts
///                                        as {text: String, isFinal: Bool}
final class VoicePlugin: NSObject {

    static func register(with messenger: FlutterBinaryMessenger) {
        let plugin = VoicePlugin()
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

    // ── TTS ───────────────────────────────────────────────────────────────────
    private let synthesizer = AVSpeechSynthesizer()
    private var speechRate: Float = AVSpeechUtteranceDefaultSpeechRate

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
            stopListening()
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
        stopListening()

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            result(FlutterError(code: "AUDIO_SESSION",
                                message: error.localizedDescription, details: nil))
            return
        }

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
                    self.eventSink?([
                        "text": text,
                        "isFinal": isFinal,
                    ])
                }
                if isFinal { self.stopListening() }
            } else if let err = err {
                DispatchQueue.main.async {
                    self.eventSink?(FlutterError(code: "STT_ERROR",
                                                  message: err.localizedDescription,
                                                  details: nil))
                }
                self.stopListening()
            }
        }

        result(nil)
    }

    private func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false,
              options: .notifyOthersOnDeactivation)
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
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
        synthesizer.speak(utterance)
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
        stopListening()
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
