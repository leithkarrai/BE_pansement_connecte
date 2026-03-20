/// Modèle Alerte
class Alert {
  final String id;
  final String patientId;
  final String deviceId;
  final String? measurementId;
  final String
      alertType; // temperature, impedance, orp, infection, battery, device_error
  final String severity; // info, warning, critical
  final String title;
  final String message;
  final double? currentValue;
  final double? thresholdValue;
  final DateTime triggeredAt;
  final DateTime? acknowledgedAt;
  final String? acknowledgedBy;
  /// Vu par un médecin (acquittement séparé du rôle admin).
  final DateTime? acknowledgedByMedecinAt;
  /// Vu par l'admin (acquittement séparé du rôle médecin).
  final DateTime? acknowledgedByAdminAt;
  final DateTime? resolvedAt;
  final String? resolvedBy;
  final String? resolutionNote;
  final bool notificationSent;
  final String? notificationMethod;
  final DateTime? notificationSentAt;

  Alert({
    required this.id,
    required this.patientId,
    required this.deviceId,
    this.measurementId,
    required this.alertType,
    required this.severity,
    required this.title,
    required this.message,
    this.currentValue,
    this.thresholdValue,
    required this.triggeredAt,
    this.acknowledgedAt,
    this.acknowledgedBy,
    this.acknowledgedByMedecinAt,
    this.acknowledgedByAdminAt,
    this.resolvedAt,
    this.resolvedBy,
    this.resolutionNote,
    required this.notificationSent,
    this.notificationMethod,
    this.notificationSentAt,
  });

  // Helper pour nettoyer les chaînes de caractères et corriger l'encodage
  static String _cleanString(dynamic value) {
    if (value == null) return '';
    String str = value.toString();
    try {
      if (str.contains('??')) return str;
      return str;
    } catch (e) {
      return str;
    }
  }

  /// Parse une date depuis le JSON (chaîne ISO ou null).
  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    final s = value.toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  factory Alert.fromJson(Map<String, dynamic> json) {
    final rawId = json['id']?.toString().trim() ?? '';
    final id = (rawId.isEmpty || rawId == 'null') ? '' : rawId;
    return Alert(
      id: id,
      patientId: json['patient_id'].toString(),
      deviceId: json['device_id'].toString(),
      measurementId: json['measurement_id']?.toString(),
      alertType: _cleanString(json['alert_type'] ?? 'unknown'),
      severity: _cleanString(json['severity'] ?? 'info'),
      title: _cleanString(json['title'] ?? ''),
      message: _cleanString(json['message'] ?? ''),
      currentValue: json['current_value'] != null
          ? double.tryParse(json['current_value'].toString())
          : null,
      thresholdValue: json['threshold_value'] != null
          ? double.tryParse(json['threshold_value'].toString())
          : null,
      triggeredAt: DateTime.tryParse(json['triggered_at'].toString()) ?? DateTime.now(),
      acknowledgedAt: _parseDate(json['acknowledged_at']),
      acknowledgedBy: json['acknowledged_by']?.toString(),
      acknowledgedByMedecinAt: _parseDate(json['acknowledged_by_medecin_at']),
      acknowledgedByAdminAt: _parseDate(json['acknowledged_by_admin_at']),
      resolvedAt: _parseDate(json['resolved_at']),
      resolvedBy: json['resolved_by']?.toString(),
      resolutionNote: json['resolution_note']?.toString(),
      notificationSent: json['notification_sent'] ?? false,
      notificationMethod: json['notification_method']?.toString(),
      notificationSentAt: _parseDate(json['notification_sent_at']),
    );
  }

  /// Considère l'alerte comme acquittée pour le rôle donné.
  /// Chaque rôle a son propre acquittement : médecin voit barré seulement s'il a acquitté, idem pour l'admin.
  bool isAcknowledgedForRole(String? role) {
    if (role == null) return acknowledgedAt != null;
    switch (role.toLowerCase()) {
      case 'medecin':
        return acknowledgedByMedecinAt != null;
      case 'admin':
        return acknowledgedByAdminAt != null;
      default:
        return acknowledgedAt != null;
    }
  }

  /// Pour compatibilité : vrai si au moins un acquittement (patient = acknowledgedAt).
  bool get isAcknowledged => acknowledgedAt != null;
  bool get isResolved => resolvedAt != null;
  bool get isCritical => severity == 'critical';
  bool get isWarning => severity == 'warning';
  bool get isInfo => severity == 'info';
}
