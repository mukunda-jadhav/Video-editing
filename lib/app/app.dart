import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/config/app_config.dart';
import '../core/theme/app_theme.dart';
import 'app_router.dart';

class FrameLabApp extends ConsumerWidget {
  const FrameLabApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title: AppConfig.name,
    debugShowCheckedModeBanner: false,
    theme: AppTheme.dark,
    themeMode: ThemeMode.dark,
    routerConfig: ref.watch(appRouterProvider),
  );
}
