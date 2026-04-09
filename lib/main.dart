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
  final List<String> _resources = <String>[];
  final Map<String, String> _resourceToDeviceName = <String, String>{};
  String _drainResource = '';
  String _gateResource = '';
  String _pulseGeneratorResource = '';
  String _pulseScopeResource = '';
  String _pulseCurrentResource = '';

  TestInstrument _drainInstrument = TestInstrument.afg2225;
  TestInstrument _gateInstrument = TestInstrument.afg2225;
  TestInstrument _pulseGeneratorInstrument = TestInstrument.afg2225;
  TestInstrument _pulseScopeInstrument = TestInstrument.oscilloscope;
  TestInstrument _pulseCurrentInstrument = TestInstrument.currentMeter;
  CommTransport _drainTransport = CommTransport.serial;
  CommTransport _gateTransport = CommTransport.serial;
  CommTransport _pulseGeneratorTransport = CommTransport.serial;
  CommTransport _pulseScopeTransport = CommTransport.visa;
  CommTransport _pulseCurrentTransport = CommTransport.visa;
  ConnectionStateView _drainConnection = ConnectionStateView.idle;
  ConnectionStateView _gateConnection = ConnectionStateView.idle;
  ConnectionStateView _pulseGeneratorConnection = ConnectionStateView.idle;
  ConnectionStateView _pulseScopeConnection = ConnectionStateView.idle;
  ConnectionStateView _pulseCurrentConnection = ConnectionStateView.idle;
  String _drainDetail = 'No handshake has been run yet.';
  String _gateDetail = 'No handshake has been run yet.';
  String _pulseGeneratorDetail = 'No handshake has been run yet.';
  String _pulseScopeDetail = 'No handshake has been run yet.';
  String _pulseCurrentDetail = 'No handshake has been run yet.';
  GateMeasurementMode _gateMeasurementMode = GateMeasurementMode.dc;
  bool _running = false;
  bool _loadingResources = false;
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

  bool _canControl(DeviceRole role) {
    final transport = _transportFor(role);
    final instrument = _instrumentFor(role);
    return transport == CommTransport.visa || instrument == TestInstrument.afg2225;
  }

  List<TestInstrument> _availableInstrumentsFor(CommTransport transport) {
    return TestInstrument.values
        .where((instrument) => instrument.supportedTransports.contains(transport))
        .toList();
  }

  CommTransport _transportFor(DeviceRole role) {
    return role == DeviceRole.drain ? _drainTransport : _gateTransport;
  }

  TestInstrument _instrumentFor(DeviceRole role) {
    return role == DeviceRole.drain ? _drainInstrument : _gateInstrument;
  }

  ConnectionStateView _connectionFor(DeviceRole role) {
    return role == DeviceRole.drain ? _drainConnection : _gateConnection;
  }

  String _detailFor(DeviceRole role) {
    return role == DeviceRole.drain ? _drainDetail : _gateDetail;
  }

  String _targetFor(DeviceRole role) {
    final transport = _transportFor(role);
    if (transport == CommTransport.visa) {
      return role == DeviceRole.drain ? _drainResource : _gateResource;
    }
    return role == DeviceRole.drain ? _port.text.trim() : _port.text.trim();
  }

  void _setTransport(DeviceRole role, CommTransport value) {
    if (role == DeviceRole.drain) {
      _drainTransport = value;
    } else {
      _gateTransport = value;
    }
  }

  void _setInstrument(DeviceRole role, TestInstrument value) {
    if (role == DeviceRole.drain) {
      _drainInstrument = value;
    } else {
      _gateInstrument = value;
    }
  }

  void _setConnection(DeviceRole role, ConnectionStateView value) {
    if (role == DeviceRole.drain) {
      _drainConnection = value;
    } else {
      _gateConnection = value;
    }
  }

  void _setDetail(DeviceRole role, String value) {
    if (role == DeviceRole.drain) {
      _drainDetail = value;
    } else {
      _gateDetail = value;
    }
  }

  CommTransport _pulseTransportFor(PulseDeviceRole role) {
    switch (role) {
      case PulseDeviceRole.generator:
        return _pulseGeneratorTransport;
      case PulseDeviceRole.oscilloscope:
        return _pulseScopeTransport;
      case PulseDeviceRole.current:
        return _pulseCurrentTransport;
    }
  }

  TestInstrument _pulseInstrumentFor(PulseDeviceRole role) {
    switch (role) {
      case PulseDeviceRole.generator:
        return _pulseGeneratorInstrument;
      case PulseDeviceRole.oscilloscope:
        return _pulseScopeInstrument;
      case PulseDeviceRole.current:
        return _pulseCurrentInstrument;
    }
  }

  ConnectionStateView _pulseConnectionFor(PulseDeviceRole role) {
    switch (role) {
      case PulseDeviceRole.generator:
        return _pulseGeneratorConnection;
      case PulseDeviceRole.oscilloscope:
        return _pulseScopeConnection;
      case PulseDeviceRole.current:
        return _pulseCurrentConnection;
    }
  }

  String _pulseDetailFor(PulseDeviceRole role) {
    switch (role) {
      case PulseDeviceRole.generator:
        return _pulseGeneratorDetail;
      case PulseDeviceRole.oscilloscope:
        return _pulseScopeDetail;
      case PulseDeviceRole.current:
        return _pulseCurrentDetail;
    }
  }

  void _setPulseTransport(PulseDeviceRole role, CommTransport value) {
    switch (role) {
      case PulseDeviceRole.generator:
        _pulseGeneratorTransport = value;
        return;
      case PulseDeviceRole.oscilloscope:
        _pulseScopeTransport = value;
        return;
      case PulseDeviceRole.current:
        _pulseCurrentTransport = value;
        return;
    }
  }

  void _setPulseInstrument(PulseDeviceRole role, TestInstrument value) {
    switch (role) {
      case PulseDeviceRole.generator:
        _pulseGeneratorInstrument = value;
        return;
      case PulseDeviceRole.oscilloscope:
        _pulseScopeInstrument = value;
        return;
      case PulseDeviceRole.current:
        _pulseCurrentInstrument = value;
        return;
    }
  }

  void _setPulseConnection(PulseDeviceRole role, ConnectionStateView value) {
    switch (role) {
      case PulseDeviceRole.generator:
        _pulseGeneratorConnection = value;
        return;
      case PulseDeviceRole.oscilloscope:
        _pulseScopeConnection = value;
        return;
      case PulseDeviceRole.current:
        _pulseCurrentConnection = value;
        return;
    }
  }

  void _setPulseDetail(PulseDeviceRole role, String value) {
    switch (role) {
      case PulseDeviceRole.generator:
        _pulseGeneratorDetail = value;
        return;
      case PulseDeviceRole.oscilloscope:
        _pulseScopeDetail = value;
        return;
      case PulseDeviceRole.current:
        _pulseCurrentDetail = value;
        return;
    }
  }

  PulseTestConfig? get _preview {
    try {
      return _readConfig();
    } catch (_) {
      return null;
    }
  }

  PulseTestConfig _readConfig() {
    final activeTransport = _gateMeasurementMode == GateMeasurementMode.pulse
        ? _pulseGeneratorTransport
        : _gateTransport;
    final activeTarget = _gateMeasurementMode == GateMeasurementMode.pulse
        ? _pulseTargetFor(PulseDeviceRole.generator)
        : _port.text.trim();
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
      _drainTransport = CommTransport.serial;
      _gateTransport = d.transport;
      _pulseGeneratorTransport = CommTransport.serial;
      _pulseScopeTransport = CommTransport.visa;
      _pulseCurrentTransport = CommTransport.visa;
      _drainInstrument = TestInstrument.afg2225;
      _gateInstrument = TestInstrument.afg2225;
      _pulseGeneratorInstrument = TestInstrument.afg2225;
      _pulseScopeInstrument = TestInstrument.oscilloscope;
      _pulseCurrentInstrument = TestInstrument.currentMeter;
      _port.text = d.port;
      _drainConnection = ConnectionStateView.idle;
      _gateConnection = ConnectionStateView.idle;
      _pulseGeneratorConnection = ConnectionStateView.idle;
      _pulseScopeConnection = ConnectionStateView.idle;
      _pulseCurrentConnection = ConnectionStateView.idle;
      _drainDetail = 'Defaults restored.';
      _gateDetail = 'Defaults restored.';
      _pulseGeneratorDetail = 'Defaults restored.';
      _pulseScopeDetail = 'Defaults restored.';
      _pulseCurrentDetail = 'Defaults restored.';
      _gateMeasurementMode = GateMeasurementMode.dc;
      _periodUs.text = '${d.periodUs}';
      _vStart.text = '${d.voltageStart}';
      _vEnd.text = '${d.voltageEnd}';
      _vStep.text = '${d.voltageStep}';
      _onTime.text = '${d.onTimeSeconds}';
      _offTime.text = '${d.offTimeSeconds}';
      _duty.text = '${d.dutyRatio}';
      _syncVisaSelections(preserveExisting: true);
    });
  }

  Future<void> _checkConnection(DeviceRole role) async {
    final transport = _transportFor(role);
    if (!_canControl(role)) {
      _message('This instrument driver is not implemented yet.');
      return;
    }
    final target = _targetFor(role);
    if (target.isEmpty) {
      _message('${transport.targetLabel} is required.');
      return;
    }
    setState(() {
      _setConnection(role, ConnectionStateView.checking);
      _setDetail(role, 'Running *IDN? handshake on $target via ${transport.label}');
    });
    try {
      final result = await _bridge.identify(target: target, transport: transport);
      _appendBridgeLogs(result.logs);
      if (!mounted) {
        return;
      }
      setState(() {
        _setConnection(
          role,
          result.success ? ConnectionStateView.connected : ConnectionStateView.failed,
        );
        _setDetail(role, result.summary);
      });
    } catch (error) {
      setState(() {
        _setConnection(role, ConnectionStateView.failed);
        _setDetail(role, 'Handshake failed: $error');
      });
      _log(LogEntry.error('${role.label} connection check failed: $error'));
    }
  }

  Future<void> _startRun() async {
    final canRun = _gateMeasurementMode == GateMeasurementMode.pulse
        ? (_pulseGeneratorTransport == CommTransport.visa ||
            _pulseGeneratorInstrument == TestInstrument.afg2225)
        : _canControl(DeviceRole.gate);
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
        _gateConnection = ConnectionStateView.connected;
        _gateDetail = 'Sweep started.';
      });
      final result = await _bridge.startSweep(config: config);
      _appendBridgeLogs(result.logs);
      if (!mounted) {
        return;
      }
      setState(() {
        _gateDetail = result.summary;
        if (!result.success) {
          _running = false;
          _gateConnection = ConnectionStateView.failed;
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
          _gateConnection = ConnectionStateView.failed;
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
      _gateDetail = 'Stop requested.';
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
          if (_gateDetail == 'Sweep started.') {
            _gateDetail = 'Sweep finished.';
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

  void _syncVisaSelections({bool preserveExisting = true}) {
    final resources = _resources;
    if (resources.isEmpty) {
      _drainResource = '';
      _gateResource = '';
      _pulseGeneratorResource = '';
      _pulseScopeResource = '';
      _pulseCurrentResource = '';
      _port.text = '';
      return;
    }

    if (!preserveExisting || !resources.contains(_drainResource)) {
      _drainResource = resources.first;
    }

    if (!preserveExisting || !resources.contains(_gateResource)) {
      _gateResource =
          resources.length >= 2 ? resources[1] : resources.first;
    }

    if (!preserveExisting || !resources.contains(_pulseGeneratorResource)) {
      _pulseGeneratorResource = resources.first;
    }

    if (!preserveExisting || !resources.contains(_pulseScopeResource)) {
      _pulseScopeResource = resources.length >= 2 ? resources[1] : resources.first;
    }

    if (!preserveExisting || !resources.contains(_pulseCurrentResource)) {
      _pulseCurrentResource = resources.length >= 3 ? resources[2] : resources.last;
    }

    _port.text = _gateResource;
  }

  String _resourceLabel(String resource) {
    final name = _resourceToDeviceName[resource];
    if (name == null || name.isEmpty || name == resource) {
      return resource;
    }
    return '$name ($resource)';
  }

  String _resourceShortLabel(String resource) {
    final name = _resourceToDeviceName[resource];
    if (name == null || name.isEmpty || name == resource) {
      return resource;
    }
    return name;
  }

  String _transportSelectionLabel(CommTransport transport) {
    switch (transport) {
      case CommTransport.visa:
        return 'VISA Resource';
      case CommTransport.serial:
        return 'Target Instrument';
      case CommTransport.tcp:
        return 'Target Instrument';
    }
  }

  String _instrumentDescription(DeviceRole role) {
    final instrument = _instrumentFor(role);
    final transport = _transportFor(role);
    if (instrument == TestInstrument.afg2225) {
      switch (transport) {
        case CommTransport.serial:
          return 'Connected through the Windows native serial driver.';
        case CommTransport.visa:
          return 'Connected through the Windows native VISA driver.';
        case CommTransport.tcp:
          return instrument.description;
      }
    }
    return instrument.description;
  }

  String _connectionHint(DeviceRole role) {
    final instrument = _instrumentFor(role);
    final transport = _transportFor(role);
    if (instrument == TestInstrument.afg2225) {
      switch (transport) {
        case CommTransport.serial:
          return 'SCPI *IDN? over serial';
        case CommTransport.visa:
          return 'SCPI *IDN? over VISA';
        case CommTransport.tcp:
          return instrument.connectionHint;
      }
    }
    return instrument.connectionHint;
  }

  String _defaultTargetFor(DeviceRole role) {
    final transport = _transportFor(role);
    final instrument = _instrumentFor(role);
    if (transport == CommTransport.visa) {
      return role == DeviceRole.drain ? _drainResource : _gateResource;
    }
    return transport.defaultTarget(instrument);
  }

  String _pulseTargetFor(PulseDeviceRole role) {
    final transport = _pulseTransportFor(role);
    if (transport == CommTransport.visa) {
      switch (role) {
        case PulseDeviceRole.generator:
          return _pulseGeneratorResource;
        case PulseDeviceRole.oscilloscope:
          return _pulseScopeResource;
        case PulseDeviceRole.current:
          return _pulseCurrentResource;
      }
    }
    if (role == PulseDeviceRole.generator) {
      return _port.text.trim();
    }
    return transport.defaultTarget(_pulseInstrumentFor(role));
  }

  void _onTransportChanged(DeviceRole role, CommTransport? value) {
    if (value == null) {
      return;
    }
    setState(() {
      _setTransport(role, value);
      final available = _availableInstrumentsFor(value);
      if (!available.contains(_instrumentFor(role)) && available.isNotEmpty) {
        _setInstrument(role, available.first);
      }
      if (value == CommTransport.visa) {
        _syncVisaSelections(preserveExisting: true);
      } else if (role == DeviceRole.gate) {
        _port.text = value.defaultTarget(_instrumentFor(role));
      }
      _setConnection(role, ConnectionStateView.idle);
      _setDetail(role, 'Transport changed to ${value.label}');
    });
    if (value == CommTransport.visa && _resources.isEmpty) {
      unawaited(_listResources());
    }
  }

  void _onInstrumentChanged(DeviceRole role, TestInstrument? value) {
    if (value == null) {
      return;
    }
    setState(() {
      _setInstrument(role, value);
      if (_transportFor(role) != CommTransport.visa && role == DeviceRole.gate) {
        _port.text = _transportFor(role).defaultTarget(value);
      }
      _setConnection(role, ConnectionStateView.idle);
      _setDetail(role, 'Selected ${value.label}');
    });
  }

  void _onPulseTransportChanged(PulseDeviceRole role, CommTransport? value) {
    if (value == null) {
      return;
    }
    setState(() {
      _setPulseTransport(role, value);
      final available = _availableInstrumentsFor(value);
      if (!available.contains(_pulseInstrumentFor(role)) && available.isNotEmpty) {
        _setPulseInstrument(role, available.first);
      }
      if (value == CommTransport.visa) {
        _syncVisaSelections(preserveExisting: true);
      } else if (role == PulseDeviceRole.generator) {
        _port.text = value.defaultTarget(_pulseInstrumentFor(role));
      }
      _setPulseConnection(role, ConnectionStateView.idle);
      _setPulseDetail(role, 'Transport changed to ${value.label}');
    });
    if (value == CommTransport.visa && _resources.isEmpty) {
      unawaited(_listResources());
    }
  }

  void _onPulseInstrumentChanged(PulseDeviceRole role, TestInstrument? value) {
    if (value == null) {
      return;
    }
    setState(() {
      _setPulseInstrument(role, value);
      if (_pulseTransportFor(role) != CommTransport.visa &&
          role == PulseDeviceRole.generator) {
        _port.text = _pulseTransportFor(role).defaultTarget(value);
      }
      _setPulseConnection(role, ConnectionStateView.idle);
      _setPulseDetail(role, 'Selected ${value.label}');
    });
  }

  String _activeGateInstrumentLabel() {
    if (_gateMeasurementMode == GateMeasurementMode.pulse) {
      return _pulseGeneratorInstrument.label;
    }
    return _gateInstrument.label;
  }

  Future<void> _checkPulseConnection(PulseDeviceRole role) async {
    final transport = _pulseTransportFor(role);
    final instrument = _pulseInstrumentFor(role);
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
      _setPulseConnection(role, ConnectionStateView.checking);
      _setPulseDetail(role, 'Running *IDN? handshake on $target via ${transport.label}');
    });
    try {
      final result = await _bridge.identify(target: target, transport: transport);
      _appendBridgeLogs(result.logs);
      if (!mounted) {
        return;
      }
      setState(() {
        _setPulseConnection(
          role,
          result.success ? ConnectionStateView.connected : ConnectionStateView.failed,
        );
        _setPulseDetail(role, result.summary);
      });
    } catch (error) {
      setState(() {
        _setPulseConnection(role, ConnectionStateView.failed);
        _setPulseDetail(role, 'Handshake failed: $error');
      });
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
      _loadingResources = true;
    });
    try {
      final resources = await _bridge.listResources();
      if (!mounted) {
        return;
      }
      setState(() {
        _resources
          ..clear()
          ..addAll(resources);
        _resourceToDeviceName
          ..clear()
          ..addEntries(resources.map((resource) => MapEntry(resource, resource)));
        _syncVisaSelections(preserveExisting: true);
        _loadingResources = false;
      });
      _log(LogEntry.info('Found ${resources.length} VISA resource(s).'));
      unawaited(_resolveResourceNames(resources));
    } catch (error) {
      _log(LogEntry.error('VISA resource scan failed: $error'));
      _message('VISA resource scan failed: $error');
      if (mounted) {
        setState(() {
          _loadingResources = false;
        });
      }
    }
  }

  Future<void> _resolveResourceNames(List<String> resources) async {
    for (final resource in resources) {
      try {
        final idn = await _bridge.queryIdn(resource: resource);
        if (!mounted) {
          return;
        }
        setState(() {
          _resourceToDeviceName[resource] = _extractDeviceName(idn);
        });
      } catch (_) {}
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
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Instrument Selection', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text('Run a real connection check before starting the sweep.', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 900) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 4, child: _channelSection(DeviceRole.drain)),
                    const SizedBox(width: 12),
                    Expanded(flex: 6, child: _channelSection(DeviceRole.gate)),
                  ],
                );
              }
              return Column(
                children: [
                  _channelSection(DeviceRole.drain),
                  const SizedBox(height: 12),
                  _channelSection(DeviceRole.gate),
                ],
              );
            },
          ),
        ]),
      ),
    );
  }

  Widget _channelSection(DeviceRole role) {
    final transport = _transportFor(role);
    final instrument = _instrumentFor(role);
    final connection = _connectionFor(role).presentation;
    final detail = _detailFor(role);
    final transportWidth = role == DeviceRole.drain ? 145.0 : 145.0;
    final targetWidth = role == DeviceRole.drain ? 210.0 : 250.0;
    final checkButtonStyle = switch (connection) {
      ConnectionStateView.connected => FilledButton.styleFrom(
          backgroundColor: const Color(0xFF2563EB),
          foregroundColor: Colors.white,
          visualDensity: VisualDensity.compact,
        ),
      ConnectionStateView.failed => FilledButton.styleFrom(
          backgroundColor: const Color(0xFFB42318),
          foregroundColor: Colors.white,
          visualDensity: VisualDensity.compact,
        ),
      _ => FilledButton.styleFrom(
          visualDensity: VisualDensity.compact,
        ),
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD7E2DB)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          textTheme: Theme.of(context).textTheme.apply(fontSizeFactor: 0.9),
          inputDecorationTheme: const InputDecorationTheme(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              role.label,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 15),
            ),
            if (role == DeviceRole.gate) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: GateMeasurementMode.values
                    .map(
                      (mode) => ChoiceChip(
                        label: Text(mode.label),
                        selected: _gateMeasurementMode == mode,
                        onSelected: _running
                            ? null
                            : (selected) {
                                if (!selected) {
                                  return;
                                }
                                setState(() {
                                  _gateMeasurementMode = mode;
                                  _gateDetail = 'Gate mode changed to ${mode.label}.';
                                });
                              },
                      ),
                    )
                    .toList(),
              ),
            ],
            const SizedBox(height: 8),
            if (role == DeviceRole.gate && _gateMeasurementMode == GateMeasurementMode.pulse)
              _pulseModePanel()
            else
              Wrap(
                spacing: role == DeviceRole.drain ? 6 : 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: transportWidth,
                    child: DropdownButtonFormField<CommTransport>(
                      initialValue: transport,
                      decoration: InputDecoration(
                        labelText: 'Transport',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      items: <CommTransport>[
                        CommTransport.serial,
                        CommTransport.visa,
                      ]
                          .map((v) => DropdownMenuItem<CommTransport>(value: v, child: Text(v.label)))
                          .toList(),
                      onChanged: _running ? null : (value) => _onTransportChanged(role, value),
                    ),
                  ),
                  SizedBox(
                    width: targetWidth,
                    child: transport == CommTransport.visa
                        ? _visaResourceDropdown(role)
                        : DropdownButtonFormField<TestInstrument>(
                            value: instrument,
                            decoration: InputDecoration(
                              labelText: _transportSelectionLabel(transport),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            items: _availableInstrumentsFor(transport)
                                .map((v) => DropdownMenuItem<TestInstrument>(value: v, child: Text(v.label)))
                                .toList(),
                            onChanged: _running ? null : (value) => _onInstrumentChanged(role, value),
                          ),
                  ),
                  FilledButton.icon(
                    style: checkButtonStyle,
                    onPressed: _running ? null : () => _checkConnection(role),
                    icon: const Icon(Icons.usb_rounded, size: 18),
                    label: const Text('Check Connection'),
                  ),
                  if (transport == CommTransport.visa)
                    IconButton(
                      onPressed: (_running || _loadingResources) ? null : _listResources,
                      tooltip: 'Reload VISA resources',
                      icon: _loadingResources
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded, size: 20),
                    ),
                  Tooltip(
                    message: [
                      instrument.label,
                      _instrumentDescription(role),
                      'Transport: ${transport.label}',
                      '${transport.targetLabel}: ${_defaultTargetFor(role)}',
                      'Connection Check: ${_connectionHint(role)}',
                    ].join('\n'),
                    waitDuration: const Duration(milliseconds: 250),
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF5F0),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF0B6E4F).withAlpha(70)),
                      ),
                      child: const Center(
                        child: Text(
                          '?',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0B6E4F),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            Text('Status Detail: $detail', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _pulseModePanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_pulseGeneratorTransport == CommTransport.visa ||
            _pulseScopeTransport == CommTransport.visa ||
            _pulseCurrentTransport == CommTransport.visa)
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: (_running || _loadingResources) ? null : _listResources,
              tooltip: 'Reload VISA resources',
              icon: _loadingResources
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded, size: 20),
            ),
          ),
        _pulseDevicePanel(PulseDeviceRole.generator),
        const SizedBox(height: 10),
        _pulseDevicePanel(PulseDeviceRole.oscilloscope),
        const SizedBox(height: 10),
        _pulseDevicePanel(PulseDeviceRole.current),
      ],
    );
  }

  Widget _pulseDevicePanel(PulseDeviceRole role) {
    final transport = _pulseTransportFor(role);
    final instrument = _pulseInstrumentFor(role);
    final detail = _pulseDetailFor(role);
    final connection = _pulseConnectionFor(role);
    final buttonStyle = switch (connection) {
      ConnectionStateView.connected => FilledButton.styleFrom(
          backgroundColor: const Color(0xFF2563EB),
          foregroundColor: Colors.white,
          visualDensity: VisualDensity.compact,
        ),
      ConnectionStateView.failed => FilledButton.styleFrom(
          backgroundColor: const Color(0xFFB42318),
          foregroundColor: Colors.white,
          visualDensity: VisualDensity.compact,
        ),
      _ => FilledButton.styleFrom(visualDensity: VisualDensity.compact),
    };

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBF8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDCE8DF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(role.label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 125,
                child: DropdownButtonFormField<CommTransport>(
                  initialValue: transport,
                  decoration: InputDecoration(
                    labelText: 'Transport',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  items: <CommTransport>[CommTransport.serial, CommTransport.visa]
                      .map((v) => DropdownMenuItem<CommTransport>(value: v, child: Text(v.label)))
                      .toList(),
                  onChanged: _running ? null : (value) => _onPulseTransportChanged(role, value),
                ),
              ),
              SizedBox(
                width: 230,
                child: transport == CommTransport.visa
                    ? _pulseVisaResourceDropdown(role)
                    : DropdownButtonFormField<TestInstrument>(
                        value: instrument,
                        decoration: InputDecoration(
                          labelText: _transportSelectionLabel(transport),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        items: _availableInstrumentsFor(transport)
                            .map((v) => DropdownMenuItem<TestInstrument>(value: v, child: Text(v.label)))
                            .toList(),
                        onChanged: _running ? null : (value) => _onPulseInstrumentChanged(role, value),
                      ),
              ),
              FilledButton.icon(
                style: buttonStyle,
                onPressed: _running ? null : () => _checkPulseConnection(role),
                icon: const Icon(Icons.usb_rounded, size: 18),
                label: const Text('Check Connection'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(detail, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _visaResourceDropdown(DeviceRole role) {
    final selected = role == DeviceRole.drain ? _drainResource : _gateResource;
    final label = role == DeviceRole.drain ? 'Target Instrument' : 'Target Instrument';

    return DropdownButtonFormField<String>(
      value: _resources.contains(selected) ? selected : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
      items: _resources
          .map((resource) => DropdownMenuItem<String>(
                value: resource,
                child: Tooltip(
                  message: _resourceLabel(resource),
                  child: Text(
                    _resourceShortLabel(resource),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ))
          .toList(),
      selectedItemBuilder: (context) => _resources
          .map(
            (resource) => Align(
              alignment: Alignment.centerLeft,
              child: Tooltip(
                message: _resourceLabel(resource),
                child: Text(
                  _resourceShortLabel(resource),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ),
          )
          .toList(),
      onChanged: (_running || _loadingResources)
          ? null
          : (value) {
              if (value == null) {
                return;
              }
              setState(() {
                if (role == DeviceRole.drain) {
                  _drainResource = value;
                  _drainDetail = 'Selected Drain: ${_resourceLabel(value)}';
                } else {
                  _gateResource = value;
                  _port.text = value;
                  _gateDetail = 'Selected Gate: ${_resourceLabel(value)}';
                }
              });
            },
      hint: Text(_loadingResources ? 'Loading VISA resources...' : 'Select VISA resource'),
    );
  }

  Widget _pulseVisaResourceDropdown(PulseDeviceRole role) {
    final selected = _pulseTargetFor(role);
    return DropdownButtonFormField<String>(
      value: _resources.contains(selected) ? selected : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Target Instrument',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
      items: _resources
          .map((resource) => DropdownMenuItem<String>(
                value: resource,
                child: Tooltip(
                  message: _resourceLabel(resource),
                  child: Text(
                    _resourceShortLabel(resource),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ))
          .toList(),
      selectedItemBuilder: (context) => _resources
          .map(
            (resource) => Align(
              alignment: Alignment.centerLeft,
              child: Tooltip(
                message: _resourceLabel(resource),
                child: Text(
                  _resourceShortLabel(resource),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ),
          )
          .toList(),
      onChanged: (_running || _loadingResources)
          ? null
          : (value) {
              if (value == null) {
                return;
              }
              setState(() {
                switch (role) {
                  case PulseDeviceRole.generator:
                    _pulseGeneratorResource = value;
                    _pulseGeneratorDetail = 'Selected ${role.label}: ${_resourceLabel(value)}';
                    return;
                  case PulseDeviceRole.oscilloscope:
                    _pulseScopeResource = value;
                    _pulseScopeDetail = 'Selected ${role.label}: ${_resourceLabel(value)}';
                    return;
                  case PulseDeviceRole.current:
                    _pulseCurrentResource = value;
                    _pulseCurrentDetail = 'Selected ${role.label}: ${_resourceLabel(value)}';
                    return;
                }
              });
            },
      hint: Text(_loadingResources ? 'Loading VISA resources...' : 'Select VISA resource'),
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
            Text(
              'Start Sweep uses the ${_gateMeasurementMode == GateMeasurementMode.pulse ? 'Pulse Function Generator' : 'Gate'} configuration below.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text('Selected Gate instrument: ${_activeGateInstrumentLabel()}', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 20),
            Wrap(spacing: 16, runSpacing: 16, children: [
              if (_gateMeasurementMode == GateMeasurementMode.dc && _gateTransport != CommTransport.visa)
                SizedBox(width: 220, child: _field(_port, _gateTransport.targetLabel, _gateTransport.defaultTarget(_gateInstrument))),
              if (_gateMeasurementMode == GateMeasurementMode.pulse && _pulseGeneratorTransport != CommTransport.visa)
                SizedBox(width: 220, child: _field(_port, _pulseGeneratorTransport.targetLabel, _pulseGeneratorTransport.defaultTarget(_pulseGeneratorInstrument))),
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
            if ((_gateMeasurementMode == GateMeasurementMode.dc && !_canControl(DeviceRole.gate)) ||
                (_gateMeasurementMode == GateMeasurementMode.pulse &&
                    !(_pulseGeneratorTransport == CommTransport.visa ||
                        _pulseGeneratorInstrument == TestInstrument.afg2225))) ...[
              const SizedBox(height: 12),
              Text(
                'AFG-2225 sweep logic is active on ${_gateMeasurementMode == GateMeasurementMode.pulse ? _pulseGeneratorTransport.label : _gateTransport.label}.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ]),
        ),
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

  Future<List<String>> listResources() async {
    final response = await _channel.invokeListMethod<Object?>('listResources');
    return (response ?? const <Object?>[]).map((item) => item.toString()).toList();
  }

  Future<String> queryIdn({required String resource}) async {
    final response = await _channel.invokeMapMethod<Object?, Object?>(
      'queryIdn',
      <String, Object?>{'resource': resource},
    );
    return (response?['idn'] ?? '').toString();
  }

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

enum PulseDeviceRole {
  generator('Function Generator'),
  oscilloscope('Oscilloscope'),
  current('Current Measurement');

  const PulseDeviceRole(this.label);
  final String label;
}

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
