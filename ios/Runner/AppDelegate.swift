// ios/Runner/AppDelegate.swift
//
// PintSizeAi AppDelegate.
//
// Registers:
//   - DevicePlugin        (hardware profiling channel)
//   - SiriBridge          (Siri IPC + deep link handler)
//   - SiriMethodChannel   (Flutter ↔ Siri answer/ready signalling)

import Flutter
import UIKit
import AppIntents

@main
@objc class AppDelegate: FlutterAppDelegate {

    // Shared engine — allows AppIntents to reach Flutter even when the app
    // is launched headlessly by the system in response to a Siri intent.
    private lazy var flutterEngine = FlutterEngine(
        name: "PintSizeAiEngine",
        project: nil,
        allowHeadlessExecution: true  // critical for background Siri handling
    )

    // Strong reference — keeps the plugin (and LlamaEngine) alive for the app lifetime
    private var llamaPlugin: LlamaPlugin?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        // Start engine before registering plugins
        flutterEngine.run()
        GeneratedPluginRegistrant.register(with: flutterEngine)

        // ── Register native plugins ──────────────────────────────────────
        DevicePlugin.register(with: flutterEngine.registrar(forPlugin: "DevicePlugin")!)
        if #available(iOS 16.2, *) {
            ImageGenPlugin.register(with: flutterEngine.binaryMessenger)
        }

        // LLM inference — llama.cpp bridge
        llamaPlugin = LlamaPlugin.register(with: flutterEngine.binaryMessenger)

        // Voice input (STT) + output (TTS)
        VoicePlugin.register(with: flutterEngine.binaryMessenger)

        // Media analysis: image understanding, background removal, PDF extraction
        MediaPlugin.register(with: flutterEngine.binaryMessenger)

        // ── Register Siri method channel ─────────────────────────────────
        let siriChannel = FlutterMethodChannel(
            name: "com.mypocketai/siri",
            binaryMessenger: flutterEngine.binaryMessenger
        )

        siriChannel.setMethodCallHandler { [weak self] call, result in
            switch call.method {

            case "answerReady":
                // Flutter has finished generating — write answer to App Groups
                guard let answer = call.arguments as? String else {
                    result(FlutterError(code: "BAD_ARGS", message: nil, details: nil))
                    return
                }
                SiriBridge.shared.receiveAnswer(answer)
                result(nil)

            case "modelLoaded":
                // Flutter signals that a model is loaded and ready for inference
                let ready = (call.arguments as? Bool) ?? false
                SiriBridge.shared.setModelReady(ready)
                result(nil)

            default:
                result(FlutterMethodNotImplemented)
            }
        }

        // Listen for internal Siri question notifications and forward to Flutter
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("PintSizeAiSiriQuestion"),
            object: nil,
            queue: .main
        ) { notification in
            guard let question = notification.object as? String else { return }
            siriChannel.invokeMethod("siriQuestion", arguments: question)
        }

        // Set up the bridge
        SiriBridge.shared.setup(binaryMessenger: flutterEngine.binaryMessenger)

        // ── Root view controller ─────────────────────────────────────────
        let controller = FlutterViewController(
            engine: flutterEngine,
            nibName: nil,
            bundle: nil
        )
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = controller
        window?.makeKeyAndVisible()

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // ── Deep link handling ────────────────────────────────────────────────

    override func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        // Handle mypocketai://siri?q=... deep links from the intent fallback
        if let question = SiriBridge.questionFromURL(url) {
            let siriChannel = FlutterMethodChannel(
                name: "com.mypocketai/siri",
                binaryMessenger: flutterEngine.binaryMessenger
            )
            siriChannel.invokeMethod("siriQuestion", arguments: question)
            return true
        }
        return super.application(app, open: url, options: options)
    }
}
