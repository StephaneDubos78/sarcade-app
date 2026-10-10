import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Urgent and immediate messages, weather warnings.
const _urgentChannel=AndroidNotificationChannel('sarcade_urgent','Messages urgents',
  description:'Messages urgents et immédiats, vigilance météo',importance:Importance.max);
/// Routine messages.
const _routineChannel=AndroidNotificationChannel('sarcade_routine','Messages',
  description:'Messages de routine',importance:Importance.defaultImportance);

bool isUrgentPriority(String priority)=>priority=='urgent'||priority=='immediate';

class NotificationService {
  final _plugin=FlutterLocalNotificationsPlugin();
  bool _ready=false; int _id=0;

  Future<void> initialize() async {
    try{
      await _plugin.initialize(const InitializationSettings(
        android:AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS:DarwinInitializationSettings(),
        macOS:DarwinInitializationSettings(),
        linux:LinuxInitializationSettings(defaultActionName:'Ouvrir SARCADE'),
        windows:WindowsInitializationSettings(appName:'SARCADE',appUserModelId:'org.sarcade.app',
          guid:'5f0e7c2a-1b8d-4c3e-9a6f-2d4b8e1c7a90'),
      ));
      final android=_plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(_urgentChannel);
      await android?.createNotificationChannel(_routineChannel);
      // Android 13 and later ask the operator once.
      await android?.requestNotificationsPermission();
      _ready=true;
    }catch(e){
      debugPrint('SARCADE notifications unavailable: $e');
    }
  }

  Future<void> message({required String title,required String body,required String priority}) async {
    if(!_ready){debugPrint('SARCADE notification [$priority] $title: $body');return;}
    final urgent=isUrgentPriority(priority);
    final channel=urgent?_urgentChannel:_routineChannel;
    try{
      await _plugin.show(_id++ & 0x7fffffff,title,body,NotificationDetails(
        android:AndroidNotificationDetails(channel.id,channel.name,channelDescription:channel.description,
          importance:channel.importance,priority:urgent?Priority.max:Priority.defaultPriority,
          category:urgent?AndroidNotificationCategory.message:null),
        iOS:DarwinNotificationDetails(interruptionLevel:urgent?InterruptionLevel.timeSensitive:InterruptionLevel.active),
        linux:LinuxNotificationDetails(urgency:urgent?LinuxNotificationUrgency.critical:LinuxNotificationUrgency.normal),
      ));
    }catch(e){
      debugPrint('SARCADE notification failed: $e');
    }
  }
}
