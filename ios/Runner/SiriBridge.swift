// ios/Runner/SiriBridge.swift
//
// Dart ↔ Siri IPC bridge running inside the main app process.
//
// Responsibilities:
//   1. Listen for Darwin notifications posted by AskPintSizeAiIntent.
//   2. Read the pending question from the App Groups shared container.
//   3. Forward the question to Flutter via MethodChannel.
//   4. Receive the generated answer from Flutter.
//   5. Write the answer back to App Groups so the intent can read it.
//   6. Handle deep-link URLs (mypocketai://siri?q=...) when the app is opened
//      by the intent's fallback path.
//   7. Signal app readiness (model loaded flag) so the intent knows whether
//      to attempt IPC or fall back to deep-linking.
//
// Register in AppDelegate.swift:
//   SiriBridge.shared.setup(flutterEngine: flutterEngine)

import Foundation
import UIKit

@objc class SiriBridge: NSObject {

    @objc static let shared = SiriBridge()

    private let kAppGroupID  = "group.com.mypocketai.app"
    private let kQuestionKey = "siri_pending_question"
    private let kAnswerKey   = "siri_latest_answer"
    private let kReadyKey    = "siri_app_ready"
    private let kChannelName = "com.mypocketai/siri"

    private var channel: Any? // FlutterMethodChannel — typed as Any to avoid import
    private var defaults: UserDefaults?

    // ── Setup ──────────────────────────────────────────────────────────────

    /// Call once from AppDelegate after the Flutter engine is running.
    func setup(binaryMessenger: Any) {
        defaults = UserDefaults(suiteName: kAppGroupID)

        // Register Flutter method channel
        // (Using NSObject to avoid direct FlutterMethodChannel import here —
        //  see AppDelegate for the typed setup.)
        registerDarwinNotificationObserver()
    }

    // ── Darwin notification (background wake) ──────────────────────────────

    private func registerDarwinNotificationObserver() {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passRetained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let bridge = Unmanaged<SiriBridge>
                    .fromOpaque(observer).takeUnretainedValue()
                bridge.handleSiriQuestion()
            },
            "com.mypocketai.siri.question" as CFString,
            nil,
            .deliverImmediately
        )
    }

    @objc private func handleSiriQuestion() {
        guard let question = defaults?.string(forKey: kQuestionKey),
              !question.isEmpty else { return }

        // Clear the question so we don't re-process on next launch
        defaults?.removeObject(forKey: kQuestionKey)
        defaults?.synchronize()

        // Forward to Flutter on the main thread
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name("PintSizeAiSiriQuestion"),
                object: question
            )
        }
    }

    // ── Answer from Flutter ────────────────────────────────────────────────

    /// Called by Flutter (via MethodChannel) when inference is complete.
    /// Writes the answer to App Groups so the waiting Siri intent can read it.
    @objc func receiveAnswer(_ answer: String) {
        defaults?.set(answer, forKey: kAnswerKey)
        defaults?.synchronize()
    }

    // ── App readiness flag ─────────────────────────────────────────────────

    /// Flutter calls this when a model is loaded and ready for inference.
    @objc func setModelReady(_ ready: Bool) {
        defaults?.set(ready, forKey: kReadyKey)
        defaults?.synchronize()
    }

    // ── Deep link parsing ──────────────────────────────────────────────────

    /// Parses mypocketai://siri?q=... URLs and returns the question string.
    static func questionFromURL(_ url: URL) -> String? {
        guard url.scheme == "mypocketai",
              url.host == "siri",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let q = components.queryItems?.first(where: { $0.name == "q" })?.value,
              !q.isEmpty
        else { return nil }
        return q
    }
}
