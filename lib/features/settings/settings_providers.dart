import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'settings_service.dart';

final settingsServiceProvider = Provider<SettingsService>(
  (_) => SettingsService(),
);

/// Triggers auto-load of the last used model on app startup.
/// Watched by HomeScreen to start the async chain once the widget tree is live.
final autoLoadLastModelProvider = FutureProvider<String?>((ref) async {
  return ref.read(settingsServiceProvider).getLastModelId();
});
