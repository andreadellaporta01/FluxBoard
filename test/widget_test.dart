import 'package:flutter_test/flutter_test.dart';

import 'package:fluxboard/main.dart';

void main() {
  testWidgets('FluxBoard renders its title', (WidgetTester tester) async {
    await tester.pumpWidget(const FluxBoardApp());
    await tester.pump();
    expect(find.text('FluxBoard'), findsOneWidget);
  });
}
