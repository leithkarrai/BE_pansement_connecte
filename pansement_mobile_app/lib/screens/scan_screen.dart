import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:nfc_manager/nfc_manager.dart';
import '../providers/ble_provider.dart';
import '../services/navigation_service.dart';
import 'device_connection_screen.dart';

/// UUID du service Nordic UART (nRF51/nRF52, cartes de test).
const String _nusServiceUuid = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';

/// Délai entre stopScan et startScan après détection NFC (réduit pour réactivité, tout en gardant le stack BLE stable).
const Duration _kDelayNfcToBleScan = Duration(milliseconds: 300);

/// Indique si un device scanné est ciblé : pansement ou carte Nordic (nRF) pour les tests.
bool _isTargetDevice(ScanResult result) {
  final name = result.device.platformName.toLowerCase();
  if (name.contains('pansement') || name.contains('pensement') || name.contains('pans')) return true;
  if (name.contains('nordic') || name.contains('nrf') || name.contains('nrf52') || name.contains('nrf51')) return true;
  return result.advertisementData.serviceUuids.any((uuid) {
    final u = uuid.toString().toLowerCase();
    return u == '75c276c3-8f97-20bc-a143-b354244886d4' ||
        u == '76c276c3-8f97-20bc-a143-b354244886d4' ||
        u == _nusServiceUuid;
  });
}

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  bool _hasTriggeredAutoConnect = false;
  /// true après un scan NFC réussi : autorise la connexion (tap liste ou auto-connect).
  bool _nfcScanCompletedForSession = false;
  Timer? _autoConnectTimer;
  BleScanNotifier? _scanNotifier;

  /// Détecte le tag NFC puis arrête/relance le scan BLE. Connexion possible uniquement après ce scan.
  Future<void> _onNfcTap() async {
    // Message immédiat au clic sur le logo NFC
    NavigationService().showSnackBar(
      const SnackBar(
        content: Text('Rapprochez votre téléphone du pansement'),
        duration: Duration(seconds: 8),
        behavior: SnackBarBehavior.floating,
      ),
    );

    final available = await NfcManager.instance.isAvailable();
    if (!available) {
      NavigationService().showSnackBar(
        const SnackBar(
          content: Text('NFC non disponible. Activez le NFC dans les paramètres.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    try {
      await NfcManager.instance.startSession(
        pollingOptions: {
          NfcPollingOption.iso14443,
          NfcPollingOption.iso15693,
          NfcPollingOption.iso18092,
        },
        onDiscovered: (tag) async {
          await NfcManager.instance.stopSession();

          if (mounted) {
            setState(() {
              _nfcScanCompletedForSession = true;
              _hasTriggeredAutoConnect = false;
            });
          }

          await ref.read(bleScanProvider.notifier).stopScan();
          await Future.delayed(_kDelayNfcToBleScan);
          await ref.read(bleScanProvider.notifier).startScan();

          WidgetsBinding.instance.addPostFrameCallback((_) {
            final navCtx = NavigationService().navigatorKey.currentContext;
            if (navCtx != null) {
              ScaffoldMessenger.maybeOf(navCtx)?.showSnackBar(
                const SnackBar(
                  content: Text('Tag NFC détecté. Connexion au pansement...'),
                  duration: Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          });
        },
      );
    } catch (e) {
      try {
        await NfcManager.instance.stopSession();
      } catch (_) {}
      if (!mounted) return;
      NavigationService().showSnackBar(
        SnackBar(
          content: Text('Erreur NFC: $e'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _scanNotifier = ref.read(bleScanProvider.notifier);
    // Démarrage différé pour laisser l'UI se stabiliser avant le scan BLE.
    Future.delayed(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      _scanNotifier?.startScan();
    });
  }

  @override
  void dispose() {
    _autoConnectTimer?.cancel();
    // Ne pas utiliser ref dans dispose() pour éviter "Looking up a deactivated widget's ancestor"
    _scanNotifier?.stopScan();
    super.dispose();
  }

  void _tryAutoConnectToPansement(List<ScanResult> devices) {
    if (!_nfcScanCompletedForSession) return;
    if (_hasTriggeredAutoConnect) return;
    final pansements = devices.where(_isTargetDevice).toList();
    if (pansements.isEmpty) return;

    _hasTriggeredAutoConnect = true;
    _autoConnectTimer?.cancel();
    // Petit délai pour laisser le scan se remplir avant de choisir le meilleur RSSI.
    _autoConnectTimer = Timer(const Duration(milliseconds: 1500), () async {
      if (!mounted) return;
      await ref.read(bleScanProvider.notifier).stopScan();
      if (!mounted) return;
      // Laisser le stack BLE se libérer avant de lancer la connexion (évite échec sur Android)
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      // Un seul pansement : le prendre ; plusieurs : prendre celui avec le meilleur signal (RSSI le plus élevé)
      final best = pansements.length == 1
          ? pansements.first
          : pansements.reduce(
              (a, b) => a.rssi >= b.rssi ? a : b,
            );
      final device = best.device;
      // Utiliser le navigator racine (ScanScreen est dans un onglet IndexedStack)
      final navContext = NavigationService().navigatorKey.currentContext;
      if (navContext != null && mounted) {
        Navigator.of(navContext).push(
          MaterialPageRoute(
            builder: (_) => DeviceConnectionScreen(device: device),
          ),
        ).then((_) {
          _hasTriggeredAutoConnect = false;
          ref.read(bleScanProvider.notifier).startScan();
        });
      } else {
        _hasTriggeredAutoConnect = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scanState = ref.watch(bleScanProvider);
    final pansementDevices = scanState.devices.where(_isTargetDevice).toList();
    // Afficher aussi les autres appareils BLE si aucun pansement reconnu (nom ou UUID peut varier)
    final allDevices = pansementDevices.isNotEmpty
        ? pansementDevices
        : scanState.devices;

    // Connexion automatique uniquement quand un pansement est clairement détecté
    if (pansementDevices.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _tryAutoConnectToPansement(pansementDevices);
      });
    }

    // Ecran de pairing:
    // NFC -> scan BLE -> sélection/auto-connexion -> écran de connexion device.
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
                  'Connexion au pansement (BLE)',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.nfc, color: Colors.white),
                tooltip: 'Scanner via NFC',
                onPressed: _onNfcTap,
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
                  _nfcScanCompletedForSession
                      ? 'Pansement détecté par NFC. Sélectionnez-le dans la liste ou attendez la connexion automatique.'
                      : 'Scannez d\'abord le pansement avec le bouton NFC (icône en haut), puis choisissez le pansement dans la liste. Sans NFC, la connexion est bloquée.',
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

        // Liste : pansements détectés en priorité, sinon tous les appareils BLE
        Expanded(
          child: allDevices.isEmpty
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
                            : 'Aucun appareil détecté',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey[600],
                        ),
                      ),
                      if (scanState.error != null) ...[
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            scanState.error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.red[700],
                            ),
                          ),
                        ),
                      ],
                      if (!scanState.isScanning) ...[
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () {
                            ref.read(bleScanProvider.notifier).startScan();
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('Lancer le scan'),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Vérifiez que le Bluetooth et la localisation sont activés.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
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
                    itemCount: allDevices.length,
                    itemBuilder: (context, index) {
                      final result = allDevices[index];
                      final isPansement = _isTargetDevice(result);
                      final device = result.device;
                      final rssi = result.rssi;

                      final rawId = device.remoteId.toString();
                      final deviceName = device.platformName.isNotEmpty
                          ? device.platformName
                          : 'Appareil ${rawId.length > 8 ? "${rawId.substring(0, 8)}..." : rawId}';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isPansement
                                ? Colors.green
                                : _getSignalColor(rssi),
                            child: const Icon(
                              Icons.bluetooth,
                              color: Colors.white,
                            ),
                          ),
                          title: Row(
                            children: [
                              Expanded(child: Text(deviceName, style: const TextStyle(fontWeight: FontWeight.bold))),
                              if (isPansement)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.green[100],
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text('Pansement', style: TextStyle(fontSize: 11, color: Colors.green[800])),
                                ),
                            ],
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
                            if (!_nfcScanCompletedForSession) {
                              NavigationService().showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Scannez d\'abord le pansement avec le bouton NFC (icône en haut) pour autoriser la connexion.',
                                  ),
                                  duration: Duration(seconds: 4),
                                  behavior: SnackBarBehavior.floating,
                                  backgroundColor: Colors.orange,
                                ),
                              );
                              return;
                            }
                            // Arrêter le scan
                            await ref.read(bleScanProvider.notifier).stopScan();
                            if (mounted) setState(() => _nfcScanCompletedForSession = false);

                            // Naviguer vers l'écran de connexion (navigator racine : ScanScreen est dans un onglet)
                            final navContext =
                                NavigationService().navigatorKey.currentContext;
                            if (navContext != null) {
                              Navigator.of(navContext).push(
                                MaterialPageRoute(
                                  builder: (_) => DeviceConnectionScreen(
                                    device: device,
                                  ),
                                ),
                              ).then((_) {
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
