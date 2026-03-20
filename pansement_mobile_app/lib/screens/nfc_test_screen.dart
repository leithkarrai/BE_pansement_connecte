import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';

/// Écran de test NFC isolé — vérifier que la lecture marche sans BLE.
/// Temporairement défini comme home dans main.dart pour debug.
class NfcTestScreen extends StatefulWidget {
  const NfcTestScreen({super.key});

  @override
  State<NfcTestScreen> createState() => _NfcTestScreenState();
}

class _NfcTestScreenState extends State<NfcTestScreen> {
  String _status = 'Appuie sur le bouton puis approche le pansement.';

  Future<void> _startTest() async {
    try {
      // nfc_manager 4.0.x : isAvailable() retourne bool
      final available = await NfcManager.instance.isAvailable();
      if (!mounted) return;
      setState(() => _status =
          'Disponibilité NFC: ${available ? "enabled" : "disabled"}');

      if (!available) return;

      // Session NFC minimale pour vérifier la détection tag sans dépendance BLE.
      await NfcManager.instance.startSession(
        pollingOptions: {
          NfcPollingOption.iso14443,
          NfcPollingOption.iso15693,
          NfcPollingOption.iso18092,
        },
        onDiscovered: (tag) async {
          if (mounted) {
            setState(() => _status = 'Tag détecté: ${tag.toString()}');
          }
          await NfcManager.instance.stopSession();
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() => _status = 'Erreur NFC: $e');
      }
      try {
        await NfcManager.instance.stopSession();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    // Ecran de diagnostic NFC dédié aux tests terrain.
    return Scaffold(
      appBar: AppBar(title: const Text('Test NFC')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _status,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _startTest,
                child: const Text('Démarrer test NFC'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
