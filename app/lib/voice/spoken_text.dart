final _parenthetical = RegExp(r'\s*\([^()]*\)');
final _semicolon = RegExp(r'\s*;\s*(\S?)');
final _spaces = RegExp(r'\s{2,}');

/// The words the mascot says out loud for a line shown on screen.
///
/// Conversions in parentheses, like "(about 178 cm)", are for reading only:
/// spoken, they interrupt the sentence. A semicolon becomes a sentence break
/// so the voice pauses there. The screen always shows the full line.
String spokenText(String line) {
  var s = line;
  for (var before = ''; before != s;) {
    before = s;
    s = s.replaceAll(_parenthetical, '');
  }
  s = s.replaceAllMapped(_semicolon, (m) => '. ${m[1]!.toUpperCase()}');
  return s.replaceAll(_spaces, ' ').trim();
}
