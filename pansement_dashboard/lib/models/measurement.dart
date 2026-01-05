/// Modèle mesure
class Measurement {
  final String id;
  final String deviceId;
  final String measurementType;
  final double value;
  final String unit;
  final int? qualityScore;
  final DateTime timestamp;
  final String? patientName;

  Measurement({
    required this.id,
    required this.deviceId,
    required this.measurementType,
    required this.value,
    required this.unit,
    this.qualityScore,
    required this.timestamp,
    this.patientName,
  });

  factory Measurement.fromJson(Map<String, dynamic> json) {
    return Measurement(
      id: json['id'].toString(),
      deviceId: json['device_id'].toString(),
      measurementType: json['measurement_type'].toString(),
      value: (json['value'] is num)
          ? json['value'].toDouble()
          : double.tryParse(json['value'].toString()) ?? 0.0,
      unit: json['unit']?.toString() ?? '',
      qualityScore: json['quality_score'] != null
          ? (json['quality_score'] is int
              ? json['quality_score']
              : int.tryParse(json['quality_score'].toString()))
          : null,
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'].toString()) ?? DateTime.now()
          : DateTime.now(),
      patientName: json['patient_name']?.toString(),
    );
  }

  String get typeLabel {
    switch (measurementType) {
      case 'temperature':
        return 'Température';
      case 'humidity':
        return 'Humidité';
      case 'ph':
        return 'pH';
      case 'exudate':
        return 'Exsudat';
      default:
        return measurementType;
    }
  }
}
