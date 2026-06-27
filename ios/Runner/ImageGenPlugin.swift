import Flutter
import UIKit

/// Flutter plugin for on-device Stable Diffusion image generation.
/// Bridges Dart ↔ SDPipelineRunner (which is isolated behind @available(iOS 16.2, *)).
class ImageGenPlugin: NSObject, FlutterStreamHandler {

    static let methodChannelName = "pintsize/image_gen"
    static let eventChannelName  = "pintsize/image_gen_progress"

    // Stores SDPipelineRunner on iOS 16.2+ as AnyObject to avoid @available leaking here.
    private var runnerBox: AnyObject?
    private var eventSink: FlutterEventSink?

    static func register(with messenger: FlutterBinaryMessenger) {
        let method = FlutterMethodChannel(name: methodChannelName, binaryMessenger: messenger)
        let event  = FlutterEventChannel(name: eventChannelName,  binaryMessenger: messenger)
        let plugin = ImageGenPlugin()
        method.setMethodCallHandler(plugin.handle(_:result:))
        event.setStreamHandler(plugin)
    }

    // MARK: - Method dispatch

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isModelReady":
            if #available(iOS 16.2, *) {
                result((runnerBox as? SDPipelineRunner)?.isReady ?? false)
            } else {
                result(false)
            }

        case "loadModel":
            guard let args = call.arguments as? [String: Any],
                  let path = args["modelPath"] as? String else {
                result(FlutterError(code: "BAD_ARGS", message: "modelPath required", details: nil))
                return
            }
            doLoad(path: path, result: result)

        case "generate":
            guard let args = call.arguments as? [String: Any],
                  let prompt = args["prompt"] as? String else {
                result(FlutterError(code: "BAD_ARGS", message: "prompt required", details: nil))
                return
            }
            // img2img: optional source image bytes + strength
            var srcImage: CGImage? = nil
            if let rawBytes = args["sourceImageBytes"] as? FlutterStandardTypedData,
               let uiImg = UIImage(data: rawBytes.data) {
                srcImage = uiImg.cgImage
            }
            let strength = (args["strength"] as? NSNumber)?.floatValue ?? 0.7

            doGenerate(
                prompt: prompt,
                negativePrompt: args["negativePrompt"] as? String ?? "low quality, blurry",
                steps: args["steps"] as? Int ?? 20,
                guidanceScale: (args["guidanceScale"] as? NSNumber)?.floatValue ?? 7.5,
                seed: (args["seed"] as? NSNumber)?.uint32Value ?? UInt32.random(in: 0..<UInt32.max),
                frameCount: args["frameCount"] as? Int ?? 1,
                startingImage: srcImage,
                strength: strength,
                result: result
            )

        case "cancel":
            if #available(iOS 16.2, *) {
                (runnerBox as? SDPipelineRunner)?.cancelled = true
            }
            result(nil)

        case "unloadModel":
            if #available(iOS 16.2, *) {
                (runnerBox as? SDPipelineRunner)?.unload()
            }
            result(true)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Load

    private func doLoad(path: String, result: @escaping FlutterResult) {
        guard #available(iOS 16.2, *) else {
            result(FlutterError(code: "NOT_SUPPORTED",
                                message: "Requires iOS 16.2+",
                                details: nil))
            return
        }
        let runner = SDPipelineRunner()
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try runner.load(path: path)
                DispatchQueue.main.async {
                    self.runnerBox = runner
                    result(true)
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "LOAD_FAILED",
                                        message: error.localizedDescription,
                                        details: nil))
                }
            }
        }
    }

    // MARK: - Generate

    private func doGenerate(prompt: String,
                             negativePrompt: String,
                             steps: Int,
                             guidanceScale: Float,
                             seed: UInt32,
                             frameCount: Int,
                             startingImage: CGImage? = nil,
                             strength: Float = 0.7,
                             result: @escaping FlutterResult) {
        guard #available(iOS 16.2, *) else {
            result(FlutterError(code: "NOT_SUPPORTED", message: "Requires iOS 16.2+", details: nil))
            return
        }
        guard let runner = runnerBox as? SDPipelineRunner, runner.isReady else {
            result(FlutterError(code: "NOT_LOADED", message: "Call loadModel first", details: nil))
            return
        }

        runner.cancelled = false
        let sink = eventSink

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let data = try runner.generate(
                    prompt: prompt,
                    negativePrompt: negativePrompt,
                    steps: steps,
                    guidanceScale: guidanceScale,
                    seed: seed,
                    frameCount: frameCount,
                    startingImage: startingImage,
                    strength: strength,
                    onProgress: { step, total, overall in
                        DispatchQueue.main.async {
                            sink?(["step": step, "stepCount": total, "progress": overall]
                                  as [String: Any])
                        }
                    }
                )
                DispatchQueue.main.async {
                    result(FlutterStandardTypedData(bytes: data))
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "GEN_ERROR",
                                        message: error.localizedDescription,
                                        details: nil))
                }
            }
        }
    }

    // MARK: - FlutterStreamHandler

    func onListen(withArguments arguments: Any?,
                  eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
}
