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
  bool _isConnecting = false;
  bool _isConnected = false;
  bool _isReading = false;
  Map<String, double>? _measurements;
  String? _error;

  @override
  void initState() {
    super.initState();
    _connectToDevice();
  }

  Future<void> _connectToDevice() async {
    setState(() {
      _isConnecting = true;
      _error = null;
    });

    try {
      final bleService = ref.read(bleServiceProvider);
      await bleService.connectToDevice(widget.device);

      setState(() {
        _isConnecting = false;
        _isConnected = true;
      });

      // Lire les mesures automatiquement après connexion
      await _readMeasurements();
    } catch (e) {
      setState(() {
        _isConnecting = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _readMeasurements() async {
    setState(() {
      _isReading = true;
      _error = null;
    });

    try {
      final bleService = ref.read(bleServiceProvider);
      final measurements = await bleService.readMeasurements(widget.device);

      setState(() {
        _measurements = measurements;
        _isReading = false;
      });
    } catch (e) {
      setState(() {
        _isReading = false;
        _error = 'Erreur lecture: ${e.toString()}';
      });
    }
  }

  Future<void> _sendToServer() async {
    if (_measurements == null) return;

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
      if (_measurements!.containsKey('temperature')) {
        await apiService.createMeasurement(
          deviceId: deviceId,
          measurementType: 'temperature',
          value: _measurements!['temperature']!,
          unit: '°C',
          qualityScore: 95,
        );
      }

      // Envoyer humidité
      if (_measurements!.containsKey('humidity')) {
        await apiService.createMeasurement(
          deviceId: deviceId,
          measurementType: 'humidity',
          value: _measurements!['humidity']!,
          unit: '%',
          qualityScore: 95,
        );
      }

      // Envoyer pH
      if (_measurements!.containsKey('ph')) {
        await apiService.createMeasurement(
          deviceId: deviceId,
          measurementType: 'ph',
          value: _measurements!['ph']!,
          unit: '',
          qualityScore: 95,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Mesures envoyées au serveur'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erreur: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    // Se déconnecter en quittant
    ref.read(bleServiceProvider).disconnectDevice(widget.device);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
              color: _isConnected ? Colors.green[50] : Colors.orange[50],
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Icon(
                      _isConnected ? Icons.check_circle : Icons.sync,
                      color: _isConnected ? Colors.green : Colors.orange,
                      size: 32,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isConnecting
                                ? 'Connexion en cours...'
                                : _isConnected
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
            if (_error != null)
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
                        _error!,
                        style: TextStyle(color: Colors.red[900]),
                      ),
                    ),
                  ],
                ),
              ),

            // Mesures
            if (_measurements != null) ...[
              Text(
                'Mesures',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              _buildMeasurementCard(
                'Température',
                '${_measurements!['temperature']?.toStringAsFixed(1) ?? '--'}',
                '°C',
                Icons.thermostat,
                Colors.red,
              ),
              const SizedBox(height: 12),
              _buildMeasurementCard(
                'Humidité',
                '${_measurements!['humidity']?.toStringAsFixed(1) ?? '--'}',
                '%',
                Icons.water_drop,
                Colors.blue,
              ),
              const SizedBox(height: 12),
              _buildMeasurementCard(
                'pH',
                '${_measurements!['ph']?.toStringAsFixed(2) ?? '--'}',
                '',
                Icons.science,
                Colors.green,
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
            if (_isConnected && _measurements == null)
              ElevatedButton.icon(
                onPressed: _isReading ? null : _readMeasurements,
                icon: _isReading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sensors),
                label: Text(_isReading ? 'Lecture...' : 'Lire les mesures'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
              ),

            if (_measurements != null)
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
