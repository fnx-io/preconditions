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

/// Use this constant to specify unlimited cache in [PreconditionsRepository.registerPrecondition]
const forEver = Duration(days: 365 * 100, milliseconds: 42);

/// Repository of all preconditions of your app. You will typically
/// need just one singleton instance of [PreconditionsRepository]. It is a mutable ChangeNotifier, which you can integrate with
/// all sort of state management tools.
///
/// See package README for usage example.
///
///
class PreconditionsRepository extends ChangeNotifier {
  final Map<PreconditionId, Precondition> _known = {};

  LocalSemaphore _semaphore = LocalSemaphore(1);

  /// Use this flag to render CircularProgressIndicator or similar feedback to user.
  ///
  bool get isRunning => !_semaphore.isFree;

  ///
  /// Use this method to register your [PreconditionFunction] with given unique id.
  ///
  /// Optionally:
  ///
  /// * provide [statusBuilder] which will be later used to render feedback to the user (see [Precondition.build])
  /// * limit evaluation duration with [resolveTimeout], after which the precondition is evaluated as [PreconditionStatus.isFailed] (default is 10s)
  /// * allow precondition to cache its positive and/or negative result with [satisfiedCache] and [notSatisfiedCache].
  /// * specify [dependsOn] - set of preconditions which must be satisfied before the repository attempts to evaluate this one
  ///
  Precondition registerPrecondition(PreconditionId id, PreconditionFunction preconditionFunction,
      {String? description,
      Iterable<Dependency> dependsOn: const [],
      resolveTimeout: const Duration(seconds: 10),
      satisfiedCache: Duration.zero,
      notSatisfiedCache: Duration.zero,
      StatusBuilder? statusBuilder,
      }) {
    for (var dId in dependsOn) {
      var dp = _known[dId._targetId];
      if (dp == null) throw Exception("Precondition '$id' depends on '$dId', which is not (yet?) registered");
      dId._target = dp;
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
  Precondition registerAggregatePrecondition(PreconditionId id, Iterable<Dependency> dependsOn,
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
    var list = _known.values.toList();
    _log.info("Evaluating ${list.length} preconditions");
    try {
      await _semaphore.acquire();
      _log.info("Semaphore acquired");
      notifyListeners();
      _Runner _context = _Runner(this);
      var result = await _context.runAll(list);
      await _context.waitForFinish();
      return List.unmodifiable(result);

    } finally {
      _semaphore.release();
      notifyListeners();
    }
  }

  ///
  /// Runs single precondition test. If the test is already running
  /// it won't be started again and you will receive the result of already running evaluation. If the test has dependencies,
  /// they will be evaluated first. If they fail, your test won't be run at all and it's result will be [PreconditionStatus.Failed()].
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
  /// they will be evaluated first. If they fail, your test won't be run at all and it's result will be [PreconditionStatus.Failed()].
  ///
  /// The [registerPrecondition.satisfiedCache] and [registerPrecondition.notSatisfiedCache] can also influence
  /// whether the precondition will be actually run or not.
  ///
  /// Use [ignoreCache] = true to omit any cached value
  ///
  Future<Precondition> evaluatePrecondition(Precondition p, {bool ignoreCache: false}) async {
    _log.info("Evaluating $p");
    try {
      await _semaphore.acquire();
      notifyListeners();
      _Runner _context = _Runner(this);
      var result = await _context.run(p);
      await _context.waitForFinish();
      return result;

    } finally {
      _semaphore.release();
      notifyListeners();
    }
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

  Precondition _getById(PreconditionId id) {
    var p = getPrecondition(id);
    if (p == null) throw Exception("No such precondition is registered: $id");
    return p;
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
        _debugPreconditionImpl(getPrecondition(o._targetId)!, _doneMap, depth + 1);
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
  Iterable<Precondition> getFailedPreconditions() {
    var list = _known.values.toList();
    return List.unmodifiable(list.where((p) => p.status.isNotSatisfied));
  }

}