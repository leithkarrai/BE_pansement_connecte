import 'package:flutter/material.dart';

/// Widget réutilisable pour afficher les erreurs avec des suggestions
class ErrorDisplayWidget extends StatelessWidget {
  final String error;
  final VoidCallback? onRetry;
  final List<String>? suggestions;
  final IconData? icon;

  const ErrorDisplayWidget({
    super.key,
    required this.error,
    this.onRetry,
    this.suggestions,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon ?? Icons.error_outline,
              size: 64,
              color: Colors.red[300],
            ),
            const SizedBox(height: 16),
            Text(
              'Erreur',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[700]),
            ),
            if (suggestions != null && suggestions!.isNotEmpty) ...[
              const SizedBox(height: 24),
              ...suggestions!.map((suggestion) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 16, color: Colors.blue[300]),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            suggestion,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                      ],
                    ),
                  )),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Widget pour afficher un message d'erreur simple dans un SnackBar
class ErrorSnackBar {
  static void show(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 4),
    List<String>? suggestions,
  }) {
    // Utiliser addPostFrameCallback pour s'assurer que le widget est monté
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Vérifier que le contexte est toujours valide
      if (!context.mounted) {
        debugPrint("⚠️ Contexte désactivé, impossible d'afficher le SnackBar");
        return;
      }

      try {
        final scaffoldMessenger = ScaffoldMessenger.maybeOf(context);
        if (scaffoldMessenger == null) {
          debugPrint("⚠️ ScaffoldMessenger non disponible");
          return;
        }

        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        message,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                if (suggestions != null && suggestions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...suggestions.map((s) => Padding(
                        padding: const EdgeInsets.only(left: 32, top: 4),
                        child: Text(
                          '• $s',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      )),
                ],
              ],
            ),
            backgroundColor: Colors.red,
            duration: duration,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } catch (e) {
        debugPrint("❌ Erreur lors de l'affichage du SnackBar: $e");
      }
    });
  }
}
