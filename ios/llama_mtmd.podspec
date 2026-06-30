Pod::Spec.new do |s|
  s.name             = 'llama_mtmd'
  s.version          = '0.0.1'
  s.summary          = 'llama.cpp multimodal (clip / mtmd) for vision models'
  s.homepage         = 'https://github.com/ggerganov/llama.cpp'
  s.license          = { :type => 'MIT' }
  s.author           = 'ggerganov'
  s.platform         = :ios, '16.0'
  s.source           = { :path => '.' }

  # Compiles in its own target so object files don't collide by basename with
  # llama_cpp's src/models/*.cpp (several names overlap: qwen2vl, cogvlm, etc.).
  s.dependency 'llama_cpp'

  s.source_files = [
    'llama.cpp/tools/mtmd/clip.cpp',
    'llama.cpp/tools/mtmd/mtmd.cpp',
    'llama.cpp/tools/mtmd/mtmd-audio.cpp',
    'llama.cpp/tools/mtmd/mtmd-image.cpp',
    'llama.cpp/tools/mtmd/mtmd-helper.cpp',
    'llama.cpp/tools/mtmd/models/*.cpp',
    'llama.cpp/tools/mtmd/*.h',
    'llama.cpp/tools/mtmd/debug/mtmd-debug.h',
  ]

  s.pod_target_xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY'           => 'libc++',
    'HEADER_SEARCH_PATHS'         => [
      '"$(PODS_TARGET_SRCROOT)/llama.cpp/include"',
      '"$(PODS_TARGET_SRCROOT)/llama.cpp/src"',
      '"$(PODS_TARGET_SRCROOT)/llama.cpp/ggml/include"',
      '"$(PODS_TARGET_SRCROOT)/llama.cpp/ggml/src"',
      '"$(PODS_TARGET_SRCROOT)/llama.cpp/tools/mtmd"',
      '"$(PODS_TARGET_SRCROOT)/llama.cpp/vendor"',
    ].join(' '),
    'GCC_PREPROCESSOR_DEFINITIONS' => [
      '$(inherited)',
      'NDEBUG=1',
      'GGML_USE_CPU=1',
    ].join(' '),
    'OTHER_CFLAGS'           => '$(inherited) -O2',
    'OTHER_CPLUSPLUSFLAGS'   => '$(inherited) -O2',
    'GCC_OPTIMIZATION_LEVEL' => '2',
  }

  s.libraries  = 'c++'
  s.frameworks = 'Foundation', 'Accelerate'
end
