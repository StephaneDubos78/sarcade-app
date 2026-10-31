import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../features/car/car_background.dart' show fetchWokenMessage;
import '../l10n/strings.dart';
import 'notification_actions.dart' show NotificationPayload, actionOpen, actionsFor, notificationIdFor;

/// Wake-up of Android when SARCADE is closed (note « Réveil des appareils »).
/// The Firebase project is given at build time by the CI (secret
/// GOOGLE_SERVICES_JSON); without it nothing is initialised.
const _apiKey=String.fromEnvironment('SARCADE_FCM_API_KEY');
const _appId=String.fromEnvironment('SARCADE_FCM_APP_ID');
const _senderId=String.fromEnvironment('SARCADE_FCM_SENDER_ID');
const _projectId=String.fromEnvironment('SARCADE_FCM_PROJECT_ID');
/// iPhone: same Firebase project, its own app (GoogleService-Info.plist,
/// secret GOOGLE_SERVICE_INFO_PLIST); the APNs key is held by Firebase.
const _iosApiKey=String.fromEnvironment('SARCADE_FCM_IOS_API_KEY');
const _iosAppId=String.fromEnvironment('SARCADE_FCM_IOS_APP_ID');

bool get _ios=>!kIsWeb&&defaultTargetPlatform==TargetPlatform.iOS;
bool get fcmAvailable=>!kIsWeb&&_senderId.isNotEmpty&&_projectId.isNotEmpty&&(
  defaultTargetPlatform==TargetPlatform.android?_apiKey.isNotEmpty&&_appId.isNotEmpty
  :_ios&&_iosApiKey.isNotEmpty&&_iosAppId.isNotEmpty);

/// Platform name of the token for the server (« fcm_ios »: the server adds
/// the generic alert that iOS needs to show something application closed).
String get fcmPlatform=>_ios?'fcm_ios':'fcm';

Future<void> _ensureFirebase() async {
  if(Firebase.apps.isEmpty){
    await Firebase.initializeApp(options:_ios
      ?const FirebaseOptions(apiKey:_iosApiKey,appId:_iosAppId,messagingSenderId:_senderId,projectId:_projectId,iosBundleId:'org.sarcade.sarcadeApp')
      :const FirebaseOptions(apiKey:_apiKey,appId:_appId,messagingSenderId:_senderId,projectId:_projectId));
  }
}

/// Signal received with SARCADE closed: the server sends no content, so the
/// notification asks to open SARCADE, which then synchronises.
@pragma('vm:entry-point')
Future<void> fcmBackgroundHandler(RemoteMessage message) async {
  // iPhone: the system already shows the alert sent by the server.
  if(defaultTargetPlatform==TargetPlatform.iOS)return;
  await showWakeNotification(message.data);
}

String wakeTitle(Map<String,dynamic> data){
  final priority='${data['priority']??'routine'}';
  if(data['kind']=='test')return 'SARCADE : réveil reçu';
  return priority=='immediate'||priority=='urgent'?'SARCADE : message prioritaire':'SARCADE : nouveau message';
}

String wakeChannel(Map<String,dynamic> data)=>switch('${data['priority']??'routine'}'){
  'immediate'=>'sarcade_immediate','urgent'=>'sarcade_urgent',_=>'sarcade_routine'};

/// Same identifier as the notification of the message shown later by the
/// application (« tag » of the server: the message, or the distress of its
/// sender): one notification, whatever the path (30 Oct 2026, 12 h 45).
/// An older server without the tag: one per event, as before.
int wakeNotificationId(Map<String,dynamic> data){
  final tag='${data['tag']??''}';
  return tag.isNotEmpty?notificationIdFor(tag):90000+('${data['event_id']}'.hashCode&0x3ff);
}

Future<void> showWakeNotification(Map<String,dynamic> data) async {
  if(data['type']!='wake')return;
  final urgent=wakeChannel(data)!='sarcade_routine';
  final plugin=FlutterLocalNotificationsPlugin();
  await plugin.initialize(const InitializationSettings(android:AndroidInitializationSettings('@mipmap/ic_launcher')));
  // Real text read from the server of the application, so that the car
  // reads the message itself (lot 1a); otherwise the generic text.
  final woken=data['kind']=='test'?null:await fetchWokenMessage(data);
  final m=woken?.message;
  final payload=m==null?null:NotificationPayload(eventId:m.eventId,messageId:m.id,deviceId:woken!.deviceId,
    priority:m.priority,tag:'${data['tag']}');
  // Same title as the notification shown by the application.
  final title=m==null?wakeTitle(data):'SARCADE · ${S.t('priority.${m.priority}')} · ${m.senderId}';
  await plugin.show(wakeNotificationId(data),title,m?.body??'Ouvrez SARCADE pour le lire.',
    NotificationDetails(android:AndroidNotificationDetails(wakeChannel(data),wakeChannel(data),
      importance:urgent?Importance.max:Importance.defaultImportance,priority:urgent?Priority.max:Priority.defaultPriority,
      category:AndroidNotificationCategory.message,
      actions:payload==null?null:[for(final a in actionsFor(m!.priority))
        AndroidNotificationAction(a,S.t('notif.action.$a'),showsUserInterface:a==actionOpen)])),
    payload:payload?.encode());
}

/// Token of this phone for the server; null without Firebase.
Future<String?> fcmToken() async {
  if(!fcmAvailable)return null;
  try{
    await _ensureFirebase();
    FirebaseMessaging.onBackgroundMessage(fcmBackgroundHandler);
    if(_ios){
      // iPhone: the operator allows the notifications, then the APNs
      // token must exist before Firebase gives its own.
      final settings=await FirebaseMessaging.instance.requestPermission(alert:true,sound:true,badge:false);
      if(settings.authorizationStatus==AuthorizationStatus.denied)return null;
      for(var i=0;i<10&&await FirebaseMessaging.instance.getAPNSToken()==null;i++){
        await Future<void>.delayed(const Duration(seconds:1));
      }
    }
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
