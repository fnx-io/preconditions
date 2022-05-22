// Copyright (c) 2021, fnx.io
// https://pub.dev/packages/preconditions
// All rights reserved.

part of preconditions;

Logger _log = Logger("Precondition");

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
  final Duration satisfiedCache;

  /// For how long should we cache negative (failed and error) test results.
  /// Might be usefull in cases when the test itself is expensive,
  /// failed results don't spontaneously change that often etc.
  final Duration notSatisfiedCache;

  /// Specify a timeout for your [PreconditionFunction]. After this period test is
  /// evaluated as "failed". Default value is 10 seconds. Because all test are executed simultaneously,
  /// we can say that "evaluation" method in [PreconditionsRepository] will run for maximum duration
  /// equal to maximum timeout among all executed tests.
  final Duration resolveTimeout;

  /// Implementation of precondition test you supplied.
  final PreconditionFunction preconditionFunction;

  /// Widget builder of this precondition.
  final StatusBuilder statusBuilder;

  /// Identification of this precondition. Supply your own or it will be assigned by the repository.
  final PreconditionId id;

  final Iterable<Dependency> dependsOn;

  final PreconditionsRepository _parent;

  final String? description;

  /// Convenient discriminator.
  bool get isFailed => status.isFailed;

  /// Convenient discriminator.
  bool get isError => status.isError;

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

  Precondition._(this.id, this.preconditionFunction, this.statusBuilder, this.dependsOn, this._parent,
      {this.description,
        this.resolveTimeout: const Duration(seconds: 10),
        this.satisfiedCache: Duration.zero,
        this.notSatisfiedCache: Duration.zero});

  /// Builds a widget with status description. Uses [statusBuilder] supplied in [PreconditionsRepository.registerPrecondition].
  Widget build(BuildContext context) => statusBuilder(context, status);

  Future<PreconditionStatus> _evaluate(_Runner context, {bool ignoreCache: false}) async {
    _log.info("Running evaluate ${this}");
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

  Future<PreconditionStatus>? _evaluateImpl(_Runner context, {bool ignoreCache: false}) async {
    var beforeRunStatus = status;
    if (context._results.containsKey(id)) {
      // this is already resolved
      return status;
    }
    if (!ignoreCache && !status.isUnknown) {
      // we need to evaluate possible cached value
      if (_currentStatus.isSatisfied
          && satisfiedCache.inMicroseconds > 0 &&
          _lastEvaluation!.add(satisfiedCache).isAfter(DateTime.now())) return _currentStatus;
      if ((_currentStatus.isFailed || _currentStatus.isError)
          && notSatisfiedCache.inMicroseconds > 0 &&
          _lastEvaluation!.add(notSatisfiedCache).isAfter(DateTime.now())) return _currentStatus;
    }
    if (dependsOn.isNotEmpty) {
      // resolve all dependencies first:
      await context.runAll(dependsOn.map((e) => context._repository._getById(e._targetId)));
    }

    try {
      var unsatisfied = dependsOn.map((d) => context._repository._getById(d._targetId)).where((d)=>d.status.isNotSatisfied);
      if (unsatisfied.isNotEmpty) {
        _log.info("$this - not evaluating, some dependencies are not satisfied (${unsatisfied.first})");
        _currentStatus = unsatisfied.first.status;
      } else {
        _log.info("$this - evaluating (ignoreCache=$ignoreCache)");
        var _run = preconditionFunction();
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
        var _dependants = _allPreconditions.where((p) => p.dependsOn.any((d) => d._instantPropagationFromTarget == true && d._targetId == id));
        for (var _dependant in _dependants) {
          _log.info("$this - propagating failure to tightly dependant $_dependant");
          _dependant._currentStatus = status;
          _dependant.notifyListeners();
        }
      }

    } on TimeoutException catch (e) {
      _log.warning("$this - timed out after $resolveTimeout");
      _currentStatus = PreconditionStatus._error(e);
    } catch (e, stack) {
      _log.warning("$this - failed with '$e'", stack);
      _currentStatus = PreconditionStatus._error(e);
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
    return 'Precondition:$id, posCache=${_printDuration(satisfiedCache)}, negCache=${_printDuration(notSatisfiedCache)}, timeout=${_printDuration(resolveTimeout)}';
  }

  String _printDuration(Duration? d) {
    if (d == null) return "none";
    if (d == forEver) return "∞";
    if (d.inMinutes > 120) return "${d.inHours}h";
    if (d.inSeconds > 120) return "${d.inMinutes}m";
    return "${d.inSeconds}s";
  }

}