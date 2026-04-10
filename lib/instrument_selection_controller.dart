import 'dart:async';

import 'instrument_selection_panel.dart';
import 'instrument_service.dart';
import 'pulse_tester_types.dart';

// Instrument Selection 상태와 장치 선택/연결 확인 로직을 묶어 관리한다.
// main.dart는 이 컨트롤러를 통해 현재 상태를 읽고, UI 이벤트를 전달한다.
class InstrumentSelectionController {
  InstrumentSelectionController(this._bridge);

  final NativeInstrumentBridge _bridge;

  final List<String> resources = <String>[];
  final Map<String, String> resourceToDeviceName = <String, String>{};

  String drainResource = '';
  String gateResource = '';
  String pulseGeneratorResource = '';
  String pulseScopeResource = '';
  String pulseCurrentResource = '';

  TestInstrument drainInstrument = TestInstrument.afg2225;
  TestInstrument gateInstrument = TestInstrument.afg2225;
  TestInstrument pulseGeneratorInstrument = TestInstrument.afg2225;
  TestInstrument pulseScopeInstrument = TestInstrument.oscilloscope;
  TestInstrument pulseCurrentInstrument = TestInstrument.currentMeter;

  CommTransport drainTransport = CommTransport.serial;
  CommTransport gateTransport = CommTransport.serial;
  CommTransport pulseGeneratorTransport = CommTransport.serial;
  CommTransport pulseScopeTransport = CommTransport.visa;
  CommTransport pulseCurrentTransport = CommTransport.visa;

  ConnectionStateView drainConnection = ConnectionStateView.idle;
  ConnectionStateView gateConnection = ConnectionStateView.idle;
  ConnectionStateView pulseGeneratorConnection = ConnectionStateView.idle;
  ConnectionStateView pulseScopeConnection = ConnectionStateView.idle;
  ConnectionStateView pulseCurrentConnection = ConnectionStateView.idle;

  String drainDetail = 'No handshake has been run yet.';
  String gateDetail = 'No handshake has been run yet.';
  String pulseGeneratorDetail = 'No handshake has been run yet.';
  String pulseScopeDetail = 'No handshake has been run yet.';
  String pulseCurrentDetail = 'No handshake has been run yet.';

  GateMeasurementMode gateMeasurementMode = GateMeasurementMode.dc;
  bool loadingResources = false;

  ChannelUiState get drainState => ChannelUiState(
        transport: drainTransport,
        instrument: drainInstrument,
        connection: drainConnection,
        detail: drainDetail,
        visaResource: drainResource,
      );

  ChannelUiState get gateState => ChannelUiState(
        transport: gateTransport,
        instrument: gateInstrument,
        connection: gateConnection,
        detail: gateDetail,
        visaResource: gateResource,
      );

  PulseDeviceUiState get generatorState => PulseDeviceUiState(
        transport: pulseGeneratorTransport,
        instrument: pulseGeneratorInstrument,
        connection: pulseGeneratorConnection,
        detail: pulseGeneratorDetail,
        visaResource: pulseGeneratorResource,
      );

  PulseDeviceUiState get scopeState => PulseDeviceUiState(
        transport: pulseScopeTransport,
        instrument: pulseScopeInstrument,
        connection: pulseScopeConnection,
        detail: pulseScopeDetail,
        visaResource: pulseScopeResource,
      );

  PulseDeviceUiState get currentState => PulseDeviceUiState(
        transport: pulseCurrentTransport,
        instrument: pulseCurrentInstrument,
        connection: pulseCurrentConnection,
        detail: pulseCurrentDetail,
        visaResource: pulseCurrentResource,
      );

  bool canControl(DeviceRole role) {
    final transport = transportFor(role);
    final instrument = instrumentFor(role);
    return transport == CommTransport.visa || instrument == TestInstrument.afg2225;
  }

  CommTransport transportFor(DeviceRole role) {
    return role == DeviceRole.drain ? drainTransport : gateTransport;
  }

  TestInstrument instrumentFor(DeviceRole role) {
    return role == DeviceRole.drain ? drainInstrument : gateInstrument;
  }

  String targetFor(DeviceRole role, String portText) {
    final transport = transportFor(role);
    if (transport == CommTransport.visa) {
      return role == DeviceRole.drain ? drainResource : gateResource;
    }
    return portText.trim();
  }

  CommTransport pulseTransportFor(PulseDeviceRole role) {
    switch (role) {
      case PulseDeviceRole.generator:
        return pulseGeneratorTransport;
      case PulseDeviceRole.oscilloscope:
        return pulseScopeTransport;
      case PulseDeviceRole.current:
        return pulseCurrentTransport;
    }
  }

  TestInstrument pulseInstrumentFor(PulseDeviceRole role) {
    switch (role) {
      case PulseDeviceRole.generator:
        return pulseGeneratorInstrument;
      case PulseDeviceRole.oscilloscope:
        return pulseScopeInstrument;
      case PulseDeviceRole.current:
        return pulseCurrentInstrument;
    }
  }

  String pulseTargetFor(PulseDeviceRole role, String portText) {
    final transport = pulseTransportFor(role);
    if (transport == CommTransport.visa) {
      switch (role) {
        case PulseDeviceRole.generator:
          return pulseGeneratorResource;
        case PulseDeviceRole.oscilloscope:
          return pulseScopeResource;
        case PulseDeviceRole.current:
          return pulseCurrentResource;
      }
    }
    if (role == PulseDeviceRole.generator) {
      return portText.trim();
    }
    return transport.defaultTarget(pulseInstrumentFor(role));
  }

  List<TestInstrument> availableInstrumentsFor(CommTransport transport) {
    return TestInstrument.values
        .where((instrument) => instrument.supportedTransports.contains(transport))
        .toList();
  }

  void reset(String portText) {
    final d = PulseTestConfig.defaults;
    drainTransport = CommTransport.serial;
    gateTransport = d.transport;
    pulseGeneratorTransport = CommTransport.serial;
    pulseScopeTransport = CommTransport.visa;
    pulseCurrentTransport = CommTransport.visa;
    drainInstrument = TestInstrument.afg2225;
    gateInstrument = TestInstrument.afg2225;
    pulseGeneratorInstrument = TestInstrument.afg2225;
    pulseScopeInstrument = TestInstrument.oscilloscope;
    pulseCurrentInstrument = TestInstrument.currentMeter;
    drainConnection = ConnectionStateView.idle;
    gateConnection = ConnectionStateView.idle;
    pulseGeneratorConnection = ConnectionStateView.idle;
    pulseScopeConnection = ConnectionStateView.idle;
    pulseCurrentConnection = ConnectionStateView.idle;
    drainDetail = 'Defaults restored.';
    gateDetail = 'Defaults restored.';
    pulseGeneratorDetail = 'Defaults restored.';
    pulseScopeDetail = 'Defaults restored.';
    pulseCurrentDetail = 'Defaults restored.';
    gateMeasurementMode = GateMeasurementMode.dc;
    syncVisaSelections(preserveExisting: true, portText: portText);
  }

  void syncVisaSelections({required bool preserveExisting, required String portText}) {
    if (resources.isEmpty) {
      drainResource = '';
      gateResource = '';
      pulseGeneratorResource = '';
      pulseScopeResource = '';
      pulseCurrentResource = '';
      return;
    }
    if (!preserveExisting || !resources.contains(drainResource)) {
      drainResource = resources.first;
    }
    if (!preserveExisting || !resources.contains(gateResource)) {
      gateResource = resources.length >= 2 ? resources[1] : resources.first;
    }
    if (!preserveExisting || !resources.contains(pulseGeneratorResource)) {
      pulseGeneratorResource = resources.first;
    }
    if (!preserveExisting || !resources.contains(pulseScopeResource)) {
      pulseScopeResource = resources.length >= 2 ? resources[1] : resources.first;
    }
    if (!preserveExisting || !resources.contains(pulseCurrentResource)) {
      pulseCurrentResource = resources.length >= 3 ? resources[2] : resources.last;
    }
  }

  void setGateMode(GateMeasurementMode mode) {
    gateMeasurementMode = mode;
    gateDetail = 'Gate mode changed to ${mode.label}.';
  }

  void onTransportChanged(DeviceRole role, CommTransport? value, String portText) {
    if (value == null) return;
    if (role == DeviceRole.drain) {
      drainTransport = value;
    } else {
      gateTransport = value;
    }
    final available = availableInstrumentsFor(value);
    if (!available.contains(instrumentFor(role)) && available.isNotEmpty) {
      if (role == DeviceRole.drain) {
        drainInstrument = available.first;
      } else {
        gateInstrument = available.first;
      }
    }
    if (value == CommTransport.visa) {
      syncVisaSelections(preserveExisting: true, portText: portText);
    }
    if (role == DeviceRole.drain) {
      drainConnection = ConnectionStateView.idle;
      drainDetail = 'Transport changed to ${value.label}';
    } else {
      gateConnection = ConnectionStateView.idle;
      gateDetail = 'Transport changed to ${value.label}';
    }
  }

  void onInstrumentChanged(DeviceRole role, TestInstrument? value) {
    if (value == null) return;
    if (role == DeviceRole.drain) {
      drainInstrument = value;
      drainConnection = ConnectionStateView.idle;
      drainDetail = 'Selected ${value.label}';
    } else {
      gateInstrument = value;
      gateConnection = ConnectionStateView.idle;
      gateDetail = 'Selected ${value.label}';
    }
  }

  void onPulseTransportChanged(PulseDeviceRole role, CommTransport? value, String portText) {
    if (value == null) return;
    switch (role) {
      case PulseDeviceRole.generator:
        pulseGeneratorTransport = value;
      case PulseDeviceRole.oscilloscope:
        pulseScopeTransport = value;
      case PulseDeviceRole.current:
        pulseCurrentTransport = value;
    }
    final available = availableInstrumentsFor(value);
    if (!available.contains(pulseInstrumentFor(role)) && available.isNotEmpty) {
      switch (role) {
        case PulseDeviceRole.generator:
          pulseGeneratorInstrument = available.first;
        case PulseDeviceRole.oscilloscope:
          pulseScopeInstrument = available.first;
        case PulseDeviceRole.current:
          pulseCurrentInstrument = available.first;
      }
    }
    if (value == CommTransport.visa) {
      syncVisaSelections(preserveExisting: true, portText: portText);
    }
    setPulseConnection(role, ConnectionStateView.idle);
    setPulseDetail(role, 'Transport changed to ${value.label}');
  }

  void onPulseInstrumentChanged(PulseDeviceRole role, TestInstrument? value) {
    if (value == null) return;
    switch (role) {
      case PulseDeviceRole.generator:
        pulseGeneratorInstrument = value;
      case PulseDeviceRole.oscilloscope:
        pulseScopeInstrument = value;
      case PulseDeviceRole.current:
        pulseCurrentInstrument = value;
    }
    setPulseConnection(role, ConnectionStateView.idle);
    setPulseDetail(role, 'Selected ${value.label}');
  }

  void onVisaResourceChanged(DeviceRole role, String value) {
    if (role == DeviceRole.drain) {
      drainResource = value;
      drainConnection = ConnectionStateView.idle;
      drainDetail = 'Selected Drain: ${resourceLabel(value)}';
    } else {
      gateResource = value;
      gateConnection = ConnectionStateView.idle;
      gateDetail = 'Selected Gate: ${resourceLabel(value)}';
    }
  }

  void onPulseVisaResourceChanged(PulseDeviceRole role, String value) {
    switch (role) {
      case PulseDeviceRole.generator:
        pulseGeneratorResource = value;
      case PulseDeviceRole.oscilloscope:
        pulseScopeResource = value;
      case PulseDeviceRole.current:
        pulseCurrentResource = value;
    }
    setPulseConnection(role, ConnectionStateView.idle);
    setPulseDetail(role, 'Selected ${role.label}: ${resourceLabel(value)}');
  }

  Future<void> checkConnection(DeviceRole role, String portText) async {
    final transport = transportFor(role);
    final target = targetFor(role, portText);
    final duplicatedConnection = _hasConnectedTarget(
      transport: transport,
      target: target,
      portText: portText,
      excludeRole: role,
    );
    if (role == DeviceRole.drain) {
      drainConnection = ConnectionStateView.checking;
      drainDetail = 'Running *IDN? handshake on $target via ${transport.label}';
    } else {
      gateConnection = ConnectionStateView.checking;
      gateDetail = 'Running *IDN? handshake on $target via ${transport.label}';
    }
    try {
      final result = await _bridge.identify(target: target, transport: transport);
      if (role == DeviceRole.drain) {
        drainConnection = result.success
            ? (duplicatedConnection ? ConnectionStateView.rechecked : ConnectionStateView.connected)
            : ConnectionStateView.failed;
        drainDetail = result.summary;
      } else {
        gateConnection = result.success
            ? (duplicatedConnection ? ConnectionStateView.rechecked : ConnectionStateView.connected)
            : ConnectionStateView.failed;
        gateDetail = result.summary;
      }
    } catch (error) {
      if (role == DeviceRole.drain) {
        drainConnection = ConnectionStateView.failed;
        drainDetail = 'Handshake failed: $error';
      } else {
        gateConnection = ConnectionStateView.failed;
        gateDetail = 'Handshake failed: $error';
      }
      rethrow;
    }
  }

  Future<void> checkPulseConnection(PulseDeviceRole role, String portText) async {
    final transport = pulseTransportFor(role);
    final target = pulseTargetFor(role, portText);
    final duplicatedConnection = _hasConnectedTarget(
      transport: transport,
      target: target,
      portText: portText,
      excludePulseRole: role,
    );
    setPulseConnection(role, ConnectionStateView.checking);
    setPulseDetail(role, 'Running *IDN? handshake on $target via ${transport.label}');
    try {
      final result = await _bridge.identify(target: target, transport: transport);
      setPulseConnection(
        role,
        result.success
            ? (duplicatedConnection ? ConnectionStateView.rechecked : ConnectionStateView.connected)
            : ConnectionStateView.failed,
      );
      setPulseDetail(role, result.summary);
    } catch (error) {
      setPulseConnection(role, ConnectionStateView.failed);
      setPulseDetail(role, 'Handshake failed: $error');
      rethrow;
    }
  }

  void applyResourceScan(ResourceScanResult update, String portText, String Function(String idn) extractDeviceName) {
    resources
      ..clear()
      ..addAll(update.resources);
    resourceToDeviceName
      ..clear()
      ..addEntries(update.resources.map((resource) => MapEntry(resource, resource)));
    for (final entry in update.resourceToName.entries) {
      resourceToDeviceName[entry.key] = extractDeviceName(entry.value);
    }
    syncVisaSelections(preserveExisting: true, portText: portText);
    loadingResources = update.running;
  }

  bool _isConnectedState(ConnectionStateView state) {
    return state == ConnectionStateView.connected || state == ConnectionStateView.rechecked;
  }

  bool _hasConnectedTarget({
    required CommTransport transport,
    required String target,
    required String portText,
    DeviceRole? excludeRole,
    PulseDeviceRole? excludePulseRole,
  }) {
    if (target.isEmpty) {
      return false;
    }

    if (excludeRole != DeviceRole.drain &&
        _isConnectedState(drainConnection) &&
        drainTransport == transport &&
        targetFor(DeviceRole.drain, portText) == target) {
      return true;
    }
    if (excludeRole != DeviceRole.gate &&
        _isConnectedState(gateConnection) &&
        gateTransport == transport &&
        targetFor(DeviceRole.gate, portText) == target) {
      return true;
    }
    if (excludePulseRole != PulseDeviceRole.generator &&
        _isConnectedState(pulseGeneratorConnection) &&
        pulseGeneratorTransport == transport &&
        pulseTargetFor(PulseDeviceRole.generator, portText) == target) {
      return true;
    }
    if (excludePulseRole != PulseDeviceRole.oscilloscope &&
        _isConnectedState(pulseScopeConnection) &&
        pulseScopeTransport == transport &&
        pulseTargetFor(PulseDeviceRole.oscilloscope, portText) == target) {
      return true;
    }
    if (excludePulseRole != PulseDeviceRole.current &&
        _isConnectedState(pulseCurrentConnection) &&
        pulseCurrentTransport == transport &&
        pulseTargetFor(PulseDeviceRole.current, portText) == target) {
      return true;
    }

    return false;
  }

  String resourceLabel(String resource) {
    final name = resourceToDeviceName[resource];
    if (name == null || name.isEmpty || name == resource) {
      return resource;
    }
    return '$name ($resource)';
  }

  String activeGateInstrumentLabel() {
    if (gateMeasurementMode == GateMeasurementMode.pulse) {
      return pulseGeneratorInstrument.label;
    }
    return gateInstrument.label;
  }

  bool canRunGate() {
    if (gateMeasurementMode == GateMeasurementMode.pulse) {
      return pulseGeneratorTransport == CommTransport.visa ||
          pulseGeneratorInstrument == TestInstrument.afg2225;
    }
    return canControl(DeviceRole.gate);
  }

  CommTransport activeGateTransport() {
    return gateMeasurementMode == GateMeasurementMode.pulse
        ? pulseGeneratorTransport
        : gateTransport;
  }

  String activeGateTarget(String portText) {
    return gateMeasurementMode == GateMeasurementMode.pulse
        ? pulseTargetFor(PulseDeviceRole.generator, portText)
        : portText.trim();
  }

  void setPulseConnection(PulseDeviceRole role, ConnectionStateView value) {
    switch (role) {
      case PulseDeviceRole.generator:
        pulseGeneratorConnection = value;
        return;
      case PulseDeviceRole.oscilloscope:
        pulseScopeConnection = value;
        return;
      case PulseDeviceRole.current:
        pulseCurrentConnection = value;
        return;
    }
  }

  void setPulseDetail(PulseDeviceRole role, String value) {
    switch (role) {
      case PulseDeviceRole.generator:
        pulseGeneratorDetail = value;
        return;
      case PulseDeviceRole.oscilloscope:
        pulseScopeDetail = value;
        return;
      case PulseDeviceRole.current:
        pulseCurrentDetail = value;
        return;
    }
  }
}
