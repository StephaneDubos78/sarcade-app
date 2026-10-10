/// Switch of the applications to HTTPS (server note « Mises à jour et
/// sécurité », HTTPS section, 10 Oct 2026): the server announces its HTTPS
/// address; an application still connected over plain HTTP tries it and
/// keeps it when it answers. Pure code.
library;

/// HTTPS address to try, or null: only from plain HTTP to a valid HTTPS
/// address different from the current one.
String? httpsTarget(String current,String? announced){
  if(announced==null)return null;
  final a=Uri.tryParse(announced.trim()), c=Uri.tryParse(current.trim());
  if(a==null||c==null||a.scheme!='https'||a.host.isEmpty||c.scheme!='http')return null;
  var url=announced.trim();
  while(url.endsWith('/')){url=url.substring(0,url.length-1);}
  return url==current?null:url;
}
