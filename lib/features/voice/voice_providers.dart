import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'voice_service.dart';

final voiceServiceProvider = Provider<VoiceService>((ref) {
  final svc = VoiceService();
  ref.onDispose(svc.stopListening);
  return svc;
});
