import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/dashboard_provider.dart';
import '../providers/auth_provider.dart';
import '../models/device.dart';
import '../models/user.dart';
import '../widgets/error_widget.dart';
import 'patient_comments_screen.dart';
import 'create_edit_patient_screen.dart';
import 'admin_raw_data_screen.dart';
import 'patient_wound_status_screen.dart';

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
    final authState = ref.watch(authProvider);
    final canToggleAccounts = authState.user?.isAdmin ?? false;
    final isAdmin = authState.user?.isAdmin ?? false;
    final isMedecin = authState.user?.isMedecin ?? false;
    final patientMedecinAsync =
        ref.watch(patientMedecinProvider(widget.patientId));
    final patientDevicesAsync = ref.watch(
      patientDevicesProvider(widget.patientId),
    );

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

                      if (canToggleAccounts) ...[
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(
                                  patient.isActive ? Icons.toggle_off : Icons.toggle_on,
                                  size: 32,
                                ),
                                color: patient.isActive ? Colors.orange : Colors.green,
                                tooltip: patient.isActive
                                    ? patient.isMedecin
                                        ? 'Désactiver le médecin'
                                        : 'Désactiver le patient'
                                    : patient.isMedecin
                                        ? 'Activer le médecin'
                                        : 'Activer le patient',
                                onPressed: () => _toggleAccountStatus(
                                  context,
                                  ref,
                                  patient,
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_forever,
                                  size: 32,
                                ),
                                color: Colors.red[700],
                                tooltip: patient.isMedecin
                                    ? 'Supprimer définitivement le médecin'
                                    : 'Supprimer définitivement le patient',
                                onPressed: () => _hardDeleteAccount(
                                  context,
                                  ref,
                                  patient,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

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
                      if (canToggleAccounts &&
                          patient.role.toLowerCase() == 'patient') ...[
                        const SizedBox(height: 24),
                        Text(
                          'Médecin assigné',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 12),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                patientMedecinAsync.when(
                                  loading: () => const SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: CircularProgressIndicator(strokeWidth: 3),
                                  ),
                                  error: (e, _) => Text(
                                    'Erreur lors du chargement du médecin assigné',
                                    style: TextStyle(color: Colors.red[700]),
                                  ),
                                  data: (data) {
                                    // "data == null" => aucun médecin assigné
                                    if (data == null || data['medecin'] == null) {
                                      final medecins = patients
                                          .where((u) =>
                                              u.role.toLowerCase() == 'medecin')
                                          .toList();

                                      return Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Expanded(
                                            child: Text(
                                              'Aucun médecin assigné',
                                              style: TextStyle(color: Colors.grey),
                                            ),
                                          ),
                                          ElevatedButton.icon(
                                            onPressed: () async {
                                              if (medecins.isEmpty) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                        'Aucun médecin disponible'),
                                                    backgroundColor:
                                                        Colors.orange,
                                                  ),
                                                );
                                                return;
                                              }

                                              User? selectedMedecin =
                                                  medecins.first;

                                              await showDialog<void>(
                                                context: context,
                                                builder: (ctx) =>
                                                    StatefulBuilder(
                                                  builder: (ctx, setStateDialog) {
                                                    return AlertDialog(
                                                      title: const Text(
                                                          'Assigner un médecin'),
                                                      content:
                                                          DropdownButtonFormField<User>(
                                                        value: selectedMedecin,
                                                        decoration:
                                                            const InputDecoration(
                                                          labelText: 'Médecin',
                                                        ),
                                                        items: medecins
                                                            .map(
                                                              (m) =>
                                                                  DropdownMenuItem<User>(
                                                                value: m,
                                                                child: Text(
                                                                  '${m.firstName} ${m.lastName}',
                                                                ),
                                                              ),
                                                            )
                                                            .toList(),
                                                        onChanged: (v) {
                                                          setStateDialog(() {
                                                            selectedMedecin = v;
                                                          });
                                                        },
                                                      ),
                                                      actions: [
                                                        TextButton(
                                                          onPressed: () {
                                                            Navigator.of(ctx)
                                                                .pop();
                                                          },
                                                          child: const Text(
                                                              'Annuler'),
                                                        ),
                                                        ElevatedButton(
                                                          onPressed: selectedMedecin ==
                                                                  null
                                                              ? null
                                                              : () async {
                                                                  Navigator.of(ctx)
                                                                      .pop();
                                                                  try {
                                                                    final apiService =
                                                                        ref.read(apiServiceProvider);
                                                                    await apiService.assignPatientToMedecin(
                                                                      patientId: patient.id,
                                                                      medecinId: selectedMedecin!.id,
                                                                    );
                                                                    ref.invalidate(
                                                                        patientMedecinProvider(
                                                                            patient.id));
                                                                    ref.invalidate(
                                                                        patientsProvider);
                                                                    if (!context
                                                                        .mounted) {
                                                                      return;
                                                                    }
                                                                    ScaffoldMessenger.of(
                                                                            context)
                                                                        .showSnackBar(
                                                                      const SnackBar(
                                                                        content: Text(
                                                                            'Médecin assigné avec succès'),
                                                                        backgroundColor:
                                                                            Colors.green,
                                                                      ),
                                                                    );
                                                                  } catch (e) {
                                                                    ErrorSnackBar.show(
                                                                      context,
                                                                      'Erreur lors de l’assignation',
                                                                      suggestions: [
                                                                        e.toString().replaceAll('Exception: ', ''),
                                                                        'Vérifiez votre connexion internet',
                                                                      ],
                                                                    );
                                                                  }
                                                                },
                                                          style: ElevatedButton
                                                              .styleFrom(
                                                            backgroundColor:
                                                                Theme.of(context)
                                                                    .primaryColor,
                                                            foregroundColor:
                                                                Colors.white,
                                                          ),
                                                          child: const Text(
                                                              'Assigner'),
                                                        ),
                                                      ],
                                                    );
                                                  },
                                                ),
                                              );
                                            },
                                            icon: const Icon(Icons.person_add),
                                            label: const Text(
                                                'Assigner un médecin'),
                                          ),
                                        ],
                                      );
                                    }

                                    final medecinJson =
                                        data['medecin'] as Map<String, dynamic>;
                                    final medecin =
                                        User.fromJson(medecinJson);

                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                '${medecin.firstName} ${medecin.lastName}',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                ),
                                              ),
                                            ),
                                            if (canToggleAccounts) ...[
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.link_off,
                                                  size: 20,
                                                ),
                                                tooltip:
                                                    'Désassigner le médecin',
                                                onPressed: () async {
                                                  final confirmed =
                                                      await showDialog<bool>(
                                                    context: context,
                                                    builder: (ctx) =>
                                                        AlertDialog(
                                                      title: const Text(
                                                          'Désassigner un médecin'),
                                                      content: Text(
                                                        'Voulez-vous désassigner ${medecin.firstName} ${medecin.lastName} du patient ${patient.fullName} ?',
                                                      ),
                                                      actions: [
                                                        TextButton(
                                                          onPressed: () {
                                                            Navigator.of(ctx)
                                                                .pop(false);
                                                          },
                                                          child:
                                                              const Text('Annuler'),
                                                        ),
                                                        ElevatedButton(
                                                          onPressed: () {
                                                            Navigator.of(ctx)
                                                                .pop(true);
                                                          },
                                                          style:
                                                              ElevatedButton
                                                                  .styleFrom(
                                                            backgroundColor:
                                                                Colors.orange,
                                                            foregroundColor:
                                                                Colors.white,
                                                          ),
                                                          child: const Text(
                                                              'Désassigner'),
                                                        ),
                                                      ],
                                                    ),
                                                  );

                                                  if (confirmed != true ||
                                                      !context.mounted) {
                                                    return;
                                                  }

                                                  try {
                                                    final apiService =
                                                        ref.read(apiServiceProvider);
                                                    await apiService
                                                        .unassignPatientFromMedecin(
                                                      patientId: patient.id,
                                                      medecinId: medecin.id,
                                                    );

                                                    ref.invalidate(
                                                      patientMedecinProvider(
                                                        patient.id,
                                                      ),
                                                    );
                                                    ref.invalidate(patientsProvider);

                                                    if (!context.mounted) {
                                                      return;
                                                    }
                                                    ScaffoldMessenger.of(context)
                                                        .showSnackBar(
                                                      const SnackBar(
                                                        content: Text(
                                                          'Médecin désassigné avec succès',
                                                        ),
                                                        backgroundColor:
                                                            Colors.green,
                                                      ),
                                                    );
                                                  } catch (e) {
                                                    if (!context.mounted) {
                                                      return;
                                                    }
                                                    ErrorSnackBar.show(
                                                      context,
                                                      'Erreur lors de la désassignation',
                                                      suggestions: [
                                                        e.toString().replaceAll(
                                                            'Exception: ', ''),
                                                        'Vérifiez votre connexion internet',
                                                      ],
                                                    );
                                                  }
                                                },
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        const Text(
                                          'Médecin assigné',
                                          style: TextStyle(color: Colors.grey),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
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
                          child: patientDevicesAsync.when(
                            loading: () => const SizedBox(
                              height: 44,
                              child: Center(
                                child: CircularProgressIndicator(strokeWidth: 3),
                              ),
                            ),
                            error: (e, _) => Text(
                              'Erreur lors du chargement des dispositifs',
                              style: TextStyle(color: Colors.red[700]),
                            ),
                            data: (devices) {
                              if (devices.isEmpty) {
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.blue[100],
                                    child: Icon(
                                      Icons.bluetooth,
                                      color: Colors.blue[700],
                                    ),
                                  ),
                                  title: const Text('Pansement connecté'),
                                  subtitle: const Text('Aucun dispositif assigné'),
                                  trailing: ElevatedButton(
                                    onPressed: () => _showAssignDeviceDialog(
                                        context, ref, patient.id),
                                    child: const Text('Assigner'),
                                  ),
                                );
                              }

                              return Column(
                                children: [
                                  for (final device in devices) ...[
                                    ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: Colors.blue[100],
                                        child: Icon(
                                          Icons.bluetooth,
                                          color: Colors.blue[700],
                                        ),
                                      ),
                                      title: Text(device.serialNumber),
                                      subtitle: Text('Modèle: ${device.model}'),
                                      trailing: ElevatedButton(
                                        onPressed: () => _showAssignDeviceDialog(
                                            context, ref, patient.id),
                                        child: const Text('Assigner'),
                                      ),
                                    ),
                                  ],
                                ],
                              );
                            },
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (isAdmin) ...[
                                Text(
                                  'Données brutes',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 10),
                                ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => AdminRawDataScreen(
                                          patient: patient,
                                        ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.table_chart),
                                  label: const Text(
                                    'Voir les valeurs brutes',
                                  ),
                                ),
                                const SizedBox(height: 6),
                              ] else if (isMedecin) ...[
                                Text(
                                  'État de la plaie',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 10),
                                ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => PatientWoundStatusScreen(
                                          patient: patient,
                                          forMedecin: true,
                                        ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.show_chart),
                                  label: const Text(
                                    'Voir l\'état complet',
                                  ),
                                ),
                              ] else ...[
                                Center(
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.timeline,
                                        size: 64,
                                        color: Colors.grey[400],
                                      ),
                                      const SizedBox(height: 16),
                                      const Text(
                                        'Historique disponible côté admin/médecin',
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: Colors.grey,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
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

  Future<void> _toggleAccountStatus(
    BuildContext context,
    WidgetRef ref,
    User target,
  ) async {
    final currentUser = ref.read(authProvider).user;
    if (currentUser?.isAdmin != true) return;

    final newStatus = !target.isActive;
    final roleLabel = target.isMedecin ? 'médecin' : 'patient';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(newStatus
            ? 'Activer le $roleLabel'
            : 'Désactiver le $roleLabel'),
        content: Text(
          'Êtes-vous sûr de vouloir ${newStatus ? 'activer' : 'désactiver'} $roleLabel ${target.fullName} ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: newStatus ? Colors.green : Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: Text(newStatus ? 'Activer' : 'Désactiver'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final apiService = ref.read(apiServiceProvider);
      await apiService.updateUser(
        userId: target.id,
        isActive: newStatus,
      );

      if (!mounted) return;
      Navigator.pop(context); // Fermer le dialog de chargement
      ref.invalidate(patientsProvider);
      // Les KPI "Total Utilisateurs" / "Utilisateurs Actifs" dépendent de l'état is_active.
      // On invalide explicitement pour refléter le changement sur la dashboard admin immédiatement.
      ref.invalidate(dashboardStatsProvider);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${roleLabel[0].toUpperCase()}${roleLabel.substring(1)} ${newStatus ? 'activé' : 'désactivé'} avec succès.',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Fermer le dialog de chargement

      ErrorSnackBar.show(
        context,
        'Erreur lors du changement de statut',
        suggestions: [
          e.toString().replaceAll('Exception: ', ''),
          'Vérifiez votre connexion internet',
        ],
      );
    }
  }

  Future<void> _hardDeleteAccount(
    BuildContext context,
    WidgetRef ref,
    User target,
  ) async {
    final currentUser = ref.read(authProvider).user;
    if (currentUser?.isAdmin != true) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Suppression définitive'),
        content: Text(
          'Êtes-vous sûr de vouloir supprimer définitivement ce compte ${target.isMedecin ? 'médecin' : 'patient'} ?\n\nCette action est irréversible.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final apiService = ref.read(apiServiceProvider);
      await apiService.deleteUserHard(target.id);

      if (!mounted) return;
      Navigator.pop(context); // fermer le dialog de chargement

      // Rafraîchir et fermer la page de détail.
      ref.invalidate(patientsProvider);
      // Les KPI dashboard admin doivent se mettre à jour après une suppression hard.
      ref.invalidate(dashboardStatsProvider);
      if (context.mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // fermer le dialog de chargement

      ErrorSnackBar.show(
        context,
        'Erreur lors de la suppression définitive',
        suggestions: [
          e.toString().replaceAll('Exception: ', ''),
          'Vérifiez votre connexion internet',
        ],
      );
    }
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
