import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../l10n/strings.dart';
import 'dictation.dart';

/// Microphone next to a text field: tap to dictate, tap again to stop.
/// Windows and Linux: a tap explains the system dictation (Windows + H).
class DictationButton extends StatefulWidget {
  final TextEditingController controller;
  /// Called after each recognised piece (the search runs again).
  final VoidCallback? onChanged;
  const DictationButton({super.key,required this.controller,this.onChanged});
  @override State<DictationButton> createState()=>_DictationButtonState();
}

class _DictationButtonState extends State<DictationButton> {
  static final SpeechToText _speech=SpeechToText();
  static bool? _available;
  bool _listening=false;
  String _before='';

  bool get _offered=>dictationOffered(isWeb:kIsWeb,targetPlatform:defaultTargetPlatform.name);

  void _snack(String t){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(t)));}

  Future<void> _toggle() async {
    if(!_offered){_snack(S.t('dictation.windows'));return;}
    if(_listening){await _speech.stop();if(mounted)setState(()=>_listening=false);return;}
    try{
      _available??=await _speech.initialize(
        onStatus:(s){if((s=='done'||s=='notListening')&&mounted)setState(()=>_listening=false);},
        onError:(_){if(mounted)setState(()=>_listening=false);});
    }catch(_){_available=false;}
    if(_available!=true){_snack(S.t('dictation.unavailable'));return;}
    final c=widget.controller;
    _before=c.text;
    setState(()=>_listening=true);
    await _speech.listen(
      localeId:dictationLocale(S.lang),
      listenOptions:SpeechListenOptions(partialResults:true,cancelOnError:true),
      onResult:(r){
        final text=dictatedText(_before,r.recognizedWords);
        c.value=TextEditingValue(text:text,selection:TextSelection.collapsed(offset:text.length));
        widget.onChanged?.call();
        if(r.finalResult&&mounted)setState(()=>_listening=false);
      },
    );
  }

  @override void dispose(){if(_listening){_speech.stop();}super.dispose();}

  @override
  Widget build(BuildContext context)=>IconButton(
    tooltip:_listening?S.t('dictation.stop'):S.t('dictation.start'),
    onPressed:_toggle,
    color:_listening?Colors.red:null,
    icon:Icon(_listening?Icons.mic:Icons.mic_none),
  );
}
