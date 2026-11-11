import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:tronclass/auth/login_diagnostics.dart';
import 'package:tronclass/auth/login_error_history_dialog.dart';
import 'package:tronclass/data/get_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('login-history-dialog-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
    getStorage = GetStorage('login-history-dialog-test', directory.path);
    await getStorage.initStorage;
  });

  setUp(() async => await LoginErrorHistory.clear());

  tearDownAll(() async {
    await getStorage.save();
    try {
      await directory.delete(recursive: true);
    } on FileSystemException catch (error) {
      if (error.osError?.errorCode != 32) rethrow;
    }
  });

  for (final size in [const Size(320, 568), const Size(800, 1024)]) {
    testWidgets('history fits $size and supports copy, clear and reopening', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final report = List.filled(
        20,
        'POST https://ids.cqupt.edu.cn/authserver/login\nHTTP: 401',
      ).join('\n');
      await tester.runAsync(
        () => LoginErrorHistory.add(
          LoginErrorRecord(
            time: DateTime(2026, 11, 11, 12),
            result: '出现错误后登录成功',
            report: report,
          ),
        ),
      );
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
                  builder: (_) => const LoginErrorHistoryDialog(),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('出现错误后登录成功'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('复制本条诊断'));
      await tester.pumpAndSettle();
      expect(copied, report);
      copied = null;
      await tester.tap(find.byTooltip('复制全部诊断'));
      await tester.pumpAndSettle();
      expect(copied, report);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('出现错误后登录成功'), findsOneWidget);
      await tester.tap(find.byTooltip('清空历史'));
      await tester.runAsync(() => getStorage.save());
      await tester.pumpAndSettle();
      expect(find.text('暂无登录报错记录'), findsOneWidget);
      expect(LoginErrorHistory.read(), isEmpty);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
