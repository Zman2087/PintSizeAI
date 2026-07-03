/// Downloadable Stable Diffusion Core ML model catalogue.
/// Each entry describes a model available from HuggingFace in compiled CoreML format.

library;

class SDModel {
  const SDModel({
    required this.id,
    required this.displayName,
    required this.description,
    required this.downloadUrl,
    required this.totalSizeBytes,
    required this.minRamGb,
    required this.minIphone,
    required this.stepsRecommended,
    this.strengths = const [],
    this.notes,
  });

  final String id;
  final String displayName;
  final String description;
  final String downloadUrl;
  final int totalSizeBytes;
  final int minRamGb;
  final String minIphone;
  final int stepsRecommended;
  final List<String> strengths;
  final String? notes;

  double get totalSizeGb => totalSizeBytes / (1024 * 1024 * 1024);

  String get sizeLabel {
    if (totalSizeGb >= 1.0) return '${totalSizeGb.toStringAsFixed(1)} GB';
    return '${(totalSizeBytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  }
}

const kSDModelCatalogue = [
  SDModel(
    id: 'sd-v1-5-palettized',
    displayName: 'Stable Diffusion 1.5',
    description:
        'Apple\'s palettized (6-bit quantised) version of SD 1.5. '
        'Good all-round quality for photorealistic and artistic images. '
        '~1 GB download, runs on iPhone 12 or newer.',
    downloadUrl:
        'https://huggingface.co/apple/coreml-stable-diffusion-v1-5-palettized/resolve/main/'
        'coreml-stable-diffusion-v1-5-palettized_split_einsum_v2_compiled.zip',
    totalSizeBytes: 1073741824, // ~1 GB
    minRamGb: 4,
    minIphone: 'iPhone 12',
    stepsRecommended: 20,
    strengths: ['Photorealistic', 'Artistic styles', 'Portraits', 'Landscapes'],
    notes: 'Best balance of quality and speed for most iPhones.',
  ),
  SDModel(
    id: 'sd-v2-1-base-palettized',
    displayName: 'Stable Diffusion 2.1',
    description:
        'Upgraded base model with better prompt adherence and fewer artefacts. '
        'Requires more RAM than SD 1.5 but produces sharper images.',
    downloadUrl:
        'https://huggingface.co/apple/coreml-stable-diffusion-2-1-base-palettized/resolve/main/'
        'coreml-stable-diffusion-2-1-base-palettized_split_einsum_compiled.zip',
    totalSizeBytes: 2147483648, // ~2 GB
    minRamGb: 6,
    minIphone: 'iPhone 13',
    stepsRecommended: 20,
    strengths: ['Sharper detail', 'Better prompts', 'Consistent outputs'],
    notes: 'Recommended for iPhone 14 or newer.',
  ),
  SDModel(
    id: 'sd-v2-base-palettized',
    displayName: 'Stable Diffusion 2.0 (Compact)',
    description:
        'The smallest, fastest option (~1.1 GB). Good for quick generations on '
        'devices with less memory, with solid quality for its size.',
    downloadUrl:
        'https://huggingface.co/apple/coreml-stable-diffusion-2-base-palettized/resolve/main/'
        'coreml-stable-diffusion-2-base-palettized_split_einsum_v2_compiled.zip',
    totalSizeBytes: 1224736768, // ~1.14 GB
    minRamGb: 4,
    minIphone: 'iPhone 12',
    stepsRecommended: 20,
    strengths: ['Small & fast', 'Low memory', 'Quick previews'],
    notes: 'The lightest model — best if storage or RAM is tight.',
  ),
  SDModel(
    id: 'sd-v1-4-palettized',
    displayName: 'Stable Diffusion 1.4',
    description:
        'The classic SD 1.4 base (~1.6 GB). A slightly different artistic '
        'character to 1.5 — useful as an alternative style.',
    downloadUrl:
        'https://huggingface.co/apple/coreml-stable-diffusion-1-4-palettized/resolve/main/'
        'coreml-stable-diffusion-1-4-palettized_split_einsum_v2_compiled.zip',
    totalSizeBytes: 1685598208, // ~1.57 GB
    minRamGb: 4,
    minIphone: 'iPhone 12',
    stepsRecommended: 20,
    strengths: ['Artistic', 'Alternative style', 'Photorealistic'],
    notes: 'A good stylistic alternative to Stable Diffusion 1.5.',
  ),
];
