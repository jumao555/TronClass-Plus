import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tronclass/auth/login_dialogs.dart';
import 'package:tronclass/data/service/login.dart';

Future<Uint8List> captchaImage(WidgetTester tester) async {
  return (await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawColor(Colors.white, ui.BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(8, 8);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    return bytes!.buffer.asUint8List();
  }))!;
}

Widget dialogHost<T>({
  required Widget dialog,
  required ValueChanged<T?> result,
}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async => result(
            await showDialog<T>(
              context: context,
              builder: (_) => dialog,
              barrierDismissible: false,
            ),
          ),
          child: const Text('Open dialog'),
        ),
      ),
    ),
  );
}

void main() {
  for (final confirm in [true, false]) {
    testWidgets(
      'captcha closes safely while its text field is focused ($confirm)',
      (tester) async {
        String? result;
        await tester.pumpWidget(
          dialogHost<String>(
            dialog: LoginCaptchaDialog(image: await captchaImage(tester)),
            result: (value) => result = value,
          ),
        );
        await tester.tap(find.text('Open dialog'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '1234');
        await tester.tap(find.text(confirm ? '确定' : '取消'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);
        await tester.pumpAndSettle();
        expect(result, confirm ? '1234' : isNull);
        expect(find.byType(LoginCaptchaDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('late SMS send result cannot update a closed dialog', (
    tester,
  ) async {
    final pending = Completer<DynamicCodeResponse>();
    await tester.pumpWidget(
      dialogHost<bool>(
        dialog: LoginVerificationDialog(
          sendCode: () => pending.future,
          verifyCode: (_) async => ReAuthResponse(code: 'reAuth_success'),
        ),
        result: (_) {},
      ),
    );
    await tester.tap(find.text('Open dialog'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('发送验证码'));
    await tester.pump();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    pending.complete(
      DynamicCodeResponse(codeTime: 120, mobile: 'masked-number'),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LoginVerificationDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late SMS verification cannot pop a different route', (
    tester,
  ) async {
    final pending = Completer<ReAuthResponse>();
    await tester.pumpWidget(
      dialogHost<bool>(
        dialog: LoginVerificationDialog(
          sendCode: () async => DynamicCodeResponse(),
          verifyCode: (_) => pending.future,
        ),
        result: (_) {},
      ),
    );
    await tester.tap(find.text('Open dialog'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('验证并继续'));
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    pending.complete(ReAuthResponse(code: 'reAuth_success'));
    await tester.pumpAndSettle();
    expect(find.text('Open dialog'), findsOneWidget);
    expect(find.byType(LoginVerificationDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'successful SMS verification completes without rebuilding the closing dialog',
    (tester) async {
      bool? result;
      await tester.pumpWidget(
        dialogHost<bool>(
          dialog: LoginVerificationDialog(
            sendCode: () async => DynamicCodeResponse(),
            verifyCode: (_) async => ReAuthResponse(code: 'reAuth_success'),
          ),
          result: (value) => result = value,
        ),
      );
      await tester.tap(find.text('Open dialog'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '123456');
      await tester.tap(find.text('验证并继续'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
      expect(find.byType(LoginVerificationDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('SMS countdown is cancelled on system back', (tester) async {
    await tester.pumpWidget(
      dialogHost<bool>(
        dialog: LoginVerificationDialog(
          sendCode: () async => DynamicCodeResponse(codeTime: 2),
          verifyCode: (_) async => ReAuthResponse(),
        ),
        result: (_) {},
      ),
    );
    await tester.tap(find.text('Open dialog'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('发送验证码'));
    await tester.pump();
    expect(find.text('2s'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(LoginVerificationDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
