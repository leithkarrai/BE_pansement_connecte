import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../providers/dashboard_provider.dart';
import '../providers/alerts_provider.dart';
import '../widgets/stat_card.dart';
import '../widgets/patient_list_tile.dart';
import 'login_screen.dart';
import 'patient_detail_screen.dart';
import 'patients_list_screen.dart';
import 'devices_list_screen.dart';
import 'alerts_screen.dart';
import 'settings_screen.dart';

/// Dashboard Administrateur - Vue complète du système
/// Actualisation automatique du compteur d'alertes toutes les 30 s + au retour sur l'app
class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen>
    with WidgetsBindingObserver {
  WidgetRef? _ref;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _ref?.invalidate(dashboardStatsProvider);
    _ref?.invalidate(alertsProvider);
    _ref?.invalidate(unacknowledgedAlertsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    _ref = ref;
    // Polling UI léger des indicateurs (stats/alertes) pendant l'affichage du dashboard.
    if (_refreshTimer == null && mounted) {
      _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted && _ref != null) {
          _ref!.invalidate(dashboardStatsProvider);
          _ref!.invalidate(alertsProvider);
          _ref!.invalidate(unacknowledgedAlertsProvider);
        }
      });
    }

    final authState = ref.watch(authProvider);
    final user = authState.user;
    final statsAsync = ref.watch(dashboardStatsProvider);
    final patientsAsync = ref.watch(patientsProvider);

    // Notification in-app quand de nouvelles alertes non acquittées apparaissent.
    ref.listen(unacknowledgedAlertsProvider, (previous, next) {
      next.whenData((alerts) {
        if (alerts.isNotEmpty && context.mounted) {
          final first = alerts.first as Map<String, dynamic>?;
          final msg = first?['title'] ?? 'Nouvelles mesures reçues';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              action: SnackBarAction(
                label: 'Voir',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AlertsScreen(),
                    ),
                  );
                },
              ),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      });
    });

    // Dashboard admin: supervision globale + accès rapide aux écrans de gestion.
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 8,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.admin_panel_settings, size: 18),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                'admin System',
                style: const TextStyle(fontSize: 15),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: ref.watch(unacknowledgedAlertsProvider).when(
                  data: (alerts) {
                    final count = alerts.length;
                    if (count > 0) {
                      return Badge(
                        label: Text(
                          count > 99 ? '99+' : '$count',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                          ),
                        ),
                        child: const Icon(Icons.notifications_active, size: 20),
                      );
                    }
                    return const Icon(Icons.notifications_active, size: 20);
                  },
                  loading: () => const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  error: (_, __) => const Icon(Icons.notifications_off, size: 20),
                ),
            tooltip: 'Alertes (nouvelles mesures)',
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: () {
              ref.invalidate(alertsProvider);
              ref.invalidate(unacknowledgedAlertsProvider);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AlertsScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings, size: 20),
            tooltip: 'Paramètres',
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const SettingsScreen(),
                ),
              );
            },
          ),
          if (user != null)
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: Colors.white,
                    child: Text(
                      user.firstName[0].toUpperCase(),
                      style: TextStyle(
                        color: Theme.of(context).primaryColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      'Administrateur',
                      style: TextStyle(
                        fontSize: 9,
                        color: Colors.grey[600],
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  const SizedBox(width: 2),
                  IconButton(
                    icon: const Icon(Icons.logout, size: 18),
                    tooltip: 'Déconnexion',
                    padding: const EdgeInsets.all(8),
                    constraints:
                        const BoxConstraints(minWidth: 36, minHeight: 36),
                    onPressed: () async {
                      await ref.read(authProvider.notifier).logout();
                      if (context.mounted) {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                              builder: (_) => const LoginScreen()),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(dashboardStatsProvider);
          ref.invalidate(patientsProvider);
          ref.invalidate(alertsProvider);
          ref.invalidate(unacknowledgedAlertsProvider);
          await ref.read(unacknowledgedAlertsProvider.future);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Statistiques globales
              Text(
                'Vue d\'ensemble du système',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),

              statsAsync.when(
                data: (stats) => GridView.count(
                  crossAxisCount: 4,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 1.2,
                  children: [
                    StatCard(
                      title: 'Total Utilisateurs',
                      value: stats['total_patients']?.toString() ?? '0',
                      icon: Icons.people,
                      color: Colors.blue,
                    ),
                    StatCard(
                      title: 'Total Médecins',
                      value: stats['total_doctors']?.toString() ?? '0',
                      icon: Icons.medical_services,
                      color: Colors.green,
                    ),
                    StatCard(
                      title: 'Appareils Actifs',
                      value: stats['active_devices']?.toString() ?? '0',
                      icon: Icons.devices,
                      color: Colors.orange,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const DevicesListScreen(),
                          ),
                        );
                      },
                    ),
                    StatCard(
                      title: 'Mesures Aujourd\'hui',
                      value: stats['today_measurements']?.toString() ?? '0',
                      icon: Icons.analytics,
                      color: Colors.purple,
                    ),
                    StatCard(
                      title: 'Alertes',
                      value: stats['alerts']?.toString() ?? '0',
                      icon: Icons.notifications_active,
                      color: Colors.red,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const AlertsScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
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
                    'Tous les utilisateurs',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  InkWell(
                    onTap: () {
                      debugPrint('🔍 Clic sur "Voir tout" détecté');
                      try {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const PatientsListScreen(),
                          ),
                        );
                        debugPrint('✅ Navigation lancée');
                      } catch (e) {
                        debugPrint('❌ Erreur: $e');
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Erreur: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Voir tout',
                          style: TextStyle(
                            color: Theme.of(context).primaryColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.arrow_forward,
                          color: Theme.of(context).primaryColor,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              patientsAsync.when(
                data: (patients) {
                  if (patients.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32.0),
                        child: Text('Aucun utilisateur trouvé'),
                      ),
                    );
                  }

                  return ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: patients.length > 5 ? 5 : patients.length,
                    itemBuilder: (context, index) {
                      final patient = patients[index];
                      return PatientListTile(
                        patient: patient,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  PatientDetailScreen(patientId: patient.id),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) => Center(
                  child: Text('Erreur: $error'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
