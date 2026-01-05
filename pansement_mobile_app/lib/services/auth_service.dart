import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';
import 'api_service.dart';
import '../models/user.dart';

/// Service d'authentification
class AuthService {
  final ApiService _apiService;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final Logger _logger = Logger();

  static const String _tokenKey = 'access_token';
  static const String _userIdKey = 'user_id';

  AuthService(this._apiService);

  // Login
  Future<User> login(String email, String password) async {
    try {
      final response = await _apiService.login(email, password);

      // Sauvegarder le token
      final token = response['access_token'];
      if (token == null) {
        throw Exception('Token non reçu dans la réponse');
      }

      await _storage.write(key: _tokenKey, value: token);

      // Configurer le token dans ApiService
      _apiService.setToken(token);

      // Récupérer les infos utilisateur
      final user = User.fromJson(response['user']);
      await _storage.write(key: _userIdKey, value: user.id);

      _logger.i('Login successful: ${user.email}');
      return user;
    } catch (e) {
      _logger.e('Login failed: $e');
      // Améliorer le message d'erreur
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('timeout') ||
          errorStr.contains('connection') ||
          errorStr.contains('failed host lookup') ||
          errorStr.contains('network is unreachable')) {
        throw Exception(
            'Impossible de se connecter au serveur.\n\nVérifiez que:\n1. Le backend est démarré (http://localhost:8000)\n2. L\'émulateur peut accéder à 10.0.2.2:8000\n3. Le firewall n\'bloque pas la connexion');
      }
      if (errorStr.contains('401') || errorStr.contains('unauthorized')) {
        throw Exception('Email ou mot de passe incorrect');
      }
      rethrow;
    }
  }

  // Logout
  Future<void> logout() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userIdKey);
    _apiService.clearToken();
    _logger.i('Logout successful');
  }

  // Vérifier si l'utilisateur est connecté
  Future<bool> isLoggedIn() async {
    final token = await _storage.read(key: _tokenKey);
    return token != null;
  }

  // Récupérer l'utilisateur courant
  Future<User?> getCurrentUser() async {
    try {
      final token = await _storage.read(key: _tokenKey);
      if (token == null) return null;

      _apiService.setToken(token);
      return await _apiService.getCurrentUser();
    } catch (e) {
      _logger.e('Get current user failed: $e');
      await logout(); // Token invalide, déconnexion
      return null;
    }
  }
}
