/// Configuration de l'API backend
class ApiConfig {
  // ⚠️ POUR MOBILE :
  // - Android Emulator : http://10.0.2.2:8000/api/v1
  // - iOS Simulator : http://localhost:8000/api/v1
  // - Device physique : http://192.168.1.200:8000/api/v1 (IP de votre PC)

  static const String baseUrl =
      'http://192.168.1.200:8000/api/v1'; // Device physique - Changez cette IP si nécessaire

  // Auth endpoints
  static const String login = '/auth/login';
  static const String register = '/auth/register';
  static const String me = '/auth/me';
  static const String refresh = '/auth/refresh';
  static const String forgotPassword = '/auth/forgot-password';
  static const String resetPassword = '/auth/reset-password';
  static const String verifyEmail = '/auth/verify-email';
  static const String changePassword = '/auth/change-password';

  // Data endpoints
  static const String users = '/users';
  static const String devices = '/devices';
  static const String measurements = '/measurements';
  static const String alerts = '/alerts';

  // Config
  static const Duration timeout = Duration(seconds: 30);

  // BLE Configuration
  static const String deviceNamePrefix =
      'PANS'; // Pansements commencent par "PANS"

  // GATT Services & Characteristics UUIDs
  // ⚠️ Ces UUIDs doivent correspondre à ceux programmés dans l'ESP32
  static const String serviceUuid = '12345678-1234-1234-1234-123456789012';
  static const String temperatureCharUuid =
      '12345678-1234-1234-1234-123456789013';
  static const String humidityCharUuid = '12345678-1234-1234-1234-123456789014';
  static const String phCharUuid = '12345678-1234-1234-1234-123456789015';
}
