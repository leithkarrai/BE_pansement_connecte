import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import 'login_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;

    return ListView(
      padding: const EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: 16, // Espace pour la Bottom Navigation Bar
      ),
      children: [
        // Avatar et nom
        Center(
          child: Column(
            children: [
              CircleAvatar(
                radius: 60,
                backgroundColor: Theme.of(context).primaryColor,
                child: Text(
                  user?.firstName[0].toUpperCase() ?? 'U',
                  style: const TextStyle(
                    fontSize: 48,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                user?.fullName ?? 'Utilisateur',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  user?.role.toUpperCase() ?? '',
                  style: TextStyle(
                    color: Theme.of(context).primaryColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 32),

        // Informations personnelles
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.email),
                title: const Text('Email'),
                subtitle: Text(user?.email ?? ''),
              ),
              const Divider(),
              if (user?.phone != null)
                ListTile(
                  leading: const Icon(Icons.phone),
                  title: const Text('Téléphone'),
                  subtitle: Text(user!.phone!),
                ),
              if (user?.phone != null) const Divider(),
              if (user?.bloodType != null) ...[
                ListTile(
                  leading: const Icon(Icons.bloodtype),
                  title: const Text('Groupe sanguin'),
                  subtitle: Text(user!.bloodType!),
                ),
                const Divider(),
              ],
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Paramètres et actions
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.settings),
                title: const Text('Paramètres'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  // TODO: Navigation vers paramètres
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Paramètres - À venir'),
                    ),
                  );
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.notifications),
                title: const Text('Notifications'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  // TODO: Navigation vers notifications
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Notifications - À venir'),
                    ),
                  );
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.security),
                title: const Text('Sécurité et confidentialité'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  // TODO: Navigation vers sécurité
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Sécurité - À venir'),
                    ),
                  );
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.help_outline),
                title: const Text('Aide et support'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  // TODO: Navigation vers aide
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Aide - À venir'),
                    ),
                  );
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('À propos'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  showAboutDialog(
                    context: context,
                    applicationName: 'Pansement Connecté',
                    applicationVersion: '1.0.0',
                    applicationIcon:
                        const Icon(Icons.medical_services, size: 48),
                    children: [
                      const Text(
                        'Application de monitoring des pansements connectés pour le suivi médical des patients.',
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 32),

        // Bouton de déconnexion
        ElevatedButton.icon(
          onPressed: () async {
            final shouldLogout = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Déconnexion'),
                content:
                    const Text('Êtes-vous sûr de vouloir vous déconnecter ?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Annuler'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Déconnexion'),
                  ),
                ],
              ),
            );

            if (shouldLogout == true && context.mounted) {
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              }
            }
          },
          icon: const Icon(Icons.logout),
          label: const Text('Se déconnecter'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.all(16),
          ),
        ),

        const SizedBox(height: 16),

        // Version et informations légales
        Center(
          child: Column(
            children: [
              Text(
                'Version 1.0.0',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () {
                      // TODO: Afficher les CGU
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('CGU - À venir'),
                        ),
                      );
                    },
                    child: const Text('CGU'),
                  ),
                  Text('•', style: TextStyle(color: Colors.grey[600])),
                  TextButton(
                    onPressed: () {
                      // TODO: Afficher la politique de confidentialité
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Confidentialité - À venir'),
                        ),
                      );
                    },
                    child: const Text('Confidentialité'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
