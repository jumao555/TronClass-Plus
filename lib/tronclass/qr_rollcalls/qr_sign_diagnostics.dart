import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:tronclass/data/school_config.dart';

import '../common.dart';

class QrSignDiagnostics {
  QrSignDiagnostics._({
    required this.successful,
    required this.message,
    required this.report,
  });

  final bool successful;
  final String message;
  final String report;

  static const _loginMessages = {
    'Login failed',
    'login_failed',
    'login_required',
    'not_logged_in',
    'unauthorized',
    'session_expired',
  };

  factory QrSignDiagnostics.fromResponse(Response<dynamic> response) {
    dynamic body = response.data;
    var shape = body == null ? 'empty' : 'other';
    if (body is String) {
      final text = body.trim();
      shape = text.isEmpty
          ? 'empty'
          : text.startsWith('<')
          ? 'html'
          : 'text';
      if (text.isNotEmpty && shape != 'html') {
        try {
          body = jsonDecode(text);
          shape = 'json_other';
        } on FormatException {
          // Only the response shape is retained, never the raw body.
        }
      }
    }

    final data = body is Map ? body : null;
    if (data != null) shape = 'json_object';
    final rawMessage = data?['message'];
    final knownMessage =
        rawMessage is String &&
            (messageMap.containsKey(rawMessage) ||
                _loginMessages.contains(rawMessage))
        ? rawMessage
        : null;
    final successful =
        response.statusCode == 200 && data?['status'] == 'on_call';
    final loginRequired =
        response.statusCode == 401 ||
        _isLoginUri(response.realUri) ||
        _loginMessages.contains(knownMessage);

    final String message;
    if (successful) {
      message = getMappingMessage('success');
    } else if (loginRequired) {
      message = '登录已失效，请重新登录后再扫码';
    } else if (knownMessage != null) {
      message = getMappingMessage(knownMessage);
    } else if (response.statusCode == 403) {
      message = '服务器拒绝了请求，请查看错误详情';
    } else if (shape != 'json_object') {
      message = '服务器返回格式异常，请查看错误详情';
    } else {
      message = '签到未成功，请查看错误详情';
    }

    return QrSignDiagnostics._(
      successful: successful,
      message: message,
      report: _report(
        response: response,
        result: message,
        shape: shape,
        serverMessage:
            knownMessage ??
            (rawMessage == null ? 'none' : 'unrecognized (redacted)'),
      ),
    );
  }

  factory QrSignDiagnostics.fromError(Object error) {
    final dioError = error is DioException ? error : null;
    final timeout =
        error is TimeoutException ||
        (dioError != null &&
            {
              DioExceptionType.connectionTimeout,
              DioExceptionType.sendTimeout,
              DioExceptionType.receiveTimeout,
            }.contains(dioError.type));
    final message = timeout
        ? '网络连接超时，请检查网络'
        : dioError?.type == DioExceptionType.connectionError
        ? '网络连接失败，请检查网络'
        : dioError?.type == DioExceptionType.badCertificate
        ? '服务器证书校验失败'
        : '签到请求异常，请查看错误详情';
    return QrSignDiagnostics._(
      successful: false,
      message: message,
      report: _report(
        response: dioError?.response,
        result: message,
        errorType: dioError == null
            ? error.runtimeType.toString()
            : '${dioError.type.name} / ${dioError.error.runtimeType}',
      ),
    );
  }

  static bool _isLoginUri(Uri uri) {
    return uri.host == Uri.parse(SchoolConfig.casBaseUrl).host ||
        uri.host == Uri.parse(SchoolConfig.identityBaseUrl).host;
  }

  static String _safeResponseUrl(Uri uri) {
    final allowedHosts = {
      Uri.parse(SchoolConfig.lmsBaseUrl).host,
      Uri.parse(SchoolConfig.casBaseUrl).host,
      Uri.parse(SchoolConfig.identityBaseUrl).host,
    };
    if (!allowedHosts.contains(uri.host)) return 'unexpected URL (redacted)';
    final path = uri.path.replaceFirst(
      RegExp(r'^/api/rollcall/[^/]+/answer_qr_rollcall$'),
      '/api/rollcall/:id/answer_qr_rollcall',
    );
    const allowedPaths = {
      '/api/rollcall/:id/answer_qr_rollcall',
      '/authserver/login',
      '/authserver/reAuthCheck/reAuthLoginView.do',
      '/auth/realms/cqupt/protocol/cas/login',
      '/auth/realms/cqupt/broker/cas-client/endpoint',
      '/user/index',
    };
    return '${uri.scheme}://${uri.host}'
        '${allowedPaths.contains(path) ? path : '/[redacted]'}';
  }

  static String _report({
    required String result,
    Response<dynamic>? response,
    String? shape,
    String? serverMessage,
    String? errorType,
  }) {
    final contentType = response?.headers
        .value(Headers.contentTypeHeader)
        ?.split(';')
        .first
        .trim()
        .toLowerCase();
    const allowedTypes = {
      'application/json',
      'text/json',
      'text/html',
      'text/plain',
      'application/octet-stream',
    };
    return [
      'TronClass Plus QR diagnostics v1',
      '时间: ${DateTime.now().toLocal().toIso8601String()}',
      '结果: $result',
      '请求: PUT ${SchoolConfig.lmsBaseUrl}/api/rollcall/:id/answer_qr_rollcall',
      'HTTP: ${response?.statusCode ?? 'unavailable'}',
      if (response != null) '最终地址: ${_safeResponseUrl(response.realUri)}',
      'Content-Type: ${allowedTypes.contains(contentType) ? contentType : 'other / unavailable'}',
      if (shape != null) '返回类型: $shape',
      if (serverMessage != null) '服务端消息: $serverMessage',
      if (errorType != null) '异常类型: $errorType',
    ].join('\n');
  }
}
