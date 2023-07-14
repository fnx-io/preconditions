// Copyright (c) 2021, fnx.io
// https://pub.dev/packages/preconditions
// All rights reserved.

part of preconditions;

/// Implement your precondition verification in form of this function type.  Return either:
/// [PreconditionStatus.satisfied()]
/// or
/// [PreconditionStatus.Failed()]
/// as a result of your test.
///
typedef FutureOr<PreconditionStatus> PreconditionFunction();

typedef FutureOr InitPreconditionFunction();

/// Unique identificator of precondition.
class PreconditionId {
  final dynamic _value;

  PreconditionId(this._value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is PreconditionId && runtimeType == other.runtimeType && _value == other._value;

  @override
  int get hashCode => _value.hashCode;

  @override
  String toString() {
    return _value.toString();
  }

  dynamic get value => _value;
}

/// [PreconditionsRepository] creates this object from [PreconditionFunction] which you register in
/// [PreconditionsRepository.registerPrecondition()]. Think of it as a handle
/// to your precondition. It is a mutable ChangeNotifier, but is modified only through
/// methods of [PreconditionsRepository] and from your point of view is read-only. It's possible
/// to integrate it with your state management tool, for example:
///
///     Precondition pHandle = repository.registerPrecondition( ... );
///     // ...
///     AnimatedBuilder(
///         animation: pHandle,
///         builder: (context, _) => pHandle.build(context),
///     );
///
///
class Precondition extends ChangeNotifier {
  var _currentStatus = PreconditionStatus._unknown();

  /// For how long should we cache positive test results.
  /// Might be usefull in cases when the test itself is expensive,
  /// positive results don't spontaneously change that often etc.
  final Duration staySatisfiedCacheDuration;

  /// For how long should we cache negative (failed and error) test results.
  /// Might be usefull in cases when the test itself is expensive,
  /// failed results don't spontaneously change that often etc.
  final Duration stayFailedCacheDuration;

  /// Specify a timeout for your [PreconditionFunction]. After this period test is
  /// evaluated as "failed". Default value is 10 seconds. Because all test are executed simultaneously,
  /// we can say that "evaluation" method in [PreconditionsRepository] will run for maximum duration
  /// equal to maximum timeout among all executed tests.
  final Duration resolveTimeout;

  /// Implementation of precondition test you supplied.
  final PreconditionFunction _preconditionFunction;

  final InitPreconditionFunction? initFunction;

  /// Identification of this precondition. Supply your own or it will be assigned by the repository.
  final PreconditionId id;

  final Iterable<_Dependency> _dependsOn;

  final PreconditionsRepository _parent;

  final String? description;

  /// Convenient discriminator.
  bool get isFailed => status.isFailed;

  /// Convenient discriminator.
  bool get isUnknown => status.isUnknown;

  /// Convenient discriminator.
  bool get isSatisfied => status.isSatisfied;

  /// Is running right now.
  bool get isRunning => _workingOn != null;

  /// Convenient discriminator. Please note, that it's not the same as 'isFailed'.
  bool get isNotSatisfied => status.isNotSatisfied;

  DateTime? _lastEvaluation;

  /// Last evaluation run was finished at ...
  DateTime? get lastEvaluation => _lastEvaluation;

  Future<PreconditionStatus>? _workingOn;

  /// Current (equals last) result of evaluation, which happened at [lastEvaluation].
  PreconditionStatus get status => _currentStatus;

  bool _wasInitialized = false;

  bool get needsInitialization => initFunction != null && _wasInitialized != true;

  Precondition._(this.id, this._preconditionFunction, this._dependsOn, this._parent,
      {this.description,
      this.resolveTimeout = const Duration(seconds: 10),
      this.initFunction,
      this.staySatisfiedCacheDuration = Duration.zero,
      this.stayFailedCacheDuration = Duration.zero});

  Future<PreconditionStatus> _evaluate(_Runner context, {bool ignoreCache = false}) async {
    _log.info("Running evaluate $this");
    if (context._results.containsKey(id)) {
      // this is already resolved
      return status;
    }
    if (_workingOn != null) {
      try {
        _log.info("Returing existing 'workingOn'");
        return await _workingOn!;
      } catch (e) {} // this is processed in _evaluateImpl
    }
    try {
      _workingOn = _evaluateImpl(context, ignoreCache: ignoreCache);
      var _result = await _workingOn!;
      return _result;
    } finally {
      _workingOn = null;
    }
  }

  Future<PreconditionStatus>? _evaluateImpl(_Runner context, {bool ignoreCache = false}) async {
    var beforeRunStatus = status;
    if (context._results.containsKey(id)) {
      // this is already resolved
      return status;
    }
    if (!ignoreCache && !status.isUnknown) {
      // we need to evaluate possible cached value
      if (_currentStatus.isSatisfied &&
          staySatisfiedCacheDuration.inMicroseconds > 0 &&
          _lastEvaluation != null &&
          _lastEvaluation!.add(staySatisfiedCacheDuration).isAfter(DateTime.now())) return _currentStatus;

      if (_currentStatus.isFailed &&
          stayFailedCacheDuration.inMicroseconds > 0 &&
          _lastEvaluation != null &&
          _lastEvaluation!.add(stayFailedCacheDuration).isAfter(DateTime.now())) return _currentStatus;
    }

    if (_dependsOn.where(_evaluationNeeded).isNotEmpty) {
      // resolve all dependencies first:

      await context.runAll(_dependsOn.map((e) => e._target), ignoreCache);

      for (var d in _dependsOn) {
        if (d._target.isSatisfied) d._wasSatisfied = true;
      }
    }

    try {
      var _unsatisfied = _dependsOn.where(_evaluationNeeded).where((d) => d._target.status.isNotSatisfied);
      if (_unsatisfied.isNotEmpty) {
        _log.info("$this - not evaluating, some dependencies are not satisfied (${_unsatisfied.first})");
        _currentStatus = _unsatisfied.first._target.status;
      } else {
        if (needsInitialization) {
          _log.info("$this - initializing");
          await initFunction!();
          _wasInitialized = true;
        }

        _log.info("$this - evaluating (ignoreCache=$ignoreCache)");

        var _run = _preconditionFunction();
        if (_run is Future<PreconditionStatus>) {
          _workingOn = _run.timeout(resolveTimeout);
          _currentStatus = await _workingOn!;
        } else {
          _currentStatus = _run;
        }
      }
      context._addResult(this);

      // change in status
      if (beforeRunStatus != status && status.isFailed) {
        // These depend on me (we don't trigger unresolved dependencies)
        var _allPreconditions = _parent._known.values;
        var _dependants =
            _allPreconditions.where((p) => p._dependsOn.any((d) => d._instantPropagationFromTarget == true && d._targetId == id));
        for (var _dependant in _dependants) {
          _log.info("$this - propagating failure to tightly dependant $_dependant");
          _dependant._currentStatus = status;
          _dependant.notifyListeners();
        }
      }
    } on TimeoutException catch (e, stack) {
      _log.warning("$this - timed out after $resolveTimeout");
      _currentStatus = PreconditionStatus._crash(e, stack);
    } catch (e, stack) {
      _log.warning("$this - failed with '$e'", stack);
      _currentStatus = PreconditionStatus._crash(e, stack);
    } finally {
      _lastEvaluation = DateTime.now();
      _workingOn = null;
    }
    notifyListeners();
    _log.info("$this - evaluation finished");
    return _currentStatus;
  }

  @override
  bool operator ==(Object other) => identical(this, other) || other is Precondition && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'Precondition{#$id, status=$_currentStatus, isRunning=$isRunning, lastEvaluation=$lastEvaluation}';
  }

  String toStringDebug() {
    return 'Precondition:$id, posCache=${_printDuration(staySatisfiedCacheDuration)}, negCache=${_printDuration(stayFailedCacheDuration)}, timeout=${_printDuration(resolveTimeout)}';
  }

  static String _printDuration(Duration? d) {
    if (d == null) return "none";
    if (d == forEver) return "∞";
    if (d.inMinutes > 120) return "${d.inHours}h";
    if (d.inSeconds > 120) return "${d.inMinutes}m";
    return "${d.inSeconds}s";
  }

  static bool _evaluationNeeded(_Dependency e) {
    if (e._onceOnly && e._wasSatisfied) return false;
    return true;
  }
}
