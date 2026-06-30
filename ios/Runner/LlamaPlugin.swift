import Flutter
import Foundation

/// Bridges LlamaEngine to Flutter.
///
/// MethodChannel  pintsize/llama       — loadModel, unloadModel, cancelGeneration
/// EventChannel   pintsize/llama_stream — streams one String token per event,
///                                        ends with FlutterEndOfEventStream
final class LlamaPlugin: NSObject {

    private let engine = LlamaEngine()
    private var eventSink: FlutterEventSink?

    // Call once from AppDelegate after the engine is running.
    static func register(with messenger: FlutterBinaryMessenger) -> LlamaPlugin {
        let plugin = LlamaPlugin()

        FlutterMethodChannel(name: "pintsize/llama", binaryMessenger: messenger)
            .setMethodCallHandler(plugin.handleMethodCall(_:result:))

        FlutterEventChannel(name: "pintsize/llama_stream", binaryMessenger: messenger)
            .setStreamHandler(plugin)

        return plugin
    }

    // ── MethodChannel handler ─────────────────────────────────────────────────

    private func handleMethodCall(_ call: FlutterMethodCall,
                                  result: @escaping FlutterResult) {
        switch call.method {

        case "loadModel":
            guard let args = call.arguments as? [String: Any],
                  let path = args["path"] as? String else {
                result(FlutterError(code: "BAD_ARGS",
                                    message: "loadModel requires {path: String}",
                                    details: nil))
                return
            }
            let contextLength = args["contextLength"] as? Int ?? 2048

            // Load on a background thread — can take several seconds for large models
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    // Swift bridges the ObjC NSError** pattern to throws automatically
                    try self.engine.loadModel(atPath: path, contextLength: contextLength)
                    DispatchQueue.main.async { result(nil) }
                } catch {
                    DispatchQueue.main.async {
                        result(FlutterError(
                            code: "LOAD_FAILED",
                            message: error.localizedDescription,
                            details: nil
                        ))
                    }
                }
            }

        case "loadProjector":
            guard let args = call.arguments as? [String: Any],
                  let path = args["path"] as? String else {
                result(FlutterError(code: "BAD_ARGS",
                                    message: "loadProjector requires {path: String}",
                                    details: nil))
                return
            }
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try self.engine.loadMultimodalProjector(atPath: path)
                    DispatchQueue.main.async { result(nil) }
                } catch {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "PROJECTOR_FAILED",
                                            message: error.localizedDescription,
                                            details: nil))
                    }
                }
            }

        case "hasVision":
            result(engine.hasVision)

        case "applyChatTemplate":
            guard let args = call.arguments as? [String: Any],
                  let messages = args["messages"] as? [[String: String]] else {
                result(FlutterError(code: "BAD_ARGS",
                                    message: "applyChatTemplate requires {messages: [...]}",
                                    details: nil))
                return
            }
            let addAss = args["addAssistant"] as? Bool ?? true
            let formatted = engine.applyChatTemplate(messages, addAssistant: addAss)
            result(formatted)

        case "unloadModel":
            engine.unload()
            result(nil)

        case "cancelGeneration":
            engine.cancelGeneration()
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

// ── EventChannel — streaming tokens ──────────────────────────────────────────

extension LlamaPlugin: FlutterStreamHandler {

    /// Called when Dart subscribes to the event channel.
    /// arguments must contain at least {prompt: String}.
    func onListen(withArguments arguments: Any?,
                  eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events

        guard let args = arguments as? [String: Any],
              let prompt = args["prompt"] as? String else {
            return FlutterError(code: "BAD_ARGS",
                                message: "generate requires {prompt: String}",
                                details: nil)
        }

        let maxTokens  = args["maxTokens"]   as? Int   ?? 512
        let temperature = args["temperature"] as? Float ?? 0.7
        let topP        = args["topP"]        as? Float ?? 0.9
        let imageData = (args["imageBytes"] as? FlutterStandardTypedData)?.data

        let onToken = { [weak self] (token: String?, isDone: Bool, error: Error?) in
            // Already dispatched to main thread by LlamaEngine
            guard let sink = self?.eventSink else { return }

            if let error = error {
                sink(FlutterError(code: "GEN_ERROR",
                                  message: error.localizedDescription,
                                  details: nil))
                self?.eventSink = nil
                return
            }

            if isDone {
                sink(FlutterEndOfEventStream)
                self?.eventSink = nil
                return
            }

            if let token = token {
                sink(token)
            }
        }

        if let imageData = imageData {
            engine.generate(withPrompt: prompt,
                            imageData: imageData,
                            maxTokens: maxTokens,
                            temperature: temperature,
                            topP: topP,
                            tokenHandler: onToken)
        } else {
            engine.generate(withPrompt: prompt,
                            maxTokens: maxTokens,
                            temperature: temperature,
                            topP: topP,
                            tokenHandler: onToken)
        }

        return nil
    }

    /// Called when Dart cancels the stream subscription.
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        engine.cancelGeneration()
        eventSink = nil
        return nil
    }
}
