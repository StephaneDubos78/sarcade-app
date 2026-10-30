/// Navigation of the Messages screen from outside (lot 10C, 30 Oct 2026).
/// « Bouton Messages, réappui = retour à la liste » (13 h 22): a new press
/// on Messages while a conversation is open comes back to the list of the
/// groups and conversations; from the list it closes Messages.
library;

import 'package:flutter/material.dart';

class MessagesNavigator {
  bool Function()? _back;
  /// Set by the Messages screen shown; cleared when it goes away.
  void attach(bool Function()? back)=>_back=back;
  void detach(bool Function() back){if(identical(_back,back))_back=null;}
  /// True when a conversation was open and the list is shown again; false
  /// when the list was already shown (the caller then closes Messages).
  bool backToList()=>_back?.call()??false;
}

/// Drafts kept per conversation: the conversation left keeps what was
/// being written (decision 2 of the card of 13 h 22).
class ConversationDrafts {
  final Map<String,String> _byConv={};
  String take(String conv)=>_byConv[conv]??'';
  void keep(String conv,String text){if(text.isEmpty){_byConv.remove(conv);}else{_byConv[conv]=text;}}
}

/// Side panel beside the map, as the other sub-screens (the map stays
/// visible behind).
Widget chatSidePanel({required double width,required Widget child})=>SizedBox(width:width,child:Material(elevation:3,child:child));

/// Computer rail: « Messages » in blue while the Messages page or a
/// conversation side panel is open (card of 30 Oct 2026, 16 h 13).
bool messagesRailSelected({required String? deskId,required String? chatPeer})=>deskId=='messages'||chatPeer!=null;
