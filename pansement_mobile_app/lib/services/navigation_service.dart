import 'package:flutter/material.dart';
import '../screens/comments_list_screen.dart';
import '../screens/alerts_screen.dart';

/// Service global de navigation.
///
/// Permet:
/// - la navigation sans BuildContext direct (ex: callback de notification),
/// - l'affichage global de SnackBars via une clé de ScaffoldMessenger.
class NavigationService {
  static final NavigationService _instance = NavigationService._internal();
  factory NavigationService() => _instance;
  NavigationService._internal();

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  /// Clé pour afficher des SnackBars sans BuildContext (évite "deactivated widget's ancestor")
  final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  /// Affiche un SnackBar de manière sécurisée (sans BuildContext, évite "deactivated widget's ancestor")
  void showSnackBar(SnackBar snackBar, {bool clearFirst = false}) {
    if (clearFirst) scaffoldMessengerKey.currentState?.clearSnackBars();
    scaffoldMessengerKey.currentState?.showSnackBar(snackBar);
  }

  /// Résout un payload de notification vers l'écran cible.
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

  /// Navigation nommée avec paramètres optionnels.
  void navigateTo(String route, {Object? arguments}) {
    if (navigatorKey.currentContext == null) return;
    Navigator.of(navigatorKey.currentContext!)
        .pushNamed(route, arguments: arguments);
  }

  /// Retour arrière si possible.
  void goBack() {
    if (navigatorKey.currentContext == null) return;
    Navigator.of(navigatorKey.currentContext!).pop();
  }
}
