import 'dart:async';

import 'package:headunit_shared/headunit_shared_io.dart';

/// Publishes declarative headunit pages and routes semantic actions back to
/// callbacks owned by the application process.
///
/// UI updates are control-plane RPC requests. The shell renders the resulting
/// [HeadunitUiPage] using its own Flutter widgets and theme.
class HeadunitUiController {
  final RpcConnection _rpc;
  final StreamController<String> _unhandledActions =
      StreamController<String>.broadcast(sync: true);
  late final StreamSubscription<RpcNotification> _notificationSubscription;
  Map<String, HeadunitUiActionCallback> _actions =
      <String, HeadunitUiActionCallback>{};
  Future<void> _updateQueue = Future<void>.value();
  bool _disposed = false;

  HeadunitUiController(this._rpc) {
    _notificationSubscription = _rpc.notifications.listen(
      _handleNotification,
      onDone: () {
        _disposed = true;
        _actions.clear();
        if (!_unhandledActions.isClosed) {
          unawaited(_unhandledActions.close());
        }
      },
    );
  }

  /// Action identifiers received from the headunit that had no local callback.
  Stream<String> get unhandledActions => _unhandledActions.stream;

  /// Publishes [page] and replaces the callbacks associated with its actions.
  ///
  /// Every action ID in a page must be unique. Callbacks are local functions;
  /// only their IDs and the page's declarative data are sent to the headunit.
  Future<void> showPage(
    HeadunitUiPage page, {
    Duration timeout = const Duration(seconds: 10),
  }) {
    return _enqueueUpdate(() async {
      _ensureActive();
      // Round-trip validation applies the same depth and schema checks on the
      // producer as the receiver, rather than relying on the host to reject it.
      HeadunitUiPage.fromJson(page.toJson());

      final Map<String, HeadunitUiActionCallback> nextActions =
          <String, HeadunitUiActionCallback>{};
      final Set<String> actionIds = <String>{};
      int actionCount = 0;
      for (final HeadunitUiAction action in page.actions) {
        actionCount++;
        if (!actionIds.add(action.id)) {
          throw ArgumentError.value(
            action.id,
            'page.actions',
            'Action identifiers must be unique within a page.',
          );
        }
        final HeadunitUiActionCallback? callback = action.onInvoke;
        if (callback != null) nextActions[action.id] = callback;
      }

      if (actionCount > 128) {
        throw ArgumentError(
          'A headunit page cannot register more than 128 actions.',
        );
      }
      // Keep old and new callbacks alive during the request. The host may
      // render the new page immediately before the request response arrives.
      final Map<String, HeadunitUiActionCallback> previousActions = _actions;
      _actions = <String, HeadunitUiActionCallback>{
        ...previousActions,
        ...nextActions,
      };
      try {
        await _rpc.request(
          'ui.showPage',
          parameters: <String, Object?>{'page': page.toJson()},
          timeout: timeout,
        );
        _actions = nextActions;
      } catch (_) {
        _actions = previousActions;
        rethrow;
      }
    });
  }

  /// Removes the application's currently published page from the shell.
  Future<void> clearPage({Duration timeout = const Duration(seconds: 10)}) {
    return _enqueueUpdate(() async {
      _ensureActive();
      await _rpc.request('ui.clearPage', timeout: timeout);
      _actions = <String, HeadunitUiActionCallback>{};
    });
  }

  Future<void> _enqueueUpdate(Future<void> Function() operation) {
    final Future<void> result = _updateQueue.then<void>((_) => operation());
    _updateQueue = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return result;
  }

  void _handleNotification(RpcNotification notification) {
    if (notification.method != 'ui.action') return;
    final Object? rawActionId = notification.parameters['actionId'];
    if (rawActionId is! String || rawActionId.isEmpty) return;
    final HeadunitUiActionCallback? callback = _actions[rawActionId];
    if (callback == null) {
      if (!_unhandledActions.isClosed) _unhandledActions.add(rawActionId);
      return;
    }
    unawaited(
      Future<void>.sync(callback)
          .catchError((Object error, StackTrace stackTrace) {
            Zone.current.handleUncaughtError(error, stackTrace);
          }),
    );
  }

  void _ensureActive() {
    if (_disposed || _rpc.isClosed) {
      throw StateError('Headunit UI connection is closed.');
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _actions.clear();
    await _notificationSubscription.cancel();
    if (!_unhandledActions.isClosed) await _unhandledActions.close();
  }
}
