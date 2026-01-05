import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/api_service.dart';
import '../providers/auth_provider.dart';
import '../providers/dashboard_provider.dart';
import '../models/device.dart';
import '../models/user.dart';

/// Provider pour les détails d'un device
final deviceDetailProvider =
    FutureProvider.family<Device, String>((ref, deviceId) async {
  final apiService = ref.watch(apiServiceProvider);
  const storage = FlutterSecureStorage();
  final token = await storage.read(key: 'access_token');
  if (token != null) {
    apiService.setToken(token);
  }
  return await apiService.getDevice(deviceId);
});

class DeviceDetailScreen extends ConsumerStatefulWidget {
  final String deviceId;

  const DeviceDetailScreen({
    super.key,
    required this.deviceId,
  });

  @override
  ConsumerState<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends ConsumerState<DeviceDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final deviceAsync = ref.watch(deviceDetailProvider(widget.deviceId));
    final currentUser = ref.watch(authProvider).user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Détails de l\'appareil'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(deviceDetailProvider(widget.deviceId));
            },
          ),
        ],
      ),
      body: deviceAsync.when(
        data: (device) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Carte principale du device
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 30,
                            backgroundColor: _getStatusColor(device.status),
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
                                      .headlineSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _getStatusColor(device.status)
                                        .withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: _getStatusColor(device.status),
                                    ),
                                  ),
                                  child: Text(
                                    _getStatusLabel(device.status),
                                    style: TextStyle(
                                      color: _getStatusColor(device.status),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 32),
                      _buildInfoRow('Modèle', device.model),
                      if (device.firmwareVersion != null)
                        _buildInfoRow('Firmware', device.firmwareVersion!),
                      if (device.batteryLevel != null)
                        _buildInfoRow(
                          'Batterie',
                          '${device.batteryLevel}%',
                          icon: Icons.battery_charging_full,
                          color: _getBatteryColor(device.batteryLevel!),
                        ),
                      if (device.patientName != null)
                        _buildInfoRow(
                          'Patient assigné',
                          device.patientName!,
                          icon: Icons.person,
                          color: Colors.blue,
                        ),
                      if (device.assignedAt != null)
                        _buildInfoRow(
                          'Assigné le',
                          DateFormat('dd/MM/yyyy à HH:mm')
                              .format(device.assignedAt!),
                          icon: Icons.calendar_today,
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Actions (Admin uniquement)
              if (currentUser?.role == 'admin') ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Actions',
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        const SizedBox(height: 16),
                        if (device.patientId == null)
                          ElevatedButton.icon(
                            onPressed: () => _showAssignDialog(context, device),
                            icon: const Icon(Icons.person_add),
                            label: const Text('Assigner à un patient'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.all(16),
                            ),
                          )
                        else
                          OutlinedButton.icon(
                            onPressed: () => _unassignDevice(context, device),
                            icon: const Icon(Icons.person_remove),
                            label: const Text('Retirer l\'assignation'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.all(16),
                            ),
                          ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: () => _showStatusDialog(context, device),
                          icon: const Icon(Icons.edit),
                          label: const Text('Modifier le statut'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.all(16),
                            backgroundColor: Colors.orange,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
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
                  style: TextStyle(color: Colors.grey[600]),
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

  Widget _buildInfoRow(String label, String value,
      {IconData? icon, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 8),
          ],
          Text(
            '$label: ',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.grey[700],
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: color),
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

  Color _getBatteryColor(int level) {
    if (level > 50) return Colors.green;
    if (level > 20) return Colors.orange;
    return Colors.red;
  }

  void _showAssignDialog(BuildContext context, Device device) async {
    final apiService = ref.read(apiServiceProvider);
    // Utiliser patientsOnlyProvider pour n'avoir que les patients (pas les médecins)
    final patientsAsync = ref.read(patientsOnlyProvider.future);

    try {
      final patients = await patientsAsync;
      if (patients.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Aucun patient disponible'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      String? selectedPatientId;

      await showDialog(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Assigner à un patient'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: patients.length,
                  itemBuilder: (context, index) {
                    final patient = patients[index];
                    return RadioListTile<String>(
                      title: Text(patient.fullName),
                      subtitle: Text(patient.email),
                      value: patient.id,
                      groupValue: selectedPatientId,
                      onChanged: (value) {
                        setDialogState(() {
                          selectedPatientId = value;
                        });
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
                ElevatedButton(
                  onPressed: selectedPatientId == null
                      ? null
                      : () async {
                          try {
                            await apiService.assignDeviceToPatient(
                              device.id,
                              selectedPatientId!,
                            );
                            if (context.mounted) {
                              Navigator.of(context).pop();
                              ref.invalidate(
                                  deviceDetailProvider(widget.deviceId));
                              ref.invalidate(devicesProvider);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Appareil assigné avec succès'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Erreur: ${e.toString()}'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                  child: const Text('Assigner'),
                ),
              ],
            );
          },
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _unassignDevice(BuildContext context, Device device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Retirer l\'assignation'),
        content: const Text(
          'Êtes-vous sûr de vouloir retirer cet appareil du patient ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Retirer'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final apiService = ref.read(apiServiceProvider);
        await apiService.unassignDevice(device.id);
        if (context.mounted) {
          ref.invalidate(deviceDetailProvider(widget.deviceId));
          ref.invalidate(devicesProvider);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Assignation retirée avec succès'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erreur: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _showStatusDialog(BuildContext context, Device device) {
    String? tempStatus = device.status;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Modifier le statut'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<String>(
                  title: const Text('Actif'),
                  value: 'active',
                  groupValue: tempStatus,
                  onChanged: (value) {
                    setDialogState(() {
                      tempStatus = value;
                    });
                  },
                ),
                RadioListTile<String>(
                  title: const Text('Inactif'),
                  value: 'inactive',
                  groupValue: tempStatus,
                  onChanged: (value) {
                    setDialogState(() {
                      tempStatus = value;
                    });
                  },
                ),
                RadioListTile<String>(
                  title: const Text('Maintenance'),
                  value: 'maintenance',
                  groupValue: tempStatus,
                  onChanged: (value) {
                    setDialogState(() {
                      tempStatus = value;
                    });
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Annuler'),
              ),
              ElevatedButton(
                onPressed: tempStatus == device.status
                    ? null
                    : () async {
                        try {
                          final apiService = ref.read(apiServiceProvider);
                          await apiService.updateDevice(device.id,
                              status: tempStatus);
                          if (context.mounted) {
                            Navigator.of(context).pop();
                            ref.invalidate(
                                deviceDetailProvider(widget.deviceId));
                            ref.invalidate(devicesProvider);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Statut modifié avec succès'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Erreur: ${e.toString()}'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                child: const Text('Appliquer'),
              ),
            ],
          );
        },
      ),
    );
  }
}
