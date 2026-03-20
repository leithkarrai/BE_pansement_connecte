import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../providers/dashboard_provider.dart';
import '../providers/measurements_provider.dart';
import '../widgets/stat_card.dart';
import 'login_screen.dart';
import 'patient_detail_screen.dart';
import 'patient_wound_status_screen.dart';
import 'alerts_screen.dart';
import 'settings_screen.dart';

/// Dashboard Patient - Vue personnelle
class PatientDashboardScreen extends ConsumerWidget {
  const PatientDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final user = authState.user;

    // Si l'utilisateur est un patient, utiliser son propre ID
    final patientId = user?.id;

    // Provider stats créé systématiquement pour garder un build stable.
    final statsAsync = ref.watch(
      patientStatsProvider({
        'patientId': patientId ?? '',
        'days': 7,
      }),
    );
    final devicesAsync =
        patientId != null ? ref.watch(patientDevicesProvider(patientId)) : null;

    // Dashboard patient: espace personnel (infos, device, état de plaie, mesures récentes).
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Mon Espace Patient',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_active),
            tooltip: 'Alertes',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AlertsScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Paramètres',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const SettingsScreen(),
                ),
              );
            },
          ),
          if (user != null) ...[
            // Avatar et nom (caché sur petits écrans)
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth > 600) {
                  // Écran large : afficher avatar + nom
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: Colors.white,
                          child: Text(
                            user.firstName[0].toUpperCase(),
                            style: TextStyle(
                              color: Theme.of(context).primaryColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                user.fullName,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'Patient',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey[600],
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                } else {
                  // Écran petit : afficher seulement l'avatar
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.white,
                      child: Text(
                        user.firstName[0].toUpperCase(),
                        style: TextStyle(
                          color: Theme.of(context).primaryColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  );
                }
              },
            ),
            // Bouton de déconnexion
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Déconnexion',
              onPressed: () async {
                await ref.read(authProvider.notifier).logout();
                if (context.mounted) {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
                }
              },
            ),
          ],
        ],
      ),
      body: patientId == null
          ? const Center(child: Text('Erreur: Utilisateur non identifié'))
          : RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(
                    patientStatsProvider({'patientId': patientId, 'days': 7}));
                ref.invalidate(patientDevicesProvider(patientId));
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Informations personnelles
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Mes informations',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            const SizedBox(height: 16),
                            if (user != null) ...[
                              _buildInfoRow(
                                  Icons.person, 'Nom complet', user.fullName),
                              if (user.phone != null)
                                _buildInfoRow(
                                    Icons.phone, 'Téléphone', user.phone!),
                              if (user.bloodType != null)
                                _buildInfoRow(Icons.bloodtype, 'Groupe sanguin',
                                    user.bloodType!),
                            ],
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // État complet du patient (état de la plaie, résumé, évolution)
                    if (user != null)
                      Card(
                        elevation: 2,
                        child: InkWell(
                          onTap: () {
                            final bool forMedecin =
                                user.role.toLowerCase() != 'patient';
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => PatientWoundStatusScreen(
                                  patient: user,
                                  forMedecin: forMedecin,
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
                                    color: Theme.of(context)
                                        .primaryColor
                                        .withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    Icons.favorite,
                                    color: Theme.of(context).primaryColor,
                                    size: 32,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Mon état complet',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'État de la plaie, résumé et évolution',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right),
                              ],
                            ),
                          ),
                        ),
                      ),

                    if (user != null) const SizedBox(height: 24),

                    // Appareils assignés
                    Text(
                      devicesAsync?.value?.isEmpty ?? true
                          ? 'Mon appareil'
                          : 'Mes appareils (${devicesAsync?.value?.length ?? 0})',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 16),

                    devicesAsync?.when(
                          data: (devices) {
                            if (devices.isEmpty) {
                              return Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      Icon(Icons.info_outline,
                                          color: Colors.orange),
                                      const SizedBox(width: 12),
                                      const Expanded(
                                        child: Text(
                                            'Aucun appareil assigné pour le moment'),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }

                            return Column(
                              children: devices.map((device) {
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(Icons.devices,
                                                color: Theme.of(context)
                                                    .primaryColor),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                device.serialNumber,
                                                style: const TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            if (device.batteryLevel != null)
                                              Chip(
                                                label: Text(
                                                    '${device.batteryLevel}%'),
                                                avatar: const Icon(
                                                  Icons.battery_charging_full,
                                                  size: 18,
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Text('Modèle: ${device.model}'),
                                        Text('Statut: ${device.status}'),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            );
                          },
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (error, stack) => Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text('Erreur: $error'),
                            ),
                          ),
                        ) ??
                        const SizedBox(),

                    const SizedBox(height: 24),

                    // Statistiques
                    Text(
                      'Mes statistiques',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 16),

                    statsAsync.when(
                      data: (stats) {
                        // S'assurer que stats n'est jamais null
                        final safeStats = stats;
                        return GridView.count(
                          crossAxisCount: 2,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                          childAspectRatio: 1.2,
                          children: [
                            StatCard(
                              title: 'Mesures Total',
                              value:
                                  safeStats['total_measurements']?.toString() ??
                                      '0',
                              icon: Icons.analytics,
                              color: Colors.blue,
                            ),
                            StatCard(
                              title: 'Dernière mesure',
                              value: () {
                                final lastMeasurement =
                                    safeStats['last_measurement'];
                                if (lastMeasurement == null) return 'Aucune';

                                final lastDate = lastMeasurement is DateTime
                                    ? lastMeasurement
                                    : DateTime.tryParse(
                                        lastMeasurement.toString());

                                if (lastDate == null) return 'Aucune';

                                final now = DateTime.now();
                                final today =
                                    DateTime(now.year, now.month, now.day);
                                final lastDay = DateTime(lastDate.year,
                                    lastDate.month, lastDate.day);

                                if (lastDay == today) {
                                  return 'Aujourd\'hui';
                                } else if (lastDay ==
                                    today.subtract(const Duration(days: 1))) {
                                  return 'Hier';
                                } else {
                                  final diff = now.difference(lastDate).inDays;
                                  return '$diff jour${diff > 1 ? 's' : ''}';
                                }
                              }(),
                              icon: Icons.access_time,
                              color: Colors.green,
                            ),
                          ],
                        );
                      },
                      loading: () => const Center(
                        child: CircularProgressIndicator(),
                      ),
                      error: (error, stack) {
                        // En cas d'erreur, afficher des stats vides au lieu d'une erreur
                        return GridView.count(
                          crossAxisCount: 2,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                          childAspectRatio: 1.2,
                          children: [
                            StatCard(
                              title: 'Mesures Total',
                              value: '0',
                              icon: Icons.analytics,
                              color: Colors.blue,
                            ),
                            StatCard(
                              title: 'Dernière mesure',
                              value: 'Aucune',
                              icon: Icons.access_time,
                              color: Colors.green,
                            ),
                          ],
                        );
                      },
                    ),

                    const SizedBox(height: 24),

                    // Bouton pour voir les détails
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  PatientDetailScreen(patientId: patientId),
                            ),
                          );
                        },
                        icon: const Icon(Icons.visibility),
                        label: const Text('Voir mes données détaillées'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 12),
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
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}
