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
import 'alerts_screen.dart';
import 'settings_screen.dart';

/// Dashboard Médecin - Vue des patients assignés
/// Actualisation automatique des alertes + notification in-app au retour sur l'app
class DoctorDashboardScreen extends ConsumerStatefulWidget {
  const DoctorDashboardScreen({super.key});

  @override
  ConsumerState<DoctorDashboardScreen> createState() =>
      _DoctorDashboardScreenState();
}

class _DoctorDashboardScreenState extends ConsumerState<DoctorDashboardScreen>
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
    Future.delayed(const Duration(milliseconds: 800), () async {
      if (!mounted || _ref == null) return;
      try {
        final alerts = await _ref!.read(unacknowledgedAlertsProvider.future);
        if (alerts.isNotEmpty && mounted) {
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
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    _ref = ref;
    // Rafraîchissement périodique des compteurs d'alertes/stats pendant la consultation.
    if (_refreshTimer == null && mounted) {
      _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted && _ref != null) {
          _ref!.invalidate(dashboardStatsProvider);
          _ref!.invalidate(alertsProvider);
          _ref!.invalidate(unacknowledgedAlertsProvider);
        }
      });
    }

    // Feedback in-app à l'arrivée de nouvelles alertes non lues.
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

    final authState = ref.watch(authProvider);
    final user = authState.user;
    final statsAsync = ref.watch(dashboardStatsProvider);
    final patientsAsync = ref.watch(patientsProvider);

    // Dashboard médecin: vue orientée patients suivis + alertes actionnables.
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.medical_services),
            const SizedBox(width: 8),
            const Text('Dashboard Médecin'),
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
                            fontSize: 12,
                            color: Colors.white,
                          ),
                        ),
                        child: const Icon(Icons.notifications_active),
                      );
                    }
                    return const Icon(Icons.notifications_active);
                  },
                  loading: () => const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  error: (_, __) => const Icon(Icons.notifications_off),
                ),
            tooltip: 'Alertes (nouvelles mesures)',
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
                        'Dr. ${user.fullName}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Médecin',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    icon: const Icon(Icons.logout),
                    tooltip: 'Déconnexion',
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
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Bannière "nouvelles alertes" dans l'application (visible sur l'écran)
              statsAsync.when(
                data: (stats) {
                  final unack = stats['alerts_unacknowledged'] ?? 0;
                  if (unack <= 0) return const SizedBox.shrink();
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.notifications_active, color: Colors.orange.shade800, size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Vous avez $unack alerte(s) à consulter',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.orange.shade900,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            ref.invalidate(alertsProvider);
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const AlertsScreen(),
                              ),
                            );
                          },
                          child: const Text('Voir'),
                        ),
                      ],
                    ),
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
              // Statistiques des patients
              Text(
                'Mes patients',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),

              statsAsync.when(
                data: (stats) => GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 1.2,
                  children: [
                    StatCard(
                      title: 'Mes Patients',
                      value: stats['my_patients']?.toString() ?? '0',
                      icon: Icons.people,
                      color: Colors.blue,
                    ),
                    StatCard(
                      title: 'Appareils Actifs',
                      value: stats['active_devices']?.toString() ?? '0',
                      icon: Icons.devices,
                      color: Colors.orange,
                    ),
                    StatCard(
                      title: 'Alertes',
                      value: stats['alerts']?.toString() ?? '0',
                      icon: Icons.warning,
                      color: Colors.red,
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
                    'Patients récents',
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
                        child: Text('Aucun patient assigné'),
                      ),
                    );
                  }

                  return ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: patients.length,
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
