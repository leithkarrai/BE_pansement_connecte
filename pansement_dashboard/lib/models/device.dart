/// Modèle dispositif
class Device {
  final String id;
  final String serialNumber;
  final String model;
  final String? firmwareVersion;
  final int? batteryLevel;
  final String status;
  final String? patientId;
  final String? patientName;
  final DateTime? assignedAt;

  Device({
    required this.id,
    required this.serialNumber,
    required this.model,
    this.firmwareVersion,
    this.batteryLevel,
    required this.status,
    this.patientId,
    this.patientName,
    this.assignedAt,
  });

  factory Device.fromJson(Map<String, dynamic> json) {
    return Device(
      id: json['id'].toString(),
      serialNumber: json['serial_number']?.toString() ?? '',
      model: json['model']?.toString() ?? 'Unknown',
      firmwareVersion: json['firmware_version']?.toString(),
      // ✅ CORRECTION : Convertir en int de manière sûre
      batteryLevel: json['battery_level'] != null
          ? (json['battery_level'] is int
              ? json['battery_level']
              : int.tryParse(json['battery_level'].toString()))
          : null,
      status: json['status']?.toString() ?? 'inactive',
      patientId: json['patient_id']?.toString(),
      patientName: json['patient_name']?.toString(),
      assignedAt: json['assigned_at'] != null
          ? DateTime.tryParse(json['assigned_at'].toString())
          : null,
    );
  }
}
