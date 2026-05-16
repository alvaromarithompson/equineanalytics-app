import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/captured_frame.dart';
import '../models/sensor_device.dart';
import 'file_saver.dart';

// WitMotion WT901SDCL-BT50 BLE UUIDs — matched by substring below.
const _serviceUuid = '0000ffe5-0000-1000-8000-00805f9a34fb';

// WitMotion command protocol: FF AA <reg> <dataL> <dataH>
// Register 0x69 controls SD card recording on SDCL models.
const _cmdStartRecording = [0xFF, 0xAA, 0x69, 0x01, 0x00];
const _cmdStopRecording = [0xFF, 0xAA, 0x69, 0x00, 0x00];

const _maxSensors = 4;

// Device name prefixes used by WitMotion BT50 sensors.
const _witDevicePrefixes = ['WT', 'BWT', 'WITMOTION'];

class WitmotionBleService {
  final Map<String, SensorDevice> _sensors = {};
  final Map<String, StreamSubscription> _dataSubscriptions = {};

  final _sensorsController = StreamController<List<SensorDevice>>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  Stream<List<SensorDevice>> get sensorsStream => _sensorsController.stream;
  Stream<String> get errors => _errorController.stream;
  List<SensorDevice> get sensors => List.unmodifiable(_sensors.values);

  bool get canAddMore => _sensors.length < _maxSensors;

  // ── Scanning ──────────────────────────────────────────────────────────────

  void startScan() {
    FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 15),
      // withServices empty → acceptAllDevices on web (device appears in picker).
      // webOptionalServices declares FFE5 so Chrome grants GATT access post-connect.
      webOptionalServices: kIsWeb ? [Guid(_serviceUuid)] : [],
    );
  }

  void stopScan() => FlutterBluePlus.stopScan();

  Stream<List<ScanResult>> get scanResults => FlutterBluePlus.scanResults.map(
        (results) => results
            .where((r) => _isWitDevice(r.device.platformName))
            .toList(),
      );

  Stream<bool> get isScanning => FlutterBluePlus.isScanning;

  bool _isWitDevice(String name) =>
      _witDevicePrefixes.any((p) => name.toUpperCase().startsWith(p));

  // ── Connection ────────────────────────────────────────────────────────────

  Future<void> connect(BluetoothDevice device) async {
    if (_sensors.containsKey(device.remoteId.str) || !canAddMore) return;

    final sensor = SensorDevice(device);
    sensor.state = SensorState.connecting;
    _sensors[sensor.id] = sensor;
    _notify();

    try {
      await device.connect(timeout: const Duration(seconds: 15));
      await _discoverServices(sensor);
    } catch (e) {
      debugPrint('BLE connect error: $e');
      _errorController.add('Could not connect to ${sensor.name}: $e');
      _sensors.remove(sensor.id);
    }
    _notify();
  }

  Future<void> disconnect(String sensorId) async {
    final sensor = _sensors[sensorId];
    if (sensor == null) return;

    await _dataSubscriptions[sensorId]?.cancel();
    _dataSubscriptions.remove(sensorId);

    try {
      await sensor.device.disconnect();
    } catch (_) {}

    _sensors.remove(sensorId);
    _notify();
  }

  Future<void> _discoverServices(SensorDevice sensor) async {
    final services = await sensor.device.discoverServices();

    debugPrint('Discovered ${services.length} services:');
    for (final svc in services) {
      debugPrint('  Service: ${svc.uuid}');
      for (final char in svc.characteristics) {
        debugPrint('    Char: ${char.uuid}  props: ${char.properties}');
      }
    }

    for (final svc in services) {
      // Compare only the significant part to handle short vs full UUID formats.
      if (!svc.uuid.toString().toLowerCase().contains('ffe5')) continue;
      for (final char in svc.characteristics) {
        final uuid = char.uuid.toString().toLowerCase();
        if (uuid.contains('ffe4')) sensor.notifyCharacteristic = char;
        if (uuid.contains('ffe9')) sensor.writeCharacteristic = char;
      }
    }

    if (sensor.notifyCharacteristic != null) {
      // Mark connected now — don't block on setNotifyValue which can hang on web.
      sensor.state = SensorState.connected;
      _notify();

      _dataSubscriptions[sensor.id] = sensor.notifyCharacteristic!
          .onValueReceived
          .listen((data) => _parsePacket(sensor, data));

      // Enable notifications in the background; timeout is non-fatal on web
      // because addEventListener is already attached before startNotifications().
      sensor.notifyCharacteristic!
          .setNotifyValue(true)
          .catchError((e) {
            debugPrint('setNotifyValue (non-fatal): $e');
            return false;
          });
    } else {
      debugPrint('Warning: notify characteristic (FFE4) not found on ${sensor.name}');
    }
  }

  // ── Recording ─────────────────────────────────────────────────────────────

  Future<void> startRecording(String sensorId) async {
    final sensor = _sensors[sensorId];
    if (sensor == null || !sensor.isConnected) return;
    await _write(sensor, _cmdStartRecording);
    sensor.state = SensorState.recording;
    _notify();
  }

  Future<void> stopRecording(String sensorId) async {
    final sensor = _sensors[sensorId];
    if (sensor == null || !sensor.isRecording) return;
    await _write(sensor, _cmdStopRecording);
    sensor.state = SensorState.connected;
    _notify();
  }

  Future<void> startAllRecording() async {
    for (final id in _sensors.keys.toList()) {
      await startRecording(id);
    }
  }

  Future<void> stopAllRecording() async {
    for (final id in _sensors.keys.toList()) {
      await stopRecording(id);
    }
  }

  // ── Capture to file ───────────────────────────────────────────────────────

  void startCapture(String sensorId) {
    final sensor = _sensors[sensorId];
    if (sensor == null || !sensor.isConnected) return;
    sensor.capturedFrames.clear();
    sensor.isCapturing = true;
    _notify();
  }

  Future<void> stopCapture(String sensorId) async {
    final sensor = _sensors[sensorId];
    if (sensor == null || !sensor.isCapturing) return;
    sensor.isCapturing = false;
    _notify();

    final frames = List<CapturedFrame>.from(sensor.capturedFrames);
    sensor.capturedFrames.clear();

    if (frames.isEmpty) return;

    final csv = StringBuffer()
      ..writeln(CapturedFrame.csvHeader)
      ..writeAll(frames.map((f) => f.toCsvRow()), '\n');

    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .substring(0, 19);
    final filename = '${sensor.name}_$timestamp.csv';

    try {
      await saveTextFile(filename, csv.toString());
    } catch (e) {
      _errorController.add('Could not save file: $e');
    }
  }

  Future<void> _write(SensorDevice sensor, List<int> bytes) async {
    if (sensor.writeCharacteristic == null) return;
    await sensor.writeCharacteristic!.write(
      Uint8List.fromList(bytes),
      withoutResponse:
          sensor.writeCharacteristic!.properties.writeWithoutResponse,
    );
  }

  // ── Data parsing ──────────────────────────────────────────────────────────

  // WT901SDCL-BT50 combined packet: 0x55 0x61 + 13× int16 LE (26 data bytes = 28 total)
  // Byte layout (all int16 little-endian):
  //   [2-3]  Acc X   (/32768 × 16 × 9.8 m/s²)
  //   [4-5]  Acc Y
  //   [6-7]  Acc Z
  //   [8-9]  Gyro X  (/32768 × 2000 °/s)
  //   [10-11] Gyro Y
  //   [12-13] Gyro Z
  //   [14-15] Roll   (/32768 × 180 °)
  //   [16-17] Pitch
  //   [18-19] Yaw
  //   [20+]  magnetometer / timestamp (ignored for now)
  void _parsePacket(SensorDevice sensor, List<int> data) {
    if (data.length < 2 || data[0] != 0x55) return;

    final bytes = Uint8List.fromList(data);
    final bd = ByteData.sublistView(bytes);

    if (data[1] == 0x61 && data.length >= 20) {
      sensor.accX = bd.getInt16(2, Endian.little) / 32768.0 * 16 * 9.8;
      sensor.accY = bd.getInt16(4, Endian.little) / 32768.0 * 16 * 9.8;
      sensor.accZ = bd.getInt16(6, Endian.little) / 32768.0 * 16 * 9.8;
      sensor.gyroX = bd.getInt16(8, Endian.little) / 32768.0 * 2000;
      sensor.gyroY = bd.getInt16(10, Endian.little) / 32768.0 * 2000;
      sensor.gyroZ = bd.getInt16(12, Endian.little) / 32768.0 * 2000;
      sensor.roll = bd.getInt16(14, Endian.little) / 32768.0 * 180;
      sensor.pitch = bd.getInt16(16, Endian.little) / 32768.0 * 180;
      sensor.yaw = bd.getInt16(18, Endian.little) / 32768.0 * 180;

      if (sensor.isCapturing) {
        sensor.capturedFrames.add(CapturedFrame(
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          accX: sensor.accX!, accY: sensor.accY!, accZ: sensor.accZ!,
          gyroX: sensor.gyroX!, gyroY: sensor.gyroY!, gyroZ: sensor.gyroZ!,
          roll: sensor.roll!, pitch: sensor.pitch!, yaw: sensor.yaw!,
        ));
      }
    } else {
      // Legacy 11-byte individual packets (0x51 acc / 0x52 gyro / 0x53 angle)
      if (data.length < 11) return;
      switch (data[1]) {
        case 0x51:
          sensor.accX = bd.getInt16(2, Endian.little) / 32768.0 * 16 * 9.8;
          sensor.accY = bd.getInt16(4, Endian.little) / 32768.0 * 16 * 9.8;
          sensor.accZ = bd.getInt16(6, Endian.little) / 32768.0 * 16 * 9.8;
        case 0x52:
          sensor.gyroX = bd.getInt16(2, Endian.little) / 32768.0 * 2000;
          sensor.gyroY = bd.getInt16(4, Endian.little) / 32768.0 * 2000;
          sensor.gyroZ = bd.getInt16(6, Endian.little) / 32768.0 * 2000;
        case 0x53:
          sensor.roll = bd.getInt16(2, Endian.little) / 32768.0 * 180;
          sensor.pitch = bd.getInt16(4, Endian.little) / 32768.0 * 180;
          sensor.yaw = bd.getInt16(6, Endian.little) / 32768.0 * 180;
      }
    }
    _notify();
  }

  void _notify() {
    _sensorsController.add(sensors);
  }

  void dispose() {
    for (final sub in _dataSubscriptions.values) {
      sub.cancel();
    }
    _sensorsController.close();
    _errorController.close();
  }
}
