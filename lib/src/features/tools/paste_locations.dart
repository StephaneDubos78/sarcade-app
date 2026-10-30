/// « Coller » of the converter (card « Convertisseur, zone « Coller » texte
/// ou image », validated 30 Oct 2026, 16 h 34), text part: every position
/// found in a pasted text — decimal degrees, DMS, DM, UTM, MGRS, Lambert 93,
/// DFCI, links of Google Maps / Apple Plans / OpenStreetMap / Waze, `geo:` —
/// each with its excerpt; the address search comes last, by the page. The
/// image part (OCR, EXIF) was cancelled by the porteur (30 Oct 2026, 18 h 32).
library;

import 'package:latlong2/latlong.dart';

import '../measure/coordinates.dart';

typedef FoundLocation=({LatLng point,String excerpt,String format});

bool _valid(double lat,double lon)=>lat.abs()<=90&&lon.abs()<=180&&!(lat==0&&lon==0);

final _num=r'(-?\d{1,3}\.\d+)';
final _links=<RegExp>[
  RegExp('geo:$_num,$_num',caseSensitive:false),
  RegExp('@$_num,$_num'),
  RegExp('[?&#](?:q|query|ll|sll|daddr|destination|center|to)=(?:loc:)?$_num(?:,|%2C)\\s*$_num',caseSensitive:false),
  RegExp('mlat=$_num&(?:amp;)?mlon=$_num',caseSensitive:false),
  RegExp('#map=\\d+(?:\\.\\d+)?/$_num/$_num',caseSensitive:false),
  RegExp('!3d$_num!4d$_num'),
];

final _url=RegExp(r'(?:https?://|geo:)\S+',caseSensitive:false);
final _ddPair=RegExp(r'([NS]\s*)?(-?\d{1,2}[.,]\d{3,})\s*°?\s*([NS])?\s*[,;/]?\s+([EOW]\s*)?(-?\d{1,3}[.,]\d{3,})\s*°?\s*([EOW])?',caseSensitive:false);
final _dms=RegExp(r'''\d{1,2}\s*°\s*\d{1,2}\s*['′]\s*(?:\d{1,2}(?:[.,]\d+)?\s*["″]?)?\s*[NS][\s,;/]*\d{1,3}\s*°\s*\d{1,2}\s*['′]\s*(?:\d{1,2}(?:[.,]\d+)?\s*["″]?)?\s*[EOW]''',caseSensitive:false);

String _shorten(String s)=>s.length<=80?s:'${s.substring(0,77)}…';

/// Every position of [text], without duplicates: links first, then whole
/// lines, then positions inside sentences.
List<FoundLocation> findLocations(String text){
  final out=<FoundLocation>[]; final seen=<String>{};
  void add(LatLng p,String excerpt,String format){
    if(!_valid(p.latitude,p.longitude))return;
    final k='${p.latitude.toStringAsFixed(5)},${p.longitude.toStringAsFixed(5)}';
    if(seen.add(k))out.add((point:p,excerpt:_shorten(excerpt.trim()),format:format));
  }
  // 1) Links and geo: URIs.
  for(final u in _url.allMatches(text)){
    final link=Uri.decodeFull(u.group(0)!);
    for(final r in _links){
      final m=r.firstMatch(link);
      if(m!=null){add(LatLng(double.parse(m.group(1)!),double.parse(m.group(2)!)),u.group(0)!,'link');break;}
    }
  }
  final rest=text.replaceAll(_url,' ');
  // 2) Whole lines in a known format (UTM, MGRS, Lambert 93, DFCI, DD, DMS…).
  for(final line in rest.split(RegExp(r'[\r\n]+'))){
    final l=line.trim();
    if(l.isEmpty||l.length>60)continue;
    final f=detectFormat(l);
    // A QTH locator only when it is the whole line (« JN18 » in a sentence is a word).
    if(f==null||(f==CoordFormat.qth&&l.contains(' ')))continue;
    final p=parseCoordinates(l);
    if(p!=null)add(p,l,f.name);
  }
  // 3) Positions inside sentences.
  for(final m in _dms.allMatches(rest)){
    final p=parseCoordinates(m.group(0)!);
    if(p!=null)add(p,m.group(0)!,CoordFormat.dms.name);
  }
  for(final m in _ddPair.allMatches(rest)){
    final p=parseCoordinates(m.group(0)!);
    if(p!=null)add(p,m.group(0)!,CoordFormat.dd.name);
  }
  return out;
}
