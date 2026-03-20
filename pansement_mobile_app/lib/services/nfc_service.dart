import 'package:flutter/foundation.dart';
import 'package:nfc_manager/nfc_manager.dart';

/// Service NFC minimal : détecte un tag (sans parser le payload).
/// Utilisé comme déclencheur du scan BLE quand l'utilisateur touche le pansement.
class NfcService {
  /// Debug : vérifie que la lecture NFC marche vraiment (sans BLE).
  /// À appeler depuis un bouton de test.
  static Future<void> debugNfc() async {
    try {
      final available = await NfcManager.instance.isAvailable();
      debugPrint('📶 NFC isAvailable=$available');
      if (!available) {
        debugPrint('❌ NFC pas supporté / désactivé');
        return;
      }
      debugPrint('📶 NFC startSession - approchez un tag...');
      await NfcManager.instance.startSession(
        pollingOptions: {
          NfcPollingOption.iso14443,
          NfcPollingOption.iso15693,
          NfcPollingOption.iso18092,
        },
        onDiscovered: (tag) async {
          debugPrint('✅ TAG NFC détecté: $tag');
          await NfcManager.instance.stopSession();
        },
      );
    } catch (e, st) {
      debugPrint('❌ Erreur NFC: $e');
      debugPrint('$st');
      try {
        await NfcManager.instance.stopSession();
      } catch (_) {}
    }
  }

  /// Vérifie si le NFC est disponible sur l'appareil.
  Future<bool> isAvailable() async {
    try {
      return await NfcManager.instance.isAvailable();
    } catch (_) {
      return false;
    }
  }

  /// Attend qu'un tag NFC soit détecté. Retourne true si détecté, false si annulé/erreur.
  /// Ne parse pas le payload (application/vnd.bluetooth.le.oob ou autre).
  /// V1 : onDiscovered fait stopSession() puis appelle [onTagDetected] pour lancer le scan BLE.
  /// L'appairage système peut afficher une erreur — on l'ignore, le GATT BLE reste indépendant.
  Future<bool> waitForAnyTag({void Function()? onTagDetected}) async {
    bool found = false;

    try {
      final available = await NfcManager.instance.isAvailable();
      debugPrint('📶 NFC available=$available');
      if (!available) return false;

      debugPrint('📶 NFC startSession - approchez le pansement...');
      await NfcManager.instance.startSession(
        pollingOptions: {
          NfcPollingOption.iso14443,
          NfcPollingOption.iso15693,
          NfcPollingOption.iso18092,
        },
        onDiscovered: (tag) async {
          debugPrint('✅ NFC tag détecté: $tag');
          found = true;
          await NfcManager.instance.stopSession();
          // V1 : démarrage immédiat du scan BLE (sans attendre l'appairage système)
          onTagDetected?.call();
        },
      );
    } catch (e, st) {
      debugPrint('❌ NFC erreur: $e');
      debugPrint('$st');
      return false;
    }

    return found;
  }
}
