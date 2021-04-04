# preconditions

Pure Dart library for management of preconditions in Flutter apps. Has the user granted all permissions? Is the phone online? Is there enough free disk space?

# Example

Implement precondition functions for your app:

    Future<PreconditionStatus> isSubscriptionValid() { ... }
    Future<PreconditionStatus> arePermissionsGranted() { ... }
    Future<PreconditionStatus> isServerRunning() { ... }
    Future<PreconditionStatus> isThereEnoughDiskSpace() { ... }
    // some will find some example implementations at the and of this readme

Create a repository, and register you preconditions:



# Preconditions cookbook



