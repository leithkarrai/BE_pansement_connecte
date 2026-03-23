import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Service BLE : pansement ou carte Nordic nRF (tests).
///
/// Pansement (comme dans nRF Connect) :
/// - Service: 75c276c3-8f97-20bc-a143-b354244886d4
/// - Caractéristique données (NOTIFY, READ): 76c276c3-8f97-20bc-a143-b354244886d4
/// - Nordic UART (NUS): 6E400001-B5A3-F393-E0A9-E50E24DCCA9E (TX = notify)
class BleService {
  static const String serviceUuid = "75c276c3-8f97-20bc-a143-b354244886d4";
  /// Caractéristique du pansement (NOTIFY + READ), même UUID que dans nRF Connect.
  static const String pansementCharacteristicUuid = "76c276c3-8f97-20bc-a143-b354244886d4";
  static const String nusServiceUuid = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
  static const String nusTxCharacteristicUuid = "6e400003-b5a3-f393-e0a9-e50e24dcca9e";
  static const String? characteristicUuid = pansementCharacteristicUuid;
  static const String deviceNamePrefix = "Pansement";

  /// Délais pour stabiliser la connexion GATT (évite "ça marche une fois puis plus").
  static const Duration kStabilisationAfterConnect = Duration(milliseconds: 1000);
  /// Délai avant setNotifyValue ; augmenté pour certains firmwares lents.
  static const Duration kDelayBeforeSetNotify = Duration(milliseconds: 2500);
  static const Duration kDelayAfterDiscoverServices = Duration(milliseconds: 200);

  // État de connexion
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _dataCharacteristic;
  StreamSubscription? _notificationSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;
  bool _readNotPermitted = false;
  bool _readNotPermittedLogged = false;
  Map<String, dynamic>? _lastNotificationMeasurements;
  /// Liste des points du balayage (freq, impedance, phase) pour courbe Bode
  final List<Map<String, dynamic>> _sweepPoints = [];
  /// Buffer de réception binaire pour réassembler les paquets fragmentés
  /// et traiter plusieurs paquets reçus dans une seule notification.
  final List<int> _binaryReceiveBuffer = [];
  bool _isConnecting = false;
  /// True si setNotifyValue a échoué avec "Device is disconnected" (plus fiable que connectionState.first).
  bool _notifyFailedBecauseDisconnected = false;

  // Callbacks
  Function(Map<String, dynamic>)? onDataReceived;
  Function(String)? onError;
  Function(BluetoothConnectionState)? onConnectionStateChanged;

  /// Vérifie si le Bluetooth est disponible et activé
  Future<bool> isBluetoothAvailable() async {
    try {
      if (await FlutterBluePlus.isSupported == false) {
        debugPrint("❌ Bluetooth non supporté sur cet appareil");
        return false;
      }

      final adapterState = await FlutterBluePlus.adapterState.first;
      if (adapterState != BluetoothAdapterState.on) {
        debugPrint("⚠️ Bluetooth désactivé");
        return false;
      }

      return true;
    } catch (e) {
      debugPrint("❌ Erreur vérification Bluetooth: $e");
      return false;
    }
  }

  /// Scanner les appareils BLE
  Stream<List<ScanResult>> scanDevices() {
    return FlutterBluePlus.scanResults;
  }

  /// Démarrer le scan
  Future<void> startScan() async {
    try {
      // Vérifier que Bluetooth est activé
      final isOn = await FlutterBluePlus.isOn;
      if (!isOn) {
        throw Exception('Bluetooth désactivé. Veuillez l\'activer.');
      }

      debugPrint('🔍 Démarrage du scan BLE...');

      // Démarrer le scan (15 secondes timeout)
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        androidUsesFineLocation: true,
      );

      debugPrint('✅ Scan BLE démarré');
    } catch (e) {
      debugPrint('❌ Erreur scan BLE: $e');
      rethrow;
    }
  }

  /// Arrêter le scan
  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    debugPrint('⏹️ Scan BLE arrêté');
  }

  /// Se connecte à un device BLE spécifique.
  /// Retourne (true, null) en succès, (false, messageErreur) en échec.
  /// [internalRetry] : tentative interne après échec des notifications (déconnexion).
  Future<(bool, String?)> connectToDevice(BluetoothDevice device, {int internalRetry = 0}) async {
    _isConnecting = true;
    _notifyFailedBecauseDisconnected = false;
    try {
      debugPrint("🔵 Connexion à ${device.platformName}...");
      debugPrint("🔍 UUID du service recherché: $serviceUuid");

      // Ne déconnecter que si déjà connecté (ex. connexion précédente), pour repartir propre
      final stateBefore = await device.connectionState.first;
      if (stateBefore == BluetoothConnectionState.connected) {
        try {
          await device.disconnect();
          await Future<void>.delayed(const Duration(milliseconds: 800));
        } catch (_) {}
      }

      // Connexion au device (comme nRF Connect)
      await device.connect(
        timeout: const Duration(seconds: 15),
        autoConnect: false,
      );

      _connectedDevice = device;

      await device.connectionState
          .where((s) => s == BluetoothConnectionState.connected)
          .first
          .timeout(const Duration(seconds: 5),
              onTimeout: () => throw Exception('Connexion BLE non établie à temps'));

      // Stabilisation courte puis demande MTU (améliore fiabilité GATT sur Android, comme nRF)
      debugPrint("🔗 [BLE] Connexion établie, stabilisation ${kStabilisationAfterConnect.inMilliseconds}ms...");
      await Future<void>.delayed(kStabilisationAfterConnect);
      final stateAfterDelay = await device.connectionState.first;
      if (stateAfterDelay != BluetoothConnectionState.connected) {
        debugPrint("🔗 [BLE] Déconnexion pendant la stabilisation (état: $stateAfterDelay).");
        throw Exception('Le pansement s\'est déconnecté pendant la connexion.');
      }

      // Demander un MTU plus grand (fiabilité Android, comme nRF Connect)
      try {
        final mtu = await device.requestMtu(512);
        debugPrint("🔗 [BLE] MTU négocié: $mtu");
      } catch (e) {
        debugPrint("⚠️ requestMtu ignoré: $e");
      }

      // Un seul listener : annuler l'ancien pour ne pas accumuler les callbacks
      _connectionStateSubscription?.cancel();
      _connectionStateSubscription = device.connectionState.listen((state) {
        debugPrint("📡 État connexion: $state");
        onConnectionStateChanged?.call(state);

        if (state == BluetoothConnectionState.disconnected && !_isConnecting) {
          debugPrint("🔗 [BLE] Déconnexion reçue (listener), cleanup.");
          _cleanup();
        }
      });

      // Découvrir les services
      debugPrint("🔗 [BLE] Début discoverServices()...");
      final services = await device.discoverServices();
      debugPrint("🔗 [BLE] discoverServices() terminé, ${services.length} service(s).");

      for (final s in services) {
        debugPrint("📋 Service trouvé: ${s.uuid}");
      }

      // Court délai pour laisser le GATT bien prêt (stabilité sur certains appareils)
      await Future<void>.delayed(kDelayAfterDiscoverServices);

      // Essayer d'abord le service pansement, sinon Nordic UART (NUS) pour cartes nRF
      BluetoothService? service;
      try {
        service = services.firstWhere(
            (s) => s.uuid.toString().toLowerCase() == serviceUuid.toLowerCase());
        debugPrint("✅ Service pansement trouvé: ${service.uuid}");
      } catch (_) {
        try {
          service = services.firstWhere(
              (s) => s.uuid.toString().toLowerCase() == nusServiceUuid.toLowerCase());
          debugPrint("✅ Service Nordic UART (NUS) trouvé: ${service.uuid}");
        } catch (_) {
          service = null;
        }
      }
      if (service == null) {
        throw Exception("Aucun service supporté (pansement ou Nordic NUS). Trouvé: ${services.map((s) => s.uuid).join(', ')}");
      }

      debugPrint("🔗 [BLE] Service utilisé: ${service.uuid} (vérifier dans nRF Connect que c'est celui qui notifie)");

      // Caractéristique : pour NUS utiliser TX (notify), sinon choisir notify/indicate si possible
      if (service.uuid.toString().toLowerCase() == nusServiceUuid.toLowerCase()) {
        try {
          _dataCharacteristic = service.characteristics.firstWhere(
              (c) => c.uuid.toString().toLowerCase() == nusTxCharacteristicUuid.toLowerCase());
        } catch (_) {
          final notif = service.characteristics.where(
              (c) => c.properties.notify || c.properties.indicate);
          _dataCharacteristic = notif.isNotEmpty ? notif.first : service.characteristics.first;
        }
      } else {
        if (characteristicUuid == null || characteristicUuid!.isEmpty) {
          final notif = service.characteristics.where(
              (c) => c.properties.notify || c.properties.indicate);
          if (notif.isNotEmpty) {
            _dataCharacteristic = notif.first;
          } else {
            // Fallback: première caractéristique disponible
            _dataCharacteristic = service.characteristics.isNotEmpty
                ? service.characteristics.first
                : null;
          }
        } else {
          try {
            _dataCharacteristic = service.characteristics.firstWhere(
                (c) => c.uuid.toString().toLowerCase() == characteristicUuid!.toLowerCase());
          } catch (_) {
            _dataCharacteristic = null;
          }
        }
      }
      if (_dataCharacteristic == null) {
        throw Exception("Aucune caractéristique notify/read trouvée dans le service ${service.uuid}");
      }
      debugPrint("✅ Caractéristique utilisée: ${_dataCharacteristic!.uuid} (doit être Notify/Indicate dans nRF Connect)");

      // Délai avant setNotifyValue (stabilité : évite GATT pas prêt)
      debugPrint("🔗 [BLE] Attente ${kDelayBeforeSetNotify.inMilliseconds}ms avant setNotifyValue...");
      await Future<void>.delayed(kDelayBeforeSetNotify);
      final stateBeforeNotify = await device.connectionState.first;
      if (stateBeforeNotify != BluetoothConnectionState.connected) {
        _isConnecting = false;
        _notifyFailedBecauseDisconnected = true;
        _cleanup();
        debugPrint("⚠️ Pansement déjà déconnecté avant setNotifyValue (état: $stateBeforeNotify).");
        const disconnectMsg =
            'Le pansement s\'est déconnecté. Rapprochez l\'appareil et réessayez.';
        return (false, disconnectMsg);
      }
      debugPrint("🔗 [BLE] Appel setNotifyValue(true)...");

      // Activer les notifications pour recevoir les données
      await _enableNotifications();

      const disconnectMsg =
          'Le pansement s\'est déconnecté. Rapprochez l\'appareil et réessayez.';
      if (_notifyFailedBecauseDisconnected) {
        _isConnecting = false;
        if (internalRetry < 1) {
          debugPrint("🔄 [BLE] Reconnexion automatique (1 tentative) après échec notifications...");
          await disconnectDevice(device);
          await Future<void>.delayed(const Duration(milliseconds: 2200));
          _cleanup();
          return await connectToDevice(device, internalRetry: internalRetry + 1);
        }
        _cleanup();
        debugPrint("⚠️ Pansement déconnecté avant la fin de la configuration.");
        return (false, disconnectMsg);
      }
      final currentState = await device.connectionState.first;
      if (currentState != BluetoothConnectionState.connected) {
        _isConnecting = false;
        _cleanup();
        debugPrint("⚠️ Pansement déconnecté avant la fin de la configuration.");
        return (false, disconnectMsg);
      }

      _isConnecting = false;
      debugPrint("✅ Connecté avec succès à ${device.platformName}");

      // Réessai automatique des notifications après 5 s (débloque si le 1er setNotifyValue a timeout)
      Future<void>.delayed(const Duration(seconds: 5), () {
        if (_connectedDevice != null && _dataCharacteristic != null) {
          debugPrint("🔔 [BLE] Réessai automatique setNotifyValue (5 s après connexion)...");
          retryEnableNotifications();
        }
      });

      return (true, null);
    } catch (e, stackTrace) {
      _isConnecting = false;
      debugPrint("❌ Erreur de connexion: $e");
      debugPrint("Stack trace: $stackTrace");
      final String msg;
      if (e is PlatformException) {
        final m = (e.message ?? '').toLowerCase();
        if (m.contains('requestmtu') && m.contains('disconnected')) {
          msg = 'Le pansement s\'est déconnecté pendant la liaison. Rapprochez l\'appareil et réessayez.';
        } else {
          msg = _userFriendlyReadError(e.toString());
        }
      } else {
        msg = _userFriendlyReadError(e.toString());
      }
      try {
        await device.disconnect();
      } catch (_) {}
      _cleanup();
      return (false, msg);
    }
  }

  /// Écrit le [token] (ex. depuis deep link epatch://pair?token=...) sur une caractéristique en écriture.
  Future<void> writeTokenToDevice(BluetoothDevice device, String token) async {
    try {
      final services = await device.discoverServices();
      final tokenBytes = utf8.encode(token);
      for (final service in services) {
        final uuid = service.uuid.toString().toLowerCase();
        if (uuid != serviceUuid.toLowerCase() && uuid != nusServiceUuid.toLowerCase()) {
          continue;
        }
        for (final char in service.characteristics) {
          if (char.properties.write || char.properties.writeWithoutResponse) {
            await char.write(tokenBytes, withoutResponse: char.properties.writeWithoutResponse && !char.properties.write);
            debugPrint("✅ Token écrit sur ${char.uuid}");
            return;
          }
        }
      }
      debugPrint("⚠️ Aucune caractéristique en écriture trouvée pour le token.");
    } catch (e) {
      debugPrint("❌ Erreur écriture token: $e");
      rethrow;
    }
  }

  /// Active les notifications et s'abonne au stream pour recevoir les données.
  /// En cas de GATT_INSUFFICIENT_AUTHENTICATION, tente un appariement (createBond) puis réessaie.
  Future<void> _enableNotifications() async {
    if (_dataCharacteristic == null) return;

    final canNotify = _dataCharacteristic!.properties.notify;
    final canIndicate = _dataCharacteristic!.properties.indicate;
    if (!canNotify && !canIndicate) {
      debugPrint(
        "⚠️ Ni notify ni indicate supportés, lecture manuelle uniquement",
      );
      return;
    }

    bool success = false;
    const int maxAttempts = 3;
    BluetoothDevice? device = _connectedDevice;
    for (int attempt = 0; attempt < maxAttempts && !success; attempt++) {
      if (_dataCharacteristic == null || _connectedDevice == null) break;
      try {
        if (attempt > 0) {
          final state = device != null ? await device.connectionState.first : BluetoothConnectionState.disconnected;
          if (state != BluetoothConnectionState.connected) {
            _notifyFailedBecauseDisconnected = true;
            debugPrint("   Pansement déconnecté avant réessai, abandon.");
            break;
          }
          debugPrint("🔔 Réessai setNotifyValue (tentative ${attempt + 1}/$maxAttempts)...");
          await Future<void>.delayed(const Duration(milliseconds: 2000));
        }
        if (device != null) {
          final stateBefore = await device.connectionState.first;
          if (stateBefore != BluetoothConnectionState.connected) {
            _notifyFailedBecauseDisconnected = true;
            debugPrint("   Pansement déconnecté, abandon setNotifyValue.");
            break;
          }
        }
        await _dataCharacteristic!.setNotifyValue(true);
        debugPrint("🔔 Notifications activées (notify: $canNotify, indicate: $canIndicate)");
        success = true;
      } catch (e) {
        debugPrint("❌ Erreur activation notifications: $e");
        final msg = e.toString().toLowerCase();
        if (msg.contains('disconnected') || msg.contains('fbp-code: 6') || msg.contains('not connected')) {
          _notifyFailedBecauseDisconnected = true;
          debugPrint("   Pansement déconnecté : pas de nouvel essai setNotifyValue.");
          break;
        }
        // Timeout (fbp-code: 1) : le GATT peut quand même être prêt, on continue en mode "lecture manuelle possible"
        if (msg.contains('fbp-code: 1') || msg.contains('timed out')) {
          debugPrint("   Timeout setNotifyValue : connexion maintenue, vous pouvez lancer la collecte manuelle.");
          success = true;
          break;
        }
        // GATT_INSUFFICIENT_AUTHENTICATION (5) : le périphérique peut demander un appariement.
        // Sur beaucoup de téléphones (ex. Samsung) la demande de pairage in-app ne s'affiche pas.
        // On tente createBond() une fois ; si ça échoue ou timeout, on indique d'appairer manuellement.
        final isAuthError = msg.contains('insufficient_auth') ||
            msg.contains('android-code: 5') ||
            msg.contains('gatt_insufficient_authentication');
        if (isAuthError && _connectedDevice != null) {
          const bondTimeout = Duration(seconds: 25);
          try {
            debugPrint("🔐 Tentative d'appariement (createBond)...");
            await _connectedDevice!.createBond();
            final bonded = await _connectedDevice!.bondState
                .where((s) => s == BluetoothBondState.bonded)
                .first
                .timeout(bondTimeout);
            if (bonded == BluetoothBondState.bonded) {
              debugPrint("🔔 Réessai setNotifyValue après appariement...");
              await _dataCharacteristic!.setNotifyValue(true);
              debugPrint("🔔 Notifications activées après appariement.");
              success = true;
            }
          } catch (bondError) {
            debugPrint("⚠️ Appariement in-app impossible: $bondError");
            final deviceName = _connectedDevice?.platformName ?? 'pansement';
            onError?.call(
              'Pairage : quittez l\'app → Paramètres → Bluetooth → appairez « $deviceName » → revenez dans l\'app et réessayez.',
            );
          }
        }
        if (!success && attempt == maxAttempts - 1) {
          debugPrint("   Abonnement au stream quand même (le device peut envoyer des données).");
          onError?.call(_userFriendlySetNotifyError(e.toString()));
        }
      }
    }

    if (_dataCharacteristic != null) {
      _subscribeToNotificationStream();
    }
  }

  /// Réessaie d'activer les notifications (utile après un timeout au premier essai).
  /// Retourne true si setNotifyValue a réussi.
  Future<bool> retryEnableNotifications() async {
    if (_dataCharacteristic == null || _connectedDevice == null) return false;
    final state = await _connectedDevice!.connectionState.first;
    if (state != BluetoothConnectionState.connected) return false;
    try {
      await _dataCharacteristic!.setNotifyValue(true);
      debugPrint("🔔 Notifications réactivées (retry).");
      return true;
    } catch (e) {
      debugPrint("❌ Retry setNotifyValue: $e");
      return false;
    }
  }

  void _subscribeToNotificationStream() {
    if (_dataCharacteristic == null) return;
    _notificationSubscription?.cancel();
    _notificationSubscription = _dataCharacteristic!.lastValueStream.listen(
      (data) {
        if (data.isEmpty) return;
        _handleReceivedData(data);
      },
      onError: (error) {
        debugPrint("❌ Erreur notification: $error");
        onError?.call(error.toString());
      },
    );
  }

  /// Traite les données reçues depuis le pansement.
  /// Accepte soit du JSON (ancien format), soit le paquet binaire 12 octets (firmware nRF):
  /// struct data_packet_t { uint32_t freq; float z_val; float phase; } __packed; (little-endian)
  void _handleReceivedData(List<int> data) {
    try {
      if (data.isEmpty) return;

      debugPrint("🔴 RAW DATA (${data.length} bytes): $data");

      final measurements = data.length >= 12 && data[0] != 0x7b /* '{' */
          ? _handleBinaryStreamData(data)
          : _parseJsonPacket(data);

      if (measurements != null) {
        debugPrint("🟢 PARSED: $measurements");
        _lastNotificationMeasurements = measurements;
        onDataReceived?.call(measurements);
      } else {
        debugPrint("🔴 NULL après parsing");
        debugPrint("📥 Données reçues mais non reconnues: length=${data.length}, premiers octets: ${data.take(16).toList()} (binaire 12 octets ou JSON attendu)");
      }
    } catch (e) {
      debugPrint("❌ Erreur traitement données: $e");
      debugPrint("Données brutes (length=${data.length}): ${data.take(32).toList()}");
      onError?.call("Erreur de décodage: $e");
    }
  }

  /// Traite un flux binaire BLE composé de paquets de 12 octets:
  /// [uint32 freq][float impedance][float phase] en little-endian.
  ///
  /// Gère:
  /// - les paquets fragmentés (ex: 8 + 4 octets sur 2 notifications),
  /// - les paquets concaténés (ex: 24, 36, 48 octets en une notification).
  Map<String, dynamic>? _handleBinaryStreamData(List<int> data) {
    _binaryReceiveBuffer.addAll(data);
    Map<String, dynamic>? lastParsed;

    while (_binaryReceiveBuffer.length >= 12) {
      final packet = _binaryReceiveBuffer.sublist(0, 12);
      _binaryReceiveBuffer.removeRange(0, 12);

      final parsed = _parseBinaryPacket(packet);
      if (parsed != null) {
        lastParsed = parsed;
        _lastNotificationMeasurements = parsed;
        onDataReceived?.call(parsed);
      }
    }

    if (_binaryReceiveBuffer.isNotEmpty) {
      debugPrint(
        "🧩 Buffer partiel conservé: ${_binaryReceiveBuffer.length} octets",
      );
    }

    return lastParsed;
  }

  /// Paquet binaire 12 octets (nRF): freq (uint32), z_val (float), phase (float), little-endian.
  Map<String, dynamic>? _parseBinaryPacket(List<int> data) {
    if (data.length < 12) return null;
    final byteData = ByteData.sublistView(Uint8List.fromList(data));
    final freq = byteData.getUint32(0, Endian.little);
    final zVal = byteData.getFloat32(4, Endian.little);
    final phase = byteData.getFloat32(8, Endian.little);
    debugPrint("📥 Paquet binaire: freq=$freq Hz | Z=$zVal Ω | φ=$phase°");
    final point = {
      'timestamp': DateTime.now().toIso8601String(),
      'freq': freq.toDouble(),
      'impedance': zVal,
      'phase': phase,
    };
    _sweepPoints.add(point);
    return point;
  }

  /// Liste de tous les points du balayage reçus (pour Bode + envoi serveur).
  List<Map<String, dynamic>> getSweepPoints() =>
      List<Map<String, dynamic>>.from(_sweepPoints);

  /// Réinitialise la liste des points (à la déconnexion ou nouveau balayage).
  void clearSweepPoints() => _sweepPoints.clear();

  /// Ancien format JSON (ex: {"val": 101} ou {"adc_val": 1234}).
  Map<String, dynamic>? _parseJsonPacket(List<int> data) {
    final jsonString = utf8.decode(data);
    debugPrint("📥 Données brutes reçues: $jsonString");
    final jsonData = json.decode(jsonString) as Map<String, dynamic>;
    debugPrint("📊 JSON parsé: $jsonData");
    return _convertAdcToMeasurements(jsonData);
  }

  /// Repasse les données reçues du pansement telles quelles (avec horodatage).
  /// Aucune conversion : on affiche exactement ce que le device envoie.
  Map<String, dynamic> _convertAdcToMeasurements(
    Map<String, dynamic> jsonData,
  ) {
    final result = <String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
    };
    for (final entry in jsonData.entries) {
      final v = entry.value;
      if (v is num) {
        result[entry.key] = v is int ? v.toDouble() : v;
      } else if (v is String) {
        result[entry.key] = v;
      } else {
        result[entry.key] = v;
      }
    }
    return result;
  }

  /// Dernières mesures reçues par notification (pour Rafraîchir quand la lecture n'est pas permise).
  Map<String, dynamic>? getLastMeasurements() => _lastNotificationMeasurements;

  /// Lit les données manuellement (si la caractéristique le permet).
  /// [forceTryRead] : quand true (ex. tap sur Rafraîchir), tente read() même si une tentative précédente a échoué (GATT).
  Future<Map<String, dynamic>?> readMeasurements(
    BluetoothDevice device, {
    bool forceTryRead = false,
  }) async {
    try {
      if (_dataCharacteristic == null) {
        const msg =
            'Connexion perdue ou capteur non prêt. Rapprochez le pansement et réessayez.';
        onError?.call(msg);
        return null;
      }

      // Ne jamais rappeler read() si on sait déjà que la lecture n'est pas permise (évite GATT_READ_NOT_PERMITTED en boucle).
      if (_readNotPermitted) {
        return _lastNotificationMeasurements;
      }

      if (!forceTryRead) return null;

      if (!_dataCharacteristic!.properties.read) {
        if (!_readNotPermittedLogged) {
          _readNotPermittedLogged = true;
          debugPrint(
            "📡 Lecture non permise. Données via notifications uniquement.",
          );
          onError?.call(
            'Le pansement envoie les données automatiquement. Attendez quelques secondes ou rapprochez l\'appareil.',
          );
        }
        _readNotPermitted = true;
        return null;
      }

      if (!forceTryRead) debugPrint("📖 Lecture manuelle des données...");

      final data = await _dataCharacteristic!.read();

      if (data.isEmpty) {
        throw Exception("Aucune donnée reçue");
      }

      final measurements = data.length >= 12 && data[0] != 0x7b
          ? _handleBinaryStreamData(data)
          : _parseJsonPacket(data);
      if (measurements != null) {
        _lastNotificationMeasurements = measurements;
        return measurements;
      }
      return null;
    } catch (e) {
      final msg = e.toString().toLowerCase();
      final isReadNotPermitted = msg.contains('gatt_read_not_permitted') ||
          msg.contains('readcharacteristic') ||
          msg.contains('read not permitted') ||
          msg.contains('fbp-code: 2');
      if (isReadNotPermitted) {
        _readNotPermitted = true;
        if (!_readNotPermittedLogged) {
          _readNotPermittedLogged = true;
          debugPrint(
              "📡 Lecture non permise. Données via notifications uniquement.");
        }
        return _lastNotificationMeasurements;
      }
      debugPrint("❌ Erreur lecture: $e");
      onError?.call(_userFriendlyReadError(msg));
      return null;
    }
  }

  /// Message court pour l'erreur setNotifyValue / Device is disconnected.
  static String _userFriendlySetNotifyError(String technical) {
    final lower = technical.toLowerCase();
    if (lower.contains('disconnected') || lower.contains('fbp-code: 6') || lower.contains('setnotifyvalue')) {
      return 'Le pansement s\'est déconnecté pendant la configuration. Rapprochez-le et appuyez sur « Réessayer la connexion ».';
    }
    return technical.length > 100 ? 'Erreur de connexion au pansement. Rapprochez l\'appareil et réessayez.' : technical;
  }

  /// Message utilisateur pour les erreurs BLE (connexion et lecture).
  static String _userFriendlyReadError(String technical) {
    final lower = technical.toLowerCase();
    if (lower.contains('disconnected') || lower.contains('déconnecté') ||
        lower.contains('non initialisée') || lower.contains('characteristic')) {
      return 'Connexion perdue ou capteur non prêt. Rapprochez le pansement et réessayez.';
    }
    // Erreur Android 133 : connexion refusée / appareil occupé (souvent après annulation appariement)
    if (lower.contains('android-code: 133') || lower.contains('android_code: 133') ||
        lower.contains('133') && lower.contains('android')) {
      return 'Connexion refusée par l\'appareil. Éteignez-le puis rallumez-le, attendez 5 s et réessayez.';
    }
    if (lower.contains('gatt') || lower.contains('read') && lower.contains('permit')) {
      return 'Données disponibles uniquement via le flux du capteur. Attendez quelques secondes ou réessayez.';
    }
    if (lower.contains('aucune donnée') || lower.contains('empty') || lower.contains('timeout')) {
      return 'Aucune donnée reçue du pansement. Rapprochez l\'appareil et réessayez.';
    }
    return 'Impossible de lire le pansement. Rapprochez l\'appareil et réessayez.';
  }

  /// Déconnecte le device actuel
  Future<void> disconnectDevice(BluetoothDevice device) async {
    try {
      debugPrint("🔴 Déconnexion de ${device.platformName}...");
      await device.disconnect();
      _cleanup();
      debugPrint("✅ Déconnecté");
    } catch (e) {
      debugPrint("❌ Erreur déconnexion: $e");
    }
  }

  /// Nettoie les ressources (chaque reconnexion repart à zéro).
  void _cleanup() {
    _connectionStateSubscription?.cancel();
    _connectionStateSubscription = null;
    _notificationSubscription?.cancel();
    _notificationSubscription = null;
    _dataCharacteristic = null;
    _connectedDevice = null;
    _readNotPermitted = false;
    _readNotPermittedLogged = false;
    _lastNotificationMeasurements = null;
    _notifyFailedBecauseDisconnected = false;
    _binaryReceiveBuffer.clear();
    clearSweepPoints();
  }

  /// Vérifie si un device est connecté
  bool get isConnected => _connectedDevice != null;

  /// Récupère le device connecté
  BluetoothDevice? get connectedDevice => _connectedDevice;

  /// Dispose (à appeler quand on quitte l'app)
  void dispose() {
    _cleanup();
  }
}
