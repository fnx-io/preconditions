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

  FutureOr<PreconditionStatus> failing() {
    testCallsCount++;
    log.info("Failing: $testCallsCount");
    return PreconditionStatus.failed("ano");
  }

  FutureOr<PreconditionStatus> error() {
    testCallsCount++;
    log.info("Error: $testCallsCount");
    throw "I threw an exception";
  }

  FutureOr<PreconditionStatus> satisfied() {
    testCallsCount++;
    log.info("Satisfied: $testCallsCount");
    return PreconditionStatus.satisfied("ano");
  }

  FutureOr<PreconditionStatus> flexible() {
    testCallsCount++;
    log.info("Flexible($flexibleResult): $testCallsCount");
    return PreconditionStatus.fromBoolean(flexibleResult);
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
    var p = repo.registerPrecondition(PreconditionId("simple"), t.satisfied);
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
    var p = repo.registerPrecondition(PreconditionId("simple"), t.failing);
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
    var p = repo.registerPrecondition(PreconditionId("simple"), t.error);
    expect(t.testCallsCount, equals(0));
    expect(repo.hasAnyUnsatisfiedPreconditions(), isTrue);
    expect(p.status.isUnknown, isTrue);
    await repo.evaluatePreconditions();
    expect(p.status.isError, isTrue);
    expect(t.testCallsCount, equals(1));
    expect(repo.hasAnyUnsatisfiedPreconditions(), isTrue);
    await repo.evaluatePreconditions();
    expect(p.status.isError, isTrue);
    expect(t.testCallsCount, equals(2));
    expect(p, equals(repo.getPrecondition(PreconditionId("simple"))));
  });

  test('Repository doesn\'t allow parallel run', () async {
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

  test('Repository handles failing preconditions with cache', () async {
    var t = TestProvider();
    var repo = PreconditionsRepository();
    var p = repo.registerPrecondition(PreconditionId("failing"), t.failing, notSatisfiedCache: Duration(milliseconds: 100));
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
    var p = repo.registerPrecondition(PreconditionId("satisfied"), t.satisfied, satisfiedCache: Duration(milliseconds: 100));
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

  test('Repository handles multiple independent preconditions',
          () async {
    var t = TestProvider();
    var repo = PreconditionsRepository();
    var p1 = repo.registerPrecondition(PreconditionId("satisfied"), t.satisfied);
    var p2 = repo.registerPrecondition(PreconditionId("runningHalfSecond"), t.runningHalfSecond, resolveTimeout: Duration(milliseconds: 501));
    var p3 = repo.registerPrecondition(PreconditionId("satisfied2"), t.satisfied);
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
    var p1 = repo.registerPrecondition(PreconditionId("satisfied"), t.satisfied);
    var p2 = repo.registerPrecondition(PreconditionId("runningHalfSecond"), t.runningHalfSecond, resolveTimeout: Duration(milliseconds: 400));
    var p3 = repo.registerPrecondition(PreconditionId("satisfied2"), t.satisfied);
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
    expect(p2.status.isError, isTrue);
    expect(p3.status.isSatisfied, isTrue);
    expect(t.testCallsCount, equals(3));
    expect(repo.hasAnyUnsatisfiedPreconditions(), isTrue);
  });

  test('Repository handles simple dependencies (all)', () async {
    var t = TestProvider();
    var repo = PreconditionsRepository();
    var fP = repo.registerPrecondition(PreconditionId("failing"), t.failing);
    var sCh = repo.registerPrecondition(PreconditionId("satisfied"), t.satisfied, dependsOn: [
      tight(PreconditionId("failing"))
    ]);
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
    var fP = repo.registerPrecondition(PreconditionId("failing"), t.failing);
    var sCh = repo.registerPrecondition(PreconditionId("satisfied"), t.satisfied, dependsOn: [
      tight(PreconditionId("failing"))
    ]);
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
    var s1P = repo.registerPrecondition(PreconditionId("s1"), t.failing);
    var s2P = repo.registerPrecondition(PreconditionId("s2"), t.runningHalfSecond);
    var res = repo.registerPrecondition(PreconditionId("result"), t.runningHalfSecond, dependsOn: [
      lazy(PreconditionId("s1")),
      lazy(PreconditionId("s2"))
    ]);
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
    var flex = repo.registerPrecondition(PreconditionId("flex"), t.flexible);
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
    var flex = repo.registerPrecondition(PreconditionId("flex"), t.flexible);
    var res = repo.registerPrecondition(PreconditionId("result"), t.runningHalfSecond, dependsOn: [
      tight(PreconditionId("flex")),
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
    expect(res.status.isFailed, isTrue); // status will change without evaluation
    await repo.evaluatePreconditions();
    expect(flex.status.isFailed, isTrue);
    expect(res.status.isFailed, isTrue);
  });

  /*
  test('Repository handles dependencies', () async {
    var t = TestProvider();
    var repo = PreconditionsRepository();
    var rl = repo.registerPrecondition(PreconditionId("runningHalfSecond1"), t.runningHalfSecond);
    var rl2 = repo.registerPrecondition(PreconditionId("runningHalfSecond2"), t.runningHalfSecond, dependsOn: [PreconditionId("runningHalfSecond1")]);
    var agr = repo.registerAggregatePrecondition(PreconditionId("agr"), [PreconditionId("runningHalfSecond1"), PreconditionId("runningHalfSecond2")]);
    var f = repo.registerPrecondition(PreconditionId("failing"), t.failing);
    var s = repo.registerPrecondition(PreconditionId("satisfied"), t.satisfied, dependsOn: [PreconditionId("failing")]);
    repo.evaluatePreconditions();
    // long run takes 800ms, after 1000 we should see everything resolved but runningHalfSecond2
    await Future.delayed(Duration(milliseconds: 1000));
    expect(rl.status.isSatisfied, isTrue);
    expect(rl2.status.isUnknown, isTrue);
    expect(agr.status.isUnknown, isTrue);
    expect(f.status.isFailed, isTrue);
    expect(s.status.isFailed, isFalse);
    expect(s.status.isSatisfied, isFalse);
    expect(s.status.isUnsatisfied, isTrue);
    await Future.delayed(Duration(milliseconds: 900));
    expect(rl.status.isSatisfied, isTrue);
    expect(rl2.status.isUnknown, isFalse);
    expect(rl2.status.isSatisfied, isTrue);
    expect(agr.status.isSatisfied, isTrue);
    expect(f.status.isFailed, isTrue);
    expect(s.status.isFailed, isFalse);
    expect(s.status.isSatisfied, isFalse);
    expect(s.status.isUnsatisfied, isTrue);
  });

  test('Repository handles deps. in single call', () async {
    var t = TestProvider();
    var repo = PreconditionsRepository();
    var rl = repo.registerPrecondition(PreconditionId("runningHalfSecond1"), t.runningHalfSecond);
    var rl2 = repo.registerPrecondition(PreconditionId("runningHalfSecond2"), t.runningHalfSecond, dependsOn: [PreconditionId("runningHalfSecond1")]);
    var agr = repo.registerAggregatePrecondition(PreconditionId("agr"), [PreconditionId("runningHalfSecond1"), PreconditionId("runningHalfSecond2")]);
    repo.evaluatePreconditionById(PreconditionId("runningHalfSecond2"));
    // long run takes 800ms, after 1000 we should see everything resolved but runningHalfSecond2
    await Future.delayed(Duration(milliseconds: 1000));
    expect(rl.status.isSatisfied, isTrue);
    expect(rl2.status.isUnknown, isTrue);
    expect(agr.status.isUnknown, isTrue);
    await Future.delayed(Duration(milliseconds: 900));
    expect(rl.status.isSatisfied, isTrue);
    expect(rl2.status.isUnknown, isFalse);
    expect(rl2.status.isSatisfied, isTrue);
    expect(agr.status.isUnknown, isTrue);
  });

  test('Repository handles deps. from bottom up', () async {
    bool parentResult = true;
    int parentRunCount = 0;

    int pesimisticNotificationCount = 0;
    int optimisticNotificationCount = 0;

    var repo = PreconditionsRepository();
    var p = repo.registerPrecondition(PreconditionId("parent"), () async {
      parentRunCount++;
      await Future.delayed(Duration(milliseconds: 100));
      return PreconditionStatus.fromBoolean(parentResult);
    });

    var pch = repo.registerPrecondition(PreconditionId("pesimisticChild"), () => PreconditionStatus.fromBoolean(true),
        dependsOn: [PreconditionId("parent")], dependenciesStrategy: DependenciesStrategy.unsatisfiedOnUnsatisfied, satisfiedCache: Duration(days: 1));
    pch.addListener(() {
      pesimisticNotificationCount++;
    });

    var och = repo.registerPrecondition(PreconditionId("optimisticChild"), () => PreconditionStatus.fromBoolean(true),
        dependsOn: [PreconditionId("parent")], dependenciesStrategy: DependenciesStrategy.stayInSuccessCache, satisfiedCache: Duration(days: 1));
    och.addListener(() {
      optimisticNotificationCount++;
    });

    await repo.evaluatePreconditions();

    expect(p.status.isSatisfied, isTrue);
    expect(parentRunCount, equals(1));
    expect(pch.status.isSatisfied, isTrue);
    expect(och.status.isSatisfied, isTrue);
    expect(pesimisticNotificationCount, equals(1));
    expect(optimisticNotificationCount, equals(1));

    parentResult = false;
    await repo.evaluatePrecondition(p);
    expect(p.status.isSatisfied, isFalse);
    expect(parentRunCount, equals(2));
    expect(pch.status.isSatisfied, isFalse);
    expect(och.status.isSatisfied, isTrue);
    expect(pesimisticNotificationCount, equals(2));
    expect(optimisticNotificationCount, equals(1));

    parentResult = true;
    await repo.evaluatePrecondition(p);

    expect(p.status.isSatisfied, isTrue);
    expect(parentRunCount, equals(3));
    expect(pch.status.isSatisfied, isTrue);
    expect(och.status.isSatisfied, isTrue);
    expect(pesimisticNotificationCount, equals(3));
    expect(optimisticNotificationCount, equals(1));
  });

   */
}
