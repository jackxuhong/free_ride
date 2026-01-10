enum ConfigurationDataType {
  boolean,
  integer,
  floatingPoint,
  string,
}

class ConfigurationItem {
  final String key;
  final String name;
  final String description;
  final ConfigurationDataType dataType;
  final dynamic minValue;
  final dynamic maxValue;
  final dynamic defaultValue;
  final int sortOrder;
  final bool isReadOnly;
  final String? units;

  ConfigurationItem({
    required this.key,
    required this.name,
    required this.description,
    required this.dataType,
    this.minValue,
    this.maxValue,
    required this.defaultValue,
    required this.sortOrder,
    this.isReadOnly = false,
    this.units,
  });

  /// Validates a value against the configuration constraints
  bool isValid(dynamic value) {
    if (value == null) return false;

    switch (dataType) {
      case ConfigurationDataType.boolean:
        return value is bool;
      case ConfigurationDataType.integer:
        if (value is! int) return false;
        if (minValue != null && value < minValue) return false;
        if (maxValue != null && value > maxValue) return false;
        return true;
      case ConfigurationDataType.floatingPoint:
        final numValue = value is num ? value : double.tryParse(value.toString());
        if (numValue == null) return false;
        if (minValue != null && numValue < minValue) return false;
        if (maxValue != null && numValue > maxValue) return false;
        return true;
      case ConfigurationDataType.string:
        return value is String;
    }
  }

  /// Formats a value for display
  String formatValue(dynamic value) {
    if (value == null) return '';

    switch (dataType) {
      case ConfigurationDataType.boolean:
        return value ? 'On' : 'Off';
      case ConfigurationDataType.integer:
        final suffix = units != null ? ' $units' : '';
        return '$value$suffix';
      case ConfigurationDataType.floatingPoint:
        final numValue = value is num ? value : double.tryParse(value.toString());
        if (numValue == null) return '';
        final suffix = units != null ? ' $units' : '';
        return '${numValue.toStringAsFixed(2)}$suffix';
      case ConfigurationDataType.string:
        return value.toString();
    }
  }

  /// Coerces a value to the correct type
  dynamic coerceValue(dynamic value) {
    if (value == null) return defaultValue;

    switch (dataType) {
      case ConfigurationDataType.boolean:
        if (value is bool) return value;
        if (value is String) return value.toLowerCase() == 'true';
        return false;
      case ConfigurationDataType.integer:
        if (value is int) return value;
        if (value is String) return int.tryParse(value) ?? defaultValue;
        if (value is double) return value.toInt();
        return defaultValue;
      case ConfigurationDataType.floatingPoint:
        if (value is double) return value;
        if (value is int) return value.toDouble();
        if (value is String) return double.tryParse(value) ?? defaultValue;
        return defaultValue;
      case ConfigurationDataType.string:
        return value.toString();
    }
  }
}
