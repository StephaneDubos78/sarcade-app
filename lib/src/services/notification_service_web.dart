import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

bool isUrgentPriority(String priority)=>priority=='urgent'||priority=='immediate';

/// Browser notifications (installed PWA on ChromeOS, any browser): shown
/// when the operator allowed them; urgent ones stay until dismissed.
class NotificationService {
  bool _allowed=false;

  Future<void> initialize() async {
    try{
      final current=web.Notification.permission;
      if(current=='granted'){_allowed=true;return;}
      if(current=='default'){
        final answer=await web.Notification.requestPermission().toDart;
        _allowed=answer.toDart=='granted';
      }
    }catch(e){
      debugPrint('SARCADE notifications unavailable: $e');
    }
  }

  Future<void> message({required String title,required String body,required String priority}) async {
    if(!_allowed){debugPrint('SARCADE notification [$priority] $title: $body');return;}
    try{
      web.Notification(title,web.NotificationOptions(body:body,tag:'sarcade-${DateTime.now().millisecondsSinceEpoch}',
        requireInteraction:isUrgentPriority(priority)));
    }catch(e){
      debugPrint('SARCADE notification failed: $e');
    }
  }
}
