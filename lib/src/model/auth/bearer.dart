import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:lichess_mobile/src/constants.dart';

final hmacSha1 = Hmac(sha1, utf8.encode(kLichessWSSecret));

/// Whether [token] is a personal API token created at https://lichess.org/account/oauth/token,
/// rather than one obtained by the app's own sign-in flows.
bool isPersonalToken(String token) => token.startsWith('lip_');

/// Sign a bearer token with the lichess secret.
///
/// Personal API tokens are sent as is, like any other API client would, since builds without the
/// production secret cannot produce a signature the server accepts.
String signBearerToken(String token) {
  if (isPersonalToken(token)) return token;
  final digest = hmacSha1.convert(utf8.encode(token));
  return '$token:$digest';
}
