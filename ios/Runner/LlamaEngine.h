#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Called on the main thread for every generated token.
/// token   — the decoded text piece, nil on completion or error
/// isDone  — YES when generation has finished (token will be nil)
/// error   — non-nil only on failure
typedef void (^LlamaTokenHandler)(
    NSString * _Nullable token,
    BOOL isDone,
    NSError * _Nullable error
);

/// Wraps the llama.cpp C API for use from Swift.
/// Thread-safe: load/generate/cancel may be called from any thread.
@interface LlamaEngine : NSObject

@property (nonatomic, readonly) BOOL isLoaded;

/// Synchronously loads a GGUF model file.
/// Must NOT be called on the main thread — blocks for several seconds.
- (BOOL)loadModelAtPath:(NSString *)path
          contextLength:(NSInteger)contextLength
                  error:(NSError **)error;

/// Frees model memory. Safe to call even when nothing is loaded.
- (void)unload;

/// Starts asynchronous token generation.
/// tokenHandler is always called on the main thread.
- (void)generateWithPrompt:(NSString *)prompt
                 maxTokens:(NSInteger)maxTokens
               temperature:(float)temperature
                      topP:(float)topP
              tokenHandler:(LlamaTokenHandler)handler;

/// Signals the generation loop to stop at the next token boundary.
- (void)cancelGeneration;

@end

NS_ASSUME_NONNULL_END
