/// Every word on the Experiment screens in one place (design/canvas/project/Y-*.dc.html), so
/// the designer's copy changes land in one file.
abstract final class ExperimentCopy {
  static const title = 'Experiment';
  static const heroTitle = 'Your what-if twin vs today';
  static const subtitle = 'Modeled difference between profiles';
  static const stillAlive = 'Of 100 people like you, still alive in 5 years';
  static const linked = 'Linked, not proven.';
  static const whatIfOnly = 'What-if only.';
  static const why = 'Why?';
  static const whySheet =
      "This compares people in a US health survey with answers like today's you and like your what-if "
      'twin. It shows a link, not proof that a change causes it. Your real answers stay the same. '
      'Not a promise, not a date.';
  static const tryAChange = 'Try a change';
  static const sideBySide = 'See side by side';
  static const tryOther = 'Try other changes';
  static const useInWhatIf = 'Use in my what-if';
  static const justThisChange = 'Just this change';
  static const inThisWhatIf = 'In this what-if';
  static const seeYears = 'See years 1 to 5';
  static const seeNumbers = 'See the numbers';
  static const backToChanges = 'Back to my changes';

  // Headlines (the rounding rule, y_gen.py header).
  static String more(int n) => 'About $n more in 100';
  static String fewer(int n) => 'About $n fewer in 100';
  static const tiny = 'Less than 1 more in 100';

  /// The headline beside a Rough guide badge (Y-17), which leaves less room.
  static const tinyShort = 'Under 1 more in 100';
  static const tinyBox = 'A tiny bit more';
  static const same = 'About the same';
  static const moreThan99 = 'More than 99';
  static String about(int n) => 'About $n';
  static String exactTiny(double d) {
    // From 0.1 points: "About round(10 d) in 1,000"; below that: "Less than 1 in 1,000".
    final text = d >= 0.1 ? 'About ${roundHalfUp(d * 10).toInt()} in 1,000' : 'Less than 1 in 1,000';
    return '$text. Too small for a 100-bear picture.';
  }

  static const pickAChange = 'Pick a change';
  static const noNumber = 'No number';
  static const notCounted = 'Not counted';
  static const tooRare = 'Try a smaller step.';
  static const tooManyHours = 'Too many hours';
  static const tooManyHoursBody = 'Try smaller changes.';
  static const topOfRange = 'is the top';

  // Still learning (Y-8, Y-13).
  static const almostReady = 'Almost ready';
  static const stillLearning = 'Still learning';
  static const firstINeed = 'First, I need:';
  static const onceIKnow = 'Your outlook shows once I know these.';
  static const notSure = 'Not sure? “I don’t know” is fine.';
  static const tellMochi = 'Tell Mochi';
  static String toGo(int n) => '$n to go';
  static String whatIKnow(int n) => 'What I know ($n)';

  // Not available (Y-9, Y-10).
  static const outsideRange = 'Outside my range';
  static const beyondNumbers = 'Beyond my numbers';
  static const ageRange = 'My numbers cover ages 30 to 85.';
  static const rareAnswers = 'Rare answers';
  static const tooRareToEstimate = 'Too rare to estimate';
  static const rareBody = 'More exercise than almost anyone in the health survey I learned from.';
  static const change = 'Change';
  static const backToRoom = 'Back to room';
  static const goingWell = 'Going well';
  static const roomToGrow = 'Room to grow';

  // Weight (Y-6): an info card, never a lever.
  static const aboutWeight = 'About weight';
  static const cdcGuidance = 'CDC guidance';
  static const weightClue = 'Weight is one clue';
  static const weightBody = 'Not a diagnosis or a goal.';
  static const weightCdc = 'CDC: Healthy weight';
  static const whyNot = 'Why not?';
  static const askMochi = 'Ask Mochi about it';
  static const weightNotWhatIf = 'Not a what-if';
  static const weightNotWhatIfBody = "My numbers can't show weight changes fairly.";
  static const weightWhyNot =
      "Height and weight are part of today's number, but the survey can't show whether changing weight "
      "helps, so it's left out of what-ifs.";

  // Smoking (Y-7).
  static const smokeNow = 'Smoke now';
  static const quit = 'Quit';
  static const quitline = 'Free help: 1-800-QUIT-NOW';
  static const quitlineNumber = '18007848669';

  // Speech bubbles.
  static const bubbleBase = 'Try a change!';
  static const bubbleTiny = "You're already doing great!";
  static const bubbleBig = 'Small steps count!';

  static const roughGuide = 'Rough guide';

  /// Rounds half up (away from zero on ties), so 0.05 gives 0.1 and 89.5 gives 90, as the
  /// design's rule (y_gen.py) does with decimals. The small epsilon undoes binary error.
  static num roundHalfUp(double x, [int digits = 0]) {
    final k = digits == 0 ? 1.0 : (digits == 1 ? 10.0 : 100.0);
    final r = (x.abs() * k + 0.5 + 1e-9).floorToDouble() / k;
    final v = x < 0 ? -r : r;
    return digits == 0 ? v.toInt() : v;
  }

  /// "5½ h", "30 min", "1 h 15 min", "2 h": minutes shown as hours from an hour up.
  static String duration(num minutes) {
    final m = minutes.round();
    if (m < 60) return '$m min';
    final h = m ~/ 60, r = m % 60;
    if (r == 0) return '$h h';
    if (r == 30) return '$h½ h';
    return '$h h $r min';
  }

  /// Hours a night, to the half hour: "6½ h".
  static String hours(num h) {
    final whole = h.floor();
    final half = (h - whole) >= 0.5;
    if (!half) return '$whole h';
    return whole == 0 ? '½ h' : '$whole½ h';
  }
}
