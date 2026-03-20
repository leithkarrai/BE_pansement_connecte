import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../services/ble_service.dart';

// ============================================================================
// PROVIDERS
// ============================================================================

/// Provider pour le service BLE singleton
final bleServiceProvider = Provider<BleService>((ref) {
  final service = BleService();
  // Nettoyer à la fin
  ref.onDispose(() {
    service.dispose();
  });
  return service;
});

/// Provider pour l'état du scan BLE
final bleScanProvider = StateNotifierProvider<BleScanNotifier, BleScanState>((
  ref,
) {
  return BleScanNotifier(ref.read(bleServiceProvider));
});

// ============================================================================
// ÉTATS
// ============================================================================

/// État du scan BLE
class BleScanState {
  final bool isScanning;
  final List<ScanResult> devices;
  final String? error;

  BleScanState({this.isScanning = false, this.devices = const [], this.error});

  BleScanState copyWith({
    bool? isScanning,
    List<ScanResult>? devices,
    String? error,
  }) {
    return BleScanState(
      isScanning: isScanning ?? this.isScanning,
      devices: devices ?? this.devices,
      error: error,
    );
  }
}

// ============================================================================
// NOTIFIER POUR LE SCAN
// ============================================================================

class BleScanNotifier extends StateNotifier<BleScanState> {
  final BleService _bleService;
  StreamSubscription? _scanSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;
  bool _isDisposed = false;

  BleScanNotifier(this._bleService) : super(BleScanState()) {
    // Écouter les changements d'état Bluetooth
    _adapterStateSubscription = FlutterBluePlus.adapterState.listen((
      adapterState,
    ) {
      if (_isDisposed) return;
      if (adapterState == BluetoothAdapterState.off) {
        _safeSetState(
            state.copyWith(isScanning: false, error: 'Bluetooth désactivé'));
        _scanSubscription?.cancel();
      }
    });
  }

  /// True si l'erreur est l'assertion de cycle de vie (widget disposé) — on ne la log pas.
  static bool _isLifecycleAssertion(Object? error) {
    final s = error.toString().toLowerCase();
    return s.contains('defunct') ||
        s.contains('_elementlifecycle') ||
        s.contains('lifecyclestate') ||
        s.contains('deactivated') ||
        s.contains('ancestor');
  }

  /// Met à jour l'état après le prochain frame pour éviter les assertions
  /// de cycle de vie quand un widget qui écoute est déjà disposé.
  void _safeSetState(BleScanState newState) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isDisposed) return;
      runZonedGuarded(() {
        if (_isDisposed) return;
        state = newState;
      }, (error, stackTrace) {
        if (!_isDisposed && !_isLifecycleAssertion(error)) {
          debugPrint("⚠️ Erreur mise à jour état scan: $error");
        }
      });
    });
  }

  /// Démarre le scan des devices BLE
  Future<void> startScan() async {
    if (_isDisposed) return;

    try {
      // Vérifier si le Bluetooth est disponible
      if (!await _bleService.isBluetoothAvailable()) {
        _safeSetState(state.copyWith(
          error: "Bluetooth non disponible. Veuillez l'activer.",
          isScanning: false,
        ));
        return;
      }

      // Nettoyer le scan précédent
      await stopScan();
      // Laisser le stack BLE se libérer avant de redémarrer (évite les échecs sur Android)
      await Future<void>.delayed(const Duration(milliseconds: 400));

      if (_isDisposed) return;
      _safeSetState(state.copyWith(isScanning: true, error: null, devices: []));

      debugPrint("🔍 Démarrage du scan BLE...");
      await _bleService.startScan();
      if (_isDisposed) return;

      // Écouter les résultats du scan
      _scanSubscription = FlutterBluePlus.scanResults.listen(
        (results) {
          if (_isDisposed) return;

          // DEBUG: Afficher tous les devices pour diagnostic
          debugPrint("📡 ${results.length} device(s) BLE détecté(s)");
          for (var result in results) {
            final name = result.device.platformName;
            debugPrint(
              "  - Device: ${name.isEmpty ? 'Sans nom' : name} (${result.device.remoteId})",
            );
          }
          // Afficher tous les appareils BLE pour ne pas rater le pansement (nom ou UUID parfois absents au scan)
          final filteredResults = List<ScanResult>.from(results);
          for (var result in results) {
            final name = result.device.platformName.toLowerCase();
            final hasPans = name.contains('pansement') ||
                name.contains('pensement') ||
                name.contains('pans');
            final hasNordic = name.contains('nordic') || name.contains('nrf');
            final hasService =
                result.advertisementData.serviceUuids.any((uuid) {
              final u = uuid.toString().toLowerCase();
              return u.contains('75c276c3') ||
                  u.contains('76c276c3') ||
                  u.contains('6e400001');
            });
            if (hasPans || hasNordic || hasService) {
              debugPrint(
                  "✅ Pansement/Nordic: ${result.device.remoteId} (${result.device.platformName})");
            }
          }

          // Éviter les doublons en utilisant un Set basé sur l'adresse MAC
          final uniqueDevices = <String, ScanResult>{};
          for (var result in filteredResults) {
            uniqueDevices[result.device.remoteId.toString()] = result;
          }

          // Vérifier à nouveau avant de mettre à jour l'état
          if (_isDisposed) return;

          final newDevicesList = uniqueDevices.values.toList();
          final currentState = state;

          // Reporter la mise à jour après le prochain frame pour éviter les assertions
          // de cycle de vie (widget disposé) quand un écran quitte pendant le scan
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_isDisposed) return;
            runZonedGuarded(() {
              if (_isDisposed) return;
              state = currentState.copyWith(devices: newDevicesList);
            }, (error, stackTrace) {
              if (!_isDisposed && !_isLifecycleAssertion(error)) {
                debugPrint(
                    "⚠️ Erreur mise à jour état scan (cycle de vie): $error");
              }
            });
          });

          if (uniqueDevices.isNotEmpty) {
            debugPrint("📡 ${uniqueDevices.length} device(s) détecté(s)");
          } else if (results.isNotEmpty) {
            debugPrint(
              "⚠️ Aucun device ciblé (pansement / Nordic nRF) parmi ${results.length} device(s)",
            );
          }
        },
        onError: (error) {
          if (_isDisposed) return;
          debugPrint("❌ Erreur scan: $error");
          _safeSetState(
              state.copyWith(isScanning: false, error: error.toString()));
        },
      );
    } catch (e) {
      if (_isDisposed) return;
      debugPrint("❌ Erreur démarrage scan: $e");
      final msg = e.toString().toLowerCase();
      final friendly = msg.contains('location') || msg.contains('localisation')
          ? 'Activez la localisation (requise pour le scan BLE sur Android).'
          : msg.contains('permission') || msg.contains('bluetooth')
              ? 'Vérifiez les autorisations : Bluetooth et localisation doivent être autorisés.'
              : e.toString();
      _safeSetState(state.copyWith(isScanning: false, error: friendly));
    }
  }

  /// Arrête le scan BLE
  Future<void> stopScan() async {
    try {
      await _scanSubscription?.cancel();
      _scanSubscription = null;

      if (await FlutterBluePlus.isScanning.first) {
        await FlutterBluePlus.stopScan();
      }

      _safeSetState(state.copyWith(isScanning: false));
      debugPrint("⏹️ Scan arrêté");
    } catch (e) {
      debugPrint("❌ Erreur arrêt scan: $e");
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    stopScan();
    _adapterStateSubscription?.cancel();
    super.dispose();
  }
}

// ============================================================================
// PROVIDER POUR LA CONNEXION À UN DEVICE
// ============================================================================

/// Provider pour gérer la connexion à un device spécifique
final deviceConnectionProvider = StateNotifierProvider.family<
    DeviceConnectionNotifier,
    DeviceConnectionState,
    BluetoothDevice>((ref, device) {
  final notifier = DeviceConnectionNotifier(
    device,
    ref.read(bleServiceProvider),
  );
  // Nettoyer à la fin
  ref.onDispose(() {
    notifier.dispose();
  });
  return notifier;
});

/// État de connexion à un device
class DeviceConnectionState {
  final bool isConnecting;
  final bool isConnected;
  final bool isReading;
  final Map<String, dynamic>? measurements;
  /// Points du balayage (freq, impedance, phase) pour courbe Bode et envoi serveur
  final List<Map<String, dynamic>> sweepPoints;
  final String? error;

  DeviceConnectionState({
    this.isConnecting = false,
    this.isConnected = false,
    this.isReading = false,
    this.measurements,
    this.sweepPoints = const [],
    this.error,
  });

  DeviceConnectionState copyWith({
    bool? isConnecting,
    bool? isConnected,
    bool? isReading,
    Map<String, dynamic>? measurements,
    List<Map<String, dynamic>>? sweepPoints,
    String? error,
    bool clearMeasurements = false,
  }) {
    return DeviceConnectionState(
      isConnecting: isConnecting ?? this.isConnecting,
      isConnected: isConnected ?? this.isConnected,
      isReading: isReading ?? this.isReading,
      measurements: clearMeasurements ? null : (measurements ?? this.measurements),
      sweepPoints: sweepPoints ?? this.sweepPoints,
      error: error,
    );
  }
}

class DeviceConnectionNotifier extends StateNotifier<DeviceConnectionState> {
  final BluetoothDevice device;
  final BleService bleService;
  bool _isDisposed = false;
  int _connectRetryCount = 0;

  DeviceConnectionNotifier(this.device, this.bleService)
      : super(DeviceConnectionState()) {
    _init();
  }

  void _init() {
    // Configurer les callbacks du service BLE
    bleService.onDataReceived = _handleDataReceived;
    bleService.onError = _handleError;
    bleService.onConnectionStateChanged = _handleConnectionStateChanged;
  }

  /// Connecte au device (avec 1 tentative automatique si déconnexion pendant setNotifyValue).
  Future<void> connect() async {
    if (_isDisposed) return;

    _safeSetState(state.copyWith(isConnecting: true, error: null));

    try {
      const connectionTimeout = Duration(seconds: 35);
      final (success, errorMsg) =
          await bleService.connectToDevice(device).timeout(
        connectionTimeout,
        onTimeout: () async {
          try {
            await bleService.disconnectDevice(device);
          } catch (_) {}
          return (
            false,
            'La connexion prend trop de temps. Rapprochez le pansement et appuyez sur « Réessayer la connexion ».'
          );
        },
      );

      if (_isDisposed) return;
      if (success) {
        _connectRetryCount = 0;
        bleService.clearSweepPoints();
        _safeSetState(state.copyWith(
          isConnecting: false,
          isConnected: true,
          sweepPoints: [],
          clearMeasurements: true,
          error: null,
        ));
        // Lancer la collecte automatique en arrière-plan (ne pas bloquer l'UI)
        Future<void>.delayed(Duration.zero, () => readMeasurements());
      } else {
        _safeSetState(state.copyWith(
          isConnecting: false,
          isConnected: false,
          error: errorMsg ?? state.error,
        ));
        if (!_isDisposed && _connectRetryCount < 1) {
          _connectRetryCount++;
          debugPrint("🔄 [BLE] Reconnexion automatique dans 2s...");
          await Future<void>.delayed(const Duration(seconds: 2));
          if (!_isDisposed) await connect();
        }
      }
    } catch (e) {
      if (_isDisposed) return;
      _safeSetState(state.copyWith(
        isConnecting: false,
        isConnected: false,
        error: e.toString(),
      ));
    }
  }

  /// Met à jour l'état après le prochain frame ; les erreurs de cycle de vie (widget disposé) sont absorbées.
  void _safeSetState(DeviceConnectionState newState) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isDisposed) return;
      runZonedGuarded(() {
        if (_isDisposed) return;
        state = newState;
      }, (error, _) {
        // Ne pas logger les assertions de cycle de vie (widget disposé / deactivated ancestor)
        final msg = error.toString().toLowerCase();
        final isLifecycleError = error is AssertionError ||
            msg.contains('defunct') ||
            (msg.contains('ref') && msg.contains('disposed')) ||
            msg.contains('deactivated') ||
            msg.contains('ancestor');
        if (!_isDisposed && !isLifecycleError) {
          debugPrint("⚠️ _safeSetState: $error");
        }
      });
    });
  }

  /// Lit les mesures.
  /// [forceRead] false = "Démarrer la collecte" : on n'envoie PAS de read BLE (évite la déconnexion),
  ///   on attend les données déjà reçues par notification.
  /// [forceRead] true = "Rafraîchir" : on tente un read() BLE.
  Future<void> readMeasurements({bool forceRead = false}) async {
    if (_isDisposed) return;

    // Effacer l'erreur avant de lancer la collecte pour ne pas afficher un ancien "Connexion perdue"
    final loadingState = state.copyWith(isReading: true, error: null);
    _safeSetState(loadingState);

    try {
      Map<String, dynamic>? measurements;

      if (forceRead) {
        measurements = await bleService.readMeasurements(
          device,
          forceTryRead: true,
        );
        if (_isDisposed) return;
        if (measurements == null) {
          measurements = bleService.getLastMeasurements();
        }
      } else {
        // "Démarrer la collecte" : attendre UNIQUEMENT les notifications (pas de read BLE).
        // Un read() sur ce pansement provoque souvent une déconnexion (caractéristique en notification seule).
        // Attendre jusqu'à ~25 s pour laisser le temps d'appuyer sur le bouton nRF puis de lancer la collecte.
        for (int i = 0; i < 25; i++) {
          await Future<void>.delayed(const Duration(seconds: 1));
          if (_isDisposed) return;
          final last = bleService.getLastMeasurements();
          if (last != null) {
            measurements = last;
            break;
          }
        }
        if (_isDisposed) return;
        measurements ??= bleService.getLastMeasurements();
      }

      // En collecte automatique (forceRead: false), ne pas afficher d'erreur si pas de données :
      // rester en "En attente" ; les données s'afficheront dès réception (callback).
      final String? errorMsg = measurements != null
          ? null
          : (forceRead
              ? (state.error ??
                  'Aucune donnée reçue. Le pansement envoie les données automatiquement ; gardez l\'app ouverte et rapprochez le capteur.')
              : null);
      // Ne jamais marquer "déconnecté" ici : seul le callback _handleConnectionStateChanged
      // doit mettre isConnected à false. Sinon un ancien message d'erreur ou l'absence de
      // données fait afficher "déconnecté" alors que le BLE est encore connecté.
      _safeSetState(state.copyWith(
        isReading: false,
        measurements: measurements,
        error: errorMsg,
        isConnected: state.isConnected,
      ));
    } catch (e) {
      if (_isDisposed) return;
      final msg = e.toString().toLowerCase();
      final friendly = msg.contains('caractéristique') ||
              msg.contains('non initialisée') ||
              msg.contains('disconnected') ||
              msg.contains('device is disconnected') ||
              msg.contains('gatt') ||
              msg.contains('aucune donnée') ||
              msg.contains('exception')
          ? 'Connexion perdue ou capteur non prêt. Rapprochez le pansement et réessayez.'
          : e.toString();
      _safeSetState(state.copyWith(isReading: false, error: friendly));
    }
  }

  /// Efface le message d'erreur affiché (ex. avant de réessayer la connexion).
  void clearError() {
    if (_isDisposed) return;
    _safeSetState(state.copyWith(error: null));
  }

  /// Réessaie d'activer les notifications BLE (utile après un timeout au premier essai).
  Future<void> retryNotifications() async {
    if (_isDisposed) return;
    final ok = await bleService.retryEnableNotifications();
    if (_isDisposed) return;
    if (ok) {
      _safeSetState(state.copyWith(error: null));
    }
  }

  /// Déconnecte du device
  Future<void> disconnect() async {
    if (_isDisposed) return;

    try {
      await bleService.disconnectDevice(device);
      if (!_isDisposed) {
        state = DeviceConnectionState();
      }
    } catch (e) {
      debugPrint("❌ Erreur déconnexion: $e");
    }
  }

  /// Callback quand des données sont reçues (notifications BLE)
  void _handleDataReceived(Map<String, dynamic> data) {
    if (_isDisposed) return;

    debugPrint("📊 DATA RECUE: $data");

    // Stocker directement chaque point Bode dans sweepPoints (état du provider)
    final newSweepPoints = List<Map<String, dynamic>>.from(state.sweepPoints);
    if (data.containsKey('freq') && data.containsKey('impedance')) {
      newSweepPoints.add(data);
      debugPrint("📈 SWEEPPOINT AJOUTÉ → total: ${newSweepPoints.length}");
    }

    _safeSetState(state.copyWith(
      measurements: data,
      sweepPoints: newSweepPoints,
      error: null,
    ));
  }

  /// Callback en cas d'erreur
  void _handleError(String error) {
    if (_isDisposed) return;
    _safeSetState(state.copyWith(error: error));
  }

  /// Callback quand l'état de connexion change
  void _handleConnectionStateChanged(BluetoothConnectionState connectionState) {
    if (_isDisposed) return;
    final isConnected = connectionState == BluetoothConnectionState.connected;
    _safeSetState(state.copyWith(
      isConnecting: isConnected ? false : state.isConnecting,
      isConnected: isConnected,
      measurements: isConnected ? state.measurements : null,
      sweepPoints: isConnected ? state.sweepPoints : [],
    ));
  }

  @override
  void dispose() {
    _isDisposed = true;
    disconnect();
    // Nettoyer les callbacks
    bleService.onDataReceived = null;
    bleService.onError = null;
    bleService.onConnectionStateChanged = null;
    super.dispose();
  }
}
