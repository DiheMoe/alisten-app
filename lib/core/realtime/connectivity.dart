import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final connectivityStatusProvider = StreamProvider<List<ConnectivityResult>>((
  ref,
) {
  throw UnimplementedError('connectivityStatus 未注入');
});
