import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../providers/ble_provider.dart';
import '../providers/auth_provider.dart';
import 'measurements_screen.dart';

class DeviceDetailScreen extends ConsumerStatefulWidget {
  final BluetoothDevice device;

  const DeviceDetailScreen({
    super.key,
    required this.device,
  });

  @override
  ConsumerState<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends ConsumerState<DeviceDetailScreen> {
  BluetoothConnectionState _connectionState =
      BluetoothConnectionState.disconnected;
  Map<String, dynamic>? _measurements;
  bool _isLoading = false;
  String? _error;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;

  @override
  void initState() {
    super.initState();
    _listenToConnection();
  }

  void _listenToConnection() async {
    // Obtenir l'état initial
    _connectionState = await widget.device.connectionState.first;

    // Écouter les changements
    _connectionSubscription = widget.device.connectionState.listen((state) {
      if (mounted) {
        setState(() {
          _connectionState = state;
        });
      }
    });
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final bleService = ref.read(bleServiceProvider);
      await bleService.connectToDevice(widget.device);

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connecté au pansement'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _disconnect() async {
    try {
      final bleService = ref.read(bleServiceProvider);
      await bleService.disconnectDevice(widget.device);

      if (mounted) {
        setState(() {
          _measurements = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Déconnecté'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _readMeasurements() async {
    if (_connectionState != BluetoothConnectionState.connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez d\'abord vous connecter'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final bleService = ref.read(bleServiceProvider);
      final measurements = await bleService.readMeasurements(widget.device);

      if (mounted) {
        setState(() {
          _measurements = measurements;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _startStreaming() {
    if (_connectionState != BluetoothConnectionState.connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez d\'abord vous connecter'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Les notifications sont gérées automatiquement via les callbacks
    // du BleService après la connexion
    final bleService = ref.read(bleServiceProvider);
    bleService.onDataReceived = (measurements) {
      if (mounted) {
        setState(() {
          _measurements = measurements;
        });
      }
    };
  }

  Future<void> _sendToBackend() async {
    if (_measurements == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aucune mesure à envoyer'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final user = ref.read(authProvider).user;

      if (user == null) {
        throw Exception('Utilisateur non connecté');
      }

      // TODO: Implémenter l'envoi des mesures au backend
      // Pour l'instant, on simule l'envoi
      // final apiService = ref.read(apiServiceProvider);
      // await apiService.createMeasurement(...);

      // Simulation d'envoi réussi
      await Future.delayed(const Duration(seconds: 1));

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Mesures envoyées au serveur'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = _connectionState == BluetoothConnectionState.connected;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.device.platformName.isNotEmpty
            ? widget.device.platformName
            : 'Pansement'),
        actions: [
          if (isConnected)
            IconButton(
              icon: const Icon(Icons.analytics),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => MeasurementsScreen(
                      device: widget.device,
                    ),
                  ),
                );
              },
              tooltip: 'Voir les mesures',
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // État de connexion
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Icon(
                      isConnected
                          ? Icons.bluetooth_connected
                          : Icons.bluetooth_disabled,
                      size: 48,
                      color: isConnected ? Colors.green : Colors.grey,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isConnected ? 'Connecté' : 'Déconnecté',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: isConnected ? Colors.green : Colors.grey,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'ID: ${widget.device.remoteId}',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Boutons d'action
            if (!isConnected)
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _connect,
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.bluetooth),
                label: const Text('Se connecter'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _disconnect,
                      icon: const Icon(Icons.bluetooth_disabled),
                      label: const Text('Déconnecter'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _readMeasurements,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Lire'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: _startStreaming,
                icon: const Icon(Icons.stream),
                label: const Text('Démarrer le streaming'),
              ),
            ],

            // Mesures
            if (_measurements != null) ...[
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mesures actuelles',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const Divider(),
                      _buildMeasurementRow(
                        'Température',
                        '${_measurements!['temperature']?.toStringAsFixed(2) ?? 'N/A'} °C',
                        Icons.thermostat,
                        Colors.red,
                      ),
                      const SizedBox(height: 12),
                      _buildMeasurementRow(
                        'Humidité',
                        '${_measurements!['humidity']?.toStringAsFixed(2) ?? 'N/A'} %',
                        Icons.water_drop,
                        Colors.blue,
                      ),
                      const SizedBox(height: 12),
                      _buildMeasurementRow(
                        'pH',
                        '${_measurements!['ph']?.toStringAsFixed(2) ?? 'N/A'}',
                        Icons.science,
                        Colors.purple,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _isLoading ? null : _sendToBackend,
                        icon: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.cloud_upload),
                        label: const Text('Envoyer au serveur'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            // Erreur
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMeasurementRow(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}
