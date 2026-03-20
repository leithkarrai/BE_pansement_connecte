import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/notification_service.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';

/// Contrôle le polling périodique des notifications locales.
final notificationPollingProvider =
    StateNotifierProvider<NotificationPollingNotifier, bool>((ref) {
  return NotificationPollingNotifier(ref);
});

class NotificationPollingNotifier extends StateNotifier<bool> {
  final Ref _ref;
  Timer? _timer;

  NotificationPollingNotifier(this._ref) : super(false);

  /// Démarre le polling des notifications backend.
  /// `state=true` signifie "timer actif".
  void startPolling({int intervalSeconds = 30}) {
    if (state) return; // Déjà démarré

    _timer = Timer.periodic(Duration(seconds: intervalSeconds), (_) {
      _checkNotifications(_ref);
    });

    // Vérifier immédiatement
    _checkNotifications(_ref);

    state = true;
    debugPrint(
        '🔄 Polling des notifications démarré (intervalle: ${intervalSeconds}s)');
  }

  /// Arrête proprement le timer de polling.
  void stopPolling() {
    _timer?.cancel();
    _timer = null;
    state = false;
    debugPrint('⏹️ Polling des notifications arrêté');
  }

  @override
  void dispose() {
    stopPolling();
    super.dispose();
  }
}

/// Charge le token JWT depuis le stockage sécurisé.
Future<void> _ensureTokenLoaded(ApiService apiService) async {
  const storage = FlutterSecureStorage();
  final token = await storage.read(key: 'access_token');
  if (token != null) {
    apiService.setToken(token);
  }
}

/// Vérifie les nouvelles notifications côté backend et déclenche des notifications locales.
///
/// Stratégie:
/// - déduplication via SharedPreferences (`last_notified_*`),
/// - logique par rôle (patient / medecin / admin),
/// - robustesse: erreurs isolées par bloc pour ne pas interrompre tout le polling.
Future<void> _checkNotifications(Ref ref) async {
  try {
    // Vérifier si les notifications sont activées
    final prefs = await SharedPreferences.getInstance();
    final pushNotificationsEnabled =
        prefs.getBool('notifications_push_enabled') ?? true;

    if (!pushNotificationsEnabled) {
      return; // Notifications désactivées
    }

    final user = ref.read(authProvider).user;
    if (user == null) return;

    final apiService = ref.read(apiServiceProvider);
    // Charger le token avant de faire les appels API
    await _ensureTokenLoaded(apiService);
    final notificationService = NotificationService();

    // Vérifier les nouveaux commentaires (pour les patients)
    if (user.isPatient) {
      try {
        final unreadCount = await apiService.getUnreadCommentsCount(user.id);
        if (unreadCount > 0) {
          // Vérifier si on a déjà notifié pour ce nombre
          final lastNotifiedCount =
              prefs.getInt('last_notified_comments_count') ?? 0;

          if (unreadCount > lastNotifiedCount) {
            await notificationService.showNotification(
              id: 1,
              title: 'Nouveau commentaire',
              body: unreadCount == 1
                  ? 'Vous avez un nouveau commentaire de votre médecin'
                  : 'Vous avez $unreadCount nouveaux commentaires',
              payload: 'comments',
            );
            await prefs.setInt('last_notified_comments_count', unreadCount);
            debugPrint('📬 Notification commentaire envoyée: $unreadCount');
          }
        }
      } catch (e) {
        debugPrint('❌ Erreur vérification commentaires: $e');
      }
    }

    // Vérifier les nouvelles alertes (sauf pour l'admin : il a ses propres blocs plus bas)
    if (!user.isAdmin) {
      try {
        Map<String, dynamic> alertsResponse;
        try {
          alertsResponse = await apiService.getAlerts(
            unacknowledgedOnly: true,
            limit: 1,
          );
        } catch (e) {
          debugPrint('⚠️ Erreur récupération alertes: $e');
          alertsResponse = {
            'alerts': [],
            'total': 0,
            'unacknowledged': 0,
            'critical': 0,
          };
        }

        final alerts = alertsResponse['alerts'] as List? ?? [];
        if (alerts.isNotEmpty) {
          final lastAlertId = prefs.getString('last_notified_alert_id') ?? '';
          final currentAlertId = alerts[0]['id'] as String? ?? '';
          if (currentAlertId != lastAlertId && currentAlertId.isNotEmpty) {
            final alert = alerts[0];
            await notificationService.showNotification(
              id: 2,
              title: alert['title'] as String? ?? 'Nouvelle alerte',
              body: alert['message'] as String? ??
                  'Une nouvelle alerte nécessite votre attention',
              payload: 'alerts',
            );
            await prefs.setString('last_notified_alert_id', currentAlertId);
            debugPrint('🚨 Notification alerte envoyée: $currentAlertId');
          }
        }
      } catch (e) {
        debugPrint('❌ Erreur vérification alertes: $e');
      }
    }

    // Pour les médecins : vérifier les nouvelles données patient (graphiques à consulter)
    if (user.isMedecin) {
      try {
        final dataAlerts = await apiService.getAlerts(
          alertType: 'new_patient_data',
          unacknowledgedOnly: true,
          limit: 1,
        );
        final alerts = (dataAlerts['alerts'] as List? ?? []);
        if (alerts.isNotEmpty) {
          final lastId =
              prefs.getString('last_notified_medecin_data_alert_id') ?? '';
          final currentId = alerts[0]['id'] as String? ?? '';
          if (currentId != lastId && currentId.isNotEmpty) {
            await notificationService.showNotification(
              id: 5,
              title: alerts[0]['title'] as String? ?? 'Nouvelles données patient',
              body: alerts[0]['message'] as String? ??
                  'Un patient a envoyé de nouvelles mesures. Consultez les graphiques.',
              payload: 'alerts',
            );
            await prefs.setString(
                'last_notified_medecin_data_alert_id', currentId);
            debugPrint(
                '🔔 Notification médecin (nouvelles données): $currentId');
          }
        }
      } catch (e) {
        debugPrint('⚠️ Erreur alertes médecin (données patient): $e');
      }
    }

    // Pour les admins : vérifier les alertes nouveau médecin ET nouvelles données patient
    if (user.isAdmin) {
      // 1) Nouveau médecin inscrit
      try {
        final medecinAlerts = await apiService.getAlerts(
          alertType: 'new_medecin_registration',
          unacknowledgedOnly: true,
          limit: 1,
        );
        final alerts = (medecinAlerts['alerts'] as List? ?? []);
        if (alerts.isNotEmpty) {
          final lastId = prefs.getString('last_notified_admin_medecin_alert_id') ?? '';
          final currentId = alerts[0]['id'] as String? ?? '';
          if (currentId != lastId && currentId.isNotEmpty) {
            await notificationService.showNotification(
              id: 3,
              title: alerts[0]['title'] as String? ?? 'Nouveau médecin inscrit',
              body: alerts[0]['message'] as String? ?? 'Un nouveau médecin s\'est inscrit',
              payload: 'admin_alerts',
            );
            await prefs.setString('last_notified_admin_medecin_alert_id', currentId);
            debugPrint('🔔 Notification admin (nouveau médecin): $currentId');
          }
        }
      } catch (e) {
        debugPrint('⚠️ Erreur alertes admin (médecin): $e');
      }

      // 2) Nouvelles données patient (données brutes à consulter)
      try {
        final dataAlerts = await apiService.getAlerts(
          alertType: 'new_patient_data',
          unacknowledgedOnly: true,
          limit: 1,
        );
        final alerts = (dataAlerts['alerts'] as List? ?? []);
        if (alerts.isNotEmpty) {
          final lastId = prefs.getString('last_notified_admin_data_alert_id') ?? '';
          final currentId = alerts[0]['id'] as String? ?? '';
          if (currentId != lastId && currentId.isNotEmpty) {
            await notificationService.showNotification(
              id: 4,
              title: alerts[0]['title'] as String? ?? 'Nouvelles données patient',
              body: alerts[0]['message'] as String? ?? 'Un patient a envoyé de nouvelles mesures. Consultez les données brutes.',
              payload: 'alerts',
            );
            await prefs.setString('last_notified_admin_data_alert_id', currentId);
            debugPrint('🔔 Notification admin (nouvelles données patient): $currentId');
          }
        }
      } catch (e) {
        debugPrint('⚠️ Erreur alertes admin (données patient): $e');
      }
    }

    // Médecin : reçoit les alertes new_patient_data via le bloc général (l.109-146).
    // Le backend filtre par rôle : médecin = alertes de ses patients uniquement.
  } catch (e) {
    debugPrint('❌ Erreur vérification notifications: $e');
  }
}
