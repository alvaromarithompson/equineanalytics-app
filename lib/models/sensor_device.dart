import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'captured_frame.dart';

enum SensorState { disconnected, connecting, connected, recording }

class SensorDevice {
  final BluetoothDevice device;
  SensorState state;
  BluetoothCharacteristic? writeCharacteristic;
  BluetoothCharacteristic? notifyCharacteristic;

  // Latest parsed data
  double? accX, accY, accZ;
  double? gyroX, gyroY, gyroZ;
  double? roll, pitch, yaw;

  // Capture
  bool isCapturing = false;
  final List<CapturedFrame> capturedFrames = [];

  SensorDevice(this.device) : state = SensorState.disconnected;

  String get id => device.remoteId.str;
  String get name => device.platformName.isNotEmpty ? device.platformName : id;
  bool get isConnected => state == SensorState.connected || state == SensorState.recording;
  bool get isRecording => state == SensorState.recording;
}
