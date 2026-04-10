import 'dart:async';

import 'package:flutter/material.dart';

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
  final _formKey = GlobalKey<FormState>();
  final _bridge = NativeInstrumentBridge();
  late final InstrumentSelectionController _selection;
  final _logs = <LogEntry>[];
  late final TextEditingController _port;
  late final TextEditingController _periodUs;
  late final TextEditingController _vStart;
  late final TextEditingController _vEnd;
  late final TextEditingController _vStep;
  late final TextEditingController _onTime;
  late final TextEditingController _offTime;
  late final TextEditingController _duty;
  bool _running = false;
  Timer? _logPoller;

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
    _onTime = TextEditingController(text: '${d.onTimeSeconds}');
    _offTime = TextEditingController(text: '${d.offTimeSeconds}');
    _duty = TextEditingController(text: '${d.dutyRatio}');
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
    _onTime.dispose();
    _offTime.dispose();
    _duty.dispose();
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
      _onTime.text = '${d.onTimeSeconds}';
      _offTime.text = '${d.offTimeSeconds}';
      _duty.text = '${d.dutyRatio}';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SiC MOSFET Pulse Tester')),
      body: LayoutBuilder(
        builder: (context, c) {
          final content = c.maxWidth >= 1100
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 5, child: _setupCard()),
                  const SizedBox(width: 20),
                  Expanded(flex: 4, child: _logCard()),
                ])
              : Column(children: [_setupCard(), const SizedBox(height: 20), _logCard()]);
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _instrumentCard(),
                const SizedBox(height: 20),
                content,
              ],
            ),
          );
        },
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
    return Form(
      key: _formKey,
      child: SweepSetupCard(
        description:
            'Start Sweep uses the ${_selection.gateMeasurementMode == GateMeasurementMode.pulse ? 'Pulse Function Generator' : 'Gate'} configuration below.',
        selectedInstrumentLabel: 'Selected Gate instrument: ${_activeGateInstrumentLabel()}',
        fields: [
          if (_selection.gateMeasurementMode == GateMeasurementMode.dc &&
              _selection.gateTransport != CommTransport.visa)
            SizedBox(
                width: 220,
                child: _field(
                  _port,
                  _selection.gateTransport.targetLabel,
                  _selection.gateTransport.defaultTarget(_selection.gateInstrument),
                )),
          if (_selection.gateMeasurementMode == GateMeasurementMode.pulse &&
              _selection.pulseGeneratorTransport != CommTransport.visa)
            SizedBox(
                width: 220,
                child: _field(
                  _port,
                  _selection.pulseGeneratorTransport.targetLabel,
                  _selection.pulseGeneratorTransport
                      .defaultTarget(_selection.pulseGeneratorInstrument),
                )),
          SizedBox(width: 220, child: _field(_periodUs, 'Period (us)', '10.0', numeric: true)),
          SizedBox(width: 220, child: _field(_duty, 'Duty Ratio (0-1)', '0.5', numeric: true)),
          SizedBox(width: 220, child: _field(_vStart, 'Voltage Start (Vpp)', '1.0', numeric: true)),
          SizedBox(width: 220, child: _field(_vEnd, 'Voltage End (Vpp)', '5.0', numeric: true)),
          SizedBox(width: 220, child: _field(_vStep, 'Voltage Step (V)', '0.1', numeric: true)),
          SizedBox(width: 220, child: _field(_onTime, 'Output On-Time (s)', '2.0', numeric: true)),
          SizedBox(width: 220, child: _field(_offTime, 'Output Off-Time (s)', '0.01', numeric: true)),
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
            : null,
      ),
    );
  }

  Widget _logCard() {
    return ExecutionLogCard(
      running: _running,
      content: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 220, maxHeight: 420),
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
