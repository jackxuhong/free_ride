import 'package:free_ride/models/configuration_item.dart';

class DeviceConfiguration {
  final Map<String, ConfigurationItem> schema;
  final Map<String, dynamic> values;

  DeviceConfiguration({
    required this.schema,
    required this.values,
  });

  /// Get the current value of a configuration item
  dynamic getValue(String key) {
    final item = schema[key];
    if (item == null) return null;

    final value = values[key];
    if (value == null) return item.defaultValue;

    return item.coerceValue(value);
  }

  /// Set a configuration value, with validation
  bool setValue(String key, dynamic value) {
    final item = schema[key];
    if (item == null) return false;
    if (item.isReadOnly) return false;
    if (!item.isValid(value)) return false;

    values[key] = item.coerceValue(value);
    return true;
  }

  /// Reset all values to defaults
  void resetToDefaults() {
    values.clear();
    for (final item in schema.values) {
      values[item.key] = item.defaultValue;
    }
  }

  /// Reset a single value to default
  bool resetValue(String key) {
    final item = schema[key];
    if (item == null) return false;

    values[key] = item.defaultValue;
    return true;
  }

  /// Get all values, replacing nulls with defaults
  Map<String, dynamic> getAllValues() {
    final result = <String, dynamic>{};
    for (final item in schema.values) {
      result[item.key] = getValue(item.key);
    }
    return result;
  }

  /// Get sorted list of configuration items
  List<ConfigurationItem> getSortedItems() {
    final items = schema.values.toList();
    items.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return items;
  }

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return Map<String, dynamic>.from(values);
  }

  /// Create from JSON data
  factory DeviceConfiguration.fromJson(
    Map<String, ConfigurationItem> schema,
    Map<String, dynamic> json,
  ) {
    return DeviceConfiguration(
      schema: schema,
      values: Map<String, dynamic>.from(json),
    );
  }

  /// Create a fresh configuration with default values
  factory DeviceConfiguration.withDefaults(
    Map<String, ConfigurationItem> schema,
  ) {
    final values = <String, dynamic>{};
    for (final item in schema.values) {
      values[item.key] = item.defaultValue;
    }
    return DeviceConfiguration(schema: schema, values: values);
  }
}
