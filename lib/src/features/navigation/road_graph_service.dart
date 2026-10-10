import 'dart:typed_data';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../../offline/local_store.dart';
import '../../services/sarcade_api.dart';
import 'road_graph.dart';

RoadGraph _parse(Uint8List bytes)=>RoadGraph.parse(bytes);

/// Keeps the road graph of navigation on the device up to date: downloaded
/// automatically on Wi-Fi or on the local network of the PCO when an event
/// opens, never on mobile data without the operator's consent (decision of
/// 10 Oct 2026); parsed off the main thread.
class RoadGraphService extends ChangeNotifier {
  final SarcadeApi api; final LocalStore store;
  RoadGraphService({required this.api,required this.store});

  RoadGraph? graph;
  /// Size of a newer graph waiting for consent on mobile data.
  int? pendingMobileBytes;
  bool downloading=false;
  Map<String,dynamic>? get info=>store.roadGraphInfo();

  Future<void> start() async {
    await _loadLocal();
    await check();
  }

  Future<void> _loadLocal() async {
    try{
      final bytes=await store.roadGraph();
      if(bytes!=null){graph=await compute(_parse,bytes);notifyListeners();}
    }catch(e){debugPrint('road graph unreadable: $e');}
  }

  /// Compares with the server version; downloads when allowed.
  Future<void> check({bool allowMobile=false}) async {
    try{
      final remote=await api.roadGraphInfo();
      if(remote['available']!=true)return;
      if(remote['sha256']==info?['sha256']&&graph!=null){pendingMobileBytes=null;return;}
      if(!allowMobile&&!await _unmeteredNetwork()){
        pendingMobileBytes=(remote['size'] as num?)?.toInt();
        notifyListeners();
        return;
      }
      downloading=true; notifyListeners();
      final bytes=Uint8List.fromList(await api.download('/api/v0.1/routing/graph'));
      final parsed=await compute(_parse,bytes);
      await store.saveRoadGraph(bytes,remote);
      graph=parsed; pendingMobileBytes=null;
    }catch(e){
      debugPrint('road graph not updated: $e');
    }finally{
      if(downloading){downloading=false;notifyListeners();}
    }
  }

  /// Wi-Fi or wired network (the PCO local network). A browser cannot tell,
  /// and the web app is served by the SARCADE server itself: allowed.
  Future<bool> _unmeteredNetwork() async {
    if(kIsWeb)return true;
    try{
      final types=await Connectivity().checkConnectivity();
      return types.contains(ConnectivityResult.wifi)||types.contains(ConnectivityResult.ethernet);
    }catch(_){return false;}
  }
}
