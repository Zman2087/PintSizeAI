// CocoaPods names object files by basename, so ggml-cpu/arch/arm/repack.cpp
// would collide with ggml-cpu/repack.cpp if listed directly (same trick as
// llama_main.cpp). Resolved via the ggml-cpu HEADER_SEARCH_PATHS entry.
#include "arch/arm/repack.cpp"
