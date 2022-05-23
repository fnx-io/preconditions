// Copyright (c) 2021, fnx.io
// https://pub.dev/packages/preconditions
// All rights reserved.

part of preconditions;

///
/// Result of precondition check. Your precondition function should return one of two
/// possible results:
///
///     PreconditionStatus.satisfied([Object data])
///     // test finished OK (and possible additional details)
///
///     PreconditionStatus.Failed([Object data])
///     // test DIDN'T finished OK (and possible additional details)
///
/// There are few other possible statuses, but those are assigned automatically during the check
/// and you are not supposed to use them as your return value. When reading the result state use convenient is-something methods:
/// [isSatisfied], [isFailed], [isFailed] (test threw an exception),
/// [isUnknown] (test wasn't run yet), [isNotSatisfied] (which means - anything else then satisfied).
///
class PreconditionStatus {
  final int _code;

  /// Addition data about the result, use anyway you need.
  final Object? data;

  /// Possible exception when "failed"
  final Object? exception;

  /// Possible exception's stack trace when "failed"
  final StackTrace? stackTrace;

  // ignore: unused_element
  PreconditionStatus._()
      : _code = -1,
        data = null,
        exception = null,
        stackTrace = null;

  /// Convenient discriminator.
  bool get isFailed => _code == 2;

  /// Convenient discriminator.
  bool get isUnknown => _code == 4;

  /// Convenient discriminator.
  bool get isSatisfied => _code == 10;

  /// Convenient discriminator. Please note, that it's not the same as 'isFailed'.
  bool get isNotSatisfied => !isSatisfied;

  /// The test wasn't run yet, don't return this as a result of your test.
  const PreconditionStatus._unknown()
      : data = null,
        _code = 4,
        exception = null,
        stackTrace = null;

  /// Test finished OK (and possible additional details). Return it as the result of your [PreconditionFunction].
  PreconditionStatus.satisfied([this.data])
      : _code = 10,
        exception = null,
        stackTrace = null;

  /// Test DIDN'T finished OK (and possible additional details). Return it as the result of your [PreconditionFunction].
  PreconditionStatus.failed([this.data])
      : _code = 2,
        exception = null,
        stackTrace = null;

  PreconditionStatus._crash([this.exception, this.stackTrace])
      : _code = 2,
        data = null;

  /// Often you have a boolean value in your hands - use this constructor to create either
  /// [PreconditionStatus.satisfied()] (true) or [PreconditionStatus.Failed()] (false).
  ///
  factory PreconditionStatus.fromBoolean(bool result, [Object? data]) {
    if (result) return PreconditionStatus.satisfied(data);
    return PreconditionStatus.failed(data);
  }

  @override
  String toString() {
    switch (_code) {
      case 1:
        return "error";
      case 2:
        return "failed";
      case 4:
        return "unknown";
      case 10:
        return "satisfied";
      default:
        return "error";
    }
  }
}
