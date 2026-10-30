import 'package:flutter/services.dart';

const _channel=EventChannel('org.sarcade/compass');

/// Raw events of the system compass: [heading (degrees from magnetic north,
/// -1 when not valid), accuracy (degrees, -1 when unknown), status (0-3 on
/// Android, -1 on iPhone)].
Stream<List<double>> systemCompassEvents()=>_channel.receiveBroadcastStream().map((e)=>[for(final v in e as List)(v as num).toDouble()]);
