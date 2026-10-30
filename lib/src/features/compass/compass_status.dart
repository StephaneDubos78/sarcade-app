import 'package:flutter/material.dart';

import '../../l10n/strings.dart';

/// Accuracy of the compass under the azimuth of a bearing (card « Boussole
/// instable »): « Boussole ±10° », or an invitation to calibrate (figure of
/// 8) when the system says it is low; « Moyenne sur 2 s… » while saving.
class CompassStatus extends StatelessWidget {
  final double? accuracyDeg; final bool calibrate, averaging;
  const CompassStatus({super.key,this.accuracyDeg,this.calibrate=false,this.averaging=false});
  @override Widget build(BuildContext context){
    final s=Theme.of(context).colorScheme;
    if(averaging){
      return Row(mainAxisSize:MainAxisSize.min,children:[
        const SizedBox(width:14,height:14,child:CircularProgressIndicator(strokeWidth:2)),const SizedBox(width:8),
        Flexible(child:Text(S.t('compass.averaging'),style:TextStyle(fontSize:12,color:s.primary,fontWeight:FontWeight.w600)))]);
    }
    if(calibrate){
      return Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:4),
        decoration:BoxDecoration(color:const Color(0xFFFFF4E5),borderRadius:BorderRadius.circular(8),border:Border.all(color:const Color(0xFFE8710A))),
        child:Row(mainAxisSize:MainAxisSize.min,children:[
          const Icon(Icons.all_inclusive,size:16,color:Color(0xFFB45309)),const SizedBox(width:6),
          Flexible(child:Text(S.t('compass.calibrate'),style:const TextStyle(fontSize:12,color:Color(0xFF7A3E00),fontWeight:FontWeight.w600)))]));
    }
    final a=accuracyDeg; if(a==null)return const SizedBox.shrink();
    return Text(S.t('compass.accuracy',{'v':a.toStringAsFixed(0)}),style:TextStyle(fontSize:12,color:s.onSurfaceVariant));
  }
}
