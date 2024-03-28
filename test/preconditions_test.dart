// Copyright (c) 2021, fnx.io
// https://pub.dev/packages/preconditions
// All rights reserved.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:preconditions/preconditions.dart';

Logger log = Logger("PreconditionTest");

class TestProvider {
  int testCallsCount = 0;
  bool flexibleResult = true;

  PreconditionStatus allwaysFail() {
    testCallsCount++;
    log.info("Failing: $testCallsCount");
    return PreconditionStatus.failed("ano");
  }

  PreconditionStatus allwaysThrow() {
    testCallsCount++;
    log.info("Error: $testCallsCount");
    throw "I threw an exception";
  }

  PreconditionStatus allwaysSatisfied() {
    testCallsCount++;
    log.info("Satisfied: $testCallsCount");
    return PreconditionStatus.satisfied("ano");
  }

  Future<PreconditionStatus> dependsOnFlexibleResult() async {
    testCallsCount++;
    log.info("Flexible($flexibleResult): $testCallsCount");
    return PreconditionStatus.fromBoolean(flexibleResult);
  }

  FutureOr<PreconditionStatus> dependsOnFlexibleResultWithCrash() {
    testCallsCount++;
    log.info("FlexibleError($flexibleResult): $testCallsCount");
    if (!flexibleResult) throw "FlexibleError crashed";
    return PreconditionStatus.satisfied();
  }

  FutureOr<PreconditionStatus> runningHalfSecond() async {
    testCallsCount++;
    log.info("Long run: $testCallsCount");
    await Future.delayed(Duration(milliseconds: 500));
    return PreconditionStatus.satisfied("done");
  }
}

void main() {
  /*
  bool get isError => _code == 1;
  bool get isFailed => _code == 2;
  bool get isUnknown => _code == 4;
  bool get isSatisfied => _code == 10;
  bool get isNotSatisfied => !isSatisfied;
   */

  Logger.root.level = Level.ALL; // defaults to Level.INFO
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.message}');
  });

  test('Repository handles satisfied preconditions', () async {
    var t = TestProvider();
    var repo = PreconditionsRepository();
    var p = repo.registerPrecondition(PreconditionId("simple"), t.allwaysSatisfied);
    expect(t.testCallsCount, equals(0));
    expect(repo.hasAnyUnsatisfiedPreconditions(), isTrue);
    expect(p.status.isUnknown, isTrue);
    await repo.evaluatePreconditions();
    expect(p.status.isSatisfied, isTrue);
    expect(p.status.data.toString(), contains("ano"));
    expect(t.testCallsCount, equals(1));
    expect(repo.hasAnyUnsatisfiedPreconditions(), isFalse);
    await repo.evaluatePreconditions();
    expect(t.testCallsCount, equals(2));
    expect(p.status.isSatisfied, isTrue);
    expect(p, equals(repo.getPrecondition(PreconditionId("simple"))));
  });

  test('Repository handles failing preconditions', () async {
    var t = TestProvider();
    var repo = PreconditionsRepository();
    var p = repo.registerPrecondition(PreconditionId("simple"), t.allwaysFail);
    expect(t.testCallsCount, equals(0));
    expect(repo.hasAnyUnsatisfiedPreconditions(), isTrue);
    expect(p.status.isUnknown, isTrue);
    await repo.evaluatePreconditions();
    expect(p.status.isFailed, isTrue);
    expect(t.testCallsCount, equals(1));
    expect(repo.hasAnyUnsatisfiedPreconditions(), isTrue);
    await repo.evaluatePreconditions();
    expect(t.testCallsCount, equals(2));
    expect(p.status.isFailed, isTrue);
    expect(p, equals(repo.getPrecondition(PreconditionId("simple"))));
  });

  test('Repository handles crashing preconditions', () async {
    var t = TestProvider();
    var repo = PreconditionsRepository();
    var p = repo.registerPrecondition(PreconditionId("simple"), t.allwaysThrow);
    expect(t.testCallsCount, equals(0));
    expect(repo.hasAnyUnsatisfiedPreconditions(), isTrue);
    expect(p.status.isUnknown, isTrue);
    await repo.evaluatePreconditions();
    expect(p.status.isFailed, isTrue);
    expect(p.status.exception, isNotNull);
    expect(t.testCallsCount, equals(1));
    expect(repo.hasAnyUnsatisfiedPreconditions(), isTrue);
    await repo.evaluatePreconditions();
    expect(p.status.isFailed, isTrue);
    expect(t.testCallsCount, equals(2));
    expect(p, equals(repo.getPrecondition(PreconditionId("simple"))));
  });

  test('Repository handles evaluation calls serially', () async {
    var t = TestProvider();
    var repo = PreconditionsRepository();
    repo.registerPrecondition(PreconditionId("simple"), t.runningHalfSecond);
    expect(t.testCallsCount, equals(0));
    // following will NOT run in paralel, will be serialized
    expect(repo.isRunning, isFalse);
    var run1 = repo.evaluatePreconditions();
    expect(repo.isRunning, isTrue);
    var run2 = repo.evaluatePreconditions();
    expect(repo.isRunning, isTrue);
    await Future.delayed(Duration(milliseconds: 400));
    expect(t.testCallsCount, equals(1));
    await run1;
    expect(t.testCallsCount, equals(1));
    await Future.delayed(Duration(milliseconds: 400));
    expect(t.testCallsCount, equals(2));
    expect(repo.isRunning, isTrue);
    await run2;
    expect(repo.isRunning, isFalse);
  });

  test('Repository runs single evaluations in parallel', () async {
    var t = TestProvider();
    var repo = PreconditionsRepository();
    for (int a = 0; a < 10; a++) {
      repo.registerPrecondition(PreconditionId("simple$a"), t.runningHalfSecond);
    }
    expect(t.testCallsCount, equals(0));
    var n = DateTime.now();
    await repo.evaluatePreconditions();
    expect(DateTime.now().difference(n).inMilliseconds < 600, isTrue);
    expect(DateTime.now().difference(n).inMilliseconds >= 500, isTrue);
    expect(t.testCallsCount, equals(10));
  });

  test('Repository handles failing preconditions with cache', () async {
    var t = TestProvider();
    var repo = PreconditionsRepository();
    var p = repo.registerPrecondition(PreconditionId("failing"), t.allwaysFail, stayFailedCacheDuration: Duration(milliseconds: 100));
    expect(t.testCallsCount, equals(0));
    expect(p.status.isUnknown, isTrue);
    await repo.evaluatePreconditions();
    expect(p.status.isFailed, true);
    expect(t.testCallsCount, equals(1));
    await repo.evaluatePreconditions();
    expect(t.testCallsCount, equals(1)); // was taken from cache
    expect(p.status.isFailed, true);
    await Future.delayed(Duration(milliseconds: 110));
    await repo.evaluatePreconditions();
    expect(t.testCallsCount, equals(2));
    expect(p.status.isFailed, true);
  });

  test('Repository handles satisfied preconditions with cache', () async {
    var t = TestProvider();
    var repo = PreconditionsRepository();
    var p =
        repo.registerPrecondition(PreconditionId("satisfied"), t.allwaysSatisfied, staySatisfiedCacheDuration: Duration(milliseconds: 100));
    expect(t.testCallsCount, equals(0));
    expect(p.status.isUnknown, isTrue);
    await repo.evaluatePreconditions();
    expect(p.status.isSatisfied, true);
    expect(t.testCallsCount, equals(1));
    await repo.evaluatePreconditions();
    expect(t.testCallsCount, equals(1)); // was taken from cache
    expect(p.status.isSatisfied, true);
    await Future.delayed(Duration(milliseconds: 110));
    await repo.evaluatePreconditions();
    expect(t.testCallsCount, equals(2));
    expect(p.status.isSatisfied, true);
  });

  test('Repository handles multiple independent preconditions', () async {
    var t = TestProvider();
    var repo = PreconditionsRepository();
    var p1 = repo.registerPrecondition(PreconditionId("satisfied"), t.allwaysSatisfied);
    var p2 =
        repo.registerPrecondition(PreconditionId("runningHalfSecond"), t.runningHalfSecond, resolveTimeout: Duration(milliseconds: 501));
    var p3 = repo.registerPrecondition(PreconditionId("satisfied2"), t.allwaysSatisfied);
    expect(t.testCallsCount, equals(0));
    expect(repo.hasAnyUnsatisfiedPreconditions(), isTrue);
    expect(p1.status.isUnknown, isTrue);
    expect(p2.status.isUnknown, isTrue);
    expect(p3.status.isUnknown, isTrue);
    repo.evaluatePreconditions();
    await Future.delayed(Duration(milliseconds: 100));
    expect(p1.status.isSatisfied, isTrue);
    expect(p2.status.isUnknown, isTrue);
    expect(p3.status.isSatisfied, isTrue);
    expect(repo.hasAnyUnsatisfiedPreconditions(), isTrue);
    await Future.delayed(Duration(milliseconds: 500));
    expect(p1.status.isSatisfied, isTrue);
    expect(p2.status.isSatisfied, isTrue);
    expect(p3.status.isSatisfied, isTrue);
    expect(t.testCallsCount, equals(3));
    expect(repo.hasAnyUnsatisfiedPreconditions(), isFalse);
  });
  test('Repository handles time-outing preconditions', () async {
    var t = TestProvider();
    var repo = PreconditionsRepository();
    var p1 = repo.registerPrecondition(PreconditionId("satisfied"), t.allwaysSatisfied);
    var p2 =
        repo.registerPrecondition(PreconditionId("runningHalfSecond"), t.runningHalfSecond, resolveTimeout: Duration(milliseconds: 400));
    var p3 = repo.registerPrecondition(PreconditionId("satisfied2"), t.allwaysSatisfied);
    expect(t.testCallsCount, equals(0));
    expect(repo.hasAnyUnsatisfiedPreconditions(), isTrue);
    expect(p1.status.isUnknown, isTrue);
    expect(p2.status.isUnknown, isTrue);
    expect(p3.status.isUnknown, isTrue);
    repo.evaluatePreconditions();
    await Future.delayed(Duration(milliseconds: 100));
    expect(p1.status.isSatisfied, isTrue);
    expect(p2.status.isUnknown, isTrue);
    expect(p3.status.isSatisfied, isTrue);
    expect(repo.hasAnyUnsatisfiedPreconditions(), isTrue);
    await Future.delayed(Duration(milliseconds: 500));
    expect(p1.status.isSatisfied, isTrue);
    expect(p2.status.isFailed, isTrue);
    expect(p3.status.isSatisfied, isTrue);
    expect(t.testCallsCount, equals(3));
    expect(repo.hasAnyUnsatisfiedPreconditions(), isTrue);
  });

  test('Repository handles simple dependencies (all)', () async {
    var t = TestProvider();
    var repo = PreconditionsRepository();
    var fP = repo.registerPrecondition(PreconditionId("failing"), t.allwaysFail);
    var sCh = repo.registerPrecondition(PreconditionId("satisfied"), t.allwaysSatisfied, dependsOn: [tight(PreconditionId("failing"))]);
    expect(fP.status.isUnknown, isTrue);
    expect(sCh.status.isUnknown, isTrue);
    expect(t.testCallsCount, equals(0));
    await repo.evaluatePreconditions();
    expect(fP.status.isFailed, isTrue);
    expect(sCh.status.isFailed, isTrue);
    // sCh wasn't even evaluated
    expect(t.testCallsCount, equals(1));
  });

  test('Repository handles simple dependencies as agregate (all)', () async {
    var t = TestProvider();
    var repo = PreconditionsRepository();
    var fP = repo.registerPrecondition(PreconditionId("failing"), t.allwaysFail);
    var sCh = repo.registerAggregatePrecondition(PreconditionId("satisfied"), [tight(PreconditionId("failing"))]);
    expect(fP.status.isUnknown, isTrue);
    expect(sCh.status.isUnknown, isTrue);
    expect(t.testCallsCount, equals(0));
    await repo.evaluatePreconditions();
    expect(fP.status.isFailed, isTrue);
    expect(sCh.status.isFailed, isTrue);
    // sCh wasn't even evaluated
    expect(t.testCallsCount, equals(1));
  });

  test('Repository handles simple dependencies (by id)', () async {
    var t = TestProvider();
    var repo = PreconditionsRepository();
    var fP = repo.registerPrecondition(PreconditionId("failing"), t.allwaysFail);
    var sCh = repo.registerPrecondition(PreconditionId("satisfied"), t.allwaysSatisfied, dependsOn: [tight(PreconditionId("failing"))]);
    expect(fP.status.isUnknown, isTrue);
    expect(sCh.status.isUnknown, isTrue);
    expect(t.testCallsCount, equals(0));
    await repo.evaluatePreconditionById(PreconditionId("satisfied"));
    expect(fP.status.isFailed, isTrue);
    expect(sCh.status.isFailed, isTrue);
    // sCh wasn't even evaluated
    expect(t.testCallsCount, equals(1));
  });

  test('Repository handles complex dependencies', () async {
    var t = TestProvider();
    var repo = PreconditionsRepository();
    var s1P = repo.registerPrecondition(PreconditionId("s1"), t.allwaysFail);
    var s2P = repo.registerPrecondition(PreconditionId("s2"), t.runningHalfSecond);
    var res = repo.registerPrecondition(PreconditionId("result"), t.runningHalfSecond,
        dependsOn: [lazy(PreconditionId("s1")), lazy(PreconditionId("s2"))]);
    expect(s1P.status.isUnknown, isTrue);
    expect(s2P.status.isUnknown, isTrue);
    expect(res.status.isUnknown, isTrue);
    expect(t.testCallsCount, equals(0));
    var tot = repo.evaluatePreconditionById(PreconditionId("result"));
    await Future.delayed(Duration(milliseconds: 100));
    expect(t.testCallsCount, equals(2));
    expect(s1P.status.isFailed, isTrue);
    log.info(s2P);
    expect(s2P.status.isUnknown, isTrue);
    expect(res.status.isUnknown, isTrue);
    await tot;
    expect(s1P.status.isFailed, isTrue);
    expect(s2P.status.isSatisfied, isTrue);
    expect(res.status.isFailed, isTrue);
    expect(t.testCallsCount, equals(2));
  });

  test('Repository handles lazy dependencies', () async {
    var t = TestProvider();
    var repo = PreconditionsRepository();
    t.flexibleResult = true;
    var flex = repo.registerPrecondition(PreconditionId("flex"), t.dependsOnFlexibleResult);
    var res = repo.registerPrecondition(PreconditionId("result"), t.runningHalfSecond, dependsOn: [
      lazy(PreconditionId("flex")),
    ]);
    await repo.evaluatePreconditionById(PreconditionId("flex"));
    expect(flex.status.isSatisfied, isTrue);
    expect(res.status.isUnknown, isTrue);
    await repo.evaluatePreconditions();
    expect(flex.status.isSatisfied, isTrue);
    expect(res.status.isSatisfied, isTrue);
    t.flexibleResult = false;
    await repo.evaluatePreconditionById(PreconditionId("flex"));
    expect(flex.status.isFailed, isTrue);
    expect(res.status.isSatisfied, isTrue);
    await repo.evaluatePreconditions();
    expect(flex.status.isFailed, isTrue);
    expect(res.status.isFailed, isTrue);
  });

  test('Repository handles tight dependencies', () async {
    var t = TestProvider();
    var repo = PreconditionsRepository();
    t.flexibleResult = true;
    var flex = repo.registerPrecondition(PreconditionId("flex"), t.dependsOnFlexibleResult);
    var res = repo.registerPrecondition(PreconditionId("result"), t.runningHalfSecond, dependsOn: [
      tight(PreconditionId("flex")),
    ]);
    await repo.evaluatePreconditionById(PreconditionId("flex"));
    expect(flex.status.isSatisfied, isTrue);
    expect(res.status.isUnknown, isTrue);
    t.flexibleResult = false;
    await repo.evaluatePreconditionById(PreconditionId("flex"));
    expect(flex.status.isFailed, isTrue);
    expect(res.status.isFailed, isTrue); // status will change without evaluation
    await repo.evaluatePreconditions();
    expect(flex.status.isFailed, isTrue);
    expect(res.status.isFailed, isTrue);
  });

  test('Repository handles one time dependencies', () async {
    var t = TestProvider();
    var repo = PreconditionsRepository();
    var flex = repo.registerPrecondition(PreconditionId("flex"), t.dependsOnFlexibleResult);
    var res = repo.registerPrecondition(PreconditionId("result"), t.runningHalfSecond, dependsOn: [
      oneTime(PreconditionId("flex")),
    ]);

    t.flexibleResult = false;
    await repo.evaluatePreconditions();
    expect(flex.status.isFailed, isTrue);
    expect(res.status.isFailed, isTrue);

    t.flexibleResult = true;
    await repo.evaluatePreconditions();
    expect(flex.status.isSatisfied, isTrue);
    expect(res.status.isSatisfied, isTrue);

    t.flexibleResult = false;
    await repo.evaluatePreconditions();
    expect(flex.status.isFailed, isTrue);
    expect(res.status.isSatisfied, isTrue);
  });

  test('Repository handles one time dependencies across repository', () async {
    var t = TestProvider();
    var repo = PreconditionsRepository();
    int callCount = 0;

    var counter = repo.registerPrecondition(PreconditionId("counter"), () {
      callCount++;
      return PreconditionStatus.satisfied();
    }, staySatisfiedCacheDuration: forEver);

    var resOne = repo.registerPrecondition(PreconditionId("one"), t.allwaysSatisfied, dependsOn: [
      oneTime(PreconditionId("counter")),
    ]);
    var resTwo = repo.registerPrecondition(PreconditionId("two"), t.allwaysSatisfied, dependsOn: [
      oneTime(PreconditionId("counter")),
    ]);

    // counter precondition should be run only once, no matter what

    await repo.evaluatePreconditionById(PreconditionId("one"), ignoreCache: true);
    expect(resOne.status.isSatisfied, isTrue);
    expect(callCount, 1);

    await repo.evaluatePreconditionById(PreconditionId("two"), ignoreCache: true);
    expect(resTwo.status.isSatisfied, isTrue);
    expect(callCount, 1);

    await repo.evaluatePreconditionById(PreconditionId("one"), ignoreCache: true);
    expect(resOne.status.isSatisfied, isTrue);
    expect(callCount, 1);

    await repo.evaluatePreconditionById(PreconditionId("two"), ignoreCache: true);
    expect(resTwo.status.isSatisfied, isTrue);
    expect(callCount, 1);
  });

  test('Repository handles initialization', () async {
    var t = TestProvider();
    var repo = PreconditionsRepository();
    var p = repo.registerPrecondition(
      PreconditionId("simple"),
      t.allwaysSatisfied,
      initFunction: t.allwaysSatisfied,
    );
    expect(t.testCallsCount, equals(0));
    await repo.evaluatePreconditions();
    expect(p.status.isSatisfied, isTrue);
    expect(t.testCallsCount, equals(2));
    await repo.evaluatePreconditions();
    expect(p.status.isSatisfied, isTrue);
    expect(t.testCallsCount, equals(3));
  });

  test('Repository handles failing initialization', () async {
    var t = TestProvider();
    var repo = PreconditionsRepository();
    var p = repo.registerPrecondition(
      PreconditionId("simple"),
      t.allwaysSatisfied,
      initFunction: t.dependsOnFlexibleResultWithCrash,
    );
    expect(t.testCallsCount, equals(0));

    t.flexibleResult = false;
    await repo.evaluatePreconditions();
    expect(p.status.isFailed, isTrue);
    expect(t.testCallsCount, equals(1));

    await repo.evaluatePreconditions();
    expect(p.status.isFailed, isTrue);
    expect(t.testCallsCount, equals(2));

    t.flexibleResult = true;
    await repo.evaluatePreconditions();
    expect(p.status.isSatisfied, isTrue);
    expect(t.testCallsCount, equals(4));
  });
}
