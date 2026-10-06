import 'dart:async';

/// One cancellation scope per run; closes live clients and interrupts waits.
class TaskCancel {
  final _signal = Completer<void>();
  final _callbacks = <void Function()>{};
  bool get cancelled => _signal.isCompleted;
  Future<void> get signal => _signal.future;
  void check() {
    if (cancelled) throw const TaskCancelled();
  }

  void Function() register(void Function() callback) {
    if (cancelled) {
      callback();
    } else {
      _callbacks.add(callback);
    }
    return () => _callbacks.remove(callback);
  }

  void cancel() {
    if (cancelled) return;
    _signal.complete();
    for (final callback in List.of(_callbacks)) {
      callback();
    }
    _callbacks.clear();
  }

  Future<T> wait<T>(Future<T> future) async {
    check();
    return Future.any([
      future,
      signal.then<T>((_) => throw const TaskCancelled()),
    ]);
  }

  Future<void> delay(Duration duration) async {
    check();
    final done = Completer<void>();
    final timer = Timer(duration, done.complete);
    final unregister = register(() {
      timer.cancel();
      if (!done.isCompleted) done.completeError(const TaskCancelled());
    });
    try {
      await done.future;
    } finally {
      timer.cancel();
      unregister();
    }
  }
}

class TaskCancelled implements Exception {
  const TaskCancelled();
  @override
  String toString() => '任务已取消';
}
