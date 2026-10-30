/// Échap closes the window or the panel opened last (card « Ordinateur (web
/// et Windows), Échap ferme la fenêtre ou le panneau ouvert », 30 Oct 2026,
/// 10 h 35). Windows and bottom sheets are routes and close by themselves
/// (DismissIntent); the side panels beside the map are followed here: the
/// set of panels open is given at every build, the order of opening is
/// kept, and [top] is the one to close. Nothing open: nothing to do.
library;

class EscapeStack {
  final List<String> _order=[];

  /// Panels open now (any order): newly opened ones go on top, closed ones leave.
  void sync(Iterable<String> open){
    final now=open.toSet();
    _order.removeWhere((k)=>!now.contains(k));
    for(final k in now){if(!_order.contains(k))_order.add(k);}
  }

  /// Panel opened last, null when none is open.
  String? get top=>_order.isEmpty?null:_order.last;

  /// Order of opening, the oldest first.
  List<String> get order=>List.unmodifiable(_order);

  /// Échap: closes the panel on top with [close]; false when nothing is open.
  bool escape(void Function(String panel) close){
    final t=top; if(t==null)return false;
    close(t); _order.remove(t); return true;
  }
}
