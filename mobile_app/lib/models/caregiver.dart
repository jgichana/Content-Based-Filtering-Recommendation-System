class Caregiver {
  const Caregiver({required this.id, required this.name, this.email});

  final int id;
  final String name;
  final String? email;

  factory Caregiver.fromJson(Map<String, dynamic> json) => Caregiver(
        id: json['caregiver_id'] as int,
        name: json['name'] as String,
        email: json['email'] as String?,
      );

  Map<String, dynamic> toJson() =>
      {'caregiver_id': id, 'name': name, 'email': email};
}

/// What the backend returns from /auth/register, /auth/login and /auth/google.
class AuthSession {
  const AuthSession({required this.accessToken, required this.caregiver});

  final String accessToken;
  final Caregiver caregiver;

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
        accessToken: json['access_token'] as String,
        caregiver:
            Caregiver.fromJson(json['caregiver'] as Map<String, dynamic>),
      );
}
