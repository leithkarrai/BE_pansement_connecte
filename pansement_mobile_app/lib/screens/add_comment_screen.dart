// ============================================
// Écran Ajout Commentaire - Médecin
// ============================================
// Fichier : lib/screens/add_comment_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/comments_provider.dart';
import '../models/user.dart';

class AddCommentScreen extends ConsumerStatefulWidget {
  final User patient;
  final String? measurementId;

  const AddCommentScreen({
    super.key,
    required this.patient,
    this.measurementId,
  });

  @override
  ConsumerState<AddCommentScreen> createState() => _AddCommentScreenState();
}

class _AddCommentScreenState extends ConsumerState<AddCommentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _commentController = TextEditingController();
  bool _sendNotification = true;
  bool _sendEmail = false;

  @override
  void initState() {
    super.initState();
    // Écouter les changements du TextField pour mettre à jour le compteur
    _commentController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submitComment() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    try {
      // Création du commentaire via provider (backend = source d'autorité permissions).
      final success =
          await ref.read(commentsNotifierProvider.notifier).createComment(
                patientId: widget.patient.id,
                commentText: _commentController.text.trim(),
                measurementId: widget.measurementId,
              );

      // Fermer l'écran immédiatement après le succès
      // L'écran parent affichera le message de succès
      if (success && mounted) {
        Navigator.of(context).pop(true);
        return;
      }

      // En cas d'erreur, afficher le message
      if (!success && mounted) {
        final error = ref.read(commentsNotifierProvider).error;
        final messenger = ScaffoldMessenger.maybeOf(context);
        if (messenger != null) {
          messenger.showSnackBar(
            SnackBar(
              content: Text('❌ ${error ?? "Erreur inconnue"}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger != null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('❌ Erreur: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final commentsState = ref.watch(commentsNotifierProvider);

    // Formulaire guidé d'ajout de commentaire médical.
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nouveau commentaire'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Info patient
            Card(
              color: Colors.blue[50],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: Theme.of(context).primaryColor,
                      child: Text(
                        widget.patient.firstName.isNotEmpty
                            ? widget.patient.firstName[0].toUpperCase()
                            : 'P',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Patient',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                          Text(
                            widget.patient.fullName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Titre section
            const Text(
              'Votre commentaire',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),

            // Champ de commentaire
            TextFormField(
              controller: _commentController,
              maxLines: 8,
              maxLength: 500,
              decoration: InputDecoration(
                hintText: 'Ex: La plaie est en bonne voie de guérison. '
                    'Température normale, pas d\'inquiétude 👍',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey[50],
                counterText: '', // Masquer le compteur par défaut
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Veuillez entrer un commentaire';
                }
                if (value.trim().length < 10) {
                  return 'Le commentaire doit contenir au moins 10 caractères';
                }
                return null;
              },
            ),

            // Compteur de caractères
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${_commentController.text.length}/500 caractères',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.right,
              ),
            ),

            const SizedBox(height: 24),

            // Suggestions rapides
            const Text(
              'Suggestions',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _SuggestionChip(
                  label: 'Tout va bien 👍',
                  onTap: () => _addText('Tout va bien, continuez ainsi 👍'),
                ),
                _SuggestionChip(
                  label: 'Bonne évolution',
                  onTap: () =>
                      _addText('La plaie est en bonne voie de guérison'),
                ),
                _SuggestionChip(
                  label: 'Température normale',
                  onTap: () =>
                      _addText('Température normale, pas d\'inquiétude'),
                ),
                _SuggestionChip(
                  label: 'À surveiller',
                  onTap: () => _addText('À surveiller dans les prochaines 24h'),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Options de notification
            const Text(
              'Notifications',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  CheckboxListTile(
                    title: const Text('Notification push'),
                    subtitle:
                        const Text('Le patient sera notifié instantanément'),
                    value: _sendNotification,
                    onChanged: (value) {
                      setState(() {
                        _sendNotification = value ?? true;
                      });
                    },
                  ),
                  const Divider(height: 1),
                  CheckboxListTile(
                    title: const Text('Email'),
                    subtitle: const Text('Envoyer un email au patient'),
                    value: _sendEmail,
                    onChanged: (value) {
                      setState(() {
                        _sendEmail = value ?? false;
                      });
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Boutons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: commentsState.isLoading
                        ? null
                        : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                    ),
                    child: const Text('Annuler'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: commentsState.isLoading ? null : _submitComment,
                    icon: commentsState.isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send),
                    label: Text(
                      commentsState.isLoading ? 'Envoi...' : 'Publier',
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _addText(String text) {
    final currentText = _commentController.text;
    if (currentText.isNotEmpty && !currentText.endsWith('\n')) {
      _commentController.text = '$currentText\n$text';
    } else {
      _commentController.text = currentText + text;
    }
    _commentController.selection = TextSelection.fromPosition(
      TextPosition(offset: _commentController.text.length),
    );
  }
}

// ============================================
// WIDGET : Suggestion Chip
// ============================================

class _SuggestionChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SuggestionChip({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      onPressed: onTap,
      backgroundColor: Colors.grey[100],
      side: BorderSide(color: Colors.grey[300]!),
    );
  }
}
