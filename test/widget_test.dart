import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_sic_mosfet_test/main.dart';

void main() {
  testWidgets('pulse tester screen renders controls', (WidgetTester tester) async {
    await tester.pumpWidget(const PulseTesterApp());

    expect(find.text('SiC MOSFET Pulse Tester'), findsOneWidget);
    expect(find.text('Instrument Selection'), findsOneWidget);
    expect(find.text('GW Instek AFG-2225'), findsOneWidget);
    expect(find.text('Sweep Setup'), findsOneWidget);
    expect(find.text('Start Sweep'), findsOneWidget);
    expect(find.text('Windows C++'), findsOneWidget);
    expect(find.text('Execution Log'), findsOneWidget);
  });
}
