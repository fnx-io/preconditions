## [0.7.5] 2024-03-28

* "onlyOnce" preconditions not be run multiple times, even when declared as a dependecy in multiple preconditions => don't run onceOnly precondition, when you know it was once successfull even as someone elses dependency 

## [0.7.2] 2023-07-14

* some more fixes

## [0.7.1] 2023-07-14

* fixed "ignoreCache" issue

## [0.7.0] 2023-04-20

* BREAKING CHANGE: removed notSatisfied, only satisfied and failed are available now
* BREAKING CHANGE: added different variants of dependency

## [0.4.3] 2022-03-29

* fixed cache issue with failing preconditions

## [0.4.2] 2022-03-25

* fixed lock issue caused by parallel calls to failing preconditions

## [0.4.1] 2022-03-02

* Fixed cache related race condition

## [0.4.0] 2022-31-01

* Methods to print/debug preconditions graph.

## [0.3.2] 2022-01-11

* dependencies are now also resolved proactively, whenever ancestor changes
* fixed find-by-id bug, added test case

## [0.3.0] 2022-01-11

* PreconditionId is now a class, not a plain String value.

## [0.2.3] 2021-04-23

* support for "ignoreCache" - evaluate no matter what is in the cache

## [0.2.1] 2021-04-12

* support for "evaluate one time, stay in success forever" preconditions

## [0.2.0] 2021-04-06

* BREAKING CHANGE: id is mandatory String
* preconditions can depend on each other -> run some precondition, only if all "parent" preconditions are satisfied
* BREAKING CHANGE: removed scopes and replaced thm with much more precise concept of "aggregate preconditions"

## [0.0.7] 2021-04-06

* added few more useful methods

## [0.0.6] 2021-04-05

* few convenient changes to make API users life easier

## [0.0.5] 2021-04-05

* Basic functions and docs, decent "beta"
