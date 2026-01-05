/// Modèle utilisateur
class User {
  final String id;
  final String email;
  final String firstName;
  final String lastName;
  final String role;
  final String? phone;
  final String? bloodType;
  final bool isActive;
  final bool isVerified;
  final bool twoFactorEnabled;

  User({
    required this.id,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.role,
    this.phone,
    this.bloodType,
    this.isActive = true,
    this.isVerified = false,
    this.twoFactorEnabled = false,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      email: json['email'],
      firstName: json['first_name'],
      lastName: json['last_name'],
      role: json['role'],
      phone: json['phone'],
      bloodType: json['blood_type'],
      isActive: json['is_active'] ?? true,
      isVerified: json['is_verified'] ?? false,
      twoFactorEnabled: json['two_factor_enabled'] ?? false,
    );
  }

  String get fullName => '$firstName $lastName';
}
