import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'services/power_service.dart';
import 'services/settings_service.dart';
import 'viewmodels/app_viewmodel.dart';
import 'screens/home_screen.dart';
import 'screens/privacy_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await SettingsService.create();
  runApp(ColabDesktopRunnerApp(settings: settings));
}

class ColabDesktopRunnerApp extends StatelessWidget {
  final SettingsService settings;
  const ColabDesktopRunnerApp({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<SettingsService>.value(value: settings),
        ChangeNotifierProvider(create: (_) => PowerService(settings)),
        ChangeNotifierProvider(create: (_) => AppViewModel(settings)),
      ],
      child: Consumer<AppViewModel>(
        builder: (context, vm, _) {
          return MaterialApp(
            title: 'Colab Desktop Runner',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: vm.themeMode,
            // دعم اللغة العربية واتجاه RTL
            locale: const Locale('ar'),
            supportedLocales: const [Locale('ar'), Locale('en')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: settings.privacyAccepted
                ? const HomeScreen()
                : const PrivacyScreen(),
          );
        },
      ),
    );
  }
}
