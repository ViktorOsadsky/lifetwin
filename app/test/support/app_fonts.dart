import 'dart:io';

import 'package:flutter/services.dart';

/// The bundled fonts, so widths in widget tests are the real ones (the default test font is much wider).
Future<void> loadAppFonts() async {
  for (final (family, files) in [
    (
      'Atkinson Hyperlegible',
      ['atkinson_hyperlegible/AtkinsonHyperlegible-Regular.ttf', 'atkinson_hyperlegible/AtkinsonHyperlegible-Bold.ttf'],
    ),
    ('Fredoka', ['fredoka/Fredoka-Variable.ttf']),
  ]) {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(Future.value(ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync())));
    }
    await loader.load();
  }
}
