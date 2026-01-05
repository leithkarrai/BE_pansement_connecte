import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../providers/dashboard_provider.dart';
import '../widgets/stat_card.dart';
import '../widgets/patient_list_tile.dart';
import 'login_screen.dart';
import 'patient_detail_screen.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final user = authState.user;
    final statsAsync = ref.watch(dashboardStatsProvider);
    final patientsAsync = ref.watch(patientsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.medical_services),
            const SizedBox(width: 8),
            const Text('Pansement Connecté'),
          ],
        ),
        actions: [
          // Info utilisateur
          if (user != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.white,
                    child: Text(
                      user.firstName[0].toUpperCase(),
                      style: TextStyle(
                        color: Theme.of(context).primaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.fullName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        user.role.toUpperCase(),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[300],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

          // Bouton logout
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              }
            },
            tooltip: 'Déconnexion',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Titre
            Text(
              'Dashboard',
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 24),

            // Statistiques
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
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 2,
                    children: [
                      StatCard(
                        title: 'Mon Pansement',
                        value:
                            stats['my_device'] == 1 ? 'Assigné' : 'Non assigné',
                        icon: Icons.medical_services,
                        color: stats['my_device'] == 1
                            ? Colors.green
                            : Colors.grey,
                      ),
                      StatCard(
                        title: 'Statut Device',
                        value:
                            stats['device_status'] == 1 ? 'Actif' : 'Inactif',
                        icon: Icons.sensors,
                        color: stats['device_status'] == 1
                            ? Colors.green
                            : Colors.orange,
                      ),
                      StatCard(
                        title: 'Batterie',
                        value: '${stats['battery_level'] ?? 0}%',
                        icon: Icons.battery_charging_full,
                        color: Colors.blue,
                      ),
                      StatCard(
                        title: 'Mes Mesures',
                        value: '${stats['total_measurements'] ?? 0}',
                        icon: Icons.analytics,
                        color: Colors.purple,
                      ),
                    ],
                  );
                } else {
                  // ADMIN et MÉDECIN : Afficher stats globales
                  return GridView.count(
                    crossAxisCount:
                        MediaQuery.of(context).size.width > 1200 ? 4 : 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 2,
                    children: [
                      StatCard(
                        title: 'Total Patients',
                        value: '${stats['total_patients'] ?? 0}',
                        icon: Icons.people,
                        color: Colors.blue,
                      ),
                      StatCard(
                        title: 'Patients Actifs',
                        value: '${stats['active_patients'] ?? 0}',
                        icon: Icons.verified_user,
                        color: Colors.green,
                      ),
                      StatCard(
                        title: 'Devices Actifs',
                        value: '${stats['active_devices'] ?? 0}',
                        icon: Icons.sensors,
                        color: Colors.orange,
                      ),
                      if (user?.role == 'admin')
                        StatCard(
                          title: 'Devices Disponibles',
                          value: '${stats['available_devices'] ?? 0}',
                          icon: Icons.inventory,
                          color: Colors.purple,
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

            // Liste des patients
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  user?.role == 'patient' ? 'Mon Profil' : 'Patients Récents',
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
                                : 'Aucun patient',
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

                // PATIENT : Afficher son profil comme une card
                if (user?.role == 'patient') {
                  final patient = patients.first;
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 32,
                                backgroundColor: Theme.of(context).primaryColor,
                                child: Text(
                                  patient.firstName[0].toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      patient.fullName,
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(patient.email),
                                    if (patient.phone != null)
                                      Text('📞 ${patient.phone}'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
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
                      Icon(Icons.error_outline,
                          size: 48, color: Colors.red[300]),
                      const SizedBox(height: 16),
                      Text('Erreur: $error'),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
