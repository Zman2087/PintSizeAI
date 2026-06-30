import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const _kLastModelId = 'last_model_id';
  static const _kHasAcceptedTos = 'has_accepted_tos';
  static const _kSystemPrompt = 'custom_system_prompt';
  static const _kMemories = 'persistent_memories_v1';
  static const _kAutoSpeak = 'auto_speak_enabled';
  static const _kOnboardingComplete = 'onboarding_complete';

  Future<bool> getOnboardingComplete() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kOnboardingComplete) ?? false;
  }

  Future<bool> getMemoryEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('memory_enabled') ?? true;
  }

  Future<void> setMemoryEnabled(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('memory_enabled', v);
  }

  Future<void> setOnboardingComplete(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOnboardingComplete, v);
  }

  Future<String?> getLastModelId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kLastModelId);
  }

  Future<void> setLastModelId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastModelId, id);
  }

  Future<void> clearLastModelId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kLastModelId);
  }

  Future<bool> hasAcceptedTos() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kHasAcceptedTos) ?? false;
  }

  Future<void> acceptTos() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHasAcceptedTos, true);
  }

  // ── TTS voice ───────────────────────────────────────────────────────────────

  Future<String?> getVoiceId() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString('tts_voice_id');
    return (v == null || v.isEmpty) ? null : v;
  }

  Future<void> setVoiceId(String? id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null || id.isEmpty) {
      await prefs.remove('tts_voice_id');
    } else {
      await prefs.setString('tts_voice_id', id);
    }
  }

  // ── Custom system prompt ────────────────────────────────────────────────────

  Future<String?> getSystemPrompt() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_kSystemPrompt);
    return (v == null || v.isEmpty) ? null : v;
  }

  Future<void> setSystemPrompt(String prompt) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSystemPrompt, prompt);
  }

  // ── Persistent memory ───────────────────────────────────────────────────────

  Future<List<String>> getMemories() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kMemories);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List).cast<String>();
    } catch (_) {
      return [];
    }
  }

  Future<void> addMemory(String summary) async {
    final existing = await getMemories();
    final updated = [summary, ...existing].take(12).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMemories, jsonEncode(updated));
  }

  Future<void> clearMemories() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kMemories);
  }

  // ── Auto-speak ──────────────────────────────────────────────────────────────

  Future<bool> getAutoSpeak() async {
    final prefs = await SharedPreferences.getInstance();
    // Default ON so the assistant speaks its replies out of the box.
    return prefs.getBool(_kAutoSpeak) ?? true;
  }

  Future<void> setAutoSpeak(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoSpeak, value);
  }

  // ── Sampling params ─────────────────────────────────────────────────────────

  static const _kTemperature = 'llm_temperature';
  static const _kTopP = 'llm_top_p';
  static const _kMaxTokens = 'llm_max_tokens';

  Future<double> getTemperature() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_kTemperature) ?? 0.7;
  }

  Future<void> setTemperature(double v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kTemperature, v);
  }

  Future<double> getTopP() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_kTopP) ?? 0.9;
  }

  Future<void> setTopP(double v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kTopP, v);
  }

  Future<int> getMaxTokens() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kMaxTokens) ?? 512;
  }

  Future<void> setMaxTokens(int v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kMaxTokens, v);
  }

  // ── Streaming TTS ────────────────────────────────────────────────────────────

  static const _kStreamingTts = 'streaming_tts_enabled';

  Future<bool> getStreamingTts() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kStreamingTts) ?? false;
  }

  Future<void> setStreamingTts(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kStreamingTts, v);
  }

  // ── iCloud sync ──────────────────────────────────────────────────────────────

  static const _kICloudSync = 'icloud_sync_enabled';

  Future<bool> getICloudSync() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kICloudSync) ?? false;
  }

  Future<void> setICloudSync(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kICloudSync, v);
  }
}
