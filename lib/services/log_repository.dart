import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/execution_log.dart';

class LogRepository {
  static const _logIndexKey = 'execution_log_index_v1';
  static String _logKey(String scriptId) => 'execution_log_$scriptId';

  Future<void> save(ExecutionLog log) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_logKey(log.scriptId), jsonEncode(log.toJson()));
    final index = await _getIndex();
    if (!index.contains(log.scriptId)) {
      index.add(log.scriptId);
      await prefs.setString(_logIndexKey, jsonEncode(index));
    }
  }

  Future<ExecutionLog?> getForScript(String scriptId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_logKey(scriptId));
    if (raw == null) return null;
    return ExecutionLog.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<List<String>> getScriptIdsWithLogs() async => _getIndex();

  Future<void> deleteForScript(String scriptId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_logKey(scriptId));
    final index = await _getIndex();
    index.remove(scriptId);
    await prefs.setString(_logIndexKey, jsonEncode(index));
  }

  Future<List<String>> _getIndex() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_logIndexKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List<dynamic>).cast<String>();
  }
}
