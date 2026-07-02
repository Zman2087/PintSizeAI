// Basic smoke test — verifies PintSizeAiApp wraps in a ProviderScope correctly.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pintsize_ai/main.dart';

void main() {
  testWidgets('App builds without errors', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: PintSizeAiApp()),
    );
    expect(find.byType(PintSizeAiApp), findsOneWidget);
  });
}
