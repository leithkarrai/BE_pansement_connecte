import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import 'navigation_service.dart';

/// Service singleton pour les notifications locales.
///
/// Rôle:
/// - initialiser le plugin de notifications,
/// - créer le canal Android,
/// - afficher/annuler les notifications,
/// - router l'action "tap" vers la navigation applicative.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Initialise le service de notifications (idempotent).
  /// Retourne `false` si les permissions sont refusées ou en cas d'erreur plugin.
  Future<bool> initialize() async {
    if (_initialized) return true;

    try {
      // Demander la permission sur Android 13+
      if (await Permission.notification.isDenied) {
        final status = await Permission.notification.request();
        if (status.isDenied) {
          debugPrint('⚠️ Permission de notification refusée');
          return false;
        }
      }

      // Configuration Android
      const AndroidInitializationSettings androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      // Configuration iOS
      const DarwinInitializationSettings iosSettings =
          DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const InitializationSettings initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      // Initialiser le plugin
      final initialized = await _notifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      if (initialized == true) {
        // Créer le canal de notification Android
        await _createNotificationChannel();
        _initialized = true;
        debugPrint('✅ Service de notifications initialisé');
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('❌ Erreur initialisation notifications: $e');
      return false;
    }
  }

  /// Crée le canal Android principal utilisé par l'app.
  Future<void> _createNotificationChannel() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'pansement_channel',
      'Pansement Connecté',
      description: 'Notifications pour les pansements connectés',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  /// Affiche une notification locale immédiate.
  /// Le `payload` est utilisé pour la navigation au tap.
  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_initialized) {
      debugPrint('⚠️ Service de notifications non initialisé');
      return;
    }

    try {
      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        'pansement_channel',
        'Pansement Connecté',
        channelDescription: 'Notifications pour les pansements connectés',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        playSound: true,
      );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notifications.show(id, title, body, details, payload: payload);
      debugPrint('📱 Notification affichée: $title');
    } catch (e) {
      debugPrint('❌ Erreur affichage notification: $e');
    }
  }

  /// Callback déclenché lors du tap utilisateur sur la notification.
  void _onNotificationTapped(NotificationResponse response) {
    debugPrint('🔔 Notification tapée: ${response.payload}');
    final navigationService = NavigationService();
    navigationService.navigateFromNotification(response.payload);
  }

  /// Annule une notification
  Future<void> cancelNotification(int id) async {
    await _notifications.cancel(id);
  }

  /// Annule toutes les notifications
  Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
  }

  /// Vérifie l'état global des notifications côté OS.
  Future<bool> areNotificationsEnabled() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidImplementation =
          _notifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      return await androidImplementation?.areNotificationsEnabled() ?? false;
    }
    return true; // iOS gère les permissions différemment
  }
}
