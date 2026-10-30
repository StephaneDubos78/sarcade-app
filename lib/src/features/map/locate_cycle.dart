/// One « Ma position » button (card « Carte, boutons Recentrer et Ma
/// position fusionnés », decision of 30 Oct 2026, 2 h 54): each touch goes
/// to the next mode, no long press: centred on me → follow → compass →
/// every operator → centred on me.
library;

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';

enum LocateMode { idle, me, follow, compass, all }

/// Mode after a touch; [compass] false (computer, refused) skips the compass.
LocateMode nextLocateMode(LocateMode m,{bool compass=true})=>switch(m){
  LocateMode.idle=>LocateMode.me,
  LocateMode.me=>LocateMode.follow,
  LocateMode.follow=>compass?LocateMode.compass:LocateMode.all,
  LocateMode.compass=>LocateMode.all,
  LocateMode.all=>LocateMode.me,
};

IconData locateIcon(LocateMode m)=>switch(m){
  LocateMode.idle=>Icons.location_searching,
  LocateMode.me=>Icons.my_location,
  LocateMode.follow=>Icons.navigation,
  LocateMode.compass=>Icons.explore,
  LocateMode.all=>Icons.zoom_out_map,
};

String locateTooltip(LocateMode m)=>S.t(switch(m){
  LocateMode.idle||LocateMode.me=>'map.myPosition',
  LocateMode.follow=>'map.followMeOn',
  LocateMode.compass=>'map.compassOn',
  LocateMode.all=>'map.fit',
});

/// Short label shown 2 s when the mode changes (none for « centred on me »).
String? locateLabel(LocateMode m)=>switch(m){
  LocateMode.follow=>S.t('locate.follow'),
  LocateMode.compass=>S.t('locate.compass'),
  LocateMode.all=>S.t('locate.all'),
  _=>null,
};
