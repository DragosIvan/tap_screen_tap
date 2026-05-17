import 'package:shared_preferences/shared_preferences.dart';

class SettingsRepository {
  static const _logsEnabledKey = 'settings_logs_enabled';

  Future<bool> isLoggingEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_logsEnabledKey) ?? false;
  }

  Future<void> setLoggingEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_logsEnabledKey, enabled);
  }
}
