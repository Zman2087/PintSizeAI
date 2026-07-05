// CocoaPods names object files by basename, so ggml-cpu/arch/arm/quants.c
// would collide with ggml-cpu/quants.c if listed directly (same trick as
// llama_main.cpp). Resolved via the ggml-cpu HEADER_SEARCH_PATHS entry.
#include "arch/arm/quants.c"
