import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../models/user.dart';
import '../models/device.dart';
import 'auth_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Charge le token JWT pour les appels dashboard effectués hors flux login direct.
Future<void> _ensureTokenLoaded(ApiService apiService) async {
  const storage = FlutterSecureStorage();
  final token = await storage.read(key: 'access_token');
  if (token != null) {
    apiService.setToken(token);
  }
}

/// Liste utilisateurs pour le dashboard.
/// - admin: patients + médecins
/// - médecin: lui-même + ses patients
/// - patient: lui-même
final usersProvider = FutureProvider<List<User>>((ref) async {
  try {
    final apiService = ref.watch(apiServiceProvider);
    await _ensureTokenLoaded(apiService);
    final currentUser = ref.watch(authProvider).user;

    if (currentUser == null) return [];

    if (currentUser.role == 'admin') {
      final patients = await apiService.getUsers(role: 'patient');
      final doctors = await apiService.getUsers(role: 'medecin');
      return [...patients, ...doctors];
    }
    if (currentUser.role == 'medecin') {
      final patients = await apiService.getUsers(role: 'patient');
      return [currentUser, ...patients];
    }
    if (currentUser.role == 'patient') {
      return [currentUser];
    }
    return [];
  } catch (_) {
    return [];
  }
});

/// Liste "patients" adaptée au rôle courant.
final patientsProvider = FutureProvider<List<User>>((ref) async {
  try {
    final apiService = ref.watch(apiServiceProvider);
    await _ensureTokenLoaded(apiService);
    final currentUser = ref.watch(authProvider).user;

    if (currentUser == null) return [];

    if (currentUser.role == 'admin') {
      final patients = await apiService.getUsers(role: 'patient');
      final doctors = await apiService.getUsers(role: 'medecin');
      return [...patients, ...doctors];
    }
    if (currentUser.role == 'medecin') {
      return await apiService.getUsers(role: 'patient');
    }
    if (currentUser.role == 'patient') {
      return [currentUser];
    }
    return [];
  } catch (_) {
    return [];
  }
});

/// Liste stricte des patients (utile pour assignation de devices).
final patientsOnlyProvider = FutureProvider<List<User>>((ref) async {
  final apiService = ref.watch(apiServiceProvider);
  await _ensureTokenLoaded(apiService);

  // Toujours retourner uniquement les patients, peu importe le rôle
  return await apiService.getUsers(role: 'patient');
});

/// Liste devices filtrée par rôle.
final devicesProvider = FutureProvider<List<Device>>((ref) async {
  try {
    final apiService = ref.watch(apiServiceProvider);
    await _ensureTokenLoaded(apiService);
    final currentUser = ref.watch(authProvider).user;

    if (currentUser == null) return [];

    if (currentUser.role == 'admin') {
      return await apiService.getDevices();
    }
    if (currentUser.role == 'medecin') {
      return await apiService.getDevices();
    }
    if (currentUser.role == 'patient') {
      return await apiService.getDevices(patientId: currentUser.id);
    }
    return [];
  } catch (_) {
    return [];
  }
});

/// Valeurs par défaut en cas d'erreur API (fallback robuste UI).
Map<String, int> _defaultStats() => {
      'total_patients': 0,
      'active_patients': 0,
      'total_devices': 0,
      'active_devices': 0,
      'available_devices': 0,
      'total_doctors': 0,
      'alerts': 0,
      'alerts_unacknowledged': 0,
      'today_measurements': 0,
      'my_patients': 0,
      'my_device': 0,
      'device_status': 0,
      'battery_level': 0,
    };

/// Statistiques du dashboard selon le rôle courant.
/// Les champs absents selon rôle sont volontairement omis côté retour.
final dashboardStatsProvider = FutureProvider<Map<String, int>>((ref) async {
  try {
    final apiService = ref.watch(apiServiceProvider);
    await _ensureTokenLoaded(apiService);
    final currentUser = ref.watch(authProvider).user;

    if (currentUser == null) return _defaultStats();

    if (currentUser.role == 'admin') {
      final patients = await apiService.getUsers(role: 'patient');
      final doctors = await apiService.getUsers(role: 'medecin');
      final devices = await apiService.getDevices();
      int alertsTotal = 0;
      int alertsUnacknowledged = 0;
      try {
        final alertsData = await apiService.getAlerts(limit: 100);
        alertsTotal = (alertsData['total'] as int?) ?? 0;
        alertsUnacknowledged = (alertsData['unacknowledged'] as int?) ?? 0;
      } catch (_) {}

      int todayMeasurements = 0;
      try {
        todayMeasurements = await apiService.getTodayMeasurementsCount();
      } catch (_) {}

      // Côté admin, "utilisateurs" = patients + médecins.
      // (les KPI "Total Utilisateurs" / "Utilisateurs Actifs" doivent donc
      // inclure aussi les médecins).
      final activePatients = patients.where((p) => p.isActive).length;
      final activeDoctors = doctors.where((d) => d.isActive).length;
      final activeDevices = devices.where((d) => d.status == 'active').length;
      final availableDevices = devices.where((d) => d.patientId == null).length;

      return {
        // Garder les clés existantes pour ne pas impacter les écrans.
        'total_patients': patients.length + doctors.length,
        'active_patients': activePatients + activeDoctors,
        'total_doctors': doctors.length,
        'active_devices': activeDevices,
        'available_devices': availableDevices,
        'alerts': alertsTotal,
        'alerts_unacknowledged': alertsUnacknowledged,
        'today_measurements': todayMeasurements,
      };
    }

    if (currentUser.role == 'medecin') {
      final patients = await apiService.getUsers(role: 'patient');
      final devices = await apiService.getDevices();
      int alertsTotal = 0;
      int alertsUnacknowledged = 0;
      try {
        final alertsData = await apiService.getAlerts(limit: 100);
        alertsTotal = (alertsData['total'] as int?) ?? 0;
        alertsUnacknowledged = (alertsData['unacknowledged'] as int?) ?? 0;
      } catch (_) {}

      int todayMeasurements = 0;
      try {
        todayMeasurements = await apiService.getTodayMeasurementsCount();
      } catch (_) {}

      final activePatients = patients.where((p) => p.isActive).length;
      final activeDevices = devices.where((d) => d.status == 'active').length;

      return {
        'total_patients': patients.length,
        'active_patients': activePatients,
        'my_patients': patients.length,
        'active_devices': activeDevices,
        'alerts': alertsTotal,
        'alerts_unacknowledged': alertsUnacknowledged,
        'today_measurements': todayMeasurements,
      };
    }

    if (currentUser.role == 'patient') {
      final devices = await apiService.getDevices(patientId: currentUser.id);
      final myDevice = devices.isNotEmpty ? devices.first : null;

      return {
        'my_device': myDevice != null ? 1 : 0,
        'device_status': myDevice?.status == 'active' ? 1 : 0,
        'battery_level': myDevice?.batteryLevel ?? 0,
        'total_measurements': 0,
      };
    }

    return _defaultStats();
  } catch (_) {
    return _defaultStats();
  }
});

/// Détail d'un patient pour les écrans fiche patient.
final patientDetailProvider =
    FutureProvider.family<User, String>((ref, patientId) async {
  final apiService = ref.watch(apiServiceProvider);
  await _ensureTokenLoaded(apiService);
  return await apiService.getUser(patientId);
});

/// Device principal d'un patient (compat avec écrans historiques à device unique).
final patientDeviceProvider =
    FutureProvider.family<Device?, String>((ref, patientId) async {
  final apiService = ref.watch(apiServiceProvider);
  await _ensureTokenLoaded(apiService);

  try {
    final devices = await apiService.getDevices(patientId: patientId);
    return devices.isNotEmpty ? devices.first : null;
  } catch (e) {
    return null;
  }
});

/// Tous les devices d'un patient (cas multi-devices).
final patientDevicesProvider =
    FutureProvider.family<List<Device>, String>((ref, patientId) async {
  final apiService = ref.watch(apiServiceProvider);
  await _ensureTokenLoaded(apiService);

  try {
    final devices = await apiService.getDevices(patientId: patientId);
    return devices;
  } catch (e) {
    return [];
  }
});

/// Médecin assigné à un patient (si disponible).
final patientMedecinProvider =
    FutureProvider.family<Map<String, dynamic>?, String>(
        (ref, patientId) async {
  final apiService = ref.watch(apiServiceProvider);
  await _ensureTokenLoaded(apiService);

  try {
    return await apiService.getPatientMedecin(patientId);
  } catch (e) {
    return null;
  }
});

/// Patients suivis par un médecin donné.
final medecinPatientsProvider =
    FutureProvider.family<List<User>, String>((ref, medecinId) async {
  final apiService = ref.watch(apiServiceProvider);
  await _ensureTokenLoaded(apiService);

  try {
    return await apiService.getMedecinPatients(medecinId);
  } catch (e) {
    return [];
  }
});
