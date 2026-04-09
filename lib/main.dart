import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  final _logs = <LogEntry>[];
  late final TextEditingController _port;
  late final TextEditingController _periodUs;
  late final TextEditingController _vStart;
  late final TextEditingController _vEnd;
  late final TextEditingController _vStep;
  late final TextEditingController _onTime;
  late final TextEditingController _offTime;
  late final TextEditingController _duty;

  TestInstrument _instrument = TestInstrument.afg2225;
  CommTransport _transport = CommTransport.serial;
  ConnectionStateView _connection = ConnectionStateView.idle;
  String _detail = 'No handshake has been run yet.';
  bool _running = false;
  Timer? _logPoller;

  @override
  void initState() {
    super.initState();
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

  bool get _canControl => _instrument == TestInstrument.afg2225;

  PulseTestConfig? get _preview {
    try {
      return _readConfig();
    } catch (_) {
      return null;
    }
  }

  PulseTestConfig _readConfig() {
    final config = PulseTestConfig(
      port: _port.text.trim(),
      transport: _transport,
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
      _port.text = _transport.defaultTarget(_instrument);
      _periodUs.text = '${d.periodUs}';
      _vStart.text = '${d.voltageStart}';
      _vEnd.text = '${d.voltageEnd}';
      _vStep.text = '${d.voltageStep}';
      _onTime.text = '${d.onTimeSeconds}';
      _offTime.text = '${d.offTimeSeconds}';
      _duty.text = '${d.dutyRatio}';
      _connection = ConnectionStateView.idle;
      _detail = 'Defaults restored.';
    });
  }

  Future<void> _checkConnection() async {
    if (!_canControl) {
      _message('This instrument driver is not implemented yet.');
      return;
    }
    final target = _port.text.trim();
    if (target.isEmpty) {
      _message('${_transport.targetLabel} is required.');
      return;
    }
    setState(() {
      _connection = ConnectionStateView.checking;
      _detail = 'Running *IDN? handshake on $target via ${_transport.label}';
    });
    try {
      final result = await _bridge.identify(target: target, transport: _transport);
      _appendBridgeLogs(result.logs);
      if (!mounted) {
        return;
      }
      setState(() {
        _connection = result.success ? ConnectionStateView.connected : ConnectionStateView.failed;
        _detail = result.summary;
      });
    } catch (error) {
      setState(() {
        _connection = ConnectionStateView.failed;
        _detail = 'Handshake failed: $error';
      });
      _log(LogEntry.error('Connection check failed: $error'));
    }
  }

  Future<void> _startRun() async {
    if (!_canControl) {
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
        _connection = ConnectionStateView.connected;
        _detail = 'Sweep started.';
      });
      final result = await _bridge.startSweep(config: config);
      _appendBridgeLogs(result.logs);
      if (!mounted) {
        return;
      }
      setState(() {
        _detail = result.summary;
        if (!result.success) {
          _running = false;
          _connection = ConnectionStateView.failed;
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
          _connection = ConnectionStateView.failed;
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
      _detail = 'Stop requested.';
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
          if (_detail == 'Sweep started.') {
            _detail = 'Sweep finished.';
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

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final steps = preview == null ? <double>[] : preview.buildVoltagePoints();
    final frequency = preview?.frequencyHz ?? 0.0;
    final dutyPercent = preview?.dutyPercent ?? 0.0;
    final seconds = preview == null ? 0.0 : steps.length.toDouble() * (preview.onTimeSeconds + preview.offTimeSeconds);

    return Scaffold(
      appBar: AppBar(title: const Text('SiC MOSFET Pulse Tester')),
      body: LayoutBuilder(
        builder: (context, c) {
          final left = Column(children: [_instrumentCard(), const SizedBox(height: 20), _setupCard()]);
          final right = _statusColumn(frequency, dutyPercent, steps.length, seconds);
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: c.maxWidth >= 1100
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(flex: 5, child: left),
                    const SizedBox(width: 20),
                    Expanded(flex: 4, child: right),
                  ])
                : Column(children: [left, const SizedBox(height: 20), right]),
          );
        },
      ),
    );
  }

  Widget _instrumentCard() {
    final status = _connection.presentation;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Instrument Selection', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text('Run a real connection check before starting the sweep.', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 20),
          Wrap(spacing: 16, runSpacing: 16, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<CommTransport>(
                initialValue: _transport,
                decoration: InputDecoration(
                  labelText: 'Transport',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                ),
                items: CommTransport.values
                    .map((v) => DropdownMenuItem<CommTransport>(value: v, child: Text(v.label)))
                    .toList(),
                onChanged: _running
                    ? null
                    : (v) {
                        if (v == null) {
                          return;
                        }
                        setState(() {
                          _transport = v;
                          _port.text = v.defaultTarget(_instrument);
                          _connection = ConnectionStateView.idle;
                          _detail = 'Transport changed to ${v.label}';
                        });
                      },
              ),
            ),
            SizedBox(
              width: 320,
              child: DropdownButtonFormField<TestInstrument>(
                initialValue: _instrument,
                decoration: InputDecoration(
                  labelText: 'Target Instrument',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                ),
                items: TestInstrument.values
                    .map((v) => DropdownMenuItem<TestInstrument>(value: v, child: Text(v.label)))
                    .toList(),
                onChanged: _running
                    ? null
                    : (v) {
                        if (v == null) {
                          return;
                        }
                        setState(() {
                          _instrument = v;
                          _port.text = _transport.defaultTarget(v);
                          _connection = ConnectionStateView.idle;
                          _detail = 'Selected ${v.label}';
                        });
                      },
              ),
            ),
            FilledButton.icon(
              onPressed: _running ? null : _checkConnection,
              icon: const Icon(Icons.usb_rounded),
              label: const Text('Check Connection'),
            ),
            Chip(
              avatar: Icon(status.icon, size: 18, color: status.color),
              label: Text(status.label),
              side: BorderSide(color: status.color.withAlpha(90)),
            ),
          ]),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xFFEAF5F0), borderRadius: BorderRadius.circular(18)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_instrument.label, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(_instrument.description),
              const SizedBox(height: 8),
              Text('Transport: ${_transport.label}'),
              Text('${_transport.targetLabel}: ${_transport.defaultTarget(_instrument)}'),
              Text('Connection Check: ${_instrument.connectionHint}'),
              Text('Status Detail: $_detail'),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _setupCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Sweep Setup', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text('Start Sweep sends commands through the selected Windows native transport layer.', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            Text('Selected instrument: ${_instrument.label}', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 20),
            Wrap(spacing: 16, runSpacing: 16, children: [
              SizedBox(width: 220, child: _field(_port, _transport.targetLabel, _transport.defaultTarget(_instrument))),
              SizedBox(width: 220, child: _field(_periodUs, 'Period (us)', '10.0', numeric: true)),
              SizedBox(width: 220, child: _field(_duty, 'Duty Ratio (0-1)', '0.5', numeric: true)),
              SizedBox(width: 220, child: _field(_vStart, 'Voltage Start (Vpp)', '1.0', numeric: true)),
              SizedBox(width: 220, child: _field(_vEnd, 'Voltage End (Vpp)', '5.0', numeric: true)),
              SizedBox(width: 220, child: _field(_vStep, 'Voltage Step (V)', '0.1', numeric: true)),
              SizedBox(width: 220, child: _field(_onTime, 'Output On-Time (s)', '2.0', numeric: true)),
              SizedBox(width: 220, child: _field(_offTime, 'Output Off-Time (s)', '0.01', numeric: true)),
            ]),
            const SizedBox(height: 20),
            Wrap(spacing: 12, runSpacing: 12, children: [
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
            ]),
            if (!_canControl) ...[
              const SizedBox(height: 12),
              Text(
                'AFG-2225 sweep logic is active, and the transport can be switched between Serial SCPI, VISA SCPI, and TCP Socket.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _statusColumn(double f, double d, int steps, double sec) {
    return Column(children: [_derivedCard(f, d, steps, sec), const SizedBox(height: 20), _logCard()]);
  }

  Widget _derivedCard(double f, double d, int steps, double sec) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Derived Values', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Wrap(spacing: 12, runSpacing: 12, children: [
            _MetricTile(label: 'Frequency', value: '${f.toStringAsFixed(2)} Hz'),
            _MetricTile(label: 'Duty', value: '${d.toStringAsFixed(1)} %'),
            _MetricTile(label: 'Steps', value: '$steps'),
            _MetricTile(label: 'Estimated Run', value: '${sec.toStringAsFixed(2)} s'),
            const _MetricTile(label: 'Control Path', value: 'Windows C++'),
          ]),
        ]),
      ),
    );
  }

  Widget _logCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('Execution Log', style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            if (_running) const Chip(avatar: Icon(Icons.sync, size: 18), label: Text('Running')),
          ]),
          const SizedBox(height: 16),
          ConstrainedBox(
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
        ]),
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

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 148,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFFE7F4EE), borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ]),
    );
  }
}

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
  });

  static const defaults = PulseTestConfig(
    port: 'COM5',
    transport: CommTransport.serial,
    periodUs: 10.0,
    voltageStart: 1.0,
    voltageEnd: 5.0,
    voltageStep: 0.1,
    onTimeSeconds: 2.0,
    offTimeSeconds: 0.01,
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

  double get frequencyHz => 1000000.0 / periodUs;
  double get dutyPercent => dutyRatio * 100.0;

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

class ValidationException implements Exception {
  const ValidationException(this.message);
  final String message;

  @override
  String toString() => message;
}

class NativeInstrumentBridge {
  static const MethodChannel _channel = MethodChannel('sic_mosfet/native_control');

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
      },
    );
    return BridgeResult.fromMap(response ?? const <Object?, Object?>{});
  }

  Future<void> stopSweep() => _channel.invokeMethod<void>('stopSweep');

  Future<LogPollResult> fetchLogs() async {
    final response = await _channel.invokeMapMethod<Object?, Object?>('fetchLogs');
    return LogPollResult.fromMap(response ?? const <Object?, Object?>{});
  }

  void dispose() {}
}

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

class BridgeLog {
  const BridgeLog({
    required this.level,
    required this.message,
  });

  final String level;
  final String message;
}

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

enum TestInstrument {
  afg2225(
    label: 'GW Instek AFG-2225',
    defaultPort: 'COM5',
    defaultVisaResource: 'USB0::0x0000::0x0000::INSTR',
    defaultTcpEndpoint: '192.168.0.10:5025',
    description: 'Connected to the real Windows native serial driver.',
    connectionHint: 'SCPI *IDN? over serial',
  ),
  oscilloscope(
    label: 'Oscilloscope',
    defaultPort: 'COM6',
    defaultVisaResource: 'TCPIP0::192.168.0.20::inst0::INSTR',
    defaultTcpEndpoint: '192.168.0.20:5025',
    description: 'Reserved slot for a future scope driver.',
    connectionHint: 'Not implemented',
  ),
  custom(
    label: 'Custom Instrument',
    defaultPort: 'COM7',
    defaultVisaResource: 'USB0::CUSTOM::INSTR',
    defaultTcpEndpoint: '127.0.0.1:5025',
    description: 'Reserved slot for a custom device.',
    connectionHint: 'Not implemented',
  );

  const TestInstrument({
    required this.label,
    required this.defaultPort,
    required this.defaultVisaResource,
    required this.defaultTcpEndpoint,
    required this.description,
    required this.connectionHint,
  });

  final String label;
  final String defaultPort;
  final String defaultVisaResource;
  final String defaultTcpEndpoint;
  final String description;
  final String connectionHint;
}

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

enum ConnectionStateView {
  idle(Icons.radio_button_unchecked_rounded, Color(0xFF6B7280), 'Not Checked'),
  checking(Icons.sync_rounded, Color(0xFF2563EB), 'Checking'),
  connected(Icons.usb_rounded, Color(0xFF0B6E4F), 'Connected'),
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
