class CapturedFrame {
  final int timestampMs;
  final double accX, accY, accZ;
  final double gyroX, gyroY, gyroZ;
  final double roll, pitch, yaw;

  const CapturedFrame({
    required this.timestampMs,
    required this.accX, required this.accY, required this.accZ,
    required this.gyroX, required this.gyroY, required this.gyroZ,
    required this.roll, required this.pitch, required this.yaw,
  });

  static const csvHeader =
      'timestamp_ms,acc_x_ms2,acc_y_ms2,acc_z_ms2,'
      'gyro_x_dps,gyro_y_dps,gyro_z_dps,'
      'roll_deg,pitch_deg,yaw_deg';

  String toCsvRow() =>
      '$timestampMs'
      ',${accX.toStringAsFixed(4)},${accY.toStringAsFixed(4)},${accZ.toStringAsFixed(4)}'
      ',${gyroX.toStringAsFixed(4)},${gyroY.toStringAsFixed(4)},${gyroZ.toStringAsFixed(4)}'
      ',${roll.toStringAsFixed(4)},${pitch.toStringAsFixed(4)},${yaw.toStringAsFixed(4)}';
}
