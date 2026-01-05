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
      if (e.toString().contains('connection error') || 
          e.toString().contains('XMLHttpRequest')) {
        throw Exception('Impossible de se connecter au serveur. Vérifiez que le backend est démarré sur http://localhost:8000');
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

