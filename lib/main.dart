import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'instrument_selection_controller.dart';
import 'instrument_selection_panel.dart';
import 'instrument_service.dart';
import 'pulse_tester_types.dart';
import 'pulse_tester_widgets.dart';

// 앱의 최상위 진입점이다.
// 이 파일은 페이지의 큰 화면 배치와 상태 관리, 각 패널에 데이터와 콜백을 연결하는 역할을 담당한다.
void main() => runApp(const PulseTesterApp());

class PulseTesterApp extends StatelessWidget {
  const PulseTesterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SiC MOSFET Pulse Tester',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0B6E4F),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF3F0E8),
        useMaterial3: true,
      ),
      home: const PulseTesterPage(),
    );
  }
}

class PulseTesterPage extends StatefulWidget {
  const PulseTesterPage({super.key});

  @override
  State<PulseTesterPage> createState() => _PulseTesterPageState();
}

class _PulseTesterPageState extends State<PulseTesterPage> {
  static const MethodChannel _nativeChannel = MethodChannel('sic_mosfet/native_control');
  final _formKey = GlobalKey<FormState>();
  final _bridge = NativeInstrumentBridge();
  late final InstrumentSelectionController _selection;
  final _logs = <LogEntry>[];
  late final TextEditingController _port;
  late final TextEditingController _periodUs;
  late final TextEditingController _vStart;
  late final TextEditingController _vEnd;
  late final TextEditingController _vStep;
  late final TextEditingController _drainVFixed;
  late final TextEditingController _drainILimit;
  late final TextEditingController _gateILimit;
  late final TextEditingController _gateStartV;
  late final TextEditingController _gateStopV;
  late final TextEditingController _gateStepV;
  late final TextEditingController _onTime;
  late final TextEditingController _offTime;
  late final TextEditingController _currentMeasureDelay;
  late final TextEditingController _duty;
  late final TextEditingController _repeatWaitMs;
  late final TextEditingController _idVgsRepeat;
  late final TextEditingController _idVdsRepeat;
  late final TextEditingController _voltageDropThreshold;
  late final TextEditingController _realtimeDrainV;
  late final TextEditingController _realtimeGateV;
  late final TextEditingController _realtimeDurationSec;
  late final TextEditingController _realtimeIntervalMs;
  late final TextEditingController _realtimeDrainRange;
  late final TextEditingController _raspberryHost;
  late final TextEditingController _raspberryPort;
  late final TextEditingController _directLinkIp;
  bool _running = false;
  MeasurementSweepMode _measurementSweepMode = MeasurementSweepMode.idVgs;
  bool _repeatEnabled = false;
  bool _voltageDropProtect = true;
  bool _realtimeDrainRangeAuto = true;
  bool _realtimeMeasureVoltage = false;
  bool _realtimeRunUntilStopped = false;
  bool _thermalCameraEnabled = true;
  bool _isRaspberryStreaming = false;
  bool _isReceivingRaspberry = false;
  bool _isDirectLinkBusy = false;
  bool _directLinkModeEnabled = false;
  int _raspberryStreamToken = 0;
  String _raspberryResult = 'No Raspberry frame received yet.';
  List<double> _raspberryFrameValues = <double>[];
  int _raspberryFrameRows = 0;
  int _raspberryFrameCols = 0;
  List<String> _ethernetAdapters = <String>[];
  String? _selectedEthernetAdapter;
  Timer? _logPoller;
  static const int _thermalCameraTimeoutMs = 10000;

  @override
  void initState() {
    super.initState();
    _selection = InstrumentSelectionController(_bridge);
    final d = PulseTestConfig.defaults;
    _port = TextEditingController(text: d.port);
    _periodUs = TextEditingController(text: '${d.periodUs}');
    _vStart = TextEditingController(text: '${d.voltageStart}');
    _vEnd = TextEditingController(text: '${d.voltageEnd}');
    _vStep = TextEditingController(text: '${d.voltageStep}');
    _drainVFixed = TextEditingController(text: '10.0');
    _drainILimit = TextEditingController(text: '1.0');
    _gateILimit = TextEditingController(text: '0.5');
    _gateStartV = TextEditingController(text: '0.0');
    _gateStopV = TextEditingController(text: '10.0');
    _gateStepV = TextEditingController(text: '1.0');
    _onTime = TextEditingController(text: '${d.onTimeSeconds}');
    _offTime = TextEditingController(text: '1.0');
    _currentMeasureDelay = TextEditingController(text: '0.05');
    _duty = TextEditingController(text: '${d.dutyRatio}');
    _repeatWaitMs = TextEditingController(text: '0');
    _idVgsRepeat = TextEditingController(text: '1');
    _idVdsRepeat = TextEditingController(text: '1');
    _voltageDropThreshold = TextEditingController(text: '1.0');
    _realtimeDrainV = TextEditingController(text: '10.0');
    _realtimeGateV = TextEditingController(text: '5.0');
    _realtimeDurationSec = TextEditingController(text: '10');
    _realtimeIntervalMs = TextEditingController(text: '200');
    _realtimeDrainRange = TextEditingController(text: '5.0');
    _raspberryHost = TextEditingController(text: '0.0.0.0');
    _raspberryPort = TextEditingController(text: '5001');
    _directLinkIp = TextEditingController(text: '192.168.50.1');
    unawaited(_refreshEthernetAdapters());
  }

  @override
  void dispose() {
    _logPoller?.cancel();
    _bridge.dispose();
    _port.dispose();
    _periodUs.dispose();
    _vStart.dispose();
    _vEnd.dispose();
    _vStep.dispose();
    _drainVFixed.dispose();
    _drainILimit.dispose();
    _gateILimit.dispose();
    _gateStartV.dispose();
    _gateStopV.dispose();
    _gateStepV.dispose();
    _onTime.dispose();
    _offTime.dispose();
    _currentMeasureDelay.dispose();
    _duty.dispose();
    _repeatWaitMs.dispose();
    _idVgsRepeat.dispose();
    _idVdsRepeat.dispose();
    _voltageDropThreshold.dispose();
    _realtimeDrainV.dispose();
    _realtimeGateV.dispose();
    _realtimeDurationSec.dispose();
    _realtimeIntervalMs.dispose();
    _realtimeDrainRange.dispose();
    _raspberryHost.dispose();
    _raspberryPort.dispose();
    _directLinkIp.dispose();
    super.dispose();
  }

  PulseTestConfig? get _preview {
    try {
      return _readConfig();
    } catch (_) {
      return null;
    }
  }

  PulseTestConfig _readConfig() {
    final activeTransport = _selection.activeGateTransport();
    final activeTarget = _selection.activeGateTarget(_port.text);
    final shouldSyncDrainWithGateTiming =
        _measurementSweepMode == MeasurementSweepMode.idVgs &&
        _selection.gateMeasurementMode == GateMeasurementMode.pulse;
    final drainTransport = shouldSyncDrainWithGateTiming
        ? _selection.transportFor(DeviceRole.drain)
        : null;
    final drainTarget = shouldSyncDrainWithGateTiming
        ? _selection.targetFor(DeviceRole.drain, _port.text)
        : null;
    final drainVoltage = shouldSyncDrainWithGateTiming
        ? _num(_drainVFixed.text, 'Drain V')
        : null;
    final shouldMeasureDrainCurrentOnTime =
        _measurementSweepMode == MeasurementSweepMode.idVgs &&
        _selection.gateMeasurementMode == GateMeasurementMode.pulse;
    final currentTransport = shouldMeasureDrainCurrentOnTime
        ? drainTransport
        : null;
    final currentTarget = shouldMeasureDrainCurrentOnTime
        ? drainTarget
        : null;
    final currentMeasureDelaySeconds = shouldMeasureDrainCurrentOnTime
        ? _num(_currentMeasureDelay.text, 'Current measure delay')
        : null;
    final config = PulseTestConfig(
      port: activeTarget,
      transport: activeTransport,
      periodUs: _num(_periodUs.text, 'Period'),
      voltageStart: _num(_vStart.text, 'Voltage start'),
      voltageEnd: _num(_vEnd.text, 'Voltage end'),
      voltageStep: _num(_vStep.text, 'Voltage step'),
      onTimeSeconds: _num(_onTime.text, 'On time'),
      offTimeSeconds: _num(_offTime.text, 'Off time'),
      dutyRatio: _num(_duty.text, 'Duty'),
      drainTarget: drainTarget,
      drainTransport: drainTransport,
      drainVoltage: drainVoltage,
      drainCurrentLimitAmps:
          shouldSyncDrainWithGateTiming ? _num(_drainILimit.text, 'Drain current limit') : null,
      syncDrainWithGateTiming: shouldSyncDrainWithGateTiming,
      currentMeasureDelaySeconds: currentMeasureDelaySeconds,
      currentTarget: currentTarget,
      currentTransport: currentTransport,
      measureDrainCurrentOnTime: shouldMeasureDrainCurrentOnTime,
      voltageDropProtect:
          _measurementSweepMode != MeasurementSweepMode.realtime && _voltageDropProtect,
      voltageDropThresholdVolts:
          _measurementSweepMode != MeasurementSweepMode.realtime
              ? _num(_voltageDropThreshold.text, 'Drop threshold')
              : null,
    );
    config.validate();
    return config;
  }

  double _num(String raw, String name) {
    final value = double.tryParse(raw.trim());
    if (value == null) {
      throw FormatException('$name must be numeric.');
    }
    return value;
  }

  String? _validator(String? value, {bool numeric = false}) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return 'Required';
    }
    if (numeric && double.tryParse(text) == null) {
      return 'Number only';
    }
    return null;
  }

  void _log(LogEntry entry) {
    if (!mounted) {
      return;
    }
    setState(() => _logs.insert(0, entry));
  }

  void _reset() {
    final d = PulseTestConfig.defaults;
    setState(() {
      _port.text = d.port;
      _selection.reset(_port.text);
      _periodUs.text = '${d.periodUs}';
      _vStart.text = '${d.voltageStart}';
      _vEnd.text = '${d.voltageEnd}';
      _vStep.text = '${d.voltageStep}';
      _drainVFixed.text = '10.0';
      _drainILimit.text = '1.0';
      _gateILimit.text = '0.5';
      _gateStartV.text = '0.0';
      _gateStopV.text = '10.0';
      _gateStepV.text = '1.0';
      _onTime.text = '${d.onTimeSeconds}';
      _offTime.text = '1.0';
      _currentMeasureDelay.text = '0.05';
      _duty.text = '${d.dutyRatio}';
      _repeatWaitMs.text = '0';
      _idVgsRepeat.text = '1';
      _idVdsRepeat.text = '1';
      _voltageDropThreshold.text = '1.0';
      _realtimeDrainV.text = '10.0';
      _realtimeGateV.text = '5.0';
      _realtimeDurationSec.text = '10';
      _realtimeIntervalMs.text = '200';
      _realtimeDrainRange.text = '5.0';
      _measurementSweepMode = MeasurementSweepMode.idVgs;
      _repeatEnabled = false;
      _voltageDropProtect = true;
      _realtimeDrainRangeAuto = true;
      _realtimeMeasureVoltage = false;
      _realtimeRunUntilStopped = false;
    });
  }

  Future<void> _checkConnection(DeviceRole role) async {
    final transport = _selection.transportFor(role);
    if (!_selection.canControl(role)) {
      _message('This instrument driver is not implemented yet.');
      return;
    }
    final target = _selection.targetFor(role, _port.text);
    if (target.isEmpty) {
      _message('${transport.targetLabel} is required.');
      return;
    }
    setState(() {
      if (role == DeviceRole.drain) {
        _selection.drainConnection = ConnectionStateView.checking;
        _selection.drainDetail = 'Running *IDN? handshake on $target via ${transport.label}';
      } else {
        _selection.gateConnection = ConnectionStateView.checking;
        _selection.gateDetail = 'Running *IDN? handshake on $target via ${transport.label}';
      }
    });
    try {
      await _selection.checkConnection(role, _port.text);
      if (!mounted) {
        return;
      }
      setState(() {});
    } catch (error) {
      setState(() {});
      _log(LogEntry.error('${role.label} connection check failed: $error'));
    }
  }

  Future<void> _startRun() async {
    final canRun = _selection.canRunGate();
    if (!canRun) {
      _message('This instrument driver is not implemented yet.');
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    try {
      final config = _readConfig();
      setState(() {
        _logs.clear();
        _running = true;
        _selection.gateConnection = ConnectionStateView.connected;
        _selection.gateDetail = 'Sweep started.';
      });
      final result = await _bridge.startSweep(config: config);
      _appendBridgeLogs(result.logs);
      if (!mounted) {
        return;
      }
      setState(() {
        _selection.gateDetail = result.summary;
        if (!result.success) {
          _running = false;
          _selection.gateConnection = ConnectionStateView.failed;
        }
      });
      if (result.success) {
        _startPollingLogs();
      }
    } on ValidationException catch (error) {
      if (mounted) {
        setState(() => _running = false);
      }
      _message(error.message);
    } catch (error) {
      if (mounted) {
        setState(() {
          _running = false;
          _selection.gateConnection = ConnectionStateView.failed;
        });
      }
      _log(LogEntry.error('Run failed: $error'));
      _message('Run failed: $error');
    }
  }

  void _stopRun() {
    _bridge.stopSweep();
    _log(LogEntry.warning('Stop requested. Waiting for hardware output off.'));
    setState(() {
      _selection.gateDetail = 'Stop requested.';
    });
  }

  void _startPollingLogs() {
    _logPoller?.cancel();
    _logPoller = Timer.periodic(const Duration(milliseconds: 200), (_) async {
      final update = await _bridge.fetchLogs();
      _appendBridgeLogs(update.logs);
      if (!update.running && mounted) {
        _logPoller?.cancel();
        setState(() {
          _running = false;
          if (_selection.gateDetail == 'Sweep started.') {
            _selection.gateDetail = 'Sweep finished.';
          }
        });
      }
    });
  }

  void _appendBridgeLogs(List<BridgeLog> logs) {
    for (final log in logs) {
      _log(LogEntry.fromBridge(log));
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _refreshEthernetAdapters() async {
    try {
      final result = await _nativeChannel.invokeMethod<List<dynamic>>('listEthernetAdapters');
      final adapters = (result ?? <dynamic>[]).map((e) => '$e').toList();
      if (!mounted) {
        return;
      }
      setState(() {
        _ethernetAdapters = adapters;
        if (adapters.isEmpty) {
          _selectedEthernetAdapter = null;
          _directLinkModeEnabled = false;
        } else if (!adapters.contains(_selectedEthernetAdapter)) {
          _selectedEthernetAdapter = adapters.first;
        }
      });
    } on PlatformException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _ethernetAdapters = <String>[];
        _selectedEthernetAdapter = null;
        _directLinkModeEnabled = false;
      });
      _log(LogEntry.error('Ethernet adapter list failed: ${error.message ?? error.code}'));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _ethernetAdapters = <String>[];
        _selectedEthernetAdapter = null;
        _directLinkModeEnabled = false;
      });
      _log(LogEntry.error('Ethernet adapter list failed: $error'));
    }
  }

  Future<void> _toggleDirectLinkMode() async {
    final adapterName = _selectedEthernetAdapter;
    if (_isDirectLinkBusy || adapterName == null || adapterName.isEmpty) {
      return;
    }

    setState(() {
      _isDirectLinkBusy = true;
    });

    try {
      if (_directLinkModeEnabled) {
        await _nativeChannel.invokeMethod<void>('restoreDirectLinkMode', {
          'adapterName': adapterName,
        });
        if (!mounted) {
          return;
        }
        setState(() {
          _directLinkModeEnabled = false;
        });
        _log(LogEntry.info('Direct link mode disabled on $adapterName.'));
      } else {
        final directIp = _directLinkIp.text.trim().isEmpty ? '192.168.50.1' : _directLinkIp.text.trim();
        await _nativeChannel.invokeMethod<void>('configureDirectLinkMode', {
          'adapterName': adapterName,
          'ipAddress': directIp,
          'prefixLength': 24,
        });
        if (!mounted) {
          return;
        }
        setState(() {
          _directLinkModeEnabled = true;
          _raspberryHost.text = '0.0.0.0';
          _raspberryPort.text = '5001';
        });
        _log(LogEntry.info('Direct link mode enabled on $adapterName with $directIp.'));
      }
    } on PlatformException catch (error) {
      if (!mounted) {
        return;
      }
      final message = error.message ?? error.code;
      _message(message);
      _log(LogEntry.error('Direct link mode failed: $message'));
    } catch (error) {
      if (!mounted) {
        return;
      }
      _message('Direct link mode failed: $error');
      _log(LogEntry.error('Direct link mode failed: $error'));
    } finally {
      if (!mounted) {
        return;
      }
      setState(() {
        _isDirectLinkBusy = false;
      });
    }
  }

  bool get _isThermalBusy => _isReceivingRaspberry || _isRaspberryStreaming;

  String _resourceLabel(String resource) {
    return _selection.resourceLabel(resource);
  }

  String _pulseTargetFor(PulseDeviceRole role) {
    return _selection.pulseTargetFor(role, _port.text);
  }

  void _onTransportChanged(DeviceRole role, CommTransport? value) {
    setState(() {
      _selection.onTransportChanged(role, value, _port.text);
      if (value != null && value != CommTransport.visa && role == DeviceRole.gate) {
        _port.text = value.defaultTarget(_selection.instrumentFor(role));
      }
    });
    if (value == CommTransport.visa && _selection.resources.isEmpty) {
      unawaited(_listResources());
    }
  }

  void _onInstrumentChanged(DeviceRole role, TestInstrument? value) {
    setState(() {
      _selection.onInstrumentChanged(role, value);
      if (value != null && _selection.transportFor(role) != CommTransport.visa && role == DeviceRole.gate) {
        _port.text = _selection.transportFor(role).defaultTarget(value);
      }
    });
  }

  void _onPulseTransportChanged(PulseDeviceRole role, CommTransport? value) {
    setState(() {
      _selection.onPulseTransportChanged(role, value, _port.text);
      if (value != null && value != CommTransport.visa && role == PulseDeviceRole.generator) {
        _port.text = value.defaultTarget(_selection.pulseInstrumentFor(role));
      }
    });
    if (value == CommTransport.visa && _selection.resources.isEmpty) {
      unawaited(_listResources());
    }
  }

  void _onPulseInstrumentChanged(PulseDeviceRole role, TestInstrument? value) {
    setState(() {
      _selection.onPulseInstrumentChanged(role, value);
      if (value != null &&
          _selection.pulseTransportFor(role) != CommTransport.visa &&
          role == PulseDeviceRole.generator) {
        _port.text = _selection.pulseTransportFor(role).defaultTarget(value);
      }
    });
  }

  String _activeGateInstrumentLabel() {
    return _selection.activeGateInstrumentLabel();
  }

  Future<void> _checkPulseConnection(PulseDeviceRole role) async {
    final transport = _selection.pulseTransportFor(role);
    final instrument = _selection.pulseInstrumentFor(role);
    final target = _pulseTargetFor(role);
    final canControl = transport == CommTransport.visa || instrument == TestInstrument.afg2225;
    if (!canControl) {
      _message('This instrument driver is not implemented yet.');
      return;
    }
    if (target.isEmpty) {
      _message('${transport.targetLabel} is required.');
      return;
    }
    setState(() {
      _selection.setPulseConnection(role, ConnectionStateView.checking);
      _selection.setPulseDetail(role, 'Running *IDN? handshake on $target via ${transport.label}');
    });
    try {
      await _selection.checkPulseConnection(role, _port.text);
      if (!mounted) {
        return;
      }
      setState(() {});
    } catch (error) {
      setState(() {});
      _log(LogEntry.error('${role.label} connection check failed: $error'));
    }
  }

  String _extractDeviceName(String idn) {
    final parts = idn.split(',');
    if (parts.length >= 2) {
      final maker = parts[0].trim();
      final model = parts[1].trim();
      if (maker.isNotEmpty && model.isNotEmpty) {
        return '$maker $model';
      }
      if (model.isNotEmpty) {
        return model;
      }
    }
    return idn.trim();
  }

  Future<void> _listResources() async {
    setState(() {
      _selection.loadingResources = true;
    });
    try {
      await _bridge.startResourceScan();
      var announced = false;
      while (mounted) {
        final update = await _bridge.fetchResourceScan();
        if (!mounted) {
          return;
        }
        setState(() {
          _selection.applyResourceScan(update, _port.text, _extractDeviceName);
        });
        if (!announced && update.resources.isNotEmpty) {
          _log(LogEntry.info('Found ${update.resources.length} VISA resource(s).'));
          announced = true;
        }
        if (update.error.isNotEmpty) {
          throw Exception(update.error);
        }
        if (!update.running) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    } catch (error) {
      _log(LogEntry.error('VISA resource scan failed: $error'));
      _message('VISA resource scan failed: $error');
      if (mounted) {
        setState(() {
          _selection.loadingResources = false;
        });
      }
    }
  }

  Future<bool> _receiveRaspberryFrame() async {
    final streamToken = _raspberryStreamToken;
    final host = _raspberryHost.text.trim().isEmpty ? '0.0.0.0' : _raspberryHost.text.trim();
    final port = int.tryParse(_raspberryPort.text.trim());
    if (port == null || port <= 0 || port > 65535) {
      _message('Invalid Raspberry port.');
      return false;
    }

    setState(() {
      _isReceivingRaspberry = true;
      if (_raspberryFrameValues.isEmpty) {
        _raspberryResult = 'Waiting for Raspberry frame on $host:$port...';
      }
    });

    try {
      final result = await _bridge.receiveRaspberryFrame(
        host: host,
        port: port,
        timeoutMs: _thermalCameraTimeoutMs,
      );
      if (!mounted || streamToken != _raspberryStreamToken) {
        return false;
      }
      setState(() {
        _raspberryFrameValues = result.values;
        _raspberryFrameRows = result.rows;
        _raspberryFrameCols = result.cols;
        _raspberryResult = [
          'Remote: ${result.remoteAddress}:${result.remotePort}',
          'Debug: ${result.debugStatus}',
          if (result.timeStr.isNotEmpty) 'Time: ${result.timeStr}',
          if (result.frameId.isNotEmpty) 'Frame ID: ${result.frameId}',
          'Shape: ${result.rows} x ${result.cols}',
          'Min: ${result.minValue.toStringAsFixed(2)}',
          'Max: ${result.maxValue.toStringAsFixed(2)}',
          'Mean: ${result.meanValue.toStringAsFixed(2)}',
          'Center: ${result.centerValue.toStringAsFixed(2)}',
        ].join('\n');
      });
      return true;
    } on PlatformException catch (error) {
      if (!mounted || streamToken != _raspberryStreamToken) {
        return false;
      }
      setState(() {
        _raspberryResult = 'Receive failed: ${error.message ?? error.code}';
      });
      return false;
    } catch (error) {
      if (!mounted || streamToken != _raspberryStreamToken) {
        return false;
      }
      setState(() {
        _raspberryResult = 'Receive failed: $error';
      });
      return false;
    } finally {
      if (mounted && streamToken == _raspberryStreamToken) {
        setState(() {
          _isReceivingRaspberry = false;
        });
      }
    }
  }

  Future<void> _toggleRaspberryStream() async {
    if (_isRaspberryStreaming) {
      _raspberryStreamToken++;
      setState(() {
        _isRaspberryStreaming = false;
        _raspberryResult = 'Raspberry stream stopped.';
      });
      return;
    }

    final streamToken = ++_raspberryStreamToken;
    setState(() {
      _isRaspberryStreaming = true;
      _raspberryResult = 'Starting Raspberry live stream...';
    });

    while (mounted && streamToken == _raspberryStreamToken && _isRaspberryStreaming) {
      final ok = await _receiveRaspberryFrame();
      if (!mounted || streamToken != _raspberryStreamToken || !_isRaspberryStreaming) {
        break;
      }
      await Future<void>.delayed(Duration(milliseconds: ok ? 60 : 500));
    }

    if (mounted && streamToken == _raspberryStreamToken) {
      setState(() {
        _isRaspberryStreaming = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SiC MOSFET Pulse Tester')),
      body: LayoutBuilder(
        builder: (context, c) {
          final content = _setupCard();
          final lowerContent = c.maxWidth >= 1100
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _logCard()),
                    const SizedBox(width: 20),
                    SizedBox(width: 360, child: _thermalViewCard()),
                  ],
                )
              : Column(
                  children: [
                    _logCard(),
                    const SizedBox(height: 20),
                    _thermalViewCard(),
                  ],
                );
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _instrumentCard(),
                const SizedBox(height: 20),
                _thermalConfigCard(),
                const SizedBox(height: 20),
                content,
                const SizedBox(height: 20),
                lowerContent,
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _thermalConfigCard() {
    return ThermalCameraConfigCard(
      enabled: _thermalCameraEnabled,
      busy: _isThermalBusy,
      streaming: _isRaspberryStreaming,
      leadingFields: [
        SizedBox(
          width: 220,
          child: DropdownButtonFormField<String>(
            value: _selectedEthernetAdapter,
            items: _ethernetAdapters
                .map(
                  (adapter) => DropdownMenuItem<String>(
                    value: adapter,
                    child: Text(adapter, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: _isDirectLinkBusy
                ? null
                : (value) {
                    setState(() {
                      _selectedEthernetAdapter = value;
                    });
                  },
            decoration: const InputDecoration(
              labelText: 'Direct Link Adapter',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        SizedBox(
          width: 140,
          child: TextField(
            controller: _directLinkIp,
            enabled: !_isDirectLinkBusy,
            decoration: const InputDecoration(
              labelText: 'PC Direct IP',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        SizedBox(
          width: 170,
          height: 40,
          child: FilledButton.tonal(
            onPressed: _selectedEthernetAdapter == null ? null : _toggleDirectLinkMode,
            child: Text(_directLinkModeEnabled ? 'Disable Direct Link' : 'Enable Direct Link'),
          ),
        ),
        SizedBox(
          width: 120,
          height: 40,
          child: OutlinedButton(
            onPressed: _isDirectLinkBusy ? null : _refreshEthernetAdapters,
            child: const Text('Refresh NICs'),
          ),
        ),
      ],
      onEnabledChanged: (value) {
        setState(() {
          _thermalCameraEnabled = value;
        });
        if (!value && _isRaspberryStreaming) {
          unawaited(_toggleRaspberryStream());
        }
      },
      onToggleStream: _toggleRaspberryStream,
      hostField: TextField(
        controller: _raspberryHost,
        enabled: _thermalCameraEnabled && !_isThermalBusy,
        decoration: const InputDecoration(
          labelText: 'Raspberry IP / Bind Host',
          border: OutlineInputBorder(),
        ),
      ),
      portField: TextField(
        controller: _raspberryPort,
        enabled: _thermalCameraEnabled && !_isThermalBusy,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'Port',
          border: OutlineInputBorder(),
        ),
      ),
      footer: const Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Direct link mode sets the selected Ethernet adapter to a fixed IPv4 for the Pi cable. Run the app as administrator if this fails.',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
      ),
    );
  }

  Widget _instrumentCard() {
    return InstrumentSelectionPanel(
      running: _running,
      loadingResources: _selection.loadingResources,
      resources: _selection.resources,
      resourceToDeviceName: _selection.resourceToDeviceName,
      gateMeasurementMode: _selection.gateMeasurementMode,
      drainState: _selection.drainState,
      gateState: _selection.gateState,
      generatorState: _selection.generatorState,
      scopeState: _selection.scopeState,
      currentState: _selection.currentState,
      onGateModeChanged: (mode) {
        setState(() {
          _selection.setGateMode(mode);
        });
      },
      onTransportChanged: _onTransportChanged,
      onInstrumentChanged: _onInstrumentChanged,
      onCheckConnection: _checkConnection,
      onReloadResources: _listResources,
      onVisaResourceChanged: (role, value) {
        setState(() {
          _selection.onVisaResourceChanged(role, value);
          if (role == DeviceRole.gate) {
            _port.text = value;
          }
        });
      },
      onPulseTransportChanged: _onPulseTransportChanged,
      onPulseInstrumentChanged: _onPulseInstrumentChanged,
      onPulseCheckConnection: _checkPulseConnection,
      onPulseVisaResourceChanged: (role, value) {
        setState(() {
          _selection.onPulseVisaResourceChanged(role, value);
        });
      },
    );
  }

  Widget _setupCard() {
    final gatePathLabel = _selection.gateMeasurementMode == GateMeasurementMode.pulse
        ? 'Function Generator'
        : 'Gate channel';
    return Form(
      key: _formKey,
      child: SweepSetupCard(
        description: '',
        selectedInstrumentLabel: '',
        fields: [
          SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Measurement Setting',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ...MeasurementSweepMode.values.map(
                      (mode) => ChoiceChip(
                        label: Text(mode.label),
                        selected: _measurementSweepMode == mode,
                        onSelected: _running ? null : (_) => setState(() => _measurementSweepMode = mode),
                      ),
                    ),
                    SizedBox(
                      width: 150,
                      child: CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('Repeat Run'),
                        value: _repeatEnabled,
                        onChanged: _running
                            ? null
                            : (v) {
                                setState(() {
                                  _repeatEnabled = v ?? false;
                                });
                              },
                      ),
                    ),
                    SizedBox(
                      width: 150,
                      child: TextFormField(
                        controller: _measurementSweepMode == MeasurementSweepMode.idVds
                            ? _idVdsRepeat
                            : _idVgsRepeat,
                        enabled: _repeatEnabled && !_running,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (v) => _validator(v, numeric: true),
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: 'Repeat Count',
                          hintText: '1',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    SizedBox(
                      width: 150,
                      child: TextFormField(
                        controller: _repeatWaitMs,
                        enabled: _repeatEnabled && !_running,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (v) => _validator(v, numeric: true),
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: 'Repeat Wait (ms)',
                          hintText: '0',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Gate path: $gatePathLabel | Instrument: ${_activeGateInstrumentLabel()}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _settingsSection(
                  title: 'Drain Setting',
                  children: _buildDrainSettingFields(),
                ),
                const SizedBox(height: 10),
                _settingsSection(
                  title: 'Gate Setting',
                  children: _buildGateSettingFields(),
                ),
              ],
            ),
          ),
        ],
        actions: [
          FilledButton.icon(
            onPressed: _running ? null : _startRun,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Start Sweep'),
          ),
          OutlinedButton.icon(
            onPressed: _running ? _stopRun : null,
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('Stop'),
          ),
          TextButton.icon(
            onPressed: _running ? null : _reset,
            icon: const Icon(Icons.refresh),
            label: const Text('Reset Defaults'),
          ),
        ],
        warningText: ((_selection.gateMeasurementMode == GateMeasurementMode.dc &&
                    !_selection.canControl(DeviceRole.gate)) ||
                (_selection.gateMeasurementMode == GateMeasurementMode.pulse &&
                    !(_selection.pulseGeneratorTransport == CommTransport.visa ||
                        _selection.pulseGeneratorInstrument == TestInstrument.afg2225)))
            ? 'AFG-2225 sweep logic is active on ${_selection.gateMeasurementMode == GateMeasurementMode.pulse ? _selection.pulseGeneratorTransport.label : _selection.gateTransport.label}.'
            : _measurementSweepMode != MeasurementSweepMode.idVds
                ? 'The UI now exposes DC project measurement modes below Thermal Camera. Execution is still backed by the current sweep engine, so only the existing sweep path is wired end-to-end.'
            : null,
      ),
    );
  }

  Widget _settingsSection({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD7E2DB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  children[i],
                  if (i != children.length - 1) const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildDrainSettingFields() {
    final fields = <Widget>[
      if (_measurementSweepMode == MeasurementSweepMode.idVgs ||
          _measurementSweepMode == MeasurementSweepMode.hysteresis)
        _compactField(_drainVFixed, 'Drain V (fixed)', '10.0'),
      if (_measurementSweepMode == MeasurementSweepMode.idVds) ...[
        _compactField(_vStart, 'Vds Start', '1.0'),
        _compactField(_vEnd, 'Vds Stop', '5.0'),
        _compactField(_vStep, 'Vds Step', '0.1'),
      ],
      if (_measurementSweepMode == MeasurementSweepMode.realtime) ...[
        _compactField(_realtimeDrainV, 'Drain V (fixed)', '10.0'),
        _compactField(
          _realtimeDrainRange,
          'Drain Range (A)',
          '5.0',
          enabled: !_realtimeDrainRangeAuto,
        ),
      ],
      _compactField(_drainILimit, 'Drain I Lim (A)', '1.0'),
      if (_measurementSweepMode == MeasurementSweepMode.idVgs &&
          _selection.gateMeasurementMode == GateMeasurementMode.pulse)
        _compactField(_currentMeasureDelay, 'Current Delay (s)', '0.05'),
    ];

    if (_measurementSweepMode != MeasurementSweepMode.realtime) {
      fields.addAll([
        _compactField(_voltageDropThreshold, 'Drop Threshold (V)', '1.0'),
        _compactCheck('Voltage Protect', _voltageDropProtect, (v) => _voltageDropProtect = v),
      ]);
    } else {
      fields.addAll([
        _compactField(_realtimeIntervalMs, 'Interval (ms)', '200'),
        _compactField(_realtimeDurationSec, 'Duration (s)', '10', enabled: !_realtimeRunUntilStopped),
        _compactCheck('Drain range auto', _realtimeDrainRangeAuto, (v) => _realtimeDrainRangeAuto = v),
        _compactCheck('Run until Stop', _realtimeRunUntilStopped, (v) => _realtimeRunUntilStopped = v),
      ]);
    }
    return fields;
  }

  List<Widget> _buildGateSettingFields() {
    final fields = <Widget>[
      if (_selection.gateMeasurementMode == GateMeasurementMode.dc &&
          _selection.gateTransport != CommTransport.visa)
        _compactTextField(
          _port,
          _selection.gateTransport.targetLabel,
          _selection.gateTransport.defaultTarget(_selection.gateInstrument),
          numeric: false,
        ),
      if (_selection.gateMeasurementMode == GateMeasurementMode.pulse &&
          _selection.pulseGeneratorTransport != CommTransport.visa)
        _compactTextField(
          _port,
          _selection.pulseGeneratorTransport.targetLabel,
          _selection.pulseGeneratorTransport.defaultTarget(_selection.pulseGeneratorInstrument),
          numeric: false,
        ),
      if (_measurementSweepMode == MeasurementSweepMode.idVgs ||
          _measurementSweepMode == MeasurementSweepMode.hysteresis) ...[
        _compactField(_vStart, 'Vgs Start', '1.0'),
        _compactField(_vEnd, 'Vgs Stop', '5.0'),
        _compactField(_vStep, 'Vgs Step', '0.1'),
      ],
      if (_measurementSweepMode == MeasurementSweepMode.idVds) ...[
        _compactField(_gateStartV, 'Gate Start V', '0.0'),
        _compactField(_gateStopV, 'Gate Stop V', '10.0'),
        _compactField(_gateStepV, 'Gate Step V', '1.0'),
      ],
      if (_measurementSweepMode == MeasurementSweepMode.realtime)
        _compactField(_realtimeGateV, 'Gate V (fixed)', '5.0'),
      _compactField(_gateILimit, 'Gate I Lim (A)', '0.5'),
    ];

    if (_measurementSweepMode != MeasurementSweepMode.realtime) {
      fields.addAll([
        _compactField(_periodUs, 'Period (us)', '10.0'),
        _compactField(_duty, 'Duty Ratio', '0.5'),
        _compactField(_onTime, 'On-Time (s)', '2.0'),
        _compactField(_offTime, 'Off-Time (s)', '1.0'),
      ]);
    } else {
      fields.add(_compactCheck('Measure voltage', _realtimeMeasureVoltage, (v) => _realtimeMeasureVoltage = v));
    }
    return fields;
  }

  Widget _compactField(
    TextEditingController controller,
    String label,
    String hint, {
    bool enabled = true,
  }) {
    return _compactTextField(controller, label, hint, numeric: true, enabled: enabled);
  }

  Widget _compactTextField(
    TextEditingController controller,
    String label,
    String hint, {
    required bool numeric,
    bool enabled = true,
  }) {
    return SizedBox(
      width: 150,
      child: TextFormField(
        controller: controller,
        enabled: enabled,
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        validator: (v) => _validator(v, numeric: numeric),
        decoration: InputDecoration(
          isDense: true,
          labelText: label,
          hintText: hint,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _compactCheck(String title, bool value, void Function(bool) update) {
    return SizedBox(
      width: 150,
      child: CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(title),
        value: value,
        onChanged: _running
            ? null
            : (v) {
                setState(() {
                  update(v ?? false);
                });
              },
      ),
    );
  }

  Widget _logCard() {
    return ExecutionLogCard(
      running: _running,
      content: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 88, maxHeight: 88),
        child: _logs.isEmpty
            ? const Center(child: Text('No run history yet.'))
            : ListView.separated(
                reverse: true,
                itemCount: _logs.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final e = _logs[i];
                  return ListTile(
                    dense: true,
                    leading: Icon(e.level.icon, color: e.level.color),
                    title: Text(e.message),
                    subtitle: Text(e.timestampLabel),
                  );
                },
              ),
      ),
    );
  }

  Widget _thermalViewCard() {
    final hasFrame = _raspberryFrameValues.isNotEmpty && _raspberryFrameRows > 0 && _raspberryFrameCols > 0;
    return ThermalPreviewCard(
      streaming: _isRaspberryStreaming,
      infoText: _raspberryResult,
      preview: hasFrame
          ? AspectRatio(
              aspectRatio: _raspberryFrameCols / _raspberryFrameRows,
              child: RotatedBox(
                quarterTurns: 3,
                child: CustomPaint(
                  painter: ThermalFramePainter(
                    values: _raspberryFrameValues,
                    rows: _raspberryFrameRows,
                    cols: _raspberryFrameCols,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            )
          : Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.blueGrey.shade50,
                border: Border.all(color: Colors.black26),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Text(
                  'Thermal camera view will appear here.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
    );
  }

  Widget _field(TextEditingController c, String label, String hint, {bool numeric = false}) {
    return TextFormField(
      controller: c,
      keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      validator: (v) => _validator(v, numeric: numeric),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
      onChanged: (_) => setState(() {}),
    );
  }
}

class ThermalFramePainter extends CustomPainter {
  ThermalFramePainter({
    required this.values,
    required this.rows,
    required this.cols,
  });

  final List<double> values;
  final int rows;
  final int cols;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);
    if (values.isEmpty || rows <= 0 || cols <= 0 || values.length < rows * cols) {
      return;
    }

    var minValue = values.first;
    var maxValue = values.first;
    for (final value in values) {
      if (value < minValue) minValue = value;
      if (value > maxValue) maxValue = value;
    }
    final range = (maxValue - minValue).abs() < 1e-12 ? 1.0 : (maxValue - minValue);
    final rotatedCols = rows;
    final rotatedRows = cols;
    final scale = math.min(size.width / rotatedCols, size.height / rotatedRows);
    final contentWidth = rotatedCols * scale;
    final contentHeight = rotatedRows * scale;
    final offsetX = (size.width - contentWidth) / 2;
    final offsetY = (size.height - contentHeight) / 2;
    final paint = Paint()..style = PaintingStyle.fill;

    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        final value = values[row * cols + col];
        final t = ((value - minValue) / range).clamp(0.0, 1.0);
        paint.color = _thermalColor(t);
        final rotatedCol = row;
        final rotatedRow = cols - 1 - col;
        canvas.drawRect(
          Rect.fromLTWH(
            offsetX + rotatedCol * scale,
            offsetY + rotatedRow * scale,
            scale + 0.5,
            scale + 0.5,
          ),
          paint,
        );
      }
    }
  }

  Color _thermalColor(double t) {
    if (t < 0.25) {
      return Color.lerp(const Color(0xFF001B7A), const Color(0xFF00B5FF), t / 0.25)!;
    }
    if (t < 0.5) {
      return Color.lerp(const Color(0xFF00B5FF), const Color(0xFF00FF9C), (t - 0.25) / 0.25)!;
    }
    if (t < 0.75) {
      return Color.lerp(const Color(0xFF00FF9C), const Color(0xFFFFE600), (t - 0.5) / 0.25)!;
    }
    return Color.lerp(const Color(0xFFFFE600), const Color(0xFFFF3B00), (t - 0.75) / 0.25)!;
  }

  @override
  bool shouldRepaint(covariant ThermalFramePainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.rows != rows || oldDelegate.cols != cols;
}
