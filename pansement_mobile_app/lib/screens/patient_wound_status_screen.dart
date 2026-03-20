import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';
import '../providers/measurements_provider.dart';
import '../models/user.dart';
import '../models/measurement.dart';
import '../utils/wound_status_helper.dart';

/// État de la plaie (patient : "ma plaie" ; médecin : "plaie du patient").
class PatientWoundStatusScreen extends ConsumerStatefulWidget {
  final User patient;
  /// true quand un médecin consulte l'état de la plaie d'un patient (titre adapté).
  final bool forMedecin;

  const PatientWoundStatusScreen({
    super.key,
    required this.patient,
    this.forMedecin = false,
  });

  @override
  ConsumerState<PatientWoundStatusScreen> createState() =>
      _PatientWoundStatusScreenState();
}

class _PatientWoundStatusScreenState
    extends ConsumerState<PatientWoundStatusScreen> {
  String _selectedTimeRange = '7'; // 7 jours par défaut
  bool _didInvalidateOnOpen = false;
  List<Measurement>? _demoOverrideMeasurements; // Presentation only

  @override
  void initState() {
    super.initState();
    // Rafraîchir les mesures à l'ouverture (après collecte BLE, données à jour)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _didInvalidateOnOpen) return;
      _didInvalidateOnOpen = true;
      ref.invalidate(patientMeasurementsProvider(widget.patient.id));
    });
  }

  @override
  Widget build(BuildContext context) {
    final measurementsAsync = ref.watch(
      patientMeasurementsProvider(widget.patient.id),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.forMedecin
              ? 'État de la plaie - ${widget.patient.fullName}'
              : 'État de ma plaie',
        ),
        actions: [
          // Afficher la période actuelle pour confirmer que le filtre est appliqué
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Text(
                _selectedTimeRange == '7'
                    ? '7 j'
                    : _selectedTimeRange == '30'
                        ? '30 j'
                        : '90 j',
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).appBarTheme.foregroundColor?.withOpacity(0.9),
                ),
              ),
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.calendar_today),
            tooltip: 'Changer la période',
            onSelected: (value) {
              if (value != _selectedTimeRange) {
                setState(() {
                  _selectedTimeRange = value;
                });
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: '7',
                child: Row(
                  children: [
                    if (_selectedTimeRange == '7') Icon(Icons.check, size: 20, color: Theme.of(context).primaryColor),
                    if (_selectedTimeRange == '7') const SizedBox(width: 8),
                    const Text('7 derniers jours'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: '30',
                child: Row(
                  children: [
                    if (_selectedTimeRange == '30') Icon(Icons.check, size: 20, color: Theme.of(context).primaryColor),
                    if (_selectedTimeRange == '30') const SizedBox(width: 8),
                    const Text('30 derniers jours'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: '90',
                child: Row(
                  children: [
                    if (_selectedTimeRange == '90') Icon(Icons.check, size: 20, color: Theme.of(context).primaryColor),
                    if (_selectedTimeRange == '90') const SizedBox(width: 8),
                    const Text('90 derniers jours'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: measurementsAsync.when(
        data: (allMeasurements) {
          // Filtrer par période
          final now = DateTime.now();
          final days = int.parse(_selectedTimeRange);
          final cutoffDate = now.subtract(Duration(days: days));
          final filteredMeasurements = allMeasurements
              .where((m) => m.timestamp.isAfter(cutoffDate))
              .toList();

          final effectiveMeasurements =
              _demoOverrideMeasurements ?? filteredMeasurements;

          // Calcul local:
          // - état global synthétique,
          // - historique temporel pour les courbes.
          final woundStatus = calculateWoundStatus(effectiveMeasurements);
          final statusHistory = buildStatusHistory(effectiveMeasurements);

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(patientMeasurementsProvider(widget.patient.id));
              await ref.read(patientMeasurementsProvider(widget.patient.id).future);
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                // Vue médecin : on affiche uniquement l'état (carte) et pas les courbes.
                if (widget.forMedecin) ...[
                  // Rien à afficher ici: la carte d'état est en dehors de ce bloc.
                ],
                // Carte de résumé (message principal affiché à l'utilisateur).
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(24.0),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          woundStatus.color.withOpacity(0.2),
                          woundStatus.color.withOpacity(0.1),
                        ],
                      ),
                    ),
                    child: Column(
                      children: [
                        // Boutons de démo: uniquement côté patient (pour ne pas
                        // polluer l'UI médecin).
                        if (!widget.forMedecin && kDebugMode) ...[
                          Align(
                            alignment: Alignment.centerRight,
                            child: Wrap(
                              spacing: 8,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      _demoOverrideMeasurements =
                                          _buildDemoCriticalImpedanceMeasurements(
                                        now,
                                      );
                                    });
                                  },
                                  icon: const Icon(Icons.bug_report),
                                  label: const Text('Démo Critique'),
                                ),
                                ElevatedButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      _demoOverrideMeasurements =
                                          _buildDemoSurveillanceImpedanceMeasurements(
                                        now,
                                      );
                                    });
                                  },
                                  icon: const Icon(Icons.warning_amber_outlined),
                                  label: const Text('Démo À surveiller'),
                                ),
                                if (_demoOverrideMeasurements != null)
                                  OutlinedButton.icon(
                                    onPressed: () {
                                      setState(() {
                                        _demoOverrideMeasurements = null;
                                      });
                                    },
                                    icon: const Icon(Icons.close),
                                    label: const Text('Annuler'),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        Icon(
                          woundStatus.icon,
                          size: 64,
                          color: woundStatus.color,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '${woundStatus.label} ${woundStatus.emoji}',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: woundStatus.color,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          (widget.forMedecin &&
                                  woundStatus.label == 'Critique' &&
                                  woundStatus.message.contains(
                                    'Consultez rapidement un médecin',
                                  ))
                              ? woundStatus.message
                                  .replaceAll(
                                    'Consultez rapidement un médecin.',
                                    '',
                                  )
                                  .trim()
                              : woundStatus.message,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey[700],
                            fontSize: 14,
                          ),
                        ),
                        if (woundStatus.lastUpdate != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            'Dernière mise à jour: ${DateFormat('dd/MM/yyyy à HH:mm').format(woundStatus.lastUpdate!)}',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // Graphique d'évolution (affiché aussi pour le médecin)
                ...[
                  const SizedBox(height: 32),
                  Text(
                    'Évolution de l\'état',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Courbe jour par jour (🚨 Critique, 👀 Surveiller, ✅ Bon, 🌟 Excellent)',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (statusHistory.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(
                                Icons.timeline,
                                size: 48,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                allMeasurements.isEmpty
                                    ? 'Aucune mesure disponible pour le moment'
                                    : 'Aucune donnée sur la période sélectionnée',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 16,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              if (allMeasurements.isEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Les mesures apparaîtront ici une fois que votre pansement sera connecté et actif.',
                                  style: TextStyle(
                                    color: Colors.grey[500],
                                    fontSize: 12,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    _buildStatusChart(context, statusHistory),
                ],

                // Rappel si aucune donnée (tirer pour actualiser après envoi)
                if (woundStatus.label == 'Aucune donnée') ...[
                  const SizedBox(height: 16),
                  Text(
                    'Tirez pour actualiser après avoir envoyé des mesures depuis votre pansement.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                ],
              ),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                const SizedBox(height: 16),
                Text(
                  'Erreur de chargement',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  error.toString(),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () {
                    // Rafraîchir les données
                    ref.invalidate(
                        patientMeasurementsProvider(widget.patient.id));
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Génère des mesures factices d'impédance afin de forcer le statut
  /// global à repasser en état `Critique` (infecté) via le calcul fréquentiel.
  List<Measurement> _buildDemoCriticalImpedanceMeasurements(
    DateTime now,
  ) {
    // Les ratios sont calculés comme:
    // ratio = Zplaie / Zpeau_saine_fixe
    // Critique si ratio > 1.20 ou ratio < 0.80.
    return <Measurement>[
      Measurement(
        id: 'demo_low',
        deviceId: 'demo_device',
        measurementType: 'impedance',
        value: 1500.0,
        unit: 'ohm',
        freqHz: 1000.0, // low
        timestamp: now,
      ),
      Measurement(
        id: 'demo_mid',
        deviceId: 'demo_device',
        measurementType: 'impedance',
        value: 1000.0,
        unit: 'ohm',
        freqHz: 50000.0, // mid
        timestamp: now,
      ),
      Measurement(
        id: 'demo_high',
        deviceId: 'demo_device',
        measurementType: 'impedance',
        value: 650.0,
        unit: 'ohm',
        freqHz: 500000.0, // high
        timestamp: now,
      ),
    ];
  }

  /// Génère des mesures factices d'impédance afin de forcer le statut
  /// global à retourner `label == 'À surveiller'` (wound) mais pas `Critique`
  /// (infected), via le calcul fréquentiel.
  List<Measurement> _buildDemoSurveillanceImpedanceMeasurements(
    DateTime now,
  ) {
    // Critère 'infected' (Critique) :
    // - ratio > 1.20 ou ratio < 0.80
    //
    // Critère 'wound' (À surveiller) :
    // - ratio > 1.10 ou ratio < 0.90
    //
    // Donc on utilise ratio ~ 1.15 (wound mais pas infected).
    return <Measurement>[
      Measurement(
        id: 'demo2_low',
        deviceId: 'demo_device',
        measurementType: 'impedance',
        value: 1380.0, // 1200 * 1.15
        unit: 'ohm',
        freqHz: 1000.0, // low
        timestamp: now,
      ),
      Measurement(
        id: 'demo2_mid',
        deviceId: 'demo_device',
        measurementType: 'impedance',
        value: 920.0, // 800 * 1.15
        unit: 'ohm',
        freqHz: 50000.0, // mid
        timestamp: now,
      ),
      Measurement(
        id: 'demo2_high',
        deviceId: 'demo_device',
        measurementType: 'impedance',
        value: 575.0, // 500 * 1.15
        unit: 'ohm',
        freqHz: 500000.0, // high
        timestamp: now,
      ),
    ];
  }

  // ignore: unused_element
  Widget _buildSectionTitle(
    BuildContext context,
    String title,
    String subtitle,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  // ignore: unused_element
  Widget _buildTemperatureChart(
    BuildContext context,
    List<Measurement> tempMeasurements,
  ) {
    if (tempMeasurements.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Center(
            child: Column(
              children: [
                Icon(Icons.thermostat, size: 48, color: Colors.grey[400]),
                const SizedBox(height: 12),
                Text(
                  'Aucune mesure de température sur la période',
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }
    final spots = tempMeasurements
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.value))
        .toList();
    final values = tempMeasurements.map((m) => m.value).toList();
    final yMin = values.fold<double>(values.first, (a, b) => a < b ? a : b);
    final yMax = values.fold<double>(values.first, (a, b) => a > b ? a : b);
    final pad = 0.5;
    final minY = (yMin - pad).clamp(30.0, 45.0);
    final maxY = (yMax + pad).clamp(30.0, 45.0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SizedBox(
          height: 260,
          child: LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: true,
                getDrawingHorizontalLine: (value) =>
                    FlLine(color: Colors.grey.withOpacity(0.25), strokeWidth: 1),
              ),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 36,
                    interval: (maxY - minY) / 4,
                    getTitlesWidget: (value, meta) => Text(
                      '${value.toStringAsFixed(1)} °C',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[800],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 32,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= tempMeasurements.length) {
                        return const SizedBox.shrink();
                      }
                      return Text(
                        DateFormat('dd/MM HH:mm').format(tempMeasurements[i].timestamp),
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey[700],
                        ),
                      );
                    },
                  ),
                ),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(
                show: true,
                border: Border(
                  left: BorderSide(color: Colors.grey.withOpacity(0.4)),
                  bottom: BorderSide(color: Colors.grey.withOpacity(0.4)),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  color: Colors.orange,
                  barWidth: 2.5,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, percent, barData, index) =>
                        FlDotCirclePainter(
                      radius: 4,
                      color: Colors.orange,
                      strokeWidth: 1,
                      strokeColor: Colors.white,
                    ),
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    color: Colors.orange.withOpacity(0.15),
                  ),
                ),
              ],
              minY: minY,
              maxY: maxY,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChart(
    BuildContext context,
    List<StatusPoint> statusHistory,
  ) {
    if (statusHistory.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Center(
            child: Column(
              children: [
                Icon(Icons.timeline, size: 48, color: Colors.grey[400]),
                const SizedBox(height: 12),
                Text(
                  'Aucun historique d\'état sur la période',
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SizedBox(
          height: 260,
          child: LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: true,
                horizontalInterval: 1,
                getDrawingHorizontalLine: (value) =>
                    FlLine(color: Colors.grey.withOpacity(0.25), strokeWidth: 1),
              ),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 72,
                    interval: 1,
                    getTitlesWidget: (value, meta) {
                      final v = value.toInt();
                      if (v < 0 || v > 3) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: Text(
                          '${getStatusEmoji(v)} ${getStatusLabel(v)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[800],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 32,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index < 0 || index >= statusHistory.length) {
                        return const Text('');
                      }
                      return Text(
                        DateFormat('dd/MM').format(statusHistory[index].date),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[700],
                        ),
                      );
                    },
                  ),
                ),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(
                show: true,
                border: Border(
                  left: BorderSide(color: Colors.grey.withOpacity(0.4)),
                  bottom: BorderSide(color: Colors.grey.withOpacity(0.4)),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: statusHistory
                      .asMap()
                      .entries
                      .map((e) => FlSpot(
                            e.key.toDouble(),
                            e.value.statusValue.toDouble(),
                          ))
                      .toList(),
                  isCurved: true,
                  color: Theme.of(context).primaryColor,
                  barWidth: 4,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, percent, barData, index) =>
                        FlDotCirclePainter(
                      radius: 6,
                      color: Theme.of(context).primaryColor,
                      strokeWidth: 2,
                      strokeColor: Colors.white,
                    ),
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    color: Theme.of(context).primaryColor.withOpacity(0.2),
                  ),
                ),
              ],
              minY: 0,
              maxY: 3,
            ),
          ),
        ),
      ),
    );
  }
}
