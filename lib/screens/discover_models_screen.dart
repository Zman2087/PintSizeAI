import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/models/custom_models_service.dart';
import '../features/models/huggingface_service.dart';
import '../features/models/model_providers.dart';
import '../theme/theme.dart';

/// Live browser of the latest GGUF models on Hugging Face. Users can search,
/// pick a quant, and download — the model then appears in the normal picker.
class DiscoverModelsScreen extends ConsumerStatefulWidget {
  const DiscoverModelsScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const DiscoverModelsScreen()),
      );

  @override
  ConsumerState<DiscoverModelsScreen> createState() =>
      _DiscoverModelsScreenState();
}

class _DiscoverModelsScreenState extends ConsumerState<DiscoverModelsScreen> {
  final _searchCtrl = TextEditingController();
  late Future<List<HFRepo>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(huggingFaceServiceProvider).search();
  }

  void _runSearch() {
    setState(() {
      _future =
          ref.read(huggingFaceServiceProvider).search(query: _searchCtrl.text);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceBase,
      appBar: AppBar(
        title: const Text('Discover models'),
        backgroundColor: AppColors.surfaceBase,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _runSearch(),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search Hugging Face (e.g. llama, qwen, phi)…',
                hintStyle: const TextStyle(color: AppColors.textDim),
                prefixIcon: const Icon(Icons.search, color: AppColors.textDim),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward,
                      color: AppColors.accentGreen),
                  onPressed: _runSearch,
                ),
                filled: true,
                fillColor: AppColors.surfaceOverlay,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Most downloaded GGUF models · live from huggingface.co',
                  style: TextStyle(color: AppColors.textDim, fontSize: 11)),
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
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No results. Check your connection or try another search.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: repos.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _RepoCard(
                    repo: repos[i],
                    onTap: () => _showQuantPicker(repos[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showQuantPicker(HFRepo repo) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceSidebar,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _QuantPickerSheet(repo: repo),
    );
  }
}

class _RepoCard extends StatelessWidget {
  const _RepoCard({required this.repo, required this.onTap});
  final HFRepo repo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final updated = repo.lastModified.length >= 10
        ? repo.lastModified.substring(0, 10)
        : repo.lastModified;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceOverlay,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderDefault),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(repo.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(repo.owner,
                style: const TextStyle(color: AppColors.textDim, fontSize: 12)),
            const SizedBox(height: 8),
            Row(
              children: [
                _Stat(icon: Icons.download_outlined, label: _fmt(repo.downloads)),
                const SizedBox(width: 14),
                _Stat(icon: Icons.favorite_outline, label: _fmt(repo.likes)),
                const SizedBox(width: 14),
                if (updated.isNotEmpty)
                  _Stat(icon: Icons.update, label: updated),
                const Spacer(),
                const Icon(Icons.chevron_right, color: AppColors.textDim, size: 18),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.textDim),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(color: AppColors.textDim, fontSize: 11)),
      ],
    );
  }
}

class _QuantPickerSheet extends ConsumerStatefulWidget {
  const _QuantPickerSheet({required this.repo});
  final HFRepo repo;

  @override
  ConsumerState<_QuantPickerSheet> createState() => _QuantPickerSheetState();
}

class _QuantPickerSheetState extends ConsumerState<_QuantPickerSheet> {
  late Future<List<HFFile>> _files;

  @override
  void initState() {
    super.initState();
    _files = ref.read(huggingFaceServiceProvider).ggufFiles(widget.repo.id);
  }

  Future<void> _pick(HFFile file) async {
    final model = HuggingFaceService.toModelVariant(widget.repo, file);
    await ref.read(customModelsProvider.notifier).add(model);
    ref.read(modelActionsProvider).download(model);
    if (mounted) {
      Navigator.pop(context); // sheet
      Navigator.pop(context); // discover screen → back to picker
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Downloading ${model.displayName}…')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Text(widget.repo.displayName,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text('Choose a quantisation (smaller = faster, less RAM)',
                    style: TextStyle(color: AppColors.textDim, fontSize: 12)),
              ),
              if (files.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No single-file GGUF quants found in this repo.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                ),
              for (final f in files)
                ListTile(
                  leading: const Icon(Icons.memory, color: AppColors.textMuted),
                  title: Text(f.quantLabel,
                      style: const TextStyle(color: Colors.white)),
                  subtitle: Text('${(f.sizeBytes / 1e9).toStringAsFixed(2)} GB',
                      style: const TextStyle(
                          color: AppColors.textDim, fontSize: 12)),
                  trailing: const Icon(Icons.download_outlined,
                      color: AppColors.accentGreen, size: 20),
                  onTap: () => _pick(f),
                ),
              const SizedBox(height: 16),
            ],
          );
        },
      ),
    );
  }
}
