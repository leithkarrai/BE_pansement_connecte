import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import 'auth_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Charge le token JWT depuis le stockage sécurisé vers [ApiService].
/// Permet aux FutureProviders d'appeler l'API même après relance de l'app.
Future<void> _ensureTokenLoaded(ApiService apiService) async {
  const storage = FlutterSecureStorage();
  final token = await storage.read(key: 'access_token');
  if (token != null) {
    apiService.setToken(token);
  }
}

/// Liste des alertes visible par l'utilisateur courant.
///
/// Le filtrage réel des permissions est fait côté backend selon le rôle.
final alertsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final apiService = ref.watch(apiServiceProvider);
  await _ensureTokenLoaded(apiService);
  final currentUser = ref.watch(authProvider).user;

  if (currentUser == null) {
    return {
      'alerts': [],
      'total': 0,
      'unacknowledged': 0,
      'critical': 0,
    };
  }

  try {
    final response = await apiService.getAlerts(limit: 100);
    return response;
  } catch (e) {
    return {
      'alerts': [],
      'total': 0,
      'unacknowledged': 0,
      'critical': 0,
    };
  }
});

/// Alertes non acquittées, utilisées pour badge/snackbar.
/// Ici on cible `new_measurements` pour le signal "nouvelles mesures reçues".
final unacknowledgedAlertsProvider =
    FutureProvider.autoDispose<List<dynamic>>((ref) async {
  final apiService = ref.watch(apiServiceProvider);
  await _ensureTokenLoaded(apiService);
  final currentUser = ref.watch(authProvider).user;
  if (currentUser == null) return [];

  try {
    final data = await apiService.getAlerts(
      unacknowledgedOnly: true,
      limit: 20,
      alertType: 'new_measurements',
    );
    final list = data['alerts'];
    return list is List ? List<dynamic>.from(list) : [];
  } catch (e) {
    return [];
  }
});

/// Alertes d'un patient donné (écrans détail patient).
/// En cas d'échec, retourne une structure vide pour stabiliser l'UI.
final patientAlertsProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, patientId) async {
  final apiService = ref.watch(apiServiceProvider);
  await _ensureTokenLoaded(apiService);

  try {
    final response = await apiService.getPatientAlerts(patientId, limit: 100);
    return response;
  } catch (e) {
    return {
      'alerts': [],
      'total': 0,
      'unacknowledged': 0,
      'critical': 0,
    };
  }
});
