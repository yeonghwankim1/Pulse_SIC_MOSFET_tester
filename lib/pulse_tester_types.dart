import 'package:flutter/material.dart';

import 'instrument_service.dart';

// UI에서 공통으로 사용하는 enum과 로그 모델을 모아 둔 파일이다.
// 화면 상태 표시, 역할 구분, 실행 로그 표현처럼 여러 위젯에서 함께 쓰는 타입을 여기서 관리한다.
enum DeviceRole {
  drain('Drain'),
  gate('Gate');

  const DeviceRole(this.label);
  final String label;
}

enum GateMeasurementMode {
  dc('DC'),
  pulse('PULSE');

  const GateMeasurementMode(this.label);
  final String label;
}

enum MeasurementSweepMode {
  idVgs('Id-Vgs'),
  hysteresis('Hysteresis'),
  idVds('Id-Vds'),
  realtime('Real-time');

  const MeasurementSweepMode(this.label);
  final String label;
}

enum PulseDeviceRole {
  generator('Function Generator'),
  oscilloscope('Oscilloscope'),
  current('Current Measurement');

  const PulseDeviceRole(this.label);
  final String label;
}

enum ConnectionStateView {
  idle(Icons.radio_button_unchecked_rounded, Color(0xFF6B7280), 'Not Checked'),
  checking(Icons.sync_rounded, Color(0xFF2563EB), 'Checking'),
  connected(Icons.usb_rounded, Color(0xFF0B6E4F), 'Connected'),
  rechecked(Icons.autorenew_rounded, Color(0xFFB26A00), 'Checked Again'),
  failed(Icons.error_outline_rounded, Color(0xFFB42318), 'Check Failed');

  const ConnectionStateView(this.icon, this.color, this.label);
  final IconData icon;
  final Color color;
  final String label;
  ConnectionStateView get presentation => this;
}

enum LogLevel {
  info(Icons.bolt_rounded, Color(0xFF0B6E4F)),
  warning(Icons.warning_amber_rounded, Color(0xFFB26A00)),
  error(Icons.error_outline_rounded, Color(0xFFB42318));

  const LogLevel(this.icon, this.color);
  final IconData icon;
  final Color color;
}

class LogEntry {
  const LogEntry({required this.message, required this.level, required this.timestamp});
  LogEntry.info(String m) : this(message: m, level: LogLevel.info, timestamp: DateTime.now());
  LogEntry.warning(String m) : this(message: m, level: LogLevel.warning, timestamp: DateTime.now());
  LogEntry.error(String m) : this(message: m, level: LogLevel.error, timestamp: DateTime.now());

  factory LogEntry.fromBridge(BridgeLog log) {
    switch (log.level) {
      case 'warning':
        return LogEntry.warning(log.message);
      case 'error':
        return LogEntry.error(log.message);
      default:
        return LogEntry.info(log.message);
    }
  }

  final String message;
  final LogLevel level;
  final DateTime timestamp;

  String get timestampLabel {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
