import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/nfc_service.dart';

/// Provider du service NFC.
///
/// Rôle:
/// - expose une instance unique de [NfcService] aux écrans/providers,
/// - centralise l'accès à la détection de tag pour les parcours de pairing.
final nfcServiceProvider = Provider<NfcService>((ref) {
  return NfcService();
});
