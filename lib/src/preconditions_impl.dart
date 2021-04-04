part of preconditions;

Logger _log = Logger("Preconditions");

/// Implement your precondition verification as this function and return either:
///
///     PreconditionStatus.satisfied([Object data])
///
/// or:
///
///     PreconditionStatus.unsatisfied([Object data])
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

class PreconditionsRepository extends ChangeNotifier {
  final Map<PreconditionScope, List<Precondition>> _repo = {};
  final Map<Object, Precondition> _known = {};
  int _idSeq = 0;
  int _runningCount = 0;
  bool get isEvaluating => _runningCount > 0;

  Precondition registerPrecondition(PreconditionFunction preconditionFunction, Iterable<PreconditionScope> scope,
      {Object? id, resolveTimeout: const Duration(seconds: 10), satisfiedCache: Duration.zero, notSatisfiedCache: Duration.zero, StatusBuilder? statusBuilder}) {
    assert(scope.isNotEmpty);
    if (id == null) {
      _idSeq++;
      id = "preconditionId$_idSeq";
    }
    if (_known.containsKey(id)) {
      throw Exception("Precondition with id = ${id} is already registered");
    }
    var _p = Precondition._(id, preconditionFunction, statusBuilder ?? _nullBuilder, satisfiedCache: satisfiedCache, notSatisfiedCache: notSatisfiedCache, resolveTimeout: resolveTimeout);
    _known[id] = _p;
    for (var s in scope) {
      _log.info("Registering $_p to $s");
      var list = _listOfPreconditions(s);
      list.add(_p);
    }
    notifyListeners();
    return _p;
  }

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

  Future<Precondition> evaluatePreconditionById(Object id) async {
    var p = _known[id];
    if (p == null) {
      throw Exception("Precondition id = $id is not registered");
    }
    return evaluatePrecondition(p);
  }

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

  bool hasAnyUnsatisfiedPreconditions(PreconditionScope scope) {
    var list = _listOfPreconditions(scope);
    return list.any((p) => p.status.isNotSatisfied);
  }

  Iterable<Precondition> getPreconditions(PreconditionScope scope) {
    var list = _listOfPreconditions(scope);
    return List.unmodifiable(list);
  }

  Iterable<Precondition> getUnsatisfiedPreconditions(PreconditionScope scope) {
    var list = _listOfPreconditions(scope);
    return List.unmodifiable(list.where((p) => p.status.isNotSatisfied));
  }

  Iterable<Precondition> getAllPreconditions() {
    var list = _known.values.toList();
    return List.unmodifiable(list);
  }

  Iterable<Precondition> getAllUnsatisfiedPreconditions(PreconditionScope scope) {
    var list = _known.values.toList();
    return List.unmodifiable(list.where((p) => p.status.isNotSatisfied));
  }

  List<Precondition> _listOfPreconditions(PreconditionScope scope) {
    return _repo.putIfAbsent(scope, () => <Precondition>[]);
  }
}

class Precondition extends ChangeNotifier {
  var _currentStatus = PreconditionStatus.unknown();
  final Duration satisfiedCache;
  final Duration notSatisfiedCache;
  final Duration resolveTimeout;
  final PreconditionFunction preconditionFunction;
  final StatusBuilder statusBuilder;
  final Object id;
  DateTime? _lastRun;

  Precondition._(
    this.id,
    this.preconditionFunction,
    this.statusBuilder, {
    this.resolveTimeout: const Duration(seconds: 10),
    this.satisfiedCache: Duration.zero,
    this.notSatisfiedCache: Duration.zero,
  });

  /// Builds a widget with status description. Uses supplied statusBuilder.
  Widget build(BuildContext context) => statusBuilder(context, status);

  Future<PreconditionStatus>? _workingOn;

  PreconditionStatus get status => _currentStatus;

  Future<PreconditionStatus> _evaluate() async {
    _log.severe("Evaluating $this");
    if (_workingOn != null) {
      return await _workingOn!;
    }
    if (_lastRun != null && satisfiedCache.inMicroseconds > 0 && _currentStatus.isSatisfied && _lastRun!.add(satisfiedCache).isAfter(DateTime.now())) return _currentStatus;

    if (_lastRun != null && notSatisfiedCache.inMicroseconds > 0 && _currentStatus.isNotSatisfied && _lastRun!.add(notSatisfiedCache).isAfter(DateTime.now())) return _currentStatus;

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
      _lastRun = DateTime.now();
      _workingOn = null;
    }
    notifyListeners();
    _log.severe("Finished evaluating $this");
    return _currentStatus;
  }

  @override
  bool operator ==(Object other) => identical(this, other) || other is Precondition && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'Precondition{#$id, status=$_currentStatus}';
  }
}
