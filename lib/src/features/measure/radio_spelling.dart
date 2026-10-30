/// « Lecture radio » (lot 5, 30 Oct 2026): a value spelt for the radio,
/// digits in words and letters in the NATO alphabet, « 31U DQ » →
/// « trois un Uniform — Delta Québec ». Pure code.
library;

const _natoFr=['Alfa','Bravo','Charlie','Delta','Echo','Fox-trot','Golf','Hotel','India','Juliett','Kilo','Lima','Mike',
  'November','Oscar','Papa','Québec','Romeo','Sierra','Tango','Uniform','Victor','Whisky','X-ray','Yankee','Zoulou'];
const _natoEn=['Alfa','Bravo','Charlie','Delta','Echo','Foxtrot','Golf','Hotel','India','Juliett','Kilo','Lima','Mike',
  'November','Oscar','Papa','Quebec','Romeo','Sierra','Tango','Uniform','Victor','Whiskey','X-ray','Yankee','Zulu'];
const _digitsFr=['zéro','un','deux','trois','quatre','cinq','six','sept','huit','neuf'];
const _digitsEn=['zero','one','two','three','four','five','six','seven','eight','niner'];

/// Words of [text], groups separated by « — ».
String radioSpelling(String text,{String lang='fr'}){
  final fr=lang=='fr';
  final groups=<String>[]; var words=<String>[];
  void flush(){if(words.isNotEmpty){groups.add(words.join(' '));words=<String>[];}}
  for(final ch in text.toUpperCase().split('')){
    final c=ch.codeUnitAt(0);
    if(c>=48&&c<=57){words.add((fr?_digitsFr:_digitsEn)[c-48]);}
    else if(c>=65&&c<=90){words.add((fr?_natoFr:_natoEn)[c-65]);}
    else{
      final w=switch(ch){
        ','=>fr?'virgule':'decimal','.'=>fr?'point':'decimal','°'=>fr?'degrés':'degrees',
        '′'||"'"=>'minutes','″'||'"'=>fr?'secondes':'seconds','-'=>fr?'moins':'minus',_=>null};
      if(w!=null)words.add(w);
      // A space, « · » or « / » cuts a group; the narrow space inside a
      // number (« 6 856 031 ») and the units do not.
      if(ch==' '||ch=='·'||ch=='/')flush();
    }
  }
  flush();
  return groups.join(' — ');
}
