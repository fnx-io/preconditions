import 'dart:async';

import 'package:flutter/material.dart';
import 'package:preconditions/preconditions.dart';

void main() {
  // 1) Prepare test functions for mandatory preconditions of your app

  FutureOr<PreconditionStatus> isSubscriptionValid() {
    return PreconditionStatus.satisfied();
  }

  FutureOr<PreconditionStatus> arePermissionsGranted() {
    return PreconditionStatus.satisfied();
  }

  Future<PreconditionStatus> isServerRunning() {
    throw Exception("Oups, I failed again!");
  }

  Future<PreconditionStatus> isThereEnoughDiskSpace() async {
    return PreconditionStatus.unsatisfied("No, there is not!");
  }

  // 2) Register these preconditions to the repository
  var repository = PreconditionsRepository();
  repository.registerPrecondition(arePermissionsGranted, [onStart, onResume]);
  repository.registerPrecondition(isServerRunning, [onStart, periodic], resolveTimeout: Duration(seconds: 1));
  repository.registerPrecondition(isThereEnoughDiskSpace, [onStart, periodic]);
  repository.registerPrecondition(isSubscriptionValid, [beforePayedAction], satisfiedCache: Duration(minutes: 10));

  var statusBuilder = (BuildContext context, PreconditionStatus status) {
    if (status.isUnknown) return CircularProgressIndicator();
    if (status.isNotSatisfied) return Text("Please buy a new phone, because ${status.result}.");
    return Container();
  };
}
