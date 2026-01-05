import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../models/measurement.dart';
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

// Provider pour toutes les mesures d'un patient
final patientMeasurementsProvider =
    FutureProvider.family<List<Measurement>, String>((ref, patientId) async {
  final apiService = ref.watch(apiServiceProvider);
  await _ensureTokenLoaded(apiService);

  return await apiService.getPatientMeasurements(
    patientId,
    limit:
        100, // Augmenter la limite pour avoir plus de données pour les graphiques
  );
});

// Provider pour les mesures filtrées par type
final patientMeasurementsByTypeProvider =
    FutureProvider.family<List<Measurement>, Map<String, dynamic>>(
        (ref, params) async {
  final apiService = ref.watch(apiServiceProvider);
  await _ensureTokenLoaded(apiService);

  final String patientId = params['patientId'] as String;
  final String measurementType = params['measurementType'] as String;
  final int limit = params['limit'] as int? ?? 100;

  return await apiService.getPatientMeasurements(
    patientId,
    measurementType: measurementType,
    limit: limit,
  );
});

// Provider pour la dernière mesure d'un type spécifique
final latestMeasurementProvider =
    FutureProvider.family<Measurement?, Map<String, dynamic>>(
        (ref, params) async {
  final apiService = ref.watch(apiServiceProvider);
  await _ensureTokenLoaded(apiService);

  final String patientId = params['patientId'] as String;
  final String? measurementType = params['measurementType'] as String?;

  try {
    return await apiService.getLatestMeasurement(
      patientId,
      measurementType: measurementType,
    );
  } catch (e) {
    // Si aucune mesure n'est trouvée, retourner null
    return null;
  }
});

// Provider pour les statistiques d'un patient
final patientStatsProvider =
    FutureProvider.family<Map<String, dynamic>, Map<String, dynamic>>(
        (ref, params) async {
  // Retourner immédiatement des stats vides pour éviter le chargement infini
  // TODO: Réactiver l'appel API une fois le problème résolu

  // Utiliser Future.value pour retourner immédiatement sans attendre
  return Future.value({
    'total_measurements': 0,
    'last_measurement': null,
    'stats_by_type': [],
  });

  /* CODE DÉSACTIVÉ TEMPORAIREMENT POUR DÉBOGUER
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

  // Vérifier d'abord si le patient a des devices assignés
  try {
    final devices = await apiService.getDevices(patientId: patientId);
    if (devices.isEmpty) {
      // Pas de devices = pas de stats possibles, retourner immédiatement
      return {
        'total_measurements': 0,
        'last_measurement': null,
        'stats_by_type': [],
      };
    }
  } catch (e) {
    // Si on ne peut pas vérifier les devices, continuer quand même
    print('⚠️ Impossible de vérifier les devices: $e');
  }

  try {
    // Ajouter un timeout pour éviter un chargement infini (5 secondes)
    final stats =
        await apiService.getPatientStats(patientId, days: days).timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        print('⚠️ Timeout lors de la récupération des stats pour $patientId');
        throw TimeoutException('Timeout: La requête a pris trop de temps');
      },
    );

    // Extraire la dernière mesure depuis stats_by_type
    DateTime? lastMeasurementDate;
    if (stats['stats_by_type'] != null &&
        (stats['stats_by_type'] as List).isNotEmpty) {
      for (var typeStat in stats['stats_by_type'] as List) {
        if (typeStat['latest_timestamp'] != null) {
          final timestamp =
              DateTime.tryParse(typeStat['latest_timestamp'].toString());
          if (timestamp != null &&
              (lastMeasurementDate == null ||
                  timestamp.isAfter(lastMeasurementDate))) {
            lastMeasurementDate = timestamp;
          }
        }
      }
    }

    // Formater la réponse pour le frontend
    return {
      'total_measurements': stats['total_measurements'] ?? 0,
      'last_measurement': lastMeasurementDate,
      'stats_by_type': stats['stats_by_type'] ?? [],
    };
  } on TimeoutException catch (e) {
    print('⏱️ TimeoutException dans patientStatsProvider: $e');
    // En cas de timeout, retourner des stats vides immédiatement
    return {
      'total_measurements': 0,
      'last_measurement': null,
      'stats_by_type': [],
    };
  } catch (e, stackTrace) {
    // En cas d'erreur, logger et retourner des stats vides immédiatement
    print('❌ Erreur dans patientStatsProvider: $e');
    print('Stack trace: $stackTrace');
    return {
      'total_measurements': 0,
      'last_measurement': null,
      'stats_by_type': [],
    };
  }
  */
});

// Provider pour les mesures de température d'un patient (pour graphique)
final temperatureMeasurementsProvider =
    FutureProvider.family<List<Measurement>, String>((ref, patientId) async {
  final apiService = ref.watch(apiServiceProvider);
  await _ensureTokenLoaded(apiService);

  return await apiService.getPatientMeasurements(
    patientId,
    measurementType: 'temperature',
    limit: 100,
  );
});

// Provider pour les mesures d'humidité d'un patient (pour graphique)
final humidityMeasurementsProvider =
    FutureProvider.family<List<Measurement>, String>((ref, patientId) async {
  final apiService = ref.watch(apiServiceProvider);
  await _ensureTokenLoaded(apiService);

  return await apiService.getPatientMeasurements(
    patientId,
    measurementType: 'humidity',
    limit: 100,
  );
});

// Provider pour les mesures de pH d'un patient (pour graphique)
final phMeasurementsProvider =
    FutureProvider.family<List<Measurement>, String>((ref, patientId) async {
  final apiService = ref.watch(apiServiceProvider);
  await _ensureTokenLoaded(apiService);

  return await apiService.getPatientMeasurements(
    patientId,
    measurementType: 'ph',
    limit: 100,
  );
});
