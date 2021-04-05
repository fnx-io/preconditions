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

const testScope = PreconditionScope("test");
const testScope2 = PreconditionScope("test2");

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
    expect(repo.hasAnyUnsatisfiedPreconditions(testScope), isFalse);
    var p = repo.registerPrecondition(t.failing, [testScope]);
    expect(repo.hasAnyUnsatisfiedPreconditions(testScope), isTrue);
    expect(t.testCallsCount, equals(0));
    expect(p.status.isUnknown, isTrue);
    await repo.evaluatePreconditions(testScope);
    expect(p.status.isUnknown, isFalse);
    expect(p.status.isFailed, true);
    expect(p.status.data.toString(), contains("moon"));
    expect(t.testCallsCount, equals(1));
    expect(repo.hasAnyUnsatisfiedPreconditions(testScope), isTrue);
    expect(repo.hasAnyUnsatisfiedPreconditions(testScope2), isFalse);
    await repo.evaluatePreconditions(testScope);
    expect(t.testCallsCount, equals(2));
    expect(p.status.isFailed, true);
  });

  test('Repository handles satisfied preconditions', () async {
    var t = TestProvider();
    var repo = PreconditionsRepository();
    var p = repo.registerPrecondition(t.satisfied, [testScope]);
    expect(t.testCallsCount, equals(0));
    expect(repo.hasAnyUnsatisfiedPreconditions(testScope), isTrue);
    expect(p.status.isUnknown, isTrue);
    await repo.evaluatePreconditions(testScope);
    expect(p.status.isUnknown, isFalse);
    expect(p.status.isSatisfied, true);
    expect(p.status.data.toString(), contains("ano"));
    expect(t.testCallsCount, equals(1));
    expect(repo.hasAnyUnsatisfiedPreconditions(testScope), isFalse);
    expect(repo.hasAnyUnsatisfiedPreconditions(testScope2), isFalse);
    await repo.evaluatePreconditions(testScope);
    expect(t.testCallsCount, equals(2));
    expect(p.status.isSatisfied, true);
  });

  test('Repository handles failing preconditions with cache', () async {
    var t = TestProvider();
    var repo = PreconditionsRepository();
    var p = repo.registerPrecondition(t.failing, [testScope], notSatisfiedCache: Duration(milliseconds: 100));
    expect(t.testCallsCount, equals(0));
    expect(p.status.isUnknown, isTrue);
    await repo.evaluatePreconditions(testScope);
    expect(p.status.isFailed, true);
    expect(t.testCallsCount, equals(1));
    await repo.evaluatePreconditions(testScope);
    expect(t.testCallsCount, equals(1)); // was taken from cache
    expect(p.status.isFailed, true);
    await Future.delayed(Duration(milliseconds: 110));
    await repo.evaluatePreconditions(testScope);
    expect(t.testCallsCount, equals(2));
    expect(p.status.isFailed, true);
  });

  test('Repository handles failing preconditions with cache', () async {
    var t = TestProvider();
    var repo = PreconditionsRepository();
    var p = repo.registerPrecondition(t.satisfied, [testScope], satisfiedCache: Duration(milliseconds: 100));
    expect(t.testCallsCount, equals(0));
    expect(p.status.isUnknown, isTrue);
    await repo.evaluatePreconditions(testScope);
    expect(p.status.isSatisfied, true);
    expect(t.testCallsCount, equals(1));
    await repo.evaluatePreconditions(testScope);
    expect(t.testCallsCount, equals(1)); // was taken from cache
    expect(p.status.isSatisfied, true);
    await Future.delayed(Duration(milliseconds: 110));
    await repo.evaluatePreconditions(testScope);
    expect(t.testCallsCount, equals(2));
    expect(p.status.isSatisfied, true);
  });

  test('Repository handles long running preconditions', () async {
    var t = TestProvider();
    var repo = PreconditionsRepository();
    var p = repo.registerPrecondition(t.satisfied, [testScope]);
    var p2 = repo.registerPrecondition(t.runningLong, [testScope]);
    expect(t.testCallsCount, equals(0));
    expect(repo.hasAnyUnsatisfiedPreconditions(testScope), isTrue);
    expect(p.status.isUnknown, isTrue);
    expect(p2.status.isUnknown, isTrue);
    expect(repo.isEvaluating, isFalse);
    repo.evaluatePreconditions(testScope);
    await Future.delayed(Duration(milliseconds: 100));
    expect(p.status.isSatisfied, isTrue);
    expect(repo.isEvaluating, isTrue);
    expect(repo.hasAnyUnsatisfiedPreconditions(testScope), isTrue);
    await Future.delayed(Duration(milliseconds: 1000));
    expect(repo.isEvaluating, isFalse);
    expect(p.status.isSatisfied, isTrue);
    expect(p2.status.isSatisfied, isTrue);
    expect(p2.status.data.toString(), contains("done"));
    expect(t.testCallsCount, equals(2));
    expect(repo.hasAnyUnsatisfiedPreconditions(testScope), isFalse);
    expect(repo.hasAnyUnsatisfiedPreconditions(testScope2), isFalse);
  });

  test('Repository handles time-outing preconditions', () async {
    var t = TestProvider();
    var repo = PreconditionsRepository();
    var p = repo.registerPrecondition(t.satisfied, [testScope]);
    var p2 = repo.registerPrecondition(t.runningLong, [testScope], resolveTimeout: Duration(milliseconds: 500));
    expect(t.testCallsCount, equals(0));
    expect(repo.hasAnyUnsatisfiedPreconditions(testScope), isTrue);
    expect(p.status.isUnknown, isTrue);
    expect(p2.status.isUnknown, isTrue);
    repo.evaluatePreconditions(testScope);
    await Future.delayed(Duration(milliseconds: 100));
    expect(p.status.isSatisfied, isTrue);
    expect(repo.isEvaluating, isTrue);
    expect(repo.hasAnyUnsatisfiedPreconditions(testScope), isTrue);
    await Future.delayed(Duration(milliseconds: 1000));
    expect(p.status.isSatisfied, isTrue);
    expect(p2.status.isSatisfied, isFalse);
    expect(repo.isEvaluating, isFalse);
    expect(p2.status.isFailed, isTrue);
    expect(t.testCallsCount, equals(2));
    expect(repo.hasAnyUnsatisfiedPreconditions(testScope), isTrue);
  });
}
