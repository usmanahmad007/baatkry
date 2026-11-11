// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

bool isBrowserOnline() {
  try {
    return html.window.navigator.onLine ?? true;
  } catch (_) {
    return true;
  }
}
