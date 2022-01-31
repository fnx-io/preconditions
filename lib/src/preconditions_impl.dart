// Copyright (c) 2021, fnx.io
// https://pub.dev/packages/preconditions
// All rights reserved.

part of preconditions;

Logger _log = Logger("Preconditions");

/// Implement your precondition verification in form of this function type.  Return either:
/// [PreconditionStatus.satisfied()]
/// or
/// [PreconditionStatus.unsatisfied()]
/// as a result of your test.
///
typedef FutureOr<PreconditionStatus> PreconditionFunction();

/// Unique identificator of precondition.
class PreconditionId {
  final dynamic _value;

  PreconditionId(this._value);

  @override
  bool operator ==(Object other) => identical(this, other) || other is PreconditionId && runtimeType == other.runtimeType && _value == other._value;

  @override
  int get hashCode => _value.hashCode;

  @override
  String toString() {
    return _value.toString();
  }

  dynamic get value => _value;

}

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

///
/// How should precondition handle it's dependencies.
///
enum DependenciesStrategy {
  /// Once resolved to "success", precondition will stay in success state
  /// for [Precondition.satisfiedCache] duration, and it will not attempt to
  /// evaluate it's dependencies.
  stayInSuccessCache,

  /// Successful Precondition will always evaluate it's dependencies and regardless
  /// of its cache settings: it becomes unsatisfied if dependencies are not unsatisfied.
  unsatisfiedOnUnsatisfied
}

/// Repository of all preconditions of your app. You will typically
/// need just one singleton instance of [PreconditionsRepository]. It is a mutable ChangeNotifier, which you can integrate with
/// all sort of state management tools.
///
/// See package README for usage example.
///
///
class PreconditionsRepository extends ChangeNotifier {
  final Map<PreconditionId, Precondition> _known = {};
  Map<Precondition, PreconditionStatus>? _thisRunCache;

  int _runningCount = 0;

  /// Use this flag to render CircularProgressIndicator or similar feedback to user.
  ///
  bool get isEvaluating => _runningCount > 0;

  ///
  /// Use this method to register your [PreconditionFunction] with given unique id.
  ///
  /// Optionally:
  ///
  /// * provide [statusBuilder] which will be later used to render feedback to the user (see [Precondition.build])
  /// * limit evaluation duration with [resolveTimeout], after which the precondition is evaluated as [PreconditionStatus.isFailed]
  /// * allow precondition to cache its positive and/or negative result with [satisfiedCache] and [notSatisfiedCache].
  /// * specify [dependsOn] - set of preconditions which must be satisfied before the repository attempts to evaluate this one
  ///
  Precondition registerPrecondition(PreconditionId id, PreconditionFunction preconditionFunction,
      {String? description,
      Iterable<PreconditionId> dependsOn: const [],
      resolveTimeout: const Duration(seconds: 10),
      satisfiedCache: Duration.zero,
      notSatisfiedCache: Duration.zero,
      StatusBuilder? statusBuilder,
      DependenciesStrategy? dependenciesStrategy}) {
    for (var dId in dependsOn) {
      if (_known[dId] == null) throw Exception("Precondition '$id' depends on '$dId', which is not registered");
    }
    if (_known.containsKey(id)) {
      throw Exception("Precondition '$id' is already registered");
    }
    var _p = Precondition._(
      id,
      preconditionFunction,
      statusBuilder ?? _nullBuilder,
      Set.unmodifiable(dependsOn),
      this,
      description: description,
      satisfiedCache: satisfiedCache,
      notSatisfiedCache: notSatisfiedCache,
      resolveTimeout: resolveTimeout,
      dependenciesStrategy: dependenciesStrategy,
    );
    _known[id] = _p;
    _log.info("Registering $_p");
    notifyListeners();
    return _p;
  }

  ///
  /// Very similar to [registerPrecondition], but the test it itself is always successful and the result of this
  /// precondition depends solely on "parent" preconditions defined in [dependsOn].
  ///
  /// Use this mechanism to organize your preconditions into groups with different priority or purpose.
  ///
  Precondition registerAggregatePrecondition(PreconditionId id, Iterable<PreconditionId> dependsOn,
      {resolveTimeout: const Duration(seconds: 10), satisfiedCache: Duration.zero, notSatisfiedCache: Duration.zero, StatusBuilder? statusBuilder}) {
    return registerPrecondition(id, () => PreconditionStatus.satisfied(),
        description: "combination of other preconditions",
        dependsOn: dependsOn,
        resolveTimeout: resolveTimeout,
        satisfiedCache: satisfiedCache,
        notSatisfiedCache: notSatisfiedCache,
        statusBuilder: statusBuilder);
  }

  ///
  /// Run evaluation of all preconditions registered in this repository. Run order respects dependencies but when
  /// possible, tests are evaluated in parallel.
  ///
  /// In case the previous evaluation is still running, only the already finished tests are evaluated again.
  /// The [registerPrecondition.satisfiedCache] and [registerPrecondition.notSatisfiedCache]
  /// allow usage of previously obtained result of evaluation.
  ///
  Future<Iterable<Precondition>> evaluatePreconditions({bool ignoreCache: false}) async {
    bool _dropCacheAfterFinish = false;
    if (_runningCount == 0) {
      _thisRunCache ??= {};
    }
    var list = _known.values.toList();
    _log.info("Evaluating ${list.length} preconditions");
    try {
      _runningCount++;
      var results = list.map((p) => p._evaluate(ignoreCache: ignoreCache));
      notifyListeners();
      await Future.wait(results);
    } finally {
      _runningCount--;
    }
    notifyListeners();
    if (_runningCount == 0) {
      await Future.wait(_known.values.where((p) => p._workingOn != null).map((p) => p._workingOn!));
      if (_runningCount == 0) {
        _thisRunCache = null;
      }
    }
    return List.unmodifiable(list);
  }

  ///
  /// Runs single precondition test. If the test is already running
  /// it won't be started again and you will receive the result of already running evaluation. If the test has dependencies,
  /// they will be evaluated first. If they fail, your test won't be run at all and it's result will be [PreconditionStatus.unsatisfied()].
  ///
  /// The [registerPrecondition.satisfiedCache] and [registerPrecondition.notSatisfiedCache] can also influence
  /// whether the precondition will be actually run or not.
  ///
  /// Use [ignoreCache] = true to omit any cached value
  ///
  Future<Precondition> evaluatePreconditionById(PreconditionId id, {bool ignoreCache: false}) async {
    var p = _known[id];
    if (p == null) {
      throw Exception("Precondition id = $id is not registered");
    }
    return evaluatePrecondition(p, ignoreCache: ignoreCache);
  }

  ///
  /// Runs single precondition test. If the test is already running
  /// it won't be started again and you will receive the result of already running evaluation. If the test has dependencies,
  /// they will be evaluated first. If they fail, your test won't be run at all and it's result will be [PreconditionStatus.unsatisfied()].
  ///
  /// The [registerPrecondition.satisfiedCache] and [registerPrecondition.notSatisfiedCache] can also influence
  /// whether the precondition will be actually run or not.
  ///
  /// Use [ignoreCache] = true to omit any cached value
  ///
  Future<Precondition> evaluatePrecondition(Precondition p, {bool ignoreCache: false}) async {
    _log.info("Evaluating $p");
    bool _dropCacheAfterFinish = false;
    if (_thisRunCache == null) {
      _thisRunCache = {};
      _dropCacheAfterFinish = true;
    }
    try {
      _runningCount++;
      notifyListeners();
      await p._evaluate(ignoreCache: ignoreCache);
    } finally {
      _runningCount--;
    }
    if (_dropCacheAfterFinish) {
      await Future.wait(_known.values.where((p) => p._workingOn != null).map((p) => p._workingOn!));
      _thisRunCache = null;
    }
    notifyListeners();
    return p;
  }

  ///
  /// Is there any precondition in this repository in other [Precondition.status] then [PreconditionStatus.satisfied()]?
  ///
  bool hasAnyUnsatisfiedPreconditions() {
    var list = _known.values.toList();
    return list.any((p) => p.status.isNotSatisfied);
  }

  ///
  /// Returns desired precondition or null, if it's not registered by [registerPrecondition()] or [registerAggregatePrecondition()]
  ///
  Precondition? getPrecondition(PreconditionId id) {
    return _known[id];
  }

  void debugPrecondition(PreconditionId id, [Map<PreconditionId, bool>? _doneMap]) {
    var p = getPrecondition(id)!;
    _doneMap ??= {};
    _debugPreconditionImpl(p, _doneMap, 0);
  }

  void _debugPreconditionImpl(Precondition p, Map<PreconditionId, bool> _doneMap, int depth) {
    String pref = "    " * depth;
    if (depth == 0) {
      _log.info("$pref=> ${p.toStringDebug()}");
    } else {
      _log.info("$pref-> ${p.toStringDebug()}");
    }
    if (_doneMap[p.id] == null) {
      _doneMap[p.id] = true;
      if (p.description != null) {
        _log.info("$pref   (${p.description})");
      }
      for (var o in p.dependsOn) {
        _debugPreconditionImpl(getPrecondition(o)!, _doneMap, depth + 1);
      }
    }
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
  Iterable<Precondition> getUnsatisfiedPreconditions() {
    var list = _known.values.toList();
    return List.unmodifiable(list.where((p) => p.status.isNotSatisfied));
  }
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
  final PreconditionId id;

  final Iterable<PreconditionId> dependsOn;

  final PreconditionsRepository _parent;

  final DependenciesStrategy? dependenciesStrategy;

  final String? description;

  /// Convenient discriminator.
  bool get isFailed => status.isFailed;

  /// Convenient discriminator.
  bool get isUnsatisfied => status.isUnsatisfied;

  /// Convenient discriminator.
  bool get isUnknown => status.isUnknown;

  /// Convenient discriminator.
  bool get isSatisfied => status.isSatisfied;

  /// Convenient discriminator. Please note, that it's not the same as 'isUnsatisfied'.
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
      this.notSatisfiedCache: Duration.zero,
      this.dependenciesStrategy: DependenciesStrategy.unsatisfiedOnUnsatisfied});

  /// Builds a widget with status description. Uses [statusBuilder] supplied in [PreconditionsRepository.registerPrecondition].
  Widget build(BuildContext context) => statusBuilder(context, status);

  Future<PreconditionStatus> _evaluate({bool ignoreCache: false}) async {
    if (_parent._thisRunCache![this] != null) {
      return _parent._thisRunCache![this]!;
    }
    if (_workingOn != null) {
      return await _workingOn!;
    }
    try {
      _workingOn = _evaluateImpl(ignoreCache: ignoreCache);
      var _result = await _workingOn!;
      return _result;
    } finally {
      _workingOn = null;
    }
  }

  @override
  bool operator ==(Object other) => identical(this, other) || other is Precondition && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'Precondition{#$id, status=$_currentStatus}';
  }

  @override
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

  Future<PreconditionStatus>? _evaluateImpl({bool ignoreCache: false}) async {
    if (_parent._thisRunCache![this] != null) {
      return _parent._thisRunCache![this]!;
    }
    if (!ignoreCache &&
        _lastEvaluation != null &&
        dependenciesStrategy == DependenciesStrategy.stayInSuccessCache &&
        satisfiedCache.inMicroseconds > 0 &&
        _currentStatus.isSatisfied &&
        _lastEvaluation!.add(satisfiedCache).isAfter(DateTime.now())) return _currentStatus;

    if (dependsOn.isNotEmpty) {
      var ancestors = dependsOn.map((id) => _parent._known[id]).map((p) => p!._evaluate(ignoreCache: ignoreCache));
      var results = await Future.wait(ancestors);
      if (results.any((s) => s.isNotSatisfied)) {
        _currentStatus = PreconditionStatus.unsatisfied();
        _log.info("$this - unsatisfied dependencies");
        notifyListeners();
        return _currentStatus;
      }
    }
    if (!ignoreCache &&
        _lastEvaluation != null &&
        satisfiedCache.inMicroseconds > 0 &&
        _currentStatus.isSatisfied &&
        _lastEvaluation!.add(satisfiedCache).isAfter(DateTime.now())) return _currentStatus;

    if (!ignoreCache &&
        _lastEvaluation != null &&
        notSatisfiedCache.inMicroseconds > 0 &&
        _currentStatus.isNotSatisfied &&
        _lastEvaluation!.add(notSatisfiedCache).isAfter(DateTime.now())) return _currentStatus;

    try {
      _log.info("$this - evaluating (ignoreCache=$ignoreCache)");
      var _run = preconditionFunction();
      if (_run == null) {
        _log.warning("$this - returned null");
        throw Exception("precondition function returned null");
      }
      if (_run is Future<PreconditionStatus>) {
        _workingOn = _run.timeout(resolveTimeout);
        _currentStatus = await _workingOn!;
        if (_currentStatus == null) {
          _log.warning("$this - returned null");
          throw Exception("Future precondition function returned null");
        }
      } else {
        _currentStatus = _run;
      }

      _parent._thisRunCache![this] = _currentStatus;

      // These depend on me:
      var _dependants = _parent._known.values.where((p) => p.dependsOn.contains(id)).where((p) => !p.isUnknown); // we don't trigger unresolved dependencies
      for (var _dependant in _dependants) {
        unawaited(_dependant._evaluate(ignoreCache: ignoreCache));
      }
    } on TimeoutException catch (e) {
      _log.warning("$this - timed out after $resolveTimeout");
      _currentStatus = PreconditionStatus._failed(e);
    } catch (e, stack) {
      _log.warning("$this - failed with '$e'", stack);
      _currentStatus = PreconditionStatus._failed(e);
    } finally {
      _lastEvaluation = DateTime.now();
      _workingOn = null;
    }
    notifyListeners();
    _log.info("$this - evaluation finished");
    return _currentStatus;
  }
}

/// Use this constant to specify unlimited cache in [PreconditionsRepository.registerPrecondition]
const forEver = Duration(days: 365 * 100, milliseconds: 42);
