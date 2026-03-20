import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/dashboard_provider.dart';
import '../widgets/device_list_tile.dart';
import '../models/device.dart';
import 'api_device_detail_screen.dart';

/// Écran complet de liste des devices
class DevicesListScreen extends ConsumerStatefulWidget {
  const DevicesListScreen({super.key});

  @override
  ConsumerState<DevicesListScreen> createState() => _DevicesListScreenState();
}

class _DevicesListScreenState extends ConsumerState<DevicesListScreen> {
  String? _selectedStatus;
  final TextEditingController _searchController = TextEditingController();
  bool _isSearchExpanded = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Device> _filterDevices(List<Device> devices) {
    var filtered = devices;

    // Filtre texte local (numéro, modèle, nom patient).
    if (_searchController.text.isNotEmpty) {
      final searchLower = _searchController.text.toLowerCase();
      filtered = filtered.where((device) {
        return device.serialNumber.toLowerCase().contains(searchLower) ||
            device.model.toLowerCase().contains(searchLower) ||
            (device.patientName != null &&
                device.patientName!.toLowerCase().contains(searchLower));
      }).toList();
    }

    // Filtre statut local.
    if (_selectedStatus != null) {
      filtered = filtered
          .where((device) => device.status.toLowerCase() == _selectedStatus)
          .toList();
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final devicesAsync = ref.watch(devicesProvider);

    // Liste opérationnelle des devices:
    // recherche + filtres + stats rapides + navigation vers le détail.
    return Scaffold(
      appBar: AppBar(
        title: _isSearchExpanded
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Rechercher par numéro, modèle, patient...',
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
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.medical_services, size: 20),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Tous les appareils',
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
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
              ref.invalidate(devicesProvider);
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(devicesProvider);
        },
        child: devicesAsync.when(
          data: (devices) {
            final filteredDevices = _filterDevices(devices);

            if (filteredDevices.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.medical_services_outlined,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      devices.isEmpty
                          ? 'Aucun appareil trouvé'
                          : 'Aucun résultat pour votre recherche',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      devices.isEmpty
                          ? 'Les appareils apparaîtront ici une fois créés'
                          : 'Essayez de modifier vos critères de recherche',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[500],
                      ),
                    ),
                    if (devices.isNotEmpty &&
                        (_selectedStatus != null ||
                            _searchController.text.isNotEmpty))
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: ElevatedButton.icon(
                          onPressed: () {
                            setState(() {
                              _searchController.clear();
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
                if (_selectedStatus != null ||
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
                              if (_selectedStatus != null)
                                Chip(
                                  label: Text(
                                      'Statut: ${_getStatusLabel(_selectedStatus!)}'),
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
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${filteredDevices.length} appareil${filteredDevices.length > 1 ? 's' : ''}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (filteredDevices.length != devices.length)
                                  Text(
                                    'sur ${devices.length} total',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
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
                      // Compteurs par statut
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          _buildStatusCounter(
                            context,
                            'Actifs',
                            filteredDevices
                                .where(
                                    (d) => d.status.toLowerCase() == 'active')
                                .length,
                            Colors.green,
                            Icons.check_circle,
                          ),
                          _buildStatusCounter(
                            context,
                            'Inactifs',
                            filteredDevices
                                .where(
                                    (d) => d.status.toLowerCase() == 'inactive')
                                .length,
                            Colors.grey,
                            Icons.cancel,
                          ),
                          _buildStatusCounter(
                            context,
                            'Maintenance',
                            filteredDevices
                                .where((d) =>
                                    d.status.toLowerCase() == 'maintenance')
                                .length,
                            Colors.orange,
                            Icons.build,
                          ),
                          _buildStatusCounter(
                            context,
                            'Assignés',
                            filteredDevices
                                .where((d) => d.patientId != null)
                                .length,
                            Colors.blue,
                            Icons.person,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Liste des devices filtrés
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: filteredDevices.length,
                    itemBuilder: (context, index) {
                      final device = filteredDevices[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: DeviceListTile(
                          device: device,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    ApiDeviceDetailScreen(deviceId: device.id),
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
                    ref.invalidate(devicesProvider);
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

  void _showFilterDialog(BuildContext context) {
    String? tempStatus = _selectedStatus;

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
                      '✅ Actif',
                      tempStatus == 'active',
                      () {
                        setDialogState(() {
                          tempStatus = 'active';
                        });
                      },
                    ),
                    _buildFilterChip(
                      '⚪ Inactif',
                      tempStatus == 'inactive',
                      () {
                        setDialogState(() {
                          tempStatus = 'inactive';
                        });
                      },
                    ),
                    _buildFilterChip(
                      '🔧 Maintenance',
                      tempStatus == 'maintenance',
                      () {
                        setDialogState(() {
                          tempStatus = 'maintenance';
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
                  setState(() {
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
    );
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

  Widget _buildStatusCounter(
    BuildContext context,
    String label,
    int count,
    Color color,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: _getDarkerColor(color),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: _getDarkerColor(color),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withOpacity(0.3),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              count.toString(),
              style: TextStyle(
                fontSize: 13,
                color: _getDarkerColor(color),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getDarkerColor(Color color) {
    return Color.fromRGBO(
      (color.red * 0.7).round().clamp(0, 255),
      (color.green * 0.7).round().clamp(0, 255),
      (color.blue * 0.7).round().clamp(0, 255),
      1.0,
    );
  }

  String _getStatusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return 'Actif';
      case 'inactive':
        return 'Inactif';
      case 'maintenance':
        return 'Maintenance';
      case 'retired':
        return 'Retiré';
      default:
        return status;
    }
  }
}
