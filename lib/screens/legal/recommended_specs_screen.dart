import 'package:flutter/material.dart';
import '../../features/device_recommender/model_catalogue.dart';
import '../../theme/theme.dart';

class RecommendedSpecsScreen extends StatelessWidget {
  const RecommendedSpecsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceBase,
      appBar: AppBar(
        title: const Text('Device Requirements'),
        backgroundColor: AppColors.surfaceBase,
      ),
      body: const SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 40),
        child: _Content(),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        _h1('Device Requirements'),
        _body(
          'PintSizeAi runs AI models entirely on your device — no cloud compute needed. '
          'The performance you get depends heavily on your hardware. '
          'Here\'s what to expect.',
        ),

        const SizedBox(height: 28),
        _TierCard(
          tier: 'Minimum',
          color: const Color(0xFFE57373),
          icon: Icons.warning_amber_outlined,
          ios: 'iPhone 11 or XS\niOS 16 or newer',
          android: 'Snapdragon 855 / Exynos 990\nAndroid 10+\n4 GB RAM',
          storage: '2 GB free',
          experience:
              'Runs SmolLM2 (135M–360M). Very fast responses but limited quality. '
              'Good for simple Q&A and quick tasks.',
        ),

        const SizedBox(height: 16),
        _TierCard(
          tier: 'Recommended',
          color: const Color(0xFFFFB74D),
          icon: Icons.thumb_up_outlined,
          ios: 'iPhone 13 or newer\niOS 16 or newer',
          android: 'Snapdragon 888 / Exynos 2100\nAndroid 11+\n6 GB RAM',
          storage: '5 GB free',
          experience:
              'Runs Llama 3.2 3B or Phi-3.5 Mini comfortably. Good all-round '
              'quality at 10–20 tokens/sec. Best balance of capability and speed.',
        ),

        const SizedBox(height: 16),
        _TierCard(
          tier: 'Best Experience',
          color: AppColors.accentGreen,
          icon: Icons.star_outline,
          ios: 'iPhone 15 Pro / Pro Max\niPad Pro (M1 or newer)',
          android: 'Snapdragon 8 Gen 3+\nAndroid 12+\n8 GB+ RAM',
          storage: '10 GB free',
          experience:
              'Runs Llama 3.1 8B, Qwen 2.5 7B, or DeepSeek-R1 at full quality. '
              '15–25 tokens/sec on the best hardware. Flagship-class AI fully offline.',
        ),

        const SizedBox(height: 32),
        _sectionTitle('Per-Model Requirements'),
        const SizedBox(height: 12),
        ...kModelCatalogue.map((m) => _ModelRow(model: m)),

        const SizedBox(height: 32),
        _sectionTitle('Why RAM Matters'),
        const SizedBox(height: 8),
        _body(
          'AI models must be fully loaded into memory before inference begins. '
          'A 4 GB model needs at least 4.5 GB of free RAM (model + KV cache). '
          'If your device doesn\'t have enough free RAM, the OS will kill the app '
          'or the model will fail to load.\n\n'
          'iOS manages memory aggressively — close background apps before loading '
          'large models. On iPad Pro with 8–16 GB RAM this is rarely an issue.',
        ),

        const SizedBox(height: 16),
        _sectionTitle('Why Storage Matters'),
        const SizedBox(height: 8),
        _body(
          'Model files (GGUF format) are stored permanently on your device and '
          'must be downloaded before first use. A Llama 3.1 8B model is about '
          '5 GB. Make sure you have enough free storage before downloading.\n\n'
          'Models are stored in the app\'s document directory. Deleting the app '
          'removes all downloaded models.',
        ),
      ],
    );
  }

  Widget _h1(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(text,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                height: 1.3)),
      );

  Widget _sectionTitle(String text) => Text(
        text.toUpperCase(),
        style: AppTypography.sectionLabel,
      );

  Widget _body(String text) => Text(text,
      style: TextStyle(
          color: AppColors.textMuted, fontSize: 14, height: 1.65));
}

class _TierCard extends StatelessWidget {
  const _TierCard({
    required this.tier,
    required this.color,
    required this.icon,
    required this.ios,
    required this.android,
    required this.storage,
    required this.experience,
  });

  final String tier;
  final Color color;
  final IconData icon;
  final String ios;
  final String android;
  final String storage;
  final String experience;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceOverlay,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Text(tier,
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 14)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('iPhone / iPad'),
                    Text(ios,
                        style: TextStyle(
                            color: AppColors.textDefault,
                            fontSize: 13,
                            height: 1.5)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Android'),
                    Text(android,
                        style: TextStyle(
                            color: AppColors.textDefault,
                            fontSize: 13,
                            height: 1.5)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _label('Free storage needed'),
          Text(storage,
              style: TextStyle(
                  color: AppColors.textDefault,
                  fontSize: 13,
                  height: 1.5)),
          const SizedBox(height: 12),
          Divider(color: AppColors.borderDefault, height: 1),
          const SizedBox(height: 12),
          Text(experience,
              style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13,
                  height: 1.55)),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Text(text,
            style: TextStyle(
                color: AppColors.textDim,
                fontSize: 11,
                fontWeight: FontWeight.w500)),
      );
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({required this.model});
  final ModelVariant model;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.surfaceOverlay,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(model.displayName,
                style: AppTypography.modelName),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${model.minRamGbRecommended} GB RAM',
              style: AppTypography.modelDesc,
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${model.fileSizeGb.toStringAsFixed(1)} GB storage',
              style: AppTypography.modelDesc,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
