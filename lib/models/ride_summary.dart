import 'dart:typed_data';
import 'package:hive/hive.dart';

part 'ride_summary.g.dart';

@HiveType(typeId: 6)
class RideSummary extends HiveObject {
  // Time Metrics
  @HiveField(0)
  final Duration totalDuration;
  
  @HiveField(1)
  final Duration movingTime;
  
  @HiveField(2)
  final Duration pausedTime;
  
  @HiveField(3)
  final DateTime startTime;
  
  @HiveField(4)
  final DateTime? endTime;
  
  // Distance Metrics
  @HiveField(5)
  final double totalDistance; // meters
  
  @HiveField(6)
  final double completedDistance; // meters
  
  @HiveField(7)
  final double completionPercentage; // 0-100
  
  // Speed Metrics
  @HiveField(8)
  final double averageSpeed; // km/h
  
  @HiveField(9)
  final double averageMovingSpeed; // km/h
  
  @HiveField(10)
  final double maxSpeed; // km/h
  
  @HiveField(11)
  final double minSpeed; // km/h
  
  // Elevation Metrics
  @HiveField(12)
  final double totalElevationGain; // meters
  
  @HiveField(13)
  final double totalElevationLoss; // meters
  
  @HiveField(14)
  final double maxGrade; // percentage
  
  @HiveField(15)
  final double minGrade; // percentage
  
  @HiveField(16)
  final double currentElevation; // meters
  
  // Performance Metrics
  @HiveField(17)
  final int caloriesBurned;
  
  @HiveField(18)
  final double averagePower; // watts
  
  // Route Info
  @HiveField(19)
  final String routeId;
  
  @HiveField(20)
  String routeName; // Made mutable for renaming
  
  @HiveField(21)
  final bool completed;
  
  @HiveField(22)
  final String? cancellationReason;
  
  @HiveField(23)
  final Uint8List? routeThumbnail;

  RideSummary({
    required this.totalDuration,
    required this.movingTime,
    required this.pausedTime,
    required this.startTime,
    this.endTime,
    required this.totalDistance,
    required this.completedDistance,
    required this.completionPercentage,
    required this.averageSpeed,
    required this.averageMovingSpeed,
    required this.maxSpeed,
    required this.minSpeed,
    required this.totalElevationGain,
    required this.totalElevationLoss,
    required this.maxGrade,
    required this.minGrade,
    required this.currentElevation,
    required this.caloriesBurned,
    required this.averagePower,
    required this.routeId,
    required this.routeName,
    required this.completed,
    this.cancellationReason,
    this.routeThumbnail,
  });
  
  String get formattedDuration {
    final hours = totalDuration.inHours;
    final minutes = totalDuration.inMinutes.remainder(60);
    final seconds = totalDuration.inSeconds.remainder(60);
    
    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }
  
  String get formattedDistance {
    final km = completedDistance / 1000.0;
    return '${km.toStringAsFixed(2)} km';
  }
  
  String get formattedAverageSpeed {
    return '${averageSpeed.toStringAsFixed(1)} km/h';
  }
  
  /// Create a detached copy for saving to Hive
  RideSummary copyForSave() {
    return RideSummary(
      totalDuration: totalDuration,
      movingTime: movingTime,
      pausedTime: pausedTime,
      startTime: startTime,
      endTime: endTime,
      totalDistance: totalDistance,
      completedDistance: completedDistance,
      completionPercentage: completionPercentage,
      averageSpeed: averageSpeed,
      averageMovingSpeed: averageMovingSpeed,
      maxSpeed: maxSpeed,
      minSpeed: minSpeed,
      totalElevationGain: totalElevationGain,
      totalElevationLoss: totalElevationLoss,
      maxGrade: maxGrade,
      minGrade: minGrade,
      currentElevation: currentElevation,
      caloriesBurned: caloriesBurned,
      averagePower: averagePower,
      routeId: routeId,
      routeName: routeName,
      completed: completed,
      cancellationReason: cancellationReason,
      routeThumbnail: routeThumbnail,
    );
  }
}
