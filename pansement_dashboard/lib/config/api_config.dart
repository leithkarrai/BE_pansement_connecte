/// Configuration de l'API backend
class ApiConfig {
  // ⚠️ URL de votre backend FastAPI
  static const String baseUrl = 'http://localhost:8000/api/v1';

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
}
