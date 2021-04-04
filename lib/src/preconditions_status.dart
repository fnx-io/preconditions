part of preconditions;

///
/// Result of precondition check. Your precondition function should return one of two
/// possible results:
///
///     PreconditionStatus.satisfied([Object result])
///     // test finished OK (and possible additional details)
///
///     PreconditionStatus.unsatisfied([Object result])
///     // test DIDN'T finished OK (and possible additional details)
///
/// There are few other possible statuses, but those are assigned automatically during the check
/// and you are not supposed to return them as result of your test function.
///
///     PreconditionStatus.unknown()
///     // the test wasn't run yet
///
///     PreconditionStatus.running()
///     // the test is currently running
///
///     PreconditionStatus.failed([this.result])
///     // the test failed with an exception or timeout
///
class PreconditionStatus {
  final int _code;

  /// Addition data about the result, use anyway you need.
  final Object? result;

  PreconditionStatus._()
      : _code = -1,
        result = null;

  /// Convenient discriminator.
  bool get isFailed => _code == 1;

  /// Convenient discriminator.
  bool get isUnsatisfied => _code == 2;

  /// Convenient discriminator.
  bool get isUnknown => _code == 4;

  /// Convenient discriminator.
  bool get isSatisfied => _code == 10;

  /// Convenient discriminator. Please note, that it's not the same as 'isUnsatisfied'.
  bool get isNotSatisfied => !isSatisfied;

  /// The test wasn't run yet, don't return this as a result of your test.
  const PreconditionStatus.unknown()
      : result = null,
        _code = 4;

  /// Test finished OK (and possible additional details).
  PreconditionStatus.satisfied([this.result]) : _code = 10;

  /// Test DIDN'T finished OK (and possible additional details).
  PreconditionStatus.unsatisfied([this.result]) : _code = 2;

  /// The test failed with an exception or timeout, don't return this as a result of your test,
  /// simply throw an exception.
  PreconditionStatus.failed([this.result]) : _code = 1;

  @override
  String toString() {
    switch (_code) {
      case 1:
        return "PreconditionStatus.failed";
      case 2:
        return "PreconditionStatus.unsatisfied";
      case 4:
        return "PreconditionStatus.unknown";
      case 5:
        return "PreconditionStatus.satisfied";
      default:
        return "PreconditionStatus.error";
    }
  }
}
