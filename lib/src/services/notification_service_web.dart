import 'dart:async';
import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;
import '../l10n/strings.dart';
import 'notification_actions.dart';

export 'notification_actions.dart' show isUrgentPriority, NotificationPayload, PendingAnswer;

/// Nothing waits in a file on the web: answers are given in the application.
Future<List<PendingAnswer>> takePendingAnswers() async=>const [];

/// Browser notifications (installed PWA on ChromeOS, any browser): shown
/// when the operator allowed them; urgent ones stay until dismissed. A click
/// brings the application to the front on the message; browsers do not offer
/// reliable action buttons outside a service worker, so the answer is given
/// in the messages screen. Immediate messages are reminded while the
/// application is open.
class NotificationService {
  static final NotificationService _instance=NotificationService._();
  factory NotificationService()=>_instance;
  NotificationService._();

  bool _allowed=false; Future<void>? _init;
  bool bypassDnd=false;
  final _opens=StreamController<String>.broadcast();
  final _answers=StreamController<void>.broadcast();
  final Map<String,List<Timer>> _timers={};

  Stream<String> get opens=>_opens.stream;
  Stream<void> get answers=>_answers.stream;
  static bool get supportsDndBypass=>false;

  Future<void> initialize()=>_init??=_initialize();

  Future<void> _initialize() async {
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

  Future<bool> enableDndBypass() async=>false;

  void _show(String title,String body,String priority,NotificationPayload? payload){
    final n=web.Notification(title,web.NotificationOptions(body:body,
      tag:payload==null?'sarcade-${DateTime.now().millisecondsSinceEpoch}':'sarcade-${payload.messageId}',
      requireInteraction:isUrgentPriority(priority)));
    if(payload!=null){
      n.onclick=((web.Event _){
        web.window.focus();
        _opens.add(payload.messageId);
        n.close();
      }).toJS;
    }
  }

  Future<void> message({required String title,required String body,required String priority,NotificationPayload? payload}) async {
    if(!_allowed){debugPrint('SARCADE notification [$priority] $title: $body');return;}
    try{
      _show(title,body,priority,payload);
      if(priority=='immediate'&&payload!=null){
        final times=reminderTimes(DateTime.now().toUtc());
        for(var k=1;k<=times.length;k++){
          final n=k;
          _timers.putIfAbsent(payload.messageId,()=>[]).add(Timer(times[k-1].difference(DateTime.now().toUtc()),(){
            _show(S.t('notif.reminder',{'n':n,'total':times.length,'title':title}),body,priority,payload);
          }));
        }
      }
    }catch(e){
      debugPrint('SARCADE notification failed: $e');
    }
  }

  Future<void> answered(String messageId,String status) async {
    if(!stopsReminders(status))return;
    for(final t in _timers.remove(messageId)??const <Timer>[]){t.cancel();}
  }
}
