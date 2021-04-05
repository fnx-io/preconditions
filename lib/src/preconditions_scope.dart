// Copyright (c) 2021, fnx.io
// https://pub.dev/packages/preconditions
// All rights reserved.

part of preconditions;

///
/// Scopes define "areas" of you application which require some set of preconditions to be met.
/// For example: you need to perform some checks during startup,
/// then some more after login, then even more before some premium function, etc.
///
class PreconditionScope {
  /// Just for logging and debugging purposes.
  final String debugName;

  /// Create as many scopes as you need. Specify [debugName] for logging purposes.
  const PreconditionScope(this.debugName);

  @override
  String toString() {
    return 'PreconditionScope{$debugName}';
  }
}

/// Predefined scope for your inspiration, use it or create your own.
const PreconditionScope onStart = PreconditionScope("onStart");

/// Predefined scope for your inspiration, use it or create your own.
const PreconditionScope onResume = PreconditionScope("onResume");

/// Predefined scope for your inspiration, use it or create your own.
const PreconditionScope beforeRegistration = PreconditionScope("beforeRegistration");

/// Predefined scope for your inspiration, use it or create your own.
const PreconditionScope beforeLogin = PreconditionScope("beforeLogin");

/// Predefined scope for your inspiration, use it or create your own.
const PreconditionScope afterLogin = PreconditionScope("afterLogin");

/// Predefined scope for your inspiration, use it or create your own.
const PreconditionScope beforePayedAction = PreconditionScope("beforePayedAction");

/// Predefined scope for your inspiration, use it or create your own.
const PreconditionScope periodic = PreconditionScope("periodic");
