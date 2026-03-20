import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:dio/dio.dart';
import '../providers/ble_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/measurements_provider.dart';
import '../services/navigation_service.dart';
import '../models/device.dart';

class DeviceConnectionScreen extends ConsumerStatefulWidget {
  final BluetoothDevice device;

  const DeviceConnectionScreen({
    super.key,
    required this.device,
  });

  @override
  ConsumerState<DeviceConnectionScreen> createState() =>
      _DeviceConnectionScreenState();
}

class _DeviceConnectionScreenState
    extends ConsumerState<DeviceConnectionScreen> {
  /// Affiche un SnackBar via NavigationService (sans BuildContext, évite "deactivated widget's ancestor").
  void _showSnack(String message, {Color? color}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        NavigationService().showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: color,
          ),
        );
      } catch (_) {}
    });
  }

  /// Affiche un message d'erreur de connexion compréhensible (ex. setNotifyValue / Device is disconnected).
  static String _connectionErrorMessage(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('setnotifyvalue') &&
        (lower.contains('disconnected') || lower.contains('fbp-code: 6'))) {
      return 'Le pansement s\'est déconnecté pendant la configuration. Rapprochez-le et appuyez sur « Réessayer la connexion ».';
    }
    if (lower.contains('disconnected') || lower.contains('déconnecté')) {
      return 'Le pansement s\'est déconnecté. Rapprochez l\'appareil et réessayez.';
    }
    if (raw.length > 120) {
      return 'Erreur de connexion au pansement. Rapprochez l\'appareil et réessayez.';
    }
    return raw;
  }

  /// Message de confirmation après clic sur "Envoyer les données au médecin".
  void _showSuccessMessage(int sentCount) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        NavigationService().showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Données envoyées avec succès',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$sentCount mesure${sentCount > 1 ? 's' : ''} transmise${sentCount > 1 ? 's' : ''} au médecin',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green.shade600,
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
          ),
          clearFirst: true,
        );
      } catch (_) {}
    });
  }

  @override
  void initState() {
    super.initState();
    // Délai pour laisser le stack BLE stable après arrêt du scan (évite "impossible de se connecter" sur Android)
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      ref.read(deviceConnectionProvider(widget.device).notifier).connect();
    });
  }

  @override
  void dispose() {
    ref.read(deviceConnectionProvider(widget.device).notifier).disconnect();
    super.dispose();
  }

  Future<void> _readMeasurements({bool forceRead = false}) async {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        NavigationService().showSnackBar(
          const SnackBar(
            content: Text('Collecte en cours...'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.blue,
          ),
        );
      } catch (_) {}
    });
    // Lecture locale BLE (sans envoi serveur).
    await ref
        .read(deviceConnectionProvider(widget.device).notifier)
        .readMeasurements(forceRead: forceRead);
    if (!mounted) return;
    final connectionState = ref.read(deviceConnectionProvider(widget.device));
    try {
      if (connectionState.measurements != null) {
        NavigationService().showSnackBar(
          const SnackBar(
            content: Text('Données collectées.'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (connectionState.error != null) {
        NavigationService().showSnackBar(
          SnackBar(
            content: Text(connectionState.error!),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (_) {}
  }

  /// Affiche une boîte de confirmation avant d'envoyer les données au médecin.
  Future<void> _confirmAndSendToServer() async {
    final connectionState = ref.read(deviceConnectionProvider(widget.device));
    final hasData = connectionState.measurements != null ||
        connectionState.sweepPoints.isNotEmpty;
    if (!hasData) {
      _showSnack('Aucune donnée à envoyer. Lancez d\'abord la collecte.',
          color: Colors.orange);
      return;
    }
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Envoyer les données ?'),
        content: const Text(
          'Voulez-vous envoyer les données collectées à votre médecin ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700]),
            child: const Text('Envoyer'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _sendToServer();
    }
  }

  /// Extrait le message d'erreur depuis une réponse Dio / FastAPI.
  String _errorMessage(dynamic e) {
    if (e is DioException) {
      final code = e.response?.statusCode;
      if (code == 401) return 'Session expirée. Déconnectez-vous puis reconnectez-vous.';
      if (code == 403) return 'Accès refusé. Seul un compte patient peut envoyer des données.';
      if (code == 404) return 'Serveur ou pansement introuvable. Vérifiez l\'URL dans Paramètres.';
      if (code == 422) return 'Données refusées par le serveur. Réessayez ou contactez le support.';
      if (e.type == DioExceptionType.connectionError || e.type == DioExceptionType.connectionTimeout) {
        return 'Impossible de joindre le serveur. Vérifiez le Wi‑Fi et l\'URL du serveur (Paramètres).';
      }
      if (e.response?.data is Map) {
        final d = e.response!.data as Map;
        final detail = d['detail'] ?? d['message'];
        if (detail != null) return detail.toString();
      }
    }
    final s = e.toString();
    return s.length > 100 ? 'Erreur lors de l\'envoi. Réessayez.' : s;
  }

  Future<void> _sendToServer() async {
    final connectionState = ref.read(deviceConnectionProvider(widget.device));
    final measurements = connectionState.measurements;
    final sweepPoints = connectionState.sweepPoints;

    final hasData = measurements != null || sweepPoints.isNotEmpty;
    if (!hasData) {
      _showSnack('Aucune donnée à envoyer. Lancez d\'abord la collecte.',
          color: Colors.orange);
      return;
    }

    if (!mounted) return;
    _showSnack('Envoi en cours...', color: Colors.blue);

    try {
      final apiService = ref.read(apiServiceProvider);
      final currentUser = ref.read(authProvider).user;

      if (currentUser == null) {
        _showSnack('Vous devez être connecté pour envoyer les données.', color: Colors.red);
        return;
      }

      await apiService.ensureBaseUrlLoaded();
      if (!mounted) return;

      // 1) Enregistrer/récupérer le device côté backend via son identifiant BLE.
      final macAddress = widget.device.remoteId.toString();
      Device device;
      try {
        device = await apiService.registerDeviceByMac(macAddress);
      } catch (e) {
        if (!mounted) return;
        final msg = _errorMessage(e);
        _showSnack('❌ Enregistrement : $msg', color: Colors.red);
        _showErrorDialog('Enregistrement du pansement', msg, e);
        return;
      }
      if (!mounted) return;

      // 2) Vérifier le contexte patient (seul patient autorisé à pousser ses mesures).
      final deviceId = device.id;
      final patientId = currentUser.role == 'patient' ? currentUser.id : null;
      if (patientId == null || patientId.isEmpty) {
        _showSnack(
          'Seul un compte patient peut envoyer des données au médecin.',
          color: Colors.orange,
        );
        return;
      }

      // 3) Lier device <-> patient pour rendre visibles mesures et alertes dans les écrans.
      try {
        if (currentUser.role == 'patient') {
          await apiService.assignMyDevice(deviceId);
        } else {
          await apiService.assignDeviceToPatient(deviceId, patientId);
        }
      } catch (e) {
        if (!mounted) return;
        final msg = _errorMessage(e);
        _showSnack('❌ Liaison au patient : $msg', color: Colors.red);
        _showErrorDialog('Liaison au patient', msg, e);
        return;
      }
      if (!mounted) return;

      final knownNumeric = <String, String>{
        's1': '',
        's2': '',
        's3': '',
        'temperature': '°C',
        'adc_raw': '',
        'adc_val': '',
        'impedance': 'Ω',
        'phase': '°',
        'freq': 'Hz',
      };
      const allowedTypes = {
        'adc', 's1', 's2', 's3', 'temperature', 'impedance',
      };
      int sentCount = 0;

      // 4) Envoi des mesures:
      // - priorité aux points de sweep (impedance + freq/phase),
      // - sinon fallback sur mesures numériques classiques.
      if (sweepPoints.isNotEmpty) {
        for (final point in sweepPoints) {
          final imp = point['impedance'];
          final freq = point['freq'];
          final phase = point['phase'];
          if (imp is! num) continue;
          await apiService.createMeasurement(
            deviceId: deviceId,
            measurementType: 'impedance',
            value: (imp is int) ? imp.toDouble() : imp as double,
            unit: 'Ω',
            qualityScore: 95,
            patientId: patientId,
            freqHz: freq is num ? freq.toDouble() : null,
            phaseDeg: phase is num ? phase.toDouble() : null,
          );
          sentCount++;
          if (!mounted) return;
        }
      } else if (measurements != null) {
        for (final entry in measurements.entries) {
          final key = entry.key;
          if (key == 'timestamp' || key == 'status') continue;
          final v = entry.value;
          if (v is! num) continue;

          final value = (v is int) ? v.toDouble() : v as double;
          String measurementType = key;
          String unit = '';

          if (key == 'adc_raw' || key == 'adc_val') {
            measurementType = 'adc';
          } else if (knownNumeric.containsKey(key)) {
            unit = knownNumeric[key] ?? '';
          }
          if (!allowedTypes.contains(measurementType)) continue;

          await apiService.createMeasurement(
            deviceId: deviceId,
            measurementType: measurementType,
            value: value,
            unit: unit,
            qualityScore: 95,
            patientId: patientId,
          );
          sentCount++;
          if (!mounted) return;
        }
      }

      // 5) Retour utilisateur.
      if (sentCount == 0) {
        _showSnack(
          'Aucune mesure numérique à envoyer. Vérifiez que le capteur envoie des données.',
          color: Colors.orange,
        );
        return;
      }

      if (!mounted) return;
      ref.read(deviceConnectionProvider(widget.device).notifier).clearError();
      _showSuccessMessage(sentCount);
      // Rafraîchir les mesures via post-frame pour éviter "deactivated widget's ancestor"
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 500), () {
          try {
            if (!mounted) return;
            ref.invalidate(patientMeasurementsProvider(patientId));
          } catch (_) {}
        });
      });
    } on DioException catch (e) {
      if (!mounted) return;
      final msg = _errorMessage(e);
      _showSnack('❌ Envoi des mesures : $msg', color: Colors.red);
      _showErrorDialog('Envoi des mesures', msg, e);
    } catch (e) {
      if (!mounted) return;
      final msg = _errorMessage(e);
      _showSnack('❌ $msg', color: Colors.red);
      _showErrorDialog('Erreur envoi', msg, e);
    }
  }

  /// Affiche une boîte de dialogue avec le détail de l'erreur (pour diagnostic).
  void _showErrorDialog(String title, String message, Object? error) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('$title – détail'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(message, style: const TextStyle(fontSize: 14)),
                  if (error != null && error.toString().length > 3) ...[
                    const SizedBox(height: 12),
                    Text(
                      error.toString(),
                      style: TextStyle(fontSize: 12, color: Colors.grey[700], fontFamily: 'monospace'),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final connectionState = ref.watch(deviceConnectionProvider(widget.device));
    final currentUser = ref.watch(authProvider).user;
    final isPatient = currentUser?.role == 'patient';
    final deviceName = widget.device.platformName.isNotEmpty
        ? widget.device.platformName
        : 'Pansement connecté';

    return Scaffold(
      appBar: AppBar(
        title: Text(deviceName),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Carte statut connexion (vert = connecté, orange = en cours / déconnecté)
            Card(
              color: connectionState.isConnected
                  ? Colors.green[50]
                  : Colors.orange[50],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Row(
                  children: [
                    if (connectionState.isConnecting)
                      SizedBox(
                        width: 48,
                        height: 48,
                        child: CircularProgressIndicator(
                          color: Colors.orange[700],
                          strokeWidth: 3,
                        ),
                      )
                    else
                      Icon(
                        connectionState.isConnected
                            ? Icons.check_circle
                            : Icons.sync,
                        color: connectionState.isConnected
                            ? Colors.green[700]
                            : Colors.orange[700],
                        size: 48,
                      ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            connectionState.isConnecting
                                ? 'Connexion en cours...'
                                : connectionState.isConnected
                                    ? 'Connecté'
                                    : 'Déconnecté',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'ID: ${widget.device.remoteId}',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[800],
                            ),
                          ),
                          if (connectionState.isConnecting)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                'Cela peut prendre jusqu\'à 30 secondes.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.orange[800],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Erreur + bouton Réessayer (masqué pour le patient)
            if (connectionState.error != null && !isPatient)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.error_outline, color: Colors.red[700]),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _connectionErrorMessage(connectionState.error!),
                            style: TextStyle(color: Colors.red[900]),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (connectionState.isConnected)
                          TextButton.icon(
                            onPressed: () async {
                              final notifier = ref.read(
                                  deviceConnectionProvider(widget.device)
                                      .notifier);
                              await notifier.retryNotifications();
                            },
                            icon: const Icon(Icons.bluetooth_searching,
                                size: 20),
                            label: const Text('Réactiver la réception'),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.orange[800],
                            ),
                          ),
                        TextButton.icon(
                          onPressed: () {
                            ref
                                .read(deviceConnectionProvider(widget.device)
                                    .notifier)
                                .connect();
                            ref
                                .read(deviceConnectionProvider(widget.device)
                                    .notifier)
                                .clearError();
                          },
                          icon: const Icon(Icons.refresh, size: 20),
                          label: const Text('Réessayer la connexion'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.red[700],
                          ),
                        ),
                      ],
                    ),
                    if (connectionState.isConnected) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Si besoin : « Réactiver la réception » puis réattendre plus bas.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red[800],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

            // Carte données collectées / envoi médecin (patient, visible uniquement quand il y a des données)
            if (connectionState.isConnected &&
                isPatient &&
                (connectionState.measurements != null ||
                    connectionState.sweepPoints.isNotEmpty)) ...[
              const SizedBox(height: 24),
              Card(
                color: Colors.green[50],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(
                        Icons.check_circle,
                        size: 48,
                        color: Colors.green[700],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Données collectées',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.green[800],
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Vous pouvez envoyer ces données à votre médecin.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.green[800],
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _confirmAndSendToServer,
                          icon: const Icon(Icons.medical_services, size: 22),
                          label: const Text('Envoyer les données au médecin'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 16,
                            ),
                            backgroundColor: Colors.green[700],
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            // Admin / Médecin : données collectées (affichage brut), pas de bouton d'envoi
            if (connectionState.measurements != null && !isPatient) ...[
              Card(
                color: Colors.blue[50],
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(Icons.sensors, size: 48, color: Colors.blue[700]),
                      const SizedBox(height: 16),
                      Text(
                        'Données lues',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue[800],
                            ),
                      ),
                      const SizedBox(height: 12),
                      _MeasurementsList(
                          measurements: connectionState.measurements!),
                      const SizedBox(height: 12),
                      Text(
                        'Seul le patient peut envoyer ces données à son médecin depuis cet écran.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey[700], fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            // Tant que pas de données : bouton pour relancer la collecte (patient ou admin/médecin)
            if (connectionState.isConnected &&
                connectionState.measurements == null &&
                connectionState.sweepPoints.isEmpty) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: connectionState.isReading ? null : _readMeasurements,
                icon: connectionState.isReading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.sensors),
                label: Text(
                  connectionState.isReading
                      ? 'Réception en cours...'
                      : 'Réattendre les données (25 s)',
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Affiche la liste des mesures pour que le patient (et admin/médecin) voie les valeurs avant envoi.
class _MeasurementsList extends StatelessWidget {
  const _MeasurementsList({required this.measurements});

  final Map<String, dynamic> measurements;

  static const Map<String, String> _labels = {
    'temperature': 'Température',
    'adc_val': 'Valeur capteur (ADC)',
    'adc_raw': 'Valeur brute (ADC)',
    'impedance': 'Impédance',
    'phase': 'Phase',
    'freq': 'Fréquence',
    's1': 'Capteur 1',
    's2': 'Capteur 2',
    's3': 'Capteur 3',
    'status': 'Statut',
    'timestamp': 'Date / heure',
  };

  static const Map<String, String> _units = {
    'temperature': '°C',
    'impedance': ' Ω',
    'phase': '°',
    'freq': ' Hz',
  };

  @override
  Widget build(BuildContext context) {
    final entries = measurements.entries
        .where((e) => e.key != 'timestamp' || _labels.containsKey(e.key))
        .toList();
    if (entries.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mesures',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          ...entries.map((e) {
            final key = e.key;
            final label = _labels[key] ?? key;
            final unit = _units[key] ?? '';
            final v = e.value;
            final str = v is num
                ? '${v is int ? v : (v as double).toStringAsFixed(2)}$unit'
                : '$v';
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(label,
                      style: TextStyle(color: Colors.grey[700], fontSize: 14)),
                  Text(str,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
