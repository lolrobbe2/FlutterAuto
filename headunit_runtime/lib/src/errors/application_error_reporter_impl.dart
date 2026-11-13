import 'dart:async';

import 'package:headunit_shared/headunit_shared_io.dart';

class ApplicationErrorReporterImpl implements ApplicationErrorReporter {
  final StreamController<ApplicationError> _controller;
  final List<ApplicationError> _recentErrors = <ApplicationError>[];
  final int _maxHistorySize;

  bool _isDisposed = false;

  ApplicationErrorReporterImpl({int maxHistorySize = 100})
    : assert(maxHistorySize > 0),
      _maxHistorySize = maxHistorySize,
      _controller = StreamController<ApplicationError>.broadcast(sync: true);

  @override
  Stream<ApplicationError> get errors => _controller.stream;

  @override
  List<ApplicationError> get recentErrors =>
      List<ApplicationError>.unmodifiable(_recentErrors);

  @override
  void report(ApplicationError error) {
    if (_isDisposed) {
      throw StateError(
        'Cannot report an error after the error reporter has been disposed.',
      );
    }

    _recentErrors.add(error);

    if (_recentErrors.length > _maxHistorySize) {
      _recentErrors.removeAt(0);
    }

    _controller.add(error);
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }

    _isDisposed = true;
    await _controller.close();
  }
}
