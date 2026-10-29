import 'package:flutter/foundation.dart';

/// The QR code of the TV is read by the application on Android and iPhone
/// only (camera); elsewhere the code is typed.
bool get canScanTvQr=>!kIsWeb&&(defaultTargetPlatform==TargetPlatform.android||defaultTargetPlatform==TargetPlatform.iOS);

/// Code read from the QR code of the TV: the `code` parameter of its link
/// (…/tv/approve?code=ABC123), or the text itself; null when it is not a
/// pairing code.
String? tvCodeFrom(String raw){
  final t=raw.trim();
  final uri=Uri.tryParse(t);
  final c=(uri!=null&&uri.queryParameters.containsKey('code'))?uri.queryParameters['code']!:t;
  final up=c.trim().toUpperCase();
  return RegExp(r'^[A-Z0-9]{4,12}$').hasMatch(up)?up:null;
}
