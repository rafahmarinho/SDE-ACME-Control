import 'json.dart';

class TrendSample {
  const TrendSample({required this.tag, required this.ts, required this.value});

  final String tag;
  final DateTime ts;
  final double value;

  factory TrendSample.fromJson(Map<String, dynamic> json) => TrendSample(
        tag: json['tag'] as String,
        ts: toDate(json['ts']) ?? DateTime.now(),
        value: toDouble(json['value']),
      );
}

class TrendTagInfo {
  const TrendTagInfo(this.tag, this.label, this.unit, this.colorIndex);

  final String tag;
  final String label;
  final String unit;
  final int colorIndex;
}

const trendTags = <TrendTagInfo>[
  TrendTagInfo('LT1', 'Raw water level', '%', 0),
  TrendTagInfo('LT2', 'Treated water level', '%', 1),
  TrendTagInfo('FT1', 'Intake flow', 'm³/h', 2),
  TrendTagInfo('FT2', 'Transfer flow', 'm³/h', 3),
  TrendTagInfo('FT3', 'Distribution flow', 'm³/h', 4),
  TrendTagInfo('PT1', 'Intake pressure', 'bar', 5),
  TrendTagInfo('PT2', 'Transfer pressure', 'bar', 6),
  TrendTagInfo('PT3', 'Network pressure', 'bar', 7),
  TrendTagInfo('TU1', 'Turbidity', 'NTU', 8),
  TrendTagInfo('CL1', 'Chlorine residual', 'mg/L', 9),
];
