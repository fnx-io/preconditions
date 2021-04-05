// Copyright (c) 2021, fnx.io
// https://pub.dev/packages/preconditions
// All rights reserved.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:preconditions/preconditions.dart';

void main() async {
  // 1) Prepare test functions for mandatory preconditions of your app
  FutureOr<PreconditionStatus> isSubscriptionValid() => PreconditionStatus.satisfied();
  Future<PreconditionStatus> isServerRunning() => throw Exception("Oups, I failed again!");
  Future<PreconditionStatus> isThereEnoughDiskSpace() async => PreconditionStatus.unsatisfied("No, there is not!");

  // 2) Register these preconditions to the repository
  var repository = PreconditionsRepository();
  repository.registerPrecondition(isServerRunning, [onStart, periodic], resolveTimeout: Duration(seconds: 1));
  repository.registerPrecondition(isThereEnoughDiskSpace, [onStart, periodic]);
  repository.registerPrecondition(
    isSubscriptionValid,
    [onStart, beforePayedAction],
    id: "someArbitraryId",
    satisfiedCache: Duration(minutes: 10),
    notSatisfiedCache: Duration(minutes: 20),
    resolveTimeout: Duration(seconds: 5),
    statusBuilder: (context, status) {
      if (status.isUnknown) return CircularProgressIndicator();
      if (status.isNotSatisfied) return Text("Please buy a new phone, because ${status.data}.");
      return Container();
    },
  );

  // 3) Evaluate your preconditions
  await repository.evaluatePreconditions(onStart);

  // 4) ... organize preconditions into different scopes
  await repository.evaluatePreconditions(beforePayedAction);

  // 5) Profit:
  if (!repository.hasAnyUnsatisfiedPreconditions(beforePayedAction)) {
    // Navigator.of(context).push(...)
  }

  var demoTimer = Timer.periodic(Duration(minutes: 5), (_) {
    repository.evaluatePreconditions(periodic);
  });

  // 6) Evaluate anytime you need:
  repository.evaluatePreconditionById("someArbitraryId");

  demoTimer.cancel();
}
