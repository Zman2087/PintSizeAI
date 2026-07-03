import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/device_recommender/device_profile.dart';
import '../features/device_recommender/model_catalogue.dart';
import '../features/device_recommender/recommender_providers.dart';
import '../features/models/custom_models_service.dart';
import '../features/models/huggingface_service.dart';
import '../features/models/model_download_service.dart';
import '../features/models/model_fit.dart';
import '../features/models/model_providers.dart';
import '../features/image_gen/image_gen_providers.dart';
import '../features/image_gen/sd_model_catalogue.dart';
import '../theme/theme.dart';
import 'model_detail_sheet.dart';

/// One screen for everything model-related: what's installed, what's
/// recommended for this device, and a live Hugging Face browser.
class ModelsScreen extends ConsumerWidget {
  const ModelsScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ModelsScreen()),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: AppColors.surfaceBase,
        appBar: AppBar(
          backgroundColor: AppColors.surfaceBase,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: const Text('Models'),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: AppColors.textPrimary,
            unselectedLabelColor: AppColors.textMuted,
            indicatorColor: AppColors.textPrimary,
            indicatorWeight: 1.5,
            labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            tabs: [
              Tab(text: 'On device'),
              Tab(text: 'Recommended'),
              Tab(text: 'Discover'),
              Tab(text: 'Image models'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _OnDeviceTab(),
            _RecommendedTab(),
            _DiscoverTab(),
            _ImageModelsTab(),
          ],
        ),
      ),
    );
  }
}

// ── Shared model row ────────────────────────────────────────────────────────

class _ModelRow extends ConsumerWidget {
  const _ModelRow({required this.model, this.profile});
  final ModelVariant model;
  final DeviceProfile? profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dl = ref.watch(downloadStatesProvider)[model.id] ??
        DownloadState.notDownloaded;
    final isActive = ref.watch(activeModelProvider)?.id == model.id;
    final fit = profile == null ? null : deviceFit(model, profile!);
    final caps = capabilityTags(model);

    return InkWell(
      onTap: () => showModelDetail(context, model),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(model.displayName,
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                ),
                if (isActive)
                  _Pill(text: 'Active', color: AppColors.textPrimary)
                else
                  _StatusAction(model: model, dl: dl),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${_paramLabel(model)}${model.quant.label} · '
              '${model.fileSizeGb.toStringAsFixed(model.fileSizeGb < 1 ? 2 : 1)} GB',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            if (dl.status == DownloadStatus.downloading) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: dl.totalBytes > 0 ? dl.progress : null,
                  minHeight: 4,
                  backgroundColor: AppColors.surfaceActive,
                  valueColor: const AlwaysStoppedAnimation(AppColors.accentGreen),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                dl.totalBytes > 0
                    ? 'Downloading… ${(dl.progress * 100).toInt()}%  ·  '
                        '${(dl.receivedBytes / 1e6).toStringAsFixed(0)} / ${(dl.totalBytes / 1e6).toStringAsFixed(0)} MB'
                    : 'Downloading…',
                style: TextStyle(color: AppColors.textDim, fontSize: 11),
              ),
            ] else ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (fit != null) _FitChip(fit: fit),
                  ...caps.map((c) => _CapChip(label: c)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _paramLabel(ModelVariant m) =>
      m.parametersBillions > 0 ? '${m.parametersBillions}B · ' : '';
}

class _StatusAction extends ConsumerWidget {
  const _StatusAction({required this.model, required this.dl});
  final ModelVariant model;
  final DownloadState dl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (dl.status) {
      case DownloadStatus.downloading:
        final pct = dl.totalBytes > 0 ? ' ${(dl.progress * 100).toInt()}%' : '';
        return Text('Downloading$pct',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12));
      case DownloadStatus.downloaded:
        return _MonoButton(
          label: 'Load',
          onTap: () {
            ref.read(modelActionsProvider).loadModel(model).then((_) {
              if (context.mounted) Navigator.of(context).maybePop();
            }).catchError((e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Could not load: $e')),
                );
              }
            });
          },
        );
      default:
        return Icon(Icons.chevron_right,
            size: 18, color: AppColors.textDim);
    }
  }
}

// ── On device ───────────────────────────────────────────────────────────────

class _OnDeviceTab extends ConsumerWidget {
  const _OnDeviceTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.watch(downloadStatesProvider);
    final profile = ref.watch(deviceProfileProvider).valueOrNull;
    final ranked = ref.watch(rankedModelsProvider).valueOrNull ?? [];
    final active = ref.watch(activeModelProvider);

    // On device = downloaded, currently downloading, or the active model — so
    // in-progress downloads are trackable here with a live progress bar.
    final installed = ranked
        .map((p) => p.model)
        .where((m) {
          final s = downloads[m.id]?.status;
          return s == DownloadStatus.downloaded ||
              s == DownloadStatus.downloading ||
              m.id == active?.id;
        })
        .toList();

    if (installed.isEmpty) {
      return const _Empty(
        icon: Icons.download_done_outlined,
        text: 'No models on your device yet.\nInstall one from Recommended or Discover.',
      );
    }
    return ListView(
      children: [
        for (final m in installed)
          Dismissible(
            key: ValueKey('installed_${m.id}'),
            direction: m.id == active?.id
                ? DismissDirection.none
                : DismissDirection.endToStart,
            background: Container(
              color: const Color(0xFF3A1414),
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              child: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
            ),
            confirmDismiss: (_) => _confirmDelete(context, m.displayName),
            onDismissed: (_) {
              ref.read(modelStorageProvider).delete(m.id);
              ref.read(downloadStatesProvider.notifier).removeState(m.id);
              ref.read(customModelsProvider.notifier).remove(m.id);
            },
            child: _ModelRow(model: m, profile: profile),
          ),
        Padding(
          padding: EdgeInsets.all(16),
          child: Text('Swipe a model left to delete it and free up space.',
              style: TextStyle(color: AppColors.textDim, fontSize: 12)),
        ),
      ],
    );
  }

  Future<bool> _confirmDelete(BuildContext context, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceOverlay,
        title: Text('Delete model?',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text('Remove "$name" from this device to free up storage?',
            style: TextStyle(color: AppColors.textMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Color(0xFFEF4444))),
          ),
        ],
      ),
    );
    return ok ?? false;
  }
}

// ── Recommended ─────────────────────────────────────────────────────────────

class _RecommendedTab extends ConsumerWidget {
  const _RecommendedTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rankedAsync = ref.watch(rankedModelsProvider);
    final profile = ref.watch(deviceProfileProvider).valueOrNull;

    return rankedAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _Empty(icon: Icons.error_outline, text: 'Could not load: $e'),
      data: (ranked) {
        // Fitting, built-in models first; hide user-imported ones here.
        final list = ranked
            .where((p) => p.fitsDevice && !p.model.id.startsWith('hf_'))
            .map((p) => p.model)
            .toList();
        if (list.isEmpty) {
          return const _Empty(
              icon: Icons.tips_and_updates_outlined,
              text: 'No compatible models found.');
        }
        return ListView(
          children: [
            for (final m in list) _ModelRow(model: m, profile: profile),
          ],
        );
      },
    );
  }
}

// ── Discover (Hugging Face) ─────────────────────────────────────────────────

class _DiscoverTab extends ConsumerStatefulWidget {
  const _DiscoverTab();
  @override
  ConsumerState<_DiscoverTab> createState() => _DiscoverTabState();
}

class _DiscoverTabState extends ConsumerState<_DiscoverTab> {
  final _searchCtrl = TextEditingController();
  Future<List<HFRepo>>? _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(huggingFaceServiceProvider).search();
  }

  void _run() => setState(() => _future =
      ref.read(huggingFaceServiceProvider).search(query: _searchCtrl.text));

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: TextField(
            controller: _searchCtrl,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _run(),
            style: TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Search Hugging Face…',
              hintStyle: TextStyle(color: AppColors.textDim),
              prefixIcon: Icon(Icons.search, color: AppColors.textDim, size: 20),
              filled: true,
              fillColor: AppColors.surfaceOverlay,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<HFRepo>>(
            future: _future,
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final repos = snap.data ?? [];
              if (repos.isEmpty) {
                return const _Empty(
                    icon: Icons.cloud_off_outlined,
                    text: 'No results. Check your connection or try another search.');
              }
              return ListView.builder(
                itemCount: repos.length,
                itemBuilder: (_, i) => _HFRepoRow(repo: repos[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _HFRepoRow extends ConsumerWidget {
  const _HFRepoRow({required this.repo});
  final HFRepo repo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = capabilityTags(
      HuggingFaceService.toModelVariant(repo,
          const HFFile(path: '', sizeBytes: 0)),
      hfTags: repo.tags,
    );
    final updated =
        repo.lastModified.length >= 10 ? repo.lastModified.substring(0, 10) : '';
    return InkWell(
      onTap: () => _showQuants(context, ref),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(repo.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                ),
                Icon(Icons.chevron_right, size: 18, color: AppColors.textDim),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${repo.owner}  ·  ${_fmt(repo.downloads)} downloads'
              '${updated.isNotEmpty ? '  ·  updated $updated' : ''}',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: caps.map((c) => _CapChip(label: c)).toList(),
            ),
          ],
        ),
      ),
    );
  }

  void _showQuants(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceSidebar,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _QuantSheet(repo: repo),
    );
  }

  static String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }
}

class _QuantSheet extends ConsumerStatefulWidget {
  const _QuantSheet({required this.repo});
  final HFRepo repo;
  @override
  ConsumerState<_QuantSheet> createState() => _QuantSheetState();
}

class _QuantSheetState extends ConsumerState<_QuantSheet> {
  late Future<List<HFFile>> _files;

  @override
  void initState() {
    super.initState();
    _files = ref.read(huggingFaceServiceProvider).ggufFiles(widget.repo.id);
  }

  Future<void> _pick(HFFile file) async {
    final model = HuggingFaceService.toModelVariant(widget.repo, file);
    final profile = ref.read(deviceProfileProvider).valueOrNull;
    final fit = profile == null ? ModelFit.good : deviceFit(model, profile);

    if (fit == ModelFit.tooBig) {
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

    await ref.read(customModelsProvider.notifier).add(model);
    // For a model that fits, download + load + activate in one step so the user
    // never taps "Load" separately. For an oversized model, only download —
    // auto-loading it could exhaust memory and crash.
    final actions = ref.read(modelActionsProvider);
    final willAutoLoad = fit != ModelFit.tooBig;
    if (willAutoLoad) {
      actions.loadModel(model);
    } else {
      actions.download(model);
    }
    if (mounted) {
      final tabs = DefaultTabController.maybeOf(context);
      Navigator.pop(context); // close quant sheet
      tabs?.animateTo(0); // jump to "On device" so progress is visible
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(willAutoLoad
                ? 'Downloading ${model.displayName} — it will load automatically when ready.'
                : 'Downloading ${model.displayName} — tap it under "On device" to load.')),
      );
    }
  }

  static bool _isRecommendedQuant(String q) {
    final u = q.toUpperCase();
    return u == 'Q4_K_M' || u == 'Q4_K_S';
  }

  static String _quantPlainName(String q) {
    final u = q.toUpperCase();
    if (u.startsWith('Q2') || u.startsWith('IQ2')) return 'Smallest (lowest quality)';
    if (u.startsWith('Q3') || u.startsWith('IQ3')) return 'Small & fast';
    if (u.startsWith('Q4') || u.startsWith('IQ4')) return 'Balanced';
    if (u.startsWith('Q5')) return 'Higher quality';
    if (u.startsWith('Q6')) return 'High quality (large)';
    if (u.startsWith('Q8')) return 'Best quality (large)';
    if (u.startsWith('F16') || u.startsWith('BF16') || u.startsWith('F32')) {
      return 'Full precision (very large)';
    }
    return q;
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(deviceProfileProvider).valueOrNull;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (_, scroll) => FutureBuilder<List<HFFile>>(
        future: _files,
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final files = snap.data ?? [];
          return ListView(
            controller: scroll,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 2),
                child: Text(widget.repo.displayName,
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Text(
                    'A "version" is how compressed the model is. Smaller = faster '
                    'and less memory but slightly lower quality. Balanced is best '
                    'for most phones.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ),
              if (files.isEmpty)
                Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No compatible single-file GGUF versions found.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textMuted)),
                ),
              for (final f in files)
                Builder(builder: (_) {
                  final m = HuggingFaceService.toModelVariant(widget.repo, f);
                  final fit = profile == null ? null : deviceFit(m, profile);
                  final recommended = _isRecommendedQuant(f.quantLabel);
                  return ListTile(
                    title: Row(
                      children: [
                        Flexible(
                          child: Text(_quantPlainName(f.quantLabel),
                              style: TextStyle(color: AppColors.textPrimary)),
                        ),
                        if (recommended) ...[
                          const SizedBox(width: 8),
                          _Pill(text: 'Recommended', color: AppColors.accentGreen),
                        ],
                      ],
                    ),
                    subtitle: Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          Text('${f.quantLabel} · ${(f.sizeBytes / 1e9).toStringAsFixed(2)} GB',
                              style: TextStyle(
                                  color: AppColors.textMuted, fontSize: 12)),
                          if (fit != null) ...[
                            SizedBox(width: 8),
                            _FitChip(fit: fit),
                          ],
                        ],
                      ),
                    ),
                    trailing: Icon(Icons.download_outlined,
                        color: AppColors.textPrimary, size: 20),
                    onTap: () => _pick(f),
                  );
                }),
              SizedBox(height: 16),
            ],
          );
        },
      ),
    );
  }
}

// ── Image models (Stable Diffusion) ─────────────────────────────────────────

class _ImageModelsTab extends ConsumerWidget {
  const _ImageModelsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(sdModelProvider);
    return ListView(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(18, 14, 18, 4),
          child: Text('Image generation models',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(18, 0, 18, 8),
          child: Text(
              'On-device Stable Diffusion — create images from text, fully offline.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ),
        for (final m in kSDModelCatalogue) _SDModelRow(model: m, status: status),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
          child: Text(
              'These are the Apple-compiled Core ML models that run on iPhone. '
              'Unlike text models, on-device image generation needs specially '
              'compiled models, so the list is intentionally short — other '
              'Stable Diffusion models from the web won\'t run on iOS.',
              style: TextStyle(color: AppColors.textDim, fontSize: 11, height: 1.4)),
        ),
      ],
    );
  }
}

class _SDModelRow extends ConsumerWidget {
  _SDModelRow({required this.model, required this.status});
  final SDModel model;
  final SDModelStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThis = status.loadedModelId == model.id;
    final notifier = ref.read(sdModelProvider.notifier);

    Widget action;
    Widget? progress;
    if (isThis) {
      switch (status.state) {
        case SDModelState.downloading:
          progress = _sdProgress('Downloading', status.downloadProgress);
          action = const SizedBox.shrink();
        case SDModelState.extracting:
          progress = _sdProgress('Extracting', null);
          action = const SizedBox.shrink();
        case SDModelState.ready:
          action = _MonoButton(label: 'Load', onTap: () => notifier.loadModel(model));
        case SDModelState.loading:
          action = const SizedBox(
              width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2));
        case SDModelState.loaded:
          action = _Pill(text: 'Active', color: AppColors.textPrimary);
        case SDModelState.error:
          action = _MonoButton(label: 'Retry', onTap: () => notifier.download(model));
        default:
          action = _MonoButton(label: 'Download', onTap: () => notifier.download(model));
      }
    } else {
      action = _MonoButton(label: 'Download', onTap: () => notifier.download(model));
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(model.displayName,
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
              ),
              action,
            ],
          ),
          const SizedBox(height: 4),
          Text('${model.sizeLabel} · needs ${model.minRamGb}GB RAM · ${model.minIphone}+',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          const SizedBox(height: 8),
          Text(model.description,
              style: TextStyle(color: AppColors.textDim, fontSize: 12, height: 1.35)),
          if (progress != null) ...[const SizedBox(height: 10), progress],
        ],
      ),
    );
  }

  Widget _sdProgress(String label, double? value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: value != null && value > 0 ? value : null,
              minHeight: 4,
              backgroundColor: AppColors.surfaceActive,
              valueColor: const AlwaysStoppedAnimation(AppColors.accentGreen),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value != null && value > 0
                ? '$label… ${(value * 100).toInt()}%'
                : '$label…',
            style: TextStyle(color: AppColors.textDim, fontSize: 11),
          ),
        ],
      );
}

// ── Small shared widgets ────────────────────────────────────────────────────

class _FitChip extends StatelessWidget {
  const _FitChip({required this.fit});
  final ModelFit fit;
  @override
  Widget build(BuildContext context) {
    final b = fitBadge(fit);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(b.icon, size: 13, color: b.color),
        const SizedBox(width: 4),
        Text(b.label, style: TextStyle(color: b.color, fontSize: 12)),
      ],
    );
  }
}

class _CapChip extends StatelessWidget {
  const _CapChip({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.borderDefault),
        ),
        child: Text(label,
            style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
      );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      );
}

class _MonoButton extends StatelessWidget {
  const _MonoButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.textPrimary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(label,
              style: TextStyle(
                  color: AppColors.surfaceBase,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ),
      );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: AppColors.textDim),
              const SizedBox(height: 12),
              Text(text,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
            ],
          ),
        ),
      );
}
