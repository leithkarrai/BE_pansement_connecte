import 'dart:async';
import 'package:flutter/foundation.dart';
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
        try {
          state =
              state.copyWith(isScanning: false, error: 'Bluetooth désactivé');
        } catch (e) {
          // Ignorer les erreurs si le widget est désactivé
          if (!_isDisposed) {
            debugPrint("⚠️ Erreur mise à jour état (adapterState): $e");
          }
        }
        _scanSubscription?.cancel();
      }
    });
  }

  /// Démarre le scan des devices BLE
  Future<void> startScan() async {
    if (_isDisposed) return;

    try {
      // Vérifier si le Bluetooth est disponible
      if (!await _bleService.isBluetoothAvailable()) {
        state = state.copyWith(
          error: "Bluetooth non disponible. Veuillez l'activer.",
          isScanning: false,
        );
        return;
      }

      // Nettoyer le scan précédent
      await stopScan();

      state = state.copyWith(isScanning: true, error: null, devices: []);

      debugPrint("🔍 Démarrage du scan BLE...");

      // Démarrer le scan
      await _bleService.startScan();

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

          // TEMPORAIRE: Afficher TOUS les devices pour diagnostic
          // TODO: Remettre le filtre une fois le device Zephyr identifié
          final filteredResults = results.where((result) {
            final name = result.device.platformName.toLowerCase();

            // Vérifier par nom
            if (name.contains('pansement') || name.contains('pans')) {
              debugPrint(
                "✅ Device trouvé par nom: ${result.device.remoteId}",
              );
              return true;
            }

            // Vérifier par UUID de service dans les données d'advertising
            if (result.advertisementData.serviceUuids.isNotEmpty) {
              final hasOurService = result.advertisementData.serviceUuids.any(
                (uuid) =>
                    uuid.toString().toLowerCase() ==
                    '75c276c3-8f97-20bc-a143-b354244886d4',
              );
              if (hasOurService) {
                debugPrint(
                  "✅ Device trouvé par UUID de service: ${result.device.remoteId}",
                );
                return true;
              }
            }

            // TEMPORAIRE: Afficher TOUS les devices pour diagnostic
            // Cela permet de voir tous les devices BLE et d'identifier le device Zephyr
            debugPrint(
              "🔍 Device affiché pour diagnostic: ${result.device.remoteId} (${name.isEmpty ? 'Sans nom' : name})",
            );
            return true; // Afficher tous les devices temporairement
          }).toList();

          // Éviter les doublons en utilisant un Set basé sur l'adresse MAC
          final uniqueDevices = <String, ScanResult>{};
          for (var result in filteredResults) {
            uniqueDevices[result.device.remoteId.toString()] = result;
          }

          // Vérifier à nouveau avant de mettre à jour l'état
          if (_isDisposed) return;

          try {
            state = state.copyWith(devices: uniqueDevices.values.toList());
          } catch (e) {
            // Ignorer les erreurs si le widget est désactivé
            if (!_isDisposed) {
              debugPrint("⚠️ Erreur mise à jour état scan: $e");
            }
            return;
          }

          if (uniqueDevices.isNotEmpty) {
            debugPrint("📡 ${uniqueDevices.length} pansement(s) détecté(s)");
          } else if (results.isNotEmpty) {
            debugPrint(
              "⚠️ Aucun device 'Pansement' trouvé parmi ${results.length} device(s)",
            );
          }
        },
        onError: (error) {
          if (_isDisposed) return;
          debugPrint("❌ Erreur scan: $error");
          try {
            state = state.copyWith(isScanning: false, error: error.toString());
          } catch (e) {
            // Ignorer les erreurs si le widget est désactivé
            if (!_isDisposed) {
              debugPrint("⚠️ Erreur mise à jour état scan (onError): $e");
            }
          }
        },
      );
    } catch (e) {
      if (_isDisposed) return;
      debugPrint("❌ Erreur démarrage scan: $e");
      try {
        state = state.copyWith(isScanning: false, error: e.toString());
      } catch (stateError) {
        // Ignorer les erreurs si le widget est désactivé
        if (!_isDisposed) {
          debugPrint("⚠️ Erreur mise à jour état scan (catch): $stateError");
        }
      }
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

      if (!_isDisposed) {
        state = state.copyWith(isScanning: false);
      }
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
  final String? error;

  DeviceConnectionState({
    this.isConnecting = false,
    this.isConnected = false,
    this.isReading = false,
    this.measurements,
    this.error,
  });

  DeviceConnectionState copyWith({
    bool? isConnecting,
    bool? isConnected,
    bool? isReading,
    Map<String, dynamic>? measurements,
    String? error,
  }) {
    return DeviceConnectionState(
      isConnecting: isConnecting ?? this.isConnecting,
      isConnected: isConnected ?? this.isConnected,
      isReading: isReading ?? this.isReading,
      measurements: measurements ?? this.measurements,
      error: error,
    );
  }
}

class DeviceConnectionNotifier extends StateNotifier<DeviceConnectionState> {
  final BluetoothDevice device;
  final BleService bleService;
  bool _isDisposed = false;

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

  /// Connecte au device
  Future<void> connect() async {
    if (_isDisposed) return;

    try {
      state = state.copyWith(isConnecting: true, error: null);
    } catch (e) {
      if (!_isDisposed) {
        debugPrint("⚠️ Erreur mise à jour état (connect init): $e");
      }
      return;
    }

    try {
      final success = await bleService.connectToDevice(device);

      if (!_isDisposed) {
        try {
          if (success) {
            state = state.copyWith(isConnecting: false, isConnected: true);
            // Lire automatiquement les mesures après connexion
            await readMeasurements();
          } else {
            state = state.copyWith(
              isConnecting: false,
              isConnected: false,
              error: "Échec de la connexion",
            );
          }
        } catch (e) {
          if (!_isDisposed) {
            debugPrint("⚠️ Erreur mise à jour état (connect success): $e");
          }
        }
      }
    } catch (e) {
      if (!_isDisposed) {
        try {
          state = state.copyWith(
            isConnecting: false,
            isConnected: false,
            error: e.toString(),
          );
        } catch (stateError) {
          debugPrint("⚠️ Erreur mise à jour état (connect error): $stateError");
        }
      }
    }
  }

  /// Lit les mesures manuellement
  Future<void> readMeasurements() async {
    if (_isDisposed || !state.isConnected) return;

    try {
      state = state.copyWith(isReading: true, error: null);
    } catch (e) {
      if (!_isDisposed) {
        debugPrint("⚠️ Erreur mise à jour état (readMeasurements init): $e");
      }
      return;
    }

    try {
      final measurements = await bleService.readMeasurements(device);

      if (!_isDisposed) {
        try {
          state = state.copyWith(isReading: false, measurements: measurements);
        } catch (e) {
          if (!_isDisposed) {
            debugPrint(
                "⚠️ Erreur mise à jour état (readMeasurements success): $e");
          }
        }
      }
    } catch (e) {
      if (!_isDisposed) {
        try {
          state = state.copyWith(isReading: false, error: e.toString());
        } catch (stateError) {
          debugPrint(
              "⚠️ Erreur mise à jour état (readMeasurements error): $stateError");
        }
      }
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

  /// Callback quand des données sont reçues
  void _handleDataReceived(Map<String, dynamic> data) {
    if (_isDisposed) return;
    try {
      state = state.copyWith(measurements: data);
    } catch (e) {
      // Ignorer les erreurs si le widget est désactivé
      if (!_isDisposed) {
        debugPrint("⚠️ Erreur mise à jour état (dataReceived): $e");
      }
    }
  }

  /// Callback en cas d'erreur
  void _handleError(String error) {
    if (_isDisposed) return;
    try {
      state = state.copyWith(error: error);
    } catch (e) {
      // Ignorer les erreurs si le widget est désactivé
      if (!_isDisposed) {
        debugPrint("⚠️ Erreur mise à jour état (error): $e");
      }
    }
  }

  /// Callback quand l'état de connexion change
  void _handleConnectionStateChanged(BluetoothConnectionState connectionState) {
    if (_isDisposed) return;

    final isConnected = connectionState == BluetoothConnectionState.connected;

    try {
      state = state.copyWith(
        isConnected: isConnected,
        // Si déconnecté, réinitialiser l'état
        measurements: isConnected ? state.measurements : null,
      );
    } catch (e) {
      // Ignorer les erreurs si le widget est désactivé
      if (!_isDisposed) {
        debugPrint("⚠️ Erreur mise à jour état (connectionStateChanged): $e");
      }
    }
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
