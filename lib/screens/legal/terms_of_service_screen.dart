import 'package:flutter/material.dart';
import '../../theme/theme.dart';

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceBase,
      appBar: AppBar(
        title: const Text('Terms of Service'),
        backgroundColor: AppColors.surfaceBase,
      ),
      body: const SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 40),
        child: _TosContent(),
      ),
    );
  }
}

class _TosContent extends StatelessWidget {
  const _TosContent();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _meta('Effective date: June 26, 2026   ·   Version 1.0'),
        const SizedBox(height: 24),
        _h1('Terms of Service'),
        _body(
          'Please read these Terms of Service ("Terms") carefully before using PintSizeAi. '
          'By installing or using the app you agree to be bound by these Terms. '
          'If you do not agree, do not use PintSizeAi.',
        ),
        _h2('1. About PintSizeAi'),
        _body(
          'PintSizeAi is an on-device AI assistant application that runs large language models '
          '(LLMs) and generative AI models entirely on your device. No text, images, audio, '
          'or other content you enter is transmitted to any server operated by us. '
          'Internet access is only used when you choose to download a model file.',
        ),
        _h2('2. Acceptance of Terms'),
        _body(
          'You must be at least 13 years old to use PintSizeAi. If you are under 18, '
          'you confirm that you have your parent or guardian\'s permission. '
          'By using the app you represent that you meet these requirements.',
        ),
        _h2('3. Licence to Use'),
        _body(
          'Subject to these Terms, we grant you a personal, non-exclusive, non-transferable, '
          'revocable licence to install and use PintSizeAi on devices you own or control, '
          'solely for your personal, non-commercial purposes.',
        ),
        _h2('4. AI-Generated Content Disclaimer'),
        _body(
          'PintSizeAi uses artificial intelligence models to generate responses. '
          'You acknowledge and agree that:\n\n'
          '• AI-generated content may be inaccurate, incomplete, or misleading.\n'
          '• Responses do not constitute professional advice of any kind — medical, legal, '
          'financial, psychological, or otherwise.\n'
          '• You must exercise your own judgement before acting on any AI-generated content.\n'
          '• We make no representations about the accuracy, reliability, or suitability '
          'of AI-generated responses for any purpose.',
        ),
        _h2('5. Acceptable Use'),
        _body(
          'You agree not to use PintSizeAi to:\n\n'
          '• Generate content that is illegal, harmful, abusive, harassing, defamatory, '
          'or violates the rights of others.\n'
          '• Produce, share, or distribute child sexual abuse material (CSAM) or any '
          'content sexualising minors.\n'
          '• Attempt to circumvent model safety guidelines through prompt injection, '
          'jailbreaking, or other manipulation techniques.\n'
          '• Engage in fraud, impersonation, or any deceptive conduct.\n'
          '• Generate content intended to incite violence or terrorism.\n'
          '• Violate any applicable law or regulation in your jurisdiction.',
        ),
        _h2('6. Model Downloads and Third-Party Content'),
        _body(
          'AI model files are downloaded from Hugging Face (huggingface.co), a third-party '
          'service. Downloading and using these models is subject to their individual licences '
          '(commonly Apache 2.0, MIT, or model-specific community licences). '
          'You are responsible for complying with the licence terms of any model you download. '
          'We do not host, modify, or redistribute these model files.',
        ),
        _h2('7. Privacy'),
        _body(
          'All AI inference runs locally on your device. We do not collect, store, or '
          'transmit any conversation data, generated content, or personal information. '
          'Please see our Privacy Policy for full details.',
        ),
        _h2('8. Intellectual Property'),
        _body(
          'PintSizeAi and its original code are proprietary. The underlying AI models '
          'remain the intellectual property of their respective creators (Meta, Microsoft, '
          'Google, Mistral AI, Alibaba, DeepSeek, and others). The inference engine is '
          'based on llama.cpp (MIT Licence). Open-source component attributions are '
          'listed in the Open Source Licences section of the app.',
        ),
        _h2('9. Disclaimer of Warranties'),
        _body(
          'PINTSIZE AI IS PROVIDED "AS IS" WITHOUT WARRANTIES OF ANY KIND, EXPRESS OR '
          'IMPLIED, INCLUDING BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, FITNESS '
          'FOR A PARTICULAR PURPOSE, AND NON-INFRINGEMENT. WE DO NOT WARRANT THAT THE '
          'APP WILL BE UNINTERRUPTED, ERROR-FREE, OR THAT AI OUTPUTS WILL BE ACCURATE.',
        ),
        _h2('10. Limitation of Liability'),
        _body(
          'TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, WE SHALL NOT BE LIABLE '
          'FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES '
          'ARISING FROM YOUR USE OF OR INABILITY TO USE PINTSIZE AI, EVEN IF WE HAVE '
          'BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGES. IN JURISDICTIONS THAT DO '
          'NOT ALLOW THE EXCLUSION OF CERTAIN WARRANTIES, OUR LIABILITY IS LIMITED TO '
          'THE GREATEST EXTENT PERMITTED BY LAW.',
        ),
        _h2('11. Changes to These Terms'),
        _body(
          'We may update these Terms from time to time. If we make material changes we '
          'will update the "Effective date" above and notify you through the app. '
          'Continued use of PintSizeAi after any changes constitutes acceptance of the '
          'revised Terms.',
        ),
        _h2('12. Governing Law'),
        _body(
          'These Terms are governed by the laws of the jurisdiction in which the developer '
          'is established, without regard to conflict of law principles.',
        ),
        _h2('13. Contact'),
        _body(
          'For questions about these Terms, contact us through the app\'s support channel '
          'or the contact information provided in the App Store / Play Store listing.',
        ),
        const SizedBox(height: 32),
        _divider(),
        const SizedBox(height: 16),
        _meta('These Terms were last updated on June 26, 2026.'),
        const SizedBox(height: 8),
        _meta(
          'The plain-language summary: we built a privacy-first AI app that runs '
          'entirely on your device. Don\'t use it for illegal or harmful purposes, '
          'don\'t treat AI output as professional advice, and enjoy the app responsibly.',
        ),
      ],
    );
  }

  Widget _h1(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
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

  Widget _body(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text,
            style: TextStyle(
                color: AppColors.textMuted, fontSize: 14, height: 1.65)),
      );

  Widget _meta(String text) => Text(text,
      style: TextStyle(color: AppColors.textDim, fontSize: 12, height: 1.5));

  Widget _divider() => Divider(color: AppColors.borderDefault);
}
