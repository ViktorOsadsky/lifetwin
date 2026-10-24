const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "Today", "Yesterday" or "Tue 21 Oct".
String formatDay(DateTime d, DateTime now) {
  final a = DateTime.utc(d.year, d.month, d.day);
  final b = DateTime.utc(now.year, now.month, now.day);
  final ago = b.difference(a).inDays;
  if (ago == 0) return 'Today';
  if (ago == 1) return 'Yesterday';
  return '${_days[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';
}

/// "35 min" or "1 h 5 min".
String formatMinutes(int m) {
  if (m < 60) return '$m min';
  final h = m ~/ 60;
  final r = m % 60;
  return r == 0 ? '$h h' : '$h h $r min';
}
