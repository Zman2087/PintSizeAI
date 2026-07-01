import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/device_recommender/model_catalogue.dart';
import '../features/device_recommender/recommender_providers.dart';
import '../features/models/model_download_service.dart';
import '../features/models/model_fit.dart';
import '../features/models/model_providers.dart';
import '../theme/app_widgets.dart';
import '../theme/theme.dart';

void showModelDetail(BuildContext context, ModelVariant model) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surfaceBase,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ModelDetailSheet(model: model),
  );
}

class _ModelDetailSheet extends ConsumerWidget {
  const _ModelDetailSheet({required this.model});
  final ModelVariant model;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.watch(downloadStatesProvider);
    final activeModel = ref.watch(activeModelProvider);
    final dl = downloads[model.id] ?? DownloadState.notDownloaded;
    final isActive = activeModel?.id == model.id;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scroll) => SingleChildScrollView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: AppColors.borderDefault,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Row(
              children: [
                _modelIcon(model),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(model.displayName,
                                style: AppTypography.sheetTitle),
                          ),
                          if (isActive)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.accentGreen.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text('Active',
                                  style: AppTypography.badge.copyWith(
                                      color: AppColors.accentGreen)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${model.creator}${model.releaseLabel.isNotEmpty ? ' · ${model.releaseLabel}' : ''}',
                        style: AppTypography.modelDesc,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Device fit + capability chips
            Builder(builder: (_) {
              final profile = ref.watch(deviceProfileProvider).valueOrNull;
              final fit = profile == null ? null : deviceFit(model, profile);
              final caps = capabilityTags(model);
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (fit != null)
                    Builder(builder: (_) {
                      final b = fitBadge(fit);
                      return Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(b.icon, size: 15, color: b.color),
                        const SizedBox(width: 4),
                        Text(b.label,
                            style: TextStyle(
                                color: b.color,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                      ]);
                    }),
                  ...caps.map((c) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.borderDefault),
                        ),
                        child: Text(c,
                            style: TextStyle(
                                color: AppColors.textMuted, fontSize: 12)),
                      )),
                ],
              );
            }),

            const SizedBox(height: 20),
            const Divider(height: 1),
            const SizedBox(height: 20),

            // Specs grid
            _SectionTitle('Specifications'),
            const SizedBox(height: 12),
            _SpecsGrid(model: model),

            if (model.description != null) ...[
              const SizedBox(height: 24),
              _SectionTitle('About'),
              const SizedBox(height: 8),
              Text(model.description!, style: AppTypography.messageBody),
            ],

            // Strengths
            if (model.strengths.isNotEmpty) ...[
              const SizedBox(height: 24),
              _SectionTitle('Good at'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: model.strengths
                    .map((s) => _Chip(label: s, positive: true))
                    .toList(),
              ),
            ],

            // Limitations
            if (model.limitations.isNotEmpty) ...[
              const SizedBox(height: 20),
              _SectionTitle('Limitations'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: model.limitations
                    .map((l) => _Chip(label: l, positive: false))
                    .toList(),
              ),
            ],

            // Device recommendation
            if (model.recommendedDevice != null) ...[
              const SizedBox(height: 24),
              _SectionTitle('Recommended device'),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceOverlay,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.borderDefault),
                ),
                child: Row(
                  children: [
                    Icon(Icons.phone_iphone,
                        size: 18, color: AppColors.textMuted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(model.recommendedDevice!,
                          style: AppTypography.messageBody),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 32),

            // Action button
            SizedBox(
              width: double.infinity,
              child: _ActionButton(
                model: model,
                dl: dl,
                isActive: isActive,
                onTap: () => _handleAction(context, ref, dl, isActive),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modelIcon(ModelVariant m) {
    final color = switch (m.family) {
      ModelFamily.llama => AppColors.modelWhite,
      ModelFamily.phi => AppColors.modelBlue,
      ModelFamily.gemma => AppColors.modelGreen,
      ModelFamily.mistral => AppColors.modelPurple,
      ModelFamily.qwen => AppColors.modelPurple,
      ModelFamily.deepseek => AppColors.modelBlue,
      ModelFamily.smollm => AppColors.modelSurface,
    };
    final icon = switch (m.family) {
      ModelFamily.llama => Icons.memory,
      ModelFamily.phi => Icons.hexagon_outlined,
      ModelFamily.gemma => Icons.diamond_outlined,
      ModelFamily.mistral => Icons.bolt,
      ModelFamily.qwen => Icons.waves,
      ModelFamily.deepseek => Icons.psychology_outlined,
      ModelFamily.smollm => Icons.bubble_chart_outlined,
    };
    return ModelIcon(color: color, icon: icon, size: 44);
  }

  Future<void> _handleAction(
    BuildContext context,
    WidgetRef ref,
    DownloadState dl,
    bool isActive,
  ) async {
    if (isActive) {
      ref.read(modelActionsProvider).unloadModel();
      Navigator.of(context).pop();
      return;
    }
    if (dl.status == DownloadStatus.downloading) {
      ref.read(modelActionsProvider).cancelDownload(model.id);
      return;
    }
    if (dl.status == DownloadStatus.downloaded) {
      ref.read(modelActionsProvider).loadModel(model).then((_) {
        if (context.mounted) Navigator.of(context).pop();
      }).catchError((e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not load model: $e')),
          );
        }
      });
      return;
    }

    // Not downloaded → warn if it's too big for this device, then download.
    final profile = ref.read(deviceProfileProvider).valueOrNull;
    if (profile != null && deviceFit(model, profile) == ModelFit.tooBig) {
      final go = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppColors.surfaceOverlay,
          title: Text('Too big for your device',
              style: TextStyle(color: AppColors.textPrimary)),
          content: Text(
            'This model likely needs more memory than your iPhone can give an '
            'app, so it may fail to load or crash. Download anyway?',
            style: TextStyle(color: AppColors.textMuted),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Download anyway',
                    style: TextStyle(color: Color(0xFFEF4444)))),
          ],
        ),
      );
      if (go != true) return;
    }
    ref.read(modelActionsProvider).download(model);
    // Keep the sheet open so the user sees the live download progress.
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: AppTypography.sectionLabel,
      );
}

class _SpecsGrid extends StatelessWidget {
  const _SpecsGrid({required this.model});
  final ModelVariant model;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.8,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: [
        _SpecCell(
            label: 'Parameters', value: '${model.parametersBillions}B'),
        _SpecCell(label: 'Quantisation', value: model.quant.label),
        _SpecCell(
            label: 'Context',
            value: '${model.contextLength ~/ 1024}k tokens'),
        _SpecCell(
            label: 'File size',
            value: model.fileSizeGb.toStringAsFixed(1) + ' GB'),
        _SpecCell(
            label: 'RAM required',
            value: model.ramRequiredGb.toStringAsFixed(1) + ' GB'),
        _SpecCell(
            label: 'Min RAM rec.',
            value: '${model.minRamGbRecommended} GB'),
      ],
    );
  }
}

class _SpecCell extends StatelessWidget {
  const _SpecCell({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceOverlay,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label,
              style: AppTypography.userMeta.copyWith(fontSize: 10)),
          Text(value, style: AppTypography.modelName),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.positive});
  final String label;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final color =
        positive ? AppColors.accentGreen : const Color(0xFFE57373);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            positive ? Icons.check_circle_outline : Icons.remove_circle_outline,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(label,
              style: AppTypography.badge.copyWith(color: color)),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.model,
    required this.dl,
    required this.isActive,
    required this.onTap,
  });

  final ModelVariant model;
  final DownloadState dl;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (isActive) {
      return OutlinedButton(
        onPressed: onTap,
        child: const Text('Unload model'),
      );
    }
    if (dl.status == DownloadStatus.downloaded) {
      return FilledButton(
        onPressed: onTap,
        child: const Text('Load model'),
      );
    }
    if (dl.status == DownloadStatus.downloading) {
      return OutlinedButton(
        onPressed: onTap, // tap to cancel
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 8),
            Text(
              dl.totalBytes > 0
                  ? 'Downloading ${(dl.progress * 100).toInt()}%  ·  Tap to cancel'
                  : 'Downloading…  ·  Tap to cancel',
            ),
          ],
        ),
      );
    }
    return FilledButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.download_outlined, size: 16),
      label: Text('Download (${model.fileSizeGb.toStringAsFixed(1)} GB)'),
    );
  }
}
