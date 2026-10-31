import 'dart:async';
import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;
import '../l10n/strings.dart';
import 'notification_actions.dart';

export 'notification_actions.dart' show isUrgentPriority, NotificationPayload, PendingAnswer;

/// Nothing waits in a file on the web: answers are given in the application.
Future<List<PendingAnswer>> takePendingAnswers() async=>const [];

/// Browser notifications (installed PWA on ChromeOS and Windows, any
/// browser): shown when the operator allowed them; urgent ones stay until
/// dismissed. Browsers ignore a permission request that does not follow a
/// click (recette of lot 2, 25 October 2026): the request is made from the
/// « Activer les notifications » banner, and the permission is read again
/// for every message. A click
/// brings the application to the front on the message; browsers do not offer
/// reliable action buttons outside a service worker, so the answer is given
/// in the messages screen. Immediate messages are reminded while the
/// application is open.
class NotificationService {
  static final NotificationService _instance=NotificationService._();
  factory NotificationService()=>_instance;
  NotificationService._();
  /// Windows only (see the installed apps); always null on the web.
  static String? windowsUnavailable;

  String get _permission{try{return web.Notification.permission;}catch(_){return 'unsupported';}}

  /// The operator has not answered yet: show the banner.
  bool get needsUserAction=>_permission=='default';
  bool bypassDnd=false;
  /// Sound by priority (see [soundFor]): a browser only knows silent or not.
  Map<String,String> sounds={};
  final _opens=StreamController<String>.broadcast();
  final _answers=StreamController<void>.broadcast();
  final Map<String,List<Timer>> _timers={};

  Stream<String> get opens=>_opens.stream;
  Stream<void> get answers=>_answers.stream;
  static bool get supportsDndBypass=>false;

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

  Future<bool> enableDndBypass() async=>false;

  /// Allowed (true), refused or not asked yet (false), unsupported (null).
  Future<bool?> permissionGranted() async=>_permission=='unsupported'?null:_permission=='granted';
  /// The browser asks again only while the operator has not answered.
  Future<void> openPermissionSettings() async {await requestFromUser();}
  /// Refused once: only the site settings of the browser can change it.
  bool get permissionBlocked=>_permission=='denied';

  void _show(String title,String body,String priority,NotificationPayload? payload){
    final n=web.Notification(title,web.NotificationOptions(body:body,
      // One notification per message (or per distress): the same tag
      // replaces it, renotify rings again (30 Oct 2026, 12 h 45).
      tag:payload==null?'sarcade-${DateTime.now().millisecondsSinceEpoch}':'sarcade-${payload.key}',renotify:payload!=null,
      requireInteraction:isUrgentPriority(priority),
      silent:const {soundSilent,soundDiscreet}.contains(soundFor(priority,sounds,sos:isSosBody(body)))));
    if(payload!=null){
      n.onclick=((web.Event _){
        web.window.focus();
        _opens.add(payload.messageId);
        n.close();
      }).toJS;
    }
  }

  Future<void> message({required String title,required String body,required String priority,NotificationPayload? payload}) async {
    if(_permission!='granted'){debugPrint('SARCADE notification [$priority] $title: $body');return;}
    try{
      if(payload!=null){for(final t in _timers.remove(payload.key)??const <Timer>[]){t.cancel();}}
      _show(title,body,priority,payload);
      if(priority=='immediate'&&payload!=null){
        final times=reminderTimes(DateTime.now().toUtc());
        for(var k=1;k<=times.length;k++){
          final n=k;
          _timers.putIfAbsent(payload.key,()=>[]).add(Timer(times[k-1].difference(DateTime.now().toUtc()),(){
            _show(S.t('notif.reminder',{'n':n,'total':times.length,'title':title}),body,priority,payload);
          }));
        }
      }
    }catch(e){
      debugPrint('SARCADE notification failed: $e');
    }
  }

  Future<void> answered(String messageId,String status,{String? key}) async {
    if(!stopsReminders(status))return;
    for(final id in {messageId,?key}){for(final t in _timers.remove(id)??const <Timer>[]){t.cancel();}}
  }
}
