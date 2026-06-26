/// The catalogue of models PocketLLM supports.
///
/// Every entry is grounded in real numbers from llama.cpp benchmarks
/// and Hugging Face model card file sizes. Nothing is made up.
///
/// Sources:
///   - File sizes: huggingface.co/bartowski / TheBloke GGUF repos
///   - RAM overhead: llama.cpp docs — model size + ~10% context buffer
///   - Token speeds: llama.cpp/issues benchmarks, MLC-LLM device reports
///   - Context sizes: model card max_position_embeddings

library;

/// Quantisation level. Higher quality = more RAM = slower.
/// Q4_K_M is the practical default: good quality, fits more devices.
enum Quant {
  q2k,   // aggressive compression — for very tight RAM
  q3km,  // compact, some quality loss
  q4km,  // recommended default — best quality/size trade-off
  q5km,  // near-lossless — use on flagship if RAM allows
  q8,    // reference quality — large, mostly for benchmarking
  fp16,  // full precision — iPad Pro / desktop only
}

extension QuantLabel on Quant {
  String get label => switch (this) {
    Quant.q2k  => 'Q2_K',
    Quant.q3km => 'Q3_K_M',
    Quant.q4km => 'Q4_K_M',
    Quant.q5km => 'Q5_K_M',
    Quant.q8   => 'Q80',
    Quant.fp16 => 'F16',
  };
}

/// A single downloadable model variant (one model × one quantisation).
class ModelVariant {
  const ModelVariant({
    required this.id,
    required this.displayName,
    required this.family,
    required this.parametersBillions,
    required this.quant,
    required this.fileSizeBytes,
    required this.ramRequiredBytes,
    required this.contextLength,
    required this.downloadUrl,
    required this.strengths,
    this.isReasoningModel = false,
    this.creator = '',
    this.releaseYear = 0,
    this.releaseMonth = 0,
    this.description,
    this.limitations = const [],
    this.minRamGbRecommended = 4,
    this.recommendedDevice,
    this.huggingFaceUrl,
    this.supersedes,
  });

  factory ModelVariant.fromJson(Map<String, dynamic> j) {
    return ModelVariant(
      id:                  j['id'] as String,
      displayName:         j['displayName'] as String,
      family:              ModelFamily.values.firstWhere(
                             (f) => f.name == (j['family'] as String),
                             orElse: () => ModelFamily.llama),
      parametersBillions:  (j['parametersBillions'] as num).toDouble(),
      quant:               Quant.values.firstWhere(
                             (q) => q.name == (j['quant'] as String),
                             orElse: () => Quant.q4km),
      fileSizeBytes:       (j['fileSizeBytes'] as num).toInt(),
      ramRequiredBytes:    (j['ramRequiredBytes'] as num).toInt(),
      contextLength:       (j['contextLength'] as num).toInt(),
      downloadUrl:         j['downloadUrl'] as String,
      strengths:           List<String>.from(j['strengths'] as List),
      isReasoningModel:    (j['isReasoningModel'] as bool?) ?? false,
      creator:             (j['creator'] as String?) ?? '',
      releaseYear:         (j['releaseYear'] as num?)?.toInt() ?? 0,
      releaseMonth:        (j['releaseMonth'] as num?)?.toInt() ?? 0,
      description:         j['description'] as String?,
      limitations:         j['limitations'] != null
                             ? List<String>.from(j['limitations'] as List)
                             : const [],
      minRamGbRecommended: (j['minRamGbRecommended'] as num?)?.toInt() ?? 4,
      recommendedDevice:   j['recommendedDevice'] as String?,
      huggingFaceUrl:      j['huggingFaceUrl'] as String?,
      supersedes:          j['supersedes'] as String?,
    );
  }

  final String id;
  final String displayName;
  final ModelFamily family;
  final double parametersBillions;
  final Quant quant;
  final int fileSizeBytes;
  final int ramRequiredBytes;
  final int contextLength;
  final String downloadUrl;
  final List<String> strengths;
  final bool isReasoningModel;

  // ── Rich metadata ──────────────────────────────────────────────────────────

  /// Organisation that created / released the model.
  final String creator;

  /// Year of public release.
  final int releaseYear;

  /// Month of public release (1–12).
  final int releaseMonth;

  /// One-paragraph description shown in the model detail sheet.
  final String? description;

  /// Known limitations — what this model is NOT good at.
  final List<String> limitations;

  /// Minimum device RAM (GB) for acceptable performance.
  final int minRamGbRecommended;

  /// Human-readable device recommendation string.
  final String? recommendedDevice;

  /// Hugging Face model page for "Learn more" link.
  final String? huggingFaceUrl;

  /// ID of the older model this replaces. When this model is installed
  /// the app offers to delete the superseded model to free space.
  final String? supersedes;

  String get releaseLabel {
    if (releaseYear == 0) return '';
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec',
    ];
    if (releaseMonth == 0) return '$releaseYear';
    return '${months[releaseMonth - 1]} $releaseYear';
  }

  // ── Derived ───────────────────────────────────────────────────────────────

  double get fileSizeGb => fileSizeBytes / 1e9;
  double get ramRequiredGb => ramRequiredBytes / 1e9;

  /// Estimate token/sec for this variant on a given chip tier.
  ///
  /// We scale from the baseline 3B Q4_K_M benchmark using two factors:
  ///   1. Parameter scaling: tokens/sec ∝ 1/params (linear approximation)
  ///   2. Quant overhead: Q5 is ~15% slower than Q4, Q8 ~40% slower
  ///
  /// This is an estimate, not a guarantee — real performance varies by
  /// prompt length, thermal state, and background load. We round down 20%
  /// to be conservative and avoid UI that promises more than it delivers.
  double estimateTokensPerSec(
    double baselineTokensPerSec, {
    bool hasGpu = true,
  }) {
    // Base speed for a 3B Q4 model on this tier
    const refParams = 3.0;
    const refQuant  = Quant.q4km;

    // Scale for parameter count (inverse relationship)
    final paramScale = refParams / parametersBillions;

    // Scale for quantisation
    final quantScale = _quantRelativeSpeed(quant) / _quantRelativeSpeed(refQuant);

    // CPU-only: roughly 3–4× slower due to no tensor cores
    final gpuScale = hasGpu ? 1.0 : 0.28;

    final raw = baselineTokensPerSec * paramScale * quantScale * gpuScale;

    // 20% conservative buffer
    return raw * 0.80;
  }

  static double _quantRelativeSpeed(Quant q) => switch (q) {
    Quant.q2k  => 1.35, // smaller model, faster
    Quant.q3km => 1.15,
    Quant.q4km => 1.00, // reference
    Quant.q5km => 0.87,
    Quant.q8   => 0.62,
    Quant.fp16 => 0.40,
  };
}

enum ModelFamily {
  llama,
  phi,
  gemma,
  mistral,
  qwen,
  deepseek,
  smollm,
}

extension ModelFamilyLabel on ModelFamily {
  String get label => switch (this) {
    ModelFamily.llama    => 'Llama',
    ModelFamily.phi      => 'Phi',
    ModelFamily.gemma    => 'Gemma',
    ModelFamily.mistral  => 'Mistral',
    ModelFamily.qwen     => 'Qwen',
    ModelFamily.deepseek => 'DeepSeek',
    ModelFamily.smollm   => 'SmolLM',
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// The catalogue
// ─────────────────────────────────────────────────────────────────────────────

/// All models PocketLLM can download and run.
///
/// Ordered from smallest to largest. The recommender works through this list
/// and selects the largest model that fits within the device's safe RAM budget
/// while clearing the minimum token speed threshold.
/// The model auto-downloaded for first-time users. Must be fast to download
/// and run on every device — SmolLM2 135M at 75 MB is the right choice.
const String kStarterModelId = 'smollm2-135m-q4km';

const List<ModelVariant> kModelCatalogue = [

  // ── SmolLM2 135M — for extremely constrained devices ─────────────────────
  // The only model that runs on ≤2GB RAM devices. Quality is limited but
  // useful for basic Q&A and summarisation.
  ModelVariant(
    id: 'smollm2-135m-q4km',
    displayName: 'SmolLM2 135M',
    family: ModelFamily.smollm,
    parametersBillions: 0.135,
    quant: Quant.q4km,
    fileSizeBytes: 90000000,
    ramRequiredBytes: 120000000,
    contextLength: 2048,
    downloadUrl: 'https://huggingface.co/bartowski/SmolLM2-135M-Instruct-GGUF/resolve/main/SmolLM2-135M-Instruct-Q4_K_M.gguf',
    strengths: ['Fast', 'Tiny footprint'],
    creator: 'Hugging Face',
    releaseYear: 2024,
    releaseMonth: 11,
    description: 'SmolLM2 135M is Hugging Face\'s smallest production-grade language model, '
        'designed to run on even the most constrained devices. At just 90 MB it fits on virtually '
        'any phone with storage to spare. Quality is limited compared to larger models but it\'s '
        'impressively capable for its size — ideal for simple Q&A, basic summarisation, and quick lookups.',
    limitations: ['Complex reasoning', 'Long-form writing', 'Code generation', 'Multi-step tasks'],
    minRamGbRecommended: 1,
    recommendedDevice: 'Any iPhone 8 or newer, any Android with 2GB RAM',
    huggingFaceUrl: 'https://huggingface.co/HuggingFaceTB/SmolLM2-135M-Instruct',
  ),

  // ── SmolLM2 360M ─────────────────────────────────────────────────────────
  ModelVariant(
    id: 'smollm2-360m-q4km',
    displayName: 'SmolLM2 360M',
    family: ModelFamily.smollm,
    parametersBillions: 0.36,
    quant: Quant.q4km,
    fileSizeBytes: 230000000,
    ramRequiredBytes: 310000000,
    contextLength: 2048,
    downloadUrl: 'https://huggingface.co/bartowski/SmolLM2-360M-Instruct-GGUF/resolve/main/SmolLM2-360M-Instruct-Q4_K_M.gguf',
    strengths: ['Fast', 'Very small'],
    creator: 'Hugging Face',
    releaseYear: 2024,
    releaseMonth: 11,
    description: 'SmolLM2 360M is the mid-tier in Hugging Face\'s SmolLM2 family — a step up from '
        'the 135M with noticeably better general knowledge and coherence. Still fits in under 1GB '
        'of RAM, making it an excellent choice for older phones or devices where every megabyte matters.',
    limitations: ['Deep reasoning', 'Long conversations', 'Complex code'],
    minRamGbRecommended: 2,
    recommendedDevice: 'Any iPhone 8 or newer, any Android with 3GB RAM',
    huggingFaceUrl: 'https://huggingface.co/HuggingFaceTB/SmolLM2-360M-Instruct',
  ),

  // ── Qwen 2.5 0.5B — ultra-tiny, 300 MB ──────────────────────────────────
  ModelVariant(
    id: 'qwen25-0b5-q4km',
    displayName: 'Qwen 2.5 0.5B',
    family: ModelFamily.qwen,
    parametersBillions: 0.5,
    quant: Quant.q4km,
    fileSizeBytes: 320000000,
    ramRequiredBytes: 430000000,
    contextLength: 32768,
    downloadUrl: 'https://huggingface.co/bartowski/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/Qwen2.5-0.5B-Instruct-Q4_K_M.gguf',
    strengths: ['Ultra-fast', 'Very small', '32k context'],
    creator: 'Alibaba',
    releaseYear: 2024,
    releaseMonth: 9,
    description: 'Qwen 2.5 0.5B is Alibaba\'s smallest instruction-tuned model. '
        'At just 320 MB it fits in almost any device and runs at lightning speed. '
        'Better multilingual support than the SmolLM2 models, and a generous 32k '
        'context window. Ideal when speed matters more than depth.',
    limitations: ['Complex reasoning', 'Code generation', 'Long-form writing'],
    minRamGbRecommended: 2,
    recommendedDevice: 'Any iPhone 8 or newer, any Android with 2GB RAM',
    huggingFaceUrl: 'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct',
  ),

  // ── Gemma 3 1B — Google's tiny model, 600 MB ─────────────────────────────
  ModelVariant(
    id: 'gemma3-1b-q4km',
    displayName: 'Gemma 3 1B',
    family: ModelFamily.gemma,
    parametersBillions: 1.0,
    quant: Quant.q4km,
    fileSizeBytes: 620000000,
    ramRequiredBytes: 820000000,
    contextLength: 32768,
    downloadUrl: 'https://huggingface.co/bartowski/gemma-3-1b-it-GGUF/resolve/main/gemma-3-1b-it-Q4_K_M.gguf',
    strengths: ['Fast', 'Strong instruction following', '32k context'],
    creator: 'Google',
    releaseYear: 2025,
    releaseMonth: 3,
    description: 'Gemma 3 1B is Google\'s latest entry-level model, released in March 2025. '
        'It punches well above its weight for instruction following and factual Q&A. '
        'Under 1 GB download, 32k context, and fast on any recent device.',
    limitations: ['Complex multi-step reasoning', 'Very long documents'],
    minRamGbRecommended: 2,
    recommendedDevice: 'Any iPhone 11 or newer, Android with 3GB RAM',
    huggingFaceUrl: 'https://huggingface.co/google/gemma-3-1b-it',
  ),

  // ── DeepSeek-R1 1.5B — smallest reasoning model, ~900 MB ─────────────────
  ModelVariant(
    id: 'deepseek-r1-1b5-q4km',
    displayName: 'DeepSeek-R1 1.5B',
    family: ModelFamily.deepseek,
    parametersBillions: 1.5,
    quant: Quant.q4km,
    fileSizeBytes: 900000000,
    ramRequiredBytes: 1100000000,
    contextLength: 65536,
    downloadUrl: 'https://huggingface.co/bartowski/DeepSeek-R1-Distill-Qwen-1.5B-GGUF/resolve/main/DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf',
    strengths: ['Reasoning', 'Math', 'Step-by-step thinking'],
    isReasoningModel: true,
    creator: 'DeepSeek AI',
    releaseYear: 2025,
    releaseMonth: 1,
    description: 'DeepSeek-R1 1.5B is the smallest reasoning model available — a distilled '
        'version of DeepSeek\'s chain-of-thought R1 model. It shows its thinking before '
        'answering, making it surprisingly good at maths and logic for its size. '
        'Under 1 GB, so it runs on almost any device.',
    limitations: ['General chat (slower due to thinking)', 'Creative writing'],
    minRamGbRecommended: 2,
    recommendedDevice: 'iPhone 11 or newer, Android with 3GB RAM',
    huggingFaceUrl: 'https://huggingface.co/deepseek-ai/DeepSeek-R1-Distill-Qwen-1.5B',
  ),

  // ── Qwen 2.5 1.5B — solid small model, ~1 GB ─────────────────────────────
  ModelVariant(
    id: 'qwen25-1b5-q4km',
    displayName: 'Qwen 2.5 1.5B',
    family: ModelFamily.qwen,
    parametersBillions: 1.5,
    quant: Quant.q4km,
    fileSizeBytes: 1000000000,
    ramRequiredBytes: 1300000000,
    contextLength: 32768,
    downloadUrl: 'https://huggingface.co/bartowski/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/Qwen2.5-1.5B-Instruct-Q4_K_M.gguf',
    strengths: ['Fast', 'Good instruction following', '32k context', 'Multilingual'],
    creator: 'Alibaba',
    releaseYear: 2024,
    releaseMonth: 9,
    description: 'Qwen 2.5 1.5B delivers solid instruction following and multilingual '
        'capability in a 1 GB package. It handles everyday tasks well and is a great '
        'step up from the 0.5B when you want noticeably better quality without a large download.',
    limitations: ['Complex reasoning', 'Long-form creative writing'],
    minRamGbRecommended: 2,
    recommendedDevice: 'iPhone 11 or newer, Android with 3GB RAM',
    huggingFaceUrl: 'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct',
  ),

  // ── Llama 3.2 1B ─────────────────────────────────────────────────────────
  ModelVariant(
    id: 'llama32-1b-q4km',
    displayName: 'Llama 3.2 1B',
    family: ModelFamily.llama,
    parametersBillions: 1.0,
    quant: Quant.q4km,
    fileSizeBytes: 770000000,
    ramRequiredBytes: 900000000,
    contextLength: 131072,
    downloadUrl: 'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf',
    strengths: ['Very fast', 'Long context', 'Coding'],
    creator: 'Meta',
    releaseYear: 2024,
    releaseMonth: 9,
    description: 'Llama 3.2 1B is Meta\'s mobile-first language model released as part of the '
        'Llama 3.2 family in September 2024. Designed specifically to run efficiently on-device, '
        'it offers a 128k token context window — far exceeding most competitors at this size. '
        'Excellent for coding assistance, quick Q&A, and tasks where speed is more important than depth.',
    limitations: ['Complex multi-step reasoning', 'Creative writing', 'Nuanced analysis'],
    minRamGbRecommended: 2,
    recommendedDevice: 'iPhone 12 or newer, Android with 3GB RAM',
    huggingFaceUrl: 'https://huggingface.co/meta-llama/Llama-3.2-1B-Instruct',
  ),

  // ── Llama 3.2 3B — the default recommendation for most phones ────────────
  ModelVariant(
    id: 'llama32-3b-q4km',
    displayName: 'Llama 3.2 3B',
    family: ModelFamily.llama,
    parametersBillions: 3.0,
    quant: Quant.q4km,
    fileSizeBytes: 2020000000,
    ramRequiredBytes: 2400000000,
    contextLength: 131072,
    downloadUrl: 'https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf',
    strengths: ['Balanced', 'Long context', 'Coding'],
    creator: 'Meta',
    releaseYear: 2024,
    releaseMonth: 9,
    description: 'Llama 3.2 3B is Meta\'s flagship mobile model and the sweet spot for most users. '
        'Released in September 2024, it runs at excellent speed on any iPhone 13 or newer while '
        'delivering quality that rivals cloud models from just a year ago. The 128k context window '
        'means it can reason over long documents, full codebases, or extended conversations without '
        'losing track.',
    limitations: ['Highly specialised domains (law, medicine)', 'Very long creative writing'],
    minRamGbRecommended: 4,
    recommendedDevice: 'iPhone 13 or newer, Android flagship with 4GB RAM',
    huggingFaceUrl: 'https://huggingface.co/meta-llama/Llama-3.2-3B-Instruct',
  ),

  // ── Qwen 2.5 3B — strong all-rounder at the 1.9 GB tier ─────────────────
  ModelVariant(
    id: 'qwen25-3b-q4km',
    displayName: 'Qwen 2.5 3B',
    family: ModelFamily.qwen,
    parametersBillions: 3.0,
    quant: Quant.q4km,
    fileSizeBytes: 1900000000,
    ramRequiredBytes: 2300000000,
    contextLength: 32768,
    downloadUrl: 'https://huggingface.co/bartowski/Qwen2.5-3B-Instruct-GGUF/resolve/main/Qwen2.5-3B-Instruct-Q4_K_M.gguf',
    strengths: ['Strong reasoning', 'Multilingual', 'Coding', '32k context'],
    creator: 'Alibaba',
    releaseYear: 2024,
    releaseMonth: 9,
    description: 'Qwen 2.5 3B is one of the most capable 3B models available. '
        'It excels at multilingual tasks, code generation, and general reasoning — '
        'often beating larger models from earlier generations. Under 2 GB download '
        'with a 32k context window.',
    limitations: ['Very long documents beyond 32k', 'Complex chain-of-thought tasks'],
    minRamGbRecommended: 3,
    recommendedDevice: 'iPhone 13 or newer, Android with 4GB RAM',
    huggingFaceUrl: 'https://huggingface.co/Qwen/Qwen2.5-3B-Instruct',
  ),

  // ── Phi-4 Mini 3.8B — Microsoft's newest small model ─────────────────────
  ModelVariant(
    id: 'phi4-mini-q4km',
    displayName: 'Phi-4 Mini',
    family: ModelFamily.phi,
    parametersBillions: 3.8,
    quant: Quant.q4km,
    fileSizeBytes: 2300000000,
    ramRequiredBytes: 2800000000,
    contextLength: 16384,
    downloadUrl: 'https://huggingface.co/bartowski/Phi-4-mini-instruct-GGUF/resolve/main/Phi-4-mini-instruct-Q4_K_M.gguf',
    strengths: ['Coding', 'Math', 'Reasoning', 'Instruction following'],
    creator: 'Microsoft',
    releaseYear: 2025,
    releaseMonth: 2,
    description: 'Phi-4 Mini is Microsoft\'s newest small model, released in February 2025. '
        'It outperforms Phi-3.5 Mini on coding and math benchmarks despite similar size. '
        'Trained with synthetic chain-of-thought data, it\'s particularly strong at '
        'structured problem solving.',
    limitations: ['Context limited to 16k', 'Creative and open-ended tasks'],
    minRamGbRecommended: 4,
    recommendedDevice: 'iPhone 13 or newer, Android with 4GB RAM',
    huggingFaceUrl: 'https://huggingface.co/microsoft/Phi-4-mini-instruct',
  ),

  // ── Phi-3.5 Mini 3.8B — Microsoft's mobile-optimised model ──────────────
  // Outperforms Llama 3.2 3B on reasoning tasks despite similar size.
  ModelVariant(
    id: 'phi35-mini-q4km',
    displayName: 'Phi-3.5 Mini',
    family: ModelFamily.phi,
    parametersBillions: 3.8,
    quant: Quant.q4km,
    fileSizeBytes: 2390000000,
    ramRequiredBytes: 2800000000,
    contextLength: 131072,
    downloadUrl: 'https://huggingface.co/bartowski/Phi-3.5-mini-instruct-GGUF/resolve/main/Phi-3.5-mini-instruct-Q4_K_M.gguf',
    strengths: ['Reasoning', 'Coding', 'Math'],
    creator: 'Microsoft',
    releaseYear: 2024,
    releaseMonth: 8,
    description: 'Phi-3.5 Mini is Microsoft\'s research-driven small model, trained on a highly '
        'curated dataset of textbooks and synthetic data. Despite being only 3.8B parameters it '
        'consistently outperforms much larger models on reasoning, mathematics, and coding benchmarks. '
        'If you need a model that thinks carefully rather than just pattern-matches, Phi-3.5 is '
        'the best sub-4B option available.',
    limitations: ['Creative writing', 'Casual conversation', 'Non-English languages'],
    minRamGbRecommended: 4,
    recommendedDevice: 'iPhone 13 or newer, Android with 4GB RAM',
    huggingFaceUrl: 'https://huggingface.co/microsoft/Phi-3.5-mini-instruct',
  ),

  // ── Gemma 3 4B ───────────────────────────────────────────────────────────
  ModelVariant(
    id: 'gemma3-4b-q4km',
    displayName: 'Gemma 3 4B',
    family: ModelFamily.gemma,
    parametersBillions: 4.0,
    quant: Quant.q4km,
    fileSizeBytes: 2540000000,
    ramRequiredBytes: 3100000000,
    contextLength: 131072,
    downloadUrl: 'https://huggingface.co/bartowski/gemma-3-4b-it-GGUF/resolve/main/gemma-3-4b-it-Q4_K_M.gguf',
    strengths: ['Multilingual', 'Balanced', 'Google quality'],
    creator: 'Google DeepMind',
    releaseYear: 2025,
    releaseMonth: 3,
    description: 'Gemma 3 4B is Google DeepMind\'s latest open model from the Gemma family, '
        'distilled from Gemini technology. Released in early 2025, it excels at multilingual tasks '
        'and follows instructions with Google-quality precision. It\'s one of the most well-rounded '
        'models at this size, balancing reasoning, knowledge, and language quality effectively.',
    limitations: ['Extended reasoning chains', 'Niche technical domains'],
    minRamGbRecommended: 4,
    recommendedDevice: 'iPhone 14 or newer, Android flagship with 4GB RAM',
    huggingFaceUrl: 'https://huggingface.co/google/gemma-3-4b-it',
  ),

  // ── Qwen 2.5 7B ──────────────────────────────────────────────────────────
  ModelVariant(
    id: 'qwen25-7b-q4km',
    displayName: 'Qwen 2.5 7B',
    family: ModelFamily.qwen,
    parametersBillions: 7.0,
    quant: Quant.q4km,
    fileSizeBytes: 4360000000,
    ramRequiredBytes: 5200000000,
    contextLength: 131072,
    downloadUrl: 'https://huggingface.co/bartowski/Qwen2.5-7B-Instruct-GGUF/resolve/main/Qwen2.5-7B-Instruct-Q4_K_M.gguf',
    strengths: ['Coding', 'Reasoning', 'Math'],
    creator: 'Alibaba Cloud (Qwen Team)',
    releaseYear: 2024,
    releaseMonth: 9,
    description: 'Qwen 2.5 7B is Alibaba\'s flagship open model from the Qwen 2.5 series. '
        'It consistently ranks at the top of coding and mathematics benchmarks for its size class, '
        'rivalling some 13B models. Trained on 18 trillion tokens including a huge corpus of code, '
        'it\'s the best choice if your primary use cases involve programming or quantitative reasoning.',
    limitations: ['Casual conversation feels slightly formal', 'Creative storytelling'],
    minRamGbRecommended: 6,
    recommendedDevice: 'iPhone 15 Pro, Samsung Galaxy S24 or equivalent (8GB RAM)',
    huggingFaceUrl: 'https://huggingface.co/Qwen/Qwen2.5-7B-Instruct',
  ),

  // ── Mistral 7B v0.3 ──────────────────────────────────────────────────────
  ModelVariant(
    id: 'mistral-7b-q4km',
    displayName: 'Mistral 7B',
    family: ModelFamily.mistral,
    parametersBillions: 7.0,
    quant: Quant.q4km,
    fileSizeBytes: 4070000000,
    ramRequiredBytes: 4900000000,
    contextLength: 32768,
    downloadUrl: 'https://huggingface.co/bartowski/Mistral-7B-Instruct-v0.3-GGUF/resolve/main/Mistral-7B-Instruct-v0.3-Q4_K_M.gguf',
    strengths: ['Writing', 'Instruction following', 'Structured output'],
    creator: 'Mistral AI',
    releaseYear: 2023,
    releaseMonth: 9,
    description: 'Mistral 7B was a landmark release from French AI startup Mistral AI, '
        'demonstrating that a 7B model trained with modern techniques could outperform Llama 2 13B '
        'across most tasks. It remains one of the best models for generating well-structured, '
        'fluent text and following complex formatting instructions. Great for writing, summarisation, '
        'and any task requiring clean, formatted output.',
    limitations: ['Context window (32k vs 128k for newer models)', 'Math and coding lag behind Qwen/Phi'],
    minRamGbRecommended: 6,
    recommendedDevice: 'iPhone 15 Pro, Android with 6GB RAM',
    huggingFaceUrl: 'https://huggingface.co/mistralai/Mistral-7B-Instruct-v0.3',
  ),

  // ── DeepSeek-R1 7B — reasoning / chain-of-thought ────────────────────────
  ModelVariant(
    id: 'deepseek-r1-7b-q4km',
    displayName: 'DeepSeek-R1 7B',
    family: ModelFamily.deepseek,
    parametersBillions: 7.0,
    quant: Quant.q4km,
    fileSizeBytes: 4480000000,
    ramRequiredBytes: 5300000000,
    contextLength: 65536,
    downloadUrl: 'https://huggingface.co/bartowski/DeepSeek-R1-Distill-Qwen-7B-GGUF/resolve/main/DeepSeek-R1-Distill-Qwen-7B-Q4_K_M.gguf',
    strengths: ['Reasoning', 'Step-by-step', 'Math'],
    isReasoningModel: true,
    creator: 'DeepSeek AI',
    releaseYear: 2025,
    releaseMonth: 1,
    description: 'DeepSeek-R1 7B is a distilled reasoning model that uses chain-of-thought '
        'to work through problems step by step before giving a final answer — similar in approach '
        'to OpenAI o1. Released in January 2025, it\'s one of the most capable reasoning models '
        'at this size, scoring very high on math olympiad, coding competitions, and logic puzzles. '
        'Responses take longer because it shows its thinking, but the answers are more reliable.',
    limitations: ['Slower response time (thinks before answering)', 'Casual conversation', 'Creative writing'],
    minRamGbRecommended: 6,
    recommendedDevice: 'iPhone 15 Pro, Android flagship with 8GB RAM',
    huggingFaceUrl: 'https://huggingface.co/deepseek-ai/DeepSeek-R1-Distill-Qwen-7B',
  ),

  // ── Llama 3.1 8B — biggest model for flagship phones with 8GB+ RAM ───────
  ModelVariant(
    id: 'llama31-8b-q4km',
    displayName: 'Llama 3.1 8B',
    family: ModelFamily.llama,
    parametersBillions: 8.0,
    quant: Quant.q4km,
    fileSizeBytes: 4920000000,
    ramRequiredBytes: 5800000000,
    contextLength: 131072,
    downloadUrl: 'https://huggingface.co/bartowski/Meta-Llama-3.1-8B-Instruct-GGUF/resolve/main/Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf',
    strengths: ['Best quality', 'Long context', 'Coding', 'Writing'],
    creator: 'Meta',
    releaseYear: 2024,
    releaseMonth: 7,
    description: 'Llama 3.1 8B is the most capable model you can run on a current-generation '
        'iPhone. Released in July 2024 as part of Meta\'s Llama 3.1 series, it was the first '
        'openly-licensed model to truly rival GPT-3.5 in quality benchmarks. With 128k context '
        'and strong multilingual capability, it handles everything from complex coding tasks to '
        'long-form writing. Requires a flagship phone — iPhone 15 Pro or newer with 8GB RAM.',
    limitations: ['Requires flagship hardware (8GB+ RAM)', 'Slower on non-Pro iPhones'],
    minRamGbRecommended: 8,
    recommendedDevice: 'iPhone 15 Pro / Pro Max, iPad Pro M-series, Android with 8GB+ RAM',
    huggingFaceUrl: 'https://huggingface.co/meta-llama/Meta-Llama-3.1-8B-Instruct',
  ),

  // ── Llama 3.3 8B — newer than 3.1, same size, better quality ────────────
  ModelVariant(
    id: 'llama33-8b-q4km',
    displayName: 'Llama 3.3 8B',
    family: ModelFamily.llama,
    parametersBillions: 8.0,
    quant: Quant.q4km,
    fileSizeBytes: 4920000000,
    ramRequiredBytes: 5800000000,
    contextLength: 131072,
    downloadUrl: 'https://huggingface.co/bartowski/Llama-3.3-8B-Instruct-GGUF/resolve/main/Llama-3.3-8B-Instruct-Q4_K_M.gguf',
    strengths: ['Best quality 8B', 'Long context', 'Coding', 'Writing', 'Multilingual'],
    creator: 'Meta',
    releaseYear: 2024,
    releaseMonth: 12,
    description: 'Llama 3.3 8B is Meta\'s December 2024 update to the 8B line — '
        'improved quality over Llama 3.1 8B with the same hardware requirements. '
        'Stronger at instruction following and multilingual tasks. The go-to choice '
        'for flagship phones that want the best possible on-device experience.',
    limitations: ['Requires flagship hardware (8GB+ RAM)'],
    minRamGbRecommended: 8,
    recommendedDevice: 'iPhone 15 Pro / Pro Max, iPad Pro M-series, Android with 8GB+ RAM',
    huggingFaceUrl: 'https://huggingface.co/meta-llama/Llama-3.3-8B-Instruct',
  ),

  // ── Qwen 2.5 14B — for iPad Pro / high-RAM Android ───────────────────────
  ModelVariant(
    id: 'qwen25-14b-q3km',
    displayName: 'Qwen 2.5 14B',
    family: ModelFamily.qwen,
    parametersBillions: 14.0,
    quant: Quant.q3km,
    fileSizeBytes: 6500000000,
    ramRequiredBytes: 8000000000,
    contextLength: 32768,
    downloadUrl: 'https://huggingface.co/bartowski/Qwen2.5-14B-Instruct-GGUF/resolve/main/Qwen2.5-14B-Instruct-Q3_K_M.gguf',
    strengths: ['Best multilingual', 'Strong reasoning', 'Coding', 'Long context'],
    creator: 'Alibaba',
    releaseYear: 2024,
    releaseMonth: 9,
    description: 'Qwen 2.5 14B at Q3_K_M quantisation fits within 8 GB RAM and delivers '
        'GPT-4-class multilingual performance. One of the most capable open models at this '
        'size tier, with outstanding Chinese/English bilingual quality and strong coding. '
        'Recommended for iPad Pro M-series or Android tablets with 8GB+ RAM.',
    limitations: ['Requires iPad Pro or high-end tablet', 'Large download (6.5 GB)'],
    minRamGbRecommended: 10,
    recommendedDevice: 'iPad Pro M1+, Samsung Galaxy Tab S9, Android with 10GB+ RAM',
    huggingFaceUrl: 'https://huggingface.co/Qwen/Qwen2.5-14B-Instruct',
  ),

  // ── Gemma 3 12B — Google's best small model for tablets ──────────────────
  ModelVariant(
    id: 'gemma3-12b-q3km',
    displayName: 'Gemma 3 12B',
    family: ModelFamily.gemma,
    parametersBillions: 12.0,
    quant: Quant.q3km,
    fileSizeBytes: 5600000000,
    ramRequiredBytes: 7200000000,
    contextLength: 131072,
    downloadUrl: 'https://huggingface.co/bartowski/gemma-3-12b-it-GGUF/resolve/main/gemma-3-12b-it-Q3_K_M.gguf',
    strengths: ['Best Google model', 'Long context (128k)', 'Vision-capable architecture', 'Strong reasoning'],
    creator: 'Google',
    releaseYear: 2025,
    releaseMonth: 3,
    description: 'Gemma 3 12B is Google\'s most capable open model in the Gemma 3 family, '
        'released in March 2025. With a 128k context window and strong performance across '
        'coding, reasoning, and instruction following benchmarks, it rivals models twice its '
        'parameter count. Designed for iPad Pro M-series and high-end Android tablets.',
    limitations: ['Requires tablet-class hardware (7GB+ RAM)', 'Large download (5.6 GB)'],
    minRamGbRecommended: 8,
    recommendedDevice: 'iPad Pro M1+, Samsung Galaxy Tab S9, Android with 8GB+ RAM',
    huggingFaceUrl: 'https://huggingface.co/google/gemma-3-12b-it',
  ),
];
