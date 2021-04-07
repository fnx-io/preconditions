// Copyright (c) 2021, fnx.io
// https://pub.dev/packages/preconditions
// All rights reserved.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:preconditions/preconditions.dart';

void main() async {
  // 1) Prepare test functions for mandatory preconditions of your app
  FutureOr<PreconditionStatus> isSubscriptionValid() =>
      PreconditionStatus.satisfied();
  Future<PreconditionStatus> isServerRunning() =>
      throw Exception("Oups, I failed again!");
  Future<PreconditionStatus> isThereEnoughDiskSpace() async =>
      PreconditionStatus.unsatisfied("No, there is not!");

  // 2) Register these preconditions to the repository
  var repository = PreconditionsRepository();
  repository.registerPrecondition("serverRunning", isServerRunning,
      resolveTimeout: Duration(seconds: 1));
  repository.registerPrecondition("diskSpace", isThereEnoughDiskSpace);
  repository.registerPrecondition(
    "validSubscription",
    isSubscriptionValid,
    satisfiedCache: Duration(minutes: 10),
    notSatisfiedCache: Duration(minutes: 20),
    resolveTimeout: Duration(seconds: 5),
    statusBuilder: (context, status) {
      if (status.isUnknown) return CircularProgressIndicator();
      if (status.isNotSatisfied)
        return Text("Please buy a new phone, because ${status.data}.");
      return Container();
    },
  );

  // 3) Evaluate your preconditions
  await repository.evaluatePreconditions();

  // 4) Profit:
  if (!repository.hasAnyUnsatisfiedPreconditions()) {
    // Navigator.of(context).push(...)
  }

  // 5) Maybe schedule?
  var demoTimer = Timer.periodic(Duration(minutes: 5), (_) {
    repository.evaluatePreconditions();
  });

  // 6) Or evaluate just some:
  await repository.evaluatePreconditionById("validSubscription");

  demoTimer.cancel();
}
