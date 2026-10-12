import 'package:intl/intl.dart';

final _dateTime = DateFormat('MMM d, HH:mm');
final _dateTimeSeconds = DateFormat('MMM d, HH:mm:ss');
final _time = DateFormat('HH:mm:ss');
final _timeShort = DateFormat('HH:mm');
final _date = DateFormat('MMM d, yyyy');
final _number = NumberFormat('#,##0.0');

String fmtNum(num? value, {int decimals = 1}) {
  if (value == null) return '--';
  if (decimals == 0) return value.round().toString();
  return value.toStringAsFixed(decimals);
}

String fmtThousands(num? value) => value == null ? '--' : _number.format(value);

String fmtDateTime(DateTime? value) => value == null ? '--' : _dateTime.format(value.toLocal());

String fmtDateTimeSeconds(DateTime? value) => value == null ? '--' : _dateTimeSeconds.format(value.toLocal());

String fmtTime(DateTime? value) => value == null ? '--' : _time.format(value.toLocal());

String fmtTimeShort(DateTime? value) => value == null ? '--' : _timeShort.format(value.toLocal());

String fmtDate(DateTime? value) => value == null ? '--' : _date.format(value.toLocal());

String fmtRelative(DateTime? value, {DateTime? now}) {
  if (value == null) return '--';
  final diff = (now ?? DateTime.now()).difference(value.toLocal());
  if (diff.isNegative) {
    final ahead = -diff;
    if (ahead.inMinutes < 1) return 'in a moment';
    if (ahead.inHours < 1) return 'in ${ahead.inMinutes} min';
    if (ahead.inDays < 1) return 'in ${ahead.inHours} h';
    return 'in ${ahead.inDays} d';
  }
  if (diff.inSeconds < 10) return 'just now';
  if (diff.inMinutes < 1) return '${diff.inSeconds} s ago';
  if (diff.inHours < 1) return '${diff.inMinutes} min ago';
  if (diff.inDays < 1) return '${diff.inHours} h ago';
  if (diff.inDays < 7) return '${diff.inDays} d ago';
  return fmtDate(value);
}

String fmtHours(num? hours) {
  if (hours == null) return '--';
  if (hours < 1) return '${(hours * 60).round()} min';
  return '${hours.toStringAsFixed(hours >= 100 ? 0 : 1)} h';
}

String fmtDuration(Duration d) {
  if (d.inSeconds < 60) return '${d.inSeconds} s';
  if (d.inMinutes < 60) return '${d.inMinutes} min';
  if (d.inHours < 24) {
    final m = d.inMinutes % 60;
    return m == 0 ? '${d.inHours} h' : '${d.inHours} h $m min';
  }
  return '${d.inDays} d ${d.inHours % 24} h';
}

String titleCase(String value) {
  if (value.isEmpty) return value;
  return value
      .split(RegExp(r'[_\s]+'))
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
}
