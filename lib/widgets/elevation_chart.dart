import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:free_ride/models/saved_route.dart';

class ElevationChart extends StatelessWidget {
  final SavedRoute route;
  final double currentProgress; // 0.0 to 1.0

  const ElevationChart({
    super.key,
    required this.route,
    required this.currentProgress,
  });

  @override
  Widget build(BuildContext context) {
    final elevations = route.elevationProfile.elevations;
    final segmentDistances = route.geometry.segmentDistances;
    
    if (elevations.isEmpty || segmentDistances.isEmpty) {
      return const SizedBox.shrink();
    }

    // Calculate cumulative distances from segment distances
    final distances = <double>[0.0];
    double cumulative = 0.0;
    for (final segment in segmentDistances) {
      cumulative += segment;
      distances.add(cumulative);
    }

    // Create chart data points
    final spots = <FlSpot>[];
    for (int i = 0; i < elevations.length && i < distances.length; i++) {
      final distanceKm = distances[i] / 1000.0;
      spots.add(FlSpot(distanceKm, elevations[i]));
    }

    // Find min/max for scaling
    final minElevation = elevations.reduce((a, b) => a < b ? a : b);
    final maxElevation = elevations.reduce((a, b) => a > b ? a : b);
    final maxDistance = distances.last / 1000.0;
    
    // Current position marker
    final currentDistanceKm = currentProgress * maxDistance;

    return Container(
      height: 100,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: LineChart(
        LineChartData(
          minY: minElevation - 10,
          maxY: maxElevation + 10,
          minX: 0,
          maxX: maxDistance,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: (maxElevation - minElevation) / 3,
            getDrawingHorizontalLine: (value) {
              return FlLine(
                color: Colors.grey.shade300,
                strokeWidth: 1,
              );
            },
          ),
          titlesData: const FlTitlesData(
            show: false,
          ),
          borderData: FlBorderData(
            show: true,
            border: Border(
              bottom: BorderSide(color: Colors.grey.shade300),
              left: BorderSide(color: Colors.grey.shade300),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: Colors.blue,
              barWidth: 2,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: Colors.blue.withValues(alpha: 0.2),
              ),
            ),
          ],
          extraLinesData: ExtraLinesData(
            verticalLines: currentProgress > 0
                ? [
                    // Current position marker
                    VerticalLine(
                      x: currentDistanceKm,
                      color: Colors.green,
                      strokeWidth: 2,
                      dashArray: [5, 5],
                    ),
                  ]
                : [],
          ),
          lineTouchData: const LineTouchData(enabled: false),
        ),
      ),
    );
  }
}
