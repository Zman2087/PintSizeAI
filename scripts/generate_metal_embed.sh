#!/bin/bash
# Regenerates ios/generated/ggml-metal-embed.{metal,s} — the Metal shader
# source embedded into the llama_cpp pod (GGML_METAL_EMBED_LIBRARY).
# Run after updating the vendored ios/llama.cpp tree, then `pod install`.
#
# Mirrors the GGML_METAL_EMBED_LIBRARY branch of
# ios/llama.cpp/ggml/src/ggml-metal/CMakeLists.txt.
set -euo pipefail

cd "$(dirname "$0")/../ios"
mkdir -p generated

SRC=llama.cpp/ggml/src/ggml-metal
sed -e "/__embed_ggml-common.h__/r llama.cpp/ggml/src/ggml-common.h" \
    -e "/__embed_ggml-common.h__/d" \
    < "$SRC/ggml-metal.metal" \
    > generated/ggml-metal-embed.metal.tmp
sed -e '/#include "ggml-metal-impl.h"/r '"$SRC"'/ggml-metal-impl.h' \
    -e '/#include "ggml-metal-impl.h"/d' \
    < generated/ggml-metal-embed.metal.tmp \
    > generated/ggml-metal-embed.metal
rm generated/ggml-metal-embed.metal.tmp

# .incbin uses a bare filename; the assembler finds it via the pod's
# HEADER_SEARCH_PATHS entry for ios/generated.
cat > generated/ggml-metal-embed.s <<'EOF'
.section __DATA,__ggml_metallib
.globl _ggml_metallib_start
_ggml_metallib_start:
.incbin "ggml-metal-embed.metal"
.globl _ggml_metallib_end
_ggml_metallib_end:
EOF

echo "Generated: $(ls -la generated/)"
