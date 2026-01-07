import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../providers/ble_provider.dart';
import '../providers/auth_provider.dart';
import 'package:fl_chart/fl_chart.dart';

class MeasurementsScreen extends ConsumerStatefulWidget {
  final BluetoothDevice device;

  const MeasurementsScreen({
    super.key,
    required this.device,
  });

  @override
  ConsumerState<MeasurementsScreen> createState() => _MeasurementsScreenState();
}

class _MeasurementsScreenState extends ConsumerState<MeasurementsScreen> {
  final List<Map<String, dynamic>> _measurementsHistory = [];
  bool _isStreaming = false;

  @override
  void initState() {
    super.initState();
    _startStreaming();
  }

  void _startStreaming() {
    if (widget.device.connectionState != BluetoothConnectionState.connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez d\'abord vous connecter'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isStreaming = true;
    });

    // Les notifications sont gérées automatiquement via les callbacks
    // du BleService après la connexion
    final bleService = ref.read(bleServiceProvider);
    bleService.onDataReceived = (measurements) {
      if (mounted) {
        setState(() {
          _measurementsHistory.add(measurements);
          // Garder seulement les 50 dernières mesures
          if (_measurementsHistory.length > 50) {
            _measurementsHistory.removeAt(0);
          }
        });
      }
    };
  }

  void _stopStreaming() {
    setState(() {
      _isStreaming = false;
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final role = user?.role ?? '';
    final isPatient = role == 'patient';
    if (isPatient) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Mesures en temps réel'),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Accès réservé aux médecins et administrateurs.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final lastMeasurement =
        _measurementsHistory.isNotEmpty ? _measurementsHistory.last : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mesures en temps réel'),
        actions: [
          if (_isStreaming)
            IconButton(
              icon: const Icon(Icons.stop),
              onPressed: _stopStreaming,
              tooltip: 'Arrêter le streaming',
            )
          else
            IconButton(
              icon: const Icon(Icons.play_arrow),
              onPressed: _startStreaming,
              tooltip: 'Démarrer le streaming',
            ),
        ],
      ),
      body: _measurementsHistory.isEmpty
          ? _buildEmptyState()
          : _buildMeasurementsView(lastMeasurement!),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.sensors_off,
            size: 80,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            'Aucune mesure reçue',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.grey.shade600,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            _isStreaming
                ? 'En attente de données...'
                : 'Démarrez le streaming pour recevoir les mesures',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildMeasurementsView(Map<String, dynamic> lastMeasurement) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Indicateur de streaming
          if (_isStreaming)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('Streaming actif'),
                  const Spacer(),
                  Text(
                    '${_measurementsHistory.length} mesures',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade700,
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 16),

          // Valeurs actuelles
          Row(
            children: [
              Expanded(
                child: _buildValueCard(
                  'Température',
                  '${lastMeasurement['temperature']?.toStringAsFixed(1) ?? 'N/A'}',
                  '°C',
                  Colors.red,
                  Icons.thermostat,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildValueCard(
                  'Humidité',
                  '${lastMeasurement['humidity']?.toStringAsFixed(1) ?? 'N/A'}',
                  '%',
                  Colors.blue,
                  Icons.water_drop,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: _buildValueCard(
                  'pH',
                  '${lastMeasurement['ph']?.toStringAsFixed(2) ?? 'N/A'}',
                  '',
                  Colors.purple,
                  Icons.science,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Graphique température
          if (_measurementsHistory.length > 1)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Température',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 200,
                      child: LineChart(
                        _buildTemperatureChart(),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 16),

          // Graphique humidité
          if (_measurementsHistory.length > 1)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Humidité',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 200,
                      child: LineChart(
                        _buildHumidityChart(),
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

  Widget _buildValueCard(
    String label,
    String value,
    String unit,
    Color color,
    IconData icon,
  ) {
    return Card(
      color: color.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                if (unit.isNotEmpty)
                  Text(
                    unit,
                    style: TextStyle(
                      fontSize: 14,
                      color: color,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  LineChartData _buildTemperatureChart() {
    final spots = _measurementsHistory
        .asMap()
        .entries
        .map((entry) => FlSpot(
              entry.key.toDouble(),
              entry.value['temperature'] ?? 0.0,
            ))
        .toList();

    return LineChartData(
      gridData: FlGridData(show: true),
      titlesData: FlTitlesData(show: false),
      borderData: FlBorderData(show: true),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: Colors.red,
          barWidth: 3,
          dotData: FlDotData(show: false),
          belowBarData: BarAreaData(show: false),
        ),
      ],
      minY: spots.isNotEmpty
          ? spots.map((s) => s.y).reduce((a, b) => a < b ? a : b) - 2
          : 0,
      maxY: spots.isNotEmpty
          ? spots.map((s) => s.y).reduce((a, b) => a > b ? a : b) + 2
          : 40,
    );
  }

  LineChartData _buildHumidityChart() {
    final spots = _measurementsHistory
        .asMap()
        .entries
        .map((entry) => FlSpot(
              entry.key.toDouble(),
              entry.value['humidity'] ?? 0.0,
            ))
        .toList();

    return LineChartData(
      gridData: FlGridData(show: true),
      titlesData: FlTitlesData(show: false),
      borderData: FlBorderData(show: true),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: Colors.blue,
          barWidth: 3,
          dotData: FlDotData(show: false),
          belowBarData: BarAreaData(show: false),
        ),
      ],
      minY: 0,
      maxY: 100,
    );
  }
}
