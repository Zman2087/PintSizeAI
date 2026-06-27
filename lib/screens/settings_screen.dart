import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../features/device_recommender/device_profile.dart';
import '../features/device_recommender/model_catalogue.dart';
import '../features/device_recommender/recommender_providers.dart';
import '../features/image_gen/image_gen_providers.dart';
import '../features/models/model_providers.dart';
import '../features/settings/settings_providers.dart';
import '../features/settings/settings_service.dart';
import '../theme/theme.dart';
import 'image_gen_screen.dart';
import 'legal/privacy_policy_screen.dart';
import 'legal/recommended_specs_screen.dart';
import 'legal/terms_of_service_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeModel = ref.watch(activeModelProvider);

    return Scaffold(
      backgroundColor: AppColors.surfaceBase,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: AppColors.surfaceBase,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // Active model card
          if (activeModel != null) ...[
            _SectionHeader('Current Model'),
            _Card(
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceActive,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.memory,
                        color: AppColors.textMuted, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(activeModel.displayName,
                            style: AppTypography.modelName),
                        Text(
                          '${activeModel.creator} · ${activeModel.parametersBillions}B · ${activeModel.quant.label}',
                          style: AppTypography.modelDesc,
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        ref.read(modelActionsProvider).unloadModel(),
                    style: TextButton.styleFrom(
                        foregroundColor: AppColors.textMuted),
                    child: const Text('Unload'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Device capabilities
          const SizedBox(height: 8),
          _SectionHeader('Your Device'),
          _DeviceCapabilitiesCard(),
          const SizedBox(height: 8),

          // Privacy
          _SectionHeader('Privacy'),
          _Card(
            child: Column(
              children: [
                _InfoRow(
                  icon: Icons.lock_outline,
                  title: 'All processing on-device',
                  subtitle: 'No data ever leaves your phone',
                  iconColor: AppColors.accentGreen,
                ),
                Divider(height: 1, color: AppColors.borderDefault),
                _InfoRow(
                  icon: Icons.cloud_off_outlined,
                  title: 'No telemetry or analytics',
                  subtitle: 'We collect zero usage data',
                  iconColor: AppColors.accentGreen,
                ),
                Divider(height: 1, color: AppColors.borderDefault),
                _InfoRow(
                  icon: Icons.storage_outlined,
                  title: 'Model files stored locally',
                  subtitle: 'In your app\'s document directory',
                  iconColor: AppColors.textMuted,
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // AI Behaviour
          _SectionHeader('AI Behaviour'),
          _SystemPromptCard(),
          const SizedBox(height: 12),
          _MemoryCard(),

          const SizedBox(height: 20),

          // Voice
          _SectionHeader('Voice'),
          _VoiceSettingsCard(),

          const SizedBox(height: 20),

          // Image Generation
          _SectionHeader('Image Generation'),
          _Card(
            child: _ImageGenRow(context: context),
          ),

          const SizedBox(height: 20),

          // Legal
          _SectionHeader('Legal'),
          _Card(
            child: Column(
              children: [
                _NavRow(
                  icon: Icons.description_outlined,
                  title: 'Terms of Service',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const TermsOfServiceScreen()),
                  ),
                ),
                Divider(height: 1, color: AppColors.borderDefault),
                _NavRow(
                  icon: Icons.privacy_tip_outlined,
                  title: 'Privacy Policy',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const PrivacyPolicyScreen()),
                  ),
                ),
                Divider(height: 1, color: AppColors.borderDefault),
                _NavRow(
                  icon: Icons.phone_iphone_outlined,
                  title: 'Device Requirements',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const RecommendedSpecsScreen()),
                  ),
                ),
                Divider(height: 1, color: AppColors.borderDefault),
                _NavRow(
                  icon: Icons.code_outlined,
                  title: 'Open Source Licences',
                  onTap: () => _showOpenSourceLicences(context),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // About
          _SectionHeader('About'),
          _Card(
            child: Column(
              children: [
                _InfoRow(
                  icon: Icons.info_outline,
                  title: 'PintSizeAi',
                  subtitle: 'Version 1.0.0',
                  iconColor: AppColors.textMuted,
                ),
                Divider(height: 1, color: AppColors.borderDefault),
                _InfoRow(
                  icon: Icons.psychology_outlined,
                  title: 'Inference engine',
                  subtitle: 'llama.cpp (MIT Licence)',
                  iconColor: AppColors.textMuted,
                ),
                Divider(height: 1, color: AppColors.borderDefault),
                _LinkRow(
                  icon: Icons.hub_outlined,
                  title: 'Model source',
                  subtitle: 'Hugging Face (huggingface.co)',
                  url: 'https://huggingface.co',
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Clear data
          _SectionHeader('Data'),
          _Card(
            child: _NavRow(
              icon: Icons.delete_outline,
              title: 'Clear chat history',
              iconColor: const Color(0xFFE57373),
              titleColor: const Color(0xFFE57373),
              onTap: () => _confirmClearHistory(context, ref),
            ),
          ),

          const SizedBox(height: 40),

          Center(
            child: Text(
              'Made with ❤ for privacy',
              style: TextStyle(
                  color: AppColors.textDim, fontSize: 12),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _showOpenSourceLicences(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceOverlay,
        title: const Text('Open Source Licences',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              _LicenceEntry('llama.cpp', 'MIT Licence',
                  'Georgi Gerganov & contributors'),
              _LicenceEntry('Flutter', 'BSD 3-Clause Licence',
                  'Google & contributors'),
              _LicenceEntry('flutter_riverpod', 'MIT Licence', 'Remi Rousselet'),
              _LicenceEntry('dio', 'MIT Licence', 'CancelToken & contributors'),
              _LicenceEntry(
                  'image_picker', 'BSD 3-Clause Licence', 'Flutter team'),
              _LicenceEntry(
                  'file_picker', 'MIT Licence', 'Miguel Ruivo'),
              _LicenceEntry('shared_preferences', 'BSD 3-Clause Licence',
                  'Flutter team'),
              _LicenceEntry('path_provider', 'BSD 3-Clause Licence',
                  'Flutter team'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _confirmClearHistory(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceOverlay,
        title: const Text('Clear chat history?',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'This will remove all conversations from this session. '
          'Downloaded models will not be affected.',
          style: TextStyle(color: AppColors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
              // Clear is handled by the chat controller — emit a clear event
              // via the settings notifier (chat controller listens)
              ref.read(settingsServiceProvider).clearLastModelId();
            },
            style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFE57373)),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(
          text.toUpperCase(),
          style: AppTypography.sectionLabel,
        ),
      );
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceOverlay,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderDefault),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 20, color: iconColor ?? AppColors.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.modelName),
                Text(subtitle, style: AppTypography.modelDesc),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.url,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String url;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: iconColor ?? AppColors.textMuted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTypography.modelName),
                  Text(subtitle,
                      style: AppTypography.modelDesc.copyWith(
                          color: const Color(0xFF60A5FA))),
                ],
              ),
            ),
            const Icon(Icons.open_in_new,
                size: 14, color: Color(0xFF60A5FA)),
          ],
        ),
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.iconColor,
    this.titleColor,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Color? iconColor;
  final Color? titleColor;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: iconColor ?? AppColors.textMuted),
            const SizedBox(width: 12),
            Expanded(
              child: subtitle != null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: AppTypography.modelName.copyWith(
                                color: titleColor ?? AppColors.textDefault)),
                        Text(subtitle!, style: AppTypography.modelDesc),
                      ],
                    )
                  : Text(title,
                      style: AppTypography.modelName.copyWith(
                          color: titleColor ?? AppColors.textDefault)),
            ),
            Icon(Icons.chevron_right, size: 18, color: AppColors.textDim),
          ],
        ),
      ),
    );
  }
}

class _ImageGenRow extends ConsumerWidget {
  const _ImageGenRow({required this.context});
  final BuildContext context;

  @override
  Widget build(BuildContext ctx, WidgetRef ref) {
    final status = ref.watch(sdModelProvider);
    final subtitle = switch (status.state) {
      SDModelState.loaded => 'Active — Core ML model loaded',
      SDModelState.ready => 'Downloaded — tap to load',
      SDModelState.downloading => 'Downloading… ${(status.downloadProgress * 100).toInt()}%',
      SDModelState.extracting => 'Extracting…',
      SDModelState.loading => 'Loading into memory…',
      SDModelState.error => 'Error — tap to retry',
      _ => 'No model — download to enable real generation',
    };
    return _NavRow(
      icon: Icons.auto_awesome_outlined,
      title: 'Stable Diffusion Models',
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ImageGenScreen()),
      ),
      subtitle: subtitle,
    );
  }
}

class _LicenceEntry extends StatelessWidget {
  const _LicenceEntry(this.name, this.licence, this.author);
  final String name;
  final String licence;
  final String author;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name,
              style: TextStyle(
                  color: AppColors.textDefault,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
          Text('$licence · $author',
              style: TextStyle(
                  color: AppColors.textDim, fontSize: 12, height: 1.4)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Device capabilities card
// ─────────────────────────────────────────────────────────────────────────────

class _DeviceCapabilitiesCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(deviceProfileProvider);

    return profileAsync.when(
      loading: () => const _Card(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (_, __) => const _Card(
        child: _CapRow(
          icon: Icons.warning_amber_outlined,
          title: 'Could not read device info',
        ),
      ),
      data: (profile) => _Card(
        child: Column(
          children: [
            _CapRow(
              icon: Icons.smartphone_outlined,
              title: profile.deviceName,
              sub: 'iOS ${profile.osVersion}',
            ),
            _CapRow(
              icon: Icons.memory_outlined,
              title: 'RAM: ${profile.totalRamGb} GB total · ${profile.freeRamGb} GB free',
              sub: 'Model budget: up to ${(profile.safeModelRamBytes / 1e9).toStringAsFixed(1)} GB',
            ),
            _CapRow(
              icon: Icons.speed_outlined,
              title: 'Chip: ${_chipLabel(profile.chipTier)}',
              sub: profile.hasGpuAcceleration
                  ? 'GPU acceleration available'
                  : 'CPU-only inference',
            ),
            _CapRow(
              icon: Icons.storage_outlined,
              title: 'Storage free: ${(profile.freeStorageBytes / 1e9).toStringAsFixed(1)} GB',
            ),
            _CapRow(
              icon: Icons.lightbulb_outline,
              title: _tierSummary(profile.chipTier),
            ),
          ],
        ),
      ),
    );
  }

  String _chipLabel(ChipTier tier) => switch (tier) {
        ChipTier.flagship => 'Flagship (A17 Pro / A18 class)',
        ChipTier.highEnd => 'High-end (A15 / A16)',
        ChipTier.midRange => 'Mid-range (A14 / A13)',
        ChipTier.entry => 'Entry-level',
        ChipTier.tooSlow => 'Older chip',
      };

  String _tierSummary(ChipTier tier) => switch (tier) {
        ChipTier.flagship =>
          'Best for models up to 8B params (Q4). Real-time generation.',
        ChipTier.highEnd =>
          'Good for models up to 3B params (Q4). ~10–20 tok/s.',
        ChipTier.midRange =>
          'Best with 1–2B models (Q4). Expect 5–10 tok/s.',
        ChipTier.entry =>
          'Stick to 135M–360M models. Larger models may be slow.',
        ChipTier.tooSlow =>
          'Very old device — only tiny models (135M) will run usably.',
      };
}

class _CapRow extends StatelessWidget {
  const _CapRow({required this.icon, required this.title, this.sub});
  final IconData icon;
  final String title;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.modelName),
                if (sub != null) ...[
                  const SizedBox(height: 2),
                  Text(sub!, style: AppTypography.modelDesc),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// System prompt card
// ─────────────────────────────────────────────────────────────────────────────

class _SystemPromptCard extends ConsumerStatefulWidget {
  @override
  ConsumerState<_SystemPromptCard> createState() => _SystemPromptCardState();
}

class _SystemPromptCardState extends ConsumerState<_SystemPromptCard> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    final current = ref.read(customSystemPromptProvider) ?? '';
    _ctrl = TextEditingController(text: current);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.edit_note_outlined,
                  size: 18, color: AppColors.textMuted),
              const SizedBox(width: 8),
              Text('Custom system prompt', style: AppTypography.modelName),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Override the default AI personality. Leave blank to use the default.',
            style: AppTypography.modelDesc,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _ctrl,
            style: AppTypography.messageBody
                .copyWith(fontSize: 13),
            maxLines: 4,
            decoration: InputDecoration(
              hintText: 'You are a helpful assistant...',
              hintStyle: AppTypography.placeholder,
              filled: true,
              fillColor: AppColors.surfaceBase,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.borderDefault),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.borderDefault),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppColors.accentGreen),
              ),
              contentPadding: const EdgeInsets.all(10),
            ),
            onChanged: (val) {
              ref.read(customSystemPromptProvider.notifier).update(val.isEmpty ? null : val);
              ref.read(settingsServiceProvider).setSystemPrompt(val);
            },
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Memory card
// ─────────────────────────────────────────────────────────────────────────────

class _MemoryCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memories = ref.watch(persistentMemoriesProvider);
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.psychology_outlined,
                  size: 18, color: AppColors.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Persistent memory', style: AppTypography.modelName),
              ),
              if (memories.isNotEmpty)
                GestureDetector(
                  onTap: () async {
                    ref.read(persistentMemoriesProvider.notifier).clear();
                    await ref.read(settingsServiceProvider).clearMemories();
                  },
                  child: Text('Clear',
                      style: AppTypography.badge
                          .copyWith(color: const Color(0xFFEF4444))),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'The AI automatically summarises conversations and remembers them across sessions.',
            style: AppTypography.modelDesc,
          ),
          if (memories.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...memories.map((m) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ',
                          style: TextStyle(color: AppColors.textMuted)),
                      Expanded(
                        child: Text(m, style: AppTypography.modelDesc),
                      ),
                    ],
                  ),
                )),
          ] else ...[
            const SizedBox(height: 6),
            Text('No memories yet — start chatting!',
                style: AppTypography.modelDesc.copyWith(
                    fontStyle: FontStyle.italic)),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Voice settings card
// ─────────────────────────────────────────────────────────────────────────────

class _VoiceSettingsCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final autoSpeak = ref.watch(autoSpeakProvider);
    return _Card(
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.record_voice_over_outlined,
                  size: 18, color: AppColors.textMuted),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Auto-read responses', style: AppTypography.modelName),
                    Text('AI replies are spoken aloud automatically.',
                        style: AppTypography.modelDesc),
                  ],
                ),
              ),
              Switch(
                value: autoSpeak,
                onChanged: (v) {
                  ref.read(autoSpeakProvider.notifier).set(v);
                  ref.read(settingsServiceProvider).setAutoSpeak(v);
                },
                activeColor: AppColors.accentGreen,
              ),
            ],
          ),
          const Divider(height: 1, color: AppColors.borderDefault, indent: 30),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.mic_none_outlined,
                  size: 18, color: AppColors.textMuted),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Voice input', style: AppTypography.modelName),
                    Text('Tap the mic icon in the chat bar to speak your message.',
                        style: AppTypography.modelDesc),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
