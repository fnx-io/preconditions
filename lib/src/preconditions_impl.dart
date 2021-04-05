// Copyright (c) 2021, fnx.io
// https://pub.dev/packages/preconditions
// All rights reserved.

part of preconditions;

Logger _log = Logger("Preconditions");

/// Implement your precondition verification as this function and return either:
/// [PreconditionStatus.satisfied()]
/// or
/// [PreconditionStatus.unsatisfied()]
/// as a result of your test.
///
typedef FutureOr<PreconditionStatus> PreconditionFunction();

/// Optionally provide this Widget builder to render a feedback to your user, i.e. "Please grant all permissions", etc.
/// Example:
///
///     (BuildContext context, PreconditionStatus status) {
///        if (status.isNotSatisfied) return Text("Please buy a new phone, because ${status.data}.");
///        return Container();
///     }
///
typedef Widget StatusBuilder(BuildContext context, PreconditionStatus status);

StatusBuilder _nullBuilder = (BuildContext c, PreconditionStatus s) => SizedBox(width: 0, height: 0);

/// Repository of all preconditions of your app, organized into different [PreconditionScope]s. You will typically
/// need just one singleton instance of [PreconditionsRepository]. It is a mutable ChangeNotifier, which you can integrate with
/// all sort of state management tools.
///
/// See package README for usage example.
///
///
class PreconditionsRepository extends ChangeNotifier {
  final Map<PreconditionScope, List<Precondition>> _repo = {};
  final Map<Object, Precondition> _known = {};
  int _idSeq = 0;
  int _runningCount = 0;

  /// Use this flag to render CircularProgressIndicator or similar feedback to user.
  ///
  bool get isEvaluating => _runningCount > 0;

  ///
  /// Use this method to register your [PreconditionFunction]. Define in which [scope]s it should
  /// be evaluated and optionally:
  ///
  /// * assign an [id] to the precondition
  /// * provide [statusBuilder] which will be later used to render feedback to the user (see [Precondition.build])
  /// * limit evaluation duration with [resolveTimeout], after which the precondition is evaluated as [PreconditionStatus.failed()]
  /// * allow precondition to cache its positive and negative result with [satisfiedCache] and [notSatisfiedCache].
  ///
  Precondition registerPrecondition(PreconditionFunction preconditionFunction, Iterable<PreconditionScope> scope,
      {Object? id,
      resolveTimeout: const Duration(seconds: 10),
      satisfiedCache: Duration.zero,
      notSatisfiedCache: Duration.zero,
      StatusBuilder? statusBuilder}) {
    assert(scope.isNotEmpty);
    if (id == null) {
      _idSeq++;
      id = "preconditionId$_idSeq";
    }
    if (_known.containsKey(id)) {
      throw Exception("Precondition with id = ${id} is already registered");
    }
    var _p = Precondition._(id, preconditionFunction, statusBuilder ?? _nullBuilder,
        satisfiedCache: satisfiedCache, notSatisfiedCache: notSatisfiedCache, resolveTimeout: resolveTimeout);
    _known[id] = _p;
    for (var s in scope) {
      _log.info("Registering $_p to $s");
      var list = _listOfPreconditions(s);
      list.add(_p);
    }
    notifyListeners();
    return _p;
  }

  ///
  /// Run evaluation of all preconditions registered within the [scope]. All tests are evaluated in parallel.
  /// If the previous evaluation is still running, only already finished test are run again.
  /// The [registerPrecondition.satisfiedCache] and [registerPrecondition.notSatisfiedCache] might
  /// force the repository to use previously obtained result of evaluation.
  ///
  Future<Iterable<Precondition>> evaluatePreconditions(PreconditionScope scope) async {
    var list = _listOfPreconditions(scope);
    _log.info("Evaluating ${list.length} preconditions in $scope");
    try {
      _runningCount++;
      var results = list.map((p) => p._evaluate());
      notifyListeners();
      await Future.wait(results);
    } finally {
      _runningCount--;
    }
    notifyListeners();
    return List.unmodifiable(list);
  }

  ///
  /// Run single precondition test with no regard to its scopes. If the test is already running
  /// it won't be started again.
  /// The [registerPrecondition.satisfiedCache] and [registerPrecondition.notSatisfiedCache] can also influence
  /// whether the precondition will be actually run or not.
  ///
  Future<Precondition> evaluatePreconditionById(Object id) async {
    var p = _known[id];
    if (p == null) {
      throw Exception("Precondition id = $id is not registered");
    }
    return evaluatePrecondition(p);
  }

  ///
  /// Run single precondition test with no regard to its scopes. If the test is already running
  /// it won't be started again.
  /// The [registerPrecondition.satisfiedCache] and [registerPrecondition.notSatisfiedCache] can also influence
  /// whether the precondition will be actually run or not.
  ///
  Future<Precondition> evaluatePrecondition(Precondition p) async {
    _log.info("Evaluating ${p}");
    try {
      _runningCount++;
      notifyListeners();
      await p._evaluate();
    } finally {
      _runningCount--;
    }
    notifyListeners();
    return p;
  }

  ///
  /// Are any preconditions in this scope in other [Precondition.status] then [PreconditionStatus.satisfied()]?
  ///
  bool hasAnyUnsatisfiedPreconditions(PreconditionScope scope) {
    var list = _listOfPreconditions(scope);
    return list.any((p) => p.status.isNotSatisfied);
  }

  ///
  /// Returns all preconditions in this [scope].
  ///
  Iterable<Precondition> getPreconditions(PreconditionScope scope) {
    var list = _listOfPreconditions(scope);
    return List.unmodifiable(list);
  }

  ///
  /// Returns all preconditions in this [scope] which has other [Precondition.status] then [PreconditionStatus.satisfied()].
  ///
  Iterable<Precondition> getUnsatisfiedPreconditions(PreconditionScope scope) {
    var list = _listOfPreconditions(scope);
    return List.unmodifiable(list.where((p) => p.status.isNotSatisfied));
  }

  ///
  /// Returns all known preconditions in this repository.
  ///
  Iterable<Precondition> getAllPreconditions() {
    var list = _known.values.toList();
    return List.unmodifiable(list);
  }

  ///
  /// Returns all known preconditions in this repository which has other [Precondition.status] then [PreconditionStatus.satisfied()].
  ///
  Iterable<Precondition> getAllUnsatisfiedPreconditions() {
    var list = _known.values.toList();
    return List.unmodifiable(list.where((p) => p.status.isNotSatisfied));
  }

  List<Precondition> _listOfPreconditions(PreconditionScope scope) {
    return _repo.putIfAbsent(scope, () => <Precondition>[]);
  }
}

/// [PreconditionsRepository] creates this object from [PreconditionFunction] which you register in
/// [PreconditionsRepository.registerPrecondition()]. Think of it as a handle
/// to your precondition. It is a mutable ChangeNotifier, but is modified only through
/// methods of [PreconditionsRepository] and from your point of view it's read-only. It's possible
/// to integrate it with your state management tool, for example:
///
///     Precondition handle = repository.registerPrecondition( ... );
///     // ...
///     AnimatedBuilder(
///         animation: handle,
///         builder: (context, _) => handle.build(context),
///     );
///
///
class Precondition extends ChangeNotifier {
  var _currentStatus = PreconditionStatus.unknown();

  /// For how long should we cache positive test results.
  /// Might be usefull in cases when the test itself is expensive,
  /// positive results don't spontaneously change that often etc.
  final Duration satisfiedCache;

  /// For how long should we cache negative (unsatisfiend and failed) test results.
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
  final Object id;

  DateTime? _lastEvaluation;

  /// Last evaluation run was finished at ...
  DateTime? get lastEvaluation => _lastEvaluation;

  Future<PreconditionStatus>? _workingOn;

  /// Current (equals last) result of evaluation, which happened at [lastEvaluation].
  PreconditionStatus get status => _currentStatus;

  Precondition._(
    this.id,
    this.preconditionFunction,
    this.statusBuilder, {
    this.resolveTimeout: const Duration(seconds: 10),
    this.satisfiedCache: Duration.zero,
    this.notSatisfiedCache: Duration.zero,
  });

  /// Builds a widget with status description. Uses [statusBuilder] supplied in [PreconditionsRepository.registerPrecondition].
  Widget build(BuildContext context) => statusBuilder(context, status);

  Future<PreconditionStatus> _evaluate() async {
    _log.severe("Evaluating $this");
    if (_workingOn != null) {
      return await _workingOn!;
    }
    if (_lastEvaluation != null &&
        satisfiedCache.inMicroseconds > 0 &&
        _currentStatus.isSatisfied &&
        _lastEvaluation!.add(satisfiedCache).isAfter(DateTime.now())) return _currentStatus;

    if (_lastEvaluation != null &&
        notSatisfiedCache.inMicroseconds > 0 &&
        _currentStatus.isNotSatisfied &&
        _lastEvaluation!.add(notSatisfiedCache).isAfter(DateTime.now())) return _currentStatus;

    notifyListeners();
    try {
      var _run = preconditionFunction();
      if (_run is Future<PreconditionStatus>) {
        _workingOn = _run.timeout(resolveTimeout);
        _currentStatus = await _workingOn!;
      } else {
        _currentStatus = _run;
      }
    } on TimeoutException catch (e, stack) {
      _log.severe("$this timed out after $resolveTimeout");
      _currentStatus = PreconditionStatus.failed(e);
    } catch (e, stack) {
      _log.severe("$this failed with $e", stack);
      _currentStatus = PreconditionStatus.failed(e);
    } finally {
      _lastEvaluation = DateTime.now();
      _workingOn = null;
    }
    notifyListeners();
    _log.severe("Finished evaluating $this");
    return _currentStatus;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Precondition && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'Precondition{#$id, status=$_currentStatus}';
  }
}
