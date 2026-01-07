// ============================================
// Écran Aide et Support
// ============================================
// Fichier : lib/screens/help_support_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/auth_provider.dart';

class HelpSupportScreen extends ConsumerWidget {
  const HelpSupportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final role = user?.role.toLowerCase() ?? 'patient';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Aide et Support'),
      ),
      body: ListView(
        children: [
          // FAQ - Questions varient selon le rôle
          _buildSectionHeader(context, 'Questions fréquentes'),
          ..._getFAQQuestions(context, role),

          // Guides
          _buildSectionHeader(context, 'Guides'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.play_circle_outline, color: Colors.blue),
                  title: const Text('Tutoriel vidéo'),
                  subtitle: Text(_getTutorialSubtitle(role)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showComingSoonDialog(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.book, color: Colors.green),
                  title: const Text('Guide utilisateur'),
                  subtitle: Text(_getGuideSubtitle(role)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showComingSoonDialog(context),
                ),
              ],
            ),
          ),

          // Contact
          _buildSectionHeader(context, 'Nous contacter'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.email, color: Colors.blue),
                  title: const Text('Email'),
                  subtitle: const Text('support@pansement-connecte.fr'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _launchEmail(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.phone, color: Colors.green),
                  title: const Text('Téléphone'),
                  subtitle: const Text('+33 1 23 45 67 89'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _launchPhone(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.chat_bubble, color: Colors.orange),
                  title: const Text('Chat en direct'),
                  subtitle: const Text('Disponible 24/7'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showComingSoonDialog(context),
                ),
              ],
            ),
          ),

          // Informations système
          _buildSectionHeader(context, 'Informations'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Version de l\'application'),
                  trailing: Text('1.0.0', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.bug_report),
                  title: const Text('Signaler un bug'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showBugReportDialog(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.star),
                  title: const Text('Noter l\'application'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showComingSoonDialog(context),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  /// Retourne les questions FAQ selon le rôle de l'utilisateur
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

  /// Retourne le sous-titre du tutoriel selon le rôle
  String _getTutorialSubtitle(String role) {
    switch (role) {
      case 'patient':
        return 'Comment utiliser l\'application en tant que patient';
      case 'medecin':
        return 'Guide pour les médecins';
      case 'admin':
        return 'Guide d\'administration';
      default:
        return 'Comment utiliser l\'application';
    }
  }

  /// Retourne le sous-titre du guide selon le rôle
  String _getGuideSubtitle(String role) {
    switch (role) {
      case 'patient':
        return 'Documentation patient (PDF)';
      case 'medecin':
        return 'Documentation médecin (PDF)';
      case 'admin':
        return 'Documentation administrateur (PDF)';
      default:
        return 'Documentation complète (PDF)';
    }
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

  void _showComingSoonDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bientôt disponible'),
        content: const Text('Cette fonctionnalité sera disponible dans une prochaine mise à jour.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _launchEmail(BuildContext context) async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: 'support@pansement-connecte.fr',
      query: 'subject=Demande de support',
    );
    
    try {
      if (await canLaunchUrl(emailUri)) {
        await launchUrl(emailUri, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(
              content: Text('Impossible d\'ouvrir l\'application email'),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text('Erreur: $e'),
          ),
        );
      }
    }
  }

  Future<void> _launchPhone(BuildContext context) async {
    final Uri phoneUri = Uri(
      scheme: 'tel',
      path: '+33123456789',
    );
    
    try {
      if (await canLaunchUrl(phoneUri)) {
        await launchUrl(phoneUri, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(
              content: Text('Impossible d\'ouvrir l\'application téléphone'),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text('Erreur: $e'),
          ),
        );
      }
    }
  }

  void _showBugReportDialog(BuildContext context) {
    final descriptionController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Signaler un bug'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Décrivez le problème rencontré :'),
              const SizedBox(height: 8),
              TextField(
                controller: descriptionController,
                maxLines: 5,
                decoration: const InputDecoration(
                  hintText: 'Ex: L\'application se ferme quand je clique sur...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              // TODO: Envoyer le rapport de bug à l'API
              Navigator.pop(context);
              if (context.mounted) {
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                  const SnackBar(
                    content: Text('Merci ! Votre rapport a été envoyé.'),
                  ),
                );
              }
            },
            child: const Text('Envoyer'),
          ),
        ],
      ),
    );
  }
}
