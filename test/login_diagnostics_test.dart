import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:get_storage/get_storage.dart';
import 'package:tronclass/auth/login_diagnostics.dart';
import 'package:tronclass/data/get_storage.dart';
import 'package:tronclass/data/school_config.dart';
import 'package:tronclass/data/service/login.dart';

class _ResponseAdapter implements HttpClientAdapter {
  _ResponseAdapter(this.respond);

  final ResponseBody Function(RequestOptions) respond;
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('login-diagnostics-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
    getStorage = GetStorage('login-diagnostics-test', directory.path);
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

  test(
    '401 records endpoint and category, not credentials or response text',
    () async {
      const secret = 'SENSITIVE_TEST_VALUE';
      final adapter = _ResponseAdapter(
        (_) => ResponseBody.fromString(
          '<html><div id="showErrorTip">密码错误 $secret</div>'
          '<input name="execution" value="$secret"></html>',
          401,
          headers: {
            'content-type': ['text/html; charset=utf-8'],
            'set-cookie': ['session=$secret'],
            'location': ['https://unexpected.example/$secret?ticket=$secret'],
          },
        ),
      );
      final dio = Dio(BaseOptions(validateStatus: (_) => true))
        ..httpClientAdapter = adapter;
      final existing = Interceptor();
      dio.interceptors.add(existing);
      final original = dio.interceptors.toList();
      final diagnostics = LoginDiagnostics([dio, dio]);
      diagnostics.startAttempt(1);
      final response = await dio.post<dynamic>(
        '${SchoolConfig.casBaseUrl}authserver/login',
        queryParameters: {'service': secret, 'state': secret, secret: secret},
        data: {'username': secret, 'password': secret, 'captcha': secret},
        options: Options(
          responseType: ResponseType.plain,
          headers: {'Cookie': 'session=$secret', 'Authorization': secret},
        ),
      );
      diagnostics.recordError(LogonFailedException('401 $secret'));
      await diagnostics.finish();
      await diagnostics.finish();
      expect(response.statusCode, 401);
      expect(response.data, contains(secret));
      expect(adapter.lastRequest!.data['password'], secret);
      expect(adapter.lastRequest!.headers['Cookie'], 'session=$secret');
      expect(dio.interceptors, orderedEquals(original));
      final records = LoginErrorHistory.read();
      expect(records, hasLength(1));
      expect(records.single.result, '登录失败');
      expect(records.single.report, contains('HTTP: 401'));
      expect(
        records.single.report,
        contains('POST https://ids.cqupt.edu.cn/authserver/login'),
      );
      expect(records.single.report, contains('账号或密码校验未通过'));
      expect(records.single.report, contains('参数名: service, state'));
      final persisted = jsonEncode(
        getStorage.read<dynamic>(LoginErrorHistory.storageKey),
      );
      expect(persisted, isNot(contains(secret)));
      expect(persisted, isNot(contains('unexpected.example')));
      await getStorage.save();
      await getStorage.queue.add(() async {});
      final disk = await File(
        '${directory.path}/login-diagnostics-test.gs',
      ).readAsString();
      expect(disk, isNot(contains(secret)));
      expect(
        jsonDecode(disk)[LoginErrorHistory.storageKey],
        jsonDecode(persisted),
      );
      // Stored data survives JSON serialization and can be read by a new view.
      getStorage.writeInMemory(
        LoginErrorHistory.storageKey,
        jsonDecode(persisted),
      );
      expect(LoginErrorHistory.read().single.report, records.single.report);
      dio.close();
    },
  );

  test(
    'intermediate failure stays in history after a successful retry',
    () async {
      var status = 401;
      final dio = Dio(BaseOptions(validateStatus: (_) => true))
        ..httpClientAdapter = _ResponseAdapter(
          (_) => ResponseBody.fromString('', status),
        );
      final diagnostics = LoginDiagnostics([dio]);
      diagnostics.startAttempt(1);
      await dio.get<dynamic>(SchoolConfig.portalUrl);
      diagnostics.recordError(LogonFailedException('Login failed'));
      diagnostics.startAttempt(2);
      status = 200;
      await dio.get<dynamic>(SchoolConfig.portalUrl);
      diagnostics.authenticationSucceeded();
      await diagnostics.finish();
      final record = LoginErrorHistory.read().single;
      expect(record.result, '出现错误后登录成功');
      expect(record.report, contains('第 1 轮'));
      expect(record.report, contains('第 2 轮'));
      expect(record.report, contains('HTTP: 401'));
      expect(record.report, contains('HTTP: 200'));
      dio.close();
    },
  );

  test(
    'successful login and unrelated API responses create no history',
    () async {
      final dio = Dio(BaseOptions(validateStatus: (_) => true))
        ..httpClientAdapter = _ResponseAdapter(
          (_) => ResponseBody.fromString('', 401),
        );
      final diagnostics = LoginDiagnostics([dio]);
      await dio.get<dynamic>('${SchoolConfig.lmsBaseUrl}/api/my-courses');
      diagnostics.authenticationSucceeded();
      await diagnostics.finish();
      expect(LoginErrorHistory.read(), isEmpty);
      // The observer is detached: later requests cannot enter the previous trace.
      await dio.get<dynamic>('${SchoolConfig.casBaseUrl}authserver/login');
      expect(LoginErrorHistory.read(), isEmpty);
      dio.close();
    },
  );

  test(
    'network failure metadata is safe and still propagates to the caller',
    () async {
      const secret = 'SENSITIVE_TIMEOUT';
      final dio = Dio()
        ..httpClientAdapter = _ResponseAdapter((options) {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionTimeout,
            message: secret,
          );
        });
      final diagnostics = LoginDiagnostics([dio]);
      await expectLater(
        dio.get<dynamic>(
          '${SchoolConfig.casBaseUrl}authserver/login?service=$secret',
        ),
        throwsA(isA<DioException>()),
      );
      diagnostics.recordError(StateError(secret));
      await diagnostics.finish();
      final report = LoginErrorHistory.read().single.report;
      expect(report, contains('connectionTimeout'));
      expect(report, contains('/authserver/login'));
      expect(report, isNot(contains(secret)));
      dio.close();
    },
  );

  test('history and per-login traces have bounded retention', () async {
    final dio = Dio(BaseOptions(validateStatus: (_) => true))
      ..httpClientAdapter = _ResponseAdapter(
        (_) => ResponseBody.fromString('private', 401),
      );
    for (var index = 0; index < 12; index++) {
      final diagnostics = LoginDiagnostics([dio]);
      for (var attempt = 0; attempt < 65; attempt++) {
        diagnostics.startAttempt(attempt + 1);
      }
      await dio.get<dynamic>(SchoolConfig.portalUrl);
      diagnostics.recordError(LogonFailedException('private'));
      await diagnostics.finish();
    }
    expect(LoginErrorHistory.read(), hasLength(LoginErrorHistory.limit));
    expect(LoginErrorHistory.read().first.report, contains('条事件已省略'));
    expect(LoginErrorHistory.read().first.report, isNot(contains('private')));
    await LoginErrorHistory.clear();
    expect(LoginErrorHistory.read(), isEmpty);
    dio.close();
  });

  test('a diagnostics storage error cannot fail authentication', () async {
    final workingStorage = getStorage;
    getStorage = _FailingStorage();
    try {
      final dio = Dio();
      final diagnostics = LoginDiagnostics([dio]);
      diagnostics.recordError(LogonFailedException('test failure'));
      diagnostics.authenticationSucceeded();
      await diagnostics.finish();
      expect(dio.interceptors.whereType<InterceptorsWrapper>(), isEmpty);
      expect(LoginErrorHistory.read(), isEmpty);
      dio.close();
    } finally {
      getStorage = workingStorage;
    }
  });
}

class _FailingStorage implements GetStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('storage unavailable');
}
