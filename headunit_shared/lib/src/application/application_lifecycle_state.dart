enum ApplicationLifecycleState {
  stopped,
  starting,
  foreground,
  background,
  suspended,
  stopping,
  failed,
}

extension ApplicationLifecycleStateTransitions on ApplicationLifecycleState {
  bool canTransitionTo(ApplicationLifecycleState next) {
    switch (this) {
      case ApplicationLifecycleState.stopped:
        return next == ApplicationLifecycleState.starting;

      case ApplicationLifecycleState.starting:
        return next == ApplicationLifecycleState.foreground ||
            next == ApplicationLifecycleState.background ||
            next == ApplicationLifecycleState.stopping ||
            next == ApplicationLifecycleState.failed;

      case ApplicationLifecycleState.foreground:
        return next == ApplicationLifecycleState.background ||
            next == ApplicationLifecycleState.stopping ||
            next == ApplicationLifecycleState.failed;

      case ApplicationLifecycleState.background:
        return next == ApplicationLifecycleState.foreground ||
            next == ApplicationLifecycleState.suspended ||
            next == ApplicationLifecycleState.stopping ||
            next == ApplicationLifecycleState.failed;

      case ApplicationLifecycleState.suspended:
        return next == ApplicationLifecycleState.background ||
            next == ApplicationLifecycleState.stopping ||
            next == ApplicationLifecycleState.failed;

      case ApplicationLifecycleState.stopping:
        return next == ApplicationLifecycleState.stopped ||
            next == ApplicationLifecycleState.failed;

      case ApplicationLifecycleState.failed:
        return next == ApplicationLifecycleState.stopped ||
            next == ApplicationLifecycleState.starting;
    }
  }
}
