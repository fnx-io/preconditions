// Copyright (c) 2021, fnx.io
// https://pub.dev/packages/preconditions
// All rights reserved.

part of preconditions;

class Dependency {

  PreconditionId _targetId;
  late Precondition _target;
  final bool _instantPropagationFromTarget;
  bool _wasSatisfied = false;

  Dependency._(this._targetId, this._instantPropagationFromTarget);

}

///
/// This kind of dependency requires the target to be satisfied at least once during the test.
/// Later fails or crashes of the target doesn't change the dependants status.
///
Dependency oneTime(PreconditionId targetId) {
  return Dependency._(targetId, false);
}

///
/// The dependant will never be satisfied unless the target is satisfied as well. Later
/// fails or crashes will immediately propagate to the dependant, even when the dependant is not being evaluated.
///
Dependency tight(PreconditionId targetId) {
  return Dependency._(targetId, true);
}

///
/// The dependant will be satisfied only if the target is satisfied during the evaluation.
/// However - later fails or crashes of target will NOT change the status of the dependant.
/// The status will remain unchanged same till the evaluation of the dependant.
///
Dependency lazy(PreconditionId targetId) {
  return Dependency._(targetId, false);
}