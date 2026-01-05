import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/auth_provider.dart';
import '../models/user.dart';
import 'login_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _profileFormKey = GlobalKey<FormState>();
  final _emailFormKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();

  bool _isEditingProfile = false;
  bool _isEditingEmail = false;
  bool _isLoading2FA = false;

  // Préférences de notifications (stockées localement)
  bool _emailNotifications = true;
  bool _pushNotifications = true;
  bool _alertNotifications = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadNotificationPreferences();
  }

  void _loadUserData() {
    final user = ref.read(authProvider).user;
    if (user != null) {
      _firstNameController.text = user.firstName;
      _lastNameController.text = user.lastName;
      _phoneController.text = user.phone ?? '';
      _emailController.text = user.email;
    }
  }

  Future<void> _loadNotificationPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _emailNotifications = prefs.getBool('notifications_email') ?? true;
      _pushNotifications = prefs.getBool('notifications_push') ?? true;
      _alertNotifications = prefs.getBool('notifications_alert') ?? true;
    });
  }

  Future<void> _saveNotificationPreference(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
    setState(() {
      switch (key) {
        case 'notifications_email':
          _emailNotifications = value;
          break;
        case 'notifications_push':
          _pushNotifications = value;
          break;
        case 'notifications_alert':
          _alertNotifications = value;
          break;
      }
    });
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Paramètres'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section Profil
            _buildSection(
              context,
              title: 'Mon Profil',
              icon: Icons.person,
              child: _buildProfileSection(user),
            ),

            const SizedBox(height: 24),

            // Section Email
            _buildSection(
              context,
              title: 'Adresse Email',
              icon: Icons.email,
              child: _buildEmailSection(user),
            ),

            const SizedBox(height: 24),

            // Section Sécurité
            _buildSection(
              context,
              title: 'Sécurité',
              icon: Icons.security,
              child: _buildSecuritySection(user),
            ),

            const SizedBox(height: 24),

            // Section Notifications
            _buildSection(
              context,
              title: 'Notifications',
              icon: Icons.notifications,
              child: _buildNotificationsSection(),
            ),

            const SizedBox(height: 24),

            // Section Compte
            _buildSection(
              context,
              title: 'Informations du Compte',
              icon: Icons.info,
              child: _buildAccountInfoSection(user),
            ),

            const SizedBox(height: 24),

            // Bouton Déconnexion
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Déconnexion'),
                      content: const Text(
                          'Êtes-vous sûr de vouloir vous déconnecter ?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Annuler'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Déconnexion'),
                        ),
                      ],
                    ),
                  );

                  if (confirm == true && context.mounted) {
                    await ref.read(authProvider.notifier).logout();
                    if (context.mounted) {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(
                          builder: (_) => const LoginScreen(),
                        ),
                        (route) => false,
                      );
                    }
                  }
                },
                icon: const Icon(Icons.logout),
                label: const Text('Déconnexion'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const Divider(height: 24),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildProfileSection(User? user) {
    return Form(
      key: _profileFormKey,
      child: Column(
        children: [
          TextFormField(
            controller: _firstNameController,
            decoration: const InputDecoration(
              labelText: 'Prénom',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person_outline),
            ),
            enabled: _isEditingProfile,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Le prénom est requis';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _lastNameController,
            decoration: const InputDecoration(
              labelText: 'Nom',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person_outline),
            ),
            enabled: _isEditingProfile,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Le nom est requis';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _phoneController,
            decoration: const InputDecoration(
              labelText: 'Téléphone',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.phone),
            ),
            enabled: _isEditingProfile,
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 16),
          if (_isEditingProfile)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _isEditingProfile = false;
                        _loadUserData(); // Recharger les données
                      });
                    },
                    child: const Text('Annuler'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _saveProfile,
                    child: const Text('Enregistrer'),
                  ),
                ),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _isEditingProfile = true;
                  });
                },
                icon: const Icon(Icons.edit),
                label: const Text('Modifier le profil'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmailSection(User? user) {
    return Form(
      key: _emailFormKey,
      child: Column(
        children: [
          TextFormField(
            controller: _emailController,
            decoration: InputDecoration(
              labelText: 'Adresse email',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.email_outlined),
              suffixIcon: user?.isVerified == true
                  ? const Icon(Icons.verified, color: Colors.green)
                  : const Icon(Icons.warning_amber, color: Colors.orange),
              helperText: user?.isVerified == true
                  ? 'Email vérifié'
                  : 'Email non vérifié',
            ),
            enabled: _isEditingEmail,
            keyboardType: TextInputType.emailAddress,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'L\'email est requis';
              }
              if (!value.contains('@')) {
                return 'Email invalide';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          if (_isEditingEmail)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _isEditingEmail = false;
                        _emailController.text = user?.email ?? '';
                      });
                    },
                    child: const Text('Annuler'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _saveEmail,
                    child: const Text('Enregistrer'),
                  ),
                ),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _isEditingEmail = true;
                  });
                },
                icon: const Icon(Icons.edit),
                label: const Text('Modifier l\'email'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSecuritySection(User? user) {
    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.lock_outline),
          title: const Text('Changer le mot de passe'),
          subtitle: const Text(
              'Mettez à jour votre mot de passe pour plus de sécurité'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showChangePasswordDialog(context),
        ),
        const Divider(),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.two_wheeler),
          title: const Text('Authentification à deux facteurs (2FA)'),
          subtitle: Text(
            user?.twoFactorEnabled == true
                ? '2FA activé - Protection renforcée'
                : '2FA désactivé - Activez pour plus de sécurité',
          ),
          value: user?.twoFactorEnabled ?? false,
          onChanged: _isLoading2FA ? null : (value) => _toggle2FA(value),
        ),
        if (_isLoading2FA)
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: LinearProgressIndicator(),
          ),
      ],
    );
  }

  Widget _buildNotificationsSection() {
    return Column(
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.email_outlined),
          title: const Text('Notifications par email'),
          subtitle: const Text('Recevoir des notifications par email'),
          value: _emailNotifications,
          onChanged: (value) =>
              _saveNotificationPreference('notifications_email', value),
        ),
        const Divider(),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.notifications_active),
          title: const Text('Notifications push'),
          subtitle:
              const Text('Recevoir des notifications push sur votre appareil'),
          value: _pushNotifications,
          onChanged: (value) =>
              _saveNotificationPreference('notifications_push', value),
        ),
        const Divider(),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.warning_amber),
          title: const Text('Alertes médicales'),
          subtitle:
              const Text('Recevoir des alertes pour les mesures critiques'),
          value: _alertNotifications,
          onChanged: (value) =>
              _saveNotificationPreference('notifications_alert', value),
        ),
      ],
    );
  }

  Widget _buildAccountInfoSection(User? user) {
    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.badge_outlined),
          title: const Text('Rôle'),
          trailing: Chip(
            label: Text(
              user?.role.toUpperCase() ?? '',
              style: const TextStyle(fontSize: 12),
            ),
            backgroundColor: _getRoleColor(user?.role),
          ),
        ),
        const Divider(),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.calendar_today_outlined),
          title: const Text('Compte créé'),
          subtitle: Text(
            user != null
                ? 'ID: ${user.id.substring(0, 8)}...'
                : 'Non disponible',
          ),
        ),
        const Divider(),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.check_circle_outline),
          title: const Text('Statut du compte'),
          trailing: user?.isActive == true
              ? const Chip(
                  label: Text('Actif'),
                  backgroundColor: Colors.green,
                  labelStyle: TextStyle(color: Colors.white),
                )
              : const Chip(
                  label: Text('Inactif'),
                  backgroundColor: Colors.red,
                  labelStyle: TextStyle(color: Colors.white),
                ),
        ),
      ],
    );
  }

  Color _getRoleColor(String? role) {
    switch (role?.toLowerCase()) {
      case 'admin':
        return Colors.red.shade100;
      case 'medecin':
        return Colors.blue.shade100;
      case 'patient':
        return Colors.green.shade100;
      default:
        return Colors.grey.shade100;
    }
  }

  Future<void> _saveProfile() async {
    if (!_profileFormKey.currentState!.validate()) return;

    try {
      final apiService = ref.read(apiServiceProvider);
      await apiService.updateProfile(
        firstName: _firstNameController.text,
        lastName: _lastNameController.text,
        phone: _phoneController.text.isEmpty ? null : _phoneController.text,
      );

      await ref.read(authProvider.notifier).refreshUser();

      if (!mounted) return;
      setState(() {
        _isEditingProfile = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profil mis à jour avec succès'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _saveEmail() async {
    if (!_emailFormKey.currentState!.validate()) return;

    try {
      final apiService = ref.read(apiServiceProvider);
      await apiService.updateProfile(
        email: _emailController.text,
      );

      await ref.read(authProvider.notifier).refreshUser();

      if (!mounted) return;
      setState(() {
        _isEditingEmail = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Email mis à jour avec succès. Veuillez vérifier votre nouvelle adresse.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _toggle2FA(bool enabled) async {
    setState(() {
      _isLoading2FA = true;
    });

    try {
      final apiService = ref.read(apiServiceProvider);
      await apiService.toggleTwoFactorAuth(enabled);

      await ref.read(authProvider.notifier).refreshUser();

      if (!mounted) return;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              enabled
                  ? 'Authentification à deux facteurs activée'
                  : 'Authentification à deux facteurs désactivée',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading2FA = false;
        });
      }
    }
  }

  void _showChangePasswordDialog(BuildContext context) {
    final oldPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Changer le mot de passe'),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: oldPasswordController,
                  decoration: const InputDecoration(
                    labelText: 'Ancien mot de passe',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  obscureText: true,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Ce champ est requis';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: newPasswordController,
                  decoration: const InputDecoration(
                    labelText: 'Nouveau mot de passe',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                    helperText: 'Minimum 8 caractères',
                  ),
                  obscureText: true,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Ce champ est requis';
                    }
                    if (value.length < 8) {
                      return 'Le mot de passe doit contenir au moins 8 caractères';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: confirmPasswordController,
                  decoration: const InputDecoration(
                    labelText: 'Confirmer le nouveau mot de passe',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                  obscureText: true,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Ce champ est requis';
                    }
                    if (value != newPasswordController.text) {
                      return 'Les mots de passe ne correspondent pas';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;

              try {
                final apiService = ref.read(apiServiceProvider);
                await apiService.changePassword(
                  oldPassword: oldPasswordController.text,
                  newPassword: newPasswordController.text,
                );

                if (context.mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Mot de passe modifié avec succès'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Erreur: ${e.toString()}'),
                      backgroundColor: Colors.red,
                    ),
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
}
