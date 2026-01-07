import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../providers/ble_provider.dart';
import '../providers/auth_provider.dart';

class DeviceConnectionScreen extends ConsumerStatefulWidget {
  final BluetoothDevice device;

  const DeviceConnectionScreen({
    super.key,
    required this.device,
  });

  @override
  ConsumerState<DeviceConnectionScreen> createState() =>
      _DeviceConnectionScreenState();
}

class _DeviceConnectionScreenState
    extends ConsumerState<DeviceConnectionScreen> {
  void _showSnack(String message, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    // Connecter automatiquement au device
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(deviceConnectionProvider(widget.device).notifier).connect();
    });
  }

  Future<void> _readMeasurements() async {
    await ref
        .read(deviceConnectionProvider(widget.device).notifier)
        .readMeasurements();
  }

  Future<void> _sendToServer() async {
    final connectionState = ref.read(deviceConnectionProvider(widget.device));
    final measurements = connectionState.measurements;

    if (measurements == null) return;

    try {
      final apiService = ref.read(apiServiceProvider);
      final currentUser = ref.read(authProvider).user;

      if (currentUser == null) {
        throw Exception('Utilisateur non connecté');
      }

      // TODO: Récupérer le vrai device_id depuis le serveur
      // Pour l'instant, on utilise l'ID Bluetooth
      final deviceId = widget.device.remoteId.toString();

      // Envoyer température
      if (measurements.containsKey('temperature')) {
        await apiService.createMeasurement(
          deviceId: deviceId,
          measurementType: 'temperature',
          value: (measurements['temperature'] as num).toDouble(),
          unit: '°C',
          qualityScore: 95,
        );
        if (!mounted) return;
      }

      // Envoyer humidité
      if (measurements.containsKey('humidity')) {
        await apiService.createMeasurement(
          deviceId: deviceId,
          measurementType: 'humidity',
          value: (measurements['humidity'] as num).toDouble(),
          unit: '%',
          qualityScore: 95,
        );
        if (!mounted) return;
      }

      // Envoyer pH
      if (measurements.containsKey('ph')) {
        await apiService.createMeasurement(
          deviceId: deviceId,
          measurementType: 'ph',
          value: (measurements['ph'] as num).toDouble(),
          unit: '',
          qualityScore: 95,
        );
        if (!mounted) return;
      }

      _showSnack('✅ Mesures envoyées au serveur', color: Colors.green);
    } catch (e) {
      _showSnack('❌ Erreur: ${e.toString()}', color: Colors.red);
    }
  }

  @override
  void dispose() {
    // Se déconnecter en quittant
    ref.read(deviceConnectionProvider(widget.device).notifier).disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connectionState = ref.watch(deviceConnectionProvider(widget.device));
    final deviceName = widget.device.platformName.isNotEmpty
        ? widget.device.platformName
        : 'Device inconnu';

    return Scaffold(
      appBar: AppBar(
        title: Text(deviceName),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Statut connexion
            Card(
              color: connectionState.isConnected
                  ? Colors.green[50]
                  : Colors.orange[50],
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Icon(
                      connectionState.isConnected
                          ? Icons.check_circle
                          : Icons.sync,
                      color: connectionState.isConnected
                          ? Colors.green
                          : Colors.orange,
                      size: 32,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            connectionState.isConnecting
                                ? 'Connexion en cours...'
                                : connectionState.isConnected
                                    ? 'Connecté'
                                    : 'Déconnecté',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'ID: ${widget.device.remoteId}',
                            style: TextStyle(color: Colors.grey[700]),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Erreur
            if (connectionState.error != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red[700]),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        connectionState.error!,
                        style: TextStyle(color: Colors.red[900]),
                      ),
                    ),
                  ],
                ),
              ),

            // Mesures
            if (connectionState.measurements != null) ...[
              Text(
                'Mesures',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              _buildMeasurementCard(
                'Valeur ADC',
                '${connectionState.measurements!['adc_raw']?.toStringAsFixed(0) ?? '--'}',
                '',
                Icons.sensors,
                Colors.blue,
              ),
              const SizedBox(height: 12),
              _buildMeasurementCard(
                'Température',
                '${connectionState.measurements!['temperature']?.toStringAsFixed(1) ?? '--'}',
                '°C',
                Icons.thermostat,
                Colors.red,
              ),
              const SizedBox(height: 12),
              _buildMeasurementCard(
                'Humidité',
                '${connectionState.measurements!['humidity']?.toStringAsFixed(1) ?? '--'}',
                '%',
                Icons.water_drop,
                Colors.blue,
              ),
              const SizedBox(height: 12),
              _buildMeasurementCard(
                'pH',
                '${connectionState.measurements!['ph']?.toStringAsFixed(2) ?? '--'}',
                '',
                Icons.science,
                Colors.green,
              ),
              const SizedBox(height: 12),
              _buildMeasurementCard(
                'Statut',
                connectionState.measurements!['status']?.toString() ?? '--',
                '',
                Icons.info,
                Colors.orange,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _sendToServer,
                icon: const Icon(Icons.cloud_upload),
                label: const Text('Envoyer au serveur'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Boutons d'action
            if (connectionState.isConnected &&
                connectionState.measurements == null)
              ElevatedButton.icon(
                onPressed: connectionState.isReading ? null : _readMeasurements,
                icon: connectionState.isReading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sensors),
                label: Text(connectionState.isReading
                    ? 'Lecture...'
                    : 'Lire les mesures'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
              ),

            if (connectionState.measurements != null)
              OutlinedButton.icon(
                onPressed: _readMeasurements,
                icon: const Icon(Icons.refresh),
                label: const Text('Rafraîchir'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMeasurementCard(
    String label,
    String value,
    String unit,
    IconData icon,
    Color color,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    textBaseline: TextBaseline.alphabetic,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    children: [
                      Text(
                        value,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        unit,
                        style: TextStyle(
                          fontSize: 18,
                          color: color.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
