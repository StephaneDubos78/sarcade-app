import 'package:flutter/material.dart';
import '../../l10n/strings.dart';

/// Read-only tools for the active operation. Opening them does not save settings.
class DiagnosticsPage extends StatelessWidget {
  final String eventId;
  final VoidCallback onOpenLogbook;

  const DiagnosticsPage({super.key, required this.eventId, required this.onOpenLogbook});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(S.t('settings.diagnostics'))),
    body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
      Text(S.t('diagnostics.description')),
      const SizedBox(height: 16),
      ListTile(
        leading: const Icon(Icons.receipt_long),
        title: Text(S.t('map.logbook')),
        subtitle: Text(S.t('diagnostics.activeEvent', {'event': eventId})),
        trailing: const Icon(Icons.chevron_right),
        onTap: onOpenLogbook,
      ),
    ])),
  );
}
