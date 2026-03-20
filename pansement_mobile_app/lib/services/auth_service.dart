import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';
import 'api_service.dart';
import '../models/user.dart';

/// Service d'authentification côté mobile.
///
/// Responsabilités:
/// - appeler les endpoints auth via [ApiService],
/// - persister la session (token + user_id) dans le stockage sécurisé,
/// - recharger l'utilisateur courant au redémarrage.
class AuthService {
  final ApiService _apiService;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final Logger _logger = Logger();

  static const String _tokenKey = 'access_token';
  static const String _userIdKey = 'user_id';

  AuthService(this._apiService);

  /// Connexion utilisateur.
  ///
  /// Flux:
  /// 1) POST /auth/login
  /// 2) stockage sécurisé du token
  /// 3) injection du token dans ApiService pour les appels suivants
  /// 4) retour du profil utilisateur
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

      // Si le backend fournit explicitement le motif (ex: hard delete),
      // on évite de remplacer par un message générique.
      final match = RegExp(r'Exception:\s*(.*)$', caseSensitive: false)
          .firstMatch(e.toString());
      final backendDetail = match?.group(1)?.trim();
      if (backendDetail != null &&
          backendDetail
              .toLowerCase()
              .contains('votre compte a été supprimé par un administrateur')) {
        throw Exception(backendDetail);
      }

      if (errorStr.contains('timeout') ||
          errorStr.contains('connection') ||
          errorStr.contains('failed host lookup') ||
          errorStr.contains('network is unreachable')) {
        // Le message d'erreur détaillé vient déjà de ApiService
        // On le propage tel quel
        rethrow;
      }
      if (errorStr.contains('401') || errorStr.contains('unauthorized')) {
        throw Exception('Email ou mot de passe incorrect');
      }
      rethrow;
    }
  }

  /// Déconnexion locale (suppression token + user_id côté device).
  Future<void> logout() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userIdKey);
    _apiService.clearToken();
    _logger.i('Logout successful');
  }

  /// Indique si un token est présent localement.
  /// Ne garantit pas à lui seul que le token est encore valide côté backend.
  Future<bool> isLoggedIn() async {
    final token = await _storage.read(key: _tokenKey);
    return token != null;
  }

  /// Tente de recharger l'utilisateur courant à partir du token stocké.
  /// Si le token est invalide/expiré, force un logout propre.
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
