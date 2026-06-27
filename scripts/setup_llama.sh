#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# setup_llama.sh — clone llama.cpp and run pod install
#
# Run once from the project root:
#   chmod +x scripts/setup_llama.sh && ./scripts/setup_llama.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

LLAMA_DIR="ios/llama.cpp"

echo "──────────────────────────────────────────────────"
echo "  PintSizeAI — llama.cpp setup"
echo "──────────────────────────────────────────────────"

if [ -d "$LLAMA_DIR/.git" ]; then
  echo "✔ llama.cpp already present. Pulling latest..."
  git -C "$LLAMA_DIR" pull --ff-only 2>/dev/null || echo "  (skipping pull — local changes present)"
else
  echo "⬇  Cloning llama.cpp (this is ~80 MB, takes ~1 min)..."
  git clone --depth 1 https://github.com/ggerganov/llama.cpp "$LLAMA_DIR"
fi

echo ""
echo "⚙  Running pod install..."
cd ios && pod install && cd ..

echo ""
echo "✅  Done! Open ios/Runner.xcworkspace in Xcode and build."
