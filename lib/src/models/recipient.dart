class SarcadeRecipient {
 final String id,label,type;
 const SarcadeRecipient({required this.id,required this.label,required this.type});
 String get protocolId=>'$type:$id';
}
