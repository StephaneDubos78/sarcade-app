import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Wake-up of Android when SARCADE is closed (note « Réveil des appareils »).
/// The Firebase project is given at build time by the CI (secret
/// GOOGLE_SERVICES_JSON); without it nothing is initialised.
const _apiKey=String.fromEnvironment('SARCADE_FCM_API_KEY');
const _appId=String.fromEnvironment('SARCADE_FCM_APP_ID');
const _senderId=String.fromEnvironment('SARCADE_FCM_SENDER_ID');
const _projectId=String.fromEnvironment('SARCADE_FCM_PROJECT_ID');

bool get fcmAvailable=>!kIsWeb&&defaultTargetPlatform==TargetPlatform.android
  &&_apiKey.isNotEmpty&&_appId.isNotEmpty&&_senderId.isNotEmpty&&_projectId.isNotEmpty;

Future<void> _ensureFirebase() async {
  if(Firebase.apps.isEmpty){
    await Firebase.initializeApp(options:const FirebaseOptions(apiKey:_apiKey,appId:_appId,messagingSenderId:_senderId,projectId:_projectId));
  }
}

/// Signal received with SARCADE closed: the server sends no content, so the
/// notification asks to open SARCADE, which then synchronises.
@pragma('vm:entry-point')
Future<void> fcmBackgroundHandler(RemoteMessage message) async {
  await showWakeNotification(message.data);
}

String wakeTitle(Map<String,dynamic> data){
  final priority='${data['priority']??'routine'}';
  if(data['kind']=='test')return 'SARCADE : réveil reçu';
  return priority=='immediate'||priority=='urgent'?'SARCADE : message prioritaire':'SARCADE : nouveau message';
}

String wakeChannel(Map<String,dynamic> data)=>switch('${data['priority']??'routine'}'){
  'immediate'=>'sarcade_immediate','urgent'=>'sarcade_urgent',_=>'sarcade_routine'};

Future<void> showWakeNotification(Map<String,dynamic> data) async {
  if(data['type']!='wake')return;
  final urgent=wakeChannel(data)!='sarcade_routine';
  final plugin=FlutterLocalNotificationsPlugin();
  await plugin.initialize(const InitializationSettings(android:AndroidInitializationSettings('@mipmap/ic_launcher')));
  await plugin.show(90000+('${data['event_id']}'.hashCode&0x3ff),wakeTitle(data),'Ouvrez SARCADE pour le lire.',
    NotificationDetails(android:AndroidNotificationDetails(wakeChannel(data),wakeChannel(data),
      importance:urgent?Importance.max:Importance.defaultImportance,priority:urgent?Priority.max:Priority.defaultPriority,
      category:AndroidNotificationCategory.message)));
}

/// Token of this phone for the server; null without Firebase.
Future<String?> fcmToken() async {
  if(!fcmAvailable)return null;
  try{
    await _ensureFirebase();
    FirebaseMessaging.onBackgroundMessage(fcmBackgroundHandler);
    return await FirebaseMessaging.instance.getToken();
  }catch(e){
    debugPrint('SARCADE FCM unavailable: $e');
    return null;
  }
}

/// New token given by Firebase (sent again to the server).
Stream<String> fcmTokenRefresh()=>fcmAvailable?FirebaseMessaging.instance.onTokenRefresh:const Stream<String>.empty();

/// Signal received with SARCADE open: the application synchronises.
Stream<Map<String,dynamic>> fcmForeground()=>fcmAvailable?FirebaseMessaging.onMessage.map((m)=>m.data):const Stream<Map<String,dynamic>>.empty();
