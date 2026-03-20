import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../providers/comments_provider.dart';
import '../models/comment.dart';
import '../models/user.dart';
import 'add_comment_screen.dart';

class PatientCommentsScreen extends ConsumerStatefulWidget {
  final String patientId;
  final String patientName;
  final User? patient; // Optionnel : objet User complet

  const PatientCommentsScreen({
    super.key,
    required this.patientId,
    required this.patientName,
    this.patient,
  });

  @override
  ConsumerState<PatientCommentsScreen> createState() =>
      _PatientCommentsScreenState();
}

class _PatientCommentsScreenState extends ConsumerState<PatientCommentsScreen> {
  bool _loading = false;
  String? _error;
  List<Comment> _comments = [];

  @override
  void initState() {
    super.initState();
    _fetchComments();
  }

  Future<void> _fetchComments() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiServiceProvider);
      final data = await api.getPatientComments(widget.patientId, limit: 100);
      if (!mounted) return;
      setState(() {
        _comments = data;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _deleteComment(Comment c) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer le commentaire'),
        content: const Text(
          'Voulez-vous vraiment supprimer ce commentaire ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final success = await ref
        .read(commentsNotifierProvider.notifier)
        .deleteComment(c.id);
    if (!mounted) return;
    if (success) {
      _fetchComments();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Commentaire supprimé'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      final error = ref.read(commentsNotifierProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur: ${error ?? "Impossible de supprimer"}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteSeveralComments(List<Comment> toDelete) async {
    if (toDelete.isEmpty) return;
    final count = toDelete.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer les commentaires'),
        content: Text(
          count == 1
              ? 'Voulez-vous vraiment supprimer ce commentaire ?'
              : 'Voulez-vous vraiment supprimer ces $count commentaires ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(count == 1 ? 'Supprimer' : 'Tout supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    int deleted = 0;
    for (final c in toDelete) {
      final ok = await ref
          .read(commentsNotifierProvider.notifier)
          .deleteComment(c.id);
      if (ok) deleted++;
      if (!mounted) return;
    }
    _fetchComments();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          deleted == 1
              ? 'Commentaire supprimé'
              : '$deleted commentaire${deleted > 1 ? 's' : ''} supprimé${deleted > 1 ? 's' : ''}',
        ),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final isPatient = user?.role.toLowerCase() == 'patient';
    final isAdmin = user?.role.toLowerCase() == 'admin';
    final isMedecin = user?.role.toLowerCase() == 'medecin';
    final currentUserId = user?.id ?? '';
    // Admin : peut supprimer tous les commentaires. Médecin : uniquement les siens.
    final canDeleteComment = (Comment c) =>
        isAdmin || (isMedecin && c.medecinId == currentUserId);
    final deletableComments = _comments.where(canDeleteComment).toList();
    final hasDeletable = deletableComments.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text('Commentaires - ${widget.patientName}'),
        actions: [
          if (hasDeletable)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              tooltip: 'Options',
              onSelected: (value) async {
                if (value == 'delete_all' && isAdmin) {
                  await _deleteSeveralComments(List.from(_comments));
                } else if (value == 'delete_mine' && isMedecin) {
                  await _deleteSeveralComments(
                    _comments.where((c) => c.medecinId == currentUserId).toList(),
                  );
                }
              },
              itemBuilder: (context) => [
                if (isAdmin && _comments.isNotEmpty)
                  const PopupMenuItem(
                    value: 'delete_all',
                    child: Row(
                      children: [
                        Icon(Icons.delete_sweep, color: Colors.red, size: 22),
                        SizedBox(width: 12),
                        Expanded(
                            child: Text('Supprimer tous les commentaires')),
                      ],
                    ),
                  ),
                if (isMedecin &&
                    _comments.any((c) => c.medecinId == currentUserId))
                  const PopupMenuItem(
                    value: 'delete_mine',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, color: Colors.red, size: 22),
                        SizedBox(width: 12),
                        Expanded(child: Text('Supprimer mes commentaires')),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchComments,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  )
                : _comments.isEmpty
                    ? ListView(
                        children: const [
                          Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('Aucun commentaire pour l\'instant.'),
                          ),
                        ],
                      )
                    : ListView.builder(
                        itemCount: _comments.length,
                        itemBuilder: (context, index) {
                          final c = _comments[index];
                          final canDelete = canDeleteComment(c);
                          return ListTile(
                            leading: CircleAvatar(
                              child: Text(
                                c.medecinName.isNotEmpty
                                    ? c.medecinName[0].toUpperCase()
                                    : 'M',
                              ),
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(c.medecinName),
                                ),
                                if (!c.isRead)
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: Colors.blue,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(c.commentText),
                                const SizedBox(height: 4),
                                Text(
                                  c.getFormattedDate(),
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (c.measurementId != null)
                                  const Icon(Icons.analytics, size: 18),
                                if (canDelete)
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    color: Colors.red,
                                    tooltip: 'Supprimer',
                                    onPressed: () => _deleteComment(c),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
      ),
      floatingActionButton: isPatient
          ? null
          : FloatingActionButton.extended(
              onPressed: () async {
                // Récupérer l'objet User du patient si disponible, sinon créer un objet minimal
                User? patientUser = widget.patient;

                if (patientUser == null) {
                  // Si l'objet User n'est pas fourni, essayer de le récupérer depuis l'API
                  try {
                    final api = ref.read(apiServiceProvider);
                    patientUser = await api.getUser(widget.patientId);
                  } catch (e) {
                    // Si erreur, créer un objet User minimal avec les données disponibles
                    patientUser = User(
                      id: widget.patientId,
                      email: '',
                      firstName: widget.patientName.split(' ').first,
                      lastName: widget.patientName.split(' ').length > 1
                          ? widget.patientName.split(' ').skip(1).join(' ')
                          : '',
                      role: 'patient',
                    );
                  }
                }

                // Ouvrir l'écran d'ajout de commentaire
                final result = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AddCommentScreen(
                      patient: patientUser!,
                    ),
                  ),
                );

                // Si un commentaire a été ajouté, rafraîchir la liste et afficher un message
                if (result == true) {
                  _fetchComments();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('✅ Commentaire publié avec succès'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                }
              },
              icon: const Icon(Icons.add_comment),
              label: const Text('Commenter'),
            ),
    );
  }
}
