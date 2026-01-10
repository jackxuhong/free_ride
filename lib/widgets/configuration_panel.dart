import 'package:flutter/material.dart';
import 'package:free_ride/models/device_configuration.dart';
import 'package:free_ride/widgets/configuration_item_widget.dart';

typedef ConfigurationAppliedCallback = void Function(Map<String, dynamic> config);

class ConfigurationPanel extends StatefulWidget {
  final DeviceConfiguration configuration;
  final VoidCallback onReset;
  final ConfigurationAppliedCallback onApply;
  final VoidCallback onCancel;

  const ConfigurationPanel({
    Key? key,
    required this.configuration,
    required this.onReset,
    required this.onApply,
    required this.onCancel,
  }) : super(key: key);

  @override
  State<ConfigurationPanel> createState() => _ConfigurationPanelState();
}

class _ConfigurationPanelState extends State<ConfigurationPanel> {
  late Map<String, dynamic> _workingValues;

  @override
  void initState() {
    super.initState();
    _workingValues = Map<String, dynamic>.from(widget.configuration.getAllValues());
  }

  @override
  Widget build(BuildContext context) {
    final sortedItems = widget.configuration.getSortedItems();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(
          child: ListView.separated(
            itemCount: sortedItems.length,
            separatorBuilder: (context, index) => Divider(height: 1),
            itemBuilder: (context, index) {
              final item = sortedItems[index];
              final currentValue = _workingValues[item.key];

              return ConfigurationItemWidget(
                item: item,
                currentValue: currentValue,
                onChanged: (value) {
                  setState(() {
                    _workingValues[item.key] = value;
                  });
                },
                enabled: !item.isReadOnly,
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: Icon(Icons.refresh),
                  label: Text('Reset All'),
                  onPressed: () {
                    setState(() {
                      _workingValues = {};
                      for (final item in widget.configuration.schema.values) {
                        _workingValues[item.key] = item.defaultValue;
                      }
                    });
                    widget.onReset();
                  },
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  icon: Icon(Icons.close),
                  label: Text('Cancel'),
                  onPressed: widget.onCancel,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  icon: Icon(Icons.check),
                  label: Text('Apply'),
                  onPressed: () {
                    widget.onApply(_workingValues);
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
