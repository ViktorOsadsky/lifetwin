import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/voice/spoken_text.dart';

void main() {
  test('parenthetical conversions are not read aloud', () {
    expect(
      spokenText('I heard you are 5 feet 10 inches (about 178 cm) tall. Is that right?'),
      'I heard you are 5 feet 10 inches tall. Is that right?',
    );
    expect(spokenText('Weight: 160 pounds (about 73 kg).'), 'Weight: 160 pounds.');
    expect(spokenText('(Optional) How tall are you?'), 'How tall are you?');
    expect(spokenText('Nested (a (b) c) end'), 'Nested end');
  });

  test('a semicolon becomes a sentence break', () {
    expect(spokenText("That's okay; I won't fill it in."), "That's okay. I won't fill it in.");
    expect(spokenText('Done;'), 'Done.');
    expect(spokenText('one ; two'), 'one. Two');
  });

  test('plain lines are unchanged', () {
    expect(spokenText('How old are you?'), 'How old are you?');
    expect(spokenText('Blood pressure: 130 over 85.'), 'Blood pressure: 130 over 85.');
    expect(spokenText('An unmatched ( bracket stays'), 'An unmatched ( bracket stays');
  });
}
