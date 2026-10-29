import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:tronclass/auth/account_manager_page.dart';
import 'package:tronclass/auth/login_page.dart';
import 'package:tronclass/auth/login_controller.dart';
import 'package:tronclass/data/changke_client.dart';
import 'package:tronclass/data/get_storage.dart';
import 'package:tronclass/data/school_config.dart';
import 'package:tronclass/path.dart';
import 'package:tronclass/routes.dart';

class _DelayedPortalAdapter implements HttpClientAdapter {
  // Real I/O callbacks must be able to signal a fake-clock widget test.
  final started = Completer<void>.sync();
  final response = Completer<ResponseBody>.sync();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    if (!started.isCompleted) started.complete();
    return response.future;
  }

  @override
  void close({bool force = false}) {}
}

Widget loginHost() => GetMaterialApp(
  navigatorKey: AppRoute.navigatorKey,
  defaultTransition: Transition.noTransition,
  home: Scaffold(
    body: TextButton(
      onPressed: () => Get.toNamed(AppRoute.loginPage),
      child: const Text('Open login'),
    ),
  ),
  getPages: [
    GetPage(name: AppRoute.loginPage, page: () => const LoginPage()),
    GetPage(
      name: AppRoute.accountManagerPage,
      page: () => const AccountManagerPage(),
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory storageDirectory;

  setUpAll(() async {
    storageDirectory = await Directory.systemTemp.createTemp(
      'tronclass-login-',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => storageDirectory.path,
        );
    applicationSupportDirectory = storageDirectory;
    getStorage = GetStorage('login-lifecycle-test', storageDirectory.path);
    await getStorage.initStorage;
  });

  tearDown(() => Get.reset());

  tearDownAll(() async {
    try {
      await storageDirectory.delete(recursive: true);
    } on FileSystemException catch (error) {
      // GetStorage keeps its file handle open until the test process exits.
      if (error.osError?.errorCode != 32) rethrow;
    }
  });

  testWidgets('nested login pages keep independent form keys and input state', (
    tester,
  ) async {
    await tester.pumpWidget(
      GetMaterialApp(
        navigatorKey: AppRoute.navigatorKey,
        defaultTransition: Transition.noTransition,
        home: Scaffold(
          body: TextButton(
            onPressed: () => Get.toNamed(AppRoute.loginPage),
            child: const Text('Open login'),
          ),
        ),
        getPages: [
          GetPage(name: AppRoute.loginPage, page: () => const LoginPage()),
          GetPage(
            name: AppRoute.accountManagerPage,
            page: () => const AccountManagerPage(),
          ),
        ],
      ),
    );
    await tester.tap(find.text('Open login'));
    await tester.pumpAndSettle();
    final firstFormKey = tester.widget<Form>(find.byType(Form)).key;
    final firstController = tester
        .state<GetBuilderState<LoginController>>(
          find.byType(GetBuilder<LoginController>),
        )
        .controller!;
    await tester.enterText(find.byType(TextFormField).first, 'first-user');
    await tester.enterText(find.byType(TextFormField).last, 'first-password');
    await tester.ensureVisible(find.text('管理已保存账号'));
    await tester.tap(find.text('管理已保存账号'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加账号'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final secondFormKey = tester.widget<Form>(find.byType(Form)).key;
    final secondController = tester
        .state<GetBuilderState<LoginController>>(
          find.byType(GetBuilder<LoginController>),
        )
        .controller!;
    expect(firstController.isClosed, isFalse);
    expect(secondController, isNot(same(firstController)));
    expect(secondFormKey, isNot(same(firstFormKey)));
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).first)
          .controller!
          .text,
      isEmpty,
    );
    Get.back<void>();
    await tester.pumpAndSettle();
    expect(secondController.isClosed, isTrue);
    expect(firstController.isClosed, isFalse);
    Get.back<void>();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).first)
          .controller!
          .text,
      'first-user',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(firstController.isClosed, isTrue);
  });

  testWidgets('nested login success can close all login routes safely', (
    tester,
  ) async {
    await tester.pumpWidget(loginHost());
    await tester.tap(find.text('Open login'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('管理已保存账号'));
    await tester.tap(find.text('管理已保存账号'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加账号'));
    await tester.pumpAndSettle();
    Get.back(result: true);
    await tester.pumpAndSettle();
    expect(find.text('Open login'), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'a login response after leaving the page cannot pop the new page',
    (tester) async {
      final client = ChangkeClient.getInstance(username: 'late-test-user');
      final adapter = _DelayedPortalAdapter();
      client.dio.httpClientAdapter = adapter;
      client.dio.interceptors.clear();
      await tester.runAsync(
        () => client.cookieJar.saveFromResponse(
          Uri.parse(SchoolConfig.portalUrl),
          [
            Cookie('session', 'test-session'),
            Cookie('role_token', 'test-role'),
          ],
        ),
      );
      await tester.pumpWidget(loginHost());
      await tester.tap(find.text('Open login'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).first,
        'late-test-user',
      );
      await tester.enterText(find.byType(TextFormField).last, 'test-password');
      final controller = tester
          .state<GetBuilderState<LoginController>>(
            find.byType(GetBuilder<LoginController>),
          )
          .controller!;
      late Future<void> pendingLogin;
      await tester.runAsync(() async {
        pendingLogin = controller.submit();
        expect(controller.isSubmitting.value, isTrue);
        await adapter.started.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw StateError('Mock request did not start'),
        );
      });
      Get.back<void>();
      await tester.pumpAndSettle();
      expect(controller.isClosed, isTrue);
      Get.to(
        () => const Scaffold(body: Text('Replacement page')),
        transition: Transition.noTransition,
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        adapter.response.complete(
          ResponseBody.fromString('<html>Portal</html>', 200),
        );
        await pendingLogin.timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw StateError('Mock login did not finish'),
        );
        await getStorage.save();
      });
      await tester.pumpAndSettle();
      expect(find.text('Replacement page'), findsOneWidget);
      expect(getStorage.read<dynamic>(GetStorageKeys.savedAccounts), isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      client.dio.close(force: true);
    },
  );
}
