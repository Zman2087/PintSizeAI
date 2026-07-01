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
import '../features/voice/voice_providers.dart';
import '../features/voice/voice_service.dart';
import '../theme/theme.dart';
import 'image_gen_screen.dart';
import 'legal/privacy_policy_screen.dart';
import 'legal/recommended_specs_screen.dart';
import 'legal/terms_of_service_screen.dart';

/// Buy Me a Coffee tip link.
const String kBuyMeACoffeeUrl = 'https://buymeacoffee.com/zwylie';

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
                    child: Icon(Icons.memory,
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

          // Model parameters
          _SectionHeader('Model Parameters'),
          _ModelParamsCard(),

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

          // Sync
          _SectionHeader('Sync'),
          _ICloudSyncCard(),

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
          _SectionHeader('Support'),
          _Card(
            child: Column(
              children: [
                _LinkRow(
                  icon: Icons.coffee_outlined,
                  title: 'Buy me a coffee',
                  subtitle: 'Support the developer with a tip',
                  url: kBuyMeACoffeeUrl,
                  iconColor: const Color(0xFFFFDD00),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

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
        title: Text('Open Source Licences',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
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
        title: Text('Clear chat history?',
            style: TextStyle(color: AppColors.textPrimary)),
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
  const _Card({required this.child, this.padding = EdgeInsets.zero});
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceOverlay,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderDefault),
        ),
        clipBehavior: Clip.antiAlias,
        padding: padding,
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.edit_note_outlined,
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
                borderSide: BorderSide(color: AppColors.borderDefault),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppColors.borderDefault),
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
    final enabled = ref.watch(memoryEnabledProvider);
    final memories = ref.watch(persistentMemoriesProvider);
    return _Card(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.psychology_outlined,
                  size: 18, color: AppColors.textMuted),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Remember across chats',
                        style: AppTypography.modelName),
                    Text(
                      'Let the AI recall context and your feedback from past chats.',
                      style: AppTypography.modelDesc,
                    ),
                  ],
                ),
              ),
              Switch(
                value: enabled,
                onChanged: (v) {
                  ref.read(memoryEnabledProvider.notifier).set(v);
                  ref.read(settingsServiceProvider).setMemoryEnabled(v);
                  // Turning memory off clears anything already stored.
                  if (!v) {
                    ref.read(persistentMemoriesProvider.notifier).clear();
                    ref.read(settingsServiceProvider).clearMemories();
                  }
                },
                activeColor: AppColors.accentGreen,
              ),
            ],
          ),
          if (enabled && memories.isNotEmpty) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                onTap: () async {
                  ref.read(persistentMemoriesProvider.notifier).clear();
                  await ref.read(settingsServiceProvider).clearMemories();
                },
                child: Text('Clear ${memories.length} stored memories',
                    style: AppTypography.badge
                        .copyWith(color: const Color(0xFFEF4444))),
              ),
            ),
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.record_voice_over_outlined,
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
          Divider(height: 1, color: AppColors.borderDefault, indent: 30),
          const SizedBox(height: 4),
          // AI voice picker
          InkWell(
            onTap: () => _showVoicePicker(context, ref),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.graphic_eq,
                      size: 18, color: AppColors.textMuted),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('AI voice', style: AppTypography.modelName),
                        Text('Choose the voice the AI speaks with.',
                            style: AppTypography.modelDesc),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right,
                      size: 18, color: AppColors.textDim),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: AppColors.borderDefault, indent: 30),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.mic_none_outlined,
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

  void _showVoicePicker(BuildContext context, WidgetRef ref) {
    final voice = ref.read(voiceServiceProvider);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceSidebar,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.92,
        builder: (_, scroll) => FutureBuilder<List<VoiceOption>>(
          future: voice.listVoices(),
          builder: (ctx, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final voices = snap.data!;
            final selected = ref.read(selectedVoiceProvider);
            return ListView(
              controller: scroll,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
                  child: Text('AI voice',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: Text(
                    'For the most human voices, pick an "Enhanced" or "Premium" '
                    'one below. If none appear, download them in iOS Settings ▸ '
                    'Accessibility ▸ Spoken Content ▸ Voices.',
                    style: TextStyle(color: AppColors.textDim, fontSize: 12),
                  ),
                ),
                // Personal Voice — speak in the user's own cloned voice.
                ListTile(
                  leading: const Icon(Icons.face_retouching_natural,
                      color: AppColors.accentGreen),
                  title: Text('Speak in my own voice',
                      style: TextStyle(color: AppColors.textPrimary)),
                  subtitle: Text(
                      'Use your iOS Personal Voice (private, on-device)',
                      style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                  trailing: Icon(Icons.chevron_right,
                      size: 18, color: AppColors.textDim),
                  onTap: () => _setupPersonalVoice(ctx, ref, voice),
                ),
                Divider(height: 1, color: AppColors.borderSubtle),
                _VoiceTile(
                  name: 'System default',
                  detail: 'Use the device default voice',
                  isSelected: selected == null,
                  onTap: () {
                    ref.read(selectedVoiceProvider.notifier).update(null);
                    ref.read(settingsServiceProvider).setVoiceId(null);
                    voice.setVoice(null);
                    Navigator.pop(ctx);
                  },
                ),
                for (final v in voices)
                  _VoiceTile(
                    name: v.name,
                    detail: '${v.lang} · ${v.quality}',
                    isSelected: selected == v.id,
                    onTap: () async {
                      ref.read(selectedVoiceProvider.notifier).update(v.id);
                      ref.read(settingsServiceProvider).setVoiceId(v.id);
                      await voice.setVoice(v.id);
                      await voice.speak('Hi, this is how I will sound.');
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                  ),
                const SizedBox(height: 16),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _setupPersonalVoice(
      BuildContext ctx, WidgetRef ref, dynamic voice) async {
    final status = await voice.requestPersonalVoice();
    if (!ctx.mounted) return;

    if (status == 'authorized') {
      final voices = await voice.listVoices();
      final personal = voices.where((v) => v.isPersonal).toList();
      if (personal.isNotEmpty) {
        final v = personal.first;
        ref.read(selectedVoiceProvider.notifier).update(v.id);
        ref.read(settingsServiceProvider).setVoiceId(v.id);
        await voice.setVoice(v.id);
        await voice.speak('Hi, this is your Personal Voice.');
        if (ctx.mounted) Navigator.pop(ctx);
      } else if (ctx.mounted) {
        _personalVoiceDialog(
          ctx, voice,
          title: 'Create your Personal Voice',
          message:
              'PintSize can speak in your voice, but first you need to create '
              'it in iOS Settings ▸ Accessibility ▸ Personal Voice (a one-time '
              '~15-minute recording, trained privately on your device). Once '
              'it\'s ready, come back and tap this again.',
          showSettings: true,
        );
      }
    } else if (status == 'denied' && ctx.mounted) {
      _personalVoiceDialog(
        ctx, voice,
        title: 'Permission needed',
        message:
            'To speak in your voice, allow PintSize to use your Personal Voice '
            'in iOS Settings ▸ Accessibility ▸ Personal Voice.',
        showSettings: true,
      );
    } else if (ctx.mounted) {
      _personalVoiceDialog(
        ctx, voice,
        title: 'Not available',
        message:
            'Personal Voice needs iPhone 12 or newer on iOS 17 or later. Create '
            'one in Settings ▸ Accessibility ▸ Personal Voice.',
        showSettings: true,
      );
    }
  }

  void _personalVoiceDialog(BuildContext ctx, dynamic voice,
      {required String title, required String message, bool showSettings = false}) {
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceOverlay,
        title: Text(title, style: TextStyle(color: AppColors.textPrimary)),
        content: Text(message,
            style: TextStyle(color: AppColors.textMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Close',
                style: TextStyle(color: AppColors.textMuted)),
          ),
          if (showSettings)
            TextButton(
              onPressed: () {
                voice.openSettings();
                Navigator.pop(ctx);
              },
              child: const Text('Open Settings',
                  style: TextStyle(color: AppColors.accentGreen)),
            ),
        ],
      ),
    );
  }
}

class _VoiceTile extends StatelessWidget {
  const _VoiceTile({
    required this.name,
    required this.detail,
    required this.isSelected,
    required this.onTap,
  });
  final String name;
  final String detail;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(name, style: TextStyle(color: AppColors.textPrimary)),
      subtitle: Text(detail,
          style: TextStyle(color: AppColors.textDim, fontSize: 12)),
      trailing: isSelected
          ? const Icon(Icons.check, color: AppColors.accentGreen, size: 18)
          : null,
      onTap: onTap,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Model Parameters card
// ─────────────────────────────────────────────────────────────────────────────

class _ModelParamsCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final temperature = ref.watch(temperatureProvider);
    final topP = ref.watch(topPProvider);
    final maxTokens = ref.watch(maxTokensProvider);
    final streamingTts = ref.watch(streamingTtsProvider);
    final svc = ref.read(settingsServiceProvider);

    return _Card(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Temperature
          Row(
            children: [
              Icon(Icons.thermostat_outlined,
                  size: 16, color: AppColors.textMuted),
              const SizedBox(width: 8),
              Expanded(
                  child: Text('Temperature', style: AppTypography.modelName)),
              Text(temperature.toStringAsFixed(2),
                  style: AppTypography.modelDesc),
            ],
          ),
          Text('Higher = more creative, lower = more deterministic',
              style: AppTypography.modelDesc),
          Slider(
            value: temperature,
            min: 0.0,
            max: 2.0,
            divisions: 40,
            activeColor: AppColors.accentGreen,
            onChanged: (v) {
              ref.read(temperatureProvider.notifier).set(v);
              svc.setTemperature(v);
            },
          ),

          Divider(height: 8, color: AppColors.borderDefault),

          // Top-P
          Row(
            children: [
              Icon(Icons.filter_alt_outlined,
                  size: 16, color: AppColors.textMuted),
              const SizedBox(width: 8),
              Expanded(child: Text('Top-P', style: AppTypography.modelName)),
              Text(topP.toStringAsFixed(2), style: AppTypography.modelDesc),
            ],
          ),
          Text('Nucleus sampling — controls diversity',
              style: AppTypography.modelDesc),
          Slider(
            value: topP,
            min: 0.1,
            max: 1.0,
            divisions: 18,
            activeColor: AppColors.accentGreen,
            onChanged: (v) {
              ref.read(topPProvider.notifier).set(v);
              svc.setTopP(v);
            },
          ),

          Divider(height: 8, color: AppColors.borderDefault),

          // Max tokens
          Row(
            children: [
              Icon(Icons.format_list_numbered_outlined,
                  size: 16, color: AppColors.textMuted),
              const SizedBox(width: 8),
              Expanded(
                  child: Text('Max tokens', style: AppTypography.modelName)),
              Text('$maxTokens', style: AppTypography.modelDesc),
            ],
          ),
          Text('Maximum length of each AI response',
              style: AppTypography.modelDesc),
          Slider(
            value: maxTokens.toDouble(),
            min: 64,
            max: 2048,
            divisions: 31,
            activeColor: AppColors.accentGreen,
            onChanged: (v) {
              ref.read(maxTokensProvider.notifier).set(v.round());
              svc.setMaxTokens(v.round());
            },
          ),

          Divider(height: 8, color: AppColors.borderDefault),

          // Streaming TTS
          Row(
            children: [
              Icon(Icons.record_voice_over_outlined,
                  size: 16, color: AppColors.textMuted),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Streaming voice', style: AppTypography.modelName),
                    Text('Speak sentences as they generate (faster response)',
                        style: AppTypography.modelDesc),
                  ],
                ),
              ),
              Switch(
                value: streamingTts,
                onChanged: (v) {
                  ref.read(streamingTtsProvider.notifier).set(v);
                  svc.setStreamingTts(v);
                },
                activeColor: AppColors.accentGreen,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// iCloud Sync card
// ─────────────────────────────────────────────────────────────────────────────

class _ICloudSyncCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(iCloudSyncProvider);
    return _Card(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.cloud_outlined, size: 18, color: AppColors.textMuted),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('iCloud sync', style: AppTypography.modelName),
                    Text('Back up conversations to iCloud KV. '
                        'Requires iCloud account and Apple Developer entitlement.',
                        style: AppTypography.modelDesc),
                  ],
                ),
              ),
              Switch(
                value: enabled,
                onChanged: (v) {
                  ref.read(iCloudSyncProvider.notifier).set(v);
                  ref.read(settingsServiceProvider).setICloudSync(v);
                },
                activeColor: AppColors.accentGreen,
              ),
            ],
          ),
          if (enabled) ...[
            Divider(height: 16, color: AppColors.borderDefault),
            Text(
              '⚠ iCloud sync requires the iCloud capability and App Groups '
              'entitlement to be configured in Xcode with a paid Apple Developer '
              'account. Without this, the toggle is saved but sync will silently '
              'no-op.',
              style: AppTypography.modelDesc
                  .copyWith(color: const Color(0xFFF59E0B)),
            ),
          ],
        ],
      ),
    );
  }
}
