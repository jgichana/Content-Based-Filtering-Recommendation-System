import 'package:intl/intl.dart';

class ChildProfile {
  const ChildProfile({
    required this.id,
    required this.name,
    required this.birthDate,
    required this.ageInMonths,
    required this.interests,
  });

  final int id;
  final String name;
  final DateTime birthDate;
  final int ageInMonths;
  final List<String> interests;

  factory ChildProfile.fromJson(Map<String, dynamic> json) => ChildProfile(
        id: json['child_id'] as int,
        name: json['name'] as String,
        birthDate: DateTime.parse(json['birth_date'] as String),
        ageInMonths: json['age_in_months'] as int,
        interests: List<String>.from(json['interests'] as List? ?? const []),
      );
}

/// The editable part of a child profile: what the create/edit form sends.
class ChildDraft {
  const ChildDraft({
    required this.name,
    required this.birthDate,
    required this.interests,
  });

  final String name;
  final DateTime birthDate;
  final List<String> interests;

  Map<String, dynamic> toJson() => {
        'name': name,
        'birth_date': DateFormat('yyyy-MM-dd').format(birthDate),
        'interests': interests,
      };
}
