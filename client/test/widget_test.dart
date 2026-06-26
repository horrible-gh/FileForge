import 'package:flutter_test/flutter_test.dart';

import 'package:file_forge_app/app.dart';
import 'package:file_forge_app/providers/file_provider.dart';

void main() {
  testWidgets('App builds', (WidgetTester tester) async {
    await tester.pumpWidget(
      const App(initialViewMode: FileViewMode.list),
    );
    await tester.pump();
  });
}
