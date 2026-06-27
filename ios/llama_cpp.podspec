Pod::Spec.new do |s|
  s.name             = 'llama_cpp'
  s.version          = '0.0.1'
  s.summary          = 'llama.cpp inference engine (CPU generic) for iOS'
  s.homepage         = 'https://github.com/ggerganov/llama.cpp'
  s.license          = { :type => 'MIT' }
  s.author           = 'ggerganov'
  s.platform         = :ios, '16.0'
  s.source           = { :path => '.' }

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

    # CPU backend (generic C path — no NEON, but compiles on any arch)
    'llama.cpp/ggml/src/ggml-cpu/ggml-cpu.{c,cpp}',
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
    'llama.cpp/ggml/src/ggml-metal/**',
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
    'llama.cpp/ggml/src/ggml-cpu/arch/**',   # all arch-specific; generic covers us
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
    ].join(' '),
    'GCC_PREPROCESSOR_DEFINITIONS' => [
      '$(inherited)',
      'NDEBUG=1',
      'GGML_USE_CPU=1',        # register CPU backend
      'GGML_CPU_GENERIC=1',    # use generic C implementations (no NEON)
      'GGML_VERSION=\"0.15.3\"',
      'GGML_COMMIT=\"ios\"',
    ].join(' '),
    'OTHER_CFLAGS'           => '$(inherited) -O2',
    'OTHER_CPLUSPLUSFLAGS'   => '$(inherited) -O2',
    'GCC_OPTIMIZATION_LEVEL' => '2',
  }

  s.libraries  = 'c++'
  s.frameworks = 'Foundation', 'Accelerate'
end
