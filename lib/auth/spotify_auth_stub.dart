class SpotifyAuthWeb {
  Future<void> startLogin() async {
    throw UnsupportedError('SpotifyAuthWeb is only available on Flutter Web.');
  }

  Future<bool> handleRedirect() async => false;

  Future<String?> getValidAccessToken() async => null;

  void logout() {}
}
