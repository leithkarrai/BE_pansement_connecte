import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/measurement.dart';

// ============================================================================
// Références impédance peau saine (fixes)
// ============================================================================
const double _zSaineBasse = 1200.0; // 10 Hz - 10 kHz
const double _zSaineMoyenne = 800.0; // 10 kHz - 100 kHz
const double _zSaineHaute = 500.0; // 100 kHz - 1 MHz

const double _fMinBasse = 10.0;
const double _fMaxBasse = 10000.0;
const double _fMaxMoyenne = 100000.0;
const double _fMaxHaute = 1000000.0;

/// Résultat du calcul d'état de la plaie (partagé patient / médecin).
class WoundStatusResult {
  final String label;
  final String message;
  final Color color;
  final IconData icon;
  final String emoji;
  final DateTime? lastUpdate;
  /// low / mid / high (+ mean = moyenne des R utilisée pour l'état global)
  final Map<String, double?>? bandRatios;

  WoundStatusResult({
    required this.label,
    required this.message,
    required this.color,
    required this.icon,
    required this.emoji,
    this.lastUpdate,
    this.bandRatios,
  });
}

/// Point d'historique pour le graphique état vs temps.
class StatusPoint {
  final DateTime date;
  final int statusValue;

  StatusPoint({required this.date, required this.statusValue});
}

enum _BandState {
  healthy,
  wound,
  infected,
}

/// Classe un ratio R = Zplaie / Zsaine (ou la moyenne de plusieurs R) selon les seuils.
_BandState _classifyRatio(double ratio) {
  // Plaie infectée d'abord (seuil plus sévère), puis plaie.
  if (ratio > 1.20 || ratio < 0.80) return _BandState.infected;
  if (ratio > 1.10 || ratio < 0.90) return _BandState.wound;
  return _BandState.healthy;
}

double? _mean(List<double> values) {
  if (values.isEmpty) return null;
  return values.reduce((a, b) => a + b) / values.length;
}

WoundStatusResult? _calculateFromImpedance(List<Measurement> measurements) {
  final impedance = measurements.where(
    (m) =>
        m.measurementType == 'impedance' &&
        m.freqHz != null &&
        m.value.isFinite &&
        m.freqHz!.isFinite,
  );

  final low = <double>[];
  final mid = <double>[];
  final high = <double>[];
  DateTime? lastUpdate;

  for (final m in impedance) {
    final f = m.freqHz!;
    if (f < _fMinBasse || f > _fMaxHaute) continue;

    if (lastUpdate == null || m.timestamp.isAfter(lastUpdate)) {
      lastUpdate = m.timestamp;
    }

    if (f < _fMaxBasse) {
      low.add(m.value);
    } else if (f < _fMaxMoyenne) {
      mid.add(m.value);
    } else {
      high.add(m.value);
    }
  }

  if (low.isEmpty && mid.isEmpty && high.isEmpty) {
    return null;
  }

  final lowMean = _mean(low);
  final midMean = _mean(mid);
  final highMean = _mean(high);

  final lowRatio = lowMean != null ? lowMean / _zSaineBasse : null;
  final midRatio = midMean != null ? midMean / _zSaineMoyenne : null;
  final highRatio = highMean != null ? highMean / _zSaineHaute : null;

  // Agrégation globale : moyenne des R sur les bandes où l'on a des mesures,
  // puis un seul classement par intervalles (même seuils que par bande).
  final ratiosForMean = <double>[
    if (lowRatio != null) lowRatio,
    if (midRatio != null) midRatio,
    if (highRatio != null) highRatio,
  ];
  if (ratiosForMean.isEmpty) {
    return null;
  }
  final meanR =
      ratiosForMean.reduce((a, b) => a + b) / ratiosForMean.length;
  final globalState = _classifyRatio(meanR);

  final bandRatios = <String, double?>{
    'low': lowRatio,
    'mid': midRatio,
    'high': highRatio,
    'mean': meanR,
  };

  switch (globalState) {
    case _BandState.infected:
      return WoundStatusResult(
        label: 'Critique',
        message:
            'Risque d\'infection détecté. Consultez rapidement un médecin.',
        color: Colors.red,
        icon: Icons.warning,
        emoji: '🚨',
        lastUpdate: lastUpdate,
        bandRatios: bandRatios,
      );
    case _BandState.wound:
      return WoundStatusResult(
        label: 'À surveiller',
        message:
            'Anomalie de plaie détectée. Surveillance recommandée.',
        color: Colors.orange,
        icon: Icons.info_outline,
        emoji: '👀',
        lastUpdate: lastUpdate,
        bandRatios: bandRatios,
      );
    case _BandState.healthy:
      return WoundStatusResult(
        label: 'Bon',
        message: 'Impédance dans la plage attendue de peau saine.',
        color: Colors.green,
        icon: Icons.check_circle,
        emoji: '✅',
        lastUpdate: lastUpdate,
        bandRatios: bandRatios,
      );
  }
}

/// Calcule l'état global de la plaie à partir des mesures.
WoundStatusResult calculateWoundStatus(List<Measurement> measurements) {
  if (measurements.isEmpty) {
    return WoundStatusResult(
      label: 'Aucune donnée',
      message: 'Aucune mesure disponible pour le moment',
      color: Colors.grey,
      icon: Icons.help_outline,
      emoji: '❓',
      lastUpdate: null,
    );
  }

  // 1) Priorité au calcul impédance (balayage fréquentiel).
  final impedanceBased = _calculateFromImpedance(measurements);
  if (impedanceBased != null) {
    return impedanceBased;
  }

  /*
  // 2) Fallback historique si aucune mesure d'impédance exploitable.
  // Désactivé volontairement: la classification se fait désormais uniquement
  // à partir des mesures d'impédance.
  */
  return WoundStatusResult(
    label: 'Aucune donnée',
    message: 'Aucune mesure d\'impédance exploitable pour calculer l\'état.',
    color: Colors.grey,
    icon: Icons.help_outline,
    emoji: '❓',
    lastUpdate: null,
  );
}

/// Étiquette courte pour affichage patient ("État normal" pour Bon).
String getWoundStatusDisplayLabel(WoundStatusResult status) {
  if (status.label == 'Bon' || status.label == 'Excellent') {
    return 'État normal';
  }
  return status.label;
}

/// Calcule l'état de la plaie à partir des mesures BLE (Map après un scan).
WoundStatusResult calculateWoundStatusFromMap(Map<String, dynamic> measurements) {
  final timestamp = measurements['timestamp'] != null
      ? DateTime.tryParse(measurements['timestamp'].toString()) ?? DateTime.now()
      : DateTime.now();
  final List<Measurement> list = [];
  for (final key in ['temperature', 'humidity', 'ph']) {
    final v = measurements[key];
    if (v != null && v is num) {
      list.add(Measurement(
        id: '',
        deviceId: '',
        measurementType: key,
        value: v is int ? v.toDouble() : v as double,
        unit: '',
        timestamp: timestamp,
      ));
    }
  }
  if (list.isEmpty) {
    return WoundStatusResult(
      label: 'Aucune donnée',
      message: 'Aucune mesure disponible pour le moment',
      color: Colors.grey,
      icon: Icons.help_outline,
      emoji: '❓',
      lastUpdate: null,
    );
  }
  return calculateWoundStatus(list);
}

/// Construit l'historique des états pour le graphique (par jour).
List<StatusPoint> buildStatusHistory(List<Measurement> measurements) {
  if (measurements.isEmpty) return [];

  final Map<String, List<Measurement>> byDay = {};
  for (var m in measurements) {
    final dayKey = DateFormat('yyyy-MM-dd').format(m.timestamp);
    byDay.putIfAbsent(dayKey, () => []).add(m);
  }

  final List<StatusPoint> history = [];
  final sortedDays = byDay.keys.toList()..sort();

  for (var dayKey in sortedDays) {
    final dayMeasurements = byDay[dayKey]!;
    final status = calculateWoundStatus(dayMeasurements);
    history.add(StatusPoint(
      date: DateTime.parse(dayKey),
      statusValue: getStatusValue(status.label),
    ));
  }

  return history;
}

/// Construit l'historique des états par session de mesure (scan à scan).
///
/// Une nouvelle session commence quand l'écart temporel entre 2 mesures
/// consécutives dépasse [maxGapSeconds].
List<StatusPoint> buildStatusHistoryBySession(
  List<Measurement> measurements, {
  int maxGapSeconds = 120,
}) {
  if (measurements.isEmpty) return [];

  final sorted = [...measurements]
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

  final sessions = <List<Measurement>>[];
  var current = <Measurement>[sorted.first];

  for (var i = 1; i < sorted.length; i++) {
    final prev = sorted[i - 1];
    final cur = sorted[i];
    final gapSeconds = cur.timestamp.difference(prev.timestamp).inSeconds.abs();

    if (gapSeconds <= maxGapSeconds) {
      current.add(cur);
    } else {
      sessions.add(current);
      current = <Measurement>[cur];
    }
  }

  sessions.add(current);

  final history = <StatusPoint>[];
  for (final sessionMeasurements in sessions) {
    final status = calculateWoundStatus(sessionMeasurements);
    history.add(
      StatusPoint(
        date: sessionMeasurements.last.timestamp,
        statusValue: getStatusValue(status.label),
      ),
    );
  }

  return history;
}

int getStatusValue(String label) {
  switch (label) {
    case 'Critique':
      return 0;
    case 'À surveiller':
      return 1;
    case 'Bon':
      return 2;
    case 'Excellent':
      return 2;
    default:
      return 1;
  }
}

String getStatusLabel(int value) {
  switch (value) {
    case 0:
      return 'Critique';
    case 1:
      return 'Surveiller';
    case 2:
      return 'Bon';
    case 3:
      return 'Bon';
    default:
      return '';
  }
}

/// Emoji associé à l'état (pour l'affichage patient).
String getStatusEmoji(int value) {
  switch (value) {
    case 0:
      return '🚨';
    case 1:
      return '👀';
    case 2:
      return '✅';
    case 3:
      return '✅';
    default:
      return '';
  }
}
