
// ControlCommand and related command classes remain for use with FitnessDevice

/// Base class for control commands
sealed class ControlCommand {
  const ControlCommand();
}

/// Set resistance level (for bikes)
class SetResistance extends ControlCommand {
  final int level; // 1-20

  const SetResistance(this.level);

  @override
  String toString() => 'SetResistance($level)';
}

/// Set incline percentage (for treadmills)
class SetIncline extends ControlCommand {
  final double percentage; // -3.0 to +15.0

  const SetIncline(this.percentage);

  @override
  String toString() => 'SetIncline(${percentage.toStringAsFixed(1)}%)';
}
