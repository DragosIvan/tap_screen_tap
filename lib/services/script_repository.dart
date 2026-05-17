import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/script.dart';
import '../models/tap_step.dart';

class ScriptRepository {
  static const _scriptsKey = 'scripts_v1';
  static const _activeScriptIdKey = 'active_script_id_v1';

  static Future<void>? _writeChain;

  Future<List<Script>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    // Reload from native storage so writes from the overlay isolate are visible.
    await prefs.reload();
    final raw = prefs.getString(_scriptsKey);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => Script.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Script?> getById(String id) async {
    final all = await getAll();
    try {
      return all.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(Script script) async {
    final all = await getAll();
    final index = all.indexWhere((s) => s.id == script.id);
    if (index >= 0) {
      all[index] = script;
    } else {
      all.add(script);
    }
    await _persist(all);
  }

  /// Updates only the steps for [scriptId]. Serialized across isolates and
  /// always reads from disk first so overlay edits are not lost to stale cache.
  Future<bool> updateSteps(String scriptId, List<TapStep> steps) async {
    final completer = Completer<bool>();
    final previous = _writeChain;
    _writeChain = (previous ?? Future.value()).then((_) async {
      try {
        final ok = await _updateStepsUnlocked(scriptId, steps);
        completer.complete(ok);
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  Future<bool> _updateStepsUnlocked(String scriptId, List<TapStep> steps) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString(_scriptsKey);
    if (raw == null || raw.isEmpty) return false;

    final list = jsonDecode(raw) as List<dynamic>;
    var found = false;
    final updated = <Map<String, dynamic>>[];
    for (final item in list) {
      final map = Map<String, dynamic>.from(item as Map);
      if (map['id'] == scriptId) {
        map['steps'] = steps.map((s) => s.toJson()).toList();
        found = true;
      }
      updated.add(map);
    }
    if (!found) return false;

    await prefs.setString(_scriptsKey, jsonEncode(updated));
    return true;
  }

  Future<void> delete(String id) async {
    final all = await getAll();
    all.removeWhere((s) => s.id == id);
    await _persist(all);
    final activeId = await getActiveScriptId();
    if (activeId == id) {
      await clearActiveScript();
    }
  }

  Future<String?> getActiveScriptId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeScriptIdKey);
  }

  Future<Script?> getActiveScript() async {
    final id = await getActiveScriptId();
    if (id == null) return null;
    return getById(id);
  }

  Future<void> setActiveScriptId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeScriptIdKey, id);
  }

  Future<void> clearActiveScript() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activeScriptIdKey);
  }

  Future<void> _persist(List<Script> scripts) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(scripts.map((s) => s.toJson()).toList());
    await prefs.setString(_scriptsKey, encoded);
  }
}
