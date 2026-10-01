import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilipala/pages/video/detail/widgets/audio_time_jump_dialog.dart';

void main() {
  Future<void> openDialog(WidgetTester tester, ValueChanged<Duration?> result,
      {Duration duration = const Duration(hours: 2)}) async {
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      return Scaffold(
          body: TextButton(
        onPressed: () async {
          result(await showDialog<Duration>(
              context: context,
              builder: (_) => AudioTimeJumpDialog(
                  position: const Duration(seconds: 12), duration: duration)));
        },
        child: const Text('打开'),
      ));
    })));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
  }

  testWidgets('accepts hours minutes seconds and returns precise position',
      (tester) async {
    Duration? result;
    await openDialog(tester, (value) => result = value);
    await tester.enterText(find.byType(TextFormField).at(0), '1');
    await tester.enterText(find.byType(TextFormField).at(1), '23');
    await tester.enterText(find.byType(TextFormField).at(2), '45');
    await tester.tap(find.text('跳转'));
    await tester.pumpAndSettle();
    expect(result, const Duration(hours: 1, minutes: 23, seconds: 45));
  });

  testWidgets('rejects invalid minute and out of range duration',
      (tester) async {
    await openDialog(tester, (_) {});
    await tester.enterText(find.byType(TextFormField).at(1), '60');
    await tester.tap(find.text('跳转'));
    await tester.pumpAndSettle();
    expect(find.text('最多 59'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(1), '0');
    await tester.enterText(find.byType(TextFormField).at(0), '3');
    await tester.tap(find.text('跳转'));
    await tester.pumpAndSettle();
    expect(find.text('跳转时间不能超过音频总时长'), findsOneWidget);
  });

  testWidgets('zero and exact duration are valid', (tester) async {
    Duration? result;
    await openDialog(tester, (value) => result = value,
        duration: const Duration(seconds: 12));
    await tester.tap(find.text('跳转'));
    await tester.pumpAndSettle();
    expect(result, const Duration(seconds: 12));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(2), '0');
    await tester.tap(find.text('跳转'));
    await tester.pumpAndSettle();
    expect(result, Duration.zero);
  });

  testWidgets('cancel does not request a seek', (tester) async {
    Duration? result = Duration.zero;
    await openDialog(tester, (value) => result = value);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
