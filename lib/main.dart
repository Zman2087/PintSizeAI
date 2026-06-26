import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'features/models/model_providers.dart';
import 'features/siri/siri_service.dart';
import 'screens/home_screen.dart';
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
      home: const HomeScreen(),
    );
  }
}
