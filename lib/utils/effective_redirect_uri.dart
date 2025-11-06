import 'effective_redirect_uri_stub.dart'
    if (dart.library.html) 'effective_redirect_uri_web.dart';

String effectiveRedirectUri() => effectiveRedirectUriImpl();
