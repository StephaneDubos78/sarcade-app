import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

bool isUrgentPriority(String priority)=>priority=='urgent'||priority=='immediate';

/// Browser notifications (installed PWA on ChromeOS and Windows, any
/// browser): shown when the operator allowed them; urgent ones stay until
/// dismissed.
///
/// Browsers ignore a permission request that does not follow a click
/// (recette of lot 2, 25 October 2026): the request is made from the
/// « Activer les notifications » banner, and the permission is read again
/// for every message, so a change in the site settings applies at once.
class NotificationService {
  String get _permission{try{return web.Notification.permission;}catch(_){return 'unsupported';}}

  /// The operator has not answered yet: show the banner.
  bool get needsUserAction=>_permission=='default';

  Future<void> initialize() async {}

  /// From a click on the banner.
  Future<bool> requestFromUser() async {
    try{
      final answer=await web.Notification.requestPermission().toDart;
      return answer.toDart=='granted';
    }catch(e){
      debugPrint('SARCADE notifications unavailable: $e');
      return false;
    }
  }

  Future<void> message({required String title,required String body,required String priority}) async {
    if(_permission!='granted'){debugPrint('SARCADE notification [$priority] $title: $body');return;}
    try{
      web.Notification(title,web.NotificationOptions(body:body,tag:'sarcade-${DateTime.now().millisecondsSinceEpoch}',
        requireInteraction:isUrgentPriority(priority)));
    }catch(e){
      debugPrint('SARCADE notification failed: $e');
    }
  }
}
