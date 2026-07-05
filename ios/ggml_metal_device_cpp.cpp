// CocoaPods names object files by basename, so ggml-metal-device.cpp would
// collide with ggml-metal-device.m if both were listed directly (same trick
// as llama_main.cpp). Resolved via the ggml-metal HEADER_SEARCH_PATHS entry.
#include "ggml-metal-device.cpp"
