import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/lan_server.dart';

/// Settings card for phone access over the home network.
class LanSettingsCard extends StatefulWidget {
  const LanSettingsCard({super.key});

  @override
  State<LanSettingsCard> createState() => _LanSettingsCardState();
}

class _LanSettingsCardState extends State<LanSettingsCard> {
  LanSettings? _settings;
  final _pinCtrl = TextEditingController();
  final _portCtrl = TextEditingController();
  String? _formError;

  @override
  void initState() {
    super.initState();
    LanSettings.load().then((s) {
      if (!mounted) return;
      setState(() {
        _settings = s;
        _pinCtrl.text = s.pin;
        _portCtrl.text = '${s.port}';
      });
    });
  }

  @override
  void dispose() {
    _pinCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  /// Saves the form; (re)starts the server when [enabled].
  Future<void> _apply({required bool enabled}) async {
    final pin = _pinCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text.trim());
    if (enabled && pin.length < 4) {
      setState(() => _formError = 'Set a PIN of at least 4 characters first.');
      return;
    }
    // port + 1 is used for the secure (HTTPS) server
    if (port == null || port < 1024 || port > 65534) {
      setState(() => _formError = 'Port must be between 1024 and 65534.');
      return;
    }
    final s = _settings!.copyWith(enabled: enabled, pin: pin, port: port);
    await s.save();
    setState(() { _settings = s; _formError = null; });
    if (enabled) {
      await LanServer.instance.start(context.read<AppState>(), s);
    } else {
      await LanServer.instance.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _settings;
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: s == null
            ? const SizedBox(height: 40)
            : ValueListenableBuilder<LanServerStatus>(
                valueListenable: LanServer.instance.status,
                builder: (ctx, status, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text('Phone access (Wi-Fi)', style: theme.textTheme.titleMedium),
                      const Spacer(),
                      Switch(value: s.enabled, onChanged: (v) => _apply(enabled: v)),
                    ]),
                    Text(
                      'Browse and stream the library from your phone on the same Wi-Fi. '
                      'Only devices on your home network can connect, and they need the PIN. '
                      'Runs while the app is open.',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      SizedBox(
                        width: 160,
                        child: TextField(
                          controller: _pinCtrl,
                          decoration: const InputDecoration(labelText: 'PIN', border: OutlineInputBorder(), isDense: true),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 110,
                        child: TextField(
                          controller: _portCtrl,
                          decoration: const InputDecoration(labelText: 'Port', border: OutlineInputBorder(), isDense: true),
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (s.enabled)
                        OutlinedButton(onPressed: () => _apply(enabled: true), child: const Text('Apply')),
                    ]),
                    if (_formError != null) ...[
                      const SizedBox(height: 8),
                      Text(_formError!, style: TextStyle(color: theme.colorScheme.error)),
                    ],
                    if (status.error != null) ...[
                      const SizedBox(height: 8),
                      Text(status.error!, style: TextStyle(color: theme.colorScheme.error)),
                    ],
                    if (status.running) ...[
                      const SizedBox(height: 12),
                      Text('Open on your phone:', style: theme.textTheme.bodyMedium),
                      const SizedBox(height: 4),
                      if (status.urls.isEmpty)
                        Text('No home network address found. Is the PC connected?', style: theme.textTheme.bodySmall),
                      for (final url in status.urls) _UrlRow(url: url),
                      if (status.secureUrls.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text('Secure address, for VR head tracking (needs one-time phone setup):',
                            style: theme.textTheme.bodyMedium),
                        _UrlRow(url: status.secureUrls.first),
                        if (status.urls.isNotEmpty) ...[
                          Text('Phone setup page:', style: theme.textTheme.bodyMedium),
                          _UrlRow(url: '${status.urls.first}/setup'),
                        ],
                      ],
                      const SizedBox(height: 4),
                      Text(
                        'If the phone can\'t connect, allow ports ${s.port} and ${s.port + 1} in Windows Firewall.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}

class _UrlRow extends StatelessWidget {
  final String url;
  const _UrlRow({required this.url});

  @override
  Widget build(BuildContext context) => Row(children: [
        SelectableText(url, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontFamily: 'monospace')),
        IconButton(
          icon: const Icon(Icons.copy, size: 18),
          tooltip: 'Copy',
          onPressed: () => Clipboard.setData(ClipboardData(text: url)),
        ),
      ]);
}
