/// One-time callback URLs live only in a bounded in-memory set, never in logs
/// or persistence. Initial links and stream links share this same handler.
class AuthCallbackHandler {
  AuthCallbackHandler({
    required this.exchange,
    required this.onStart,
    required this.onError,
    this.capacity = 32,
  }) : assert(capacity > 0);
  final Future<void> Function(Uri) exchange;
  final void Function() onStart;
  final void Function() onError;
  final int capacity;
  final _seen = <Uri>{};
  Future<void> _queue = Future.value();
  bool received = false;
  Future<void> get settled => _queue;
  Future<void> receive(Uri uri) {
    if (uri.scheme != 'seaacademy-dev' ||
        uri.host != 'auth' ||
        uri.path != '/callback') {
      return Future.value();
    }
    if (_seen.contains(uri)) {
      return _queue;
    }
    if (_seen.length == capacity) {
      _seen.remove(_seen.first);
    }
    _seen.add(uri);
    received = true;
    onStart();
    _queue = _queue.then((_) async {
      try {
        await exchange(uri);
      } catch (_) {
        onError();
      }
    });
    return _queue;
  }
}
