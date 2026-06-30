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

/// YES when a multimodal projector (mmproj) is loaded so the model can see images.
@property (nonatomic, readonly) BOOL hasVision;

/// Synchronously loads a GGUF model file.
/// Must NOT be called on the main thread — blocks for several seconds.
- (BOOL)loadModelAtPath:(NSString *)path
          contextLength:(NSInteger)contextLength
                  error:(NSError **)error;

/// Loads a multimodal projector (mmproj GGUF) so the loaded model can accept
/// images. Must be called after loadModelAtPath:. Returns NO on failure.
- (BOOL)loadMultimodalProjectorAtPath:(NSString *)mmprojPath
                                error:(NSError **)error;

/// Formats a chat using the loaded model's own built-in chat template
/// (from the GGUF metadata), so every model family gets the correct prompt
/// format. [messages] is an array of {"role": ..., "content": ...} dicts.
/// Returns nil if no template is available (caller should fall back).
- (NSString * _Nullable)applyChatTemplate:(NSArray<NSDictionary<NSString *, NSString *> *> *)messages
                             addAssistant:(BOOL)addAssistant;

/// Frees model memory. Safe to call even when nothing is loaded.
- (void)unload;

/// Starts asynchronous token generation.
/// tokenHandler is always called on the main thread.
- (void)generateWithPrompt:(NSString *)prompt
                 maxTokens:(NSInteger)maxTokens
               temperature:(float)temperature
                      topP:(float)topP
              tokenHandler:(LlamaTokenHandler)handler;

/// Starts asynchronous token generation with an attached image. If no
/// projector is loaded or [imageData] is nil, behaves like the text-only call.
/// [imageData] is the raw bytes of a JPEG/PNG file.
- (void)generateWithPrompt:(NSString *)prompt
                 imageData:(nullable NSData *)imageData
                 maxTokens:(NSInteger)maxTokens
               temperature:(float)temperature
                      topP:(float)topP
              tokenHandler:(LlamaTokenHandler)handler;

/// Signals the generation loop to stop at the next token boundary.
- (void)cancelGeneration;

@end

NS_ASSUME_NONNULL_END
