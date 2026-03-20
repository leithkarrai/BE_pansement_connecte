import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/pending_nfc_payload_provider.dart';
import '../screens/nfc_pairing_screen.dart';

/// Écoute les deep links epatch://pair (NFC) et pousse l'écran de pairing.
class DeepLinkHandler {
  DeepLinkHandler(this.ref, this.navigatorKey);

  final WidgetRef ref;
  final GlobalKey<NavigatorState> navigatorKey;

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;

  Future<void> init() async {
    // Cold start (app lancée par tap NFC) : l'intent peut arriver après que le navigator soit prêt
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 100));
      final initial = await _appLinks.getInitialLink();
      if (initial != null) {
        debugPrint('🔗 [DeepLink] Lien initial reçu: $initial');
        _handle(initial);
      }
    });

    // App déjà ouverte + nouveau tap NFC
    _sub = _appLinks.uriLinkStream.listen((uri) {
      debugPrint('🔗 [DeepLink] Nouveau lien reçu: $uri');
      _handle(uri);
    });
  }

  void dispose() => _sub?.cancel();

  void _handle(Uri uri) {
    final payload = NfcPayload.fromUri(uri);
    if (payload == null) {
      debugPrint('🔗 [DeepLink] URI ignorée (pas epatch://pair?deviceId=...): $uri');
      return;
    }

    debugPrint('🔗 [DeepLink] Payload OK → deviceId=${payload.deviceId}');
    ref.read(pendingNfcPayloadProvider.notifier).state = payload;

    void doPush() {
      final state = navigatorKey.currentState;
      if (state != null) {
        state.push(
          MaterialPageRoute(builder: (_) => const NfcPairingScreen()),
        );
      }
    }

    if (navigatorKey.currentState != null) {
      doPush();
    } else {
      // Cold start : le navigator n'est pas encore prêt, repousser après le premier frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (navigatorKey.currentState != null) {
          doPush();
        } else {
          // Au cas où un frame ne suffit pas (ex. HomeScreen async)
          Future.delayed(const Duration(milliseconds: 300), () {
            if (navigatorKey.currentState != null) doPush();
          });
        }
      });
    }
  }
}
