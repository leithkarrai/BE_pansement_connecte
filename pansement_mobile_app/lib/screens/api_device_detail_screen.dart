import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../providers/auth_provider.dart';
import '../models/device.dart';
import '../models/user.dart';
import '../providers/dashboard_provider.dart';
import '../services/api_service.dart';

/// Provider pour récupérer un device spécifique
final deviceDetailProvider =
    FutureProvider.family<Device, String>((ref, deviceId) async {
  final apiService = ref.watch(apiServiceProvider);
  // Charger le token local avant l'appel API (provider utilisé hors flux login immédiat).
  try {
    const storage = FlutterSecureStorage();
    final token = await storage.read(key: 'access_token');
    if (token != null) {
      apiService.setToken(token);
    } else {
      debugPrint('⚠️ Aucun token trouvé pour deviceDetailProvider');
    }
  } catch (e) {
    debugPrint('❌ Erreur lors du chargement du token: $e');
  }
  return await apiService.getDevice(deviceId);
});

/// Écran pour afficher les détails d'un device de l'API
class ApiDeviceDetailScreen extends ConsumerStatefulWidget {
  final String deviceId;

  const ApiDeviceDetailScreen({
    super.key,
    required this.deviceId,
  });

  @override
  ConsumerState<ApiDeviceDetailScreen> createState() =>
      _ApiDeviceDetailScreenState();
}

class _ApiDeviceDetailScreenState extends ConsumerState<ApiDeviceDetailScreen> {
  final _storage = const FlutterSecureStorage();

  // Helper: injecte le token JWT dans ApiService pour les actions de cet écran.
  Future<void> _ensureTokenLoaded(ApiService apiService) async {
    try {
      final token = await _storage.read(key: 'access_token');
      if (token != null) {
        apiService.setToken(token);
        debugPrint('✅ Token chargé dans ApiService');
      } else {
        debugPrint('⚠️ Aucun token trouvé dans le stockage');
      }
    } catch (e) {
      debugPrint('❌ Erreur lors du chargement du token: $e');
    }
  }

  // Helper: SnackBar robuste même quand l'écran est en transition.
  void _showSnackBar(String message,
      {Color? backgroundColor, Duration? duration}) {
    if (!mounted) return;

    // Utiliser Future.microtask pour éviter les erreurs de widget désactivé
    Future.microtask(() {
      if (!mounted) return;
      final scaffoldMessenger = ScaffoldMessenger.maybeOf(context);
      if (scaffoldMessenger != null && mounted) {
        try {
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: backgroundColor ?? Colors.grey,
              duration: duration ?? const Duration(seconds: 3),
            ),
          );
        } catch (e) {
          debugPrint('❌ Erreur lors de l\'affichage du SnackBar: $e');
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final deviceAsync = ref.watch(deviceDetailProvider(widget.deviceId));
    final currentUser = ref.watch(authProvider).user;

    // Logs utiles en debug pour diagnostiquer les problèmes de permissions/token.
    debugPrint('🔍 DEBUG ApiDeviceDetailScreen:');
    debugPrint('   - Device ID: ${widget.deviceId}');
    debugPrint('   - Current User: ${currentUser?.email ?? "null"}');
    debugPrint('   - User Role: ${currentUser?.role ?? "null"}');
    debugPrint(
        '   - Is Admin/Medecin: ${currentUser?.role == 'admin' || currentUser?.role == 'medecin'}');

    // Détail device orienté exploitation:
    // identité device, statut, assignation patient, actions de gestion.
    return Scaffold(
      appBar: AppBar(
        title: const Text('Détails de l\'appareil'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualiser',
            onPressed: () {
              ref.invalidate(deviceDetailProvider(widget.deviceId));
            },
          ),
        ],
      ),
      body: deviceAsync.when(
        data: (device) => SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Carte principale avec informations du device
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: _getStatusColor(device.status),
                            radius: 30,
                            child: const Icon(
                              Icons.medical_services,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  device.serialNumber,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  device.model,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _getStatusColor(device.status)
                                        .withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    _getStatusLabel(device.status),
                                    style: TextStyle(
                                      color: _getStatusColor(device.status),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Informations détaillées
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Informations',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                      const Divider(height: 24),
                      _buildInfoRow(context, 'ID', device.id),
                      _buildInfoRow(
                        context,
                        'Numéro de série',
                        device.serialNumber,
                      ),
                      _buildInfoRow(context, 'Modèle', device.model),
                      if (device.firmwareVersion != null)
                        _buildInfoRow(
                          context,
                          'Version firmware',
                          device.firmwareVersion!,
                        ),
                      if (device.batteryLevel != null)
                        _buildInfoRow(
                          context,
                          'Niveau de batterie',
                          '${device.batteryLevel}%',
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Assignation patient
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Assignation',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                      const Divider(height: 24),
                      Builder(
                        builder: (context) {
                          debugPrint('🔍 DEBUG Assignation section:');
                          debugPrint(
                              '   - device.patientId: ${device.patientId}');
                          debugPrint(
                              '   - device.patientName: ${device.patientName}');
                          debugPrint(
                              '   - currentUser?.role: ${currentUser?.role}');
                          debugPrint(
                              '   - Show unassign button: ${device.patientId != null && (currentUser?.role == 'admin' || currentUser?.role == 'medecin')}');
                          debugPrint(
                              '   - Show assign button: ${device.patientId == null && (currentUser?.role == 'admin' || currentUser?.role == 'medecin')}');

                          if (device.patientId != null) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildInfoRow(
                                  context,
                                  'Patient',
                                  device.patientName ?? 'Inconnu',
                                ),
                                if (device.assignedAt != null)
                                  _buildInfoRow(
                                    context,
                                    'Assigné le',
                                    DateFormat('dd/MM/yyyy à HH:mm')
                                        .format(device.assignedAt!),
                                  ),
                                if (currentUser?.role == 'admin' ||
                                    currentUser?.role == 'medecin')
                                  Padding(
                                    padding: const EdgeInsets.only(top: 16),
                                    child: ElevatedButton.icon(
                                      onPressed: () {
                                        debugPrint(
                                            '🔘 Bouton "Désassigner" cliqué');
                                        _unassignDevice(context);
                                      },
                                      icon: const Icon(Icons.person_remove),
                                      label:
                                          const Text('Désassigner le patient'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.orange,
                                        foregroundColor: Colors.white,
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          } else {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Aucun patient assigné'),
                                if (currentUser?.role == 'admin' ||
                                    currentUser?.role == 'medecin')
                                  Padding(
                                    padding: const EdgeInsets.only(top: 16),
                                    child: ElevatedButton.icon(
                                      onPressed: () {
                                        debugPrint(
                                            '🔘 Bouton "Assigner" cliqué');
                                        _assignDevice(context);
                                      },
                                      icon: const Icon(Icons.person_add),
                                      label:
                                          const Text('Assigner à un patient'),
                                    ),
                                  ),
                              ],
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),

              // Actions (admin/médecin uniquement)
              Builder(
                builder: (context) {
                  final showActions = currentUser?.role == 'admin' ||
                      currentUser?.role == 'medecin';
                  debugPrint('🔍 DEBUG Actions section:');
                  debugPrint('   - Show actions: $showActions');
                  debugPrint('   - Device status: ${device.status}');

                  if (!showActions) {
                    return const SizedBox.shrink();
                  }

                  return Column(
                    children: [
                      const SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Actions',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                  ),
                                  PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert),
                                    tooltip: 'Actions disponibles',
                                    onSelected: (value) {
                                      debugPrint(
                                          '🔘 Menu action sélectionné: $value');
                                      _updateStatus(context, value);
                                    },
                                    itemBuilder: (BuildContext context) {
                                      final items = <PopupMenuEntry<String>>[];

                                      // Toujours afficher "Activer" si le statut n'est pas "active"
                                      if (device.status.toLowerCase() !=
                                          'active') {
                                        items.add(
                                          PopupMenuItem<String>(
                                            value: 'active',
                                            child: Row(
                                              children: [
                                                Icon(Icons.check_circle,
                                                    color: Colors.green),
                                                const SizedBox(width: 12),
                                                const Text('Activer'),
                                              ],
                                            ),
                                          ),
                                        );
                                      }

                                      // Toujours afficher "Désactiver" si le statut n'est pas "inactive"
                                      if (device.status.toLowerCase() !=
                                          'inactive') {
                                        items.add(
                                          PopupMenuItem<String>(
                                            value: 'inactive',
                                            child: Row(
                                              children: [
                                                Icon(Icons.cancel,
                                                    color: Colors.grey),
                                                const SizedBox(width: 12),
                                                const Text('Désactiver'),
                                              ],
                                            ),
                                          ),
                                        );
                                      }

                                      // Toujours afficher "Maintenance" si le statut n'est pas "maintenance"
                                      if (device.status.toLowerCase() !=
                                          'maintenance') {
                                        items.add(
                                          PopupMenuItem<String>(
                                            value: 'maintenance',
                                            child: Row(
                                              children: [
                                                Icon(Icons.build,
                                                    color: Colors.orange),
                                                const SizedBox(width: 12),
                                                const Text(
                                                    'Mettre en maintenance'),
                                              ],
                                            ),
                                          ),
                                        );
                                      }

                                      // Si aucune action disponible, afficher un message
                                      if (items.isEmpty) {
                                        items.add(
                                          const PopupMenuItem<String>(
                                            enabled: false,
                                            child: Text(
                                                'Aucune action disponible'),
                                          ),
                                        );
                                      }

                                      return items;
                                    },
                                  ),
                                ],
                              ),
                              const Divider(height: 24),
                              Text(
                                'Statut actuel: ${_getStatusLabel(device.status)}',
                                style: TextStyle(
                                  color: _getStatusColor(device.status),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Cliquez sur le menu (⋮) pour changer le statut',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        loading: () => const Center(
          child: CircularProgressIndicator(),
        ),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.red[300],
              ),
              const SizedBox(height: 16),
              Text(
                'Erreur lors du chargement',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.red[700],
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  error.toString(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  ref.invalidate(deviceDetailProvider(widget.deviceId));
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return Colors.green;
      case 'inactive':
        return Colors.grey;
      case 'maintenance':
        return Colors.orange;
      case 'retired':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getStatusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return 'Actif';
      case 'inactive':
        return 'Inactif';
      case 'maintenance':
        return 'Maintenance';
      case 'retired':
        return 'Retiré';
      default:
        return status;
    }
  }

  Future<void> _updateStatus(
    BuildContext context,
    String newStatus,
  ) async {
    debugPrint(
        '🔄 _updateStatus appelé avec status: $newStatus pour device ${widget.deviceId}');
    if (!mounted) return;

    debugPrint(
        '🔄 Mise à jour du statut: $newStatus pour device ${widget.deviceId}');

    // Afficher un indicateur de chargement
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      final apiService = ref.read(apiServiceProvider);
      // S'assurer que le token est chargé
      await _ensureTokenLoaded(apiService);
      debugPrint(
          '📡 Appel API: updateDevice(${widget.deviceId}, status: $newStatus)');
      await apiService.updateDevice(widget.deviceId, status: newStatus);
      debugPrint('✅ Statut mis à jour avec succès');

      if (!mounted) return;

      // Fermer le dialogue de chargement
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      if (!mounted) return;

      // Rafraîchir les données AVANT d'afficher le SnackBar
      debugPrint('🔄 Invalidation des providers...');
      ref.invalidate(deviceDetailProvider(widget.deviceId));
      ref.invalidate(devicesProvider);
      debugPrint('✅ Providers invalidés, l\'écran devrait se rafraîchir');

      // Attendre un peu pour que l'invalidation prenne effet
      await Future.delayed(const Duration(milliseconds: 100));

      if (!mounted) return;

      _showSnackBar(
        'Statut mis à jour: ${_getStatusLabel(newStatus)}',
        backgroundColor: Colors.green,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ Erreur lors de la mise à jour du statut: $e');
      debugPrint('Stack trace: $stackTrace');
      if (!mounted) return;

      // Fermer le dialogue de chargement s'il est ouvert
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      if (!mounted) return;

      _showSnackBar(
        'Erreur lors de la mise à jour: ${e.toString()}',
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
      );
    }
  }

  Future<void> _unassignDevice(BuildContext context) async {
    debugPrint('🔄 Désassignation du device ${widget.deviceId}');

    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Désassigner le patient'),
        content: const Text(
          'Êtes-vous sûr de vouloir désassigner ce patient de cet appareil ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (confirmed != true) {
      debugPrint('❌ Désassignation annulée par l\'utilisateur');
      return;
    }

    // Afficher un indicateur de chargement
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    try {
      final apiService = ref.read(apiServiceProvider);
      // S'assurer que le token est chargé
      await _ensureTokenLoaded(apiService);
      debugPrint('📡 Appel API: unassignDevice(${widget.deviceId})');
      await apiService.unassignDevice(widget.deviceId);
      debugPrint('✅ Patient désassigné avec succès');

      if (!mounted) return;

      // Fermer le dialogue de chargement
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      if (!mounted) return;

      // Rafraîchir les données AVANT d'afficher le SnackBar
      debugPrint('🔄 Invalidation des providers après désassignation...');
      ref.invalidate(deviceDetailProvider(widget.deviceId));
      ref.invalidate(devicesProvider);
      debugPrint('✅ Providers invalidés après désassignation');

      // Attendre un peu pour que l'invalidation prenne effet
      await Future.delayed(const Duration(milliseconds: 100));

      if (!mounted) return;

      _showSnackBar(
        'Patient désassigné avec succès',
        backgroundColor: Colors.green,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ Erreur lors de la désassignation: $e');
      debugPrint('Stack trace: $stackTrace');

      if (!mounted) return;

      // Fermer le dialogue de chargement s'il est ouvert
      try {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      } catch (navError) {
        debugPrint('⚠️ Erreur lors de la fermeture du dialogue: $navError');
      }

      if (!mounted) return;

      // Extraire un message d'erreur plus lisible
      String errorMessage = 'Erreur lors de la désassignation';
      final errorStr = e.toString();
      if (errorStr.contains('No route to host') ||
          errorStr.contains('connection')) {
        errorMessage =
            'Impossible de se connecter au serveur. Vérifiez votre connexion réseau.';
      } else if (errorStr.contains('timeout')) {
        errorMessage =
            'Timeout de connexion. Le serveur met trop de temps à répondre.';
      } else if (errorStr.contains('Exception:')) {
        errorMessage = errorStr.replaceAll('Exception: ', '');
      } else {
        errorMessage = errorStr;
      }

      _showSnackBar(
        errorMessage,
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
      );
    }
  }

  Future<void> _assignDevice(BuildContext context) async {
    debugPrint('🔄 Assignation du device ${widget.deviceId}');

    if (!mounted) return;

    // Afficher un indicateur de chargement
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      // Récupérer la liste des patients
      final apiService = ref.read(apiServiceProvider);
      // S'assurer que le token est chargé
      await _ensureTokenLoaded(apiService);
      debugPrint('📡 Appel API: getUsers(role: patient)');
      final patients = await apiService.getUsers(role: 'patient');
      debugPrint('✅ ${patients.length} patients récupérés');

      if (!mounted) return;
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(); // Fermer le dialogue de chargement
      }

      if (patients.isEmpty) {
        if (mounted) {
          _showSnackBar(
            'Aucun patient disponible',
            backgroundColor: Colors.orange,
          );
        }
        return;
      }

      // Afficher un dialogue de sélection
      final selectedPatient = await showDialog<User>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Sélectionner un patient'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: patients.length,
              itemBuilder: (context, index) {
                final patient = patients[index];
                return ListTile(
                  leading: CircleAvatar(
                    child: Text(
                      patient.firstName[0].toUpperCase(),
                    ),
                  ),
                  title: Text('${patient.firstName} ${patient.lastName}'),
                  subtitle: Text(patient.email),
                  onTap: () {
                    Navigator.of(context).pop(patient);
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
          ],
        ),
      );

      if (!mounted) return;

      if (selectedPatient == null) {
        debugPrint('❌ Aucun patient sélectionné');
        return;
      }

      if (!mounted) return;

      debugPrint(
          '👤 Patient sélectionné: ${selectedPatient.id} - ${selectedPatient.firstName} ${selectedPatient.lastName}');

      // Afficher un indicateur de chargement pendant l'assignation
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      // Assigner le device au patient sélectionné
      // S'assurer que le token est chargé
      await _ensureTokenLoaded(apiService);
      debugPrint(
          '📡 Appel API: assignDeviceToPatient(${widget.deviceId}, ${selectedPatient.id})');
      await apiService.assignDeviceToPatient(
        widget.deviceId,
        selectedPatient.id,
      );
      debugPrint('✅ Device assigné avec succès');

      if (!mounted) return;

      // Fermer le dialogue de chargement
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      if (!mounted) return;

      _showSnackBar(
        'Device assigné à ${selectedPatient.firstName} ${selectedPatient.lastName}',
        backgroundColor: Colors.green,
      );

      // Rafraîchir les données
      ref.invalidate(deviceDetailProvider(widget.deviceId));
      ref.invalidate(devicesProvider);
    } catch (e, stackTrace) {
      debugPrint('❌ Erreur lors de l\'assignation: $e');
      debugPrint('Stack trace: $stackTrace');
      if (!mounted) return;

      // Fermer le dialogue de chargement s'il est ouvert
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      if (!mounted) return;

      _showSnackBar(
        'Erreur: ${e.toString()}',
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
      );
    }
  }
}
