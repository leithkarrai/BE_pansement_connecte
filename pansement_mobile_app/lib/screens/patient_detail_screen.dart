import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/dashboard_provider.dart';
import '../providers/auth_provider.dart';
import '../models/device.dart';
import '../widgets/error_widget.dart';
import 'patient_comments_screen.dart';
import 'create_edit_patient_screen.dart';

class PatientDetailScreen extends ConsumerStatefulWidget {
  final String patientId;

  const PatientDetailScreen({
    super.key,
    required this.patientId,
  });

  @override
  ConsumerState<PatientDetailScreen> createState() =>
      _PatientDetailScreenState();
}

class _PatientDetailScreenState extends ConsumerState<PatientDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final patientsAsync = ref.watch(patientsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Détails du patient'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () async {
              final patientsAsync = ref.read(patientsProvider);
              final patients = patientsAsync.value;
              if (patients == null) return;

              final patient = patients.firstWhere(
                (p) => p.id == widget.patientId,
                orElse: () => throw Exception('Patient non trouvé'),
              );

              if (!mounted) return;
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CreateEditPatientScreen(patient: patient),
                ),
              );
              // Rafraîchir les données si le patient a été modifié
              if (result == true && mounted) {
                // Le provider se rafraîchira automatiquement
                Navigator.pop(context, true); // Retourner à la liste
              }
            },
          ),
        ],
      ),
      body: patientsAsync.when(
        data: (patients) {
          final patient = patients.firstWhere(
            (p) => p.id == widget.patientId,
            orElse: () => throw Exception('Patient non trouvé'),
          );

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // En-tête avec avatar
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Theme.of(context).primaryColor,
                        Theme.of(context).primaryColor.withOpacity(0.7),
                      ],
                    ),
                  ),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 50,
                        backgroundColor: Colors.white,
                        child: Text(
                          _getInitials(patient.fullName),
                          style: TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        patient.fullName,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: patient.isActive
                              ? Colors.green[400]
                              : Colors.grey[400],
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.circle,
                              size: 10,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              patient.isActive ? 'ACTIF' : 'INACTIF',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Commentaires
                      Text(
                        'Commentaires médicaux',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 16),
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.comment),
                          title: const Text('Voir les commentaires'),
                          subtitle: const Text(
                              'Ajouter ou consulter les commentaires du médecin'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => PatientCommentsScreen(
                                  patientId: patient.id,
                                  patientName: patient.fullName,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Informations personnelles
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Informations personnelles',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              _buildInfoRow(
                                Icons.email,
                                'Email',
                                patient.email,
                              ),
                              if (patient.phone != null) ...[
                                const Divider(height: 24),
                                _buildInfoRow(
                                  Icons.phone,
                                  'Téléphone',
                                  patient.phone!,
                                ),
                              ],
                              if (patient.bloodType != null) ...[
                                const Divider(height: 24),
                                _buildInfoRow(
                                  Icons.bloodtype,
                                  'Groupe sanguin',
                                  patient.bloodType!,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Dispositifs médicaux
                      Text(
                        'Dispositifs médicaux',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Colors.blue[100],
                                  child: Icon(
                                    Icons.bluetooth,
                                    color: Colors.blue[700],
                                  ),
                                ),
                                title: const Text('Pansement connecté'),
                                subtitle:
                                    const Text('Aucun dispositif assigné'),
                                trailing: ElevatedButton(
                                  onPressed: () => _showAssignDeviceDialog(
                                      context, ref, patient.id),
                                  child: const Text('Assigner'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Historique des mesures
                      Text(
                        'Historique des mesures',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(
                                  Icons.timeline,
                                  size: 64,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Aucune mesure disponible',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Les mesures apparaîtront ici une fois qu\'un dispositif sera connecté',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey[500],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(),
        ),
        error: (error, stackTrace) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.red,
              ),
              const SizedBox(height: 16),
              Text(
                'Erreur: $error',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  ref.invalidate(patientsProvider);
                },
                child: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
  }

  Future<void> _showAssignDeviceDialog(
    BuildContext context,
    WidgetRef ref,
    String patientId,
  ) async {
    try {
      final apiService = ref.read(apiServiceProvider);

      // Charger les dispositifs disponibles (non assignés)
      final devices = await apiService.getDevices(status: 'available');
      final availableDevices =
          devices.where((d) => d.patientId == null).toList();

      if (!mounted) return;

      if (availableDevices.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Aucun dispositif disponible'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      Device? selectedDevice;

      await showDialog(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Assigner un dispositif'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: availableDevices.length,
                itemBuilder: (context, index) {
                  final device = availableDevices[index];
                  final isSelected = selectedDevice?.id == device.id;

                  return RadioListTile<Device>(
                    title: Text(device.serialNumber),
                    subtitle: Text('Modèle: ${device.model}'),
                    value: device,
                    groupValue: selectedDevice,
                    onChanged: (value) {
                      setDialogState(() {
                        selectedDevice = value;
                      });
                    },
                    selected: isSelected,
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Annuler'),
              ),
              ElevatedButton(
                onPressed: selectedDevice == null
                    ? null
                    : () async {
                        Navigator.pop(context);
                        await _assignDevice(
                            context, ref, patientId, selectedDevice!.id);
                      },
                child: const Text('Assigner'),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ErrorSnackBar.show(
          context,
          '❌ Erreur lors du chargement des dispositifs',
          suggestions: [
            e.toString().replaceAll('Exception: ', ''),
            'Vérifiez votre connexion internet',
          ],
        );
      }
    }
  }

  Future<void> _assignDevice(
    BuildContext context,
    WidgetRef ref,
    String patientId,
    String deviceId,
  ) async {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final apiService = ref.read(apiServiceProvider);
      await apiService.assignDeviceToPatient(deviceId, patientId);

      if (mounted) {
        Navigator.pop(context); // Fermer le dialog de chargement
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Dispositif assigné avec succès'),
            backgroundColor: Colors.green,
          ),
        );
        // Rafraîchir les données
        ref.invalidate(patientsProvider);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Fermer le dialog de chargement
        ErrorSnackBar.show(
          context,
          '❌ Erreur lors de l\'assignation',
          suggestions: [
            e.toString().replaceAll('Exception: ', ''),
            'Vérifiez votre connexion internet',
          ],
        );
      }
    }
  }
}
