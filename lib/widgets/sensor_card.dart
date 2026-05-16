import 'package:flutter/material.dart';
import '../models/sensor_device.dart';

class SensorCard extends StatelessWidget {
  final SensorDevice sensor;
  final VoidCallback onDisconnect;
  final VoidCallback onStartRecording;
  final VoidCallback onStopRecording;
  final VoidCallback onStartCapture;
  final VoidCallback onStopCapture;

  const SensorCard({
    super.key,
    required this.sensor,
    required this.onDisconnect,
    required this.onStartRecording,
    required this.onStopRecording,
    required this.onStartCapture,
    required this.onStopCapture,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(sensor: sensor, onDisconnect: onDisconnect),
            if (sensor.state == SensorState.connecting)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(),
              )
            else ...[
              const SizedBox(height: 8),
              _DataRow('Acc (m/s²)', sensor.accX, sensor.accY, sensor.accZ),
              _DataRow('Gyro (°/s)', sensor.gyroX, sensor.gyroY, sensor.gyroZ),
              _DataRow('Angle (°)', sensor.roll, sensor.pitch, sensor.yaw,
                  labels: ['R', 'P', 'Y']),
              const SizedBox(height: 10),
              const Divider(height: 16),
              // SD card recording
              Row(
                children: [
                  const Icon(Icons.sd_card, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  const Text('SD Card',
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
                  const SizedBox(width: 8),
                  if (sensor.isRecording)
                    _SmallButton(
                      onPressed: onStopRecording,
                      icon: Icons.stop,
                      label: 'Stop',
                      color: colors.error,
                    )
                  else
                    _SmallButton(
                      onPressed: sensor.isConnected ? onStartRecording : null,
                      icon: Icons.fiber_manual_record,
                      label: 'Record',
                      color: colors.primary,
                    ),
                ],
              ),
              const SizedBox(height: 6),
              // In-app capture
              Row(
                children: [
                  const Icon(Icons.download, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  const Text('Capture',
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
                  const SizedBox(width: 8),
                  if (sensor.isCapturing) ...[
                    _SmallButton(
                      onPressed: onStopCapture,
                      icon: Icons.stop_circle_outlined,
                      label: 'Stop & Save',
                      color: Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${sensor.capturedFrames.length} frames',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ] else
                    _SmallButton(
                      onPressed: sensor.isConnected ? onStartCapture : null,
                      icon: Icons.circle_outlined,
                      label: 'Capture',
                      color: Colors.teal,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final String label;
  final Color color;

  const _SmallButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      icon: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: FilledButton.styleFrom(
        backgroundColor: color.withValues(alpha: 0.15),
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final SensorDevice sensor;
  final VoidCallback onDisconnect;

  const _Header({required this.sensor, required this.onDisconnect});

  @override
  Widget build(BuildContext context) {
    final stateLabel = switch (sensor.state) {
      SensorState.connecting => 'Connecting…',
      SensorState.connected =>
        sensor.isCapturing ? 'Connected · Capturing' : 'Connected',
      SensorState.recording =>
        sensor.isCapturing ? 'Recording · Capturing' : 'Recording',
      SensorState.disconnected => 'Disconnected',
    };

    final stateColor = switch (sensor.state) {
      SensorState.connected => sensor.isCapturing ? Colors.teal : Colors.green,
      SensorState.recording => Colors.red,
      SensorState.connecting => Colors.orange,
      SensorState.disconnected => Colors.grey,
    };

    return Row(
      children: [
        Icon(Icons.sensors, color: stateColor),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(sensor.name,
                  style: Theme.of(context).textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis),
              Text(stateLabel,
                  style: TextStyle(fontSize: 11, color: stateColor)),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: onDisconnect,
          tooltip: 'Disconnect',
          iconSize: 18,
        ),
      ],
    );
  }
}

class _DataRow extends StatelessWidget {
  final String label;
  final double? x, y, z;
  final List<String> labels;

  const _DataRow(this.label, this.x, this.y, this.z,
      {this.labels = const ['X', 'Y', 'Z']});

  @override
  Widget build(BuildContext context) {
    String fmt(double? v) => v != null ? v.toStringAsFixed(2) : '--';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            child: Text(label,
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ),
          for (int i = 0; i < labels.length; i++) ...[
            Text('${labels[i]}: ',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            Text(
              fmt([x, y, z][i]),
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}
