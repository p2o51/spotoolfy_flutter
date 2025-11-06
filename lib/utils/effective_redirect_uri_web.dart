// ignore_for_file: deprecated_member_use

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import '../env.dart';

String effectiveRedirectUriImpl() {
  final host = html.window.location.host.toLowerCase();

  if (host.startsWith('127.0.0.1') || host.startsWith('localhost')) {
    final template = Uri.parse(Env.redirectUriDev);
    final portStr = html.window.location.port;
    final port = int.tryParse(portStr);

    if (port != null && port > 0) {
      return template.replace(port: port).toString();
    }
    return Env.redirectUriDev;
  }

  return Env.redirectUriProd;
}
