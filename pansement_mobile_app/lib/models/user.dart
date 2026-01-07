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

  // Champs spécifiques aux médecins
  final String? rppsNumber;
  final String? specialty;
  final String? establishment;

  // Champs spécifiques aux patients
  final DateTime? dateOfBirth;
  final String? address;

  // Date de création du compte
  final DateTime? createdAt;

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
    this.rppsNumber,
    this.specialty,
    this.establishment,
    this.dateOfBirth,
    this.address,
    this.createdAt,
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
      rppsNumber: json['rpps_number'],
      specialty: json['specialty'],
      establishment: json['establishment'],
      dateOfBirth: json['date_of_birth'] != null
          ? DateTime.parse(json['date_of_birth'])
          : null,
      address: json['address'],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
    );
  }

  String get fullName => '$firstName $lastName';

  // Getters pour faciliter l'affichage
  bool get isPatient => role.toLowerCase() == 'patient';
  bool get isMedecin => role.toLowerCase() == 'medecin';
  bool get isAdmin => role.toLowerCase() == 'admin';
}
