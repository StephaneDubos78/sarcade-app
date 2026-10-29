import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/version.dart';
import '../../l10n/strings.dart';

class SarcadeAboutPage extends StatelessWidget {
  const SarcadeAboutPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(S.t('about.title'))),
    body: SafeArea(child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: ListView(padding: const EdgeInsets.all(20), children: const [SarcadeAboutContent()]),
    ))),
  );
}

/// Content of « À propos », shown in its page and in the Settings tab.
class SarcadeAboutContent extends StatelessWidget {
  const SarcadeAboutContent({super.key});

  Future<void> _open(BuildContext context, String url) async {
    bool opened;
    try {
      opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.t('about.linkFailed'))));
    }
  }

  Widget _link(BuildContext context, IconData icon, String label, String url) => ListTile(
    leading: Icon(icon),
    title: Text(S.t(label)),
    trailing: const Icon(Icons.open_in_new),
    onTap: () => _open(context, url),
  );

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('SARCADE', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(S.t('about.description')),
        const SizedBox(height: 16),
        SelectableText(S.t('about.version', {'version': appVersion})),
        if (appBuild.isNotEmpty) SelectableText(S.t('about.build', {'build': appBuild})),
        const SizedBox(height: 8),
        Text(S.t('about.publisher')),
        const Divider(height: 32),
        _link(context, Icons.language, 'about.website', 'https://sarcade.org'),
        _link(context, Icons.code, 'about.source', 'https://github.com/sdubos-consulting/sarcade-app'),
        _link(context, Icons.feedback_outlined, 'about.feedback', 'https://github.com/sdubos-consulting/sarcade-app/issues'),
        _link(context, Icons.privacy_tip_outlined, 'about.privacy', 'https://sdubos-consulting.github.io/sarcade-app/confidentialite/'),
        _link(context, Icons.description_outlined, 'about.license', 'https://github.com/sdubos-consulting/sarcade-app/blob/main/LICENSE'),
        ListTile(
          leading: const Icon(Icons.favorite_outline),
          title: Text(S.t('about.credits')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showLicensePage(context: context, applicationName: 'SARCADE', applicationVersion: appVersion),
        ),
      ]);
}
