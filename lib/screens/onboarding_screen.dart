import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/device_recommender/model_catalogue.dart';
import '../features/device_recommender/recommender_providers.dart';
import '../features/models/model_providers.dart';
import '../features/models/model_download_service.dart';
import '../features/settings/settings_providers.dart';
import '../theme/theme.dart';

/// First-run guided setup: explains the app and downloads a model that fits
/// the user's device before dropping them into the chat.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  bool _installing = false;
  String? _installingId;

  Future<void> _finish() async {
    await ref.read(settingsServiceProvider).setOnboardingComplete(true);
    ref.invalidate(onboardingStatusProvider);
  }

  Future<void> _downloadAndStart(ModelVariant model) async {
    setState(() {
      _installing = true;
      _installingId = model.id;
    });
    try {
      await ref.read(modelActionsProvider).loadModel(model);
      await _finish();
    } catch (e) {
      if (mounted) {
        setState(() => _installing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final recAsync = ref.watch(modelRecommendationProvider);

    return Scaffold(
      backgroundColor: AppColors.surfaceBase,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              // Brand mark
              Center(
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: AppColors.accentGreen.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.auto_awesome,
                      color: AppColors.accentGreen, size: 40),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Welcome to PintSize AI',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                'A private AI assistant that runs entirely on your '
                'device — chat, voice, and images with nothing sent to the cloud.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 15, height: 1.4),
              ),
              const SizedBox(height: 28),
              const _FeatureRow(
                  icon: Icons.lock_outline, text: 'Fully offline & private'),
              const _FeatureRow(
                  icon: Icons.record_voice_over_outlined,
                  text: 'Talk with your voice'),
              const _FeatureRow(
                  icon: Icons.image_outlined, text: 'Generate & edit images'),
              const Spacer(),
              // Recommended model card
              recAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, __) => _ModelCard(
                  model: kModelCatalogue.firstWhere((m) => m.id == kStarterModelId),
                  installing: _installing,
                  progress: _progressFor(kStarterModelId),
                  onDownload: _installing
                      ? null
                      : () => _downloadAndStart(kModelCatalogue
                          .firstWhere((m) => m.id == kStarterModelId)),
                ),
                data: (rec) => _ModelCard(
                  model: rec.recommended,
                  installing: _installing,
                  progress: _progressFor(rec.recommended.id),
                  onDownload: _installing
                      ? null
                      : () => _downloadAndStart(rec.recommended),
                ),
              ),
              const SizedBox(height: 12),
              if (!_installing)
                TextButton(
                  onPressed: _finish,
                  child: const Text("I'll choose a model later",
                      style: TextStyle(color: AppColors.textMuted)),
                ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  double? _progressFor(String id) {
    if (!_installing || _installingId != id) return null;
    final st = ref.watch(downloadStatesProvider)[id];
    if (st == null) return 0.0;
    return st.progress;
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: AppColors.accentGreen, size: 20),
          const SizedBox(width: 14),
          Text(text,
              style: const TextStyle(color: Colors.white, fontSize: 15)),
        ],
      ),
    );
  }
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({
    required this.model,
    required this.installing,
    required this.progress,
    required this.onDownload,
  });
  final ModelVariant model;
  final bool installing;
  final double? progress;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    final sizeGb = model.fileSizeGb.toStringAsFixed(model.fileSizeGb < 1 ? 2 : 1);
    final pct = ((progress ?? 0) * 100).toInt();
    final isThisInstalling = installing && progress != null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceOverlay,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Recommended for your device',
                  style: TextStyle(
                      color: AppColors.accentGreen,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 8),
          Text(model.displayName,
              style: const TextStyle(
                  color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('${model.parametersBillions}B · ${model.quant.label} · $sizeGb GB',
              style: const TextStyle(color: AppColors.textDim, fontSize: 13)),
          const SizedBox(height: 14),
          if (isThisInstalling) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: pct > 0 ? progress : null,
                minHeight: 6,
                backgroundColor: AppColors.surfaceActive,
                valueColor:
                    const AlwaysStoppedAnimation(AppColors.accentGreen),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              pct > 0 ? 'Downloading…  $pct%' : 'Preparing…',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ] else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onDownload,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentGreen,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Download & Get Started',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              ),
            ),
        ],
      ),
    );
  }
}
