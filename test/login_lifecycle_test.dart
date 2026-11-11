import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:tronclass/auth/account_manager_page.dart';
import 'package:tronclass/auth/login_page.dart';
import 'package:tronclass/auth/login_controller.dart';
import 'package:tronclass/auth/login_diagnostics.dart';
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

class _RejectedLoginAdapter implements HttpClientAdapter {
  int passwordSubmissions = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.uri.path == '/user/index') {
      final service =
          '${SchoolConfig.identityBaseUrl}'
          '/auth/realms/cqupt/broker/cas-client/endpoint?state=PRIVATE_STATE';
      final login = Uri.parse(
        '${SchoolConfig.casBaseUrl}authserver/login',
      ).replace(queryParameters: {'service': service});
      return ResponseBody.fromString(
        '',
        302,
        headers: {
          'location': [login.toString()],
        },
      );
    }
    if (options.uri.path == '/authserver/checkNeedCaptcha.htl') {
      return ResponseBody.fromString('{"isNeed":false}', 200);
    }
    if (options.uri.path == '/authserver/login') {
      if (options.method == 'POST') {
        passwordSubmissions++;
        return ResponseBody.fromString(
          '<html><div id="showErrorTip">Login failed</div></html>',
          401,
          headers: {
            'content-type': ['text/html'],
          },
        );
      }
      return ResponseBody.fromString(
        '<html><input name="pwdEncryptSalt" value="0123456789abcdef">'
        '<input name="execution" value="PRIVATE_EXECUTION"></html>',
        200,
        headers: {
          'content-type': ['text/html'],
        },
      );
    }
    throw StateError('Unexpected mock request');
  }

  @override
  void close({bool force = false}) {}
}

Widget loginHost() => GetMaterialApp(
  navigatorKey: AppRoute.navigatorKey,
  builder: FToastBuilder(),
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

  testWidgets(
    'small-screen feedback opens this repository in an external browser',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Map<dynamic, dynamic>? launchArguments;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/url_launcher'),
        (call) async {
          if (call.method == 'launch') launchArguments = call.arguments as Map;
          return true;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/url_launcher'),
          null,
        ),
      );
      await tester.pumpWidget(loginHost());
      await tester.tap(find.text('Open login'));
      await tester.pumpAndSettle();
      final feedback = find.widgetWithText(TextButton, '反馈问题');
      expect(tester.getRect(feedback).right, lessThanOrEqualTo(320));
      expect(tester.getRect(feedback).bottom, lessThanOrEqualTo(568));
      expect(tester.takeException(), isNull);
      await tester.tap(feedback);
      await tester.pumpAndSettle();
      expect(
        launchArguments?['url'],
        'https://github.com/jumao555/TronClass-Plus/issues/new',
      );
      expect(launchArguments?['useWebView'], isFalse);
      expect(launchArguments?['useSafariVC'], isFalse);
      expect(find.byType(LoginPage), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('a failed feedback launch leaves login usable', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'),
      (_) async => false,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/url_launcher'),
        null,
      ),
    );
    await tester.pumpWidget(loginHost());
    await tester.tap(find.text('Open login'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('反馈问题'));
    await tester.pumpAndSettle();
    expect(find.text('无法打开 GitHub，请稍后重试'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'test-user');
    expect(find.text('test-user'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('login history entry opens without affecting form input', (
    tester,
  ) async {
    await tester.pumpWidget(loginHost());
    await tester.tap(find.text('Open login'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).first,
      'history-test-user',
    );
    await tester.tap(find.byTooltip('登录报错历史'));
    await tester.pumpAndSettle();
    expect(find.text('暂无登录报错记录'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('history-test-user'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
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

  testWidgets(
    'failed login saves all existing retries and opens their diagnostic',
    (tester) async {
      const username = 'history-401-user';
      const password = 'PRIVATE_PASSWORD';
      final client = ChangkeClient.getInstance(username: username);
      final adapter = _RejectedLoginAdapter();
      client.dio.httpClientAdapter = adapter;
      client.casDio.httpClientAdapter = adapter;
      final originalMainInterceptors = client.dio.interceptors.toList();
      final originalCasInterceptors = client.casDio.interceptors.toList();
      await tester.pumpWidget(loginHost());
      await tester.tap(find.text('Open login'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, username);
      await tester.enterText(find.byType(TextFormField).last, password);
      final controller = tester
          .state<GetBuilderState<LoginController>>(
            find.byType(GetBuilder<LoginController>),
          )
          .controller!;
      await tester.runAsync(() async {
        await controller.submit().timeout(const Duration(seconds: 10));
        await getStorage.save();
      });
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(adapter.passwordSubmissions, 3);
      expect(controller.isSubmitting.value, isFalse);
      expect(client.dio.interceptors, orderedEquals(originalMainInterceptors));
      expect(
        client.casDio.interceptors,
        orderedEquals(originalCasInterceptors),
      );
      final record = LoginErrorHistory.read().single;
      expect(record.result, '登录失败');
      expect(record.report, contains('HTTP: 401'));
      expect(record.report, contains('第 3 轮登录尝试'));
      for (final secret in [
        username,
        password,
        'PRIVATE_STATE',
        'PRIVATE_EXECUTION',
      ]) {
        expect(record.report, isNot(contains(secret)));
      }
      await tester.tap(find.byTooltip('登录报错历史'));
      await tester.pumpAndSettle();
      expect(find.text(record.report), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      client.dio.close(force: true);
      client.casDio.close(force: true);
    },
  );
}
