// Copyright (c) 2021, fnx.io
// https://pub.dev/packages/preconditions
// All rights reserved.

library preconditions;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';
import 'package:preconditions/src/semaphore.dart';

part 'src/preconditions_impl.dart';
part 'src/preconditions_repository.dart';
part 'src/preconditions_status.dart';
part 'src/preconditions_dependency.dart';
part 'src/preconditions_runner.dart';

Logger _log = Logger("Preconditions");
