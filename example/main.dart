// Copyright (c) 2021, fnx.io
// https://pub.dev/packages/preconditions
// All rights reserved.

import 'dart:async';

import 'package:preconditions/preconditions.dart';

void main() async {
  // 1) Prepare check functions for mandatory preconditions of your app
  FutureOr<PreconditionStatus> isSubscriptionValid() =>
      PreconditionStatus.satisfied(); // TODO: an actual check
  Future<PreconditionStatus> isServerRunning() =>
      throw Exception("Oups, I failed again!"); // TODO: an actual check
  Future<PreconditionStatus> isThereEnoughDiskSpace() async =>
      PreconditionStatus.failed("No, there is not!"); // TODO: an actual check

  // 2) Register these preconditions to the repository
  var repository = PreconditionsRepository();
  repository.registerPrecondition(
    PreconditionId("serverRunning"),
    isServerRunning,
    resolveTimeout: Duration(seconds: 1),
  );
  repository.registerPrecondition(
    PreconditionId("diskSpace"),
    isThereEnoughDiskSpace,
  );
  repository.registerPrecondition(
    PreconditionId("validSubscription"),
    isSubscriptionValid,
    staySatisfiedCacheDuration: Duration(minutes: 30),
    stayFailedCacheDuration: Duration(minutes: 1),
    resolveTimeout: Duration(seconds: 5),
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
  await repository
      .evaluatePreconditionById(PreconditionId("validSubscription"));

  // 7) Group them into sets
  repository.registerAggregatePrecondition(
    PreconditionId("beforeLogin"),
    [
      oneTime(PreconditionId("serverRunning")),
      tight(PreconditionId("diskSpace")),
    ],
  );
  repository.evaluatePreconditionById(PreconditionId("beforeLogin"));
  demoTimer.cancel();
}
