import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/sensor_device.dart';
import '../services/witmotion_ble_service.dart';
import '../widgets/sensor_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _ble = WitmotionBleService();

  List<SensorDevice> _sensors = [];
  List<ScanResult> _scanResults = [];
  bool _isScanning = false;

  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    _subs.add(_ble.sensorsStream.listen((s) => setState(() => _sensors = s)));
    _subs.add(_ble.scanResults.listen((r) => setState(() => _scanResults = r)));
    _subs.add(_ble.isScanning.listen((s) => setState(() => _isScanning = s)));
    _subs.add(_ble.errors.listen((msg) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red),
      );
    }));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _ble.dispose();
    super.dispose();
  }

  void _toggleScan() {
    if (_isScanning) {
      _ble.stopScan();
    } else {
      _scanResults.clear();
      _ble.startScan();
    }
  }

  bool _alreadyAdded(ScanResult r) =>
      _sensors.any((s) => s.id == r.device.remoteId.str);

  @override
  Widget build(BuildContext context) {
    final allRecording = _sensors.isNotEmpty && _sensors.every((s) => s.isRecording);
    final anyConnected = _sensors.any((s) => s.isConnected);

    return Scaffold(
      appBar: AppBar(
        title: const Text('WitMotion Sensors'),
        actions: [
          if (anyConnected) ...[
            TextButton.icon(
              onPressed: allRecording
                  ? _ble.stopAllRecording
                  : _ble.startAllRecording,
              icon: Icon(allRecording ? Icons.stop : Icons.fiber_manual_record),
              label: Text(allRecording ? 'Stop All' : 'Record All'),
              style: TextButton.styleFrom(
                foregroundColor:
                    allRecording ? Colors.red : Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          _ScanBar(
            isScanning: _isScanning,
            canScan: _ble.canAddMore,
            onToggle: _toggleScan,
          ),
          if (_sensors.isNotEmpty) ...[
            const Divider(height: 0),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  Text(
                    'Connected Sensors (${_sensors.length}/4)',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ],
              ),
            ),
            ..._sensors.map(
              (s) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: SensorCard(
                  sensor: s,
                  onDisconnect: () => _ble.disconnect(s.id),
                  onStartRecording: () => _ble.startRecording(s.id),
                  onStopRecording: () => _ble.stopRecording(s.id),
                  onStartCapture: () => _ble.startCapture(s.id),
                  onStopCapture: () => _ble.stopCapture(s.id),
                ),
              ),
            ),
          ],
          if (_scanResults.isNotEmpty) ...[
            const Divider(height: 0),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  Text('Nearby Sensors',
                      style: Theme.of(context).textTheme.labelLarge),
                ],
              ),
            ),
            ..._scanResults
                .where((r) => !_alreadyAdded(r))
                .map((r) => _ScanResultTile(
                      result: r,
                      canConnect: _ble.canAddMore,
                      onConnect: () => _ble.connect(r.device),
                    )),
          ],
          if (_sensors.isEmpty && _scanResults.isEmpty && !_isScanning)
            const Expanded(child: _EmptyState()),
        ],
      ),
    );
  }
}

class _ScanBar extends StatelessWidget {
  final bool isScanning;
  final bool canScan;
  final VoidCallback onToggle;

  const _ScanBar(
      {required this.isScanning,
      required this.canScan,
      required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.tonal(
              onPressed: canScan || isScanning ? onToggle : null,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isScanning) ...[
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    const Text('Stop Scanning'),
                  ] else ...[
                    const Icon(Icons.bluetooth_searching),
                    const SizedBox(width: 8),
                    Text(canScan ? 'Scan for Sensors' : 'Max sensors reached (4/4)'),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanResultTile extends StatelessWidget {
  final ScanResult result;
  final bool canConnect;
  final VoidCallback onConnect;

  const _ScanResultTile(
      {required this.result,
      required this.canConnect,
      required this.onConnect});

  @override
  Widget build(BuildContext context) {
    final name = result.device.platformName.isNotEmpty
        ? result.device.platformName
        : result.device.remoteId.str;
    return ListTile(
      dense: true,
      leading: const Icon(Icons.bluetooth),
      title: Text(name),
      subtitle: Text('RSSI: ${result.rssi} dBm'),
      trailing: TextButton(
        onPressed: canConnect ? onConnect : null,
        child: const Text('Connect'),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.bluetooth_disabled, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text('No sensors found',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'Tap "Scan for Sensors" to discover\nnearby WitMotion WT901SDCL-BT50 devices.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
