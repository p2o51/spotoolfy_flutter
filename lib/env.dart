class Env {
  static const clientId = '64103961829a42328a6634fb80574191';
  static const redirectUriDev = 'http://127.0.0.1:3000/callback';
  static const redirectUriProd = 'https://app.spotoolfy.gojyuplus.com/callback';
  static const redirectUriMobile = 'spotoolfy://callback';
  static const scopes = <String>[
    'user-read-email',
    'user-read-private',
    'playlist-read-private',
    'user-library-read',
    'user-library-modify',
    'user-read-currently-playing',
    'user-read-playback-state',
    'user-modify-playback-state',
    'user-read-recently-played',
    'app-remote-control',
    'streaming',
  ];
}
