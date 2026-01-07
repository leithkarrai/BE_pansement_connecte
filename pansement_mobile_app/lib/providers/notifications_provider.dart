import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../services/notification_service.dart';
import '../providers/auth_provider.dart';

/// Provider pour démarrer/arrêter le polling
final notificationPollingProvider =
    StateNotifierProvider<NotificationPollingNotifier, bool>((ref) {
  return NotificationPollingNotifier(ref);
});

class NotificationPollingNotifier extends StateNotifier<bool> {
  final Ref _ref;
  Timer? _timer;

  NotificationPollingNotifier(this._ref) : super(false);

  /// Démarre le polling des notifications
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

  /// Arrête le polling
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

/// Vérifie les nouvelles notifications depuis le backend
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

    // Vérifier les nouvelles alertes
    try {
      final alertsResponse = await apiService.getAlerts(
        unacknowledgedOnly: true,
        limit: 1,
      );

      final alerts = alertsResponse['alerts'] as List? ?? [];
      if (alerts.isNotEmpty) {
        // Vérifier si on a déjà notifié pour cette alerte
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

    // Pour les médecins : vérifier les nouveaux enregistrements de patients
    if (user.isMedecin) {
      // TODO: Implémenter la vérification des nouveaux enregistrements
      // Vous pouvez créer une route API pour cela
    }
  } catch (e) {
    debugPrint('❌ Erreur vérification notifications: $e');
  }
}
