part of preconditions;

class PreconditionScope {
  final String debugName;
  const PreconditionScope(this.debugName);

  @override
  String toString() {
    return 'PreconditionScope{$debugName}';
  }
}
