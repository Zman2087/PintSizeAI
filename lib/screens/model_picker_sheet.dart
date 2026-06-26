import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/device_recommender/model_catalogue.dart';
import '../features/device_recommender/recommender_providers.dart';
import '../features/image_gen/image_gen_providers.dart';
import '../features/image_gen/sd_model_catalogue.dart';
import '../features/llm/llama_runner.dart';
import '../features/llm/llm_providers.dart';
import '../features/models/model_download_service.dart';
import '../features/models/model_providers.dart';
import '../theme/app_widgets.dart';
import '../theme/theme.dart';
import 'image_gen_screen.dart';

void showModelPicker(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surfaceBase,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _ModelPickerSheet(),
  );
}

class _ModelPickerSheet extends ConsumerWidget {
  const _ModelPickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pickerAsync = ref.watch(rankedModelsProvider);
    final downloads = ref.watch(downloadStatesProvider);
    final activeModel = ref.watch(activeModelProvider);
    final llamaStatus = ref.watch(llamaStatusProvider);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (_, scroll) => Column(
        children: [
          // Drag handle
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderDefault,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Title row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Text('Choose Model', style: AppTypography.sheetTitle),
                const Spacer(),
                if (activeModel != null)
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textMuted,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: () => ref.read(modelActionsProvider).unloadModel(),
                    child: const Text('Unload'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          const Divider(height: 1),
          // Model list
          Expanded(
            child: pickerAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text('Could not load models: $e',
                    style: AppTypography.modelDesc),
              ),
              data: (models) => RefreshIndicator(
                color: AppColors.accentGreen,
                backgroundColor: AppColors.surfaceOverlay,
                onRefresh: ref.read(catalogueRefreshProvider),
                child: ListView.builder(
                  controller: scroll,
                  padding: EdgeInsets.zero,
                  itemBuilder: (context, i) {
                    final item = _buildItems(models, downloads);
                    if (i >= item.length) return const SizedBox.shrink();
                    final entry = item[i];

                    if (entry is String) {
                      return _SectionHeader(label: entry, hasItems: true);
                    }

                    final picker = entry as PickerModel;
                    final dl = downloads[picker.model.id] ?? DownloadState.notDownloaded;
                    final isActive = activeModel?.id == picker.model.id;
                    final isLoading = isActive && llamaStatus == LlamaStatus.loading;
                    final hasUpdate = _hasUpdate(picker.model, models, downloads);

                    return _ModelTile(
                      picker: picker,
                      downloadState: dl,
                      isActive: isActive,
                      isLoading: isLoading,
                      hasUpdate: hasUpdate,
                      onTap: () => _handleTap(context, ref, picker.model, dl),
                    );
                  },
                  itemCount: _buildItems(models, downloads).length,
                ),
              ),
            ),
          ),
          // ── Image / Video generation section ──────────────────────────
          _ImageGenSection(context: context),

          // On-device privacy note
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_outline,
                      size: 12, color: AppColors.textDim),
                  const SizedBox(width: 6),
                  Text(
                    'All models run 100% on-device · no internet required',
                    style: AppTypography.userMeta,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// True when a downloaded model has a newer version available in the catalogue.
  /// i.e. another model's [supersedes] field points at this model's id.
  bool _hasUpdate(
    ModelVariant model,
    List<PickerModel> all,
    Map<String, DownloadState> downloads,
  ) {
    final isDownloaded = downloads[model.id]?.status == DownloadStatus.downloaded;
    if (!isDownloaded) return false;
    return all.any((p) =>
        p.model.supersedes == model.id &&
        downloads[p.model.id]?.status != DownloadStatus.downloaded);
  }

  /// Builds a flat list of section-header strings and PickerModel items,
  /// sorted so downloaded models appear first under "ON DEVICE".
  List<Object> _buildItems(
    List<PickerModel> models,
    Map<String, DownloadState> downloads,
  ) {
    final onDevice = models
        .where((m) => downloads[m.model.id]?.status == DownloadStatus.downloaded)
        .toList();
    final available = models
        .where((m) => downloads[m.model.id]?.status != DownloadStatus.downloaded)
        .toList();

    return [
      if (onDevice.isNotEmpty) ...['ON DEVICE', ...onDevice],
      if (available.isNotEmpty) ...['AVAILABLE TO DOWNLOAD', ...available],
    ];
  }

  void _handleTap(
    BuildContext context,
    WidgetRef ref,
    ModelVariant model,
    DownloadState dl,
  ) {
    switch (dl.status) {
      case DownloadStatus.notDownloaded:
      case DownloadStatus.error:
        _confirmDownload(context, ref, model);
      case DownloadStatus.downloading:
        ref.read(modelActionsProvider).cancelDownload(model.id);
      case DownloadStatus.downloaded:
        ref.read(modelActionsProvider).loadModel(model).then((_) {
          if (context.mounted) Navigator.of(context).pop();
        }).catchError((e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to load: $e')),
            );
          }
        });
    }
  }

  /// After a model with [supersedes] finishes downloading, offer to free space
  /// by deleting the old model from disk.
  Future<void> _offerDeleteSuperseded(
    BuildContext context,
    WidgetRef ref,
    ModelVariant newModel,
  ) async {
    final oldId = newModel.supersedes;
    if (oldId == null || !context.mounted) return;

    final storage = ref.read(modelStorageProvider);
    if (!await storage.isDownloaded(oldId)) return;

    if (!context.mounted) return;
    final sizeGb = (await storage.downloadedSizeBytes(oldId) / 1e9)
        .toStringAsFixed(1);

    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceOverlay,
        title: Text('Free up ${sizeGb}GB?', style: AppTypography.navTitle),
        content: Text(
          '${newModel.displayName} replaces the old version. '
          'Delete the old model to recover ${sizeGb}GB of storage?',
          style: AppTypography.messageBody,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Keep both'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              storage.delete(oldId);
              ref.read(downloadStatesProvider.notifier)
                  .removeState(oldId);
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accentGreen,
              foregroundColor: Colors.black,
            ),
            child: const Text('Delete old version'),
          ),
        ],
      ),
    );
  }

  void _confirmDownload(
    BuildContext context,
    WidgetRef ref,
    ModelVariant model,
  ) {
    final sizeGb = (model.fileSizeBytes / 1e9).toStringAsFixed(1);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceOverlay,
        title: Text('Download ${model.displayName}?',
            style: AppTypography.navTitle),
        content: Text(
          'This will download ${sizeGb}GB over your current connection.',
          style: AppTypography.messageBody,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              final capturedContext = context;
              ref.read(modelActionsProvider).download(model).then((_) {
                _offerDeleteSuperseded(capturedContext, ref, model);
              });
            },
            child: const Text('Download'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tiles & helpers
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.hasItems});
  final String label;
  final bool hasItems;

  @override
  Widget build(BuildContext context) {
    if (!hasItems) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Text(label.toUpperCase(), style: AppTypography.sectionLabel),
    );
  }
}

class _ModelTile extends StatelessWidget {
  const _ModelTile({
    required this.picker,
    required this.downloadState,
    required this.isActive,
    required this.isLoading,
    required this.hasUpdate,
    required this.onTap,
  });

  final PickerModel picker;
  final DownloadState downloadState;
  final bool isActive;
  final bool isLoading;
  final bool hasUpdate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final model = picker.model;
    final dl = downloadState;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: AppColors.surfaceOverlay,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            children: [
              ModelIcon(
                color: _iconColor(model.family),
                icon: _iconData(model.family),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(model.displayName, style: AppTypography.modelName),
                        if (picker.isRecommended) ...[
                          const SizedBox(width: 6),
                          _Badge(label: 'Best fit'),
                        ],
                        if (model.isReasoningModel) ...[
                          const SizedBox(width: 6),
                          _Badge(label: 'Reasoning'),
                        ],
                        if (hasUpdate) ...[
                          const SizedBox(width: 6),
                          _Badge(label: 'Update available',
                              color: const Color(0xFFF59E0B)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle(model, picker, dl),
                      style: AppTypography.modelDesc,
                    ),
                    if (dl.status == DownloadStatus.downloading &&
                        dl.totalBytes > 0) ...[
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: dl.progress,
                          minHeight: 2,
                          backgroundColor: AppColors.surfaceActive,
                          valueColor: const AlwaysStoppedAnimation(
                            AppColors.accentGreen,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _TrailingWidget(
                dl: dl,
                isActive: isActive,
                isLoading: isLoading,
                fitsDevice: picker.fitsDevice,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _subtitle(ModelVariant m, PickerModel picker, DownloadState dl) {
    if (dl.status == DownloadStatus.downloading) {
      if (dl.totalBytes > 0) {
        final recv = (dl.receivedBytes / 1e6).toStringAsFixed(0);
        final total = (dl.totalBytes / 1e6).toStringAsFixed(0);
        return 'Downloading… ${recv}MB / ${total}MB';
      }
      return 'Downloading…';
    }
    if (!picker.fitsDevice) {
      return picker.speedLabel; // shows elimination reason
    }
    final size = m.fileSizeGb.toStringAsFixed(1);
    final speed = picker.speedLabel;
    final ctx = m.contextLength >= 65536
        ? '${m.contextLength ~/ 1024}k ctx'
        : '${m.contextLength ~/ 1024}k ctx';
    return '${m.parametersBillions}B · ${m.quant.label} · ${size}GB · $ctx · $speed';
  }

  Color _iconColor(ModelFamily f) => switch (f) {
        ModelFamily.llama => AppColors.modelWhite,
        ModelFamily.phi => AppColors.modelBlue,
        ModelFamily.gemma => AppColors.modelGreen,
        ModelFamily.mistral => AppColors.modelPurple,
        ModelFamily.qwen => AppColors.modelPurple,
        ModelFamily.deepseek => AppColors.modelBlue,
        ModelFamily.smollm => AppColors.modelSurface,
      };

  IconData _iconData(ModelFamily f) => switch (f) {
        ModelFamily.llama => Icons.memory,
        ModelFamily.phi => Icons.hexagon_outlined,
        ModelFamily.gemma => Icons.diamond_outlined,
        ModelFamily.mistral => Icons.bolt,
        ModelFamily.qwen => Icons.waves,
        ModelFamily.deepseek => Icons.psychology_outlined,
        ModelFamily.smollm => Icons.bubble_chart_outlined,
      };
}

class _TrailingWidget extends StatelessWidget {
  const _TrailingWidget({
    required this.dl,
    required this.isActive,
    required this.isLoading,
    required this.fitsDevice,
  });

  final DownloadState dl;
  final bool isActive;
  final bool isLoading;
  final bool fitsDevice;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (isActive) {
      return const Icon(Icons.check, color: AppColors.accentGreen, size: 18);
    }
    if (dl.status == DownloadStatus.downloading) {
      return SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          value: dl.progress > 0 ? dl.progress : null,
          strokeWidth: 2.5,
          backgroundColor: AppColors.surfaceOverlay,
          valueColor: const AlwaysStoppedAnimation(AppColors.accentGreen),
        ),
      );
    }
    if (dl.status == DownloadStatus.downloaded) {
      return const SizedBox.shrink(); // downloaded but not active
    }
    if (!fitsDevice) {
      return const Icon(Icons.block, size: 16, color: AppColors.textDim);
    }
    return _GetBadge();
  }
}

class _GetBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.borderDefault),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text('Get', style: AppTypography.badge),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, this.color});
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.accentGreen;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: AppTypography.badge.copyWith(color: c),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Image / Video Generation section in the model picker
// ─────────────────────────────────────────────────────────────────────────────

class _ImageGenSection extends ConsumerWidget {
  const _ImageGenSection({required this.context});
  final BuildContext context;

  @override
  Widget build(BuildContext ctx, WidgetRef ref) {
    final sdStatus = ref.watch(sdModelProvider);
    final isLoaded = sdStatus.state == SDModelState.loaded;
    final isReady  = sdStatus.state == SDModelState.ready;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Text('IMAGE & VIDEO GENERATION',
              style: AppTypography.sectionLabel),
        ),

        // Summary row — tap opens full model screen
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ImageGenScreen()),
              );
            },
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              child: Row(
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
                        Text('Stable Diffusion',
                            style: AppTypography.modelName),
                        Text(
                          isLoaded
                              ? 'Active — ${sdStatus.loadedModelId ?? ""}'
                              : isReady
                                  ? 'Downloaded — tap to open and load'
                                  : 'Core ML · on-device · tap to download',
                          style: AppTypography.modelDesc,
                        ),
                        if (sdStatus.state == SDModelState.downloading) ...[
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: sdStatus.downloadProgress > 0
                                  ? sdStatus.downloadProgress
                                  : null,
                              minHeight: 2,
                              backgroundColor: AppColors.surfaceActive,
                              valueColor: const AlwaysStoppedAnimation(
                                  AppColors.accentGreen),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (isLoaded)
                    const Icon(Icons.check,
                        color: AppColors.accentGreen, size: 18)
                  else if (sdStatus.state == SDModelState.downloading)
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        value: sdStatus.downloadProgress > 0
                            ? sdStatus.downloadProgress
                            : null,
                        strokeWidth: 2.5,
                        backgroundColor: AppColors.surfaceOverlay,
                        valueColor: const AlwaysStoppedAnimation(
                            AppColors.accentGreen),
                      ),
                    )
                  else
                    _GetBadge(),
                ],
              ),
            ),
          ),
        ),

        // Quick-download tiles for each model if none ready
        if (!isLoaded && !isReady && sdStatus.state != SDModelState.downloading)
          ...kSDModelCatalogue.map((m) => _SDModelQuickTile(model: m)),
      ],
    );
  }
}

class _SDModelQuickTile extends ConsumerWidget {
  const _SDModelQuickTile({required this.model});
  final SDModel model;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _confirmDownload(context, ref),
        child: Padding(
          padding:
              const EdgeInsets.only(left: 64, right: 16, top: 8, bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(model.displayName, style: AppTypography.modelName),
                    Text(
                      '${model.sizeLabel} · ${model.minIphone}+ · ${model.stepsRecommended} steps',
                      style: AppTypography.modelDesc,
                    ),
                  ],
                ),
              ),
              _GetBadge(),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDownload(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceOverlay,
        title: Text('Download ${model.displayName}?',
            style: AppTypography.navTitle),
        content: Text(
          'This will download ${model.sizeLabel} to your device. '
          'Images and videos will be generated entirely on-device — '
          'no internet needed after download.',
          style: AppTypography.messageBody,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(sdModelProvider.notifier).download(model);
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accentGreen,
              foregroundColor: Colors.black,
            ),
            child: const Text('Download'),
          ),
        ],
      ),
    );
  }
}
