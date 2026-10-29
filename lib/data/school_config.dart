class SchoolConfig {
  static const schoolName = '重庆邮电大学';

  // Values confirmed from the provided browser console screenshots.
  static const casBaseUrl = 'https://ids.cqupt.edu.cn/';
  static const identityBaseUrl = 'http://identity.tc.cqupt.edu.cn';
  static const lmsBaseUrl = 'http://lms.tc.cqupt.edu.cn';
  static const centerBaseUrl = 'http://center.tc.cqupt.edu.cn';
  static const portalUrl = '$lmsBaseUrl/user/index';
  static const useCookieLogin = true;
  static const cookieSessionMarker = 'cookie-session';

  // Confirmed from the LMS portal's HTTP redirect.
  static const identityCasLoginUrl =
      '$identityBaseUrl/auth/realms/cqupt/protocol/cas/login';

  static const casCookieUrls = [
    'https://ids.cqupt.edu.cn',
    'https://ids.cqupt.edu.cn/authserver',
  ];

  // Inferred from the Keycloak broker callback:
  // /auth/realms/cqupt/broker/cas-client/endpoint?...state=...tronclass
  static const identityAuthorizeUrl =
      '$identityBaseUrl/auth/realms/cqupt/protocol/openid-connect/auth';
  static const identityTokenUrl =
      '$identityBaseUrl/auth/realms/cqupt/protocol/openid-connect/token';
  static const clientId = 'tronclass';

  // This is the most likely redirect URI for the web portal. If login fails
  // with redirect_uri/client errors, copy the exact redirect_uri from the
  // Network request to identityAuthorizeUrl and replace this value.
  static const redirectUri = '$lmsBaseUrl/user/index';

  // Confirmed from role_token payload: {"org_id":1,...}
  static const int? orgId = 1;

  static bool get hasLoginConfig =>
      identityAuthorizeUrl.isNotEmpty &&
      identityTokenUrl.isNotEmpty &&
      redirectUri.isNotEmpty &&
      clientId.isNotEmpty &&
      orgId != null;
}
