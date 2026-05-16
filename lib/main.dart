import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb && Platform.isAndroid) {
    FlutterBluePlus.setLogLevel(LogLevel.warning);
  }

  if (!kIsWeb) {
    await _requestPermissions();
  }

  runApp(const SensorApp());
}

Future<void> _requestPermissions() async {
  if (Platform.isAndroid) {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();
  } else if (Platform.isIOS) {
    await Permission.bluetooth.request();
  }
}

class SensorApp extends StatelessWidget {
  const SensorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WitMotion Sensors',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
      ),
      home: const _BluetoothGate(),
    );
  }
}

// Shows a friendly message if Bluetooth is off instead of crashing.
class _BluetoothGate extends StatelessWidget {
  const _BluetoothGate();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<BluetoothAdapterState>(
      stream: FlutterBluePlus.adapterState,
      initialData: BluetoothAdapterState.unknown,
      builder: (context, snapshot) {
        final state = snapshot.data!;
        if (state == BluetoothAdapterState.on) {
          return const HomeScreen();
        }
        return Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.bluetooth_disabled, size: 72, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  state == BluetoothAdapterState.off
                      ? 'Bluetooth is off'
                      : 'Bluetooth unavailable',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text('Please enable Bluetooth to use this app.',
                    style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),
        );
      },
    );
  }
}
