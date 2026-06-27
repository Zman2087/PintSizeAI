// Wrapper to include the main llama.cpp source file.
// This avoids a CocoaPods glob bug where "llama.cpp/src/llama.cpp"
// is skipped because the directory and file share the same name.
#include "llama.cpp/src/llama.cpp"
