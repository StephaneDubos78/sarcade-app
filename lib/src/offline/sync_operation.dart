class SyncOperation {
  final String operationId,eventId,objectId,objectType,action;
  final DateTime clientTime; final Map<String,dynamic> payload;
  const SyncOperation({required this.operationId,required this.eventId,required this.objectId,required this.objectType,required this.action,required this.clientTime,required this.payload});
  Map<String,dynamic> toJson()=>{'operation_id':operationId,'event_id':eventId,'object_id':objectId,'object_type':objectType,'action':action,'client_time':clientTime.toUtc().toIso8601String(),'payload':payload};
}
