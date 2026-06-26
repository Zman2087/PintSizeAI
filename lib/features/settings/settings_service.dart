import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const _kLastModelId = 'last_model_id';
  static const _kHasAcceptedTos = 'has_accepted_tos';

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
}
