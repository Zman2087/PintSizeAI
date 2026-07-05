# PintSizeAi

Run local LLMs (Qwen, Llama, Gemma, Phi, Mistral, DeepSeek…) **fully on-device** on iOS and Android. No cloud, no accounts, no data leaves the phone. Ask questions through Siri without opening the app.

## Features

- **Local chat** — streaming token generation via llama.cpp, with the model's own chat template, persistent history, and automatic session titles
- **Vision** — multimodal models (Qwen 3.5, Gemma 4, LLaVA, MiniCPM-V) understand photos through llama.cpp's mtmd projector pipeline
- **Image generation** — on-device Stable Diffusion via Apple Core ML
- **Voice mode** — hands-free conversation with sentence-streamed TTS (starts speaking within seconds) and on-device speech recognition, including iOS Personal Voice
- **Siri integration** — ask the loaded model questions straight from Siri
- **Model browser** — Hugging Face search plus a curated catalogue with device-fit recommendations (RAM, storage, and speed-aware)
- **Web & stocks** — optional web search context and live stock cards
- **Documents** — attach files and ask questions about them
- **Privacy by default** — inference, speech, and images all run locally; optional iCloud sync is off by default

## Architecture

```
lib/
├── main.dart                 # App entry point
├── features/                 # Feature-first modules (logic, no UI)
│   ├── chat/                 # Chat state, prompt building, persistence, export
│   ├── llm/                  # LlamaRunner abstraction (native + mock)
│   ├── models/               # Download, storage, HF search, remote catalogue
│   ├── device_recommender/   # Device profiling + model-fit scoring
│   ├── image_gen/            # Stable Diffusion (Core ML) pipeline management
│   ├── voice/                # STT/TTS platform channel
│   ├── web_search/           # DuckDuckGo, URL fetch (SSRF-guarded), stocks
│   ├── documents/            # Document retrieval for Q&A
│   ├── siri/                 # Siri bridge
│   ├── sync/                 # Optional iCloud chat sync
│   └── settings/             # User preferences
├── screens/                  # UI screens
├── widgets/                  # Shared widgets
└── theme/                    # Design tokens (colors, typography, spacing)

ios/Runner/
├── LlamaEngine.mm            # llama.cpp inference engine (Metal + NEON, KV prefix cache)
├── LlamaPlugin.swift         # Flutter <-> engine bridge (method + event channels)
├── VoicePlugin.swift         # AVSpeechSynthesizer / SFSpeechRecognizer
├── ImageGenPlugin.swift      # Core ML Stable Diffusion
└── SiriBridge.swift          # App Intents / Siri
```

State management is [Riverpod](https://riverpod.dev); native inference is bridged over a `MethodChannel` (control) and an `EventChannel` (token stream).

### Inference stack

llama.cpp is vendored (git-ignored) under `ios/llama.cpp/` and compiled by two local CocoaPods:

- **`llama_cpp`** — core engine with the **Metal GPU backend** (shader source embedded in the binary) and **ARM NEON** CPU kernels. All layers are offloaded to the GPU with automatic CPU fallback. The KV cache is reused across turns (longest-common-prefix), so long conversations don't re-evaluate history every message.
- **`llama_mtmd`** — the multimodal (CLIP/mtmd) pipeline for vision models.

Build quirks worth knowing before touching the podspecs are documented inline in `ios/llama_cpp.podspec` (CocoaPods basename collisions, `requires_arc = false` for the Metal sources, and the embedded-shader generation).

## Getting started

Prerequisites: Flutter ≥ 3.22, Xcode 15+, CocoaPods.

```bash
git clone https://github.com/Zman2087/PintSizeAI.git
cd PintSizeAI
flutter pub get

# One-time: clone llama.cpp and run pod install
./scripts/setup_llama.sh

# After updating ios/llama.cpp: regenerate the embedded Metal shader
./scripts/generate_metal_embed.sh && (cd ios && pod install)

flutter run --release   # release mode strongly recommended for inference speed
```

On first launch the app profiles the device, recommends a model that fits, and auto-downloads a tiny starter model so chat works immediately.

## Testing

```bash
flutter analyze          # static analysis (CI-enforced)
flutter test             # unit tests: chat controller, recommender, model fit, runner
dart format .            # formatting (CI-enforced)
```

## Model catalogue

`catalogue/models.json` is fetched **at runtime by shipped apps** from this repository's raw URL — treat it as a published API: don't move or rename it, keep `schemaVersion` stable, and verify file sizes against the Hugging Face API before adding entries (see `lib/features/device_recommender/model_catalogue.dart` for the bundled equivalent).

## Docs

- [App Store listing](docs/APP_STORE_LISTING.md)
- [Privacy & data handling](docs/PRIVACY_AND_DATA.md)
- [Release checklist](docs/RELEASE_CHECKLIST.md)
