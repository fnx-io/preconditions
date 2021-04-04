import 'dart:async';

import 'package:preconditions/preconditions.dart';

void main() {
  // 1) Prepare test functions for mandatory preconditions for your app

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
    return PreconditionStatus.dissatisfied("No, there is not!");
  }

  // 2) Register these preconditions to the repository
  var repository = PreconditionsRepository();
  repository.registerPrecondition(arePermissionsGranted, [onAppStart, onResume]);
  repository.registerPrecondition(isServerRunning, [onAppStart, periodicCheck], resolveTimeout: Duration(seconds: 1));
  repository.registerPrecondition(isThereEnoughDiskSpace, [onAppStart, periodicCheck]);
  repository.registerPrecondition(isSubscriptionValid, [beforePayedAction], satisfiedCache: Duration(minutes: 10));
}
