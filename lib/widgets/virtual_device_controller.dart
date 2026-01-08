import 'package:flutter/material.dart';

/// DEPRECATED: Virtual devices are no longer supported
class VirtualDeviceController extends StatelessWidget {
  final dynamic device;

  const VirtualDeviceController({super.key, required this.device});

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
