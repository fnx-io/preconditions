// Copyright (c) 2021, fnx.io
// https://pub.dev/packages/preconditions
// All rights reserved.

part of preconditions;

class _Dependency {
  PreconditionId _targetId;
  late Precondition _target;
  final bool _instantPropagationFromTarget;
  bool _wasSatisfied = false;
  bool _onceOnly = false;

  _Dependency._(this._targetId, this._instantPropagationFromTarget);

  @override
  String toString() {
    return '_Dependency{_targetId: $_targetId, _wasSatisfied: $_wasSatisfied, _onceOnly: $_onceOnly}';
  }
}

///
/// This kind of dependency requires the target to be satisfied at least once.
/// Later fails or crashes of the target doesn't change the dependants status.
///
_Dependency oneTime(PreconditionId targetId) {
  return _Dependency._(targetId, false).._onceOnly = true;
}

///
/// The dependant will never be satisfied unless the target is satisfied as well. Later
/// fails or crashes will immediately propagate to the dependant, even when the dependant is not being evaluated.
///
_Dependency tight(PreconditionId targetId) {
  return _Dependency._(targetId, true);
}

///
/// The dependant will be satisfied only if the target is satisfied during the evaluation.
/// However - later fails or crashes of target will NOT change the status of the dependant.
/// The status will remain unchanged untill the evaluation of the dependant.
///
_Dependency lazy(PreconditionId targetId) {
  return _Dependency._(targetId, false);
}
