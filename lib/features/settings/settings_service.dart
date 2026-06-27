import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const _kLastModelId = 'last_model_id';
  static const _kHasAcceptedTos = 'has_accepted_tos';
  static const _kSystemPrompt = 'custom_system_prompt';
  static const _kMemories = 'persistent_memories_v1';
  static const _kAutoSpeak = 'auto_speak_enabled';

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
    return prefs.getBool(_kAutoSpeak) ?? false;
  }

  Future<void> setAutoSpeak(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoSpeak, value);
  }
}
