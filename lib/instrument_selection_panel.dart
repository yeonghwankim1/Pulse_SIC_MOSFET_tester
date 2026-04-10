import 'package:flutter/material.dart';

import 'instrument_service.dart';
import 'pulse_tester_types.dart';
import 'pulse_tester_widgets.dart';

// Instrument Selection 영역 전체를 담당하는 파일이다.
// Drain/Gate 섹션, Gate의 DC/PULSE 전환, PULSE 하위 장비 UI를 여기서 구성한다.
class ChannelUiState {
  const ChannelUiState({
    required this.transport,
    required this.instrument,
    required this.connection,
    required this.detail,
    required this.visaResource,
  });

  final CommTransport transport;
  final TestInstrument instrument;
  final ConnectionStateView connection;
  final String detail;
  final String visaResource;
}

class PulseDeviceUiState {
  const PulseDeviceUiState({
    required this.transport,
    required this.instrument,
    required this.connection,
    required this.detail,
    required this.visaResource,
  });

  final CommTransport transport;
  final TestInstrument instrument;
  final ConnectionStateView connection;
  final String detail;
  final String visaResource;
}

class InstrumentSelectionPanel extends StatelessWidget {
  const InstrumentSelectionPanel({
    super.key,
    required this.running,
    required this.loadingResources,
    required this.resources,
    required this.resourceToDeviceName,
    required this.gateMeasurementMode,
    required this.drainState,
    required this.gateState,
    required this.generatorState,
    required this.scopeState,
    required this.currentState,
    required this.onGateModeChanged,
    required this.onTransportChanged,
    required this.onInstrumentChanged,
    required this.onCheckConnection,
    required this.onReloadResources,
    required this.onVisaResourceChanged,
    required this.onPulseTransportChanged,
    required this.onPulseInstrumentChanged,
    required this.onPulseCheckConnection,
    required this.onPulseVisaResourceChanged,
  });

  final bool running;
  final bool loadingResources;
  final List<String> resources;
  final Map<String, String> resourceToDeviceName;
  final GateMeasurementMode gateMeasurementMode;
  final ChannelUiState drainState;
  final ChannelUiState gateState;
  final PulseDeviceUiState generatorState;
  final PulseDeviceUiState scopeState;
  final PulseDeviceUiState currentState;
  final ValueChanged<GateMeasurementMode> onGateModeChanged;
  final void Function(DeviceRole role, CommTransport? value) onTransportChanged;
  final void Function(DeviceRole role, TestInstrument? value) onInstrumentChanged;
  final void Function(DeviceRole role) onCheckConnection;
  final VoidCallback onReloadResources;
  final void Function(DeviceRole role, String value) onVisaResourceChanged;
  final void Function(PulseDeviceRole role, CommTransport? value) onPulseTransportChanged;
  final void Function(PulseDeviceRole role, TestInstrument? value) onPulseInstrumentChanged;
  final void Function(PulseDeviceRole role) onPulseCheckConnection;
  final void Function(PulseDeviceRole role, String value) onPulseVisaResourceChanged;

  @override
  Widget build(BuildContext context) {
    return InstrumentSelectionCard(
      sideAction: _showVisaReload() ? _reloadButton() : null,
      drainChild: _channelSection(context, DeviceRole.drain, drainState),
      gateChild: _channelSection(context, DeviceRole.gate, gateState),
    );
  }

  Widget _channelSection(BuildContext context, DeviceRole role, ChannelUiState state) {
    final transportWidth = role == DeviceRole.drain ? 110.0 : 120.0;
    final targetWidth = 170.0;
    final checkButtonStyle = _checkButtonStyle(state.connection);

    return ChannelSectionCard(
      title: role.label,
      detail: state.detail,
      modeSelector: role == DeviceRole.gate
          ? Wrap(
              spacing: 8,
              children: GateMeasurementMode.values
                  .map(
                    (mode) => ChoiceChip(
                      label: Text(mode.label),
                      selected: gateMeasurementMode == mode,
                      onSelected: running
                          ? null
                          : (selected) {
                              if (selected) {
                                onGateModeChanged(mode);
                              }
                            },
                    ),
                  )
                  .toList(),
            )
          : null,
      content: role == DeviceRole.gate && gateMeasurementMode == GateMeasurementMode.pulse
          ? _pulseModePanel()
          : _dcDevicePanel(
              role: role,
              state: state,
              transportWidth: transportWidth,
              targetWidth: targetWidth,
              checkButtonWidth: 96.0,
              checkButtonStyle: checkButtonStyle,
            ),
    );
  }

  bool _showVisaReload() {
    return drainState.transport == CommTransport.visa ||
        gateState.transport == CommTransport.visa ||
        generatorState.transport == CommTransport.visa ||
        scopeState.transport == CommTransport.visa ||
        currentState.transport == CommTransport.visa;
  }

  Widget _dcDevicePanel({
    required DeviceRole role,
    required ChannelUiState state,
    required double transportWidth,
    required double targetWidth,
    required double checkButtonWidth,
    required ButtonStyle checkButtonStyle,
  }) {
    return PulseDeviceSectionCard(
      title: '${role.label} DC',
      content: Wrap(
        spacing: role == DeviceRole.drain ? 4 : 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: transportWidth,
            child: DropdownButtonFormField<CommTransport>(
              initialValue: state.transport,
              decoration: InputDecoration(
                labelText: 'Transport',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              ),
              items: <CommTransport>[CommTransport.serial, CommTransport.visa]
                  .map((v) => DropdownMenuItem<CommTransport>(value: v, child: Text(v.label)))
                  .toList(),
              onChanged: running ? null : (value) => onTransportChanged(role, value),
            ),
          ),
          SizedBox(
            width: targetWidth,
            child: state.transport == CommTransport.visa
                ? _visaResourceDropdown(role, state.visaResource)
                : DropdownButtonFormField<TestInstrument>(
                    value: state.instrument,
                    decoration: InputDecoration(
                      labelText: _transportSelectionLabel(state.transport),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    items: _availableInstrumentsFor(state.transport)
                        .map((v) => DropdownMenuItem<TestInstrument>(value: v, child: Text(v.label)))
                        .toList(),
                    onChanged: running ? null : (value) => onInstrumentChanged(role, value),
                  ),
          ),
          SizedBox(
            width: checkButtonWidth,
            child: FilledButton.icon(
              style: checkButtonStyle,
              onPressed: running ? null : () => onCheckConnection(role),
              icon: const Icon(Icons.usb_rounded, size: 18),
              label: const Text('Check'),
            ),
          ),
          _infoIcon(
            '${state.instrument.label}\n'
            '${_instrumentDescription(state.instrument, state.transport)}\n'
            'Transport: ${state.transport.label}\n'
            '${state.transport.targetLabel}: ${_defaultTarget(state.instrument, state.transport, state.visaResource)}\n'
            'Connection Check: ${_connectionHint(state.instrument, state.transport)}',
          ),
        ],
      ),
    );
  }

  Widget _pulseModePanel() {
    return PulseModeSection(
      reloadButton: null,
      children: [
        _pulseDevicePanel(PulseDeviceRole.generator, generatorState),
        _pulseDevicePanel(PulseDeviceRole.oscilloscope, scopeState),
        _pulseDevicePanel(PulseDeviceRole.current, currentState),
      ],
    );
  }

  Widget _pulseDevicePanel(PulseDeviceRole role, PulseDeviceUiState state) {
    return PulseDeviceSectionCard(
      title: role.label,
      content: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 120,
            child: DropdownButtonFormField<CommTransport>(
              initialValue: state.transport,
              decoration: InputDecoration(
                labelText: 'Transport',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              ),
              items: <CommTransport>[CommTransport.serial, CommTransport.visa]
                  .map((v) => DropdownMenuItem<CommTransport>(value: v, child: Text(v.label)))
                  .toList(),
              onChanged: running ? null : (value) => onPulseTransportChanged(role, value),
            ),
          ),
          SizedBox(
            width: 170,
            child: state.transport == CommTransport.visa
                ? _pulseVisaResourceDropdown(role, state.visaResource)
                : DropdownButtonFormField<TestInstrument>(
                    value: state.instrument,
                    decoration: InputDecoration(
                      labelText: _transportSelectionLabel(state.transport),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    items: _availableInstrumentsFor(state.transport)
                        .map((v) => DropdownMenuItem<TestInstrument>(value: v, child: Text(v.label)))
                        .toList(),
                    onChanged: running ? null : (value) => onPulseInstrumentChanged(role, value),
                  ),
          ),
          SizedBox(
            width: 96,
            child: FilledButton.icon(
              style: _checkButtonStyle(state.connection),
              onPressed: running ? null : () => onPulseCheckConnection(role),
              icon: const Icon(Icons.usb_rounded, size: 18),
              label: const Text('Check'),
            ),
          ),
          _infoIcon(
            '${state.instrument.label}\n'
            '${_instrumentDescription(state.instrument, state.transport)}\n'
            'Transport: ${state.transport.label}\n'
            '${state.transport.targetLabel}: ${_defaultTarget(state.instrument, state.transport, state.visaResource)}\n'
            'Connection Check: ${_connectionHint(state.instrument, state.transport)}',
          ),
        ],
      ),
    );
  }

  Widget _visaResourceDropdown(DeviceRole role, String selectedResource) {
    return DropdownButtonFormField<String>(
      value: resources.contains(selectedResource) ? selectedResource : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Target Instrument',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
      items: resources
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
      selectedItemBuilder: (context) => resources
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
      onChanged: (running || loadingResources)
          ? null
          : (value) {
              if (value != null) {
                onVisaResourceChanged(role, value);
              }
            },
      hint: Text(loadingResources ? 'Loading VISA resources...' : 'Select VISA resource'),
    );
  }

  Widget _pulseVisaResourceDropdown(PulseDeviceRole role, String selectedResource) {
    return DropdownButtonFormField<String>(
      value: resources.contains(selectedResource) ? selectedResource : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Target Instrument',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
      items: resources
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
      selectedItemBuilder: (context) => resources
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
      onChanged: (running || loadingResources)
          ? null
          : (value) {
              if (value != null) {
                onPulseVisaResourceChanged(role, value);
              }
            },
      hint: Text(loadingResources ? 'Loading VISA resources...' : 'Select VISA resource'),
    );
  }

  ButtonStyle _checkButtonStyle(ConnectionStateView connection) {
    return switch (connection.presentation) {
      ConnectionStateView.connected => FilledButton.styleFrom(
          backgroundColor: const Color(0xFF2563EB),
          foregroundColor: Colors.white,
          visualDensity: VisualDensity.compact,
        ),
      ConnectionStateView.rechecked => FilledButton.styleFrom(
          backgroundColor: const Color(0xFFB26A00),
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
  }

  IconButton _reloadButton() {
    return IconButton(
      onPressed: (running || loadingResources) ? null : onReloadResources,
      tooltip: 'Reload VISA resources',
      icon: loadingResources
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh_rounded, size: 20),
    );
  }

  Widget _infoIcon(String message) {
    return Tooltip(
      message: message,
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
    );
  }

  String _resourceLabel(String resource) {
    final name = resourceToDeviceName[resource];
    if (name == null || name.isEmpty || name == resource) {
      return resource;
    }
    return '$name ($resource)';
  }

  String _resourceShortLabel(String resource) {
    final name = resourceToDeviceName[resource];
    if (name == null || name.isEmpty || name == resource) {
      return resource;
    }
    return name;
  }

  List<TestInstrument> _availableInstrumentsFor(CommTransport transport) {
    return TestInstrument.values
        .where((instrument) => instrument.supportedTransports.contains(transport))
        .toList();
  }

  String _transportSelectionLabel(CommTransport transport) {
    switch (transport) {
      case CommTransport.visa:
        return 'VISA Resource';
      case CommTransport.serial:
      case CommTransport.tcp:
        return 'Target Instrument';
    }
  }

  String _instrumentDescription(TestInstrument instrument, CommTransport transport) {
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

  String _connectionHint(TestInstrument instrument, CommTransport transport) {
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

  String _defaultTarget(TestInstrument instrument, CommTransport transport, String visaResource) {
    if (transport == CommTransport.visa) {
      return visaResource;
    }
    return transport.defaultTarget(instrument);
  }
}
