import 'package:flutter/material.dart';

// 여러 화면에서 재사용할 수 있는 공통 카드/섹션 위젯 모음이다.
// 실제 데이터 처리보다 레이아웃과 시각적 표현을 담당한다.
class InstrumentSelectionCard extends StatelessWidget {
  const InstrumentSelectionCard({
    super.key,
    required this.drainChild,
    required this.gateChild,
    this.sideAction,
  });

  final Widget drainChild;
  final Widget gateChild;
  final Widget? sideAction;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Instrument Selection',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 20),
                ),
                const Spacer(),
                if (sideAction != null) sideAction!,
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Run a real connection check before starting the sweep.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 900) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // [Drain 전체폭]
                      Expanded(flex: 2, child: drainChild),
                      const SizedBox(width: 10),
                      Expanded(flex: 7, child: gateChild),
                    ],
                  );
                }
                return Column(
                  children: [
                    drainChild,
                    const SizedBox(height: 10),
                    gateChild,
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class ChannelSectionCard extends StatelessWidget {
  const ChannelSectionCard({
    super.key,
    required this.title,
    required this.detail,
    this.headerAction,
    this.modeSelector,
    required this.content,
  });

  final String title;
  final String detail;
  final Widget? headerAction;
  final Widget? modeSelector;
  final Widget content;

  @override
  Widget build(BuildContext context) {
    return Container(
      // [Drain 내부 여백]
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD7E2DB)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          textTheme: Theme.of(context).textTheme.apply(fontSizeFactor: 0.84),
          inputDecorationTheme: const InputDecorationTheme(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 13),
                ),
                if (headerAction != null) ...[
                  const SizedBox(width: 6),
                  headerAction!,
                ],
              ],
            ),
            if (modeSelector != null) ...[
              const SizedBox(height: 6),
              modeSelector!,
            ],
            const SizedBox(height: 6),
            content,
            const SizedBox(height: 6),
            Text('Status Detail: $detail', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class PulseModeSection extends StatelessWidget {
  const PulseModeSection({
    super.key,
    this.reloadButton,
    required this.children,
  });

  final Widget? reloadButton;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (reloadButton != null) ...[
          reloadButton!,
          const SizedBox(height: 6),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.start,
          children: children,
        ),
      ],
    );
  }
}

class PulseDeviceSectionCard extends StatelessWidget {
  const PulseDeviceSectionCard({
    super.key,
    required this.title,
    required this.content,
  });

  final String title;
  final Widget content;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBF8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDCE8DF)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          textTheme: Theme.of(context).textTheme.apply(fontSizeFactor: 0.84),
          inputDecorationTheme: const InputDecorationTheme(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
            ),
            const SizedBox(height: 6),
            content,
          ],
        ),
      ),
    );
  }
}

class SweepSetupCard extends StatelessWidget {
  const SweepSetupCard({
    super.key,
    required this.description,
    required this.selectedInstrumentLabel,
    required this.fields,
    required this.actions,
    this.warningText,
  });

  final String description;
  final String selectedInstrumentLabel;
  final List<Widget> fields;
  final List<Widget> actions;
  final String? warningText;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (description.isNotEmpty) ...[
              Text(description, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),
            ],
            if (selectedInstrumentLabel.isNotEmpty) ...[
              Text(selectedInstrumentLabel, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
            ],
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < fields.length; i++) ...[
                  fields[i],
                  if (i != fields.length - 1) const SizedBox(height: 16),
                ],
              ],
            ),
            const SizedBox(height: 20),
            Wrap(spacing: 12, runSpacing: 12, children: actions),
            if (warningText != null) ...[
              const SizedBox(height: 12),
              Text(warningText!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

class ExecutionLogCard extends StatelessWidget {
  const ExecutionLogCard({
    super.key,
    required this.running,
    required this.content,
  });

  final bool running;
  final Widget content;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Execution Log', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                if (running) const Chip(avatar: Icon(Icons.sync, size: 18), label: Text('Running')),
              ],
            ),
            const SizedBox(height: 16),
            content,
          ],
        ),
      ),
    );
  }
}

class ThermalCameraConfigCard extends StatelessWidget {
  const ThermalCameraConfigCard({
    super.key,
    required this.enabled,
    required this.busy,
    required this.leadingFields,
    required this.hostField,
    required this.portField,
    required this.onEnabledChanged,
    required this.onToggleStream,
    required this.streaming,
    this.footer,
  });

  final bool enabled;
  final bool busy;
  final List<Widget> leadingFields;
  final Widget hostField;
  final Widget portField;
  final ValueChanged<bool> onEnabledChanged;
  final VoidCallback onToggleStream;
  final bool streaming;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Thermal Camera', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Configure the Raspberry Pi thermal stream using the same host/port pattern.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 170,
                  child: SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Enable'),
                    value: enabled,
                    onChanged: busy && !streaming ? null : onEnabledChanged,
                  ),
                ),
                ...leadingFields,
                SizedBox(width: 220, child: hostField),
                SizedBox(width: 120, child: portField),
                SizedBox(
                  width: 150,
                  height: 40,
                  child: FilledButton(
                    onPressed: enabled && (!busy || streaming) ? onToggleStream : null,
                    child: Text(streaming ? 'Stop Camera' : 'Start Camera'),
                  ),
                ),
              ],
            ),
            if (footer != null) ...[
              const SizedBox(height: 10),
              footer!,
            ],
          ],
        ),
      ),
    );
  }
}

class ThermalPreviewCard extends StatelessWidget {
  const ThermalPreviewCard({
    super.key,
    required this.streaming,
    required this.infoText,
    required this.preview,
  });

  final bool streaming;
  final String infoText;
  final Widget preview;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Thermal View', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                if (streaming) const Chip(label: Text('Live')),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(height: 250, child: preview),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF6F8FA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFD0D7DE)),
              ),
              child: SelectableText(
                infoText,
                maxLines: 4,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
