part of preconditions;

///
/// Scopes define "areas" of you application which require some set of preconditions to be met.
/// For example: you need to perform some checks during startup,
/// then some more after login, then even more before some premium function, etc.
///
class PreconditionScope {
  final String debugName;
  const PreconditionScope(this.debugName);

  @override
  String toString() {
    return 'PreconditionScope{$debugName}';
  }
}

/// Predefined scope for your inspiration - you are the one who have to give it some meaning.
const PreconditionScope onAppStart = PreconditionScope("onAppStart");

/// Predefined scope for your inspiration - you are the one who have to give it some meaning.
const PreconditionScope onResume = PreconditionScope("onResume");

/// Predefined scope for your inspiration - you are the one who have to give it some meaning.
const PreconditionScope beforeRegistration = PreconditionScope("beforeRegistration");

/// Predefined scope for your inspiration - you are the one who have to give it some meaning.
const PreconditionScope beforeLogin = PreconditionScope("beforeLogin");

/// Predefined scope for your inspiration - you are the one who have to give it some meaning.
const PreconditionScope afterLogin = PreconditionScope("afterLogin");

/// Predefined scope for your inspiration - you are the one who have to give it some meaning.
const PreconditionScope beforePayedAction = PreconditionScope("beforePayedAction");

/// Predefined scope for your inspiration - you are the one who have to give it some meaning.
const PreconditionScope periodicCheck = PreconditionScope("periodicCheck");
