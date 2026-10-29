import 'dart:convert';
import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:dio_redirect_interceptor/dio_redirect_interceptor.dart';
import 'package:html/parser.dart' as html;
import 'package:tronclass/data/school_config.dart';
import 'package:tronclass/data/service/tronclass.dart';

String safeUri(Uri uri) =>
    '${uri.hasAuthority ? '${uri.scheme}://${uri.authority}' : ''}${uri.path}'
    '${uri.hasQuery ? '?keys=${uri.queryParameters.keys.join(",")}' : ''}';

void describe(Response<dynamic> response) {
  final doc = html.parse(
    response.data is String ? response.data as String : '',
  );
  stdout.writeln(
    jsonEncode({
      'status': response.statusCode,
      'url': safeUri(response.realUri),
      'title': doc.querySelector('title')?.text.trim(),
      'forms': doc
          .querySelectorAll('form')
          .map((e) => e.attributes['id'])
          .toList(),
      'links': doc.querySelectorAll('a[href]').map((e) {
        final uri = response.realUri.resolve(e.attributes['href']!);
        return {'text': e.text.trim(), 'url': safeUri(uri)};
      }).toList(),
      'scripts': doc
          .querySelectorAll('script[src]')
          .map((e) => safeUri(response.realUri.resolve(e.attributes['src']!)))
          .toList(),
    }),
  );
}

Future<void> main(List<String> args) async {
  final jar = CookieJar();
  final secrets = <String>[];
  Dio client(String baseUrl) {
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 micromessenger',
        },
        followRedirects: false,
        validateStatus: (status) => status != null,
        connectTimeout: const Duration(seconds: 25),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
    dio.interceptors.addAll([
      CookieManager(jar),
      InterceptorsWrapper(
        onResponse: (response, handler) {
          final location = response.headers.value('location');
          stdout.writeln(
            '${response.requestOptions.method} '
            '${response.statusCode} ${safeUri(response.requestOptions.uri)}'
            '${location == null ? '' : ' -> ${safeUri(response.realUri.resolve(location))}'}',
          );
          if (response.statusCode == 401 && response.data is String) {
            final doc = html.parse(response.data as String);
            var tip = doc.querySelector('#showErrorTip')?.text.trim() ?? '';
            for (final secret in secrets.where((value) => value.isNotEmpty)) {
              tip = tip.replaceAll(secret, '[redacted]');
            }
            stdout.writeln('CAS rejected login: $tip');
          }
          handler.next(response);
        },
      ),
      RedirectInterceptor(() => dio),
    ]);
    return dio;
  }

  final dio = client(SchoolConfig.lmsBaseUrl);
  final casDio = client(SchoolConfig.casBaseUrl);
  var echoDisabled = false;
  try {
    if (args.contains('--login')) {
      try {
        stdin.echoMode = false;
        echoDisabled = true;
      } on StdinException {
        // Piped stdin has no terminal echo.
      }
      stdout.writeln(
        'READY: provide username and password on separate stdin lines.',
      );
      final username = stdin.readLineSync()!;
      final password = stdin.readLineSync()!;
      secrets.addAll([username, password]);
      final session = await TronClassService.login(
        casDio,
        dio,
        cookieJar: jar,
        username: username,
        password: password,
        captchaHandler: (_) async => throw StateError('CAPTCHA_REQUIRED'),
      );
      final cookies = await jar.loadForRequest(
        Uri.parse(SchoolConfig.portalUrl),
      );
      stdout.writeln(
        jsonEncode({
          'loginCompleted': session == SchoolConfig.cookieSessionMarker,
          'cookieNames': cookies.map((e) => e.name).toList(),
        }),
      );
      stdout.writeln(
        'REPEAT: logging in again using the same in-memory session.',
      );
      await TronClassService.login(
        casDio,
        dio,
        cookieJar: jar,
        username: username,
        password: password,
        captchaHandler: (_) async => throw StateError('CAPTCHA_REQUIRED'),
      );
      stdout.writeln('REPEAT_OK');
    } else {
      describe(await dio.get(SchoolConfig.portalUrl));
      describe(
        await dio.get(
          SchoolConfig.identityCasLoginUrl,
          queryParameters: {
            'service': SchoolConfig.portalUrl,
            'ui_locales': 'zh-CN',
          },
        ),
      );
    }
  } catch (error) {
    // Exceptions can include tickets, form bodies, and session tokens.
    stdout.writeln('FAILED: ${error.runtimeType}');
    if (error is DioException) {
      stdout.writeln('${error.type.name} ${safeUri(error.requestOptions.uri)}');
      if (error.response != null) describe(error.response!);
    }
    exitCode = 1;
  } finally {
    dio.close(force: true);
    casDio.close(force: true);
    await jar.deleteAll();
    if (echoDisabled) stdin.echoMode = true;
  }
}
