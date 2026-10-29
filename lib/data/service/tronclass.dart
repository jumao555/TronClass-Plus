import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:tronclass/data/model/tron_class/rollcalls_response/rollcalls_response.dart';
import 'package:tronclass/data/school_config.dart';
import 'package:tronclass/data/service/login.dart';

class TronClassService {
  static Future<String> getLoginCode(
    Dio dio,
    String username,
    String password,
    CaptchaHandler captchaHandler,
  ) async {
    _ensureLoginConfig();
    final url = SchoolConfig.identityAuthorizeUrl;
    final params = {
      "scope": "openid",
      "response_type": "code",
      "redirect_uri": SchoolConfig.redirectUri,
      "client_id": SchoolConfig.clientId,
      "autologin": "true",
    };
    final resp = await dio.get(url, queryParameters: params);
    final redirectUrl = resp.requestOptions.uri;
    final redirectUrlString = redirectUrl.toString();

    Uri callbackUrl;
    if (redirectUrlString.contains(SchoolConfig.redirectUri)) {
      callbackUrl = redirectUrl;
    } else {
      final serviceUrl = redirectUrl.queryParameters['service'];
      if (serviceUrl == null) {
        throw Exception(
          "ChangKeService.getLoginServiceUrl: 'service' param is null!",
        );
      }

      final resp1 = await LoginService.loginCas(
        casDio: dio,
        username: username,
        password: password,
        service: serviceUrl,
        serviceHomeUrl: SchoolConfig.portalUrl,
        successVerify: (resp) async {
          final uri = resp.requestOptions.uri;
          final code = _readCallbackParam(uri, 'code');
          final ok = code != null;
          return ok;
        },
        captchaHandler: captchaHandler,
      );
      callbackUrl = resp1.requestOptions.uri;
    }

    final code = _readCallbackParam(callbackUrl, "code");
    if (code == null) {
      throw Exception("ChangKeService.getLoginCode: 'code' is null!");
    }
    return code;
  }

  static String? _readCallbackParam(Uri uri, String key) {
    final queryValue = uri.queryParameters[key];
    if (queryValue != null) return queryValue;

    final fragment = uri.fragment;
    if (fragment.isEmpty) return null;
    final fragmentUri = Uri.parse('?$fragment');
    return fragmentUri.queryParameters[key];
  }

  static Future<String> getAccessToken(Dio dio, {required String code}) async {
    _ensureLoginConfig();
    final url = SchoolConfig.identityTokenUrl;
    final params = {
      "client_id": SchoolConfig.clientId,
      "redirect_uri": SchoolConfig.redirectUri,
      "code": code,
      "grant_type": "authorization_code",
      "scope": "openid",
    };
    final resp = await dio.post(
      url,
      data: params,
      options: Options(contentType: "application/x-www-form-urlencoded"),
    );
    final accessToken = resp.data['access_token'];
    if (accessToken == null) {
      throw Exception("ChangKeService.getAccessToken: 'access_token' is null!");
    }
    return accessToken;
  }

  static Future<String> loginDesktopEndpoint(
    Dio dio, {
    required String accessToken,
  }) async {
    _ensureLoginConfig();
    final url = "${SchoolConfig.lmsBaseUrl}/api/login?login=access_token";
    final data = {"access_token": accessToken, "org_id": SchoolConfig.orgId};
    final resp = await dio.post(url, data: data);
    final sessionId = resp.headers.value('x-session-id');
    if (sessionId == null) {
      throw Exception(
        "ChangKeService.loginDesktopEndpoint: 'sessionId' is null!",
      );
    }
    return sessionId;
  }

  static void _ensureLoginConfig() {
    if (SchoolConfig.hasLoginConfig) return;
    throw UnsupportedError(
      'CQUPT login config is incomplete. Fill identityAuthorizeUrl, '
      'identityTokenUrl, redirectUri, clientId, and orgId in '
      'lib/data/school_config.dart.',
    );
  }

  static Future<String> login(
    Dio casDio,
    Dio dio, {
    required CookieJar cookieJar,
    required String username,
    required String password,
    required CaptchaHandler captchaHandler,
  }) async {
    if (SchoolConfig.useCookieLogin) {
      return loginWithPortalCookies(
        casDio,
        dio,
        cookieJar: cookieJar,
        username: username,
        password: password,
        captchaHandler: captchaHandler,
      );
    }

    final code = await getLoginCode(casDio, username, password, captchaHandler);
    final token = await getAccessToken(dio, code: code);
    final sessionId = await loginDesktopEndpoint(dio, accessToken: token);
    return sessionId;
  }

  static Future<String> loginWithPortalCookies(
    Dio casDio,
    Dio dio, {
    required CookieJar cookieJar,
    required String username,
    required String password,
    required CaptchaHandler captchaHandler,
  }) async {
    final entryResp = await dio.get(
      SchoolConfig.portalUrl,
      options: Options(responseType: ResponseType.plain),
    );
    // A persisted session or CAS SSO can return straight to the portal.
    if (await _hasPortalSession(entryResp, cookieJar)) {
      return SchoolConfig.cookieSessionMarker;
    }

    var serviceUrl = _readServiceFromResponse(entryResp);
    if (serviceUrl == null || serviceUrl.isEmpty) {
      final authorizeResp = await dio.get(
        SchoolConfig.identityCasLoginUrl,
        queryParameters: {
          "service": SchoolConfig.portalUrl,
          "ui_locales": "zh-CN",
        },
        options: Options(responseType: ResponseType.plain),
      );
      if (await _hasPortalSession(authorizeResp, cookieJar)) {
        return SchoolConfig.cookieSessionMarker;
      }
      serviceUrl = _readServiceFromResponse(authorizeResp);
    }

    if (serviceUrl == null || serviceUrl.isEmpty) {
      throw LogonFailedException('未能进入学校统一认证页面，请稍后重试；若持续失败，请先确认学校网页端能否正常登录。');
    }

    await LoginService.loginCas(
      casDio: casDio,
      username: username,
      password: password,
      service: serviceUrl,
      serviceHomeUrl: SchoolConfig.portalUrl,
      successVerify: (resp) async {
        return _hasPortalSession(resp, cookieJar);
      },
      captchaHandler: captchaHandler,
    );

    final verifyResp = await dio.get(
      SchoolConfig.portalUrl,
      options: Options(responseType: ResponseType.plain),
    );
    if (!await _hasPortalSession(verifyResp, cookieJar)) {
      throw LogonFailedException('学校认证已完成，但畅课登录会话未建立，请重新登录。');
    }

    return SchoolConfig.cookieSessionMarker;
  }

  static String? _readServiceFromResponse(Response<dynamic> response) {
    final uris = <Uri>[
      response.requestOptions.uri,
      response.realUri,
      ...response.redirects.map(
        (redirect) => response.requestOptions.uri.resolveUri(redirect.location),
      ),
    ];

    final location = response.headers.value('location');
    if (location != null && location.isNotEmpty) {
      uris.add(response.requestOptions.uri.resolve(location));
    }

    for (final uri in uris.reversed) {
      final service = _readServiceFromUri(uri);
      if (service != null && service.isNotEmpty) return service;
    }

    return null;
  }

  static String? _readServiceFromUri(Uri uri) {
    final cas = Uri.parse(SchoolConfig.casBaseUrl);
    if (!uri.hasAuthority ||
        uri.origin != cas.origin ||
        uri.path != '/authserver/login') {
      return null;
    }
    final service = Uri.tryParse(uri.queryParameters['service'] ?? '');
    final identity = Uri.parse(SchoolConfig.identityBaseUrl);
    if (service == null ||
        !service.hasAuthority ||
        service.origin != identity.origin ||
        service.path != '/auth/realms/cqupt/broker/cas-client/endpoint') {
      return null;
    }
    return service.toString();
  }

  static Future<bool> _hasPortalSession(
    Response<dynamic> response,
    CookieJar cookieJar,
  ) async {
    final portal = Uri.parse(SchoolConfig.portalUrl);
    final uri = response.realUri;
    if (response.statusCode != 200 ||
        !uri.hasAuthority ||
        uri.origin != portal.origin ||
        uri.path != portal.path) {
      return false;
    }
    final cookies = await cookieJar.loadForRequest(portal);
    return ['session', 'role_token'].every(
      (name) => cookies.any(
        (cookie) => cookie.name == name && cookie.value.isNotEmpty,
      ),
    );
  }

  static Future<Response<dynamic>> signQr(
    Dio dio, {
    required String rollcallId,
    required String data,
    required String deviceId,
  }) async {
    final url =
        "${SchoolConfig.lmsBaseUrl}/api/rollcall/${rollcallId}/answer_qr_rollcall";
    final body = {"data": data, "deviceId": deviceId};
    final resp = await dio.put<dynamic>(
      url,
      data: body,
      options: Options(responseType: ResponseType.plain),
    );
    return resp;
  }

  static Future<Response<Map<String, dynamic>>> signNumber(
    Dio dio, {
    required String rollcallId,
    required String numberCode,
    required String deviceId,
  }) async {
    final url =
        "${SchoolConfig.lmsBaseUrl}/api/rollcall/${rollcallId}/answer_number_rollcall";
    final body = {"numberCode": numberCode, "deviceId": deviceId};
    final resp = await dio.put<Map<String, dynamic>>(
      url,
      data: body,
      options: Options(responseType: ResponseType.json),
    );
    return resp;
  }

  static Future<RollcallsResponse> getRollcalls(Dio dio) async {
    final url =
        "${SchoolConfig.lmsBaseUrl}/api/radar/rollcalls?api_version=1.1.0";
    final resp = await dio.get(
      url,
      options: Options(responseType: ResponseType.json),
    );
    return RollcallsResponse.fromJson(resp.data);
  }

  static Future<Response<Map<String, dynamic>>> signRadar(
    Dio dio, {
    required String rollcallId,
    required String deviceId,
    required double latitude,
    required double longitude,
    required double accuracy,
    // You can use the default values
    double altitude = 0,
    // You can use the default values
    double? altitudeAccuracy,
    // You can use the default values
    double? speed,
    // You can use the default values
    String? heading,
  }) async {
    final url =
        "${SchoolConfig.lmsBaseUrl}/api/rollcall/${rollcallId}/answer?api_version=1.1.2";
    final body = {
      "deviceId": deviceId,
      "latitude": latitude,
      "longitude": longitude,
      "speed": speed,
      "accuracy": accuracy,
      "altitude": altitude,
      "altitudeAccuracy": altitudeAccuracy,
      "heading": heading,
    };
    final resp = await dio.put<Map<String, dynamic>>(
      url,
      data: body,
      options: Options(responseType: ResponseType.json),
    );
    return resp;
  }
}
