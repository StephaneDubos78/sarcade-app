/// Search bar of the map (request of 26 Oct 2026, « comme Google Maps »):
/// operators and APRS stations, reference sites, points and drawings of the
/// event, typed coordinates, and addresses through the server (Base Adresse
/// Nationale). Everything but the addresses works offline.
library;

import 'package:latlong2/latlong.dart';

import '../measure/coordinates.dart';

enum SearchKind { coordinates, operator, reference, poi, drawing, address }

class SearchResult {
  final SearchKind kind; final String title, subtitle; final LatLng point;
  const SearchResult(this.kind,this.title,this.subtitle,this.point);
}

/// Lower case without accents, for « Chatron » = « châtron ».
String fold(String s){
  const from='àâäáãåçéèêëíìîïñóòôöõúùûüýÿœæ', to='aaaaaaceeeeiiiinooooouuuuyyoa';
  final b=StringBuffer();
  for(final ch in s.toLowerCase().split('')){final i=from.indexOf(ch);b.write(i<0?ch:to[i]);}
  return b.toString();
}

/// Every word of the query is in the text (any order).
bool matchesQuery(String query,String text){
  final words=fold(query).split(RegExp(r'\s+')).where((w)=>w.isNotEmpty);
  final t=fold(text);
  return words.isNotEmpty&&words.every(t.contains);
}

/// One searchable item of the device: shown title, details, position.
class Searchable {
  final SearchKind kind; final String title, details; final LatLng point;
  const Searchable(this.kind,this.title,this.details,this.point);
}

/// Local results, coordinates first, then by kind, at most [limit].
List<SearchResult> searchLocal(String query,Iterable<Searchable> items,{int limit=20}){
  final q=query.trim();
  if(q.length<2)return const [];
  final out=<SearchResult>[];
  final coords=parseCoordinates(q);
  if(coords!=null)out.add(SearchResult(SearchKind.coordinates,q,'',coords));
  final hits=[for(final i in items)if(matchesQuery(q,'${i.title} ${i.details}'))i]
    ..sort((a,b){final k=a.kind.index.compareTo(b.kind.index);return k!=0?k:a.title.compareTo(b.title);});
  for(final i in hits){
    if(out.length>=limit)break;
    out.add(SearchResult(i.kind,i.title,i.details,i.point));
  }
  return out;
}

/// Address results of the server (`/geocode`).
List<SearchResult> addressResults(Map<String,dynamic> json){
  final list=json['results'];
  if(list is! List)return const [];
  return [for(final r in list)if(r is Map&&r['lat'] is num&&r['lon'] is num)
    SearchResult(SearchKind.address,'${r['label']??''}',[r['postcode'],r['city']].where((x)=>'${x??''}'.isNotEmpty).join(' '),
      LatLng((r['lat'] as num).toDouble(),(r['lon'] as num).toDouble()))];
}
