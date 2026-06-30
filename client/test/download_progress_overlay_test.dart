import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_forge_app/widgets/download_progress_overlay.dart';

/// fileforge.ui.0002 ("고스트 다운로드") — load-bearing guard for the
/// download in-flight indicator. Before this slice a file download showed
/// nothing on screen until the terminal toast; these tests pin that the
/// overlay (1) appears immediately and indeterminate, (2) becomes a
/// determinate percentage as progress arrives, (3) blocks input so a second
/// tap cannot restart the download, and (4) is removed on hide().
void main() {
  Future<DownloadProgressOverlay> pumpAndShow(
    WidgetTester tester, {
    required String label,
    String Function(int)? percentLabel,
  }) async {
    late DownloadProgressOverlay handle;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                handle = DownloadProgressOverlay.show(
                  context,
                  label: label,
                  percentLabel: percentLabel,
                );
              },
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    return handle;
  }

  testWidgets('shows an indeterminate spinner with the label on start',
      (tester) async {
    final handle = await pumpAndShow(tester,
        label: 'Downloading…',
        percentLabel: (p) => 'Downloading… $p%');

    expect(find.text('Downloading…'), findsOneWidget);
    // ModalBarrier blocks the underlying button → no duplicate-tap restart.
    expect(find.byType(ModalBarrier), findsWidgets);

    final indicator = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator));
    expect(indicator.value, isNull,
        reason: 'indeterminate until a total size is known');

    handle.hide();
    await tester.pump();
  });

  testWidgets('becomes determinate and shows percent as progress arrives',
      (tester) async {
    final handle = await pumpAndShow(tester,
        label: 'Downloading…',
        percentLabel: (p) => 'Downloading… $p%');

    handle.onProgress(50, 100);
    await tester.pump();

    final indicator = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator));
    expect(indicator.value, closeTo(0.5, 0.0001));
    expect(find.text('Downloading… 50%'), findsOneWidget);
    expect(find.text('Downloading…'), findsNothing);

    handle.hide();
    await tester.pump();
  });

  testWidgets('stays indeterminate when total is unknown (-1)',
      (tester) async {
    final handle = await pumpAndShow(tester,
        label: 'Downloading…',
        percentLabel: (p) => 'Downloading… $p%');

    handle.onProgress(1234, -1); // server omitted Content-Length
    await tester.pump();

    final indicator = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator));
    expect(indicator.value, isNull);
    expect(find.text('Downloading…'), findsOneWidget);

    handle.hide();
    await tester.pump();
  });

  testWidgets('hide() removes the overlay and is idempotent', (tester) async {
    final handle = await pumpAndShow(tester,
        label: 'Downloading…',
        percentLabel: (p) => 'Downloading… $p%');

    expect(find.text('Downloading…'), findsOneWidget);

    handle.hide();
    await tester.pump();
    expect(find.text('Downloading…'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // Second hide() must not throw.
    handle.hide();
    // Late progress after hide() is ignored (no disposed-notifier crash).
    handle.onProgress(10, 100);
    await tester.pump();
  });
}
