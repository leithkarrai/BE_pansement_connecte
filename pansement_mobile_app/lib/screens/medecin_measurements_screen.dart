import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../providers/measurements_provider.dart';
import '../models/user.dart';
import '../models/measurement.dart';

/// Écran pour le médecin : graphique Bode (impédance vs fréquence) + tableau des mesures.
class MedecinMeasurementsScreen extends ConsumerStatefulWidget {
  final User patient;

  const MedecinMeasurementsScreen({
    super.key,
    required this.patient,
  });

  @override
  ConsumerState<MedecinMeasurementsScreen> createState() =>
      _MedecinMeasurementsScreenState();
}

/// Délai au-delà duquel on considère une nouvelle "session" d'envoi (balayage Bode).
const _sessionGapMinutes = 2;

class _MedecinMeasurementsScreenState
    extends ConsumerState<MedecinMeasurementsScreen> {
  String _selectedTimeRange = '7'; // 7 jours par défaut
  int _selectedSessionIndex = 0; // 0 = dernières valeurs envoyées

  Widget _buildEmptyBodeChart() {
    const axisStyle = TextStyle(
      fontSize: 14,
      color: Colors.white70,
      fontWeight: FontWeight.w600,
    );
    const gridColor = Color(0xFF3D4F5F);
    return Stack(
      alignment: Alignment.center,
      children: [
        LineChart(
          LineChartData(
            minX: 0,
            maxX: 1000,
            minY: 0,
            maxY: 100,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: true,
              getDrawingHorizontalLine: (value) =>
                  FlLine(color: gridColor, strokeWidth: 1),
              getDrawingVerticalLine: (value) =>
                  FlLine(color: gridColor, strokeWidth: 1),
            ),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 48,
                  interval: 20,
                  getTitlesWidget: (value, meta) => Text(
                    '${value.toStringAsFixed(0)} Ω',
                    style: axisStyle,
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 40,
                  interval: 200,
                  getTitlesWidget: (value, meta) => Text(
                    '${value.toStringAsFixed(0)} Hz',
                    style: axisStyle,
                  ),
                ),
              ),
              topTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            borderData: FlBorderData(
              show: true,
              border: Border.all(color: gridColor, width: 1.5),
            ),
            lineBarsData: [],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF2C3E50).withOpacity(0.95),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.show_chart, size: 40, color: Colors.white54),
              const SizedBox(height: 8),
              Text(
                'Aucune donnée de balayage',
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Le patient doit se connecter au pansement,\ncollecter les données puis « Envoyer au médecin ».',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _formatFreqHz(double hz) {
    if (hz >= 1e6) return '${(hz / 1e6).toStringAsFixed(hz >= 10e6 ? 0 : 1)} M';
    if (hz >= 1e3) return '${(hz / 1e3).toStringAsFixed(hz >= 10e3 ? 0 : 1)} k';
    return hz.toStringAsFixed(0);
  }

  /// Regroupe les points Bode par session d'envoi (écart > _sessionGapMinutes = nouvelle session).
  /// Retourne les sessions de la plus récente à la plus ancienne.
  static List<List<Measurement>> _groupBodeSessions(
      List<Measurement> bodePoints) {
    if (bodePoints.isEmpty) return [];
    final sorted = List<Measurement>.from(bodePoints)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final sessions = <List<Measurement>>[];
    List<Measurement> current = [sorted.first];
    for (int i = 1; i < sorted.length; i++) {
      final prev = sorted[i - 1].timestamp;
      final next = sorted[i].timestamp;
      if (next.difference(prev).inMinutes > _sessionGapMinutes) {
        current.sort((a, b) => (a.freqHz ?? 0).compareTo(b.freqHz ?? 0));
        sessions.add(current);
        current = [sorted[i]];
      } else {
        current.add(sorted[i]);
      }
    }
    current.sort((a, b) => (a.freqHz ?? 0).compareTo(b.freqHz ?? 0));
    sessions.add(current);
    return sessions.reversed.toList(); // plus récente en premier
  }

  static String _formatSessionLabel(List<Measurement> session, int index) {
    if (session.isEmpty) return 'Session ${index + 1}';
    final t = session.first.timestamp;
    final jj = t.day.toString().padLeft(2, '0');
    final mm = t.month.toString().padLeft(2, '0');
    final hh = t.hour.toString().padLeft(2, '0');
    final min = t.minute.toString().padLeft(2, '0');
    final dateTime = '$jj/$mm $hh:$min';
    return index == 0 ? 'Dernières données ($dateTime)' : 'Session $dateTime';
  }

  Widget _buildBodeChart(List<Measurement> points) {
    // Courbe Bode: impédance (Y) en fonction de la fréquence (X).
    final freqList = points.map((m) => m.freqHz!).toList();
    final impList = points.map((m) => m.value).toList();
    double xMin =
        (freqList.isEmpty ? 0.0 : freqList.reduce((a, b) => a < b ? a : b)) - 1;
    double xMax =
        (freqList.isEmpty ? 1.0 : freqList.reduce((a, b) => a > b ? a : b)) + 1;
    double yMin =
        (impList.isEmpty ? 0.0 : impList.reduce((a, b) => a < b ? a : b)) - 1;
    double yMax =
        (impList.isEmpty ? 1.0 : impList.reduce((a, b) => a > b ? a : b)) + 1;
    if (xMax <= xMin) xMax = xMin + 1;
    if (yMax <= yMin) yMax = yMin + 1;
    const axisStyle = TextStyle(
      fontSize: 14,
      color: Colors.white70,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    );
    const gridColor = Color(0xFF3D4F5F);
    return RepaintBoundary(
      child: LineChart(
        LineChartData(
          minX: xMin,
          maxX: xMax,
          minY: yMin.clamp(0, double.infinity),
          maxY: yMax,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: true,
            getDrawingHorizontalLine: (value) =>
                FlLine(color: gridColor, strokeWidth: 1),
            getDrawingVerticalLine: (value) =>
                FlLine(color: gridColor, strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 56,
                interval: (yMax - yMin) / 5,
                getTitlesWidget: (value, meta) => Text(
                  '${value.toStringAsFixed(0)} Ω',
                  style: axisStyle,
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 48,
                interval: (xMax - xMin) / 4,
                getTitlesWidget: (value, meta) => Text(
                  '${_formatFreqHz(value)} Hz',
                  style: axisStyle,
                ),
              ),
            ),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(
            show: true,
            border: Border.all(color: gridColor, width: 1.5),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: points.map((m) => FlSpot(m.freqHz!, m.value)).toList(),
              isCurved: false,
              color: const Color(0xFF42A5F5),
              barWidth: 2.5,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, barData, index) =>
                    FlDotCirclePainter(
                  radius: 3,
                  color: const Color(0xFF42A5F5),
                  strokeWidth: 1,
                  strokeColor: const Color(0xFF1E2A38),
                ),
              ),
              belowBarData: BarAreaData(show: false),
            ),
          ],
        ),
        duration: Duration.zero,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Vue médecin orientée analyse:
    // sélection période/session + graphique Bode + tableau des points.
    final measurementsAsync = ref.watch(
      patientMeasurementsProvider(widget.patient.id),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('Mesures - ${widget.patient.fullName}'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(patientMeasurementsProvider(widget.patient.id));
          await ref.read(patientMeasurementsProvider(widget.patient.id).future);
        },
        child: measurementsAsync.when(
          data: (measurements) {
            final now = DateTime.now();
            final days = int.parse(_selectedTimeRange);
            final cutoffDate = now.subtract(Duration(days: days));
            final filteredMeasurements = measurements
                .where((m) => m.timestamp.isAfter(cutoffDate))
                .toList();

            final bodeMeasurements = filteredMeasurements
                .where(
                    (m) => m.measurementType == 'impedance' && m.freqHz != null)
                .toList();

            final sessions = _groupBodeSessions(bodeMeasurements);
            final sessionIndex = _selectedSessionIndex.clamp(
                0, sessions.isEmpty ? 0 : sessions.length - 1);
            if (sessionIndex != _selectedSessionIndex) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted)
                  setState(() => _selectedSessionIndex = sessionIndex);
              });
            }
            final selectedPoints =
                sessions.isEmpty ? <Measurement>[] : sessions[sessionIndex];

            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Courbe d\'Impédance',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).brightness == Brightness.dark
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                            ),
                            Text(
                              '(Bode)',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: Theme.of(context).brightness == Brightness.dark
                                        ? Colors.white70
                                        : Colors.black54,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      if (sessions.isNotEmpty)
                        Material(
                          color: Colors.grey[800],
                          borderRadius: BorderRadius.circular(8),
                          child: InkWell(
                            onTap: sessionIndex == 0
                                ? null
                                : () {
                                    setState(() => _selectedSessionIndex = 0);
                                  },
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Reset',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: sessionIndex == 0
                                          ? Colors.grey[500]
                                          : Colors.white,
                                    ),
                                  ),
                                  Text(
                                    'Graph',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: sessionIndex == 0
                                          ? Colors.grey[500]
                                          : Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Axe X = fréquence (Hz), axe Y = impédance (Ω). Par défaut : dernières valeurs envoyées.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                  ),
                  if (sessions.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Choisir une session',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[700],
                          ),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<int>(
                      value: sessionIndex,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      items: List.generate(sessions.length, (i) {
                        return DropdownMenuItem(
                          value: i,
                          child: Text(_formatSessionLabel(sessions[i], i)),
                        );
                      }),
                      onChanged: (v) {
                        if (v != null)
                          setState(() => _selectedSessionIndex = v);
                      },
                    ),
                  ],
                  const SizedBox(height: 16),
                  Card(
                    color: const Color(0xFF1E2A38),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: SizedBox(
                        height: 320,
                        child: RepaintBoundary(
                          child: selectedPoints.isEmpty
                              ? _buildEmptyBodeChart()
                              : _buildBodeChart(selectedPoints),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              height: MediaQuery.of(context).size.height - 200,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline,
                          size: 64, color: Colors.red[300]),
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
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
