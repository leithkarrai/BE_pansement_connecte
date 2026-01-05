import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import 'auth_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// Helper pour charger le token dans ApiService
Future<void> _ensureTokenLoaded(ApiService apiService) async {
  const storage = FlutterSecureStorage();
  final token = await storage.read(key: 'access_token');
  if (token != null) {
    apiService.setToken(token);
  }
}

// Provider pour la liste des alertes (filtré selon le rôle)
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

// Provider pour les alertes d'un patient spécifique
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
