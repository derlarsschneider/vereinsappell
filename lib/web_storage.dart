// Nur für Web
import 'package:web/web.dart' as web;

String? getItem(String key) => web.window.localStorage.getItem(key);
void setItem(String key, String value) => web.window.localStorage.setItem(key, value);
void removeItem(String key) => web.window.localStorage.removeItem(key);
