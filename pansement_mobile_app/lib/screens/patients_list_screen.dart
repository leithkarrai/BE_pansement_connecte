import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../providers/dashboard_provider.dart';
import '../widgets/patient_list_tile.dart';
import 'patient_detail_screen.dart';
import 'create_edit_patient_screen.dart';

class PatientsListScreen extends ConsumerStatefulWidget {
  const PatientsListScreen({super.key});

  @override
  ConsumerState<PatientsListScreen> createState() => _PatientsListScreenState();
}

class _PatientsListScreenState extends ConsumerState<PatientsListScreen> {
  String _searchQuery = '';
  String _filterStatus = 'all'; // all, active, inactive

  @override
  Widget build(BuildContext context) {
    final patientsAsync = ref.watch(patientsProvider);
    final currentUser = ref.watch(authProvider).user;
    final canAddPatient = currentUser?.role == 'admin';

    // Vue liste utilisateurs orientée "patients":
    // recherche + filtre statut + refresh provider.
    return Column(
      children: [
        // Header avec titre et bouton filtre
        Container(
          padding: const EdgeInsets.all(16),
          color: Theme.of(context).primaryColor,
          child: Row(
            children: [
              const Icon(Icons.people, color: Colors.white),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Patients',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.filter_list, color: Colors.white),
                onPressed: () => _showFilterDialog(),
                tooltip: 'Filtres',
              ),
            ],
          ),
        ),

        // Barre de recherche
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Material(
            color: Colors.transparent,
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Rechercher un patient...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey[50],
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.toLowerCase();
                });
              },
            ),
          ),
        ),

        // Filtres actifs
        if (_filterStatus != 'all')
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Filtre: ${_filterStatus == "active" ? "Actifs" : "Inactifs"}',
                    style: TextStyle(color: Colors.blue[900]),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _filterStatus = 'all';
                      });
                    },
                    child: Icon(
                      Icons.close,
                      size: 18,
                      color: Colors.blue[900],
                    ),
                  ),
                ],
              ),
            ),
          ),

        const SizedBox(height: 8),

        // Liste des patients
        Expanded(
          child: patientsAsync.when(
            data: (patients) {
              // Filtrage combiné local: texte + statut actif/inactif.
              var filteredPatients = patients.where((patient) {
                final matchesSearch = _searchQuery.isEmpty ||
                    patient.fullName.toLowerCase().contains(_searchQuery) ||
                    patient.email.toLowerCase().contains(_searchQuery);

                final matchesStatus = _filterStatus == 'all' ||
                    (_filterStatus == 'active' && patient.isActive) ||
                    (_filterStatus == 'inactive' && !patient.isActive);

                return matchesSearch && matchesStatus;
              }).toList();

              if (filteredPatients.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _searchQuery.isEmpty
                            ? Icons.people_outline
                            : Icons.search_off,
                        size: 80,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _searchQuery.isEmpty
                            ? 'Aucun patient'
                            : 'Aucun résultat trouvé',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey[600],
                        ),
                      ),
                      if (_searchQuery.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Essayez avec d\'autres termes',
                          style: TextStyle(
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(patientsProvider);
                },
                child: ListView.builder(
                  padding: const EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 8,
                    bottom: 80,
                  ),
                  itemCount: filteredPatients.length + (canAddPatient ? 1 : 0),
                  itemBuilder: (context, index) {
                    // Action de création réservée à l'admin.
                    if (canAddPatient && index == filteredPatients.length) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const CreateEditPatientScreen(),
                              ),
                            );
                            if (result == true) {
                              ref.invalidate(patientsProvider);
                            }
                          },
                          icon: const Icon(Icons.person_add),
                          label: const Text('Nouveau patient'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.all(16),
                            minimumSize: const Size(double.infinity, 50),
                          ),
                        ),
                      );
                    }

                    final patient = filteredPatients[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: PatientListTile(
                        patient: patient,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PatientDetailScreen(
                                patientId: patient.id,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              );
            },
            loading: () => const Center(
              child: CircularProgressIndicator(),
            ),
            error: (error, stackTrace) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 80,
                    color: Colors.red[300],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Erreur de chargement',
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
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ),
                  const SizedBox(height: 16),
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
      ],
    );
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filtrer les patients'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<String>(
              title: const Text('Tous les patients'),
              value: 'all',
              groupValue: _filterStatus,
              onChanged: (value) {
                setState(() {
                  _filterStatus = value!;
                });
                Navigator.pop(context);
              },
            ),
            RadioListTile<String>(
              title: const Text('Patients actifs'),
              value: 'active',
              groupValue: _filterStatus,
              onChanged: (value) {
                setState(() {
                  _filterStatus = value!;
                });
                Navigator.pop(context);
              },
            ),
            RadioListTile<String>(
              title: const Text('Patients inactifs'),
              value: 'inactive',
              groupValue: _filterStatus,
              onChanged: (value) {
                setState(() {
                  _filterStatus = value!;
                });
                Navigator.pop(context);
              },
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
