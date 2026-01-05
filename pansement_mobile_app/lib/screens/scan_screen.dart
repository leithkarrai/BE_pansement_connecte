import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/ble_provider.dart';
import 'device_connection_screen.dart';

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  @override
  void initState() {
    super.initState();
    // Démarrer le scan automatiquement
    Future.delayed(Duration.zero, () {
      ref.read(bleScanProvider.notifier).startScan();
    });
  }

  @override
  void dispose() {
    // Arrêter le scan quand on quitte l'écran
    ref.read(bleScanProvider.notifier).stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scanState = ref.watch(bleScanProvider);

    return Column(
      children: [
        // Header avec titre et bouton scan/stop
        Container(
          padding: const EdgeInsets.all(16),
          color: Theme.of(context).primaryColor,
          child: Row(
            children: [
              const Icon(Icons.bluetooth, color: Colors.white),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Scanner Pansements',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (scanState.isScanning)
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                ),
              IconButton(
                icon: Icon(
                  scanState.isScanning ? Icons.stop : Icons.refresh,
                  color: Colors.white,
                ),
                onPressed: scanState.isScanning
                    ? () => ref.read(bleScanProvider.notifier).stopScan()
                    : () => ref.read(bleScanProvider.notifier).startScan(),
                tooltip: scanState.isScanning ? 'Arrêter' : 'Scanner',
              ),
            ],
          ),
        ),
        // Info card
        Container(
          width: double.infinity,
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue[200]!),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue[700]),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Assurez-vous que le Bluetooth est activé et que le pansement est à proximité',
                  style: TextStyle(color: Colors.blue[900]),
                ),
              ),
            ],
          ),
        ),

        // Erreur
        if (scanState.error != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 16),
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
                    scanState.error!,
                    style: TextStyle(color: Colors.red[900]),
                  ),
                ),
              ],
            ),
          ),

        // Liste des devices
        Expanded(
          child: scanState.devices.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.bluetooth_searching,
                        size: 80,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        scanState.isScanning
                            ? 'Recherche en cours...'
                            : 'Aucun pansement détecté',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey[600],
                        ),
                      ),
                      if (!scanState.isScanning) ...[
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () {
                            ref.read(bleScanProvider.notifier).startScan();
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('Réessayer'),
                        ),
                      ],
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () async {
                    await ref.read(bleScanProvider.notifier).stopScan();
                    await ref.read(bleScanProvider.notifier).startScan();
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.only(
                      left: 16,
                      right: 16,
                      bottom: 80, // Espace pour la Bottom Navigation Bar
                    ),
                    itemCount: scanState.devices.length,
                    itemBuilder: (context, index) {
                      final result = scanState.devices[index];
                      final device = result.device;
                      final rssi = result.rssi;

                      // Filtrer seulement les pansements (nom commence par PANS)
                      final deviceName = device.platformName.isNotEmpty
                          ? device.platformName
                          : 'Device inconnu';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _getSignalColor(rssi),
                            child: const Icon(
                              Icons.bluetooth,
                              color: Colors.white,
                            ),
                          ),
                          title: Text(
                            deviceName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('ID: ${device.remoteId}'),
                              Text(
                                'Signal: $rssi dBm (${_getSignalStrength(rssi)})',
                                style: TextStyle(
                                  color: _getSignalColor(rssi),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            // Arrêter le scan
                            await ref.read(bleScanProvider.notifier).stopScan();

                            // Naviguer vers l'écran de connexion
                            if (context.mounted) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => DeviceConnectionScreen(
                                    device: device,
                                  ),
                                ),
                              ).then((_) {
                                // Redémarrer le scan au retour
                                ref.read(bleScanProvider.notifier).startScan();
                              });
                            }
                          },
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Color _getSignalColor(int rssi) {
    if (rssi >= -60) return Colors.green;
    if (rssi >= -70) return Colors.orange;
    return Colors.red;
  }

  String _getSignalStrength(int rssi) {
    if (rssi >= -60) return 'Excellent';
    if (rssi >= -70) return 'Bon';
    if (rssi >= -80) return 'Faible';
    return 'Très faible';
  }
}
