import '../../models/message.dart';
import '../../services/notification_actions.dart';
import 'car_context.dart';

/// Web application: no car (the browser handles its own notifications).
Future<void> saveCarContext(CarContext c) async {}
Future<CarContext?> loadCarContext() async=>null;
Future<bool> sendAnswerNow(PendingAnswer a) async=>false;
Future<({SarcadeMessage message,String deviceId})?> fetchWokenMessage(Map<String,dynamic> data) async=>null;
