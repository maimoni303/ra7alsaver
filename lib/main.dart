import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';

import 'state/saver_state.dart';
import 'theme.dart';
import 'ui/brand_overlay.dart';
import 'ui/shell.dart';

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    MediaKit.ensureInitialized();
    final state = SaverState();
    runApp(ChangeNotifierProvider.value(value: state, child: const SaverApp()));
    await state.init();
  }, (e, s) => debugPrint('Unhandled: $e'));
}

class SaverApp extends StatefulWidget {
  const SaverApp({super.key});
  @override
  State<SaverApp> createState() => _SaverAppState();
}

class _SaverAppState extends State<SaverApp> with WidgetsBindingObserver {
  bool _introDone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future<void>.delayed(const Duration(milliseconds: 2600), () {
      if (mounted) setState(() => _introDone = true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Lock "My files" again whenever the app goes to the background
  // (phones report "paused"; desktop windows that are minimised report "hidden").
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused || s == AppLifecycleState.hidden) context.read<SaverState>().relock();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SaverState>();
    return MaterialApp(
      title: 'RA7AL Files Downloader',
      debugShowCheckedModeBanner: false,
      shortcuts: {
        ...WidgetsApp.defaultShortcuts,
        const SingleActivator(LogicalKeyboardKey.select): const ActivateIntent(),
      },
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: s.themeMode,
      locale: Locale(s.english ? 'en' : 'ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      navigatorObservers: [BrandNavObserver()],
      // Logo: centre during the intro, then the top corner — left in Arabic, right in English.
      builder: (context, child) => BrandOverlay(
        intro: !s.ready || !_introDone,
        child: KeyedSubtree(key: ValueKey(s.english), child: child ?? const SizedBox()),
      ),
      home: !s.ready || !_introDone ? const Scaffold(backgroundColor: Color(0xFF0A0A0A)) : const Shell(),
    );
  }
}
