import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/alerts_provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/alert_list_tile.dart';
import '../models/alert.dart';

class AlertsScreen extends ConsumerStatefulWidget {
  const AlertsScreen({super.key});

  @override
  ConsumerState<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends ConsumerState<AlertsScreen> {
  String? _selectedSeverity;
  String? _selectedAlertType;
  bool _unacknowledgedOnly = false;

  @override
  Widget build(BuildContext context) {
    final alertsAsync = ref.watch(alertsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_active),
            SizedBox(width: 8),
            Flexible(
              child: Text('Alertes', overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filtres',
            onPressed: () => _showFilterDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualiser',
            onPressed: () {
              ref.invalidate(alertsProvider);
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(alertsProvider);
        },
        child: alertsAsync.when(
          data: (data) {
            final alertsList = (data['alerts'] as List?)
                    ?.map((json) => Alert.fromJson(json))
                    .toList() ??
                [];

            // Appliquer les filtres locaux
            var filteredAlerts = alertsList;
            if (_selectedSeverity != null) {
              filteredAlerts = filteredAlerts
                  .where((a) => a.severity == _selectedSeverity)
                  .toList();
            }
            if (_selectedAlertType != null) {
              filteredAlerts = filteredAlerts
                  .where((a) => a.alertType == _selectedAlertType)
                  .toList();
            }
            if (_unacknowledgedOnly) {
              filteredAlerts =
                  filteredAlerts.where((a) => !a.isAcknowledged).toList();
            }

            if (filteredAlerts.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.notifications_off,
                        size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text(
                      'Aucune alerte',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              );
            }

            return Column(
              children: [
                // Statistiques en haut
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.grey[100],
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatChip(
                        'Total',
                        data['total']?.toString() ?? '0',
                        Colors.blue,
                      ),
                      _buildStatChip(
                        'Non acquittées',
                        data['unacknowledged']?.toString() ?? '0',
                        Colors.orange,
                      ),
                      _buildStatChip(
                        'Critiques',
                        data['critical']?.toString() ?? '0',
                        Colors.red,
                      ),
                    ],
                  ),
                ),
                // Liste des alertes
                Expanded(
                  child: ListView.builder(
                    itemCount: filteredAlerts.length,
                    itemBuilder: (context, index) {
                      final alert = filteredAlerts[index];
                      return AlertListTile(
                        alert: alert,
                        onTap: () {
                          _showAlertDetails(context, alert);
                        },
                        onAcknowledge: alert.isAcknowledged
                            ? null
                            : () => _acknowledgeAlert(context, alert),
                      );
                    },
                  ),
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                const SizedBox(height: 16),
                Text('Erreur: $error'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    ref.invalidate(alertsProvider);
                  },
                  child: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }

  void _showFilterDialog(BuildContext context) {
    String? tempSeverity = _selectedSeverity;
    String? tempAlertType = _selectedAlertType;
    bool tempUnacknowledged = _unacknowledgedOnly;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Filtrer les alertes'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Sévérité',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Wrap(
                  spacing: 8,
                  children: [
                    _buildFilterChip(
                      'Toutes',
                      tempSeverity == null,
                      () => setDialogState(() => tempSeverity = null),
                    ),
                    _buildFilterChip(
                      'Critique',
                      tempSeverity == 'critical',
                      () => setDialogState(() => tempSeverity = 'critical'),
                    ),
                    _buildFilterChip(
                      'Avertissement',
                      tempSeverity == 'warning',
                      () => setDialogState(() => tempSeverity = 'warning'),
                    ),
                    _buildFilterChip(
                      'Info',
                      tempSeverity == 'info',
                      () => setDialogState(() => tempSeverity = 'info'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('Type',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Wrap(
                  spacing: 8,
                  children: [
                    _buildFilterChip(
                      'Tous',
                      tempAlertType == null,
                      () => setDialogState(() => tempAlertType = null),
                    ),
                    _buildFilterChip(
                      'Température',
                      tempAlertType == 'temperature',
                      () => setDialogState(() => tempAlertType = 'temperature'),
                    ),
                    _buildFilterChip(
                      'Humidité',
                      tempAlertType == 'impedance',
                      () => setDialogState(() => tempAlertType = 'impedance'),
                    ),
                    _buildFilterChip(
                      'pH',
                      tempAlertType == 'orp',
                      () => setDialogState(() => tempAlertType = 'orp'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  title: const Text('Non acquittées uniquement'),
                  value: tempUnacknowledged,
                  onChanged: (value) {
                    setDialogState(() => tempUnacknowledged = value ?? false);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  setState(() {
                    _selectedSeverity = null;
                    _selectedAlertType = null;
                    _unacknowledgedOnly = false;
                  });
                  Navigator.of(context).pop();
                },
                child: const Text('Réinitialiser'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Annuler'),
              ),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _selectedSeverity = tempSeverity;
                    _selectedAlertType = tempAlertType;
                    _unacknowledgedOnly = tempUnacknowledged;
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
      selectedColor: Theme.of(context).primaryColor.withValues(alpha: 0.3),
    );
  }

  void _showAlertDetails(BuildContext context, Alert alert) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(alert.title),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(alert.message),
              const SizedBox(height: 16),
              if (alert.currentValue != null)
                Text(
                    'Valeur actuelle: ${alert.currentValue!.toStringAsFixed(2)}'),
              if (alert.thresholdValue != null)
                Text('Seuil: ${alert.thresholdValue!.toStringAsFixed(2)}'),
              const SizedBox(height: 8),
              Text('Type: ${alert.alertType}'),
              Text('Sévérité: ${alert.severity}'),
              Text(
                  'Déclenchée le: ${DateFormat('dd/MM/yyyy HH:mm').format(alert.triggeredAt)}'),
              if (alert.acknowledgedAt != null)
                Text(
                    'Acquittée le: ${DateFormat('dd/MM/yyyy HH:mm').format(alert.acknowledgedAt!)}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  Future<void> _acknowledgeAlert(BuildContext context, Alert alert) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Acquitter l\'alerte'),
        content: const Text('Voulez-vous marquer cette alerte comme vue ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Acquitter'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final apiService = ref.read(apiServiceProvider);
        await apiService.acknowledgeAlert(alert.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Alerte acquittée avec succès'),
              backgroundColor: Colors.green,
            ),
          );
          ref.invalidate(alertsProvider);
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erreur: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
}
