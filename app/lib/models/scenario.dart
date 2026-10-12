class Scenario {
  const Scenario({
    required this.code,
    required this.name,
    required this.description,
    required this.expected,
  });

  final String code;
  final String name;
  final String description;
  final String expected;

  factory Scenario.fromJson(Map<String, dynamic> json) => Scenario(
        code: json['code'] as String,
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        expected: json['expected'] as String? ?? '',
      );
}
