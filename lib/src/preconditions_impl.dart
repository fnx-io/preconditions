part of preconditions;

Logger _log = Logger("Preconditions");

typedef FutureOr<PreconditionStatus> PreconditionFunction();

class PreconditionStatus {
  final Object? result;
  final int _code;

  PreconditionStatus._()
      : _code = -1,
        result = null;

  bool get isFailed => _code == 1;
  bool get isDissatisfied => _code == 2;
  bool get isUnknown => _code == 4;
  bool get isRunning => _code == 3;
  bool get isSatisfied => _code == 10;
  bool get isNotSatisfied => !isSatisfied;

  const PreconditionStatus.unknown()
      : result = null,
        _code = 4;
  const PreconditionStatus.running()
      : result = null,
        _code = 3;
  PreconditionStatus.satisfied([this.result]) : _code = 10;
  PreconditionStatus.dissatisfied([this.result]) : _code = 2;
  PreconditionStatus.failed([this.result]) : _code = 1;

  @override
  String toString() {
    switch (_code) {
      case 1:
        return "PreconditionStatus.failed";
      case 2:
        return "PreconditionStatus.dissatisfied";
      case 3:
        return "PreconditionStatus.running";
      case 4:
        return "PreconditionStatus.unknown";
      case 5:
        return "PreconditionStatus.satisfied";
      default:
        return "PreconditionStatus.error";
    }
  }
}

class PreconditionsRepository extends ChangeNotifier {
  final Map<PreconditionScope, List<Precondition>> _repo = {};
  final Map<Object, Precondition> _known = {};
  int _idSeq = 0;

  Precondition registerPrecondition(PreconditionFunction preconditionFunction, Iterable<PreconditionScope> scope,
      {Object? id,
      resolveTimeout: const Duration(seconds: 10),
      satisfiedCache: Duration.zero,
      notSatisfiedCache: Duration.zero}) {
    assert(scope.isNotEmpty);
    if (id == null) {
      _idSeq++;
      id = "preconditionId$_idSeq";
    }
    if (_known.containsKey(id)) {
      throw Exception("Precondition with id = ${id} is already registered");
    }
    var _p = Precondition._(this, id, preconditionFunction,
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

  Future<Iterable<Precondition>> evaluatePreconditions(PreconditionScope scope) async {
    var list = _listOfPreconditions(scope);
    _log.info("Evaluating ${list.length} preconditions in $scope");
    var results = list.map((p) => p._evaluate());
    notifyListeners();
    await Future.wait(results);
    notifyListeners();
    return List.unmodifiable(list);
  }

  Future<Precondition> evaluatePrecondition(Object id) async {
    var p = _known[id];
    if (p == null) {
      throw Exception("Precondition id = $id is not registered");
    }
    _log.info("Evaluating ${p}");
    notifyListeners();
    await p._evaluate();
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
  final PreconditionsRepository _parent;
  final Duration satisfiedCache;
  final Duration notSatisfiedCache;
  final Duration resolveTimeout;
  final PreconditionFunction preconditionFunction;
  final Object id;
  DateTime? _lastRun;

  Precondition._(this._parent, this.id, this.preconditionFunction,
      {this.resolveTimeout: const Duration(seconds: 10),
      this.satisfiedCache: Duration.zero,
      this.notSatisfiedCache: Duration.zero});

  Future<PreconditionStatus>? _workingOn;

  PreconditionStatus get status => _currentStatus;

  Future<PreconditionStatus> _evaluate() async {
    _log.severe("Evaluating $this");
    if (_workingOn != null) {
      assert(_currentStatus == PreconditionStatus.running());
      return await _workingOn!;
    }
    if (_lastRun != null &&
        satisfiedCache.inMicroseconds > 0 &&
        _currentStatus.isSatisfied &&
        _lastRun!.add(satisfiedCache).isAfter(DateTime.now())) return _currentStatus;

    if (_lastRun != null &&
        notSatisfiedCache.inMicroseconds > 0 &&
        _currentStatus.isNotSatisfied &&
        _lastRun!.add(notSatisfiedCache).isAfter(DateTime.now())) return _currentStatus;

    _currentStatus = PreconditionStatus.running();
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
  bool operator ==(Object other) =>
      identical(this, other) || other is Precondition && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'Precondition{#$id, status=$_currentStatus}';
  }
}
