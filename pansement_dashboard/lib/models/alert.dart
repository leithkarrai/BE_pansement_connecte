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
    // Si la chaîne contient des caractères mal encodés, essayer de les corriger
    try {
      // Essayer de décoder en UTF-8 si c'est une liste de bytes
      if (str.contains('??')) {
        // Les caractères mal encodés apparaissent souvent comme '??'
        // On ne peut pas les récupérer, mais on peut au moins s'assurer que le reste est correct
        return str;
      }
      return str;
    } catch (e) {
      return str;
    }
  }

  factory Alert.fromJson(Map<String, dynamic> json) {
    return Alert(
      id: json['id'].toString(),
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
      triggeredAt: DateTime.parse(json['triggered_at']),
      acknowledgedAt: json['acknowledged_at'] != null
          ? DateTime.tryParse(json['acknowledged_at'].toString())
          : null,
      acknowledgedBy: json['acknowledged_by']?.toString(),
      resolvedAt: json['resolved_at'] != null
          ? DateTime.tryParse(json['resolved_at'].toString())
          : null,
      resolvedBy: json['resolved_by']?.toString(),
      resolutionNote: json['resolution_note']?.toString(),
      notificationSent: json['notification_sent'] ?? false,
      notificationMethod: json['notification_method']?.toString(),
      notificationSentAt: json['notification_sent_at'] != null
          ? DateTime.tryParse(json['notification_sent_at'].toString())
          : null,
    );
  }

  bool get isAcknowledged => acknowledgedAt != null;
  bool get isResolved => resolvedAt != null;
  bool get isCritical => severity == 'critical';
  bool get isWarning => severity == 'warning';
  bool get isInfo => severity == 'info';
}
