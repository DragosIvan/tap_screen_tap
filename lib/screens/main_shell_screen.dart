import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/script.dart';
import '../services/overlay_service.dart';
import 'onboarding_screen.dart';
import 'script_editor_screen.dart';
import 'logs_tab.dart';
import 'scripts_tab.dart';

class MainShellScreen extends StatefulWidget {
  const MainShellScreen({super.key});

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  int _tabIndex = 0;
  Key _refreshKey = UniqueKey();
  StreamSubscription<void>? _scriptsSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      OverlayService.ensureControlOverlay();
    });
    _scriptsSub = OverlayService.scriptsChanged.listen((_) {
      // ignore: avoid_print
      print('[MainShell] scriptsChanged — reloading scripts tab');
      _refresh();
    });
  }

  @override
  void dispose() {
    _scriptsSub?.cancel();
    super.dispose();
  }

  void _refresh() => setState(() => _refreshKey = UniqueKey());

  Future<void> _createScript() async {
    final draft = Script.empty(id: const Uuid().v4());
    if (!mounted) return;

    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ScriptEditorScreen.create(draft: draft),
      ),
    );

    if (saved == true && mounted) {
      setState(() => _tabIndex = 0);
      _refresh();
      await OverlayService.ensureControlOverlay();
    }
  }

  Future<void> _openPermissions() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const OnboardingScreen(manageOnly: true),
      ),
    );
    _refresh();
    await OverlayService.ensureControlOverlay();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_tabIndex == 0 ? 'Scripts' : 'Logs'),
        actions: [
          IconButton(
            tooltip: 'New script',
            icon: const Icon(Icons.add),
            onPressed: _createScript,
          ),
          IconButton(
            tooltip: 'Permissions',
            icon: const Icon(Icons.settings),
            onPressed: _openPermissions,
          ),
        ],
      ),
      body: IndexedStack(
        index: _tabIndex,
        children: [
          ScriptsTab(
            key: ValueKey('scripts_$_refreshKey'),
            onChanged: _refresh,
          ),
          LogsTab(key: ValueKey('logs_$_refreshKey')),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.list_alt),
            label: 'Scripts',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long),
            label: 'Logs',
          ),
        ],
      ),
    );
  }
}
