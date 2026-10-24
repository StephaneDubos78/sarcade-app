import 'dart:async';
import 'dart:io';
import 'dart:ui' show DartPluginRegistrant;
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:uuid/uuid.dart';
import '../l10n/strings.dart';
import 'notification_actions.dart';

export 'notification_actions.dart' show isUrgentPriority, NotificationPayload, PendingAnswer;

/// Urgent messages, weather warnings.
const _urgentChannel=AndroidNotificationChannel('sarcade_urgent','Messages urgents',
  description:'Messages urgents, vigilance météo',importance:Importance.max);
/// Routine messages.
const _routineChannel=AndroidNotificationChannel('sarcade_routine','Messages',
  description:'Messages de routine',importance:Importance.defaultImportance);
/// Immediate messages: alarm sound and long vibration, distinct from the others.
final _immediateChannel=AndroidNotificationChannel('sarcade_immediate','Messages immédiats',
  description:'Messages immédiats, rappelés toutes les 2 minutes jusqu’à la réponse',importance:Importance.max,
  sound:const UriAndroidNotificationSound('content://settings/system/alarm_alert'),
  vibrationPattern:Int64List.fromList([0,700,300,700,300,700]));
/// Same, ringing in Do Not Disturb mode: only with the consent of the
/// operator and the access to the Do Not Disturb policy granted by Android.
final _immediateDndChannel=AndroidNotificationChannel('sarcade_immediate_dnd','Messages immédiats (Ne pas déranger)',
  description:'Messages immédiats, même en mode Ne pas déranger',importance:Importance.max,bypassDnd:true,
  sound:const UriAndroidNotificationSound('content://settings/system/alarm_alert'),
  vibrationPattern:Int64List.fromList([0,700,300,700,300,700]));

const _answersFileName='sarcade_notification_answers.jsonl';

Future<File> _answersFile() async =>
  File('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}$_answersFileName');

/// Appends an answer given from a notification (main or background isolate).
Future<void> appendPendingAnswer(PendingAnswer a) async {
  final f=await _answersFile();
  await f.parent.create(recursive:true);
  await f.writeAsString('${a.toLine()}\n',mode:FileMode.append,flush:true);
}

/// Takes the answers waiting since the last call (renamed before reading,
/// so that an answer written meanwhile by a background isolate is kept).
Future<List<PendingAnswer>> takePendingAnswers() async {
  final f=await _answersFile();
  final draining=File('${f.path}.draining');
  final out=<PendingAnswer>[];
  if(await draining.exists()){out.addAll(PendingAnswer.parseLines(await draining.readAsString()));await draining.delete();}
  if(await f.exists()){
    await f.rename(draining.path);
    out.addAll(PendingAnswer.parseLines(await draining.readAsString()));
    await draining.delete();
  }
  return out;
}

/// Action tapped while the application is closed or in the background
/// (Android, iOS): the answer waits in a file until the application queues
/// it in the Outbox; the reminders stop at once.
@pragma('vm:entry-point')
Future<void> notificationBackgroundHandler(NotificationResponse response) async {
  DartPluginRegistrant.ensureInitialized();
  final payload=NotificationPayload.decode(response.payload);
  final status=ackStatusForAction(resolveAction(response.actionId,response.payload));
  if(payload==null||status==null)return;
  await appendPendingAnswer(PendingAnswer(id:const Uuid().v4(),eventId:payload.eventId,messageId:payload.messageId,
    deviceId:payload.deviceId,status:status,time:DateTime.now().toUtc()));
  final plugin=FlutterLocalNotificationsPlugin();
  for(var k=1;k<=reminderCount;k++){
    try{await plugin.cancel(notificationIdFor(payload.messageId,k));}catch(_){/* already shown or gone */}
  }
}

/// System notifications: messages addressed to the terminal with their
/// actions (Accept, Refuse, Read, Open), reminders of the immediate
/// messages, weather warnings. One instance for the application.
class NotificationService {
  static final NotificationService _instance=NotificationService._();
  factory NotificationService()=>_instance;
  NotificationService._();

  final _plugin=FlutterLocalNotificationsPlugin();
  Future<void>? _init;
  bool _ready=false; int _id=0;
  /// Consent of the operator to ring immediate messages in Do Not Disturb.
  bool bypassDnd=false;
  final _opens=StreamController<String>.broadcast();
  final _answers=StreamController<void>.broadcast();
  final Map<String,List<Timer>> _timers={};

  /// Message to open (Open, or a tap on the notification).
  Stream<String> get opens=>_opens.stream;
  /// New answers waiting to be queued (see [takePendingAnswers]).
  Stream<void> get answers=>_answers.stream;

  static bool get supportsDndBypass=>defaultTargetPlatform==TargetPlatform.android;
  static bool get _schedules=>const {TargetPlatform.android,TargetPlatform.iOS,TargetPlatform.macOS,TargetPlatform.windows}
    .contains(defaultTargetPlatform);

  Future<void> initialize()=>_init??=_initialize();

  Future<void> _initialize() async {
    try{
      final urgentCategory=DarwinNotificationCategory('sarcade_urgent',actions:[
        DarwinNotificationAction.plain(actionAccept,S.t('notif.action.accept')),
        DarwinNotificationAction.plain(actionRefuse,S.t('notif.action.refuse'),options:{DarwinNotificationActionOption.destructive}),
        DarwinNotificationAction.plain(actionOpen,S.t('notif.action.open'),options:{DarwinNotificationActionOption.foreground}),
      ]);
      final routineCategory=DarwinNotificationCategory('sarcade_routine',actions:[
        DarwinNotificationAction.plain(actionRead,S.t('notif.action.read')),
        DarwinNotificationAction.plain(actionOpen,S.t('notif.action.open'),options:{DarwinNotificationActionOption.foreground}),
      ]);
      final darwin=DarwinInitializationSettings(notificationCategories:[urgentCategory,routineCategory]);
      await _plugin.initialize(InitializationSettings(
        android:const AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS:darwin,
        macOS:darwin,
        linux:LinuxInitializationSettings(defaultActionName:S.t('notif.action.open')),
        windows:const WindowsInitializationSettings(appName:'SARCADE',appUserModelId:'org.sarcade.app',
          guid:'5f0e7c2a-1b8d-4c3e-9a6f-2d4b8e1c7a90'),
      ),onDidReceiveNotificationResponse:_onResponse,onDidReceiveBackgroundNotificationResponse:notificationBackgroundHandler);
      final android=_plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(_urgentChannel);
      await android?.createNotificationChannel(_routineChannel);
      await android?.createNotificationChannel(_immediateChannel);
      // Android 13 and later ask the operator once.
      await android?.requestNotificationsPermission();
      _ready=true;
      // Application started by a notification (action or tap, application closed).
      final launch=await _plugin.getNotificationAppLaunchDetails();
      final response=launch?.notificationResponse;
      if(launch?.didNotificationLaunchApp==true&&response!=null)await _onResponse(response);
    }catch(e){
      debugPrint('SARCADE notifications unavailable: $e');
    }
  }

  Future<void> _onResponse(NotificationResponse response) async {
    final payload=NotificationPayload.decode(response.payload);
    if(payload==null)return;
    final status=ackStatusForAction(resolveAction(response.actionId,response.payload));
    if(status==null){_opens.add(payload.messageId);return;}
    await appendPendingAnswer(PendingAnswer(id:const Uuid().v4(),eventId:payload.eventId,messageId:payload.messageId,
      deviceId:payload.deviceId,status:status,time:DateTime.now().toUtc()));
    await answered(payload.messageId,status);
    _answers.add(null);
  }

  /// Consent to ring the immediate messages in Do Not Disturb (Android):
  /// asks Android for the access to the Do Not Disturb policy.
  Future<bool> enableDndBypass() async {
    final android=_plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if(android==null)return false;
    try{
      if(await android.hasNotificationPolicyAccess()!=true)await android.requestNotificationPolicyAccess();
      final granted=await android.hasNotificationPolicyAccess()==true;
      if(granted)await android.createNotificationChannel(_immediateDndChannel);
      return granted;
    }catch(_){
      return false;
    }
  }

  Future<AndroidNotificationChannel> _channelFor(String priority) async {
    if(priority=='immediate'){
      if(bypassDnd){
        final android=_plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        try{
          if(await android?.hasNotificationPolicyAccess()==true){
            await android?.createNotificationChannel(_immediateDndChannel);
            return _immediateDndChannel;
          }
        }catch(_){/* falls back on the ordinary immediate channel */}
      }
      return _immediateChannel;
    }
    return isUrgentPriority(priority)?_urgentChannel:_routineChannel;
  }

  Future<NotificationDetails> _details(String priority,NotificationPayload? payload) async {
    final urgent=isUrgentPriority(priority), immediate=priority=='immediate';
    final channel=await _channelFor(priority);
    final actions=payload==null?const <String>[]:actionsFor(priority);
    return NotificationDetails(
      android:AndroidNotificationDetails(channel.id,channel.name,channelDescription:channel.description,
        importance:channel.importance,priority:urgent?Priority.max:Priority.defaultPriority,
        category:urgent?AndroidNotificationCategory.message:null,
        sound:channel.sound,vibrationPattern:channel.vibrationPattern,
        audioAttributesUsage:channel.audioAttributesUsage,
        actions:[for(final a in actions)AndroidNotificationAction(a,S.t('notif.action.$a'),showsUserInterface:a==actionOpen)]),
      iOS:DarwinNotificationDetails(interruptionLevel:urgent?InterruptionLevel.timeSensitive:InterruptionLevel.active,
        categoryIdentifier:payload==null?null:(urgent?'sarcade_urgent':'sarcade_routine')),
      macOS:DarwinNotificationDetails(categoryIdentifier:payload==null?null:(urgent?'sarcade_urgent':'sarcade_routine')),
      linux:LinuxNotificationDetails(urgency:urgent?LinuxNotificationUrgency.critical:LinuxNotificationUrgency.normal,
        actions:[for(final a in actions)LinuxNotificationAction(key:a,label:S.t('notif.action.$a'))]),
      windows:WindowsNotificationDetails(
        actions:[for(final a in actions)WindowsAction(content:S.t('notif.action.$a'),arguments:payload!.encode(a))],
        scenario:immediate&&payload!=null?WindowsNotificationScenario.reminder:null,
        audio:immediate?WindowsNotificationAudio.preset(sound:WindowsNotificationSound.reminder):null),
    );
  }

  /// Shows a notification; with [payload] (a message addressed to this
  /// terminal) it carries the actions, and an immediate message is reminded
  /// every 2 minutes, at most 3 times, until the operator answers.
  Future<void> message({required String title,required String body,required String priority,NotificationPayload? payload}) async {
    if(!_ready){debugPrint('SARCADE notification [$priority] $title: $body');return;}
    try{
      final id=payload==null?(_id++ & 0x0fffffff)|0x40000000:notificationIdFor(payload.messageId);
      await _plugin.show(id,title,body,await _details(priority,payload),payload:payload?.encode());
      if(priority=='immediate'&&payload!=null)await _scheduleReminders(title,body,payload);
    }catch(e){
      debugPrint('SARCADE notification failed: $e');
    }
  }

  Future<void> _scheduleReminders(String title,String body,NotificationPayload payload) async {
    final details=await _details(payload.priority,payload);
    final times=reminderTimes(DateTime.now().toUtc());
    for(var k=1;k<=times.length;k++){
      final reminderTitle=S.t('notif.reminder',{'n':k,'total':times.length,'title':title});
      final id=notificationIdFor(payload.messageId,k);
      if(_schedules){
        try{
          await _plugin.zonedSchedule(id,reminderTitle,body,tz.TZDateTime.from(times[k-1],tz.UTC),details,
            androidScheduleMode:AndroidScheduleMode.inexactAllowWhileIdle,payload:payload.encode());
          continue;
        }catch(e){
          debugPrint('SARCADE reminder not scheduled ($e): kept in the application');
        }
      }
      // Linux and fallback: reminders while the application runs.
      _timers.putIfAbsent(payload.messageId,()=>[]).add(Timer(times[k-1].difference(DateTime.now().toUtc()),(){
        _plugin.show(id,reminderTitle,body,details,payload:payload.encode());
      }));
    }
  }

  /// The operator answered (notification action or messages screen): the
  /// reminders stop and the notification goes away.
  Future<void> answered(String messageId,String status) async {
    if(!stopsReminders(status))return;
    for(final t in _timers.remove(messageId)??const <Timer>[]){t.cancel();}
    if(!_ready)return;
    for(var k=0;k<=reminderCount;k++){
      try{await _plugin.cancel(notificationIdFor(messageId,k));}catch(_){/* nothing to cancel */}
    }
  }
}
