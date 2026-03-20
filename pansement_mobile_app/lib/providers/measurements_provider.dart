import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../models/measurement.dart';
import '../services/api_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Charge le token JWT depuis le stockage sécurisé vers [ApiService].
///
/// Utile pour les providers exécutés hors parcours login immédiat
/// (écran ouvert après redémarrage app, deep link, etc.).
Future<void> _ensureTokenLoaded(ApiService apiService) async {
  const storage = FlutterSecureStorage();
  final token = await storage.read(key: 'access_token');
  if (token != null) {
    apiService.setToken(token);
  }
}

/// Provider pour récupérer l'historique des mesures d'un device
final deviceMeasurementsProvider =
    FutureProvider.family<List<Measurement>, String>(
  (ref, deviceId) async {
    // Récupérer toutes les mesures du device (limite à 100 pour les graphiques)
    try {
      // Pour l'instant, on récupère via le patient si disponible
      // TODO: Créer un endpoint API pour récupérer les mesures par device_id
      return [];
    } catch (e) {
      return [];
    }
  },
);

/// Provider pour récupérer l'historique des mesures d'un patient
final patientMeasurementsProvider =
    FutureProvider.family<List<Measurement>, String>(
  (ref, patientId) async {
    final apiService = ref.watch(apiServiceProvider);
    try {
      debugPrint('📊 Chargement des mesures pour patient: $patientId');
      final measurements =
          await apiService.getPatientMeasurements(patientId, limit: 500);
      debugPrint(
          '📊 ${measurements.length} mesure(s) chargée(s) pour patient: $patientId');
      return measurements;
    } catch (e) {
      debugPrint('❌ Erreur chargement mesures pour patient $patientId: $e');
      return [];
    }
  },
);

/// Provider pour récupérer les mesures par type (pour les graphiques)
final measurementsByTypeProvider =
    FutureProvider.family<List<Measurement>, Map<String, String>>(
  (ref, params) async {
    final apiService = ref.watch(apiServiceProvider);
    final patientId = params['patientId'];
    final measurementType = params['measurementType'];

    // Vérifier que patientId est valide pour éviter une requête inutile.
    if (patientId == null || patientId.isEmpty) {
      return [];
    }

    try {
      // Timeout explicite pour éviter une UI bloquée en chargement infini.
      return await apiService
          .getPatientMeasurements(
        patientId,
        measurementType: measurementType,
        limit: 100,
      )
          .timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          print('⚠️ Timeout lors de la récupération des mesures');
          return <Measurement>[];
        },
      );
    } catch (e) {
      // Retour immédiat d'une liste vide pour stabiliser l'UI en mode dégradé.
      print('⚠️ Erreur lors de la récupération des mesures: $e');
      return [];
    }
  },
);

/// Provider de statistiques agrégées d'un patient sur une fenêtre glissante.
///
/// Sortie:
/// - total mesures dans la période,
/// - date de dernière mesure,
/// - compteur par type de mesure.
final patientStatsProvider =
    FutureProvider.family<Map<String, dynamic>, Map<String, dynamic>>(
  (ref, params) async {
    final apiService = ref.watch(apiServiceProvider);
    await _ensureTokenLoaded(apiService);

    final String patientId = params['patientId'] as String;
    final int days = params['days'] as int? ?? 7;

    // Retourner immédiatement des stats vides si patientId est invalide
    if (patientId.isEmpty) {
      return {
        'total_measurements': 0,
        'last_measurement': null,
        'stats_by_type': [],
      };
    }

    try {
      // Récupérer les mesures du patient
      final measurements = await apiService.getPatientMeasurements(
        patientId,
        limit: 1000, // Récupérer plus de mesures pour les stats
      );

      // Filtrer par période (derniers X jours)
      final cutoffDate = DateTime.now().subtract(Duration(days: days));
      final recentMeasurements = measurements.where((m) {
        return m.timestamp.isAfter(cutoffDate);
      }).toList();

      // Trouver la dernière mesure
      DateTime? lastMeasurementDate;
      if (measurements.isNotEmpty) {
        lastMeasurementDate = measurements
            .map((m) => m.timestamp)
            .reduce((a, b) => a.isAfter(b) ? a : b);
      }

      // Compter par type
      final statsByType = <String, int>{};
      for (final measurement in recentMeasurements) {
        final type = measurement.measurementType;
        statsByType[type] = (statsByType[type] ?? 0) + 1;
      }

      return {
        'total_measurements': recentMeasurements.length,
        'last_measurement': lastMeasurementDate,
        'stats_by_type': statsByType,
      };
    } catch (e) {
      debugPrint('❌ Erreur lors de la récupération des stats: $e');
      // En cas d'erreur, retourner des stats vides
      return {
        'total_measurements': 0,
        'last_measurement': null,
        'stats_by_type': {},
      };
    }
  },
);
