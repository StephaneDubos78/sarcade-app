import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/version.dart';
import '../../l10n/strings.dart';
import '../basemaps/basemap_models.dart';
import '../basemaps/basemap_sheet.dart' show basemapNotices;
import 'notifications_panel.dart' show VersionStatus;
import '../../ui/link_status.dart';

class SarcadeAboutPage extends StatelessWidget {
  const SarcadeAboutPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: LinkedAppBar(title: Text(S.t('about.title'))),
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
        // SARCADE logo above the name, version and publisher, adapted to the
        // theme (card « Paramètres › À propos, logo SARCADE », 30 Oct 2026, 13 h 27).
        // Aligned on the left with the title and the text (revue n° 67).
        Align(alignment: Alignment.centerLeft, child: Image.asset(
          Theme.of(context).brightness == Brightness.dark ? 'assets/logo/sarcade-logo-dark.png' : 'assets/logo/sarcade-logo-light.png',
          height: 96, semanticLabel: 'SARCADE',
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        )),
        const SizedBox(height: 12),
        Text('SARCADE', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(S.t('about.description')),
        const SizedBox(height: 16),
        // Version, build and publisher copied in one go (29 Oct 2026).
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SelectableText(S.t('about.version', {'version': appVersion})),
            if (appBuild.isNotEmpty) SelectableText(S.t('about.build', {'build': appBuild})),
            const SizedBox(height: 8),
            Text(S.t('about.publisher')),
          ])),
          IconButton(
            tooltip: S.t('common.copy'),
            icon: const Icon(Icons.copy_outlined),
            onPressed: () async {
              final text = [
                S.t('about.version', {'version': appVersion}),
                if (appBuild.isNotEmpty) S.t('about.build', {'build': appBuild}),
                S.t('about.publisher'),
              ].join('\n');
              await Clipboard.setData(ClipboardData(text: text));
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.t('common.copied'))));
            },
          ),
        ]),
        if (VersionStatus.shown) const Padding(padding: EdgeInsets.only(top: 12), child: VersionStatus()),
        const Divider(height: 32),
        _link(context, Icons.language, 'about.website', 'https://www.sdubos.com/'),
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
        // Licence notices of the base maps, also behind the ⓘ of the map
        // (card « Panneau Fond de carte », 30 Oct 2026, 1 h 35).
        ListTile(
          leading: const Icon(Icons.map_outlined),
          title: Text(S.t('about.mapNotices')),
          subtitle: Text(basemapNotices(builtInBasemaps).join('\n')),
        ),
      ]);
}
