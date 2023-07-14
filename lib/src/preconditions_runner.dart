// Copyright (c) 2021, fnx.io
// https://pub.dev/packages/preconditions
// All rights reserved.

part of preconditions;

class _Runner {
  Map<PreconditionId, Precondition> _results = {};
  List<_RunTask> _plan = [];

  _Runner();

  Future<Iterable<Precondition>> runAll(
      Iterable<Precondition> all, bool ignoreCache) async {
    var result = all.map((_p) => run(_p, ignoreCache));
    await Future.wait(result);
    return all;
  }

  Future<Precondition> run(Precondition p, bool ignoreCache) async {
    var _cached = _results[p.id];
    if (_cached != null) {
      return _cached;
    }
    if (_plan.any(_planForPrecondition(p))) {
      _RunTask task = _plan.firstWhere(_planForPrecondition(p));
      await task.result;
    } else {
      _RunTask task = _RunTask(p, this, ignoreCache);
      _plan.add(task);
      await task.result;
      _plan.remove(task);
    }
    return p;
  }

  void _addResult(Precondition p) {
    _results[p.id] = p;
  }

  Future waitForFinish() async {
    _log.info("Waiting for finish: ${_plan.length}");
    if (_plan.isEmpty) return;
    var allInProgress = _plan.map((t) => t.result);
    await Future.wait(allInProgress);
    return await waitForFinish();
  }

  _planForPrecondition(Precondition p) => (_RunTask e) {
        return e.p.id == p.id;
      };
}

class _RunTask {
  final Precondition p;
  late Future<PreconditionStatus> result;
  final bool ignoreCache;

  _RunTask(this.p, _Runner context, this.ignoreCache) {
    result = p._evaluate(context, ignoreCache: ignoreCache);
  }
}
