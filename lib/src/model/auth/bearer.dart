/// Whether [token] is a personal API token created at https://lichess.org/account/oauth/token,
/// rather than one obtained by the app's own sign-in flows.
bool isPersonalToken(String token) => token.startsWith('lip_');

/// The bearer value of [token].
///
/// The official app signs its tokens with a secret, which grants them the `web:mobile` scope.
/// This build has no such secret: its tokens come from a personal API token or from the OAuth
/// login of its own client (see `AuthRepository.signIn`), with regular API scopes, and are sent
/// as is, like any other API client's.
String signBearerToken(String token) => token;
