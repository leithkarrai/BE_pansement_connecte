import 'package:shared_preferences/shared_preferences.dart';

/// Configuration de l'API backend avec support de configuration dynamique
class ApiConfig {
  // Clé pour stocker l'URL du backend dans SharedPreferences
  static const String _backendUrlKey = 'backend_base_url';

  // URL par défaut - IP du PC sur le Wi-Fi (obligatoire pour téléphone réel).
  // 1) Sur le PC : ouvrir CMD → ipconfig → noter "Adresse IPv4" de la carte Wi-Fi.
  // 2) Remplacer par cette IP si tu changes de réseau (ou dans l'app : Paramètres > URL du serveur).
  // Émulateur Android : utiliser http://10.0.2.2:8000/api/v1
  static const String _defaultUrl = 'http://192.168.1.200:8000/api/v1';

  // URL de base - peut être changée dynamiquement (Paramètres > URL du serveur)
  static String _baseUrl = _defaultUrl;

  /// Récupère l'URL de base du backend
  /// Charge depuis SharedPreferences ou utilise l'URL par défaut
  static Future<String> getBaseUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUrl = prefs.getString(_backendUrlKey);
      if (savedUrl != null && savedUrl.isNotEmpty) {
        _baseUrl = savedUrl;
      } else {
        _baseUrl = _defaultUrl;
      }
    } catch (e) {
      _baseUrl = _defaultUrl;
    }
    return _baseUrl;
  }

  /// URL de base (synchrone) - utilise la valeur en cache
  /// ⚠️ Utilisez getBaseUrl() pour charger depuis SharedPreferences
  static String get baseUrl => _baseUrl;

  /// Définit une nouvelle URL de base et la sauvegarde
  static Future<void> setBaseUrl(String url) async {
    try {
      // Valider l'URL
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        throw Exception('URL invalide: doit commencer par http:// ou https://');
      }

      // Enlever le slash final si présent
      url = url.endsWith('/') ? url.substring(0, url.length - 1) : url;

      // Sauvegarder dans SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_backendUrlKey, url);

      // Mettre à jour la valeur en cache
      _baseUrl = url;
    } catch (e) {
      throw Exception('Erreur lors de la sauvegarde de l\'URL: $e');
    }
  }

  /// Réinitialise l'URL à la valeur par défaut
  static Future<void> resetBaseUrl() async {
    await setBaseUrl(defaultUrl);
  }

  /// Récupère l'URL sauvegardée (sans charger depuis SharedPreferences)
  static Future<String?> getSavedBaseUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_backendUrlKey);
    } catch (e) {
      return null;
    }
  }

  /// Récupère l'URL par défaut
  static String get defaultUrl => _defaultUrl;

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
  static const String comments = '/comments';

  // Config - délai de connexion (réseau local Wi‑Fi parfois lent)
  static const Duration timeout = Duration(seconds: 45);

  // BLE Configuration
  static const String deviceNamePrefix =
      'Pansement'; // Nom du device dans Zephyr (CONFIG_BT_DEVICE_NAME)

  // GATT Services & Characteristics UUIDs
  // ⚠️ Ces UUIDs doivent correspondre exactement à ceux du firmware Zephyr
  // Voir: BE_pansement_connecte/BLE_pansement/src/main.c
  static const String serviceUuid = '12345678-1234-5678-1234-56789abcdef0';
  static const String characteristicUuid =
      '12345678-1234-5678-1234-56789abcdef1';
}
