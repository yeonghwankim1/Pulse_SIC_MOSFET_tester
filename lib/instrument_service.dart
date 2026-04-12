import 'package:flutter/services.dart';

// 장치 제어와 직접 연결되는 서비스 계층이다.
// 네이티브 MethodChannel 통신, VISA 리소스 조회, 실행 설정 모델을 이 파일에서 관리한다.
// 실제 스윕 실행에 필요한 설정값을 한 묶음으로 관리한다.
class PulseTestConfig {
  const PulseTestConfig({
    required this.port,
    required this.transport,
    required this.periodUs,
    required this.voltageStart,
    required this.voltageEnd,
    required this.voltageStep,
    required this.onTimeSeconds,
    required this.offTimeSeconds,
    required this.dutyRatio,
    this.drainTarget,
    this.drainTransport,
    this.drainVoltage,
    this.drainCurrentLimitAmps,
    this.syncDrainWithGateTiming = false,
    this.currentMeasureDelaySeconds,
    this.currentTarget,
    this.currentTransport,
    this.measureDrainCurrentOnTime = false,
    this.voltageDropProtect = false,
    this.voltageDropThresholdVolts,
  });

  static const defaults = PulseTestConfig(
    port: 'COM5',
    transport: CommTransport.serial,
    periodUs: 10.0,
    voltageStart: 1.0,
    voltageEnd: 5.0,
    voltageStep: 0.1,
    onTimeSeconds: 2.0,
    offTimeSeconds: 1.0,
    dutyRatio: 0.5,
  );

  final String port;
  final CommTransport transport;
  final double periodUs;
  final double voltageStart;
  final double voltageEnd;
  final double voltageStep;
  final double onTimeSeconds;
  final double offTimeSeconds;
  final double dutyRatio;
  final String? drainTarget;
  final CommTransport? drainTransport;
  final double? drainVoltage;
  final double? drainCurrentLimitAmps;
  final bool syncDrainWithGateTiming;
  final double? currentMeasureDelaySeconds;
  final String? currentTarget;
  final CommTransport? currentTransport;
  final bool measureDrainCurrentOnTime;
  final bool voltageDropProtect;
  final double? voltageDropThresholdVolts;

  double get frequencyHz => 1000000.0 / periodUs;
  double get dutyPercent => dutyRatio * 100.0;

  // 실행 전에 잘못된 입력값이 없는지 확인한다.
  void validate() {
    if (port.isEmpty) throw ValidationException('${transport.targetLabel} is required.');
    if (periodUs <= 0) throw const ValidationException('Period must be greater than 0.');
    if (voltageStep <= 0) throw const ValidationException('Voltage step must be greater than 0.');
    if (voltageEnd < voltageStart) {
      throw const ValidationException('Voltage end must be greater than or equal to voltage start.');
    }
    if (onTimeSeconds < 0 || offTimeSeconds < 0) {
      throw const ValidationException('On/Off time cannot be negative.');
    }
    if (currentMeasureDelaySeconds != null &&
        currentMeasureDelaySeconds! > onTimeSeconds) {
      throw const ValidationException('Current measure delay cannot exceed On-Time.');
    }
    if (drainCurrentLimitAmps != null && drainCurrentLimitAmps! <= 0) {
      throw const ValidationException('Drain current limit must be greater than 0.');
    }
    if (voltageDropThresholdVolts != null && voltageDropThresholdVolts! < 0) {
      throw const ValidationException('Drop threshold cannot be negative.');
    }
    if (dutyRatio <= 0 || dutyRatio >= 1) {
      throw const ValidationException('Duty ratio must be between 0 and 1.');
    }
  }

  List<double> buildVoltagePoints() {
    validate();
    final points = <double>[];
    final epsilon = voltageStep / 1000.0;
    var current = voltageStart;
    while (current <= voltageEnd + epsilon) {
      points.add(current > voltageEnd ? voltageEnd : current);
      current += voltageStep;
    }
    return points;
  }
}

// UI 폼 검증이나 실행 전 검증 실패를 사용자에게 전달할 때 사용한다.
class ValidationException implements Exception {
  const ValidationException(this.message);
  final String message;

  @override
  String toString() => message;
}

// Flutter와 Windows 네이티브 계측기 제어 코드 사이의 MethodChannel 브리지다.
class NativeInstrumentBridge {
  static const MethodChannel _channel = MethodChannel('sic_mosfet/native_control');

  // 현재 PC에서 접근 가능한 VISA 리소스 목록을 가져온다.
  Future<List<String>> listResources() async {
    final response = await _channel.invokeListMethod<Object?>('listResources');
    return (response ?? const <Object?>[]).map((item) => item.toString()).toList();
  }

  // 특정 VISA 리소스에 *IDN?를 보내 장비 식별 문자열을 읽는다.
  Future<String> queryIdn({required String resource}) async {
    final response = await _channel.invokeMapMethod<Object?, Object?>(
      'queryIdn',
      <String, Object?>{'resource': resource},
    );
    return (response?['idn'] ?? '').toString();
  }

  Future<void> startResourceScan() async {
    await _channel.invokeMapMethod<Object?, Object?>('startResourceScan');
  }

  Future<ResourceScanResult> fetchResourceScan() async {
    final response = await _channel.invokeMapMethod<Object?, Object?>('fetchResourceScan');
    return ResourceScanResult.fromMap(response ?? const <Object?, Object?>{});
  }

  Future<RaspberryFrameResult> receiveRaspberryFrame({
    required String host,
    required int port,
    required int timeoutMs,
  }) async {
    final response = await _channel.invokeMapMethod<Object?, Object?>(
      'receiveRaspberryFrame',
      <String, Object?>{
        'host': host,
        'port': port,
        'timeoutMs': timeoutMs,
      },
    );
    return RaspberryFrameResult.fromMap(response ?? const <Object?, Object?>{});
  }

  // 선택한 transport/target으로 연결 확인용 핸드셰이크를 수행한다.
  Future<BridgeResult> identify({
    required String target,
    required CommTransport transport,
  }) async {
    final response = await _channel.invokeMapMethod<Object?, Object?>(
      'identify',
      <String, Object?>{
        'transportType': transport.nativeValue,
        'target': target,
      },
    );
    return BridgeResult.fromMap(response ?? const <Object?, Object?>{});
  }

  // 스윕 실행 요청을 네이티브 쪽으로 전달한다.
  Future<BridgeResult> startSweep({required PulseTestConfig config}) async {
    final response = await _channel.invokeMapMethod<Object?, Object?>(
      'startSweep',
      <String, Object?>{
        'transportType': config.transport.nativeValue,
        'target': config.port,
        'periodUs': config.periodUs,
        'voltageStart': config.voltageStart,
        'voltageEnd': config.voltageEnd,
        'voltageStep': config.voltageStep,
        'onTimeSeconds': config.onTimeSeconds,
        'offTimeSeconds': config.offTimeSeconds,
        'dutyRatio': config.dutyRatio,
        if (config.drainTarget != null && config.drainTarget!.isNotEmpty)
          'drainTarget': config.drainTarget,
        if (config.drainTransport != null)
          'drainTransportType': config.drainTransport!.nativeValue,
        if (config.drainVoltage != null) 'drainVoltage': config.drainVoltage,
        if (config.drainCurrentLimitAmps != null)
          'drainCurrentLimitAmps': config.drainCurrentLimitAmps,
        'syncDrainWithGateTiming': config.syncDrainWithGateTiming,
        if (config.currentMeasureDelaySeconds != null)
          'currentMeasureDelaySeconds': config.currentMeasureDelaySeconds,
        if (config.currentTarget != null && config.currentTarget!.isNotEmpty)
          'currentTarget': config.currentTarget,
        if (config.currentTransport != null)
          'currentTransportType': config.currentTransport!.nativeValue,
        'measureDrainCurrentOnTime': config.measureDrainCurrentOnTime,
        'voltageDropProtect': config.voltageDropProtect,
        if (config.voltageDropThresholdVolts != null)
          'voltageDropThresholdVolts': config.voltageDropThresholdVolts,
      },
    );
    return BridgeResult.fromMap(response ?? const <Object?, Object?>{});
  }

  Future<void> stopSweep() => _channel.invokeMethod<void>('stopSweep');

  // 백그라운드 스윕 실행 로그와 동작 상태를 주기적으로 가져온다.
  Future<LogPollResult> fetchLogs() async {
    final response = await _channel.invokeMapMethod<Object?, Object?>('fetchLogs');
    return LogPollResult.fromMap(response ?? const <Object?, Object?>{});
  }

  void dispose() {}
}

// identify/startSweep 같은 단발성 명령의 공통 응답 형식이다.
class BridgeResult {
  const BridgeResult({
    required this.success,
    required this.summary,
    required this.logs,
  });

  factory BridgeResult.fromMap(Map<Object?, Object?> map) {
    return BridgeResult(
      success: map['success'] == true,
      summary: (map['summary'] ?? '').toString(),
      logs: _bridgeLogsFromDynamic(map['logs']),
    );
  }

  final bool success;
  final String summary;
  final List<BridgeLog> logs;
}

// 실행 중 주기적으로 가져오는 로그 응답 형식이다.
class LogPollResult {
  const LogPollResult({
    required this.running,
    required this.logs,
  });

  factory LogPollResult.fromMap(Map<Object?, Object?> map) {
    return LogPollResult(
      running: map['running'] == true,
      logs: _bridgeLogsFromDynamic(map['logs']),
    );
  }

  final bool running;
  final List<BridgeLog> logs;
}

class ResourceScanResult {
  const ResourceScanResult({
    required this.running,
    required this.resources,
    required this.resourceToName,
    required this.error,
  });

  factory ResourceScanResult.fromMap(Map<Object?, Object?> map) {
    final rawResources = map['resources'];
    final resources = rawResources is List<Object?>
        ? rawResources.map((item) => item.toString()).toList()
        : const <String>[];

    final resourceToName = <String, String>{};
    final rawNames = map['names'];
    if (rawNames is List<Object?>) {
      for (final item in rawNames.whereType<Map<Object?, Object?>>()) {
        final resource = (item['resource'] ?? '').toString();
        if (resource.isEmpty) {
          continue;
        }
        resourceToName[resource] = (item['name'] ?? resource).toString();
      }
    }

    return ResourceScanResult(
      running: map['running'] == true,
      resources: resources,
      resourceToName: resourceToName,
      error: (map['error'] ?? '').toString(),
    );
  }

  final bool running;
  final List<String> resources;
  final Map<String, String> resourceToName;
  final String error;
}

class RaspberryFrameResult {
  const RaspberryFrameResult({
    required this.remoteAddress,
    required this.remotePort,
    required this.debugStatus,
    required this.timeStr,
    required this.frameId,
    required this.rows,
    required this.cols,
    required this.payloadBytes,
    required this.valueCount,
    required this.minValue,
    required this.maxValue,
    required this.meanValue,
    required this.centerValue,
    required this.values,
  });

  factory RaspberryFrameResult.fromMap(Map<Object?, Object?> map) {
    final rawValues = map['values'];
    final values = rawValues is List<Object?>
        ? rawValues.map((item) => (item as num).toDouble()).toList()
        : const <double>[];
    return RaspberryFrameResult(
      remoteAddress: (map['remoteAddress'] ?? '').toString(),
      remotePort: (map['remotePort'] as num?)?.toInt() ?? 0,
      debugStatus: (map['debugStatus'] ?? '').toString(),
      timeStr: (map['timeStr'] ?? '').toString(),
      frameId: (map['frameId'] ?? '').toString(),
      rows: (map['rows'] as num?)?.toInt() ?? 0,
      cols: (map['cols'] as num?)?.toInt() ?? 0,
      payloadBytes: (map['payloadBytes'] as num?)?.toInt() ?? 0,
      valueCount: (map['valueCount'] as num?)?.toInt() ?? 0,
      minValue: (map['min'] as num?)?.toDouble() ?? 0,
      maxValue: (map['max'] as num?)?.toDouble() ?? 0,
      meanValue: (map['mean'] as num?)?.toDouble() ?? 0,
      centerValue: (map['center'] as num?)?.toDouble() ?? 0,
      values: values,
    );
  }

  final String remoteAddress;
  final int remotePort;
  final String debugStatus;
  final String timeStr;
  final String frameId;
  final int rows;
  final int cols;
  final int payloadBytes;
  final int valueCount;
  final double minValue;
  final double maxValue;
  final double meanValue;
  final double centerValue;
  final List<double> values;
}

// 네이티브 계층에서 올라온 개별 로그 한 줄이다.
class BridgeLog {
  const BridgeLog({
    required this.level,
    required this.message,
  });

  final String level;
  final String message;
}

// MethodChannel에서 받은 동적 로그 배열을 Dart 객체 리스트로 변환한다.
List<BridgeLog> _bridgeLogsFromDynamic(Object? raw) {
  if (raw is! List<Object?>) {
    return const <BridgeLog>[];
  }
  return raw.whereType<Map<Object?, Object?>>().map((item) {
    return BridgeLog(
      level: (item['level'] ?? 'info').toString(),
      message: (item['message'] ?? '').toString(),
    );
  }).toList();
}

// UI에서 선택할 수 있는 계측기 종류와 기본 연결값을 정의한다.
enum TestInstrument {
  afg2225(
    label: 'GW Instek AFG-2225',
    supportedTransports: <CommTransport>[
      CommTransport.serial,
      CommTransport.visa,
    ],
    defaultPort: 'COM5',
    defaultVisaResource: 'USB0::0x0000::0x0000::INSTR',
    defaultTcpEndpoint: '192.168.0.10:5025',
    description: 'Connected to the real Windows native serial driver.',
    connectionHint: 'SCPI *IDN? over serial',
  ),
  oscilloscope(
    label: 'Oscilloscope',
    supportedTransports: <CommTransport>[
      CommTransport.visa,
    ],
    defaultPort: 'COM6',
    defaultVisaResource: 'TCPIP0::192.168.0.20::inst0::INSTR',
    defaultTcpEndpoint: '192.168.0.20:5025',
    description: 'Reserved slot for a future scope driver.',
    connectionHint: 'Not implemented',
  ),
  custom(
    label: 'Custom Instrument',
    supportedTransports: <CommTransport>[
      CommTransport.serial,
      CommTransport.visa,
    ],
    defaultPort: 'COM7',
    defaultVisaResource: 'USB0::CUSTOM::INSTR',
    defaultTcpEndpoint: '127.0.0.1:5025',
    description: 'Reserved slot for a custom device.',
    connectionHint: 'Not implemented',
  ),
  currentMeter(
    label: 'Current Measurement',
    supportedTransports: <CommTransport>[
      CommTransport.serial,
      CommTransport.visa,
    ],
    defaultPort: 'COM8',
    defaultVisaResource: 'USB0::CURRENT::INSTR',
    defaultTcpEndpoint: '127.0.0.1:5025',
    description: 'Current measurement instrument slot.',
    connectionHint: 'Not implemented',
  );

  const TestInstrument({
    required this.label,
    required this.supportedTransports,
    required this.defaultPort,
    required this.defaultVisaResource,
    required this.defaultTcpEndpoint,
    required this.description,
    required this.connectionHint,
  });

  final String label;
  final List<CommTransport> supportedTransports;
  final String defaultPort;
  final String defaultVisaResource;
  final String defaultTcpEndpoint;
  final String description;
  final String connectionHint;
}

// 네이티브 코드에 전달할 통신 방식과 기본 타깃 표기를 정의한다.
enum CommTransport {
  serial('Serial SCPI', 'serial', 'Serial Port'),
  visa('VISA SCPI', 'visa', 'VISA Resource'),
  tcp('TCP Socket', 'tcp', 'TCP Host:Port');

  const CommTransport(this.label, this.nativeValue, this.targetLabel);

  final String label;
  final String nativeValue;
  final String targetLabel;

  String defaultTarget(TestInstrument instrument) {
    switch (this) {
      case CommTransport.serial:
        return instrument.defaultPort;
      case CommTransport.visa:
        return instrument.defaultVisaResource;
      case CommTransport.tcp:
        return instrument.defaultTcpEndpoint;
    }
  }
}
