import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Payload lu depuis le deep link NFC (epatch://pair?deviceId=...&token=...&service=...).
class NfcPayload {
  final String deviceId;
  final String? token;
  final String? serviceUuid;

  const NfcPayload({
    required this.deviceId,
    this.token,
    this.serviceUuid,
  });

  /// Parse un Uri epatch://pair?deviceId=...&token=...&service=... (Format A — NFC Tools URL/URI)
  static NfcPayload? fromUri(Uri uri) {
    if (uri.scheme != 'epatch') return null;
    if (uri.host != 'pair') return null;

    final deviceId = uri.queryParameters['deviceId'];
    if (deviceId == null || deviceId.isEmpty) return null;

    return NfcPayload(
      deviceId: deviceId,
      token: uri.queryParameters['token'],
      serviceUuid: uri.queryParameters['service'],
    );
  }

  /// Parse un JSON NDEF texte (Format B) : {"deviceId":"PANSEMENT_001","token":"abc","service":"..."}
  static NfcPayload? fromJson(Map<String, dynamic> json) {
    final deviceId = json['deviceId']?.toString();
    if (deviceId == null || deviceId.isEmpty) return null;
    return NfcPayload(
      deviceId: deviceId,
      token: json['token']?.toString(),
      serviceUuid: json['service']?.toString(),
    );
  }
}

/// Tampon temporaire du payload NFC entre réception du deep link et écran de pairing.
/// La valeur est remise à `null` une fois consommée.
final pendingNfcPayloadProvider = StateProvider<NfcPayload?>((ref) => null);
