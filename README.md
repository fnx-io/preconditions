# preconditions

Management of preconditions of your Flutter app.

* Has the user granted all needed permissions?
* Is the phone online?
* Is there enough free disk space?
* Can we navigate to payed premium content?
* Is some complicated condition of my business logic fulfilled?

### Features

* implement your preconditions as simple Future returning functions
* define dependencies among them (run this precondition, only if that precondition was successful)
* declaratively cache positive and/or negative results
* set timeout to precondition tests
* render feedback to user (i.e. warning or button to app open settings)
* use your favourite state management tool and react
 to later changes (device becomes offline, user removes previously granted permissions, ...)

# Example

Implement precondition functions for your app:

    FutureOr<PreconditionStatus> arePermissionsGranted() { ... }
    FutureOr<PreconditionStatus> isDeviceOnline() { ... }
    FutureOr<PreconditionStatus> isSubscriptionValid() { ... }
    FutureOr<PreconditionStatus> isMyServerRunning() { ... }
    
    // you will find some example implementations
    // at the and of this README

Create a repository and register your preconditions:

    var repository = PreconditionsRepository();
    repository.registerPrecondition("permissions", arePermissionsGranted);
    repository.registerPrecondition("online", isDeviceOnline);
    repository.registerPrecondition("serverRunning", isMyServerRunning, dependsOn: ["online"], resolveTimeout: Duration(seconds: 1));
    repository.registerPrecondition("validSubscription", isSubscriptionValid, satisfiedCache: Duration(minutes: 10));

Then evaluate whenever you need ...

    await repository.evaluatePreconditions();
    runApp(...);
 
    
... schedule periodic check ...
    
    Timer.periodic(Duration(minutes: 5), (_) {
        repository.evaluatePreconditions();
    });

... react ...

    AnimatedBuilder(
        animation: repository,
        builder: (context, _) => if (repository.hasAnyUnsatisfiedPreconditions()) ...,
    );

... or maybe make sure you are safe to navigate to premium content:

    var p = await repository.evaluatePrecondition("validSubscription");
    if (p.isSuccessfull) {
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
     
## Precondition Repository

This is where the magic happens. Create an instance of PreconditionsRepository:

    var repository = PreconditionsRepository();
    
And register your preconditions like this:
    
    repository.registerPrecondition("important", myImportantPrecondition);
    
You have to provide the function itself and it's unique identificator,
but you have quite a few options to fine-tune your precondition:

    repository.registerPrecondition(
       "validSubscription",
       isSubscriptionValid,
       satisfiedCache: Duration(minutes: 10),
       notSatisfiedCache: Duration(minutes: 20),
       resolveTimeout: Duration(seconds: 5),
       statusBuilder: (context, status) {
           if (status.isUnknown) return CircularProgressIndicator();
           if (status.isNotSatisfied) return Text("Please buy a new phone, because ${status.data}.");
           return Container();
       },
    );

* `satisfiedCache` - specify a Duration for which the successful test won't be repeated
* `notSatisfiedCache` - specify a Duration for which the unsuccessful or failed test won't be repeated
* `resolveTimeout` - specify a timeout for your test function, after which the Precondition resolves as "failed"
* `statusBuilder` - provide a builder function which converts this precondition into explanatory widget

Registering your test function creates a `Precondition` object, which you can use as a handle to your precondition.

    Precondition handle = repository.registerPrecondition( ... );
    ...
    print(handle.status.isSatisfied);
    ...
    return handle.build(context); // uses provided 'statusBuilder'       

After you register all preconditions your app needs, you can run the evaluation:

    await repository.evaluatePreconditions();
 
You are responsible for running the evaluation at appropriate places.
This depends on your architecture, used packages etc., but  
you will find a few recommendations lower at this README.

Note that once evaluated precondition will not change its
status spontaneously, you need to run evaluate manually.
Calling `evaluatePreconditions`
will run all precondition tests again, unless their results are currently cached
(see `satisfiedCache` and `notSatisfiedCache`). That
gives you freedom to evaluated preconditions
quite often, expensive results can be easily cached.

You can also run just a single precondition:

    await repository.evaluatePreconditionById("myPreconditionId");

It's a way to organize your preconditions into more complex structures. Define an "aggregate" precondition with dependencies:

    Precondition agr = repo.registerAggregatePrecondition("beforePremiumContent", ["isOnline", "hasValidSubscription"]);

... and evaluate when needed:

    await repository.evaluatePreconditionById("beforePremiumContent");
    /// or: await repository.evaluatePrecondition(agr);

Both `Precondition` and `PreconditionRepository` extend `ChangeNotifier` so
they integrate with `Provider`, `AnimatedBuilder` and other state management tools.

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
        if (repository.hasAnyUnsatisfiedPreconditions()) {
          return Column(
              children: repository
                  .getUnsatisfiedPreconditions()
                  .map((p) => p.build(context)).toList());
        }
        
        // everything is just fine!
        return SizedBox(width: 0, height: 0);
      });
    
# Cookbook

TBD

## Flutter integration

### Provider example

You can easily plug Preconditions into Provider or similar framework:

    preconditionsRepository = PreconditionsRepository();
    _myRegisterAllPreconditions(preconditionsRepository); 

    ...    

    ChangeNotifierProvider.value(value: preconditionsRepository), child ...);

    ...

    preconditionsRepository.evaluatePreconditions();

And then listen to any changes:

    Consumer<PreconditionsRepository>(builder: (context, repo, child) {
      if (repo.isEvaluating) return CircularProgressIndicator();
      return SizedBox(width: 0, height: 0);
    }),

## Permissions

TBD

## Location Services Enabled

TBD

## Is the device (truly) online?

With:

    dependencies:
      connectivity: ^3.0.3

implement the check ...

    FutureOr<PreconditionStatus> isOnlineImpl() async {
       var connectivityResult = await (Connectivity().checkConnectivity());
       if (connectivityResult == ConnectivityResult.mobile || connectivityResult == ConnectivityResult.wifi) {
           return PreconditionStatus.satisfied();
       }
       return PreconditionStatus.unsatisfied();
    }
    
    FutureOr<PreconditionStatus> isConnectedImpl() async {
       // Should be run only when "is online"
       var connected = (await http.get("https://www.gstatic.com/generate_204")).statusCode == 204;
       return PreconditionStatus.fromBoolean(connected);
    }

... register ...
    
    repository.registerPrecondition("online", isOnlineImpl);
    repository.registerPrecondition("connected", isConnectedImpl, dependsOn: ["online"]);

... schedule re-evaluation on change ...

    Connectivity().onConnectivityChanged.listen((_) {
       repository.evaluatePreconditionById("connected");
    });

... and possibly later:

    bool get isConnected => repository.getPrecondition("connected").isSatisfied;

## Disk space

TBD

## One time configuration / migration / update

There are some tasks which need to be run and need to be run only once. Maybe download a configuration from
your server, migrate DB schema, or init some third-party plugin. Configure those tasks like this:

     // Do what you gotta do:
     FutureOr<PreconditionStatus> initSomethingImportant() { ... }

     _repo.registerPrecondition(
         "important",
         initSomethingImportant,
         dependsOn: ["connected"],    // maybe you need to be online for this
         satisfiedCache: forEver,     // and once satisfied, it can stay satisfied for ever ...
         dependenciesStrategy: DependenciesStrategy.stayInSuccessCache); // ... even when it becomes offline

## In App Update

TBD

## ... and more

TBD
