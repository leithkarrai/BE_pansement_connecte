import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/ble_provider.dart';
import '../providers/pending_nfc_payload_provider.dart';
import '../services/navigation_service.dart';
import 'device_connection_screen.dart';

/// Écran affiché quand l'app est ouverte via le deep link epatch://pair (NFC).
/// Lit le payload (deviceId, token, service), lance le scan BLE, trouve le device
/// par nom puis navigue vers DeviceConnectionScreen(device, nfcToken).
class NfcPairingScreen extends ConsumerStatefulWidget {
  const NfcPairingScreen({super.key});

  @override
  ConsumerState<NfcPairingScreen> createState() => _NfcPairingScreenState();
}

class _NfcPairingScreenState extends ConsumerState<NfcPairingScreen> {
  String? _error;
  bool _searching = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startSearch());
  }

  Future<void> _startSearch() async {
    final payload = ref.read(pendingNfcPayloadProvider);
    if (payload == null || !mounted) {
      if (mounted) _goBack();
      return;
    }

    ref.read(pendingNfcPayloadProvider.notifier).state = null;

    final deviceId = payload.deviceId.trim();
    if (deviceId.isEmpty) {
      if (mounted) setState(() {
        _error = 'deviceId manquant';
        _searching = false;
      });
      return;
    }

    // Flux deep-link NFC:
    // 1) scanner BLE, 2) retrouver le device via deviceId du payload, 3) naviguer.
    await ref.read(bleScanProvider.notifier).startScan();
    final deviceIdLower = deviceId.toLowerCase();

    for (int i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;

      final devices = ref.read(bleScanProvider).devices;
      for (final r in devices) {
        final name = (r.device.platformName).trim().toLowerCase();
        if (name == deviceIdLower || name.contains(deviceIdLower)) {
          await ref.read(bleScanProvider.notifier).stopScan();
          if (!mounted) return;

          final navContext = NavigationService().navigatorKey.currentContext;
          if (navContext != null && mounted) {
            Navigator.of(navContext).pushReplacement(
              MaterialPageRoute(
                builder: (_) => DeviceConnectionScreen(device: r.device),
              ),
            );
          }
          return;
        }
      }
    }

    await ref.read(bleScanProvider.notifier).stopScan();
    if (mounted) {
      setState(() {
        _error = 'Appareil « $deviceId » introuvable. Vérifiez qu\'il est allumé et à proximité.';
        _searching = false;
      });
    }
  }

  void _goBack() {
    final navContext = NavigationService().navigatorKey.currentContext;
    if (navContext != null && Navigator.of(navContext).canPop()) {
      Navigator.of(navContext).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Ecran transitoire de pairing lancé depuis epatch://pair.
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connexion pansement'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _searching ? null : _goBack,
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _error != null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.red[800]),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _goBack,
                      child: const Text('Retour'),
                    ),
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 24),
                    Text(
                      'Recherche du pansement en cours...',
                      style: TextStyle(color: Colors.grey[700]),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
