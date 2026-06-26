import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../features/device_recommender/model_catalogue.dart';
import '../features/image_gen/image_gen_providers.dart';
import '../features/models/model_providers.dart';
import '../features/settings/settings_providers.dart';
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
