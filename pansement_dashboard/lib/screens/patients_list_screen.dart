import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/dashboard_provider.dart';
import '../widgets/patient_list_tile.dart';
import '../models/user.dart';
import 'patient_detail_screen.dart';

/// Écran complet de liste des patients pour l'admin
class PatientsListScreen extends ConsumerStatefulWidget {
  const PatientsListScreen({super.key});

  @override
  ConsumerState<PatientsListScreen> createState() => _PatientsListScreenState();
}

class _PatientsListScreenState extends ConsumerState<PatientsListScreen> {
  final TextEditingController _searchController = TextEditingController();
  String? _selectedRole;
  bool? _selectedStatus; // null = tous, true = actif, false = inactif
  bool _isSearchExpanded = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<User> _filterUsers(List<User> users) {
    var filtered = users;

    // Filtre par recherche (nom, email, téléphone)
    if (_searchController.text.isNotEmpty) {
      final searchLower = _searchController.text.toLowerCase();
      filtered = filtered.where((user) {
        return user.fullName.toLowerCase().contains(searchLower) ||
            user.email.toLowerCase().contains(searchLower) ||
            (user.phone != null &&
                user.phone!.toLowerCase().contains(searchLower));
      }).toList();
    }

    // Filtre par rôle
    if (_selectedRole != null) {
      filtered = filtered.where((user) => user.role == _selectedRole).toList();
    }

    // Filtre par statut
    if (_selectedStatus != null) {
      filtered =
          filtered.where((user) => user.isActive == _selectedStatus).toList();
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final patientsAsync = ref.watch(patientsProvider);

    return Scaffold(
      appBar: AppBar(
        title: _isSearchExpanded
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Rechercher par nom, email, téléphone...',
                  border: InputBorder.none,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      setState(() {
                        _searchController.clear();
                        _isSearchExpanded = false;
                      });
                    },
                  ),
                ),
                onChanged: (value) {
                  setState(() {});
                },
              )
            : const Row(
                children: [
                  Icon(Icons.people),
                  SizedBox(width: 8),
                  Text('Tous les utilisateurs'),
                ],
              ),
        actions: [
          if (!_isSearchExpanded)
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'Rechercher',
              onPressed: () {
                setState(() {
                  _isSearchExpanded = true;
                });
              },
            ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filtres',
            onPressed: () {
              _showFilterDialog(context);
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualiser',
            onPressed: () {
              ref.invalidate(patientsProvider);
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(patientsProvider);
        },
        child: patientsAsync.when(
          data: (patients) {
            final filteredPatients = _filterUsers(patients);

            if (filteredPatients.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.people_outline,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      patients.isEmpty
                          ? 'Aucun utilisateur trouvé'
                          : 'Aucun résultat pour votre recherche',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      patients.isEmpty
                          ? 'Les utilisateurs apparaîtront ici une fois créés'
                          : 'Essayez de modifier vos critères de recherche',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[500],
                      ),
                    ),
                    if (patients.isNotEmpty &&
                        (_selectedRole != null ||
                            _selectedStatus != null ||
                            _searchController.text.isNotEmpty))
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: ElevatedButton.icon(
                          onPressed: () {
                            setState(() {
                              _searchController.clear();
                              _selectedRole = null;
                              _selectedStatus = null;
                            });
                          },
                          icon: const Icon(Icons.clear_all),
                          label: const Text('Réinitialiser les filtres'),
                        ),
                      ),
                  ],
                ),
              );
            }

            return Column(
              children: [
                // Indicateurs de filtres actifs
                if (_selectedRole != null ||
                    _selectedStatus != null ||
                    _searchController.text.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: Colors.blue[50],
                    child: Row(
                      children: [
                        Icon(Icons.filter_alt,
                            size: 16, color: Colors.blue[700]),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              if (_searchController.text.isNotEmpty)
                                Chip(
                                  label: Text(
                                      'Recherche: ${_searchController.text}'),
                                  onDeleted: () {
                                    setState(() {
                                      _searchController.clear();
                                    });
                                  },
                                  deleteIcon: const Icon(Icons.close, size: 18),
                                ),
                              if (_selectedRole != null)
                                Chip(
                                  label: Text(
                                      'Rôle: ${_getRoleLabel(_selectedRole!)}'),
                                  onDeleted: () {
                                    setState(() {
                                      _selectedRole = null;
                                    });
                                  },
                                  deleteIcon: const Icon(Icons.close, size: 18),
                                ),
                              if (_selectedStatus != null)
                                Chip(
                                  label: Text(
                                      'Statut: ${_selectedStatus! ? "Actif" : "Inactif"}'),
                                  onDeleted: () {
                                    setState(() {
                                      _selectedStatus = null;
                                    });
                                  },
                                  deleteIcon: const Icon(Icons.close, size: 18),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                // En-tête avec statistiques
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.grey[100],
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${filteredPatients.length} utilisateur${filteredPatients.length > 1 ? 's' : ''}',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              if (filteredPatients.length != patients.length)
                                Text(
                                  'sur ${patients.length} total',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                          Text(
                            'Résultats',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Compteurs par rôle (sur les résultats filtrés)
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          _buildRoleCounter(
                            context,
                            '👤 Patients',
                            filteredPatients
                                .where((u) => u.role == 'patient')
                                .length,
                            Colors.blue,
                          ),
                          _buildRoleCounter(
                            context,
                            '🩺 Médecins',
                            filteredPatients
                                .where((u) => u.role == 'medecin')
                                .length,
                            Colors.green,
                          ),
                          _buildRoleCounter(
                            context,
                            '👑 Admins',
                            filteredPatients
                                .where((u) => u.role == 'admin')
                                .length,
                            Colors.red,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Liste des patients filtrés
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: filteredPatients.length,
                    itemBuilder: (context, index) {
                      final patient = filteredPatients[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: PatientListTile(
                          patient: patient,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    PatientDetailScreen(patientId: patient.id),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
          loading: () => const Center(
            child: CircularProgressIndicator(),
          ),
          error: (error, stack) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Colors.red[300],
                ),
                const SizedBox(height: 16),
                Text(
                  'Erreur lors du chargement',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.red[700],
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    error.toString(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () {
                    ref.invalidate(patientsProvider);
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getDarkerColor(Color color) {
    // Retourne une version plus foncée de la couleur
    return Color.fromRGBO(
      (color.red * 0.7).round().clamp(0, 255),
      (color.green * 0.7).round().clamp(0, 255),
      (color.blue * 0.7).round().clamp(0, 255),
      1.0,
    );
  }

  Widget _buildRoleCounter(
    BuildContext context,
    String label,
    int count,
    Color color,
  ) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: _getDarkerColor(color),
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                count.toString(),
                style: TextStyle(
                  fontSize: 12,
                  color: _getDarkerColor(color),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showFilterDialog(BuildContext context) {
    // Variables temporaires pour le dialogue
    String? tempRole = _selectedRole;
    bool? tempStatus = _selectedStatus;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Filtres'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Filtre par rôle
                const Text(
                  'Rôle',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    _buildFilterChip(
                      'Tous',
                      tempRole == null,
                      () {
                        setDialogState(() {
                          tempRole = null;
                        });
                      },
                    ),
                    _buildFilterChip(
                      '👤 Patient',
                      tempRole == 'patient',
                      () {
                        setDialogState(() {
                          tempRole = 'patient';
                        });
                      },
                    ),
                    _buildFilterChip(
                      '🩺 Médecin',
                      tempRole == 'medecin',
                      () {
                        setDialogState(() {
                          tempRole = 'medecin';
                        });
                      },
                    ),
                    _buildFilterChip(
                      '👑 Admin',
                      tempRole == 'admin',
                      () {
                        setDialogState(() {
                          tempRole = 'admin';
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Filtre par statut
                const Text(
                  'Statut',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    _buildFilterChip(
                      'Tous',
                      tempStatus == null,
                      () {
                        setDialogState(() {
                          tempStatus = null;
                        });
                      },
                    ),
                    _buildFilterChip(
                      'Actif',
                      tempStatus == true,
                      () {
                        setDialogState(() {
                          tempStatus = true;
                        });
                      },
                    ),
                    _buildFilterChip(
                      'Inactif',
                      tempStatus == false,
                      () {
                        setDialogState(() {
                          tempStatus = false;
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  setDialogState(() {
                    tempRole = null;
                    tempStatus = null;
                  });
                },
                child: const Text('Réinitialiser'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text('Annuler'),
              ),
              ElevatedButton(
                onPressed: () {
                  // Appliquer les filtres sélectionnés
                  setState(() {
                    _selectedRole = tempRole;
                    _selectedStatus = tempStatus;
                  });
                  Navigator.of(context).pop();
                },
                child: const Text('Appliquer'),
              ),
            ],
          );
        },
      ),
    ).then((_) {
      // Si le dialogue est fermé sans cliquer sur "Appliquer", rien ne change
      // Les valeurs sont déjà mises à jour si "Appliquer" a été cliqué
    });
  }

  Widget _buildFilterChip(String label, bool isSelected, VoidCallback onTap) {
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onTap(),
      selectedColor: Theme.of(context).primaryColor.withOpacity(0.2),
      checkmarkColor: Theme.of(context).primaryColor,
    );
  }

  String _getRoleLabel(String role) {
    switch (role) {
      case 'admin':
        return 'Administrateur';
      case 'medecin':
        return 'Médecin';
      case 'patient':
        return 'Patient';
      default:
        return role;
    }
  }
}
