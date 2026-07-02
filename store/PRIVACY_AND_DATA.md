# App Privacy — "nutrition label" answers (App Store Connect)

PintSize AI collects **no data**. Use these answers in the App Privacy section.

## Data Collection
Question: "Do you or your third-party partners collect data from this app?"
Answer: **No, we do not collect data from this app.**

Rationale:
- All AI inference runs on-device (llama.cpp / Core ML). No prompts or outputs
  leave the device.
- No analytics or crash-reporting SDKs are integrated.
- Chats are stored only in the app's local documents directory.
- Optional iCloud sync (off by default) uses the user's own private iCloud
  key-value store (Apple-encrypted, not accessible to the developer).
- Network calls are user-initiated only and go directly to public services:
  • Hugging Face (model downloads / discovery)
  • Yahoo Finance (stock quotes) and DuckDuckGo (web search) — only when the
    user asks. These receive the query text but PintSize stores nothing.

## Required-reason API declarations
Already covered by `ios/Runner/PrivacyInfo.xcprivacy`:
- UserDefaults (CA92.1) — app settings via shared_preferences
- File timestamp (C617.1) — reading/writing model & chat files
- Disk space (E174.1) — checking space before downloads
- System boot time (35F9.1) — common library usage

## Encryption
`ITSAppUsesNonExemptEncryption = false` is set in Info.plist (only standard
HTTPS is used), so no export-compliance documentation is required.

## Permissions the app requests (with in-app usage strings)
- Camera — attach photos to messages
- Microphone — voice input / Voice Mode
- Speech Recognition — transcribe speech and audio files
- Photo Library (read + add) — attach and save images
- Personal Voice — (runtime prompt, no Info.plist key) speak in the user's voice
