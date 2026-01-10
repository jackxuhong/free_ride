import 'package:flutter/material.dart';
import 'package:free_ride/models/configuration_item.dart';

class ConfigurationItemWidget extends StatefulWidget {
  final ConfigurationItem item;
  final dynamic currentValue;
  final ValueChanged<dynamic> onChanged;
  final bool enabled;

  const ConfigurationItemWidget({
    Key? key,
    required this.item,
    required this.currentValue,
    required this.onChanged,
    this.enabled = true,
  }) : super(key: key);

  @override
  State<ConfigurationItemWidget> createState() => _ConfigurationItemWidgetState();
}

class _ConfigurationItemWidgetState extends State<ConfigurationItemWidget> {
  late TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(
      text: widget.currentValue?.toString() ?? '',
    );
  }

  @override
  void didUpdateWidget(ConfigurationItemWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentValue != widget.currentValue) {
      _textController.text = widget.currentValue?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.item.name,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (widget.item.description.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(
                    widget.item.description,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: _buildControlWidget(),
        ),
      ],
    );
  }

  Widget _buildControlWidget() {
    switch (widget.item.dataType) {
      case ConfigurationDataType.boolean:
        return Switch(
          value: widget.currentValue ?? widget.item.defaultValue ?? false,
          onChanged: widget.enabled
              ? (value) {
                  widget.onChanged(value);
                }
              : null,
        );

      case ConfigurationDataType.integer:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Slider(
              value: (widget.currentValue ?? widget.item.defaultValue ?? 0).toDouble(),
              min: (widget.item.minValue ?? 0).toDouble(),
              max: (widget.item.maxValue ?? 100).toDouble(),
              divisions: ((widget.item.maxValue ?? 100) - (widget.item.minValue ?? 0)).toInt(),
              label: widget.item.formatValue(widget.currentValue ?? widget.item.defaultValue),
              onChanged: widget.enabled
                  ? (value) {
                      widget.onChanged(value.toInt());
                    }
                  : null,
            ),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    width: 100,
                    child: TextField(
                      controller: _textController,
                      keyboardType: TextInputType.number,
                      enabled: widget.enabled,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (value) {
                        final parsed = int.tryParse(value);
                        if (parsed != null && widget.item.isValid(parsed)) {
                          widget.onChanged(parsed);
                        } else {
                          _textController.text = widget.currentValue?.toString() ?? '';
                        }
                      },
                    ),
                  ),
                ),
                if (widget.item.units != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8.0),
                    child: Text(widget.item.units!),
                  ),
              ],
            ),
          ],
        );

      case ConfigurationDataType.floatingPoint:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Slider(
              value: (widget.currentValue ?? widget.item.defaultValue ?? 0.0) as double,
              min: (widget.item.minValue ?? 0.0) as double,
              max: (widget.item.maxValue ?? 100.0) as double,
              divisions: ((((widget.item.maxValue ?? 100.0) as double) - 
                  ((widget.item.minValue ?? 0.0) as double)) * 100).toInt(),
              label: widget.item.formatValue(widget.currentValue ?? widget.item.defaultValue),
              onChanged: widget.enabled
                  ? (value) {
                      widget.onChanged(value);
                    }
                  : null,
            ),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    width: 100,
                    child: TextField(
                      controller: _textController,
                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                      enabled: widget.enabled,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (value) {
                        final parsed = double.tryParse(value);
                        if (parsed != null && widget.item.isValid(parsed)) {
                          widget.onChanged(parsed);
                        } else {
                          _textController.text = widget.currentValue?.toString() ?? '';
                        }
                      },
                    ),
                  ),
                ),
                if (widget.item.units != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8.0),
                    child: Text(widget.item.units!),
                  ),
              ],
            ),
          ],
        );

      case ConfigurationDataType.string:
        return TextField(
          controller: _textController,
          enabled: !widget.item.isReadOnly && widget.enabled,
          readOnly: widget.item.isReadOnly,
          decoration: InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onSubmitted: (value) {
            if (!widget.item.isReadOnly && widget.item.isValid(value)) {
              widget.onChanged(value);
            }
          },
        );
    }
  }
}
