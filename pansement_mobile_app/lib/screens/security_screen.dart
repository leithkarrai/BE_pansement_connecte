import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';

/// Écran de sécurité et confidentialité
class SecurityScreen extends ConsumerStatefulWidget {
  const SecurityScreen({super.key});

  @override
  ConsumerState<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends ConsumerState<SecurityScreen> {
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _twoFactorEnabled = false;

  @override
  void dispose() {
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      final apiService = ApiService();
      await apiService.changePassword(
        oldPassword: _oldPasswordController.text,
        newPassword: _newPasswordController.text,
      );

      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('✅ Mot de passe modifié avec succès'),
            backgroundColor: Colors.green,
          ),
        );
        _oldPasswordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
                '❌ Erreur: ${e.toString().replaceFirst('Exception: ', '')}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sécurité et confidentialité'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Section Authentification
          Text(
            'Authentification',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.lock),
                  title: const Text('Changer le mot de passe'),
                  subtitle: const Text('Mettre à jour votre mot de passe'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    bool dialogObscureOld = true;
                    bool dialogObscureNew = true;
                    bool dialogObscureConfirm = true;

                    showDialog(
                      context: context,
                      builder: (dialogContext) => StatefulBuilder(
                        builder: (context, setDialogState) => AlertDialog(
                          title: const Text('Changer le mot de passe'),
                          content: SingleChildScrollView(
                            child: Form(
                              key: _formKey,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextFormField(
                                    controller: _oldPasswordController,
                                    obscureText: dialogObscureOld,
                                    decoration: InputDecoration(
                                      labelText: 'Ancien mot de passe',
                                      prefixIcon:
                                          const Icon(Icons.lock_outline),
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          dialogObscureOld
                                              ? Icons.visibility
                                              : Icons.visibility_off,
                                        ),
                                        onPressed: () {
                                          setDialogState(() {
                                            dialogObscureOld =
                                                !dialogObscureOld;
                                          });
                                        },
                                      ),
                                      border: const OutlineInputBorder(),
                                    ),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Veuillez entrer votre ancien mot de passe';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    controller: _newPasswordController,
                                    obscureText: dialogObscureNew,
                                    decoration: InputDecoration(
                                      labelText: 'Nouveau mot de passe',
                                      prefixIcon: const Icon(Icons.lock),
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          dialogObscureNew
                                              ? Icons.visibility
                                              : Icons.visibility_off,
                                        ),
                                        onPressed: () {
                                          setDialogState(() {
                                            dialogObscureNew =
                                                !dialogObscureNew;
                                          });
                                        },
                                      ),
                                      border: const OutlineInputBorder(),
                                    ),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Veuillez entrer un nouveau mot de passe';
                                      }
                                      if (value.length < 8) {
                                        return 'Le mot de passe doit contenir au moins 8 caractères';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    controller: _confirmPasswordController,
                                    obscureText: dialogObscureConfirm,
                                    decoration: InputDecoration(
                                      labelText: 'Confirmer le mot de passe',
                                      prefixIcon: const Icon(Icons.lock),
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          dialogObscureConfirm
                                              ? Icons.visibility
                                              : Icons.visibility_off,
                                        ),
                                        onPressed: () {
                                          setDialogState(() {
                                            dialogObscureConfirm =
                                                !dialogObscureConfirm;
                                          });
                                        },
                                      ),
                                      border: const OutlineInputBorder(),
                                    ),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Veuillez confirmer le mot de passe';
                                      }
                                      if (value !=
                                          _newPasswordController.text) {
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
                              onPressed: () {
                                _oldPasswordController.clear();
                                _newPasswordController.clear();
                                _confirmPasswordController.clear();
                                Navigator.pop(dialogContext);
                              },
                              child: const Text('Annuler'),
                            ),
                            ElevatedButton(
                              onPressed: () async {
                                if (_formKey.currentState!.validate()) {
                                  Navigator.pop(dialogContext);
                                  if (mounted) {
                                    await _changePassword();
                                  }
                                }
                              },
                              child: const Text('Modifier'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Authentification à deux facteurs'),
                  subtitle: const Text('Sécuriser votre compte avec 2FA'),
                  value: _twoFactorEnabled,
                  onChanged: (value) {
                    setState(() {
                      _twoFactorEnabled = value;
                    });
                    // TODO: Implémenter 2FA
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                      const SnackBar(
                        content: Text('2FA - À venir'),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Section Confidentialité
          Text(
            'Confidentialité',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.visibility),
                  title: const Text('Visibilité du profil'),
                  subtitle: const Text('Qui peut voir votre profil'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                      const SnackBar(
                        content: Text('Paramètres de visibilité - À venir'),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.data_usage),
                  title: const Text('Données personnelles'),
                  subtitle: const Text('Gérer vos données personnelles'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                      const SnackBar(
                        content: Text('Gestion des données - À venir'),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Section Sécurité avancée
          Text(
            'Sécurité avancée',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.devices),
              title: const Text('Appareils connectés'),
              subtitle: const Text('Gérer les appareils autorisés'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                  const SnackBar(
                    content: Text('Gestion des appareils - À venir'),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 24),

          // Section Informations
          Card(
            color: Colors.blue[50],
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue[700]),
                      const SizedBox(width: 8),
                      Text(
                        'Informations de sécurité',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[700],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Votre compte est protégé par un chiffrement de bout en bout. '
                    'Nous ne stockons jamais vos mots de passe en clair.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue[900],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
