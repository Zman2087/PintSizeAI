// ios/SiriIntents/PintSizeAiIntents.swift
//
// App Intents for PintSizeAi — iOS 16+ (App Intents framework)
//
// THREE intents are exposed to Siri:
//
//   1. AskPintSizeAiIntent      "Ask PintSizeAi [question]"
//      The primary intent. Takes a question string, runs local inference
//      via the shared App Group container IPC bridge, and speaks the answer
//      back through Siri without opening the app.
//      openAppWhenRun = false — stays in Siri overlay.
//
//   2. OpenPintSizeAiIntent     "Open PintSizeAi"
//      Simple launcher intent. Opens the app to the chat screen.
//      openAppWhenRun = true.
//
//   3. NewChatIntent            "Start a new PintSizeAi chat"
//      Opens the app with a fresh conversation, optionally with a question
//      pre-filled — Siri passes the question, app starts generating.
//      openAppWhenRun = true.
//
// Architecture note on inference inside an Intent:
//   iOS Intents extensions have a hard 60 MB memory cap — nowhere near
//   enough for a GGUF model. AskPintSizeAiIntent uses an App Groups
//   shared container to write the question and read back the answer from
//   the main app process (which holds the loaded model).
//   If the main app isn't running, the intent falls back to deep-linking.
//
// Setup required in Xcode:
//   1. Add "Siri" capability to the Runner target.
//   2. Add an "Intents Extension" target named "SiriIntents".
//   3. Enable App Groups ("group.com.mypocketai.app") on BOTH targets.
//   4. Set minimum deployment target to iOS 16.0.

import AppIntents
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// App Group shared container key
// ─────────────────────────────────────────────────────────────────────────────

private let kAppGroupID   = "group.com.mypocketai.app"
private let kQuestionKey  = "siri_pending_question"
private let kAnswerKey    = "siri_latest_answer"
private let kModelKey     = "siri_active_model"
private let kReadyKey     = "siri_app_ready"

// ─────────────────────────────────────────────────────────────────────────────
// 1. AskPintSizeAiIntent — the main voice Q&A intent
// ─────────────────────────────────────────────────────────────────────────────

/// Triggered by: "Ask PintSizeAi [question]"
/// Runs inference on-device and speaks the answer back through Siri.
/// The app stays in the background — no foreground required.
@available(iOS 16.0, *)
struct AskPintSizeAiIntent: AppIntent {

    static let title: LocalizedStringResource = "Ask PintSizeAi"

    static let description = IntentDescription(
        "Ask your on-device AI assistant a question. " +
        "Your question never leaves your device."
    )

    // Do NOT open the app — we want Siri to speak the answer inline.
    // The intent communicates with the running app via App Groups IPC.
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: "Question",
        description: "What do you want to ask PintSizeAi?",
        requestValueDialog: IntentDialog("What would you like to ask?")
    )
    var question: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let defaults = UserDefaults(suiteName: kAppGroupID)

        // Check whether the main app is running and has a model loaded.
        let appReady = defaults?.bool(forKey: kReadyKey) ?? false

        guard appReady else {
            // App not running — deep-link to open it with the question pre-filled.
            // The intent returns a holding message while the app warms up.
            let encoded = question.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed
            ) ?? ""
            let url = URL(string: "mypocketai://siri?q=\(encoded)")!

            if await UIApplication.shared.canOpenURL(url) {
                await UIApplication.shared.open(url)
            }

            return .result(
                dialog: IntentDialog(
                    stringLiteral:
                    "Opening PintSizeAi with your question. " +
                    "A model needs to be loaded first."
                )
            )
        }

        // App is running — write the question to shared storage and poll for answer.
        defaults?.set(question, forKey: kQuestionKey)
        defaults?.set("", forKey: kAnswerKey) // clear previous answer
        defaults?.synchronize()

        // Post a Darwin notification to wake the Flutter engine in the background.
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName("com.mypocketai.siri.question" as CFString),
            nil, nil, true
        )

        // Poll for the answer — the main app writes it to kAnswerKey.
        // Timeout after 30 seconds (Siri's hard limit for intent execution).
        let timeout = Date().addingTimeInterval(30)
        var answer: String? = nil

        while Date() < timeout {
            try await Task.sleep(nanoseconds: 250_000_000) // 250ms poll
            let candidate = defaults?.string(forKey: kAnswerKey) ?? ""
            if !candidate.isEmpty {
                answer = candidate
                break
            }
        }

        guard let answer else {
            return .result(
                dialog: IntentDialog(
                    "PintSizeAi is still thinking. " +
                    "Open the app to see the response."
                )
            )
        }

        // Truncate to ~250 chars for Siri speech — beyond that it becomes
        // unwieldy to listen to. Full response is in the app.
        let spoken = answer.count > 250
            ? String(answer.prefix(250)) + "… Open PintSizeAi for the full response."
            : answer

        return .result(dialog: IntentDialog(stringLiteral: spoken))
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. OpenPintSizeAiIntent — simple launcher
// ─────────────────────────────────────────────────────────────────────────────

/// Triggered by: "Open PintSizeAi"
@available(iOS 16.0, *)
struct OpenPintSizeAiIntent: AppIntent {

    static let title: LocalizedStringResource = "Open PintSizeAi"

    static let description = IntentDescription(
        "Opens the PintSizeAi app."
    )

    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        return .result(dialog: "Opening PintSizeAi.")
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. NewChatIntent — open with a fresh conversation
// ─────────────────────────────────────────────────────────────────────────────

/// Triggered by: "Start a new PintSizeAi chat [about topic]"
@available(iOS 16.0, *)
struct NewChatIntent: AppIntent {

    static let title: LocalizedStringResource = "New PintSizeAi Chat"

    static let description = IntentDescription(
        "Starts a fresh conversation in PintSizeAi, " +
        "optionally with a question already loaded."
    )

    static var openAppWhenRun: Bool = true

    @Parameter(
        title: "Topic",
        description: "Optional starting question or topic.",
        default: ""
    )
    var topic: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Write the question to shared storage so Flutter picks it up on launch.
        if !topic.isEmpty {
            let defaults = UserDefaults(suiteName: kAppGroupID)
            defaults?.set(topic, forKey: kQuestionKey)
            defaults?.synchronize()
        }

        let dialog = topic.isEmpty
            ? IntentDialog("Starting a new PintSizeAi conversation.")
            : IntentDialog("Opening PintSizeAi with your question.")

        return .result(dialog: dialog)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// App Shortcuts Provider — registers the Siri phrases
// ─────────────────────────────────────────────────────────────────────────────
//
// These phrases are what Siri listens for WITHOUT the user needing to set up
// a shortcut. They work immediately after the app is installed.
//
// Rules for phrases:
//   - Must contain \(.applicationName) at least once.
//   - Siri's NLU fills in parameters — the phrase pattern defines the slot.
//   - Keep them short and natural — how would a real person actually say this?

@available(iOS 16.0, *)
struct PintSizeAiShortcuts: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {

        // ── Ask a question ────────────────────────────────────────────────
        AppShortcut(
            intent: AskPintSizeAiIntent(),
            phrases: [
                "Ask \(.applicationName) \(\.$question)",
                "Hey \(.applicationName) \(\.$question)",
                "Ask \(.applicationName) to \(\.$question)",
                "\(.applicationName) what is \(\.$question)",
            ],
            shortTitle: "Ask a question",
            systemImageName: "brain"
        )

        // ── Open the app ──────────────────────────────────────────────────
        AppShortcut(
            intent: OpenPintSizeAiIntent(),
            phrases: [
                "Open \(.applicationName)",
                "Launch \(.applicationName)",
                "Show \(.applicationName)",
            ],
            shortTitle: "Open app",
            systemImageName: "cpu"
        )

        // ── New chat ──────────────────────────────────────────────────────
        AppShortcut(
            intent: NewChatIntent(),
            phrases: [
                "Start a new \(.applicationName) chat",
                "New \(.applicationName) conversation",
                "New \(.applicationName) chat about \(\.$topic)",
            ],
            shortTitle: "New chat",
            systemImageName: "plus.bubble"
        )
    }
}
