import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart' as web;

bool webIsIos() {
  final ua = web.window.navigator.userAgent;
  return ua.contains('iPhone') || ua.contains('iPad') || ua.contains('iPod');
}

bool webIsStandalone() {
  final standaloneJs = (web.window.navigator as JSObject).getProperty('standalone'.toJS);
  if (standaloneJs.isA<JSBoolean>() && (standaloneJs as JSBoolean).toDart) return true;
  return web.window.matchMedia('(display-mode: standalone)').matches;
}
