/// Dictation into a text field (request of 26 Oct 2026): speech recognition
/// of the device (Android, iOS) or of the browser (Chrome, Edge). The text
/// is only written into the field, never sent by itself.
library;

/// Where dictation is offered: a phone, a tablet, the web app. The Windows
/// and Linux apps rely on the system dictation (Windows + H).
bool dictationOffered({required bool isWeb,required String targetPlatform})=>
  isWeb||targetPlatform=='android'||targetPlatform=='iOS'||targetPlatform=='macOS';

/// Text of the field while dictating: what was there before the microphone
/// was opened ([before], cursor at its end), then the recognised words.
String dictatedText(String before,String words){
  final w=words.trim();
  if(w.isEmpty)return before;
  if(before.isEmpty)return w[0].toUpperCase()+w.substring(1);
  return before.endsWith(' ')||before.endsWith('\n')?'$before$w':'$before $w';
}

/// Locale of the recognition, from the application language.
String dictationLocale(String lang)=>lang=='fr'?'fr_FR':'en_US';
