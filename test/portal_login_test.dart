import 'dart:io';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:dio_redirect_interceptor/dio_redirect_interceptor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tronclass/data/school_config.dart';
import 'package:tronclass/data/service/login.dart';
import 'package:tronclass/data/service/tronclass.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final ResponseBody Function(RequestOptions) respond;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

class _Portal {
  final jar = CookieJar();
  final requests = <RequestOptions>[];
  late final Dio dio = _client(SchoolConfig.lmsBaseUrl);
  late final Dio casDio = _client(SchoolConfig.casBaseUrl);
  bool authenticated = false;
  bool entryWithoutRedirect = false;
  bool stopAtBroker = false;
  bool failIdentity = false;
  int passwordPosts = 0;

  static final broker = Uri.parse(
    '${SchoolConfig.identityBaseUrl}/auth/realms/cqupt/broker/cas-client/endpoint',
  ).replace(queryParameters: {'state': 'fresh-test-state'});
  static final casLogin = Uri.parse(
    '${SchoolConfig.casBaseUrl}authserver/login',
  ).replace(queryParameters: {'service': broker.toString()});

  Dio _client(String baseUrl) {
    final client = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        followRedirects: false,
        validateStatus: (status) => status != null,
      ),
    );
    client.httpClientAdapter = _Adapter(_respond);
    client.interceptors.addAll([
      CookieManager(jar),
      RedirectInterceptor(() => client),
    ]);
    addTearDown(() => client.close(force: true));
    return client;
  }

  ResponseBody _redirect(String location) => ResponseBody.fromString(
    '',
    302,
    headers: {
      HttpHeaders.locationHeader: [location],
    },
  );

  ResponseBody _respond(RequestOptions request) {
    requests.add(request);
    final uri = request.uri;
    if (uri.host == Uri.parse(SchoolConfig.lmsBaseUrl).host) {
      if (uri.queryParameters.containsKey('ticket')) {
        authenticated = true;
        return ResponseBody.fromString(
          '',
          302,
          headers: {
            HttpHeaders.locationHeader: [SchoolConfig.portalUrl],
            HttpHeaders.setCookieHeader: [
              'session=test-session; Path=/',
              'role_token=test-role; Path=/',
            ],
          },
        );
      }
      if (authenticated || entryWithoutRedirect) {
        return ResponseBody.fromString('<html>Portal</html>', 200);
      }
      return _redirect(SchoolConfig.identityCasLoginUrl);
    }
    if (uri.toString().startsWith(SchoolConfig.identityCasLoginUrl)) {
      return failIdentity
          ? ResponseBody.fromString('Unavailable', 503)
          : _redirect(casLogin.toString());
    }
    if (uri.path == broker.path) {
      return stopAtBroker
          ? ResponseBody.fromString('Broker error', 200)
          : _redirect('${SchoolConfig.portalUrl}?ticket=test-ticket');
    }
    if (uri.path == '/authserver/checkNeedCaptcha.htl') {
      return ResponseBody.fromString('{"isNeed":false}', 200);
    }
    if (uri.path == '/authserver/login') {
      expect(uri.queryParameters['service'], broker.toString());
      if (request.method == 'POST') {
        passwordPosts++;
        return _redirect(broker.toString());
      }
      return ResponseBody.fromString('''
        <input id="pwdEncryptSalt" value="1234567890abcdef">
        <input name="execution" value="test-execution">
      ''', 200);
    }
    throw StateError('Unexpected route ${uri.path}');
  }

  Future<void> seedCookies() => jar.saveFromResponse(
    Uri.parse(SchoolConfig.portalUrl),
    [Cookie('session', 'test-session'), Cookie('role_token', 'test-role')],
  );

  Future<String> login() => TronClassService.login(
    casDio,
    dio,
    cookieJar: jar,
    username: 'test-user',
    password: 'test-password',
    captchaHandler: (_) async => throw StateError('Unexpected captcha'),
  );
}

void main() {
  test(
    'an existing portal session needs no CAS service or password POST',
    () async {
      final portal = _Portal()..authenticated = true;
      await portal.seedCookies();
      expect(await portal.login(), SchoolConfig.cookieSessionMarker);
      expect(portal.requests, hasLength(1));
      expect(portal.passwordPosts, 0);
    },
  );

  test(
    'fresh login completes CAS and a second login reuses the session',
    () async {
      final portal = _Portal();
      expect(await portal.login(), SchoolConfig.cookieSessionMarker);
      expect(portal.passwordPosts, 1);
      final requestCount = portal.requests.length;
      expect(await portal.login(), SchoolConfig.cookieSessionMarker);
      expect(portal.passwordPosts, 1);
      expect(portal.requests.length, requestCount + 1);
    },
  );

  test('portal without a session uses the CAS fallback, not OIDC', () async {
    final portal = _Portal()..entryWithoutRedirect = true;
    expect(await portal.login(), SchoolConfig.cookieSessionMarker);
    final fallback = portal.requests.firstWhere(
      (request) => request.uri.path.endsWith('/protocol/cas/login'),
    );
    expect(fallback.uri.queryParameters['service'], SchoolConfig.portalUrl);
    expect(portal.passwordPosts, 1);
    expect(
      portal.requests.any(
        (request) => request.uri.path.contains('openid-connect'),
      ),
      isFalse,
    );
  });

  test(
    'old cookies do not count as logged in when the portal redirects to CAS',
    () async {
      final portal = _Portal();
      await portal.seedCookies();
      expect(await portal.login(), SchoolConfig.cookieSessionMarker);
      expect(portal.passwordPosts, 1);
    },
  );

  test(
    'stopping at the identity broker is not a successful LMS login',
    () async {
      final portal = _Portal()..stopAtBroker = true;
      await expectLater(portal.login(), throwsA(isA<LogonFailedException>()));
      expect(portal.authenticated, isFalse);
    },
  );

  test('a portal page without session cookies cannot report success', () async {
    final portal = _Portal()
      ..entryWithoutRedirect = true
      ..failIdentity = true;
    await expectLater(portal.login(), throwsA(isA<LogonFailedException>()));
    expect(portal.passwordPosts, 0);
  });
}
