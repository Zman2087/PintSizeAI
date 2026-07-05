Pod::Spec.new do |s|
  s.name             = 'llama_cpp'
  s.version          = '0.0.1'
  s.summary          = 'llama.cpp inference engine (ARM NEON + Metal) for iOS'
  s.homepage         = 'https://github.com/ggerganov/llama.cpp'
  s.license          = { :type => 'MIT' }
  s.author           = 'ggerganov'
  s.platform         = :ios, '16.0'
  s.source           = { :path => '.' }

  # The Metal shader source is embedded in the binary (via the .incbin stub
  # in generated/ggml-metal-embed.s) and compiled by Metal at first model
  # load, mirroring the GGML_METAL_EMBED_LIBRARY branch of
  # ggml/src/ggml-metal/CMakeLists.txt. The generated/ files are committed;
  # regenerate with scripts/generate_metal_embed.sh after bumping llama.cpp.
  # (CocoaPods does not run prepare_command for local :path pods, so this
  # can't be automated here.)

  # ── Source files ─────────────────────────────────────────────────────────
  s.source_files = [
    # Public headers (all headers that llama.h transitively includes)
    'llama.cpp/include/llama.h',
    'llama.cpp/ggml/include/ggml.h',
    'llama.cpp/ggml/include/ggml-alloc.h',
    'llama.cpp/ggml/include/ggml-backend.h',
    'llama.cpp/ggml/include/ggml-cpp.h',
    'llama.cpp/ggml/include/ggml-cpu.h',
    'llama.cpp/ggml/include/ggml-opt.h',
    'llama.cpp/ggml/include/gguf.h',

    # ggml core
    'llama.cpp/ggml/src/ggml.c',
    'llama.cpp/ggml/src/ggml.cpp',
    'llama.cpp/ggml/src/ggml-alloc.c',
    'llama.cpp/ggml/src/ggml-backend.cpp',
    'llama.cpp/ggml/src/ggml-backend-reg.cpp',
    'llama.cpp/ggml/src/ggml-backend-meta.cpp',
    'llama.cpp/ggml/src/ggml-backend-dl.{h,cpp}',
    'llama.cpp/ggml/src/ggml-threading.{h,cpp}',
    'llama.cpp/ggml/src/ggml-quants.{h,c}',
    'llama.cpp/ggml/src/ggml-opt.cpp',
    'llama.cpp/ggml/src/gguf.cpp',
    'llama.cpp/ggml/src/ggml-common.h',
    'llama.cpp/ggml/src/ggml-impl.h',
    'llama.cpp/ggml/src/ggml-backend-impl.h',

    # Metal GPU backend (shader library embedded via generated/ggml-metal-embed.s)
    # ggml-metal-device.cpp is compiled via the ggml_metal_device_cpp.cpp
    # wrapper — its basename collides with ggml-metal-device.m.
    'llama.cpp/ggml/include/ggml-metal.h',
    'llama.cpp/ggml/src/ggml-metal/ggml-metal.cpp',
    'llama.cpp/ggml/src/ggml-metal/ggml-metal-device.{h,m}',
    'ggml_metal_device_cpp.cpp',
    'llama.cpp/ggml/src/ggml-metal/ggml-metal-common.{h,cpp}',
    'llama.cpp/ggml/src/ggml-metal/ggml-metal-context.{h,m}',
    'llama.cpp/ggml/src/ggml-metal/ggml-metal-ops.{h,cpp}',
    'llama.cpp/ggml/src/ggml-metal/ggml-metal-impl.h',
    'generated/ggml-metal-embed.s',

    # CPU backend with ARM NEON kernels (arch/arm) — the generic C path was
    # ~an order of magnitude slower per token and ran the phone hot.
    # The arch/arm files are compiled via ggml_arm_*.{c,cpp} wrappers because
    # their basenames collide with ggml-cpu/quants.c and repack.cpp.
    'llama.cpp/ggml/src/ggml-cpu/ggml-cpu.{c,cpp}',
    'ggml_arm_quants.c',
    'ggml_arm_repack.cpp',
    'llama.cpp/ggml/src/ggml-cpu/ggml-cpu-impl.h',
    'llama.cpp/ggml/src/ggml-cpu/common.h',
    'llama.cpp/ggml/src/ggml-cpu/arch-fallback.h',
    'llama.cpp/ggml/src/ggml-cpu/simd-gemm.h',
    'llama.cpp/ggml/src/ggml-cpu/simd-mappings.h',
    'llama.cpp/ggml/src/ggml-cpu/binary-ops.{h,cpp}',
    'llama.cpp/ggml/src/ggml-cpu/unary-ops.{h,cpp}',
    'llama.cpp/ggml/src/ggml-cpu/ops.{h,cpp}',
    'llama.cpp/ggml/src/ggml-cpu/vec.{h,cpp}',
    'llama.cpp/ggml/src/ggml-cpu/traits.{h,cpp}',
    'llama.cpp/ggml/src/ggml-cpu/repack.{h,cpp}',
    'llama.cpp/ggml/src/ggml-cpu/quants.{h,c}',
    'llama.cpp/ggml/src/ggml-cpu/hbm.{h,cpp}',

    # llama.cpp sources — exactly what CMakeLists.txt lists
    # NOTE: 'llama.cpp/src/llama.cpp' is skipped by CocoaPods glob due to
    #       the directory-name == file-name conflict; use wrapper instead.
    'llama_main.cpp',
    'llama.cpp/src/llama-adapter.{h,cpp}',
    'llama.cpp/src/llama-arch.{h,cpp}',
    'llama.cpp/src/llama-batch.{h,cpp}',
    'llama.cpp/src/llama-chat.{h,cpp}',
    'llama.cpp/src/llama-context.{h,cpp}',
    'llama.cpp/src/llama-cparams.{h,cpp}',
    'llama.cpp/src/llama-grammar.{h,cpp}',
    'llama.cpp/src/llama-graph.{h,cpp}',
    'llama.cpp/src/llama-hparams.{h,cpp}',
    'llama.cpp/src/llama-impl.{h,cpp}',
    'llama.cpp/src/llama-io.{h,cpp}',
    'llama.cpp/src/llama-kv-cache.{h,cpp}',
    'llama.cpp/src/llama-kv-cache-iswa.{h,cpp}',
    'llama.cpp/src/llama-kv-cache-dsa.{h,cpp}',
    'llama.cpp/src/llama-memory.{h,cpp}',
    'llama.cpp/src/llama-memory-hybrid.{h,cpp}',
    'llama.cpp/src/llama-memory-hybrid-iswa.{h,cpp}',
    'llama.cpp/src/llama-memory-recurrent.{h,cpp}',
    'llama.cpp/src/llama-mmap.{h,cpp}',
    'llama.cpp/src/llama-model-loader.{h,cpp}',
    'llama.cpp/src/llama-model-saver.{h,cpp}',
    'llama.cpp/src/llama-model.{h,cpp}',
    'llama.cpp/src/llama-quant.{h,cpp}',
    'llama.cpp/src/llama-sampler.{h,cpp}',
    'llama.cpp/src/llama-vocab.{h,cpp}',
    'llama.cpp/src/unicode.{h,cpp}',
    'llama.cpp/src/unicode-data.{h,cpp}',
    'llama.cpp/src/llama-ext.h',
    'llama.cpp/src/llama-kv-cells.h',
    # Architecture-specific model implementations
    'llama.cpp/src/models/*.{h,cpp}',
  ]

  # ── Excluded files ────────────────────────────────────────────────────────
  s.exclude_files = [
    'llama.cpp/ggml/src/ggml-cuda/**',
    'llama.cpp/ggml/src/ggml-opencl/**',
    'llama.cpp/ggml/src/ggml-vulkan/**',
    'llama.cpp/ggml/src/ggml-sycl/**',
    'llama.cpp/ggml/src/ggml-kompute/**',
    'llama.cpp/ggml/src/ggml-rpc/**',
    'llama.cpp/ggml/src/ggml-cann/**',
    'llama.cpp/ggml/src/ggml-hexagon/**',
    'llama.cpp/ggml/src/ggml-hip/**',
    'llama.cpp/ggml/src/ggml-musa/**',
    'llama.cpp/ggml/src/ggml-blas/**',
    'llama.cpp/ggml/src/ggml-openvino/**',
    'llama.cpp/ggml/src/ggml-virtgpu/**',
    'llama.cpp/ggml/src/ggml-webgpu/**',
    'llama.cpp/ggml/src/ggml-zdnn/**',
    'llama.cpp/ggml/src/ggml-zendnn/**',
    'llama.cpp/ggml/src/ggml-cpu/amx/**',
    'llama.cpp/ggml/src/ggml-cpu/spacemit/**',
    'llama.cpp/ggml/src/ggml-cpu/kleidiai/**',
    # non-ARM arch kernels (arm stays in — see source_files)
    'llama.cpp/ggml/src/ggml-cpu/arch/loongarch/**',
    'llama.cpp/ggml/src/ggml-cpu/arch/powerpc/**',
    'llama.cpp/ggml/src/ggml-cpu/arch/riscv/**',
    'llama.cpp/ggml/src/ggml-cpu/arch/s390/**',
    'llama.cpp/ggml/src/ggml-cpu/arch/wasm/**',
    'llama.cpp/ggml/src/ggml-cpu/arch/x86/**',
    'llama.cpp/ggml/src/ggml-cpu/llamafile/**',
  ]

  # ── Compiler flags ────────────────────────────────────────────────────────
  s.pod_target_xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY'           => 'libc++',
    'HEADER_SEARCH_PATHS'         => [
      '"$(PODS_TARGET_SRCROOT)/llama.cpp/include"',
      '"$(PODS_TARGET_SRCROOT)/llama.cpp/src"',
      '"$(PODS_TARGET_SRCROOT)/llama.cpp/ggml/include"',
      '"$(PODS_TARGET_SRCROOT)/llama.cpp/ggml/src"',
      '"$(PODS_TARGET_SRCROOT)/llama.cpp/ggml/src/ggml-cpu"',
      '"$(PODS_TARGET_SRCROOT)/llama.cpp/tools/mtmd"',
      '"$(PODS_TARGET_SRCROOT)/llama.cpp/vendor"',
      '"$(PODS_TARGET_SRCROOT)/llama.cpp/ggml/src/ggml-metal"',  # wrapper include
      '"$(PODS_TARGET_SRCROOT)/generated"',   # .incbin lookup for ggml-metal-embed.s
    ].join(' '),
    'GCC_PREPROCESSOR_DEFINITIONS' => [
      '$(inherited)',
      'NDEBUG=1',
      'GGML_USE_CPU=1',              # register CPU backend
      'GGML_USE_METAL=1',            # register Metal GPU backend
      'GGML_METAL_EMBED_LIBRARY=1',  # shader source embedded via .incbin stub
      'GGML_METAL_NDEBUG=1',
      'GGML_USE_CPU_REPACK=1',       # NEON-optimised Q4 weight repacking
      'GGML_USE_ACCELERATE=1',
      'ACCELERATE_NEW_LAPACK=1',
      'ACCELERATE_LAPACK_ILP64=1',
      'GGML_VERSION=\"0.15.3\"',
      'GGML_COMMIT=\"ios\"',
    ].join(' '),
    'OTHER_CFLAGS'           => '$(inherited) -O2',
    'OTHER_CPLUSPLUSFLAGS'   => '$(inherited) -O2',
    'GCC_OPTIMIZATION_LEVEL' => '2',
  }

  # ggml-metal's .m files use manual reference counting (upstream compiles
  # them without ARC); everything else here is C/C++ and unaffected.
  s.requires_arc = false

  s.libraries  = 'c++'
  s.frameworks = 'Foundation', 'Accelerate', 'Metal', 'MetalKit'
end
