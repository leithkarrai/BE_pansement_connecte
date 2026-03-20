import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/measurements_provider.dart';
import '../providers/auth_provider.dart';
import '../models/user.dart';
import '../models/measurement.dart';

/// Écran pour l'admin : Données brutes de toutes les mesures (incluant ADC)
class AdminRawDataScreen extends ConsumerStatefulWidget {
  final User patient;

  const AdminRawDataScreen({
    super.key,
    required this.patient,
  });

  @override
  ConsumerState<AdminRawDataScreen> createState() => _AdminRawDataScreenState();
}

class _AdminRawDataScreenState extends ConsumerState<AdminRawDataScreen> {
  String _selectedTimeRange = '7'; // 7 jours par défaut
  String? _selectedMeasurementType;

  @override
  Widget build(BuildContext context) {
    final measurementsAsync = ref.watch(
      patientMeasurementsProvider(widget.patient.id),
    );

    // Vue "raw data" admin:
    // inspection brute des mesures (dont ADC/freq/phase) avec filtres période/type.
    return Scaffold(
      appBar: AppBar(
        title: Text('Données brutes - ${widget.patient.fullName}'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            onSelected: (value) {
              setState(() {
                _selectedMeasurementType = value == 'all' ? null : value;
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'all',
                child: Text('Tous les types'),
              ),
              const PopupMenuItem(
                value: 'adc',
                child: Text('Valeur ADC'),
              ),
              const PopupMenuItem(
                value: 'temperature',
                child: Text('Température'),
              ),
              const PopupMenuItem(
                value: 'impedance',
                child: Text('Impédance'),
              ),
            ],
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.calendar_today),
            onSelected: (value) {
              setState(() {
                _selectedTimeRange = value;
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: '1',
                child: Text('Dernières 24h'),
              ),
              const PopupMenuItem(
                value: '7',
                child: Text('7 derniers jours'),
              ),
              const PopupMenuItem(
                value: '30',
                child: Text('30 derniers jours'),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Rafraîchir les données',
            onPressed: () {
              ref.invalidate(patientMeasurementsProvider(widget.patient.id));
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(patientMeasurementsProvider(widget.patient.id));
          await ref.read(patientMeasurementsProvider(widget.patient.id).future);
        },
        child: measurementsAsync.when(
          data: (allMeasurements) {
          // Filtres locaux d'affichage appliqués après récupération des mesures.
          final now = DateTime.now();
          final days = int.parse(_selectedTimeRange);
          final cutoffDate = now.subtract(Duration(days: days));
          var filteredMeasurements = allMeasurements
              .where((m) => m.timestamp.isAfter(cutoffDate))
              .toList();

          // Filtre de type de mesure (optionnel).
          if (_selectedMeasurementType != null) {
            filteredMeasurements = filteredMeasurements
                .where((m) => m.measurementType == _selectedMeasurementType)
                .toList();
          }

          // Trier par timestamp décroissant
          filteredMeasurements
              .sort((a, b) => b.timestamp.compareTo(a.timestamp));

          // Debug : vérifier si freq/phase sont bien reçues de l'API
          if (filteredMeasurements.isNotEmpty) {
            final impWithFreq = filteredMeasurements
                .where((m) => m.measurementType == 'impedance' && (m.freqHz != null || m.phaseDeg != null))
                .length;
            debugPrint(
              '📊 Admin données: ${filteredMeasurements.length} mesures, '
              'impédance avec freq/phase: $impWithFreq',
            );
          }

          return Column(
            children: [
              // En-tête avec statistiques
              Container(
                padding: const EdgeInsets.all(16.0),
                color: Colors.grey[100],
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatCard(
                      context,
                      'Total',
                      filteredMeasurements.length.toString(),
                      Icons.assessment,
                    ),
                    _buildStatCard(
                      context,
                      'Types',
                      filteredMeasurements
                          .map((m) => m.measurementType)
                          .toSet()
                          .length
                          .toString(),
                      Icons.category,
                    ),
                  ],
                ),
              ),

              // Tableau de toutes les valeurs (tous types : ADC, température, impédance, etc.)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Toutes les valeurs',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tous les types : ADC, température, impédance (avec fréq. et phase si dispo.)',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey[600],
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                flex: 2,
                child: Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  child: filteredMeasurements.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.analytics,
                                    size: 48, color: Colors.grey[400]),
                                const SizedBox(height: 16),
                                Text(
                                  'Aucune mesure reçue pour ce patient.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.grey[700],
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Le patient doit connecter le pansement (BLE),\n'
                                  'collecter les données puis « Envoyer au médecin ».',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                FilledButton.icon(
                                  onPressed: () {
                                    ref.invalidate(
                                        patientMeasurementsProvider(widget.patient.id));
                                  },
                                  icon: const Icon(Icons.refresh, size: 20),
                                  label: const Text('Rafraîchir'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.vertical,
                            child: DataTable(
                              columnSpacing: 20,
                              headingRowColor: WidgetStateProperty.all(Colors.grey[200]),
                              columns: [
                                DataColumn(
                                  label: Text(
                                    'Type',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey[800],
                                    ),
                                  ),
                                ),
                                DataColumn(
                                  label: Text(
                                    'Valeur',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey[800],
                                    ),
                                  ),
                                ),
                                DataColumn(
                                  label: Text(
                                    'Unité',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey[800],
                                    ),
                                  ),
                                ),
                                DataColumn(
                                  label: Text(
                                    'Fréq (Hz)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey[800],
                                    ),
                                  ),
                                ),
                                DataColumn(
                                  label: Text(
                                    'Phase (°)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey[800],
                                    ),
                                  ),
                                ),
                                DataColumn(
                                  label: Text(
                                    'Date',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey[800],
                                    ),
                                  ),
                                ),
                              ],
                              rows: filteredMeasurements
                                  .asMap()
                                  .entries
                                  .map((entry) {
                                final index = entry.key;
                                final m = entry.value;
                                return DataRow(
                                  color: WidgetStateProperty.resolveWith(
                                    (_) => index.isEven
                                        ? Colors.grey[50]
                                        : Colors.white,
                                  ),
                                  cells: [
                                    DataCell(Text(
                                      m.typeLabel,
                                      style: TextStyle(
                                        color: _getTypeColor(m.measurementType),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    )),
                                    DataCell(Text(m.value.toStringAsFixed(2))),
                                    DataCell(Text(m.unit)),
                                    DataCell(Text(
                                      m.freqHz != null
                                          ? (m.freqHz!.toStringAsFixed(0))
                                          : '—',
                                    )),
                                    DataCell(Text(
                                      m.phaseDeg != null
                                          ? (m.phaseDeg!.toStringAsFixed(1))
                                          : '—',
                                    )),
                                    DataCell(Text(
                                      DateFormat('dd/MM HH:mm').format(m.timestamp),
                                      style: TextStyle(fontSize: 12),
                                    )),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                ),
              ),

              // Liste détaillée des données brutes (cartes)
              Expanded(
                flex: 1,
                child: filteredMeasurements.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.inbox,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Aucune donnée disponible',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(8.0),
                        itemCount: filteredMeasurements.length,
                        itemBuilder: (context, index) {
                          final measurement = filteredMeasurements[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 8.0,
                              vertical: 4.0,
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: _getTypeColor(
                                  measurement.measurementType,
                                ),
                                child: Icon(
                                  _getTypeIcon(measurement.measurementType),
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              title: Text(
                                measurement.typeLabel,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  if (measurement.patientName != null)
                                    Text(
                                      'Patient: ${measurement.patientName}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.blue[700],
                                      ),
                                    ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Valeur: ${measurement.value.toStringAsFixed(2)} ${measurement.unit}',
                                  ),
                                  if (measurement.freqHz != null)
                                    Text(
                                      'Fréquence: ${measurement.freqHz!.toStringAsFixed(0)} Hz',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[700],
                                      ),
                                    ),
                                  if (measurement.phaseDeg != null)
                                    Text(
                                      'Phase: ${measurement.phaseDeg!.toStringAsFixed(2)} °',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[700],
                                      ),
                                    ),
                                  Text(
                                    'Device: ${measurement.deviceId.length > 8 ? "${measurement.deviceId.substring(0, 8)}..." : measurement.deviceId}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  Text(
                                    'Date: ${DateFormat('dd/MM/yyyy HH:mm:ss').format(measurement.timestamp)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  if (measurement.qualityScore != null)
                                    Text(
                                      'Qualité: ${measurement.qualityScore}%',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    measurement.typeLabel,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: _getTypeColor(
                                          measurement.measurementType),
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      Icons.delete_outline,
                                      color: Colors.red[700],
                                      size: 22,
                                    ),
                                    onPressed: () =>
                                        _deleteMeasurement(context, measurement),
                                    tooltip: 'Supprimer cette donnée',
                                  ),
                                ],
                              ),
                            ),
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
              Text(
                'Erreur de chargement',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                error.toString(),
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }

  Widget _buildStatCard(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    return Column(
      children: [
        Icon(icon, color: Theme.of(context).primaryColor),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).primaryColor,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'adc':
        return Colors.grey;
      case 'temperature':
        return Colors.red;
      case 'impedance':
        return Colors.purple;
      default:
        return Colors.orange;
    }
  }

  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'adc':
        return Icons.memory;
      case 'temperature':
        return Icons.thermostat;
      case 'impedance':
        return Icons.electrical_services;
      default:
        return Icons.assessment;
    }
  }

  Future<void> _deleteMeasurement(
      BuildContext context, Measurement measurement) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer cette donnée'),
        content: Text(
          'Supprimer la mesure "${measurement.typeLabel}" '
          '(${measurement.value.toStringAsFixed(2)} ${measurement.unit}) '
          'du ${DateFormat('dd/MM/yyyy HH:mm').format(measurement.timestamp)} ?',
        ),
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
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final apiService = ref.read(apiServiceProvider);
      await apiService.deleteMeasurement(measurement.id);
      ref.invalidate(patientMeasurementsProvider(widget.patient.id));
      await ref.read(patientMeasurementsProvider(widget.patient.id).future);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Donnée supprimée'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
