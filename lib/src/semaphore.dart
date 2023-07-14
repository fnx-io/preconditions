import 'dart:async';
import 'dart:collection';

/// Global semaphore is a named semaphore with max count of permits equals to 1.
class GlobalSemaphore extends Semaphore {
  static final Map<String, GlobalSemaphore> _semaphores =
      <String, GlobalSemaphore>{};

  factory GlobalSemaphore(String name) {
    var semaphore = _semaphores[name];
    if (semaphore == null) {
      semaphore = GlobalSemaphore._internal(name);
      _semaphores[name] = semaphore;
    }

    return semaphore;
  }

  GlobalSemaphore._internal(String? name) : super._internal(1, name);
}

/// Local semaphore is a unnamed semaphore with a specified count of max
/// permits.
class LocalSemaphore extends Semaphore {
  LocalSemaphore(int maxCount) : super._internal(maxCount);
}

abstract class Semaphore {
  final int maxCount;

  final String? name;

  int _currentCount = 0;

  final Queue<Completer> _waitQueue = Queue<Completer>();

  bool get isFree => _currentCount + 1 <= maxCount;

  Semaphore._internal(this.maxCount, [this.name]) {
    if (maxCount < 1) {
      throw RangeError.value(maxCount, 'maxCount');
    }
  }

  /// Acquires a permit from this semaphore, asyncronously blocking until one is
  /// available.
  Future acquire() {
    var completer = Completer();
    if (isFree) {
      _currentCount++;
      completer.complete();
    } else {
      _waitQueue.add(completer);
    }

    return completer.future;
  }

  /// Releases a permit, returning it to the semaphore.
  void release() {
    if (_currentCount == 0) {
      throw StateError('Unable to release semaphore');
    }

    _currentCount--;
    if (_waitQueue.isNotEmpty) {
      _currentCount++;
      final completer = _waitQueue.removeFirst();
      completer.complete();
    }
  }
}
