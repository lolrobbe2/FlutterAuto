import 'application_error.dart';

abstract interface class ApplicationErrorReporter {
  Stream<ApplicationError> get errors;

  List<ApplicationError> get recentErrors;

  void report(ApplicationError error);

  Future<void> dispose();
}
