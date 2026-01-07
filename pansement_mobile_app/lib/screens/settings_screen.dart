// ============================================
// Écran Paramètres
// ============================================
// Fichier : lib/screens/settings_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/auth_provider.dart';
import '../providers/notifications_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _emailNotifications = true;
  bool _pushNotifications = true;
  bool _darkMode = false;
  String _language = 'Français';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Paramètres'),
      ),
      body: ListView(
        children: [
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

                    // Démarrer/arrêter le polling selon la préférence
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

          // Section Apparence
          _buildSectionHeader('Apparence'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.dark_mode),
                  title: const Text('Mode sombre'),
                  subtitle: const Text('Activer le thème sombre'),
                  value: _darkMode,
                  onChanged: (value) {
                    setState(() {
                      _darkMode = value;
                    });
                    _showSaveSnackBar(
                        'Mode ${value ? "sombre" : "clair"} activé');
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.language),
                  title: const Text('Langue'),
                  subtitle: Text(_language),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showLanguageDialog(),
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

          // Section Données
          _buildSectionHeader('Données'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.download),
                  title: const Text('Télécharger mes données'),
                  subtitle: const Text('Export de toutes vos données'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showExportDataDialog(),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.red),
                  title: const Text('Supprimer mon compte',
                      style: TextStyle(color: Colors.red)),
                  subtitle: const Text('Action irréversible'),
                  trailing: const Icon(Icons.chevron_right, color: Colors.red),
                  onTap: () => _showDeleteAccountDialog(),
                ),
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

  void _showLanguageDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choisir la langue'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<String>(
              title: const Text('Français'),
              value: 'Français',
              groupValue: _language,
              onChanged: (value) {
                if (!mounted) return;
                setState(() => _language = value!);
                Navigator.pop(context);
                _showSaveSnackBar('Langue changée: $_language');
              },
            ),
            RadioListTile<String>(
              title: const Text('English'),
              value: 'English',
              groupValue: _language,
              onChanged: (value) {
                if (!mounted) return;
                setState(() => _language = value!);
                Navigator.pop(context);
                _showSaveSnackBar('Language changed: $_language');
              },
            ),
          ],
        ),
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
            onPressed: () {
              // TODO: Appeler l'API pour mettre à jour le profil
              Navigator.pop(context);
              if (mounted) {
                _showSaveSnackBar('Profil mis à jour');
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
            onPressed: () {
              if (newPasswordController.text ==
                  confirmPasswordController.text) {
                // TODO: Appeler l'API pour changer le mot de passe
                Navigator.pop(context);
                if (mounted) {
                  _showSaveSnackBar('Mot de passe changé');
                }
              } else {
                if (mounted) {
                  _showSaveSnackBar('Les mots de passe ne correspondent pas');
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

  void _showExportDataDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Télécharger mes données'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Vous allez recevoir un fichier contenant :'),
            SizedBox(height: 8),
            Text('• Vos informations personnelles'),
            Text('• Vos mesures'),
            Text('• Les commentaires des médecins'),
            SizedBox(height: 16),
            Text(
              'Le fichier sera envoyé par email dans les prochaines minutes.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              // TODO: Appeler l'API pour exporter les données
              Navigator.pop(context);
              if (mounted) {
                _showSaveSnackBar('Export en cours... Vous recevrez un email');
              }
            },
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
  }

  void _showDeleteAccountDialog() {
    final passwordController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer mon compte',
            style: TextStyle(color: Colors.red)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '⚠️ ATTENTION : Cette action est irréversible !',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
            ),
            const SizedBox(height: 16),
            const Text('Toutes vos données seront définitivement supprimées :'),
            const SizedBox(height: 8),
            const Text('• Profil'),
            const Text('• Mesures'),
            const Text('• Commentaires'),
            const Text('• Appareils'),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              decoration: const InputDecoration(
                labelText: 'Confirmez avec votre mot de passe',
                prefixIcon: Icon(Icons.lock),
              ),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              if (passwordController.text.isNotEmpty) {
                // TODO: Appeler l'API pour supprimer le compte
                Navigator.pop(context);
                if (mounted) {
                  _showSaveSnackBar('Compte supprimé');
                  // Déconnecter et rediriger vers login
                }
              } else {
                if (mounted) {
                  _showSaveSnackBar('Veuillez entrer votre mot de passe');
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Supprimer définitivement'),
          ),
        ],
      ),
    );
  }
}
