import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'screens/home_screen.dart';
import 'screens/comments_list_screen.dart';
import 'screens/alerts_screen.dart';
import 'config/api_config.dart';
import 'services/notification_service.dart';
import 'services/navigation_service.dart';
import 'providers/ble_provider.dart';
import 'providers/theme_provider.dart';
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Permissions BLE (Android 12+ : BLUETOOTH_SCAN, BLUETOOTH_CONNECT ; location pour le scan)
  await [
    Permission.bluetooth,
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.location,
  ].request();

  // Initialiser le service de notifications
  final notificationService = NotificationService();
  await notificationService.initialize();
  debugPrint('🔔 Service de notifications initialisé');

  // Initialiser ApiConfig pour charger l'URL depuis SharedPreferences
  final baseUrl = await ApiConfig.getBaseUrl();
  debugPrint('🔗 URL du backend chargée: $baseUrl');

  runApp(
    const ProviderScope(
      child: _BleLifecycleObserver(child: MyApp()),
    ),
  );
}

/// Arrête le scan BLE quand l'app passe en arrière-plan pour éviter les appels
/// sur un canal Flutter fermé (FBP OnScanResponse / OnDetachedFromEngine).
class _BleLifecycleObserver extends ConsumerStatefulWidget {
  const _BleLifecycleObserver({required this.child});

  final Widget child;

  @override
  ConsumerState<_BleLifecycleObserver> createState() => _BleLifecycleObserverState();
}

class _BleLifecycleObserverState extends ConsumerState<_BleLifecycleObserver>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      ref.read(bleScanProvider.notifier).stopScan();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  @override
  Widget build(BuildContext context) {
    final navigationService = NavigationService();
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      navigatorKey: navigationService.navigatorKey,
      scaffoldMessengerKey: navigationService.scaffoldMessengerKey,
      title: 'E-PATCH',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,

        // Personnalisation des cartes
        cardTheme: CardTheme(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),

        // Personnalisation des boutons
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 2,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),

        // Personnalisation des champs de texte
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          filled: true,
        ),

        // AppBar personnalisée
        appBarTheme: const AppBarTheme(
          elevation: 0,
          centerTitle: true,
          iconTheme: IconThemeData(color: Colors.white),
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        cardTheme: CardTheme(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 2,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          filled: true,
        ),
        appBarTheme: AppBarTheme(
          elevation: 0,
          centerTitle: true,
          iconTheme: const IconThemeData(color: Colors.white),
          titleTextStyle: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
          backgroundColor: Colors.grey[900],
        ),
      ),

      // Point d'entrée de l'application - IMPORTANT !
      home: const HomeScreen(),
    );
  }
}
