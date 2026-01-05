import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../providers/dashboard_provider.dart';
import '../providers/measurements_provider.dart';
import '../models/user.dart';
import '../models/device.dart';
import '../models/measurement.dart';

class PatientDetailScreen extends ConsumerWidget {
  final String patientId;

  const PatientDetailScreen({
    super.key,
    required this.patientId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patientAsync = ref.watch(patientDetailProvider(patientId));
    final devicesAsync = ref.watch(patientDevicesProvider(patientId));
    final measurementsAsync = ref.watch(patientMeasurementsProvider(patientId));
    final statsAsync = ref.watch(patientStatsProvider({
      'patientId': patientId,
      'days': 7,
    }));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Détails Patient'),
      ),
      body: patientAsync.when(
        data: (patient) => SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Profil du patient
              _buildPatientProfile(context, patient),
              const SizedBox(height: 24),

              // Devices assignés
              devicesAsync.when(
                data: (devices) => _buildDevicesSection(context, devices),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) =>
                    _buildErrorCard('Erreur devices: $error'),
              ),
              const SizedBox(height: 24),

              // Statistiques récentes
              statsAsync.when(
                data: (stats) => _buildStatsSection(context, stats),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) => const SizedBox.shrink(),
              ),
              const SizedBox(height: 24),

              // Graphiques des mesures
              _buildChartsSection(context, ref),
              const SizedBox(height: 24),

              // Historique des mesures
              measurementsAsync.when(
                data: (measurements) =>
                    _buildMeasurementsHistory(context, measurements),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) =>
                    _buildErrorCard('Erreur mesures: $error'),
              ),
            ],
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text('Erreur: $error'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Retour'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPatientProfile(BuildContext context, User patient) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: Theme.of(context).primaryColor,
              child: Text(
                patient.firstName[0].toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    patient.fullName,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.email, size: 16, color: Colors.grey),
                      const SizedBox(width: 8),
                      Text(patient.email),
                    ],
                  ),
                  if (patient.phone != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.phone, size: 16, color: Colors.grey),
                        const SizedBox(width: 8),
                        Text(patient.phone!),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: patient.isActive
                          ? Colors.green[100]
                          : Colors.grey[300],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      patient.isActive ? 'Actif' : 'Inactif',
                      style: TextStyle(
                        color: patient.isActive
                            ? Colors.green[800]
                            : Colors.grey[700],
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceSection(BuildContext context, Device? device) {
    if (device == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Row(
            children: [
              const Icon(Icons.device_unknown, size: 48, color: Colors.grey),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Aucun device assigné',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Aucun pansement connecté n\'est actuellement assigné à ce patient.',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.medical_services,
                    size: 32, color: Colors.blue),
                const SizedBox(width: 12),
                Text(
                  'Device Assigné',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const Divider(height: 32),
            _buildDeviceInfoRow('Numéro de série', device.serialNumber),
            _buildDeviceInfoRow('Modèle', device.model),
            if (device.firmwareVersion != null)
              _buildDeviceInfoRow('Version firmware', device.firmwareVersion!),
            _buildDeviceInfoRow(
              'Statut',
              device.status,
              valueColor:
                  device.status == 'active' ? Colors.green : Colors.orange,
            ),
            if (device.batteryLevel != null)
              _buildDeviceInfoRow('Batterie', '${device.batteryLevel}%'),
          ],
        ),
      ),
    );
  }

  Widget _buildDevicesSection(BuildContext context, List<Device> devices) {
    if (devices.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Row(
            children: [
              const Icon(Icons.device_unknown, size: 48, color: Colors.grey),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Aucun device assigné',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Aucun pansement connecté n\'est actuellement assigné à ce patient.',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.medical_services, size: 32, color: Colors.blue),
            const SizedBox(width: 12),
            Text(
              devices.length == 1
                  ? 'Device Assigné'
                  : 'Devices Assignés (${devices.length})',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...devices.map((device) {
          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          device.serialNumber,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: device.status == 'active'
                              ? Colors.green[100]
                              : Colors.orange[100],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          device.status == 'active' ? 'Actif' : 'Inactif',
                          style: TextStyle(
                            color: device.status == 'active'
                                ? Colors.green[800]
                                : Colors.orange[800],
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  _buildDeviceInfoRow('Modèle', device.model),
                  if (device.firmwareVersion != null)
                    _buildDeviceInfoRow(
                        'Version firmware', device.firmwareVersion!),
                  if (device.batteryLevel != null)
                    _buildDeviceInfoRow('Batterie', '${device.batteryLevel}%'),
                  if (device.assignedAt != null)
                    _buildDeviceInfoRow(
                      'Assigné le',
                      '${device.assignedAt!.day}/${device.assignedAt!.month}/${device.assignedAt!.year}',
                    ),
                ],
              ),
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildDeviceInfoRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsSection(BuildContext context, Map<String, dynamic> stats) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Statistiques (7 derniers jours)',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    'Mesures totales',
                    '${stats['total_measurements'] ?? 0}',
                    Icons.analytics,
                    Colors.blue,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildStatItem(
                    'Temp. moyenne',
                    '${stats['avg_temperature']?.toStringAsFixed(1) ?? '0.0'}°C',
                    Icons.thermostat,
                    Colors.red,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildStatItem(
                    'Humidité moyenne',
                    '${stats['avg_humidity']?.toStringAsFixed(1) ?? '0.0'}%',
                    Icons.water_drop,
                    Colors.blue,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildStatItem(
                    'pH moyen',
                    '${stats['avg_ph']?.toStringAsFixed(2) ?? '0.00'}',
                    Icons.science,
                    Colors.purple,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(
      String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildChartsSection(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Graphiques des Mesures',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 16),
        // Graphique température
        _buildChartCard(
          context,
          ref,
          'Température (°C)',
          temperatureMeasurementsProvider,
          Colors.red,
          '°C',
        ),
        const SizedBox(height: 16),
        // Graphique humidité
        _buildChartCard(
          context,
          ref,
          'Humidité (%)',
          humidityMeasurementsProvider,
          Colors.blue,
          '%',
        ),
        const SizedBox(height: 16),
        // Graphique pH
        _buildChartCard(
          context,
          ref,
          'pH',
          phMeasurementsProvider,
          Colors.purple,
          '',
        ),
      ],
    );
  }

  Widget _buildChartCard(
    BuildContext context,
    WidgetRef ref,
    String title,
    FutureProviderFamily<List<Measurement>, String> provider,
    Color color,
    String unit,
  ) {
    final measurementsAsync = ref.watch(provider(patientId));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: measurementsAsync.when(
                data: (measurements) {
                  if (measurements.isEmpty) {
                    return Center(
                      child: Text(
                        'Aucune donnée disponible',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    );
                  }
                  return _buildLineChart(measurements, color, unit);
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) => Center(
                  child: Text(
                    'Erreur: $error',
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLineChart(
      List<Measurement> measurements, Color color, String unit) {
    // Trier par timestamp
    measurements.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // Prendre les 20 dernières mesures pour le graphique
    final displayMeasurements = measurements.length > 20
        ? measurements.sublist(measurements.length - 20)
        : measurements;

    final spots = displayMeasurements
        .asMap()
        .entries
        .map((entry) => FlSpot(
              entry.key.toDouble(),
              entry.value.value,
            ))
        .toList();

    if (spots.isEmpty) {
      return Center(
        child: Text(
          'Aucune donnée à afficher',
          style: TextStyle(color: Colors.grey[600]),
        ),
      );
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(show: true),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (value, meta) {
                if (value.toInt() >= 0 &&
                    value.toInt() < displayMeasurements.length) {
                  final measurement = displayMeasurements[value.toInt()];
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      DateFormat('HH:mm').format(measurement.timestamp),
                      style: const TextStyle(fontSize: 10),
                    ),
                  );
                }
                return const Text('');
              },
            ),
          ),
          rightTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        borderData: FlBorderData(show: true),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: color,
            barWidth: 3,
            dotData: FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: color.withOpacity(0.2),
            ),
          ),
        ],
        minY: spots.map((s) => s.y).reduce((a, b) => a < b ? a : b) - 1,
        maxY: spots.map((s) => s.y).reduce((a, b) => a > b ? a : b) + 1,
      ),
    );
  }

  Widget _buildMeasurementsHistory(
      BuildContext context, List<Measurement> measurements) {
    if (measurements.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Center(
            child: Column(
              children: [
                Icon(Icons.analytics_outlined,
                    size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'Aucune mesure disponible',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Trier par timestamp (plus récent en premier)
    measurements.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Historique des Mesures',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 16),
        Card(
          child: ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: measurements.length > 50 ? 50 : measurements.length,
            itemBuilder: (context, index) {
              final measurement = measurements[index];
              return _buildMeasurementTile(measurement);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMeasurementTile(Measurement measurement) {
    Color getTypeColor() {
      switch (measurement.measurementType) {
        case 'temperature':
          return Colors.red;
        case 'humidity':
          return Colors.blue;
        case 'ph':
          return Colors.purple;
        default:
          return Colors.grey;
      }
    }

    IconData getTypeIcon() {
      switch (measurement.measurementType) {
        case 'temperature':
          return Icons.thermostat;
        case 'humidity':
          return Icons.water_drop;
        case 'ph':
          return Icons.science;
        default:
          return Icons.analytics;
      }
    }

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: getTypeColor().withOpacity(0.2),
        child: Icon(getTypeIcon(), color: getTypeColor()),
      ),
      title: Text(
        measurement.typeLabel,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(
        DateFormat('dd/MM/yyyy HH:mm').format(measurement.timestamp),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '${measurement.value.toStringAsFixed(2)} ${measurement.unit}',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: getTypeColor(),
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
    );
  }

  Widget _buildErrorCard(String message) {
    return Card(
      color: Colors.red[50],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
