import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logger/logger.dart';
import 'package:permission_handler/permission_handler.dart';
import '../config/api_config.dart';

class BleService {
  final Logger _logger = Logger();

  // Scanner les appareils BLE
  Stream<List<ScanResult>> scanDevices() {
    return FlutterBluePlus.scanResults;
  }

  // Démarrer le scan
  Future<void> startScan() async {
    try {
      // Vérifier les permissions
      final hasPermission = await _checkPermissions();
      if (!hasPermission) {
        throw Exception('Permissions Bluetooth non accordées');
      }

      // Vérifier que Bluetooth est activé
      final isOn = await FlutterBluePlus.isOn;
      if (!isOn) {
        throw Exception('Bluetooth désactivé. Veuillez l\'activer.');
      }

      _logger.i('Démarrage du scan BLE...');

      // Démarrer le scan (5 secondes timeout)
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 5),
        androidUsesFineLocation: true,
      );

      _logger.i('Scan BLE démarré');
    } catch (e) {
      _logger.e('Erreur scan BLE: $e');
      rethrow;
    }
  }

  // Arrêter le scan
  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    _logger.i('Scan BLE arrêté');
  }

  // Vérifier les permissions
  Future<bool> _checkPermissions() async {
    if (await Permission.bluetoothScan.isDenied) {
      final result = await Permission.bluetoothScan.request();
      if (result.isDenied) return false;
    }

    if (await Permission.bluetoothConnect.isDenied) {
      final result = await Permission.bluetoothConnect.request();
      if (result.isDenied) return false;
    }

    if (await Permission.location.isDenied) {
      final result = await Permission.location.request();
      if (result.isDenied) return false;
    }

    return true;
  }

  // Se connecter à un device
  Future<void> connectToDevice(BluetoothDevice device) async {
    try {
      _logger.i('Connexion à ${device.platformName}...');

      await device.connect(
        timeout: const Duration(seconds: 15),
        autoConnect: false,
      );

      _logger.i('Connecté à ${device.platformName}');
    } catch (e) {
      _logger.e('Erreur connexion: $e');
      rethrow;
    }
  }

  // Se déconnecter
  Future<void> disconnectDevice(BluetoothDevice device) async {
    try {
      await device.disconnect();
      _logger.i('Déconnecté de ${device.platformName}');
    } catch (e) {
      _logger.e('Erreur déconnexion: $e');
    }
  }

  // Lire les mesures du pansement
  Future<Map<String, double>> readMeasurements(BluetoothDevice device) async {
    try {
      _logger.i('Lecture des mesures...');

      // Découvrir les services
      final services = await device.discoverServices();

      // Trouver notre service personnalisé
      final service = services.firstWhere(
        (s) =>
            s.uuid.toString().toLowerCase() ==
            ApiConfig.serviceUuid.toLowerCase(),
        orElse: () => throw Exception('Service non trouvé'),
      );

      // Lire température
      final tempChar = service.characteristics.firstWhere(
        (c) =>
            c.uuid.toString().toLowerCase() ==
            ApiConfig.temperatureCharUuid.toLowerCase(),
        orElse: () =>
            throw Exception('Caractéristique température non trouvée'),
      );
      final tempValue = await tempChar.read();
      final temperature = _bytesToDouble(tempValue);

      // Lire humidité
      final humChar = service.characteristics.firstWhere(
        (c) =>
            c.uuid.toString().toLowerCase() ==
            ApiConfig.humidityCharUuid.toLowerCase(),
        orElse: () => throw Exception('Caractéristique humidité non trouvée'),
      );
      final humValue = await humChar.read();
      final humidity = _bytesToDouble(humValue);

      // Lire pH
      final phChar = service.characteristics.firstWhere(
        (c) =>
            c.uuid.toString().toLowerCase() ==
            ApiConfig.phCharUuid.toLowerCase(),
        orElse: () => throw Exception('Caractéristique pH non trouvée'),
      );
      final phValue = await phChar.read();
      final ph = _bytesToDouble(phValue);

      _logger.i('Mesures lues: T=$temperature, H=$humidity, pH=$ph');

      return {
        'temperature': temperature,
        'humidity': humidity,
        'ph': ph,
      };
    } catch (e) {
      _logger.e('Erreur lecture mesures: $e');
      rethrow;
    }
  }

  // Convertir bytes en double
  double _bytesToDouble(List<int> bytes) {
    if (bytes.isEmpty) return 0.0;

    // Si c'est un float (4 bytes)
    if (bytes.length == 4) {
      final uint8List = Uint8List.fromList(bytes);
      final buffer = uint8List.buffer.asByteData();
      return buffer.getFloat32(0, Endian.little);
    }

    // Sinon, conversion simple
    return bytes[0].toDouble();
  }

  // S'abonner aux notifications (streaming temps réel)
  Stream<Map<String, double>> subscribeMeasurements(
      BluetoothDevice device) async* {
    try {
      final services = await device.discoverServices();
      final service = services.firstWhere(
        (s) =>
            s.uuid.toString().toLowerCase() ==
            ApiConfig.serviceUuid.toLowerCase(),
      );

      final tempChar = service.characteristics.firstWhere(
        (c) =>
            c.uuid.toString().toLowerCase() ==
            ApiConfig.temperatureCharUuid.toLowerCase(),
      );

      // Activer les notifications
      await tempChar.setNotifyValue(true);

      // Écouter les changements
      await for (final value in tempChar.onValueReceived) {
        final temperature = _bytesToDouble(value);
        yield {'temperature': temperature};
      }
    } catch (e) {
      _logger.e('Erreur streaming: $e');
    }
  }
}
