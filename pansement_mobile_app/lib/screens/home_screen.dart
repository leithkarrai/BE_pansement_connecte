import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/auth_provider.dart';
import '../providers/notifications_provider.dart';
import 'dashboard_screen.dart';
import 'scan_screen.dart';
import 'patients_list_screen.dart';
import 'profile_screen.dart';
import 'login_screen.dart';
import 'comments_list_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    // Démarrer le polling des notifications après le premier frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startNotificationPolling();
    });
  }

  Future<void> _startNotificationPolling() async {
    // Vérifier si les notifications sont activées
    final prefs = await SharedPreferences.getInstance();
    final pushNotificationsEnabled =
        prefs.getBool('notifications_push_enabled') ?? true;

    if (pushNotificationsEnabled) {
      ref.read(notificationPollingProvider.notifier).startPolling();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final user = authState.user;

    // Si non connecté, rediriger vers login
    if (user == null) {
      return const LoginScreen();
    }

    // Écrans selon le rôle
    final screens = _getScreensForRole(user.role);
    final navItems = _getNavItemsForRole(user.role);

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          type: BottomNavigationBarType.fixed,
          selectedItemColor: Theme.of(context).primaryColor,
          unselectedItemColor: Colors.grey,
          items: navItems,
        ),
      ),
    );
  }

  List<Widget> _getScreensForRole(String role) {
    final roleLower = role.toLowerCase();

    switch (roleLower) {
      case 'admin':
      case 'medecin':
        return [
          const DashboardScreen(),
          const PatientsListScreen(),
          const ScanScreen(),
          const ProfileScreen(),
        ];
      case 'patient':
        return [
          const DashboardScreen(),
          const CommentsListScreen(), // Écran des commentaires pour les patients
          const ScanScreen(),
          const ProfileScreen(),
        ];
      default:
        return [const DashboardScreen()];
    }
  }

  List<BottomNavigationBarItem> _getNavItemsForRole(String role) {
    final roleLower = role.toLowerCase();

    switch (roleLower) {
      case 'admin':
      case 'medecin':
        return const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people),
            label: 'Patients',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bluetooth),
            label: 'Scanner',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profil',
          ),
        ];
      case 'patient':
        return const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Accueil',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline),
            label: 'Commentaires',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bluetooth),
            label: 'Mon Device',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profil',
          ),
        ];
      default:
        return const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Accueil',
          ),
        ];
    }
  }
}
