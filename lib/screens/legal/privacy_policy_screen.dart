import 'package:flutter/material.dart';
import '../../theme/theme.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceBase,
      appBar: AppBar(
        title: const Text('Privacy Policy'),
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
        _meta('Effective date: June 26, 2026   ·   Version 1.0'),
        const SizedBox(height: 24),
        _h1('Privacy Policy'),

        // TL;DR highlight box
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 24),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.accentGreen.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: AppColors.accentGreen.withOpacity(0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.shield_outlined,
                    color: AppColors.accentGreen, size: 16),
                const SizedBox(width: 6),
                Text('The short version',
                    style: TextStyle(
                        color: AppColors.accentGreen,
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
              ]),
              const SizedBox(height: 8),
              _bodySmall(
                'PintSizeAi processes everything on your device. We do not collect, '
                'store, or transmit your conversations, generated images, or any '
                'personal data. The only network activity is downloading model files '
                'you choose to install.',
              ),
            ],
          ),
        ),

        _h2('1. Information We Do NOT Collect'),
        _body(
          'We do not collect or have access to:\n\n'
          '• Your conversations or chat history\n'
          '• AI-generated responses\n'
          '• Images, videos, or files you attach\n'
          '• AI-generated images or videos\n'
          '• Your name, email address, or any account information\n'
          '• Device identifiers, IP addresses, or location data\n'
          '• Usage analytics or crash reports\n\n'
          'All processing happens on-device using the model files you download.',
        ),

        _h2('2. Model Downloads'),
        _body(
          'When you download a model, the app fetches a GGUF file from Hugging Face '
          '(huggingface.co). This is a direct file download — no account is required '
          'and no personal information is sent. Hugging Face\'s own privacy policy '
          'governs that download request.',
        ),

        _h2('3. Device Permissions'),
        _body(
          'PintSizeAi may request the following permissions:\n\n'
          '• Photo Library: Required only when you choose to attach an image or video '
          'from your library to a message. Photos are processed on-device and never uploaded.\n\n'
          '• Camera: Required only when you choose to take a photo to attach to a message. '
          'Camera data is processed on-device and never uploaded.\n\n'
          '• Microphone: Required for Siri integration (if enabled). Voice queries are '
          'processed via iOS Siri — Apple\'s privacy policy governs that interaction. '
          'The audio is not stored by PintSizeAi.\n\n'
          '• Local Storage: Required to store downloaded model files in your app\'s '
          'document directory.',
        ),

        _h2('4. Siri Integration'),
        _body(
          'When you use Siri to query PintSizeAi ("Hey Siri, Ask PintSizeAi…"), '
          'your voice is processed by iOS Siri according to Apple\'s privacy policy. '
          'The text of your query is passed to PintSizeAi via an on-device App Intent — '
          'no network request is made. The response is generated locally and returned '
          'to Siri on-device.',
        ),

        _h2('5. Local Storage'),
        _body(
          'PintSizeAi stores the following data locally on your device only:\n\n'
          '• Downloaded model files (GGUF format) in your app\'s document directory\n'
          '• Your last-used model preference (stored in app settings)\n'
          '• Chat history (stored in app memory — cleared when the app is deleted)\n\n'
          'None of this data leaves your device.',
        ),

        _h2('6. Children\'s Privacy'),
        _body(
          'PintSizeAi is not directed to children under the age of 13. '
          'We do not knowingly collect information from children under 13. '
          'If you believe a child under 13 is using the app, please contact us.',
        ),

        _h2('7. Third-Party Services'),
        _body(
          'The app uses the following third-party components, each under their own '
          'privacy terms:\n\n'
          '• Hugging Face (model downloads only): huggingface.co/privacy\n'
          '• Apple Siri (if used for voice queries): apple.com/legal/privacy\n'
          '• llama.cpp inference engine: MIT licence, no data collection',
        ),

        _h2('8. Data Security'),
        _body(
          'Because we do not collect or store your data on any server, there is no '
          'server-side data to breach. Your conversations and content exist only on '
          'your device, protected by iOS/Android\'s built-in security sandboxing.',
        ),

        _h2('9. Changes to This Policy'),
        _body(
          'We may update this Privacy Policy from time to time. The "Effective date" '
          'at the top of this page will be updated when changes are made. '
          'Continued use of PintSizeAi after changes are posted constitutes acceptance.',
        ),

        _h2('10. Contact Us'),
        _body(
          'If you have questions about this Privacy Policy, please reach out through '
          'the contact information in the App Store or Google Play listing.',
        ),

        const SizedBox(height: 32),
        Divider(color: AppColors.borderDefault),
        const SizedBox(height: 16),
        _meta('Privacy Policy last updated: June 26, 2026'),
      ],
    );
  }

  Widget _h1(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text(text,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                height: 1.3)),
      );

  Widget _h2(String text) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 8),
        child: Text(text,
            style: TextStyle(
                color: AppColors.textDefault,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                height: 1.3)),
      );

  Widget _body(String text) => Text(text,
      style: TextStyle(
          color: AppColors.textMuted, fontSize: 14, height: 1.65));

  Widget _bodySmall(String text) => Text(text,
      style: TextStyle(
          color: AppColors.textMuted, fontSize: 13, height: 1.55));

  Widget _meta(String text) => Text(text,
      style: TextStyle(
          color: AppColors.textDim, fontSize: 12, height: 1.5));
}
