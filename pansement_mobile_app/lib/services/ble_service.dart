import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Service BLE pour communiquer avec le pansement connecté
///
/// Configuration basée sur le device réel détecté :
/// - Service UUID: 75c276c3-8f97-20bc-a143-b354244886d4 (UUID réel du device)
/// - Characteristic UUID: À déterminer après connexion (sera mis à jour automatiquement)
/// - Device Name: "Pansement" ou "Mon_Pansement"
class BleService {
  // UUIDs correspondant au device réel détecté
  // Service UUID réel trouvé lors de la connexion: 75c276c3-8f97-20bc-a143-b354244886d4
  static const String serviceUuid = "75c276c3-8f97-20bc-a143-b354244886d4";
  // Characteristic UUID: sera déterminé automatiquement lors de la connexion
  // Pour l'instant, on utilisera la première caractéristique du service
  static const String? characteristicUuid =
      null; // null = utiliser la première caractéristique
  static const String deviceNamePrefix = "Pansement";

  // État de connexion
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _dataCharacteristic;
  StreamSubscription? _notificationSubscription;

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

  /// Se connecte à un device BLE spécifique
  Future<bool> connectToDevice(BluetoothDevice device) async {
    try {
      debugPrint("🔵 Connexion à ${device.platformName}...");
      debugPrint("🔍 UUID du service recherché: $serviceUuid");

      // Connexion au device
      await device.connect(
        timeout: const Duration(seconds: 15),
        autoConnect: false,
      );

      _connectedDevice = device;

      // Écouter les changements de connexion
      device.connectionState.listen((state) {
        debugPrint("📡 État connexion: $state");
        onConnectionStateChanged?.call(state);

        if (state == BluetoothConnectionState.disconnected) {
          _cleanup();
        }
      });

      // Découvrir les services
      debugPrint("🔍 Découverte des services...");
      final services = await device.discoverServices();

      // Afficher tous les services pour debug
      debugPrint("🔍 Recherche du service UUID: $serviceUuid");
      for (final s in services) {
        debugPrint("📋 Service trouvé: ${s.uuid}");
      }

      // Trouver notre service personnalisé
      debugPrint("🔍 Comparaison: serviceUuid = $serviceUuid");
      final service = services.firstWhere((s) {
        final match =
            s.uuid.toString().toLowerCase() == serviceUuid.toLowerCase();
        debugPrint("  - ${s.uuid} == $serviceUuid ? $match");
        return match;
      }, orElse: () => throw Exception("Service non trouvé: $serviceUuid"));

      debugPrint("✅ Service trouvé: ${service.uuid}");

      // Afficher toutes les caractéristiques pour debug
      for (final c in service.characteristics) {
        debugPrint("📋 Caractéristique trouvée: ${c.uuid}");
      }

      // Trouver la caractéristique de données
      // Si characteristicUuid est null, utiliser la première caractéristique disponible
      if (characteristicUuid == null || characteristicUuid!.isEmpty) {
        if (service.characteristics.isEmpty) {
          throw Exception("Aucune caractéristique trouvée dans le service");
        }
        _dataCharacteristic = service.characteristics.first;
        debugPrint(
          "📋 Utilisation de la première caractéristique: ${_dataCharacteristic!.uuid}",
        );
      } else {
        _dataCharacteristic = service.characteristics.firstWhere(
          (c) =>
              c.uuid.toString().toLowerCase() ==
              characteristicUuid!.toLowerCase(),
          orElse:
              () =>
                  throw Exception(
                    "Caractéristique non trouvée: $characteristicUuid",
                  ),
        );
      }

      debugPrint("✅ Caractéristique trouvée: ${_dataCharacteristic!.uuid}");

      // Activer les notifications pour recevoir les données
      await _enableNotifications();

      debugPrint("✅ Connecté avec succès à ${device.platformName}");
      return true;
    } catch (e, stackTrace) {
      debugPrint("❌ Erreur de connexion: $e");
      debugPrint("Stack trace: $stackTrace");
      onError?.call(e.toString());
      await disconnectDevice(device);
      return false;
    }
  }

  /// Active les notifications pour recevoir les données en temps réel
  Future<void> _enableNotifications() async {
    if (_dataCharacteristic == null) return;

    try {
      // Vérifier si les notifications sont supportées
      if (!_dataCharacteristic!.properties.notify) {
        debugPrint(
          "⚠️ Les notifications ne sont pas supportées, utilisation de la lecture manuelle",
        );
        return;
      }

      // Activer les notifications (écrit dans le CCCD)
      await _dataCharacteristic!.setNotifyValue(true);
      debugPrint("🔔 Notifications activées");

      // S'abonner au stream de notifications
      _notificationSubscription = _dataCharacteristic!.lastValueStream.listen(
        (data) {
          _handleReceivedData(data);
        },
        onError: (error) {
          debugPrint("❌ Erreur notification: $error");
          onError?.call(error.toString());
        },
      );
    } catch (e) {
      debugPrint("❌ Erreur activation notifications: $e");
      onError?.call(e.toString());
    }
  }

  /// Traite les données reçues depuis le pansement (format JSON)
  void _handleReceivedData(List<int> data) {
    try {
      // Convertir les bytes en String
      final jsonString = utf8.decode(data);
      debugPrint("📥 Données brutes reçues: $jsonString");

      // Parser le JSON
      // Format attendu: {"adc_val": 1234, "status": "OK"}
      final jsonData = json.decode(jsonString) as Map<String, dynamic>;
      debugPrint("📊 JSON parsé: $jsonData");

      // Convertir adc_val en mesures réelles
      final measurements = _convertAdcToMeasurements(jsonData);

      // Notifier l'application
      onDataReceived?.call(measurements);
    } catch (e) {
      debugPrint("❌ Erreur traitement données: $e");
      debugPrint("Données brutes: $data");
      onError?.call("Erreur de décodage: $e");
    }
  }

  /// Convertit la valeur ADC en mesures physiques
  ///
  /// Basé sur votre capteur et les formules de conversion
  /// À adapter selon vos capteurs réels (température, humidité, pH)
  Map<String, dynamic> _convertAdcToMeasurements(
    Map<String, dynamic> jsonData,
  ) {
    final adcValue = (jsonData['adc_val'] as num).toInt();
    final status = jsonData['status'] as String? ?? 'Unknown';

    // TODO: Adapter ces formules selon vos vrais capteurs
    // Exemple de conversion (à remplacer par vos vraies formules)

    // Température (exemple: thermistance NTC)
    final temperature = _convertAdcToTemperature(adcValue);

    // Humidité (exemple: capteur capacitif)
    final humidity = _convertAdcToHumidity(adcValue);

    // pH (exemple: sonde pH)
    final ph = _convertAdcToPh(adcValue);

    return {
      'temperature': temperature,
      'humidity': humidity,
      'ph': ph,
      'adc_raw': adcValue,
      'status': status,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  /// Conversion ADC → Température (°C)
  /// À adapter selon votre capteur de température
  double _convertAdcToTemperature(int adcValue) {
    // Exemple pour ADC 12 bits (0-4095) avec référence 3.3V
    const adcMax = 4095.0;
    const vRef = 3.3;

    final voltage = (adcValue / adcMax) * vRef;

    // Formule exemple pour thermistance NTC 10K
    // REMPLACER par votre vraie formule !
    const double R_SERIES = 10000.0;
    const double R0 = 10000.0; // Résistance à 25°C
    const double T0 = 298.15; // 25°C en Kelvin
    const double B = 3950.0; // Coefficient β

    if (voltage >= vRef) return 0.0;
    double rt = R_SERIES * voltage / (vRef - voltage);
    double tempK =
        1.0 / ((1.0 / T0) + (1.0 / B) * (rt / R0).clamp(0.001, 1000));
    double tempC = tempK - 273.15;

    return double.parse(tempC.toStringAsFixed(1));
  }

  /// Conversion ADC → Humidité (%)
  /// À adapter selon votre capteur d'humidité
  double _convertAdcToHumidity(int adcValue) {
    // Exemple pour capteur capacitif
    const adcMax = 4095.0;

    // Calibration linéaire simple (à adapter)
    final humidity = (adcValue / adcMax) * 100.0;

    return double.parse(humidity.toStringAsFixed(1));
  }

  /// Conversion ADC → pH
  /// À adapter selon votre sonde pH
  double _convertAdcToPh(int adcValue) {
    // Exemple pour sonde pH
    const adcMax = 4095.0;
    const vRef = 3.3;

    final voltage = (adcValue / adcMax) * vRef;

    // Formule exemple (pH de 0 à 14)
    // REMPLACER par votre vraie formule de calibration !
    final ph = 7.0 + ((voltage - 1.65) * 3.5); // Exemple simplifié

    return double.parse(ph.toStringAsFixed(2));
  }

  /// Lit les données manuellement (si pas de notifications)
  Future<Map<String, dynamic>?> readMeasurements(BluetoothDevice device) async {
    try {
      if (_dataCharacteristic == null) {
        throw Exception("Caractéristique non initialisée");
      }

      debugPrint("📖 Lecture manuelle des données...");

      final data = await _dataCharacteristic!.read();

      if (data.isEmpty) {
        throw Exception("Aucune donnée reçue");
      }

      final jsonString = utf8.decode(data);
      debugPrint("📥 JSON reçu: $jsonString");

      final jsonData = json.decode(jsonString) as Map<String, dynamic>;

      return _convertAdcToMeasurements(jsonData);
    } catch (e) {
      debugPrint("❌ Erreur lecture: $e");
      onError?.call(e.toString());
      return null;
    }
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

  /// Nettoie les ressources
  void _cleanup() {
    _notificationSubscription?.cancel();
    _notificationSubscription = null;
    _dataCharacteristic = null;
    _connectedDevice = null;
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
