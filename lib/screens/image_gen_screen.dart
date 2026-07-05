import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/image_gen/image_gen_providers.dart';
import '../features/image_gen/sd_model_catalogue.dart';
import '../theme/theme.dart';

/// Full-screen sheet for managing Stable Diffusion models.
/// Accessible from Settings → Image Generation or the + menu.
class ImageGenScreen extends ConsumerWidget {
  const ImageGenScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(sdModelProvider);

    return Scaffold(
      backgroundColor: AppColors.surfaceBase,
      appBar: AppBar(
        title: const Text('Image Generation'),
        backgroundColor: AppColors.surfaceBase,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _InfoCard(status: status),
          const SizedBox(height: 12),
          const _PerformanceWarning(),
          const SizedBox(height: 20),
          _SectionHeader('Available Models'),
          const SizedBox(height: 10),
          ...kSDModelCatalogue.map((m) => _ModelCard(model: m, status: status)),
          const SizedBox(height: 24),
          _HowItWorksCard(),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.status});
  final SDModelStatus status;

  @override
  Widget build(BuildContext context) {
    final isReady = status.state == SDModelState.loaded;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isReady
            ? AppColors.accentGreen.withAlpha(20)
            : AppColors.surfaceOverlay,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isReady
              ? AppColors.accentGreen.withAlpha(60)
              : AppColors.borderDefault,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isReady ? Icons.check_circle_outline : Icons.auto_awesome_outlined,
            color: isReady ? AppColors.accentGreen : AppColors.textMuted,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isReady ? 'Image generation ready' : 'No model loaded',
                  style: AppTypography.modelName.copyWith(
                    color:
                        isReady ? AppColors.accentGreen : AppColors.textDefault,
                  ),
                ),
                Text(
                  isReady
                      ? 'Type "/image <prompt>" or tap + → Generate Image'
                      : 'Download a model below to generate images on-device.',
                  style: AppTypography.modelDesc,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _ModelCard extends ConsumerWidget {
  const _ModelCard({required this.model, required this.status});
  final SDModel model;
  final SDModelStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThisModel = status.loadedModelId == model.id;
    final isDownloading =
        isThisModel && status.state == SDModelState.downloading;
    final isExtracting = isThisModel && status.state == SDModelState.extracting;
    final isReady = isThisModel && status.state == SDModelState.ready;
    final isLoading = isThisModel && status.state == SDModelState.loading;
    final isLoaded = isThisModel && status.state == SDModelState.loaded;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceOverlay,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isLoaded
              ? AppColors.accentGreen.withAlpha(80)
              : AppColors.borderDefault,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.accentGreen.withAlpha(25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.auto_awesome_outlined,
                    color: AppColors.accentGreen, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(model.displayName, style: AppTypography.modelName),
                        if (isLoaded) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.accentGreen.withAlpha(30),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text('Active',
                                style: AppTypography.badge
                                    .copyWith(color: AppColors.accentGreen)),
                          ),
                        ],
                      ],
                    ),
                    Text(model.sizeLabel, style: AppTypography.modelDesc),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(model.description, style: AppTypography.modelDesc),
          const SizedBox(height: 8),

          // Specs row
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _Chip('${model.minRamGb} GB RAM min'),
              _Chip(model.minIphone),
              _Chip('${model.stepsRecommended} steps'),
            ],
          ),

          // Strengths
          if (model.strengths.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: model.strengths
                  .map((s) => _Chip(s, color: AppColors.accentGreen))
                  .toList(),
            ),
          ],

          if (model.notes != null) ...[
            const SizedBox(height: 8),
            Text(model.notes!, style: AppTypography.userMeta),
          ],

          const SizedBox(height: 14),

          // Download progress
          if (isDownloading || isExtracting) ...[
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: isExtracting ? null : status.downloadProgress,
                      backgroundColor: AppColors.surfaceActive,
                      valueColor:
                          const AlwaysStoppedAnimation(AppColors.accentGreen),
                      minHeight: 6,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  isExtracting
                      ? 'Extracting…'
                      : '${(status.downloadProgress * 100).toInt()}%',
                  style: AppTypography.badge,
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () =>
                  ref.read(sdModelProvider.notifier).cancelDownload(),
              style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFE57373),
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              child: const Text('Cancel'),
            ),
          ] else if (isLoading) ...[
            Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text('Loading model into memory…', style: AppTypography.badge),
              ],
            ),
          ] else ...[
            // Action buttons
            Row(
              children: [
                if (!isReady && !isLoaded)
                  FilledButton.icon(
                    onPressed: () =>
                        ref.read(sdModelProvider.notifier).download(model),
                    icon: const Icon(Icons.download_outlined, size: 16),
                    label: Text('Download ${model.sizeLabel}'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accentGreen,
                      foregroundColor: Colors.black,
                    ),
                  ),
                if (isReady && !isLoaded)
                  FilledButton.icon(
                    onPressed: () =>
                        ref.read(sdModelProvider.notifier).loadModel(model),
                    icon: const Icon(Icons.play_arrow_outlined, size: 16),
                    label: const Text('Load into memory'),
                  ),
                if (isLoaded)
                  OutlinedButton.icon(
                    onPressed: () =>
                        ref.read(sdModelProvider.notifier).deleteModel(model),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Remove'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFE57373),
                    ),
                  ),
              ],
            ),
          ],

          // Error state
          if (isThisModel && status.state == SDModelState.error)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Error: ${status.errorMessage ?? "Unknown error"}',
                style: AppTypography.badge
                    .copyWith(color: const Color(0xFFE57373)),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _PerformanceWarning extends StatelessWidget {
  const _PerformanceWarning();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFF9800).withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFF9800).withAlpha(60)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.timer_outlined, size: 18, color: Color(0xFFFF9800)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Performance notice',
                    style: AppTypography.modelName
                        .copyWith(color: const Color(0xFFFF9800))),
                const SizedBox(height: 4),
                Text(
                  'Local image and video generation is highly hardware-dependent. '
                  'Rendering may take 10 seconds to several minutes depending on '
                  'your device\'s chip and available memory. iPhone 15 Pro and newer '
                  'offer the best experience.',
                  style: AppTypography.modelDesc,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _HowItWorksCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
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
              Icon(Icons.info_outline, color: AppColors.textMuted, size: 16),
              const SizedBox(width: 8),
              Text('How it works', style: AppTypography.modelName),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Images are generated entirely on your device using Apple\'s Neural Engine '
            '(Core ML + Stable Diffusion). No internet connection is needed after the '
            'model is downloaded.\n\n'
            'Generation takes 8–35 seconds depending on your device. iPhone 15 Pro '
            'generates a 512×512 image in ~10 seconds at 20 steps.\n\n'
            'For animated outputs (/video), 4 frames are generated and combined into '
            'an APNG — true video generation isn\'t yet practical on mobile hardware.',
            style: AppTypography.modelDesc,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: AppTypography.sectionLabel,
      );
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, {this.color});
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.withAlpha(50)),
      ),
      child: Text(label, style: AppTypography.badge.copyWith(color: c)),
    );
  }
}
