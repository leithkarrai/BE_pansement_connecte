import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
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

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final isPatient = user?.role == 'patient';

    return Scaffold(
      appBar: AppBar(
        title: Text('Commentaires - ${widget.patientName}'),
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
                            trailing: c.measurementId != null
                                ? const Icon(Icons.analytics, size: 18)
                                : null,
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
