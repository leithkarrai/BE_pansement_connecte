// ============================================
// Écran Aide et Support
// ============================================
// Fichier : lib/screens/help_support_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';

class HelpSupportScreen extends ConsumerWidget {
  const HelpSupportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final role = user?.role.toLowerCase() ?? 'patient';

    // FAQ contextualisée par rôle pour réduire la friction utilisateur.
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aide et Support'),
      ),
      body: ListView(
        children: [
          // FAQ - Questions varient selon le rôle
          _buildSectionHeader(context, 'Questions fréquentes'),
          ..._getFAQQuestions(context, role),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  /// Retourne le bloc FAQ adapté au rôle connecté.
  List<Widget> _getFAQQuestions(BuildContext context, String role) {
    switch (role) {
      case 'patient':
        return _getPatientFAQ(context);
      case 'medecin':
        return _getMedecinFAQ(context);
      case 'admin':
        return _getAdminFAQ(context);
      default:
        return _getPatientFAQ(context);
    }
  }

  /// Questions FAQ pour les patients
  List<Widget> _getPatientFAQ(BuildContext context) {
    return [
      _buildFAQCard(
        context,
        'Comment connecter mon pansement ?',
        'Allez sur l\'onglet Scanner, activez le Bluetooth et appuyez sur "Scanner". Sélectionnez votre pansement dans la liste.',
        Icons.bluetooth,
      ),
      _buildFAQCard(
        context,
        'Comment voir mes mesures ?',
        'Une fois connecté, les mesures s\'affichent automatiquement. Les données sont envoyées au serveur pour que votre médecin puisse les consulter.',
        Icons.insights,
      ),
      _buildFAQCard(
        context,
        'Je ne reçois pas les notifications',
        'Vérifiez que les notifications sont activées dans Paramètres > Notifications. Vérifiez aussi les paramètres de votre téléphone.',
        Icons.notifications_off,
      ),
      _buildFAQCard(
        context,
        'Mon pansement ne se connecte pas',
        'Vérifiez que :\n• Le Bluetooth est activé\n• Le pansement est chargé\n• Vous êtes à proximité (<2m)\n• La localisation est activée (Android)',
        Icons.bluetooth_disabled,
      ),
      _buildFAQCard(
        context,
        'Comment voir les commentaires de mon médecin ?',
        'Allez dans l\'onglet "Commentaires" pour voir tous les messages de votre médecin. Vous recevrez une notification à chaque nouveau commentaire.',
        Icons.comment,
      ),
      _buildFAQCard(
        context,
        'Mes données sont-elles sécurisées ?',
        'Oui, toutes vos données médicales sont chiffrées et protégées selon les normes RGPD. Seuls vous et votre médecin y avez accès.',
        Icons.security,
      ),
    ];
  }

  /// Questions FAQ pour les médecins
  List<Widget> _getMedecinFAQ(BuildContext context) {
    return [
      _buildFAQCard(
        context,
        'Comment voir les mesures de mes patients ?',
        'Allez dans l\'onglet "Patients" pour voir la liste de vos patients. Cliquez sur un patient pour voir ses mesures en temps réel.',
        Icons.people,
      ),
      _buildFAQCard(
        context,
        'Comment ajouter un commentaire à un patient ?',
        'Dans la page de détail d\'un patient, cliquez sur "Ajouter un commentaire". Le patient recevra une notification.',
        Icons.comment,
      ),
      _buildFAQCard(
        context,
        'Comment assigner un pansement à un patient ?',
        'Allez dans "Tous les appareils", sélectionnez un appareil disponible et cliquez sur "Assigner". Choisissez le patient dans la liste.',
        Icons.assignment,
      ),
      _buildFAQCard(
        context,
        'Comment voir l\'historique des mesures ?',
        'Dans la page de détail d\'un patient, vous pouvez voir les graphiques et l\'historique complet des mesures.',
        Icons.timeline,
      ),
      _buildFAQCard(
        context,
        'Comment recevoir des alertes pour mes patients ?',
        'Les alertes sont automatiques. Vous recevrez une notification si un patient a des valeurs anormales ou si son pansement se déconnecte.',
        Icons.warning,
      ),
      _buildFAQCard(
        context,
        'Comment exporter les données d\'un patient ?',
        'Dans la page de détail d\'un patient, cliquez sur "Exporter" pour télécharger toutes ses données au format PDF ou CSV.',
        Icons.download,
      ),
    ];
  }

  /// Questions FAQ pour les administrateurs
  List<Widget> _getAdminFAQ(BuildContext context) {
    return [
      _buildFAQCard(
        context,
        'Comment gérer les utilisateurs ?',
        'Allez dans l\'onglet "Utilisateurs" pour voir tous les utilisateurs. Vous pouvez créer, modifier ou désactiver des comptes.',
        Icons.people,
      ),
      _buildFAQCard(
        context,
        'Comment gérer les appareils ?',
        'Allez dans "Tous les appareils" pour voir tous les pansements. Vous pouvez créer, modifier, assigner ou désassigner des appareils.',
        Icons.devices,
      ),
      _buildFAQCard(
        context,
        'Comment voir les statistiques globales ?',
        'Le tableau de bord affiche les statistiques en temps réel : nombre de patients, appareils actifs, alertes, etc.',
        Icons.dashboard,
      ),
      _buildFAQCard(
        context,
        'Comment configurer le système ?',
        'Allez dans Paramètres > Administration pour configurer les paramètres système, les notifications, et les intégrations.',
        Icons.settings,
      ),
      _buildFAQCard(
        context,
        'Comment voir les logs système ?',
        'Dans la section Administration, vous pouvez consulter les logs système pour diagnostiquer les problèmes.',
        Icons.description,
      ),
      _buildFAQCard(
        context,
        'Comment gérer les permissions ?',
        'Dans la gestion des utilisateurs, vous pouvez modifier les rôles et permissions de chaque utilisateur.',
        Icons.admin_panel_settings,
      ),
    ];
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.grey[600],
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildFAQCard(BuildContext context, String question, String answer, IconData icon) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ExpansionTile(
        leading: Icon(icon, color: Theme.of(context).primaryColor),
        title: Text(
          question,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              answer,
              style: TextStyle(color: Colors.grey[700], height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

}
