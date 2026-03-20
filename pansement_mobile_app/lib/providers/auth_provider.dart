import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

/// Provider singleton logique pour l'accès API.
/// Le service se configure de façon asynchrone (URL backend + interceptors Dio).
final apiServiceProvider = Provider<ApiService>((ref) {
  final service = ApiService();
  // L'initialisation se fait automatiquement dans le constructeur.
  return service;
});

/// Couche métier auth (login/logout/session) basée sur ApiService.
final authServiceProvider = Provider<AuthService>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  return AuthService(apiService);
});

/// Etat d'authentification exposé à l'UI.
///
/// Convention:
/// - `user == null` => non authentifié
/// - `isLoading == true` => opération auth en cours
/// - `error` contient le dernier message d'erreur présentable à l'utilisateur
class AuthState {
  final User? user;
  final bool isLoading;
  final String? error;

  AuthState({
    this.user,
    this.isLoading = false,
    this.error,
  });

  AuthState copyWith({
    User? user,
    bool? isLoading,
    String? error,
  }) {
    return AuthState(
      user: user ?? this.user,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }

  bool get isAuthenticated => user != null;
}

/// Notifier Riverpod qui orchestre le flux:
/// UI -> AuthNotifier -> AuthService -> ApiService -> backend.
class AuthNotifier extends StateNotifier<AuthState> {
  final AuthService _authService;

  AuthNotifier(this._authService) : super(AuthState());

  /// Authentifie l'utilisateur et met à jour l'état global.
  ///
  /// En cas d'échec, l'erreur est stockée dans le state puis relancée
  /// pour laisser l'écran afficher un message contextualisé.
  Future<void> login(String email, String password) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final user = await _authService.login(email, password);
      state = state.copyWith(
        user: user,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
      rethrow;
    }
  }

  /// Réinitialise la session locale (token + user en mémoire).
  Future<void> logout() async {
    await _authService.logout();
    state = AuthState();
  }

  /// Rehydrate la session au démarrage de l'app.
  /// Si la session n'est plus valide, on repasse simplement en non-authentifié.
  Future<void> loadUser() async {
    state = state.copyWith(isLoading: true);

    try {
      final user = await _authService.getCurrentUser();
      state = state.copyWith(
        user: user,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false);
    }
  }

  /// Recharge le profil courant (ex: après édition profil).
  /// En cas d'échec, on conserve l'état existant pour éviter une déconnexion brutale.
  Future<void> refreshUser() async {
    try {
      final user = await _authService.getCurrentUser();
      state = state.copyWith(user: user);
    } catch (e) {
      // En cas d'erreur, on garde l'utilisateur actuel
    }
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final authService = ref.watch(authServiceProvider);
  return AuthNotifier(authService);
});
