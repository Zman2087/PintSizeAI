#import "LlamaEngine.h"
#include "llama.h"
#include "mtmd.h"
#include "mtmd-helper.h"
#include <atomic>
#include <string>
#include <vector>

static NSString * const kLlamaErrorDomain = @"LlamaEngineError";

@implementation LlamaEngine {
    struct llama_model   *_model;
    struct llama_context *_ctx;
    struct llama_sampler *_sampler;
    mtmd_context         *_mctx;   // multimodal projector context (nullable)
    std::atomic<bool>     _cancelled;
    dispatch_queue_t      _genQueue; // serial — one generation at a time
}

// ── Lifecycle ────────────────────────────────────────────────────────────────

- (instancetype)init {
    self = [super init];
    if (self) {
        _model     = nullptr;
        _ctx       = nullptr;
        _sampler   = nullptr;
        _mctx      = nullptr;
        _cancelled.store(false);
        _genQueue  = dispatch_queue_create("ai.pintsize.llama.generate", DISPATCH_QUEUE_SERIAL);
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

- (BOOL)hasVision {
    return _mctx != nullptr;
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
    // Use all available cores for faster generation on CPU.
    int cores = (int)[[NSProcessInfo processInfo] activeProcessorCount];
    cparams.n_threads       = (int32_t)MAX(2, cores);
    cparams.n_threads_batch = (int32_t)MAX(2, cores);

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

- (BOOL)loadMultimodalProjectorAtPath:(NSString *)mmprojPath
                                error:(NSError **)error {
    if (!_model) {
        if (error) {
            *error = [NSError errorWithDomain:kLlamaErrorDomain code:6
                userInfo:@{NSLocalizedDescriptionKey: @"Load a model before the projector"}];
        }
        return NO;
    }
    if (_mctx) { mtmd_free(_mctx); _mctx = nullptr; }

    mtmd_context_params mparams = mtmd_context_params_default();
    mparams.use_gpu       = false;
    mparams.print_timings = false;
    mparams.n_threads     = (int)MAX(1, [[NSProcessInfo processInfo] activeProcessorCount] - 1);
    mparams.media_marker  = mtmd_default_marker();

    _mctx = mtmd_init_from_file([mmprojPath UTF8String], _model, mparams);
    if (!_mctx) {
        if (error) {
            *error = [NSError errorWithDomain:kLlamaErrorDomain code:7
                userInfo:@{NSLocalizedDescriptionKey: @"Could not load multimodal projector"}];
        }
        return NO;
    }
    return YES;
}

- (NSString *)applyChatTemplate:(NSArray<NSDictionary<NSString *, NSString *> *> *)messages
                   addAssistant:(BOOL)addAssistant {
    if (!_model || messages.count == 0) return nil;

    const char *tmpl = llama_model_chat_template(_model, nullptr);

    // Keep the role/content C-strings alive for the duration of the call.
    std::vector<std::string> storage;
    storage.reserve(messages.count * 2);
    for (NSDictionary *m in messages) {
        NSString *role    = m[@"role"]    ?: @"user";
        NSString *content = m[@"content"] ?: @"";
        storage.push_back(std::string(role.UTF8String));
        storage.push_back(std::string(content.UTF8String));
    }

    std::vector<llama_chat_message> chat;
    chat.reserve(messages.count);
    for (NSUInteger i = 0; i < messages.count; i++) {
        llama_chat_message cm;
        cm.role    = storage[i * 2].c_str();
        cm.content = storage[i * 2 + 1].c_str();
        chat.push_back(cm);
    }

    int32_t needed = llama_chat_apply_template(tmpl, chat.data(), chat.size(),
                                               addAssistant, nullptr, 0);
    if (needed <= 0) return nil;

    std::vector<char> buf((size_t)needed + 1);
    int32_t n = llama_chat_apply_template(tmpl, chat.data(), chat.size(),
                                          addAssistant, buf.data(),
                                          (int32_t)buf.size());
    if (n <= 0) return nil;
    return [[NSString alloc] initWithBytes:buf.data()
                                    length:(NSUInteger)n
                                  encoding:NSUTF8StringEncoding];
}

- (void)unload {
    _cancelled.store(true);
    if (_mctx)    { mtmd_free(_mctx);             _mctx    = nullptr; }
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

    // Signal any in-flight generation to stop; the serial queue then runs us next.
    _cancelled.store(true);
    const float temp = temperature;
    const float tp   = topP;

    dispatch_async(_genQueue, ^{
        @autoreleasepool {
            // Rebuild the sampler inside the serial queue so it's never freed
            // while another generation is mid-flight.
            self->_cancelled.store(false);
            [self _buildSampler:temp topP:tp];
            struct llama_model   *model   = self->_model;
            struct llama_context *ctx     = self->_ctx;
            struct llama_sampler *sampler = self->_sampler;
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

            // ── 2. Evaluate prompt in n_batch-sized chunks ──────────────────
            // Decoding the whole prompt in a single batch overflows when the
            // prompt exceeds n_batch and crashes the app, so we chunk it. We
            // also drop the oldest tokens if the prompt won't leave room for
            // the response within the context window.
            const int nCtx   = (int)llama_n_ctx(ctx);
            const int nBatch  = 512;
            int maxPrompt = nCtx - (int)maxTokens - 8;
            if (maxPrompt < 64) maxPrompt = nCtx / 2;
            if ((int)tokens.size() > maxPrompt) {
                int drop = (int)tokens.size() - maxPrompt;
                tokens.erase(tokens.begin(), tokens.begin() + drop);
            }
            const int promptCount = (int)tokens.size();

            llama_memory_clear(llama_get_memory(ctx), true);

            bool decodeFailed = false;
            for (int i = 0; i < promptCount; i += nBatch) {
                if (self->_cancelled.load()) break;
                int chunk = MIN(nBatch, promptCount - i);
                llama_batch b = llama_batch_get_one(tokens.data() + i, chunk);
                if (llama_decode(ctx, b) != 0) { decodeFailed = true; break; }
            }
            if (decodeFailed) {
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
            int nPast = promptCount;
            NSInteger generated = 0;
            while (generated < maxTokens && !self->_cancelled.load()) {
                // Stop before we run out of context window (avoids a crash).
                if (nPast >= nCtx - 1) break;

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

                nPast++;
                generated++;
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                handler(nil, YES, nil); // signal completion
            });
        }
    });
}

- (void)generateWithPrompt:(NSString *)prompt
                 imageData:(NSData *)imageData
                 maxTokens:(NSInteger)maxTokens
               temperature:(float)temperature
                      topP:(float)topP
              tokenHandler:(LlamaTokenHandler)handler {
    // No projector or no image → behave exactly like the text-only path.
    if (!_mctx || imageData == nil || imageData.length == 0) {
        [self generateWithPrompt:prompt
                       maxTokens:maxTokens
                     temperature:temperature
                            topP:topP
                    tokenHandler:handler];
        return;
    }
    if (!self.isLoaded) {
        dispatch_async(dispatch_get_main_queue(), ^{
            handler(nil, YES, [NSError errorWithDomain:kLlamaErrorDomain code:3
                userInfo:@{NSLocalizedDescriptionKey: @"No model is loaded"}]);
        });
        return;
    }

    _cancelled.store(true); // stop any in-flight generation first
    const float temp = temperature;
    const float tp   = topP;

    std::vector<unsigned char> imgBytes(
        (const unsigned char *)imageData.bytes,
        (const unsigned char *)imageData.bytes + imageData.length);
    std::string promptStr(prompt.UTF8String ? prompt.UTF8String : "");

    dispatch_async(_genQueue, ^{
        @autoreleasepool {
            self->_cancelled.store(false);
            [self _buildSampler:temp topP:tp];
            struct llama_context *ctx     = self->_ctx;
            struct llama_model   *model   = self->_model;
            struct llama_sampler *sampler = self->_sampler;
            mtmd_context         *mctx    = self->_mctx;
            auto fail = ^(NSString *msg) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    handler(nil, YES, [NSError errorWithDomain:kLlamaErrorDomain code:8
                        userInfo:@{NSLocalizedDescriptionKey: msg}]);
                });
            };

            // Place the image marker ahead of the user's question.
            std::string marker = mtmd_default_marker();
            std::string full   = marker + "\n" + promptStr;

            mtmd_input_text text;
            text.text          = full.c_str();
            text.add_special   = true;
            text.parse_special = true;

            mtmd_helper_bitmap_wrapper wrap =
                mtmd_helper_bitmap_init_from_buf(mctx, imgBytes.data(), imgBytes.size(), false);
            mtmd_bitmap *bmp = wrap.bitmap;
            if (!bmp) { fail(@"Could not decode the image"); return; }

            const mtmd_bitmap *bitmaps[1] = { bmp };
            mtmd_input_chunks *chunks = mtmd_input_chunks_init();
            int32_t tk = mtmd_tokenize(mctx, chunks, &text, bitmaps, 1);
            if (tk != 0) {
                mtmd_input_chunks_free(chunks);
                mtmd_bitmap_free(bmp);
                fail(@"Failed to process image + prompt");
                return;
            }

            llama_memory_clear(llama_get_memory(ctx), true);
            llama_pos newNPast = 0;
            int32_t ev = mtmd_helper_eval_chunks(mctx, ctx, chunks,
                                                 /*n_past*/ 0,
                                                 /*seq_id*/ 0,
                                                 /*n_batch*/ 512,
                                                 /*logits_last*/ true,
                                                 &newNPast);
            mtmd_input_chunks_free(chunks);
            mtmd_bitmap_free(bmp);
            if (ev != 0) { fail(@"Vision evaluation failed"); return; }

            // ── Generation loop (identical to the text path) ────────────────
            const struct llama_vocab *vocab = llama_model_get_vocab(model);
            NSInteger generated = 0;
            while (generated < maxTokens && !self->_cancelled.load()) {
                llama_token tok = llama_sampler_sample(sampler, ctx, -1);
                llama_sampler_accept(sampler, tok);
                if (llama_vocab_is_eog(vocab, tok)) break;

                char piece[256] = {0};
                int32_t pieceLen = llama_token_to_piece(vocab, tok,
                                                        piece, sizeof(piece) - 1, 0, true);
                if (pieceLen > 0) {
                    piece[pieceLen] = '\0';
                    NSString *tokenStr = [NSString stringWithUTF8String:piece];
                    if (tokenStr.length > 0) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            handler(tokenStr, NO, nil);
                        });
                    }
                }

                llama_batch nextBatch = llama_batch_get_one(&tok, 1);
                if (llama_decode(ctx, nextBatch) != 0) break;
                generated++;
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                handler(nil, YES, nil);
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
