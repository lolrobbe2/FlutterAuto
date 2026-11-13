import 'dart:async';

import 'package:headunit_shared/headunit_shared_io.dart';

/// Host-side UI control channel for one authenticated external application.
///
/// It accepts versioned declarative pages and sends action invocations. The
/// channel intentionally knows nothing about Flutter widgets or rendering.
class RemoteApplicationUiChannel {
  final StreamController<HeadunitUiPage?> _pages =
      StreamController<HeadunitUiPage?>.broadcast(sync: true);
  RpcConnection? _connection;
  HeadunitUiPage? _currentPage;
  bool _disposed = false;

  Stream<HeadunitUiPage?> get pages => _pages.stream;
  HeadunitUiPage? get currentPage => _currentPage;

  void attach(
    RpcConnection connection, {
    required bool Function() isAuthenticated,
  }) {
    if (_disposed) throw StateError('The remote UI channel is disposed.');
    _connection = connection;

    connection.registerRequestHandler('ui.showPage', (
      Map<String, Object?> parameters,
    ) {
      _ensureAuthenticated(isAuthenticated);
      late final HeadunitUiPage page;
      try {
        page = HeadunitUiPage.fromJson(parameters['page']);
        _validateUniqueActions(page);
      } on FormatException catch (error) {
        throw RpcException(
          -32602,
          'Invalid headunit UI page: ${error.message}',
        );
      } on ArgumentError catch (error) {
        throw RpcException(-32602, 'Invalid headunit UI page: $error');
      }
      _currentPage = page;
      _pages.add(page);
      return <String, Object?>{'accepted': true};
    });

    connection.registerRequestHandler('ui.clearPage', (
      Map<String, Object?> parameters,
    ) {
      _ensureAuthenticated(isAuthenticated);
      _currentPage = null;
      _pages.add(null);
      return <String, Object?>{'accepted': true};
    });

    unawaited(
      connection.done.whenComplete(() {
        if (identical(_connection, connection)) {
          _connection = null;
          _currentPage = null;
          if (!_pages.isClosed) _pages.add(null);
        }
      }),
    );
  }

  void sendAction(String actionId) {
    if (_disposed) return;
    final RpcConnection? connection = _connection;
    if (connection == null || connection.isClosed) return;
    final HeadunitUiPage? page = _currentPage;
    if (page == null ||
        !page.actions.any((HeadunitUiAction action) => action.id == actionId)) {
      throw ArgumentError.value(
        actionId,
        'actionId',
        'The action is not in the current page.',
      );
    }
    connection.notify(
      'ui.action',
      parameters: <String, Object?>{'actionId': actionId},
    );
  }

  void _ensureAuthenticated(bool Function() isAuthenticated) {
    if (_disposed || !isAuthenticated()) {
      throw const RpcException(
        -32001,
        'Application UI requires an authenticated session.',
      );
    }
  }

  void _validateUniqueActions(HeadunitUiPage page) {
    final Set<String> ids = <String>{};
    int actionCount = 0;
    for (final HeadunitUiAction action in page.actions) {
      actionCount++;
      if (actionCount > 128) {
        throw const RpcException(
          -32602,
          'A headunit page cannot declare more than 128 actions.',
        );
      }
      if (!ids.add(action.id)) {
        throw RpcException(
          -32602,
          'Duplicate UI action identifier: ${action.id}.',
        );
      }
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _connection = null;
    _currentPage = null;
    if (!_pages.isClosed) {
      _pages.add(null);
      await _pages.close();
    }
  }
}
