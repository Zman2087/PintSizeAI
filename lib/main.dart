import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'features/models/model_providers.dart';
import 'features/settings/settings_providers.dart';
import 'features/voice/voice_providers.dart';
import 'features/siri/siri_service.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'theme/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(
    ProviderScope(
      child: _AppInit(child: const PintSizeAiApp()),
    ),
  );
}

/// Initialises services that need the ProviderScope before the widget tree builds.
class _AppInit extends ConsumerWidget {
  const _AppInit({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.read(siriServiceProvider).init();
    // Kick off first-launch setup (no-op if a model is already on disk)
    ref.watch(firstLaunchSetupProvider);
    // Apply the user's saved TTS voice once it loads.
    ref.listen(selectedVoiceProvider, (_, voiceId) {
      ref.read(voiceServiceProvider).setVoice(voiceId);
    });
    return child;
  }
}

class PintSizeAiApp extends StatelessWidget {
  const PintSizeAiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PintSizeAi',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      builder: (context, child) {
        SystemChrome.setSystemUIOverlayStyle(
          const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark,
            systemNavigationBarColor: AppColors.surfaceBase,
            systemNavigationBarIconBrightness: Brightness.light,
          ),
        );
        return child ?? const SizedBox.shrink();
      },
      home: const _RootGate(),
    );
  }
}

/// Shows onboarding on first run, otherwise the chat. Existing users with a
/// model already installed skip straight to the chat.
class _RootGate extends ConsumerWidget {
  const _RootGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(onboardingStatusProvider);
    return status.when(
      loading: () => const Scaffold(
        backgroundColor: AppColors.surfaceBase,
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => const HomeScreen(),
      data: (done) => done ? const HomeScreen() : const OnboardingScreen(),
    );
  }
}
