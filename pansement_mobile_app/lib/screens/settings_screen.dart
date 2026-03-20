// ============================================
// Écran Paramètres
// ============================================
// Fichier : lib/screens/settings_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/auth_provider.dart';
import '../providers/notifications_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/error_widget.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _emailNotifications = true;
  bool _pushNotifications = true;

  @override
  void dispose() {
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    // Préférences locales UI (le backend reste source d'autorité métier).
    setState(() {
      _emailNotifications =
          prefs.getBool('notifications_email_enabled') ?? true;
      _pushNotifications = prefs.getBool('notifications_push_enabled') ?? true;
    });
  }

  Future<void> _saveNotificationPreference(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;

    // Ecran de réglages utilisateur:
    // apparence, notifications, compte, actions données.
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paramètres'),
      ),
      body: ListView(
        children: [
          // Section Apparence (mode sombre)
          _buildSectionHeader('Apparence'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                Consumer(
                  builder: (context, ref, _) {
                    final themeNotifier = ref.watch(themeModeProvider.notifier);
                    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
                    return SwitchListTile(
                      secondary: Icon(
                        isDark ? Icons.dark_mode : Icons.light_mode,
                        color: Theme.of(context).iconTheme.color,
                      ),
                      title: const Text('Mode sombre'),
                      subtitle: const Text('Activer le thème sombre'),
                      value: isDark,
                      onChanged: (value) async {
                        await themeNotifier.setDark(value);
                        if (!mounted) return;
                        _showSaveSnackBar('Thème mis à jour');
                      },
                    );
                  },
                ),
              ],
            ),
          ),

          // Section Notifications
          _buildSectionHeader('Notifications'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.email),
                  title: const Text('Notifications par email'),
                  subtitle: const Text(
                      'Recevoir des emails pour les nouveaux événements'),
                  value: _emailNotifications,
                  onChanged: (value) async {
                    setState(() {
                      _emailNotifications = value;
                    });
                    await _saveNotificationPreference(
                        'notifications_email_enabled', value);
                    if (!mounted) return;
                    _showSaveSnackBar('Paramètre enregistré');
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.notifications_active),
                  title: const Text('Notifications push'),
                  subtitle:
                      const Text('Recevoir des notifications sur cet appareil'),
                  value: _pushNotifications,
                  onChanged: (value) async {
                    setState(() {
                      _pushNotifications = value;
                    });
                    await _saveNotificationPreference(
                        'notifications_push_enabled', value);

                    // Active/désactive la boucle de polling locale en cohérence.
                    if (value) {
                      ref
                          .read(notificationPollingProvider.notifier)
                          .startPolling();
                    } else {
                      ref
                          .read(notificationPollingProvider.notifier)
                          .stopPolling();
                    }

                    if (!mounted) return;
                    _showSaveSnackBar('Paramètre enregistré');
                  },
                ),
              ],
            ),
          ),

          // Section Compte
          _buildSectionHeader('Compte'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.person),
                  title: const Text('Modifier le profil'),
                  subtitle: const Text('Nom, photo, informations personnelles'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showEditProfileDialog(),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.lock),
                  title: const Text('Changer le mot de passe'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showChangePasswordDialog(),
                ),
                if (user?.role == 'patient') ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.bluetooth),
                    title: const Text('Appareils connectés'),
                    subtitle: const Text('Gérer vos pansements BLE'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showDevicesDialog(),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
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

  void _showSaveSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showEditProfileDialog() {
    final user = ref.read(authProvider).user;
    final firstNameController =
        TextEditingController(text: user?.firstName ?? '');
    final lastNameController =
        TextEditingController(text: user?.lastName ?? '');
    final phoneController = TextEditingController(text: user?.phone ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Modifier le profil'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: firstNameController,
                decoration: const InputDecoration(
                  labelText: 'Prénom',
                  prefixIcon: Icon(Icons.person),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: lastNameController,
                decoration: const InputDecoration(
                  labelText: 'Nom',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: phoneController,
                decoration: const InputDecoration(
                  labelText: 'Téléphone',
                  prefixIcon: Icon(Icons.phone),
                ),
                keyboardType: TextInputType.phone,
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
            onPressed: () async {
              // Afficher un indicateur de chargement
              if (!mounted) return;
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) => const Center(
                  child: CircularProgressIndicator(),
                ),
              );

              try {
                final apiService = ref.read(apiServiceProvider);
                await apiService.updateProfile(
                  firstName: firstNameController.text.trim().isNotEmpty
                      ? firstNameController.text.trim()
                      : null,
                  lastName: lastNameController.text.trim().isNotEmpty
                      ? lastNameController.text.trim()
                      : null,
                  phone: phoneController.text.trim().isNotEmpty
                      ? phoneController.text.trim()
                      : null,
                );

                // Mettre à jour l'utilisateur dans le provider
                await ref.read(authProvider.notifier).refreshUser();

                if (mounted) {
                  Navigator.pop(context); // Fermer le dialog de chargement
                  Navigator.pop(context); // Fermer le dialog d'édition
                  _showSaveSnackBar('✅ Profil mis à jour avec succès');
                }
              } catch (e) {
                if (mounted) {
                  Navigator.pop(context); // Fermer le dialog de chargement
                  final errorMessage =
                      e.toString().replaceAll('Exception: ', '');
                  ErrorSnackBar.show(
                    context,
                    '❌ Erreur lors de la mise à jour du profil',
                    suggestions: [
                      errorMessage,
                      'Vérifiez votre connexion internet',
                      'Réessayez dans quelques instants',
                    ],
                  );
                }
              }
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }

  void _showChangePasswordDialog() {
    final oldPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Changer le mot de passe'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: oldPasswordController,
                decoration: const InputDecoration(
                  labelText: 'Ancien mot de passe',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: newPasswordController,
                decoration: const InputDecoration(
                  labelText: 'Nouveau mot de passe',
                  prefixIcon: Icon(Icons.lock),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: confirmPasswordController,
                decoration: const InputDecoration(
                  labelText: 'Confirmer le mot de passe',
                  prefixIcon: Icon(Icons.lock),
                ),
                obscureText: true,
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
            onPressed: () async {
              // Validation
              if (oldPasswordController.text.isEmpty) {
                if (mounted) {
                  _showSaveSnackBar(
                      'Veuillez entrer votre ancien mot de passe');
                }
                return;
              }

              if (newPasswordController.text.isEmpty) {
                if (mounted) {
                  _showSaveSnackBar('Veuillez entrer un nouveau mot de passe');
                }
                return;
              }

              if (newPasswordController.text.length < 8) {
                if (mounted) {
                  _showSaveSnackBar(
                      'Le mot de passe doit contenir au moins 8 caractères');
                }
                return;
              }

              if (newPasswordController.text !=
                  confirmPasswordController.text) {
                if (mounted) {
                  _showSaveSnackBar('Les mots de passe ne correspondent pas');
                }
                return;
              }

              // Afficher un indicateur de chargement
              if (!mounted) return;
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) => const Center(
                  child: CircularProgressIndicator(),
                ),
              );

              try {
                final apiService = ref.read(apiServiceProvider);
                await apiService.changePassword(
                  oldPassword: oldPasswordController.text,
                  newPassword: newPasswordController.text,
                );

                if (mounted) {
                  Navigator.pop(context); // Fermer le dialog de chargement
                  Navigator.pop(context); // Fermer le dialog de changement
                  _showSaveSnackBar('✅ Mot de passe changé avec succès');
                }
              } catch (e) {
                if (mounted) {
                  Navigator.pop(context); // Fermer le dialog de chargement
                  final errorMessage =
                      e.toString().replaceAll('Exception: ', '');
                  ErrorSnackBar.show(
                    context,
                    '❌ Erreur lors du changement de mot de passe',
                    suggestions: [
                      errorMessage,
                      'Vérifiez que l\'ancien mot de passe est correct',
                      'Le nouveau mot de passe doit contenir au moins 8 caractères',
                    ],
                  );
                }
              }
            },
            child: const Text('Changer'),
          ),
        ],
      ),
    );
  }

  void _showDevicesDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mes appareils'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading:
                  const Icon(Icons.bluetooth_connected, color: Colors.blue),
              title: const Text('Pansement #1234'),
              subtitle: const Text('Bras gauche - Connecté'),
              trailing: IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () {
                  // TODO: Supprimer l'appareil
                },
              ),
            ),
            const Divider(),
            const Text(
              'Vous pouvez gérer vos pansements connectés depuis l\'onglet Scanner.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }
}
