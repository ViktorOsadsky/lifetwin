import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../ui/theme.dart';

/// Opens a source link. Tests replace it; the default opens the browser.
typedef OpenUrl = Future<void> Function(Uri url);

Future<void> defaultOpenUrl(Uri url) async {
  await launchUrl(url, mode: LaunchMode.externalApplication);
}

/// An underlined source link with an "opens a website" icon ("CDC: Quitting smoking"). The person
/// taps it; it is its own 48pt target, never the same tap as anything else.
class SourceLink extends StatelessWidget {
  const SourceLink({super.key, required this.label, required this.url, this.open = defaultOpenUrl});

  final String label;
  final String url;
  final OpenUrl open;

  /// The site's short name for a source: "CDC" for cdc.gov, else the host.
  static String siteName(String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    return host.endsWith('cdc.gov') ? 'CDC' : (host.isEmpty ? 'Source' : host.replaceFirst('www.', ''));
  }

  @override
  Widget build(BuildContext context) {
    void tap() => open(Uri.parse(url));
    return Semantics(
      container: true,
      link: true,
      label: 'Source: $label, opens ${Uri.tryParse(url)?.host ?? 'a website'}',
      excludeSemantics: true,
      onTap: tap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: tap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.open_in_new_rounded, size: 22, color: LtColors.ink),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: LtText.body(weight: FontWeight.w700)
                      .copyWith(decoration: TextDecoration.underline, decorationThickness: 2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
