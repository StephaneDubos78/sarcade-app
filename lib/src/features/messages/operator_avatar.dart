/// Round avatar with initials (« Messages, avatar rond avec initiales »,
/// 30 Oct 2026): 2 or 3 letters on the operator colour, shared by the
/// bubbles, the conversation list and Équipes.
library;

import 'package:flutter/material.dart';

import 'conversations.dart';

Widget operatorAvatar(String id,{String? label,double radius=15,bool stale=false}){
  final letters=avatarInitials(label==null||label.trim().isEmpty?id:label);
  return CircleAvatar(radius:radius,backgroundColor:Color(authorColor(id)).withValues(alpha:stale?0.45:1),foregroundColor:Colors.white,
    child:Text(letters,style:TextStyle(fontSize:letters.length>2?radius*0.58:radius*0.72,fontWeight:FontWeight.w700)));
}
