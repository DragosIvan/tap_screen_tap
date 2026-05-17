import 'package:flutter/material.dart';

import '../services/clicker_channel.dart';
import '../services/settings_repository.dart';
import 'main_shell_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, this.manageOnly = false});

  /// When true (opened from settings), do not auto-navigate away if permissions
  /// are already granted — let the user review and pop back manually.
  final bool manageOnly;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _settingsRepo = SettingsRepository();

  bool _accessibility = false;
  bool _overlay = false;
  bool _checking = true;
  bool _logsEnabled = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final a11y = await ClickerChannel.isAccessibilityEnabled();
    final overlay = await ClickerChannel.canDrawOverlays();
    final logs = await _settingsRepo.isLoggingEnabled();
    if (!mounted) return;
    setState(() {
      _accessibility = a11y;
      _overlay = overlay;
      _logsEnabled = logs;
      _checking = false;
    });
    if (a11y && overlay && !widget.manageOnly) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainShellScreen()),
      );
    }
  }

  Future<void> _setLogsEnabled(bool value) async {
    await _settingsRepo.setLoggingEnabled(value);
    if (!mounted) return;
    setState(() => _logsEnabled = value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ready = _accessibility && _overlay;

    return Scaffold(
      appBar: widget.manageOnly
          ? AppBar(
              title: const Text('Settings'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              ),
            )
          : null,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              Image.asset(
                'assets/app_icon.png',
                width: 80,
                height: 80,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 16),
              Text(
                'Tap Screen Tap',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Enable the required permissions to automate taps via Accessibility.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),
              _PermissionCard(
                title: 'Accessibility Service',
                subtitle: 'Required to perform screen taps',
                done: _accessibility,
                onAction: () async {
                  await ClickerChannel.openAccessibilitySettings();
                },
                actionLabel: 'Open Settings',
              ),
              const SizedBox(height: 16),
              _PermissionCard(
                title: 'Display over other apps',
                subtitle: 'Required for recorder and control overlays',
                done: _overlay,
                onAction: () async {
                  await ClickerChannel.openOverlaySettings();
                },
                actionLabel: 'Open Settings',
              ),
              if (widget.manageOnly) ...[
                const SizedBox(height: 24),
                Text(
                  'App Settings',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: SwitchListTile(
                    title: const Text('Save execution logs'),
                    subtitle: const Text(
                      'Record tap-by-tap details for each script run. '
                      'Disable to save storage and improve performance.',
                    ),
                    value: _logsEnabled,
                    onChanged: _checking ? null : _setLogsEnabled,
                  ),
                ),
              ],
              const Spacer(),
              FilledButton.icon(
                onPressed: _checking ? null : _refresh,
                icon: const Icon(Icons.refresh),
                label: Text(ready ? 'Continue' : 'Check again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    required this.title,
    required this.subtitle,
    required this.done,
    required this.onAction,
    required this.actionLabel,
  });

  final String title;
  final String subtitle;
  final bool done;
  final VoidCallback onAction;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              done ? Icons.check_circle : Icons.radio_button_unchecked,
              color: done ? Colors.green : theme.colorScheme.outline,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}
