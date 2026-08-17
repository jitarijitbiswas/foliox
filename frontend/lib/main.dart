import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox<String>('foliox_settings');
  // This box is the on-device paper-trading account. It is created on the
  // first launch and is never sent to the market-data service.
  await Hive.openBox<dynamic>('foliox_account');
  runApp(const ProviderScope(child: PaperTradingApp()));
}
