import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../services/ble_service.dart';

// Provider du service BLE
final bleServiceProvider = Provider<BleService>((ref) {
  return BleService();
});

// État du scan
class BleScanState {
  final bool isScanning;
  final List<ScanResult> devices;
  final String? error;

  BleScanState({
    this.isScanning = false,
    this.devices = const [],
    this.error,
  });

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

// Notifier pour gérer le scan
class BleScanNotifier extends StateNotifier<BleScanState> {
  final BleService _bleService;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;
  bool _isDisposed = false;

  BleScanNotifier(this._bleService) : super(BleScanState()) {
    // Écouter les changements d'état Bluetooth
    _adapterStateSubscription = FlutterBluePlus.adapterState.listen((adapterState) {
      if (_isDisposed) return;
      if (adapterState == BluetoothAdapterState.off) {
        state = state.copyWith(
          isScanning: false,
          error: 'Bluetooth désactivé',
        );
        _scanSubscription?.cancel();
      }
    });
  }

  // Démarrer le scan
  Future<void> startScan() async {
    if (_isDisposed) return;
    
    state = state.copyWith(isScanning: true, error: null);

    try {
      await _bleService.startScan();

      // Écouter les résultats
      _scanSubscription?.cancel(); // Annuler l'ancien si existe
      _scanSubscription = _bleService.scanDevices().listen(
        (results) {
          if (!_isDisposed) {
            state = state.copyWith(devices: results);
          }
        },
        onError: (error) {
          if (!_isDisposed) {
            state = state.copyWith(
              isScanning: false,
              error: error.toString(),
            );
          }
        },
      );
    } catch (e) {
      if (!_isDisposed) {
        state = state.copyWith(
          isScanning: false,
          error: e.toString(),
        );
      }
    }
  }

  // Arrêter le scan
  Future<void> stopScan() async {
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    await _bleService.stopScan();
    if (!_isDisposed) {
      state = state.copyWith(isScanning: false);
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _scanSubscription?.cancel();
    _adapterStateSubscription?.cancel();
    super.dispose();
  }
}

// Provider du scan
final bleScanProvider =
    StateNotifierProvider<BleScanNotifier, BleScanState>((ref) {
  final bleService = ref.watch(bleServiceProvider);
  return BleScanNotifier(bleService);
});
