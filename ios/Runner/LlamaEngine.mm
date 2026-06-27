#import "LlamaEngine.h"
#include "llama.h"
#include <atomic>
#include <string>
#include <vector>

static NSString * const kLlamaErrorDomain = @"LlamaEngineError";

@implementation LlamaEngine {
    struct llama_model   *_model;
    struct llama_context *_ctx;
    struct llama_sampler *_sampler;
    std::atomic<bool>     _cancelled;
}

// ── Lifecycle ────────────────────────────────────────────────────────────────

- (instancetype)init {
    self = [super init];
    if (self) {
        _model     = nullptr;
        _ctx       = nullptr;
        _sampler   = nullptr;
        _cancelled.store(false);
        llama_backend_init();
    }
    return self;
}

- (void)dealloc {
    [self unload];
    llama_backend_free();
}

// ── Properties ───────────────────────────────────────────────────────────────

- (BOOL)isLoaded {
    return _model != nullptr && _ctx != nullptr;
}

// ── Load / unload ────────────────────────────────────────────────────────────

- (BOOL)loadModelAtPath:(NSString *)path
          contextLength:(NSInteger)contextLength
                  error:(NSError **)error {
    [self unload]; // free any previous model first

    // Model params — CPU-only for broad compatibility
    struct llama_model_params mparams = llama_model_default_params();
    mparams.n_gpu_layers = 0;

    _model = llama_model_load_from_file([path UTF8String], mparams);
    if (!_model) {
        if (error) {
            *error = [NSError errorWithDomain:kLlamaErrorDomain
                                         code:1
                                     userInfo:@{
                NSLocalizedDescriptionKey: [NSString stringWithFormat:
                    @"Could not open model file: %@", path]
            }];
        }
        return NO;
    }

    // Context — cap at 4096 tokens to keep RAM reasonable
    struct llama_context_params cparams = llama_context_default_params();
    cparams.n_ctx   = (uint32_t)MIN(contextLength, 4096);
    cparams.n_batch = 512;

    _ctx = llama_new_context_with_model(_model, cparams);
    if (!_ctx) {
        llama_model_free(_model);
        _model = nullptr;
        if (error) {
            *error = [NSError errorWithDomain:kLlamaErrorDomain
                                         code:2
                                     userInfo:@{
                NSLocalizedDescriptionKey: @"Failed to create inference context (not enough RAM?)"
            }];
        }
        return NO;
    }

    [self _buildSampler:0.7f topP:0.9f];
    return YES;
}

- (void)unload {
    _cancelled.store(true);
    if (_sampler) { llama_sampler_free(_sampler); _sampler = nullptr; }
    if (_ctx)     { llama_free(_ctx);             _ctx     = nullptr; }
    if (_model)   { llama_model_free(_model);     _model   = nullptr; }
}

// ── Generation ───────────────────────────────────────────────────────────────

- (void)generateWithPrompt:(NSString *)prompt
                 maxTokens:(NSInteger)maxTokens
               temperature:(float)temperature
                      topP:(float)topP
              tokenHandler:(LlamaTokenHandler)handler {
    if (!self.isLoaded) {
        dispatch_async(dispatch_get_main_queue(), ^{
            handler(nil, YES, [NSError errorWithDomain:kLlamaErrorDomain
                                                  code:3
                                              userInfo:@{
                NSLocalizedDescriptionKey: @"No model is loaded"
            }]);
        });
        return;
    }

    _cancelled.store(false);
    [self _buildSampler:temperature topP:topP];

    // Capture ivars for the background block
    struct llama_model   *model   = _model;
    struct llama_context *ctx     = _ctx;
    struct llama_sampler *sampler = _sampler;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @autoreleasepool {
            const struct llama_vocab *vocab = llama_model_get_vocab(model);
            const char *promptCStr = [prompt UTF8String];
            int32_t     promptLen  = (int32_t)strlen(promptCStr);

            // ── 1. Tokenise prompt ──────────────────────────────────────────
            int32_t nTokens = -llama_tokenize(vocab, promptCStr, promptLen,
                                              nullptr, 0, true, true);
            if (nTokens <= 0) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    handler(nil, YES, [NSError errorWithDomain:kLlamaErrorDomain
                                                          code:4
                                                      userInfo:@{
                        NSLocalizedDescriptionKey: @"Tokenisation failed"
                    }]);
                });
                return;
            }

            std::vector<llama_token> tokens((size_t)nTokens);
            llama_tokenize(vocab, promptCStr, promptLen,
                           tokens.data(), nTokens, true, true);

            // ── 2. Evaluate prompt in one batch ─────────────────────────────
            llama_memory_clear(llama_get_memory(ctx), true);
            llama_batch promptBatch = llama_batch_get_one(tokens.data(), nTokens);

            if (llama_decode(ctx, promptBatch) != 0) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    handler(nil, YES, [NSError errorWithDomain:kLlamaErrorDomain
                                                          code:5
                                                      userInfo:@{
                        NSLocalizedDescriptionKey: @"Prompt evaluation failed"
                    }]);
                });
                return;
            }

            // ── 3. Generation loop ──────────────────────────────────────────
            NSInteger generated = 0;
            while (generated < maxTokens && !self->_cancelled.load()) {

                llama_token tok = llama_sampler_sample(sampler, ctx, -1);
                llama_sampler_accept(sampler, tok);

                // Stop on end-of-generation token
                if (llama_vocab_is_eog(vocab, tok)) break;

                // Decode token → UTF-8 text piece
                char piece[256] = {0};
                int32_t pieceLen = llama_token_to_piece(vocab, tok,
                                                        piece, sizeof(piece) - 1,
                                                        0, true);
                if (pieceLen > 0) {
                    piece[pieceLen] = '\0';
                    NSString *tokenStr = [NSString stringWithUTF8String:piece];
                    if (tokenStr.length > 0) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            handler(tokenStr, NO, nil);
                        });
                    }
                }

                // Feed the new token back for the next decode step
                llama_batch nextBatch = llama_batch_get_one(&tok, 1);
                if (llama_decode(ctx, nextBatch) != 0) break;

                generated++;
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                handler(nil, YES, nil); // signal completion
            });
        }
    });
}

- (void)cancelGeneration {
    _cancelled.store(true);
}

// ── Private ──────────────────────────────────────────────────────────────────

- (void)_buildSampler:(float)temperature topP:(float)topP {
    if (_sampler) {
        llama_sampler_free(_sampler);
    }
    struct llama_sampler_chain_params sparams = llama_sampler_chain_default_params();
    _sampler = llama_sampler_chain_init(sparams);
    llama_sampler_chain_add(_sampler, llama_sampler_init_temp(temperature));
    llama_sampler_chain_add(_sampler, llama_sampler_init_top_p(topP, 1));
    llama_sampler_chain_add(_sampler, llama_sampler_init_dist(LLAMA_DEFAULT_SEED));
}

@end
