import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../providers/dashboard_provider.dart';
import '../providers/alerts_provider.dart';
import '../providers/measurements_provider.dart';
import '../utils/wound_status_helper.dart';
import '../widgets/stat_card.dart';
import '../widgets/patient_list_tile.dart';
import 'patient_detail_screen.dart';
import 'devices_list_screen.dart';
import 'patient_wound_status_screen.dart';
import 'alerts_screen.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    // Rafraîchir les KPIs automatiquement (Total utilisateurs / Actifs / Alertes...).
    // Important: sans invalidation périodique, FutureProvider ne se recharge pas.
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      ref.invalidate(dashboardStatsProvider);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final user = authState.user;
    // Médecin/admin : forMedecin = true (courbe d'évolution sur l'écran plaie).
    // Patient : forMedecin = false (écran plaie sans courbe, carte d'état seule).
    final bool forMedecinScreen =
        user != null && user.role.toLowerCase() != 'patient';
    final statsAsync = ref.watch(dashboardStatsProvider);
    final patientsAsync = ref.watch(patientsProvider);
    final patientMeasurementsAsync = (user != null &&
            user.role.toLowerCase() == 'patient')
        ? ref.watch(patientMeasurementsProvider(user.id))
        : null;

    // Dashboard unifié:
    // - patient: vue personnelle (device + état plaie),
    // - admin/médecin: vue opérationnelle (utilisateurs, devices, alertes).
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: MediaQuery.of(context).size.width > 600 ? 24.0 : 10.0,
        right: MediaQuery.of(context).size.width > 600 ? 24.0 : 10.0,
        top: 10.0,
        bottom: 16.0, // Espace pour la Bottom Navigation Bar
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Titre
          Text(
            'Dashboard',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          const SizedBox(height: 12), // Réduit à 12

          // Bloc statistiques (cards) adapté au rôle.
          statsAsync.when(
            data: (stats) {
              // Affichage différent selon le rôle
              if (user?.role == 'patient') {
                // PATIENT : Afficher ses propres stats
                return GridView.count(
                  crossAxisCount:
                      MediaQuery.of(context).size.width > 800 ? 4 : 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 6,
                  childAspectRatio:
                      0.8, // Ratio très bas pour beaucoup plus de hauteur
                  children: [
                    StatCard(
                      title: 'Mon Pansement',
                      value:
                          stats['my_device'] == 1 ? 'Assigné' : 'Non assigné',
                      icon: Icons.medical_services,
                      color:
                          stats['my_device'] == 1 ? Colors.green : Colors.grey,
                    ),
                    StatCard(
                      title: 'Statut Device',
                      value: stats['device_status'] == 1 ? 'Actif' : 'Inactif',
                      icon: Icons.sensors,
                      color: stats['device_status'] == 1
                          ? Colors.green
                          : Colors.orange,
                    ),
                  ],
                );
              } else {
                // ADMIN/MÉDECIN : KPIs de supervision.
                final screenWidth = MediaQuery.of(context).size.width;
                final crossAxisCount =
                    screenWidth > 600 ? 2 : 2; // Toujours 2 colonnes sur mobile

                return GridView.count(
                  crossAxisCount: crossAxisCount,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 6,
                  childAspectRatio:
                      0.75, // Ratio très bas pour beaucoup plus de hauteur
                  children: [
                    StatCard(
                      title: 'Total Utilisateurs',
                      value: '${stats['total_patients'] ?? 0}',
                      icon: Icons.people,
                      color: Colors.blue,
                    ),
                    StatCard(
                      title: 'Utilisateurs Actifs',
                      value: '${stats['active_patients'] ?? 0}',
                      icon: Icons.verified_user,
                      color: Colors.green,
                    ),
                    StatCard(
                      title: 'Alertes',
                      value: '${stats['alerts_unacknowledged'] ?? stats['alerts'] ?? 0}',
                      icon: Icons.notifications_active,
                      color: Colors.red,
                      onTap: () {
                        ref.invalidate(alertsProvider);
                        ref.invalidate(dashboardStatsProvider);
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const AlertsScreen(),
                          ),
                        );
                      },
                    ),
                    if (user?.role == 'admin')
                      StatCard(
                        title: 'Devices Disponibles',
                        value: '${stats['available_devices'] ?? 0}',
                        icon: Icons.inventory,
                        color: Colors.purple,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const DevicesListScreen(),
                            ),
                          );
                        },
                      ),
                  ],
                );
              }
            },
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(32.0),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (error, stack) => Center(
              child: Text('Erreur: $error'),
            ),
          ),

          const SizedBox(height: 32),

          // Deuxième bloc: liste utilisateurs/profil selon rôle.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                user?.role == 'patient' ? 'Mon Profil' : 'Utilisateurs Récents',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              if (user?.role != 'patient')
                TextButton.icon(
                  onPressed: () {
                    // TODO: Navigation vers liste complète
                  },
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Voir tous'),
                ),
            ],
          ),
          const SizedBox(height: 16),

          patientsAsync.when(
            data: (patients) {
              if (patients.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      children: [
                        Icon(
                          Icons.people_outline,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          user?.role == 'patient'
                              ? 'Chargement...'
                              : 'Aucun utilisateur',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              // PATIENT: card profil + accès à l'écran détaillé d'état de la plaie.
              if (user != null && user.role.toLowerCase() == 'patient') {
                // Utiliser l'utilisateur connecté directement si la liste est vide
                final patient = patients.isNotEmpty
                    ? patients.firstWhere(
                        (p) => p.id == user.id,
                        orElse: () => user,
                      )
                    : user;

                return Column(
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 32,
                                  backgroundColor:
                                      Theme.of(context).primaryColor,
                                  child: Text(
                                    patient.firstName.isNotEmpty
                                        ? patient.firstName[0].toUpperCase()
                                        : 'P',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 24,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        patient.fullName,
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(patient.email),
                                      if (patient.phone != null &&
                                          patient.phone!.isNotEmpty)
                                        Text('📞 ${patient.phone}'),
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
                    // Résumé d'état calculé localement à partir des mesures patient.
                    if (patientMeasurementsAsync != null)
                      patientMeasurementsAsync.when(
                        data: (measurements) {
                          final status = calculateWoundStatus(measurements);
                          final displayLabel =
                              getWoundStatusDisplayLabel(status);
                          return Card(
                            elevation: 2,
                            child: InkWell(
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => PatientWoundStatusScreen(
                                      patient: patient,
                                      forMedecin: forMedecinScreen,
                                    ),
                                  ),
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: status.color.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(
                                        status.icon,
                                        color: status.color,
                                        size: 32,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'État de ma plaie',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: Theme.of(context)
                                                  .primaryColor,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '$displayLabel ${status.emoji}',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: status.color,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      Icons.chevron_right,
                                      color: Theme.of(context).primaryColor,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                        loading: () => Card(
                          elevation: 2,
                          child: InkWell(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => PatientWoundStatusScreen(
                                    patient: patient,
                                    forMedecin: forMedecinScreen,
                                  ),
                                ),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Row(
                                children: [
                                  Icon(Icons.favorite,
                                      color: Theme.of(context).primaryColor,
                                      size: 32),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'État de ma plaie',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: Theme.of(context)
                                                .primaryColor,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Chargement...',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(Icons.chevron_right,
                                      color: Theme.of(context).primaryColor),
                                ],
                              ),
                            ),
                          ),
                        ),
                        error: (_, __) => Card(
                          elevation: 2,
                          child: InkWell(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => PatientWoundStatusScreen(
                                    patient: patient,
                                    forMedecin: forMedecinScreen,
                                  ),
                                ),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Row(
                                children: [
                                  Icon(Icons.favorite,
                                      color: Theme.of(context).primaryColor,
                                      size: 32),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'État de ma plaie',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: Theme.of(context)
                                                .primaryColor,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Voir mon état complet',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(Icons.chevron_right,
                                      color: Theme.of(context).primaryColor),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              }

              // ADMIN et MÉDECIN : Afficher les 5 derniers patients
              final recentPatients = patients.take(5).toList();

              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: recentPatients.length,
                itemBuilder: (context, index) {
                  final patient = recentPatients[index];
                  return PatientListTile(
                    patient: patient,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PatientDetailScreen(
                            patientId: patient.id,
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(32.0),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (error, stack) => Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  children: [
                    Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
                    const SizedBox(height: 16),
                    Text('Erreur: $error'),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
