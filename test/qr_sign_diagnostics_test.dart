import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio_redirect_interceptor/dio_redirect_interceptor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tronclass/data/school_config.dart';
import 'package:tronclass/data/service/tronclass.dart';
import 'package:tronclass/tronclass/qr_rollcalls/qr_sign_diagnostics.dart';

class _LoginRedirectAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    if (options.uri.path == '/authserver/login') {
      return ResponseBody.fromString('<html>Login required</html>', 200,
          headers: {Headers.contentTypeHeader: ['text/html']});
    }
    return ResponseBody.fromString('', 302, headers: {
      'location': ['${SchoolConfig.casBaseUrl}authserver/login'],
    });
  }

  @override
  void close({bool force = false}) {}
}

Response<dynamic> response(
  dynamic body, {
  int status = 400,
  String? url,
  String contentType = 'application/json',
}) => Response<dynamic>(
  requestOptions: RequestOptions(
    path:
        url ??
        '${SchoolConfig.lmsBaseUrl}/api/rollcall/private-id/answer_qr_rollcall',
    method: 'PUT',
    headers: {'Cookie': 'session=private-cookie'},
    data: {'data': 'private-qr-content', 'password': 'private-password'},
  ),
  statusCode: status,
  data: body,
  headers: Headers.fromMap({
    Headers.contentTypeHeader: [contentType],
    'set-cookie': ['session=private-cookie'],
  }),
);

void main() {
  test('the actual QR service can return an HTML redirect without a Map cast', () async {
    final dio = Dio(BaseOptions(
      followRedirects: false,
      validateStatus: (status) => status != null,
    ))..httpClientAdapter = _LoginRedirectAdapter();
    dio.interceptors.add(RedirectInterceptor(() => dio));
    addTearDown(() => dio.close(force: true));
    final result = QrSignDiagnostics.fromResponse(await TronClassService.signQr(
      dio, rollcallId: 'fake-rollcall', data: 'fake-qr', deviceId: 'fake-device',
    ));
    expect(result.successful, isFalse);
    expect(result.message, contains('登录已失效'));
    expect(result.report, contains('返回类型: html'));
  });
  test('a successful response must still contain on_call and HTTP 200', () {
    expect(
      QrSignDiagnostics.fromResponse(
        response('{"status":"on_call"}', status: 200),
      ).successful,
      isTrue,
    );
    expect(
      QrSignDiagnostics.fromResponse(
        response('{"status":"on_call"}', status: 400),
      ).successful,
      isFalse,
    );
    expect(
      QrSignDiagnostics.fromResponse(
        response('{"status":"absent"}', status: 200),
      ).successful,
      isFalse,
    );
  });

  test('a closed rollcall keeps its existing user-facing message', () {
    final report = QrSignDiagnostics.fromResponse(
      response('{"message":"rollcall_closed"}'),
    );
    expect(report.message, '二维码签到已结束');
    expect(report.report, contains('HTTP: 400'));
    expect(report.report, contains('服务端消息: rollcall_closed'));
  });

  test('HTML after a redirect to CAS is reported as an expired login', () {
    final report = QrSignDiagnostics.fromResponse(
      response(
        '<html>private-cookie</html>',
        status: 200,
        url:
            '${SchoolConfig.casBaseUrl}authserver/login?service=private-ticket',
        contentType: 'text/html',
      ),
    );
    expect(report.successful, isFalse);
    expect(report.message, contains('重新登录'));
    expect(report.report, contains('返回类型: html'));
    expect(report.report, isNot(contains('private-ticket')));
    expect(report.report, isNot(contains('private-cookie')));
  });

  test('HTTP 401 and HTTP 403 have different explanations', () {
    expect(
      QrSignDiagnostics.fromResponse(response('{}', status: 401)).message,
      contains('登录已失效'),
    );
    expect(
      QrSignDiagnostics.fromResponse(response('{}', status: 403)).message,
      contains('拒绝'),
    );
  });

  test('valid JSON is understood even with an incorrect content type', () {
    expect(
      QrSignDiagnostics.fromResponse(
        response('{"message":"QR_code_expired"}', contentType: 'text/plain'),
      ).message,
      '签到二维码已过期',
    );
  });

  test('malformed text never throws a String-to-Map cast error', () {
    final report = QrSignDiagnostics.fromResponse(response('invalid {json'));
    expect(report.successful, isFalse);
    expect(report.message, contains('返回格式异常'));
  });

  test(
    'diagnostics never include form values, cookies, query values or unknown messages',
    () {
      final report = QrSignDiagnostics.fromResponse(
        response(
          {
            'message': 'private-server-message',
            'session': 'private-cookie',
            'debug': 'private-password private-qr-content',
          },
          url:
              '${SchoolConfig.lmsBaseUrl}/api/rollcall/private-id/answer_qr_rollcall'
              '?ticket=private-ticket',
        ),
      ).report;
      for (final secret in [
        'private-id',
        'private-server-message',
        'private-cookie',
        'private-password',
        'private-qr-content',
        'private-ticket',
      ]) {
        expect(report, isNot(contains(secret)));
      }
      expect(report, contains('/api/rollcall/:id/answer_qr_rollcall'));
      expect(report, contains('unrecognized (redacted)'));
    },
  );

  test('unexpected response hosts and paths are hidden', () {
    expect(
      QrSignDiagnostics.fromResponse(
        response(
          '',
          url: 'https://private-host.example/private-path?token=private-token',
        ),
      ).report,
      isNot(contains('private-')),
    );
    expect(
      QrSignDiagnostics.fromResponse(
        response(
          '',
          url: '${SchoolConfig.lmsBaseUrl}/private-path?token=private-token',
        ),
      ).report,
      isNot(contains('private-')),
    );
  });

  test(
    'network errors and timeouts can be shared without exception messages',
    () {
      final timeout = QrSignDiagnostics.fromError(
        TimeoutException('private-token'),
      );
      expect(timeout.message, contains('超时'));
      expect(timeout.report, isNot(contains('private-token')));
      final network = QrSignDiagnostics.fromError(
        DioException(
          requestOptions: RequestOptions(path: '/?password=private-password'),
          type: DioExceptionType.connectionError,
          message: 'private-password',
        ),
      );
      expect(network.message, contains('网络连接失败'));
      expect(network.report, isNot(contains('private-password')));
    },
  );
}
