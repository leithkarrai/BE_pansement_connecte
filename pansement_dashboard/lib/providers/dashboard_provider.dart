import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../models/user.dart';
import '../models/device.dart';
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

// Provider pour les patients (filtré selon le rôle)
final patientsProvider = FutureProvider<List<User>>((ref) async {
  final apiService = ref.watch(apiServiceProvider);
  await _ensureTokenLoaded(apiService);
  final currentUser = ref.watch(authProvider).user;

  if (currentUser == null) return [];

  // ADMIN : Voir tous les utilisateurs (patients + médecins)
  if (currentUser.role == 'admin') {
    final patients = await apiService.getUsers(role: 'patient');
    final doctors = await apiService.getUsers(role: 'medecin');
    return [...patients, ...doctors];
  }

  // MÉDECIN : Voir tous les patients
  if (currentUser.role == 'medecin') {
    return await apiService.getUsers(role: 'patient');
  }

  // PATIENT : Ne voir que lui-même
  if (currentUser.role == 'patient') {
    return [currentUser];
  }

  return [];
});

// Provider pour les patients uniquement (pour l'assignation de devices)
final patientsOnlyProvider = FutureProvider<List<User>>((ref) async {
  final apiService = ref.watch(apiServiceProvider);
  await _ensureTokenLoaded(apiService);

  // Toujours retourner uniquement les patients, peu importe le rôle
  return await apiService.getUsers(role: 'patient');
});

// Provider pour les devices (filtré selon le rôle)
final devicesProvider = FutureProvider<List<Device>>((ref) async {
  final apiService = ref.watch(apiServiceProvider);
  await _ensureTokenLoaded(apiService);
  final currentUser = ref.watch(authProvider).user;

  if (currentUser == null) return [];

  // ADMIN : Tous les devices
  if (currentUser.role == 'admin') {
    return await apiService.getDevices();
  }

  // MÉDECIN : Devices de ses patients uniquement
  if (currentUser.role == 'medecin') {
    // TODO: Filtrer par patients du médecin
    // Pour l'instant, on retourne tous
    return await apiService.getDevices();
  }

  // PATIENT : Son device uniquement
  if (currentUser.role == 'patient') {
    return await apiService.getDevices(patientId: currentUser.id);
  }

  return [];
});

// Provider pour les statistiques (filtré selon le rôle)
final dashboardStatsProvider = FutureProvider<Map<String, int>>((ref) async {
  final apiService = ref.watch(apiServiceProvider);
  await _ensureTokenLoaded(apiService);
  final currentUser = ref.watch(authProvider).user;

  if (currentUser == null) {
    return {
      'total_patients': 0,
      'active_patients': 0,
      'total_devices': 0,
      'active_devices': 0,
      'available_devices': 0,
    };
  }

  // ADMIN : Statistiques globales
  if (currentUser.role == 'admin') {
    final patients = await apiService.getUsers(role: 'patient');
    final doctors = await apiService.getUsers(role: 'medecin');
    final devices = await apiService.getDevices();

    final activeDevices = devices.where((d) => d.status == 'active').length;

    return {
      'total_patients': patients.length,
      'total_doctors': doctors.length,
      'active_devices': activeDevices,
      'today_measurements': 0, // TODO: Compter les mesures d'aujourd'hui
    };
  }

  // MÉDECIN : Statistiques de ses patients
  if (currentUser.role == 'medecin') {
    final patients = await apiService.getUsers(role: 'patient');
    // TODO: Filtrer par patients du médecin
    final devices = await apiService.getDevices();

    final activeDevices = devices.where((d) => d.status == 'active').length;

    return {
      'my_patients': patients.length, // Nombre de patients assignés
      'active_devices': activeDevices,
      'alerts': 0, // TODO: Compter les alertes (mesures anormales)
    };
  }

  // PATIENT : Statistiques personnelles
  if (currentUser.role == 'patient') {
    final devices = await apiService.getDevices(patientId: currentUser.id);
    final myDevice = devices.isNotEmpty ? devices.first : null;

    return {
      'my_device': myDevice != null ? 1 : 0,
      'device_status': myDevice?.status == 'active' ? 1 : 0,
      'battery_level': myDevice?.batteryLevel ?? 0,
      'total_measurements': 0, // TODO: Compter les mesures
    };
  }

  return {};
});

// Provider pour récupérer les détails d'un patient spécifique
final patientDetailProvider =
    FutureProvider.family<User, String>((ref, patientId) async {
  final apiService = ref.watch(apiServiceProvider);
  await _ensureTokenLoaded(apiService);
  return await apiService.getUser(patientId);
});

// Provider pour récupérer le device d'un patient (un seul - pour compatibilité)
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

// Provider pour récupérer TOUS les devices d'un patient (plusieurs devices possibles)
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
