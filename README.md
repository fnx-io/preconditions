# preconditions

Management of preconditions of your Flutter app.

* Has the user granted all needed permissions?
* Is the phone online?
* Is there enough free disk space?
* Can we navigate to payed premium content?
* Is some complicated condition of my business logic fulfilled?

### Features

* implement your preconditions as simple Future returning functions
* organize them to different scopes (onStart, beforeLogin, ...)
* declaratively cache positive and/or negative results
* set timeout to precondition tests
* render feedback to user (i.e. warning, or button to app open settings)
* use your favourite state management tool and react
 to later changes (device becomes offline, user removes previously granted permissions, ...)

# Example

Implement precondition functions for your app:

    FutureOr<PreconditionStatus> isSubscriptionValid() { ... }
    FutureOr<PreconditionStatus> arePermissionsGranted() { ... }
    FutureOr<PreconditionStatus> isServerRunning() { ... }
    FutureOr<PreconditionStatus> isThereEnoughDiskSpace() { ... }
    
    // you will find some example implementations
    // at the and of this README

Create a repository and register your preconditions:

    var repository = PreconditionsRepository();
    repository.registerPrecondition(arePermissionsGranted, [onStart, onResume]);
    repository.registerPrecondition(isServerRunning, [onStart, periodic], resolveTimeout: Duration(seconds: 1));
    repository.registerPrecondition(isThereEnoughDiskSpace, [onStart, periodic]);
    repository.registerPrecondition(isSubscriptionValid, [beforePayedAction], satisfiedCache: Duration(minutes: 10));

Then evaluate whenever you need ...

    await repository.evaluatePreconditions(onStart);
    runApp(...);
    
... schedule periodic check ...
    
    Timer.periodic(Duration(minutes: 5), (_) {
        repository.evaluatePreconditions(periodic);
    });
    
... or maybe make sure you are safe to navigate to premium content:

    await repository.evaluatePreconditions(beforePayedAction);
    if (!repository.hasAnyUnsatisfiedPreconditions(beforePayedAction)) {
       Navigator.of(context).push(...)
    }      

# Documentation

Let's dive into details.

## Precondition Function

Precondition test is an implementation of PreconditionFunction.
Probably similar to this:

    FutureOr<PreconditionStatus> myImportantPrecondition() async {
      int someResult = await doSomethingExpensiveUsingThirdPartyPlugin();
      if (someResult > 0) {
        // that's not good
        return PreconditionStatus.unsatisfied(someResult);
      }
      // we are good to go!
      return PreconditionStatus.satisfied();
    }
    
Some of these tests must be repeated periodically, some are quite expensive
and their results should be cached, some might throw an exception ... but you don't
need to worry about that, you will take care of that later. Keep your tests simple.    

## Precondition Status

Your test function should return either `satisfied` or `unsatisfied` result. There
are other possible results, but those are used by the library and you should
not return them as valid result of your test:

    PreconditionStatus.unknown()
    // The test wasn't run yet.
    
    PreconditionStatus.failed([Object data])
    // The test failed with an exception or timeout.
    // In such case, you just throw an exception.    
    
You can supply some detail data about your result with both
`PreconditionStatus.satisfied([Object data])`
and `PreconditionStatus.unsatisfied([Object data])` methods.    

## Precondition Scope

Preconditions are organized into scopes:

* `onStart`
* `onResume`
* `beforeRegistration`
* `beforeLogin`
* `afterLogin`
* `beforePayedAction`
* `periodic`

But:
* it's perfectly OK to have all preconditions in one scope,
 if you don't feel the need to organize them more
* scope itself doesn't mean anything, you have "assign" some meaning to it,
 as we will show later
* add any number of scopes you might need
     
## Precondition Repository

This is where the magic happens. Create an instance of PreconditionsRepository:

    var repository = PreconditionsRepository();
    
And register your preconditions like this:
    
    repository.registerPrecondition(myImportantPrecondition, [onStart, onResume]);
    
You have to provide the function itself and a list of scopes in which the test should
be evaluated. But you have quite a few options to fine-tune your precondition:

    repository.registerPrecondition(
        myImportantPrecondition,
        [onStart, beforePayedAction, someOtherScopes],
        id: "someArbitraryId",
        satisfiedCache: Duration(minutes: 10),
        notSatisfiedCache: Duration(seconds: 20),
        resolveTimeout: Duration(seconds: 5),
        statusBuilder: (context, status) {
            if (status.isUnknown) return CircularProgressIndicator();
            if (status.isNotSatisfied) return Text("Please buy a new phone, because ${status.data}.");
            return Container();
        },
    );
    
* `id` - you can assign some identificator, which can be used to run single precondition
* `satisfiedCache` - specify a Duration for which the successful test won't be repeated
* `notSatisfiedCache` - specify a Duration for which the unsuccessful or failed test won't be repeated
* `resolveTimeout` - specify a timeout for your test function, after which the Precondition resolves as "failed"
* `statusBuilder` - provide a builder function which converts this precondition into explanatory widget

Registering precondition creates `Precondition` object, which you can use as a handle to your test.

    Precondition handle = repository.registerPrecondition( ... );
    ...
    print(handle.status.isSatisfied);
    ...
    return handle.build(context); // uses provided 'statusBuilder'       

After you register all preconditions your app needs, you can run the evaluation:

    await repository.evaluatePreconditions(onStart);
    
You are responsible for running the evaluation function at appropriate places.
This depends on your architecture, used packages etc., but  
you will find a few recommendations lower at this README.

Note that once evaluated precondition will not change its
status spontaneously, you need to evaluate it when appropriate.
Calling `evaluatePreconditions`
will run all precondition tests again, unless their results are currently cached
(see `satisfiedCache` and `notSatisfiedCache`). That
gives you freedom to evaluated preconditions
quite often, expensive results can be easily cached.

Both `Precondition` and `PreconditionRepository` extend `ChangeNotifier` so
they integrate with `Provider`, `AnimatedBuilder` other state management tools.

    Precondition handle = repository.registerPrecondition( ... );
    // ...
    AnimatedBuilder(
        animation: handle,
        builder: (context, _) => handle.build(context),
    );
    
Or:

    AnimatedBuilder(
      animation: repository,
      builder: (context, _) {
        
        // evaluation in progress
        if (repository.isEvaluating) return CircularProgressIndicator();
        
        // some preconditions are not satisfied
        if (repository.hasAnyUnsatisfiedPreconditions(beforePayedAction)) {
          return Column(
              children: repository
                  .getUnsatisfiedPreconditions(beforePayedAction)
                  .map((p) => p.build(context)).toList());
        }
        
        // everything is just fine!
        return SizedBox(width: 0, height: 0);
      });
        
If you need, you can also run just one `Precondition`:

    repository.evaluatePrecondition(handle);
    repository.evaluatePreconditionById("someArbitraryId")         
    
# Cookbook

TBD

## Flutter integration

TBD

## Permissions

TBD

## Location Services Enabled

TBD

## Online

TBD

## Disk space

TBD

## In App Update

TBD

## ... and more

TBD
