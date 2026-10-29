import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tronclass/tronclass/qr_rollcalls/qr_sign_diagnostics_dialog.dart';

void main() {
  for (final size in [const Size(320, 568), const Size(800, 1024)]) {
    testWidgets('diagnostics fit $size and can be copied', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const report =
          'HTTP: 401\n'
          '请求: PUT http://lms.tc.cqupt.edu.cn/api/rollcall/:id/answer_qr_rollcall\n'
          '结果: 登录已失效，请重新登录后再扫码';
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = call.arguments['text'];
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const QrSignDiagnosticsDialog(report: report),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('扫码错误详情'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('复制诊断信息'));
      await tester.pumpAndSettle();
      expect(copied, report);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(find.text('扫码错误详情'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
