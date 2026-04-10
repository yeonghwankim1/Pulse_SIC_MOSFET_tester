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
            Text('Sweep Setup', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(description, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            Text(selectedInstrumentLabel, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 20),
            Wrap(spacing: 16, runSpacing: 16, children: fields),
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
