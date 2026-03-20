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
  final double? freqHz;
  final double? phaseDeg;

  Measurement({
    required this.id,
    required this.deviceId,
    required this.measurementType,
    required this.value,
    required this.unit,
    this.qualityScore,
    required this.timestamp,
    this.patientName,
    this.freqHz,
    this.phaseDeg,
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
      freqHz: _parseOptionalDoubleFromKeys(json, ['freq_hz', 'freqHz', 'freq']),
      phaseDeg: _parseOptionalDoubleFromKeys(json, ['phase_deg', 'phaseDeg', 'phase']),
    );
  }

  /// Parse un double optionnel depuis le JSON (plusieurs clés possibles).
  static double? _parseOptionalDoubleFromKeys(
    Map<String, dynamic> json,
    List<String> keys,
  ) {
    for (final key in keys) {
      final v = json[key];
      if (v == null) continue;
      if (v is num) return v.toDouble();
      final parsed = double.tryParse(v.toString());
      if (parsed != null) return parsed;
    }
    return null;
  }

  String get typeLabel {
    switch (measurementType) {
      case 'adc':
        return 'Valeur ADC';
      case 'temperature':
        return 'Température';
      case 'impedance':
        return 'Impédance';
      default:
        return measurementType;
    }
  }
}
