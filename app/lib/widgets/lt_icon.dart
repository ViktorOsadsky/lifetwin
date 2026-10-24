import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// One original stroke icon family: 24 grid, 2 px stroke, round caps/joins.
enum LtIcons {
  room(
    '<path d="M4 11.5 12 5l8 6.5"/><path d="M6 10.5V19h12v-8.5"/><path d="M10 19v-5h4v5"/>',
  ),
  plan(
    '<rect x="5" y="4" width="14" height="16" rx="3"/><path d="M9 9.5l1.5 1.5L14 7.5"/><path d="M9 15h6"/>',
  ),
  activity('<path d="M3 13h4l2.5-6 4 11 2.5-5H21"/>'),
  walk(
    '<circle cx="13" cy="5" r="1.8"/><path d="M12 9l-2.5 4 2.5 2.5V20"/><path d="M12 9l3 2.5 3 .5"/><path d="M9.5 13l-3 1.5"/>',
  ),
  run(
    '<circle cx="14" cy="5" r="1.8"/><path d="M13 9l-3 3.5 3 2 1 4.5"/><path d="M13 9l4 1 2 3"/><path d="M10 12.5l-4 .5"/>',
  ),
  cycle(
    '<circle cx="6" cy="16" r="3.5"/><circle cx="18" cy="16" r="3.5"/><path d="M6 16l4-8h5l3 8"/><path d="M10 8l3 8"/>',
  ),
  swim(
    '<circle cx="16" cy="6" r="1.8"/><path d="M5 12l5-2 4 2.5"/><path d="M3 17c1.5 1 3 1 4.5 0s3-1 4.5 0 3 1 4.5 0 3-1 4.5 0"/>',
  ),
  strength('<path d="M4 9v6M7 7v10M17 7v10M20 9v6M7 12h10"/>'),
  other('<circle cx="12" cy="12" r="8"/><path d="M12 8v4l2.5 2"/>'),
  plus('<path d="M12 5v14M5 12h14"/>'),
  minus('<path d="M5 12h14"/>'),
  close('<path d="M6 6l12 12M18 6 6 18"/>'),
  check('<path d="M5 12.5l4.5 4.5L19 7.5"/>'),
  chevronRight('<path d="M9.5 6l6 6-6 6"/>'),
  chevronLeft('<path d="M14.5 6l-6 6 6 6"/>'),
  arrowUp('<path d="M12 19V6M6.5 11.5 12 6l5.5 5.5"/>'),
  arrowDown('<path d="M12 5v13M6.5 12.5 12 18l5.5-5.5"/>'),
  equal('<path d="M6 9.5h12M6 14.5h12"/>'),
  heart(
    '<path d="M12 19.5S4.5 15 4.5 9.5A3.8 3.8 0 0 1 12 8a3.8 3.8 0 0 1 7.5 1.5c0 5.5-7.5 10-7.5 10z"/>',
  ),
  mic(
    '<rect x="9" y="4" width="6" height="10" rx="3"/><path d="M6 11.5a6 6 0 0 0 12 0M12 17.5V20"/>',
  ),
  send('<path d="M5 12h13M13 6.5 18.5 12 13 17.5"/>'),
  lock(
    '<rect x="6" y="11" width="12" height="9" rx="3"/><path d="M9 11V8.5a3 3 0 0 1 6 0V11"/>',
  ),
  info('<circle cx="12" cy="12" r="8.5"/><path d="M12 11v5M12 8v.2"/>'),
  sparkle('<path d="M12 4v5M12 15v5M4 12h5M15 12h5"/>'),
  calendar(
    '<rect x="4.5" y="6" width="15" height="13.5" rx="3"/><path d="M8.5 4v4M15.5 4v4M4.5 10.5h15"/>',
  ),
  flask(
    '<path d="M10 4h4M11 4v5l-5 8.5A2 2 0 0 0 7.7 20.5h8.6a2 2 0 0 0 1.7-3L13 9V4"/>',
  ),
  quiz(
    '<rect x="5" y="4" width="14" height="16" rx="3"/><path d="M9.5 9.5a2.5 2.5 0 1 1 3.5 2.3c-.7.4-1 .9-1 1.7M12 16.5v.2"/>',
  ),
  mirror(
    '<ellipse cx="12" cy="10" rx="5.5" ry="6.5"/><path d="M12 16.5V20M9 20h6"/>',
  ),
  moon('<path d="M18.5 14.6A7 7 0 0 1 9.4 5.5a7.2 7.2 0 1 0 9.1 9.1z"/>'),
  sneaker(
    '<path d="M3.5 9v8h17v-1.3a2 2 0 0 0-1.6-2l-4.4-.9-3.2-3-1.8 1.4H7.6L6 9z"/><path d="M10.6 12.2l1.2-1M12.8 13.4l1.2-1"/>',
  ),
  glass(
    '<path d="M7 5h10l-1.3 12.8a2 2 0 0 1-2 1.7h-3.4a2 2 0 0 1-2-1.7z"/><path d="M7.7 10.5h8.6"/>',
  ),
  leaf(
    '<path d="M5.5 18.5C5.5 11 10 6 19 5.5c0 8.5-4.8 13-11.5 13z"/><path d="M5.5 18.5l6.5-6.5"/>',
  ),
  question(
    '<circle cx="12" cy="12" r="8.5"/><path d="M9.8 9.7a2.3 2.3 0 1 1 3.2 2.1c-.6.3-1 .8-1 1.5M12 16.2v.2"/>',
  ),
  smile(
    '<circle cx="12" cy="12" r="8.5"/><path d="M8.8 13.6a4 4 0 0 0 6.4 0M9.5 9.8v.2M14.5 9.8v.2"/>',
  ),
  ball(
    '<circle cx="12" cy="11" r="7"/><path d="M8 20h8M9 15.5 8 20M15 15.5 16 20"/>',
  );

  const LtIcons(this.body);
  final String body;

  String get svg =>
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" '
      'stroke="currentColor" stroke-width="2" stroke-linecap="round" '
      'stroke-linejoin="round">$body</svg>';
}

class LtIcon extends StatelessWidget {
  const LtIcon(this.icon, {super.key, required this.color, this.size = 24});

  final LtIcons icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(
      icon.svg,
      width: size,
      height: size,
      theme: SvgTheme(currentColor: color),
      excludeFromSemantics: true,
    );
  }
}
