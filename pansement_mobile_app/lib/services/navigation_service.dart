import 'package:flutter/material.dart';
import '../screens/comments_list_screen.dart';
import '../screens/alerts_screen.dart';

/// Service global pour gérer la navigation depuis n'importe où dans l'app
/// Utile pour la navigation depuis les notifications
class NavigationService {
  static final NavigationService _instance = NavigationService._internal();
  factory NavigationService() => _instance;
  NavigationService._internal();

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  /// Navigue vers un écran spécifique selon le payload de la notification
  void navigateFromNotification(String? payload) {
    if (payload == null || navigatorKey.currentContext == null) {
      return;
    }

    final context = navigatorKey.currentContext!;

    switch (payload) {
      case 'comments':
        // Naviguer vers l'écran des commentaires
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const CommentsListScreen(),
          ),
        );
        debugPrint('🔔 Navigation vers l\'écran des commentaires');
        break;

      case 'alerts':
        // Naviguer vers l'écran des alertes
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const AlertsScreen(),
          ),
        );
        debugPrint('🔔 Navigation vers l\'écran des alertes');
        break;

      case 'test':
        // Pour les notifications de test, ne rien faire
        debugPrint('🔔 Notification de test tapée');
        break;

      default:
        debugPrint('⚠️ Payload de notification inconnu: $payload');
    }
  }

  /// Navigue vers un écran avec des paramètres
  void navigateTo(String route, {Object? arguments}) {
    if (navigatorKey.currentContext == null) return;
    Navigator.of(navigatorKey.currentContext!)
        .pushNamed(route, arguments: arguments);
  }

  /// Retourne au précédent écran
  void goBack() {
    if (navigatorKey.currentContext == null) return;
    Navigator.of(navigatorKey.currentContext!).pop();
  }
}
