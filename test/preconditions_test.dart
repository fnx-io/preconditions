// Copyright (c) 2021, fnx.io
// https://pub.dev/packages/preconditions
// All rights reserved.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:preconditions/preconditions.dart';

class TestProvider {
  int testCallsCount = 0;
  FutureOr<PreconditionStatus> failing() {
    testCallsCount++;
    throw "I fail! By the moon and the stars in the skies. I fail!";
  }

  FutureOr<PreconditionStatus> satisfied() {
    testCallsCount++;
    return PreconditionStatus.satisfied("ano");
  }

  FutureOr<PreconditionStatus> runningLong() async {
    testCallsCount++;
    await Future.delayed(Duration(milliseconds: 800));
    return PreconditionStatus.satisfied("done");
  }
}

void main() {
  /*
  bool get isFailed => _code == 1;
  bool get isUnsatisfied => _code == 2;
  bool get isUnknown => _code == 4;
  bool get isSatisfied => _code == 10;
  bool get isNotSatisfied => !isSatisfied;
   */

  Logger.root.level = Level.ALL; // defaults to Level.INFO
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.message}');
  });

  test('Repository handles failing preconditions', () async {
    var t = TestProvider();
    var repo = PreconditionsRepository();
    expect(repo.hasAnyUnsatisfiedPreconditions(), isFalse);
    var p = repo.registerPrecondition(PreconditionId("failing"), t.failing);
    expect(repo.hasAnyUnsatisfiedPreconditions(), isTrue);
    expect(t.testCallsCount, equals(0));
    expect(p.status.isUnknown, isTrue);
    await repo.evaluatePreconditions();
    expect(p.status.isUnknown, isFalse);
    expect(p.status.isFailed, true);
    expect(p.status.data.toString(), contains("moon"));
    expect(t.testCallsCount, equals(1));
    expect(repo.hasAnyUnsatisfiedPreconditions(), isTrue);
    await repo.evaluatePreconditions();
    expect(t.testCallsCount, equals(2));
    expect(p.status.isFailed, true);
  });

  test('Repository handles satisfied preconditions', () async {
    var t = TestProvider();
    var repo = PreconditionsRepository();
    var p = repo.registerPrecondition(PreconditionId("runningLong"), t.satisfied);
    expect(t.testCallsCount, equals(0));
    expect(repo.hasAnyUnsatisfiedPreconditions(), isTrue);
    expect(p.status.isUnknown, isTrue);
    await repo.evaluatePreconditions();
    expect(p.status.isUnknown, isFalse);
    expect(p.status.isSatisfied, true);
    expect(p.status.data.toString(), contains("ano"));
    expect(t.testCallsCount, equals(1));
    expect(repo.hasAnyUnsatisfiedPreconditions(), isFalse);
    await repo.evaluatePreconditions();
    expect(t.testCallsCount, equals(2));
    expect(p.status.isSatisfied, true);
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

  test('Repository handles failing preconditions with cache', () async {
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

  test('Repository handles long running preconditions', () async {
    var t = TestProvider();
    var repo = PreconditionsRepository();
    var p = repo.registerPrecondition(PreconditionId("satisfied"), t.satisfied);
    var p2 = repo.registerPrecondition(PreconditionId("runningLong"), t.runningLong);
    expect(t.testCallsCount, equals(0));
    expect(repo.hasAnyUnsatisfiedPreconditions(), isTrue);
    expect(p.status.isUnknown, isTrue);
    expect(p2.status.isUnknown, isTrue);
    expect(repo.isEvaluating, isFalse);
    repo.evaluatePreconditions();
    await Future.delayed(Duration(milliseconds: 100));
    expect(p.status.isSatisfied, isTrue);
    expect(repo.isEvaluating, isTrue);
    expect(repo.hasAnyUnsatisfiedPreconditions(), isTrue);
    await Future.delayed(Duration(milliseconds: 1000));
    expect(repo.isEvaluating, isFalse);
    expect(p.status.isSatisfied, isTrue);
    expect(p2.status.isSatisfied, isTrue);
    expect(p2.status.data.toString(), contains("done"));
    expect(t.testCallsCount, equals(2));
    expect(repo.hasAnyUnsatisfiedPreconditions(), isFalse);
  });

  test('Repository handles time-outing preconditions', () async {
    var t = TestProvider();
    var repo = PreconditionsRepository();
    var p = repo.registerPrecondition(PreconditionId("satisfied"), t.satisfied);
    var p2 = repo.registerPrecondition(PreconditionId("runningLong"), t.runningLong, resolveTimeout: Duration(milliseconds: 500));
    expect(t.testCallsCount, equals(0));
    expect(repo.hasAnyUnsatisfiedPreconditions(), isTrue);
    expect(p.status.isUnknown, isTrue);
    expect(p2.status.isUnknown, isTrue);
    repo.evaluatePreconditions();
    await Future.delayed(Duration(milliseconds: 100));
    expect(p.status.isSatisfied, isTrue);
    expect(repo.isEvaluating, isTrue);
    expect(repo.hasAnyUnsatisfiedPreconditions(), isTrue);
    await Future.delayed(Duration(milliseconds: 1000));
    expect(p.status.isSatisfied, isTrue);
    expect(p2.status.isSatisfied, isFalse);
    expect(repo.isEvaluating, isFalse);
    expect(p2.status.isFailed, isTrue);
    expect(t.testCallsCount, equals(2));
    expect(repo.hasAnyUnsatisfiedPreconditions(), isTrue);
  });

  test('Repository handles dependencies', () async {
    var t = TestProvider();
    var repo = PreconditionsRepository();
    var rl = repo.registerPrecondition(PreconditionId("runningLong1"), t.runningLong);
    var rl2 = repo.registerPrecondition(PreconditionId("runningLong2"), t.runningLong, dependsOn: [PreconditionId("runningLong1")]);
    var agr = repo.registerAggregatePrecondition(PreconditionId("agr"), [PreconditionId("runningLong1"), PreconditionId("runningLong2")]);
    var f = repo.registerPrecondition(PreconditionId("failing"), t.failing);
    var s = repo.registerPrecondition(PreconditionId("satisfied"), t.satisfied, dependsOn: [PreconditionId("failing")]);
    repo.evaluatePreconditions();
    // long run takes 800ms, after 1000 we should see everything resolved but runningLong2
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

  test('Repository handles dependencies in single call', () async {
    var t = TestProvider();
    var repo = PreconditionsRepository();
    var rl = repo.registerPrecondition(PreconditionId("runningLong1"), t.runningLong);
    var rl2 = repo.registerPrecondition(PreconditionId("runningLong2"), t.runningLong, dependsOn: [PreconditionId("runningLong1")]);
    var agr = repo.registerAggregatePrecondition(PreconditionId("agr"), [PreconditionId("runningLong1"), PreconditionId("runningLong2")]);
    repo.evaluatePreconditionById(PreconditionId("runningLong2"));
    // long run takes 800ms, after 1000 we should see everything resolved but runningLong2
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
}
