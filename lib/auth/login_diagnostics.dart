import 'dart:async';

import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html;
import 'package:tronclass/data/get_storage.dart';
import 'package:tronclass/data/school_config.dart';
import 'package:tronclass/data/service/login.dart';

class LoginErrorRecord {
  const LoginErrorRecord({
    required this.time,
    required this.result,
    required this.report,
  });

  final DateTime time;
  final String result;
  final String report;

  Map<String, String> toJson() => {
    'time': time.toIso8601String(),
    'result': result,
    'report': report,
  };

  static LoginErrorRecord? fromJson(dynamic value) {
    if (value is! Map) return null;
    final time = value['time'];
    final result = value['result'];
    final report = value['report'];
    if (time is! String || result is! String || report is! String) return null;
    final parsedTime = DateTime.tryParse(time);
    if (parsedTime == null || result.length > 80 || report.length > 40000) {
      return null;
    }
    return LoginErrorRecord(time: parsedTime, result: result, report: report);
  }
}

class LoginErrorHistory {
  static const storageKey = 'login_error_history_v1';
  static const limit = 10;

  static List<LoginErrorRecord> read() {
    try {
      final raw = getStorage.read<dynamic>(storageKey);
      if (raw is! List) return [];
      return raw
          .map(LoginErrorRecord.fromJson)
          .whereType<LoginErrorRecord>()
          .take(limit)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> add(LoginErrorRecord record) async {
    final records = [record, ...read()].take(limit);
    await getStorage.write(
      storageKey,
      records.map((entry) => entry.toJson()).toList(),
    );
  }

  static Future<void> clear() => getStorage.remove(storageKey);
}

/// Observes only login endpoints, retaining allowlisted metadata, never bodies.
class LoginDiagnostics {
  LoginDiagnostics(List<Dio> clients) {
    for (final client in clients.toSet()) {
      final observer = InterceptorsWrapper(
        onResponse: (response, handler) {
          _observe(() => _recordResponse(response));
          handler.next(response);
        },
        onError: (error, handler) {
          _observe(() {
            if (!_isLoginUri(error.requestOptions.uri)) return;
            if (error.response != null) _recordResponse(error.response!);
            _hasFailure = true;
            _append(
              '请求: ${_safeUri(error.requestOptions.uri)}\n'
              '网络异常: ${error.type.name}',
            );
          });
          handler.next(error);
        },
      );
      // Observe each redirect response before the existing redirect handler.
      client.interceptors.insert(0, observer);
      _observers[client] = observer;
    }
  }

  final _time = DateTime.now();
  final _clock = Stopwatch()..start();
  final _events = <String>[];
  final _observers = <Dio, Interceptor>{};
  var _hasFailure = false;
  var _authenticated = false;
  var _finished = false;
  var _omitted = 0;
  var _result = '登录未完成';

  static final _hosts = {
    Uri.parse(SchoolConfig.casBaseUrl).host,
    Uri.parse(SchoolConfig.identityBaseUrl).host,
    Uri.parse(SchoolConfig.lmsBaseUrl).host,
  };
  static const _paths = {
    '/user/index',
    '/authserver/login',
    '/authserver/checkNeedCaptcha.htl',
    '/authserver/getCaptcha.htl',
    '/authserver/reAuthCheck/reAuthLoginView.do',
    '/authserver/dynamicCode/getDynamicCodeByReauth.do',
    '/authserver/reAuthCheck/reAuthSubmit.do',
    '/auth/realms/cqupt/protocol/cas/login',
    '/auth/realms/cqupt/broker/cas-client/login',
    '/auth/realms/cqupt/broker/cas-client/endpoint',
    '/auth/realms/cqupt/protocol/openid-connect/auth',
    '/auth/realms/cqupt/protocol/openid-connect/token',
    '/api/login',
  };

  static bool _isLoginUri(Uri uri) =>
      _hosts.contains(uri.host) && _paths.contains(uri.path);

  static String _safeUri(Uri uri) {
    if (!_hosts.contains(uri.host) || !{'http', 'https'}.contains(uri.scheme)) {
      return '[地址已隐藏]';
    }
    const queryKeys = {
      'service',
      'state',
      'ticket',
      'code',
      'execution',
      'client_id',
      'redirect_uri',
      'ui_locales',
      'response_type',
      'login',
    };
    final keys = uri.queryParameters.keys.where(queryKeys.contains).toList()
      ..sort();
    return '${uri.scheme}://${uri.host}'
        '${_paths.contains(uri.path) ? uri.path : '/[路径已隐藏]'}'
        '${keys.isEmpty ? '' : ' [参数名: ${keys.join(', ')}]'}';
  }

  void _observe(void Function() action) {
    if (_finished) return;
    try {
      action();
    } catch (_) {
      // Diagnostics must never change the outcome of an authentication request.
    }
  }

  void _append(String event) {
    if (_events.length == 60) {
      _events.removeAt(0);
      _omitted++;
    }
    _events.add('[+${_clock.elapsedMilliseconds}ms] $event');
  }

  void startAttempt(int number) => _append('第 $number 轮登录尝试');

  void recordError(Object error) {
    _hasFailure = true;
    _result = _authenticated ? '登录后处理失败' : '登录失败';
    final label = switch (error) {
      DioException e => '网络异常 / ${e.type.name}',
      LogonFailedException _ => '学校认证或登录会话校验失败',
      RequireLoginVerificationCodeException _ => '需要二次验证',
      TimeoutException _ => '超时',
      FormatException _ => '返回数据解析失败',
      _ => '其他异常（详情已隐藏）',
    };
    _append('本轮结果: $label');
  }

  void authenticationSucceeded() {
    _authenticated = true;
    _result = _hasFailure ? '出现错误后登录成功' : '登录成功';
    _append('认证结果: 成功');
  }

  void cancelled() {
    _result = '登录已取消';
    _append('认证结果: 已取消或离开登录页');
  }

  void _recordResponse(Response<dynamic> response) {
    if (!_isLoginUri(response.requestOptions.uri)) return;
    if ((response.statusCode ?? 0) >= 400) _hasFailure = true;
    final method = response.requestOptions.method;
    final safeMethod = {'GET', 'POST', 'PUT'}.contains(method)
        ? method
        : 'OTHER';
    final type = response.headers
        .value(Headers.contentTypeHeader)
        ?.split(';')
        .first
        .trim()
        .toLowerCase();
    const types = {
      'text/html',
      'text/plain',
      'application/json',
      'image/jpeg',
      'image/png',
    };
    final body = response.data;
    final shape = body == null
        ? 'empty'
        : body is Map
        ? 'json_object'
        : body is String
        ? (body.trimLeft().startsWith('<') ? 'html' : 'text')
        : 'other';
    final details = <String>[
      '$safeMethod ${_safeUri(response.requestOptions.uri)}',
      'HTTP: ${response.statusCode ?? 'unavailable'}',
      'Content-Type: ${types.contains(type) ? type : 'other / unavailable'}',
      '返回类型: $shape',
    ];
    final location = response.headers.value('location');
    if (location != null) {
      details.add(
        '跳转: ${_safeUri(response.requestOptions.uri.resolve(location))}',
      );
    }
    if (response.realUri != response.requestOptions.uri) {
      details.add('最终地址: ${_safeUri(response.realUri)}');
    }
    if (shape == 'html' && body is String && body.length <= 256000) {
      final tip = html.parse(body).querySelector('#showErrorTip')?.text ?? '';
      // Classify known hints instead of retaining text that may contain an ID.
      final category = tip.contains('密码错误') || tip.contains('密码有误')
          ? '账号或密码校验未通过'
          : tip.contains('验证码')
          ? '验证码相关错误'
          : tip.contains('锁定') || tip.contains('频繁')
          ? '账号锁定或操作频繁'
          : tip.trim().isEmpty
          ? '未找到 #showErrorTip 提示'
          : '存在其他提示（原文已隐藏）';
      details.add('学校页面提示: $category');
    }
    _append(details.join('\n'));
  }

  Future<void> finish() async {
    if (_finished) return;
    _finished = true;
    _clock.stop();
    for (final entry in _observers.entries) {
      entry.key.interceptors.remove(entry.value);
    }
    _observers.clear();
    if (!_hasFailure) return;
    final record = LoginErrorRecord(
      time: _time,
      result: _result,
      report: [
        'TronClass Plus login diagnostics v1',
        '时间: ${_time.toLocal().toIso8601String()}',
        '结果: $_result',
        '耗时: ${_clock.elapsedMilliseconds}ms',
        if (_omitted > 0) '较早的 $_omitted 条事件已省略',
        ..._events,
      ].join('\n'),
    );
    try {
      await LoginErrorHistory.add(record);
    } catch (_) {
      // A storage failure must not turn a successful login into a failure.
    }
  }
}
