import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../l10n/strings.dart';
import 'tv_code.dart';

/// Camera view that returns the pairing code of the first QR code of a
/// SARCADE TV it sees (Android, iPhone).
class TvQrScanPage extends StatefulWidget {
  const TvQrScanPage({super.key});
  @override State<TvQrScanPage> createState()=>_TvQrScanPageState();
}

class _TvQrScanPageState extends State<TvQrScanPage> {
  bool _done=false;

  void _onDetect(BarcodeCapture capture){
    if(_done)return;
    for(final b in capture.barcodes){
      final code=tvCodeFrom(b.rawValue??'');
      if(code!=null){_done=true;Navigator.pop(context,code);return;}
    }
  }

  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(S.t('tv.scan'))),
    body:Stack(fit:StackFit.expand,children:[
      MobileScanner(onDetect:_onDetect),
      Align(alignment:Alignment.bottomCenter,child:SafeArea(child:Container(
        margin:const EdgeInsets.all(16),padding:const EdgeInsets.symmetric(horizontal:16,vertical:10),
        decoration:BoxDecoration(color:Colors.black54,borderRadius:BorderRadius.circular(12)),
        child:Text(S.t('tv.scanHelp'),style:const TextStyle(color:Colors.white,fontSize:16),textAlign:TextAlign.center)))),
    ]));
}
