import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import '../config/api_config.dart';
import '../models/user.dart';
import '../models/device.dart';
import '../models/measurement.dart';
import '../models/comment.dart';

/// Service API pour communiquer avec le backend FastAPI.
///
/// Responsabilités:
/// - configurer Dio (URL, timeout, headers),
/// - injecter automatiquement le token Bearer,
/// - normaliser les erreurs backend/réseau,
/// - exposer les appels REST consommés par les providers/services métiers.
class ApiService {
  final Dio _dio;
  final Logger _logger = Logger();
  String? _accessToken;
  bool _initialized = false;

  ApiService() : _dio = Dio() {
    // Différer l'init après le premier frame pour éviter "Skipped N frames" au démarrage
    Future.microtask(() => _initialize());
  }

  /// Initialise le service avec l'URL chargée depuis SharedPreferences
  Future<void> _initialize() async {
    if (_initialized) return;

    try {
      // Charger l'URL depuis SharedPreferences
      var baseUrl = await ApiConfig.getBaseUrl();

      // Configurer Dio avec l'URL chargée
      _dio.options = BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: ApiConfig.timeout,
        receiveTimeout: ApiConfig.timeout,
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Accept': 'application/json; charset=utf-8',
        },
        validateStatus: (status) => status! < 500,
        responseType: ResponseType.json,
      );

      // Interceptor central:
      // - ajoute Authorization quand on a un token,
      // - trace les requêtes en debug,
      // - loggue les erreurs HTTP pour diagnostic.
      _dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (_accessToken != null) {
              options.headers['Authorization'] = 'Bearer $_accessToken';
            }
            if (kDebugMode) {
              debugPrint('🌐 ${options.method} ${options.path}');
            }
            return handler.next(options);
          },
          onError: (error, handler) {
            _logger.e('Error: ${error.response?.statusCode} ${error.message}');
            _logger.e('Error details: ${error.toString()}');
            return handler.next(error);
          },
        ),
      );

      _initialized = true;
      if (kDebugMode) debugPrint('🔗 ApiService - URL utilisée: $baseUrl');
    } catch (e) {
      _logger.e('Erreur initialisation ApiService: $e');
      // Utiliser l'URL par défaut en cas d'erreur
      final defaultUrl = ApiConfig.defaultUrl;
      _dio.options = BaseOptions(
        baseUrl: defaultUrl,
        connectTimeout: ApiConfig.timeout,
        receiveTimeout: ApiConfig.timeout,
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Accept': 'application/json; charset=utf-8',
        },
        validateStatus: (status) => status! < 500,
        responseType: ResponseType.json,
      );
      _initialized = true;
      if (kDebugMode)
        debugPrint('🔗 ApiService - URL par défaut utilisée: $defaultUrl');
    }
  }

  /// Méthode publique d'initialisation.
  /// Idempotente: peut être appelée plusieurs fois sans effet de bord.
  Future<void> initialize() async {
    await _initialize();
  }

  /// Met à jour l'URL de base et recrée l'instance Dio
  Future<void> updateBaseUrl(String newUrl) async {
    try {
      await ApiConfig.setBaseUrl(newUrl);

      // Mettre à jour l'URL dans Dio
      _dio.options.baseUrl = newUrl;

      // Réinitialiser le token pour forcer une nouvelle authentification
      _accessToken = null;

      _logger.d('URL du backend mise à jour: $newUrl');
    } catch (e) {
      _logger.e('Erreur mise à jour URL: $e');
      rethrow;
    }
  }

  /// Recharge l'URL du backend depuis le stockage (utile avant envoi patient).
  Future<void> ensureBaseUrlLoaded() async {
    if (!_initialized) await _initialize();
    final url = await ApiConfig.getBaseUrl();
    if (url.isNotEmpty && url != _dio.options.baseUrl) {
      _dio.options.baseUrl = url;
      if (kDebugMode) debugPrint('🔗 ApiService - URL rafraîchie: $url');
    }
  }

  /// Teste si le backend est joignable (GET /health, timeout 5 s).
  Future<bool> checkBackendReachable() async {
    if (!_initialized) await _initialize();
    return checkBackendReachableAt(_dio.options.baseUrl);
  }

  /// Teste si une URL de backend est joignable (sans modifier la config).
  /// Utile pour tester une URL avant de l'utiliser.
  static Future<bool> checkBackendReachableAt(
    String baseUrl, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final trimmed = baseUrl.trim();
    if (trimmed.isEmpty) return false;
    final healthUrl = Uri.parse(trimmed).resolve('/health').toString();
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: timeout,
        receiveTimeout: timeout,
      ));
      final r = await dio.get(healthUrl);
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Enregistre le token en mémoire pour l'ajouter aux requêtes suivantes.
  /// Le stockage persistant du token est géré ailleurs (AuthService).
  void setToken(String token) {
    _accessToken = token;
  }

  /// Retire le token en mémoire (utile au logout/changement d'URL backend).
  void clearToken() {
    _accessToken = null;
  }

  /// Extrait le message d'erreur d'une réponse FastAPI
  /// Gère les formats d'erreur FastAPI (validation, HTTPException, etc.)
  String _extractErrorMessage(dynamic errorData) {
    if (errorData == null) {
      return 'Erreur inconnue - aucune réponse du serveur';
    }

    // Si c'est une string directe
    if (errorData is String) {
      return errorData.isNotEmpty ? errorData : 'Erreur inconnue';
    }

    // Si c'est un Map
    if (errorData is Map<String, dynamic>) {
      // Format standard FastAPI: {"detail": "message"}
      if (errorData.containsKey('detail')) {
        final detail = errorData['detail'];

        // Si detail est null
        if (detail == null) {
          // Chercher d'autres champs
          if (errorData.containsKey('message')) {
            return errorData['message'].toString();
          }
          return 'Erreur serveur - détail manquant';
        }

        // Si detail est une liste (erreurs de validation FastAPI)
        if (detail is List) {
          if (detail.isEmpty) {
            return 'Erreur de validation';
          }
          // Prendre le premier message d'erreur
          final firstError = detail[0];
          if (firstError is Map<String, dynamic>) {
            final msg = firstError['msg'] ?? firstError['message'];
            final loc = firstError['loc'];
            if (msg != null && msg.toString().isNotEmpty) {
              if (loc != null && loc is List && loc.isNotEmpty) {
                return '${loc.last}: $msg';
              }
              return msg.toString();
            }
          }
          return detail[0].toString();
        }

        // Si detail est une string
        if (detail is String) {
          return detail.isNotEmpty ? detail : 'Erreur inconnue';
        }

        // Sinon, convertir en string
        final detailStr = detail.toString();
        return detailStr.isNotEmpty ? detailStr : 'Erreur inconnue';
      }

      // Autres formats possibles
      if (errorData.containsKey('message')) {
        final msg = errorData['message'];
        if (msg != null) {
          return msg.toString();
        }
      }
      if (errorData.containsKey('error')) {
        final err = errorData['error'];
        if (err != null) {
          return err.toString();
        }
      }

      // Si aucun champ standard, retourner la représentation JSON
      try {
        return 'Erreur: ${errorData.toString()}';
      } catch (e) {
        return 'Erreur inconnue - format de réponse non reconnu';
      }
    }

    // Autres types
    final errorStr = errorData.toString();
    return errorStr.isNotEmpty ? errorStr : 'Erreur lors de l\'inscription';
  }

  // ---------------------------------------------------------------------------
  // AUTH
  // ---------------------------------------------------------------------------
  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final response = await _dio.post(
        ApiConfig.login,
        data: {'email': email, 'password': password},
      );

      // Vérifier le status code
      if (response.statusCode != 200) {
        final errorMessage = response.data['detail'] ?? 'Erreur de connexion';
        throw Exception(errorMessage);
      }

      // Vérifier que la réponse contient un token
      if (response.data['access_token'] == null) {
        throw Exception('Token non reçu dans la réponse');
      }

      return response.data;
    } on DioException catch (e) {
      if (e.response != null) {
        final errorMessage = _extractErrorMessage(e.response!.data);
        _logger.e('Login error: $errorMessage');
        throw Exception(errorMessage);
      }

      // Détecter les erreurs de connexion réseau
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        final errorMsg = e.message?.toLowerCase() ?? '';
        final errorStr = e.toString().toLowerCase();

        // Erreur "No route to host" - appareil ne peut pas atteindre le serveur
        if (errorMsg.contains('no route to host') ||
            errorStr.contains('no route to host') ||
            errorMsg.contains('network is unreachable') ||
            errorStr.contains('network is unreachable')) {
          _logger.e('No route to host error: ${e.message}');
          throw Exception(
            '❌ Impossible d\'atteindre le serveur.\n\n'
            'Votre appareil ne peut pas se connecter au PC.\n\n'
            '✅ Vérifications à faire:\n'
            '1. Votre appareil mobile est-il sur le MÊME réseau WiFi que le PC?\n'
            '2. Le backend est-il démarré? (uvicorn app.main:app --reload --host 0.0.0.0 --port 8000)\n'
            '3. L\'adresse IP est-elle correcte?\n'
            '   → Vérifiez que l\'adresse du serveur (IP/port) est correcte\n'
            '   → Sur Windows: ipconfig | findstr IPv4 (chercher l\'interface Wi-Fi)\n'
            '4. Le firewall Windows autorise-t-il les connexions sur le port 8000?\n'
            '   → Ouvrir le port 8000 dans le firewall Windows\n\n'
            '📍 URL utilisée: ${e.requestOptions.baseUrl}',
          );
        }

        if (errorMsg.contains('connection refused') ||
            errorMsg.contains('failed to connect')) {
          _logger.e('Connection refused error: ${e.message}');
          throw Exception(
            'Impossible de se connecter au serveur.\n\n'
            'Vérifications à faire:\n'
            '1. Le backend est-il démarré? (uvicorn avec --host 0.0.0.0 --port 8000)\n'
            '2. Votre appareil est-il sur le même réseau WiFi que le PC?\n'
            '3. L\'adresse IP du serveur est-elle correcte?\n'
            '4. Le firewall Windows autorise-t-il les connexions sur le port 8000?\n\n'
            'URL utilisée: ${e.requestOptions.baseUrl}',
          );
        }
        if (errorMsg.contains('timeout') ||
            e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout) {
          _logger.e('Connection timeout error: ${e.message}');
          throw Exception(
            'Timeout de connexion au serveur.\n\n'
            'Le serveur met trop de temps à répondre (${ApiConfig.timeout.inSeconds} secondes).\n\n'
            'Vérifications:\n'
            '1. Le backend est-il démarré avec --host 0.0.0.0 (pas 127.0.0.1)?\n'
            '2. L\'URL (IP du PC) est-elle correcte? Même WiFi?\n'
            '3. Le firewall Windows autorise-t-il le port 8000?\n\n'
            'URL utilisée: ${e.requestOptions.baseUrl}',
          );
        }
      }

      _logger.e('Login error: ${e.message}');
      throw Exception('Erreur de connexion au serveur: ${e.message}');
    } catch (e) {
      _logger.e('Login error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    String? phone,
    String? rppsNumber,
    String? specialty,
    String? establishment,
  }) async {
    // S'assurer que l'initialisation est terminée
    if (!_initialized) {
      _logger.d('Register - Initialisation en cours...');
      await _initialize();
    }

    // Vérifier que baseUrl n'est pas vide et forcer l'initialisation si nécessaire
    if (_dio.options.baseUrl.isEmpty) {
      _logger.e('Register - baseUrl est vide, réinitialisation forcée...');
      _initialized =
          false; // Réinitialiser le flag pour forcer une nouvelle initialisation
      await _initialize();

      // Si toujours vide après réinitialisation, utiliser directement l'URL par défaut
      if (_dio.options.baseUrl.isEmpty) {
        final defaultUrl = ApiConfig.defaultUrl;
        _logger.w(
          'Register - baseUrl toujours vide, utilisation directe de l\'URL par défaut: $defaultUrl',
        );
        _dio.options.baseUrl = defaultUrl;
      }
    }

    // Log final pour vérification
    _logger.d('Register - baseUrl final: ${_dio.options.baseUrl}');

    try {
      // Rôle requis par le backend : médecin si RPPS/spécialité/établissement renseigné, sinon patient
      final isMedecin = (rppsNumber != null && rppsNumber.isNotEmpty) ||
          (specialty != null && specialty.isNotEmpty) ||
          (establishment != null && establishment.isNotEmpty);
      final role = isMedecin ? 'medecin' : 'patient';

      final data = {
        'email': email,
        'password': password,
        'first_name': firstName,
        'last_name': lastName,
        'role': role,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        if (rppsNumber != null && rppsNumber.isNotEmpty)
          'rpps_number': rppsNumber,
        if (specialty != null && specialty.isNotEmpty) 'specialty': specialty,
        if (establishment != null && establishment.isNotEmpty)
          'establishment': establishment,
      };

      // Vérification finale avant la requête
      if (_dio.options.baseUrl.isEmpty) {
        throw Exception(
          'Impossible de faire la requête : baseUrl est vide après initialisation',
        );
      }

      final fullUrl = '${_dio.options.baseUrl}${ApiConfig.register}';
      _logger.d('Register - Full URL: $fullUrl');
      _logger.d('Register - Request data: $data');
      _logger.d('Register - Base URL: ${_dio.options.baseUrl}');
      _logger.d('Register - Endpoint: ${ApiConfig.register}');
      debugPrint('📤 Register - Envoi vers: $fullUrl');

      final response = await _dio.post(
        ApiConfig.register,
        data: data,
        options: Options(
          headers: {
            'Content-Type': 'application/json; charset=utf-8',
            'Accept': 'application/json; charset=utf-8',
          },
        ),
      );
      _logger.d('Register response status: ${response.statusCode}');
      _logger.d('Register response data: ${response.data}');

      // Vérifier le status code
      if (response.statusCode != 201) {
        final errorMessage = _extractErrorMessage(response.data);
        _logger.e('Register error: $errorMessage');
        throw Exception(errorMessage);
      }

      return response.data;
    } on DioException catch (e) {
      _logger.e('Register DioException - Type: ${e.type}');
      _logger.e('Register DioException - Message: ${e.message}');
      _logger.e(
        'Register DioException - Request path: ${e.requestOptions.path}',
      );
      _logger.e(
        'Register DioException - Request baseUrl: ${e.requestOptions.baseUrl}',
      );

      if (e.response != null) {
        _logger.e('Register DioException - Status: ${e.response!.statusCode}');
        _logger.e('Register DioException - Data: ${e.response!.data}');
        final errorMessage = _extractErrorMessage(e.response!.data);
        _logger.e('Register error: $errorMessage');
        throw Exception(errorMessage);
      }

      // Pas de réponse du serveur
      String errorMessage = 'Erreur de connexion au serveur';
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        errorMessage =
            'Timeout de connexion. Le serveur met trop de temps à répondre.';
      } else if (e.type == DioExceptionType.connectionError) {
        errorMessage =
            'Impossible de se connecter au serveur. Vérifiez que le backend est démarré sur ${e.requestOptions.baseUrl}';
      } else if (e.type == DioExceptionType.unknown) {
        errorMessage =
            'Erreur inconnue lors de la connexion au serveur. Vérifiez votre connexion réseau et que le backend est accessible.';
      }

      _logger.e('Register error: $errorMessage');
      throw Exception(errorMessage);
    } catch (e) {
      _logger.e('Register error: $e');
      _logger.e('Register error stack: ${StackTrace.current}');
      rethrow;
    }
  }

  Future<User> getCurrentUser() async {
    try {
      final response = await _dio.get(ApiConfig.me);
      return User.fromJson(response.data);
    } catch (e) {
      _logger.e('Get current user error: $e');
      rethrow;
    }
  }

  // USERS
  Future<List<User>> getUsers({String? role, String? search}) async {
    try {
      final response = await _dio.get(
        ApiConfig.users,
        queryParameters: {
          if (role != null) 'role': role,
          if (search != null) 'search': search,
          'limit': 100,
        },
      );
      final raw = response.data;
      if (raw == null || raw is! Map) return <User>[];
      final users = raw['users'];
      if (users == null || users is! List) return <User>[];
      return users
          .map((json) => User.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _logger.e('Get users error: $e');
      rethrow;
    }
  }

  Future<User> getUser(String userId) async {
    try {
      final response = await _dio.get('${ApiConfig.users}/$userId');
      return User.fromJson(response.data);
    } catch (e) {
      _logger.e('Get user error: $e');
      rethrow;
    }
  }

  /// Crée un nouvel utilisateur (patient) - Admin uniquement
  Future<User> createUser({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String role,
    String? phone,
    String? bloodType,
    DateTime? dateOfBirth,
    String? address,
  }) async {
    try {
      final data = <String, dynamic>{
        'email': email,
        'password': password,
        'first_name': firstName,
        'last_name': lastName,
        'role': role,
        if (phone != null) 'phone': phone,
        if (bloodType != null) 'blood_type': bloodType,
        if (dateOfBirth != null)
          'date_of_birth': dateOfBirth.toIso8601String().split('T')[0],
        if (address != null) 'address': address,
      };

      final response = await _dio.post(ApiConfig.users, data: data);
      return User.fromJson(response.data);
    } catch (e) {
      _logger.e('Create user error: $e');
      rethrow;
    }
  }

  /// Met à jour un utilisateur
  Future<User> updateUser({
    required String userId,
    String? email,
    String? firstName,
    String? lastName,
    String? phone,
    String? bloodType,
    DateTime? dateOfBirth,
    String? address,
    bool? isActive,
  }) async {
    try {
      final data = <String, dynamic>{};
      if (email != null) data['email'] = email;
      if (firstName != null) data['first_name'] = firstName;
      if (lastName != null) data['last_name'] = lastName;
      if (phone != null) data['phone'] = phone;
      if (bloodType != null) data['blood_type'] = bloodType;
      if (dateOfBirth != null)
        data['date_of_birth'] = dateOfBirth.toIso8601String().split('T')[0];
      if (address != null) data['address'] = address;
      if (isActive != null) {
        data['is_active'] = isActive;
        _logger.i('🔧 Update user - isActive: $isActive');
      }

      _logger.i('🔧 Update user - Data envoyée: $data');
      final response = await _dio.put('${ApiConfig.users}/$userId', data: data);
      _logger.i('🔧 Update user - Réponse: ${response.data}');
      return User.fromJson(response.data);
    } catch (e) {
      _logger.e('Update user error: $e');
      rethrow;
    }
  }

  /// Suppression définitive (hard delete) d'un utilisateur.
  /// Endpoint: DELETE /api/v1/users/{user_id}/hard (admin uniquement).
  Future<void> deleteUserHard(String userId) async {
    try {
      _logger.i('🧨 Hard delete user: $userId');
      final response = await _dio.delete('${ApiConfig.users}/$userId/hard');

      if (response.statusCode != 204 && response.statusCode != 200) {
        final errorMessage = _extractErrorMessage(response.data);
        throw Exception(errorMessage);
      }
    } catch (e) {
      _logger.e('Hard delete user error: $e');
      if (e is DioException) {
        if (e.response != null) {
          final errorMessage = _extractErrorMessage(e.response!.data);
          throw Exception(errorMessage);
        }
        throw Exception('Erreur de connexion: ${e.message ?? "Erreur inconnue"}');
      }
      rethrow;
    }
  }

  // DEVICES
  Future<List<Device>> getDevices({String? status, String? patientId}) async {
    try {
      final response = await _dio.get(
        ApiConfig.devices,
        queryParameters: {
          if (status != null) 'status': status,
          if (patientId != null) 'patient_id': patientId,
          'limit': 100,
        },
      );
      // L'API retourne directement une liste, pas un objet avec une clé 'devices'
      final List devices = response.data is List ? response.data : [];
      return devices.map((json) => Device.fromJson(json)).toList();
    } catch (e) {
      _logger.e('Get devices error: $e');
      rethrow;
    }
  }

  /// Récupère un device par son adresse MAC Bluetooth
  Future<Device?> getDeviceByMacAddress(String macAddress) async {
    try {
      // Normaliser l'adresse MAC (enlever les espaces, garder le format avec :)
      final normalizedMac =
          macAddress.replaceAll(' ', '').replaceAll('-', ':').toUpperCase();
      // Encoder pour l'URL (les ":" deviennent %3A) pour éviter les erreurs de parsing
      final encodedMac = Uri.encodeComponent(normalizedMac);

      final response =
          await _dio.get('${ApiConfig.devices}/by-mac/$encodedMac');
      return Device.fromJson(response.data);
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 404) {
        _logger.w('Device avec MAC $macAddress non trouvé');
        return null;
      }
      _logger.e('Get device by MAC error: $e');
      return null;
    }
  }

  /// Enregistre un pansement par son adresse MAC (création en base si absent).
  /// Lance une exception en cas d'erreur (réseau, 401, 404, etc.) pour affichage à l'utilisateur.
  Future<Device> registerDeviceByMac(String macAddress) async {
    final normalizedMac =
        macAddress.replaceAll(' ', '').replaceAll('-', ':').toUpperCase();
    final response = await _dio.post(
      '${ApiConfig.devices}/register-by-mac',
      data: {'mac_address': normalizedMac},
    );
    return Device.fromJson(response.data);
  }

  Future<Device> getDevice(String deviceId) async {
    try {
      final response = await _dio.get('${ApiConfig.devices}/$deviceId');
      return Device.fromJson(response.data);
    } catch (e) {
      _logger.e('Get device error: $e');
      rethrow;
    }
  }

  Future<Device> updateDevice(String deviceId, {String? status}) async {
    try {
      final data = <String, dynamic>{};
      if (status != null) {
        data['status'] = status;
      }
      _logger.d('PATCH ${ApiConfig.devices}/$deviceId with data: $data');
      final response = await _dio.patch(
        '${ApiConfig.devices}/$deviceId',
        data: data,
      );
      _logger.d('Update device response: ${response.statusCode}');
      if (response.statusCode != 200) {
        throw Exception('Erreur ${response.statusCode}: ${response.data}');
      }
      return Device.fromJson(response.data);
    } catch (e) {
      _logger.e('Update device error: $e');
      if (e is DioException) {
        final statusCode = e.response?.statusCode;
        // Gérer le cas où data peut être un dict ou une string
        String errorMessage = e.message ?? 'Erreur inconnue';
        if (e.response?.data != null) {
          if (e.response!.data is Map) {
            errorMessage = e.response!.data['detail'] ??
                e.response!.data['message'] ??
                errorMessage;
          } else if (e.response!.data is String) {
            errorMessage = e.response!.data;
          }
        }
        throw Exception('Erreur ${statusCode ?? 'inconnu'}: $errorMessage');
      }
      rethrow;
    }
  }

  /// Un patient s'assigne un pansement à lui-même (pour que les alertes soient créées côté backend).
  Future<Device> assignMyDevice(String deviceId) async {
    try {
      // URL complète pour éviter les soucis de concaténation Dio (path avec / peut ignorer baseUrl)
      final base = _dio.options.baseUrl.endsWith('/')
          ? _dio.options.baseUrl
          : '${_dio.options.baseUrl}/';
      final url = '${base}devices/patient/assign-device';
      if (kDebugMode) debugPrint('📤 POST assign-device: $url');
      final response = await _dio.post(
        url,
        data: {'device_id': deviceId},
      );
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Erreur ${response.statusCode}: ${response.data}');
      }
      return Device.fromJson(response.data);
    } catch (e) {
      _logger.e('Assign my device error: $e');
      if (e is DioException) {
        final statusCode = e.response?.statusCode;
        final errorMessage = _extractErrorMessage(e.response?.data);
        if (statusCode == 404) {
          _logger.w(
              'Route assign-device 404 - vérifier que le backend est à jour (BE_pansement_connecte)');
        }
        throw Exception('Erreur ${statusCode ?? 'inconnu'}: $errorMessage');
      }
      rethrow;
    }
  }

  Future<Device> assignDeviceToPatient(
    String deviceId,
    String patientId,
  ) async {
    try {
      _logger.d(
        'POST ${ApiConfig.devices}/$deviceId/assign with patient_id: $patientId',
      );
      final response = await _dio.post(
        '${ApiConfig.devices}/$deviceId/assign',
        data: {'patient_id': patientId},
      );
      _logger.d('Assign device response: ${response.statusCode}');
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Erreur ${response.statusCode}: ${response.data}');
      }
      return Device.fromJson(response.data);
    } catch (e) {
      _logger.e('Assign device error: $e');
      if (e is DioException) {
        final statusCode = e.response?.statusCode;
        final errorMessage = e.response?.data?['detail'] ?? e.message;
        throw Exception('Erreur ${statusCode ?? 'inconnu'}: $errorMessage');
      }
      rethrow;
    }
  }

  Future<void> unassignDevice(String deviceId) async {
    try {
      _logger.d('DELETE ${ApiConfig.devices}/$deviceId/assign');
      final response = await _dio.delete(
        '${ApiConfig.devices}/$deviceId/assign',
      );
      _logger.d('Unassign device response: ${response.statusCode}');
      if (response.statusCode != 204 && response.statusCode != 200) {
        final errorMessage = _extractErrorMessage(response.data);
        throw Exception(errorMessage);
      }
    } catch (e) {
      _logger.e('Unassign device error: $e');
      if (e is DioException) {
        // Gérer les erreurs de connexion réseau
        if (e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.unknown) {
          String errorMessage = 'Impossible de se connecter au serveur.';
          if (e.message?.contains('No route to host') == true) {
            errorMessage =
                'Impossible d\'atteindre le serveur. Vérifiez votre connexion réseau et que le backend est accessible sur ${_dio.options.baseUrl}';
          } else if (e.type == DioExceptionType.connectionTimeout) {
            errorMessage =
                'Timeout de connexion. Le serveur met trop de temps à répondre.';
          }
          throw Exception(errorMessage);
        }

        // Gérer les erreurs HTTP
        if (e.response != null) {
          final errorMessage = _extractErrorMessage(e.response!.data);
          throw Exception(errorMessage);
        }

        throw Exception(
          'Erreur de connexion: ${e.message ?? "Erreur inconnue"}',
        );
      }
      rethrow;
    }
  }

  // PATIENT-MEDECIN ASSIGNMENT (Admin only)
  /// Assigner un patient à un médecin (POST /api/v1/comments/assign-patient)
  Future<Map<String, dynamic>> assignPatientToMedecin({
    required String patientId,
    required String medecinId,
    bool isPrimary = true,
    String? notes,
  }) async {
    try {
      final url = '${ApiConfig.comments}/assign-patient';
      _logger.d('POST $url (patient_id: $patientId, medecin_id: $medecinId)');
      final response = await _dio.post(
        url,
        data: {
          'patient_id': patientId,
          'medecin_id': medecinId,
        },
      );
      _logger.d('Assign patient to medecin response: ${response.statusCode}');
      if (response.statusCode != 201) {
        final errorMessage = _extractErrorMessage(response.data);
        throw Exception(errorMessage);
      }
      return response.data;
    } catch (e) {
      _logger.e('Assign patient to medecin error: $e');
      if (e is DioException) {
        // Gérer les erreurs 404 (Not Found)
        if (e.response?.statusCode == 404) {
          throw Exception(
            'Endpoint non trouvé. Vérifiez que le backend a été redémarré après l\'ajout de l\'endpoint /api/v1/users/{patient_id}/assign-medecin',
          );
        }

        if (e.response != null) {
          final errorMessage = _extractErrorMessage(e.response!.data);
          throw Exception(errorMessage);
        }

        // Gérer les erreurs de connexion réseau
        if (e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.unknown) {
          String errorMessage = 'Impossible de se connecter au serveur.';
          if (e.message?.contains('No route to host') == true) {
            errorMessage =
                'Impossible d\'atteindre le serveur. Vérifiez votre connexion réseau et que le backend est accessible sur ${_dio.options.baseUrl}';
          } else if (e.type == DioExceptionType.connectionTimeout) {
            errorMessage =
                'Timeout de connexion. Le serveur met trop de temps à répondre.';
          }
          throw Exception(errorMessage);
        }

        throw Exception(
          'Erreur de connexion: ${e.message ?? "Erreur inconnue"}',
        );
      }
      rethrow;
    }
  }

  /// Retirer l'assignation d'un patient à un médecin
  Future<void> unassignPatientFromMedecin({
    required String patientId,
    required String medecinId,
  }) async {
    try {
      _logger.d(
        'DELETE ${ApiConfig.users}/$patientId/assign-medecin/$medecinId',
      );
      final response = await _dio.delete(
        '${ApiConfig.users}/$patientId/assign-medecin/$medecinId',
      );
      _logger.d(
        'Unassign patient from medecin response: ${response.statusCode}',
      );
      if (response.statusCode != 204 && response.statusCode != 200) {
        final errorMessage = _extractErrorMessage(response.data);
        throw Exception(errorMessage);
      }
    } catch (e) {
      _logger.e('Unassign patient from medecin error: $e');
      if (e is DioException) {
        if (e.response != null) {
          final errorMessage = _extractErrorMessage(e.response!.data);
          throw Exception(errorMessage);
        }
        throw Exception(
          'Erreur de connexion: ${e.message ?? "Erreur inconnue"}',
        );
      }
      rethrow;
    }
  }

  /// Récupérer la liste des patients assignés à un médecin
  Future<List<User>> getMedecinPatients(String medecinId) async {
    try {
      final url = '${ApiConfig.users}/$medecinId/patients';
      _logger.d('GET $url');
      final response = await _dio.get(url);
      _logger.d('Get medecin patients response: ${response.statusCode}');
      if (response.statusCode != 200) {
        final errorMessage = _extractErrorMessage(response.data);
        throw Exception(errorMessage);
      }
      final List users = response.data['users'];
      return users.map((json) => User.fromJson(json)).toList();
    } catch (e) {
      _logger.e('Get medecin patients error: $e');
      if (e is DioException) {
        if (e.response != null) {
          final errorMessage = _extractErrorMessage(e.response!.data);
          throw Exception(errorMessage);
        }
        throw Exception(
          'Erreur de connexion: ${e.message ?? "Erreur inconnue"}',
        );
      }
      rethrow;
    }
  }

  /// Récupérer le médecin assigné à un patient
  Future<Map<String, dynamic>?> getPatientMedecin(String patientId) async {
    try {
      final url = '${ApiConfig.users}/$patientId/medecin';
      _logger.d('GET $url');
      final response = await _dio.get(url);
      _logger.d('Get patient medecin response: ${response.statusCode}');
      if (response.statusCode != 200) {
        final errorMessage = _extractErrorMessage(response.data);
        throw Exception(errorMessage);
      }
      final data = response.data;
      // Le backend retourne {"medecin": None, ...} quand aucun médecin n'est assigné
      // On retourne quand même les données pour que l'UI puisse afficher "Aucun médecin assigné"
      if (data is Map<String, dynamic> && data['medecin'] == null) {
        // Aucun médecin assigné - retourner null pour que l'UI affiche "Aucun médecin assigné"
        return null;
      }
      return data;
    } catch (e) {
      _logger.e('Get patient medecin error: $e');
      if (e is DioException) {
        if (e.response?.statusCode == 404) {
          // 404 peut signifier soit "pas de médecin assigné", soit "endpoint non trouvé"
          // Si c'est une erreur de détail, c'est probablement "pas de médecin assigné"
          final detail = e.response?.data?['detail'] as String?;
          if (detail != null && detail.contains('Patient non trouvé')) {
            // Patient non trouvé - erreur réelle
            throw Exception('Patient non trouvé');
          }
          // Sinon, considérer comme "pas de médecin assigné" ou "endpoint non disponible"
          // Retourner null pour éviter les erreurs répétées
          return null;
        }
        if (e.response?.statusCode == 500) {
          // Erreur serveur - loguer l'erreur mais retourner null pour éviter de bloquer l'UI
          _logger.e(
            'Erreur serveur 500 lors de la récupération du médecin: ${e.response?.data}',
          );
          return null;
        }
        if (e.response != null) {
          final errorMessage = _extractErrorMessage(e.response!.data);
          throw Exception(errorMessage);
        }
        throw Exception(
          'Erreur de connexion: ${e.message ?? "Erreur inconnue"}',
        );
      }
      rethrow;
    }
  }

  // MEASUREMENTS
  Future<Measurement> createMeasurement({
    required String deviceId,
    required String measurementType,
    required double value,
    required String unit,
    int? qualityScore,
    String? patientId,
    double? freqHz,
    double? phaseDeg,
  }) async {
    try {
      final response = await _dio.post(
        ApiConfig.measurements,
        data: {
          'device_id': deviceId,
          'measurement_type': measurementType,
          'value': value,
          'unit': unit,
          if (qualityScore != null) 'quality_score': qualityScore,
          if (patientId != null && patientId.isNotEmpty)
            'patient_id': patientId,
          if (freqHz != null) 'freq_hz': freqHz,
          if (phaseDeg != null) 'phase_deg': phaseDeg,
        },
      );
      return Measurement.fromJson(response.data);
    } catch (e) {
      _logger.e('Create measurement error: $e');
      rethrow;
    }
  }

  Future<List<Measurement>> getPatientMeasurements(
    String patientId, {
    String? measurementType,
    int limit = 50,
  }) async {
    try {
      final response = await _dio.get(
        '${ApiConfig.measurements}/patient/$patientId',
        queryParameters: {
          if (measurementType != null) 'measurement_type': measurementType,
          'limit': limit,
        },
      );
      final raw = (response.data is Map ? response.data['measurements'] : null);
      final List measurements = raw is List ? raw : <dynamic>[];
      return measurements.map((json) => Measurement.fromJson(json)).toList();
    } catch (e) {
      _logger.e('Get measurements error: $e');
      rethrow;
    }
  }

  Future<Measurement> getLatestMeasurement(
    String patientId, {
    String? measurementType,
  }) async {
    try {
      final response = await _dio.get(
        '${ApiConfig.measurements}/latest/$patientId',
        queryParameters: {
          if (measurementType != null) 'measurement_type': measurementType,
        },
      );
      return Measurement.fromJson(response.data);
    } catch (e) {
      _logger.e('Get latest measurement error: $e');
      rethrow;
    }
  }

  Future<Measurement> updateMeasurement(
    String measurementId,
    double value,
  ) async {
    try {
      final response = await _dio.put(
        '${ApiConfig.measurements}/$measurementId',
        data: {'value': value},
      );
      return Measurement.fromJson(response.data);
    } catch (e) {
      _logger.e('Update measurement error: $e');
      rethrow;
    }
  }

  /// Supprime une mesure (donnée brute). Admin uniquement. 204 No Content en cas de succès.
  Future<void> deleteMeasurement(String measurementId) async {
    try {
      await _dio.delete('${ApiConfig.measurements}/$measurementId');
    } catch (e) {
      _logger.e('Delete measurement error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getPatientStats(
    String patientId, {
    int days = 7,
  }) async {
    try {
      final response = await _dio.get(
        '${ApiConfig.measurements}/stats/$patientId',
        queryParameters: {'days': days},
      );
      return response.data;
    } catch (e) {
      _logger.e('Get stats error: $e');
      rethrow;
    }
  }

  /// Nombre de mesures enregistrées aujourd'hui (pour dashboard admin / médecin).
  Future<int> getTodayMeasurementsCount() async {
    try {
      final response = await _dio.get('${ApiConfig.measurements}/today-count');
      final count = response.data is Map ? response.data['count'] : null;
      return (count is int) ? count : (count is num ? count.toInt() : 0);
    } catch (e) {
      _logger.e('Get today measurements count error: $e');
      return 0;
    }
  }

  // ALERTS
  Future<Map<String, dynamic>> getAlerts({
    String? severity,
    String? alertType,
    bool unacknowledgedOnly = false,
    int limit = 50,
  }) async {
    try {
      // Timeout plus court pour les alertes (10 secondes au lieu de 30)
      final response = await _dio.get(
        ApiConfig.alerts,
        queryParameters: {
          if (severity != null) 'severity': severity,
          if (alertType != null) 'alert_type': alertType,
          if (unacknowledgedOnly) 'unacknowledged_only': true,
          'limit': limit,
        },
        options: Options(
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
          // Ne pas lever d'exception pour les erreurs 500, on les gère manuellement
          validateStatus: (status) {
            return status != null &&
                status < 600; // Accepter tous les codes < 600
          },
        ),
      );

      const fallback = {
        'alerts': [],
        'total': 0,
        'unacknowledged': 0,
        'critical': 0
      };
      if (response.statusCode != 200) {
        if (response.statusCode == 500) {
          _logger.w('Erreur 500 lors de la récupération des alertes');
        } else if (response.statusCode == 403) {
          _logger.w('Accès refusé (403) pour les alertes');
        }
        return Map<String, dynamic>.from(fallback);
      }
      final data = response.data;
      if (data is! Map || !data.containsKey('alerts')) {
        return Map<String, dynamic>.from(fallback);
      }
      return Map<String, dynamic>.from(Map.from(data));
    } catch (e) {
      _logger.e('Get alerts error: $e');
      // Retourner une structure vide au lieu de rethrow pour ne pas bloquer l'app
      if (e is DioException) {
        // Gérer les timeouts et les erreurs 500
        if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.sendTimeout ||
            e.response?.statusCode == 500) {
          _logger.w(
            'Erreur lors de la récupération des alertes (timeout ou 500), retour d\'une liste vide',
          );
          return {'alerts': [], 'total': 0, 'unacknowledged': 0, 'critical': 0};
        }
      }
      // Pour les autres erreurs, retourner aussi une structure vide
      return {'alerts': [], 'total': 0, 'unacknowledged': 0, 'critical': 0};
    }
  }

  Future<Map<String, dynamic>> getPatientAlerts(
    String patientId, {
    String? severity,
    bool unacknowledgedOnly = false,
    int limit = 50,
  }) async {
    try {
      // Timeout plus court pour les alertes (10 secondes au lieu de 30)
      final response = await _dio.get(
        '${ApiConfig.alerts}/patient/$patientId',
        queryParameters: {
          if (severity != null) 'severity': severity,
          if (unacknowledgedOnly) 'unacknowledged_only': true,
          'limit': limit,
        },
        options: Options(
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
        ),
      );
      return response.data;
    } catch (e) {
      _logger.e('Get patient alerts error: $e');
      // Retourner une structure vide au lieu de rethrow pour ne pas bloquer l'app
      if (e is DioException &&
          (e.type == DioExceptionType.connectionTimeout ||
              e.type == DioExceptionType.receiveTimeout ||
              e.type == DioExceptionType.sendTimeout)) {
        _logger.w(
          'Timeout lors de la récupération des alertes du patient, retour d\'une liste vide',
        );
        return {'alerts': [], 'total': 0, 'unacknowledged': 0, 'critical': 0};
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> acknowledgeAlert(
    String alertId, {
    String? note,
  }) async {
    try {
      final response = await _dio.put(
        '${ApiConfig.alerts}/$alertId/acknowledge',
        data: note != null ? {'note': note} : {},
      );
      return response.data;
    } catch (e) {
      _logger.e('Acknowledge alert error: $e');
      rethrow;
    }
  }

  /// Supprime une alerte (notification). 204 No Content en cas de succès.
  /// Utilise validateStatus pour n'accepter que 204/200 ; sinon Dio considérerait 404 comme succès (validateStatus global < 500).
  Future<void> deleteAlert(String alertId) async {
    try {
      await _dio.delete(
        '${ApiConfig.alerts}/$alertId',
        options: Options(
          validateStatus: (status) => status == 204 || status == 200,
        ),
      );
    } catch (e) {
      _logger.e('Delete alert error: $e');
      rethrow;
    }
  }

  // USER PROFILE
  Future<User> updateProfile({
    String? email,
    String? firstName,
    String? lastName,
    String? phone,
    String? bloodType,
  }) async {
    try {
      final currentUser = await getCurrentUser();
      final data = <String, dynamic>{};
      if (email != null) data['email'] = email;
      if (firstName != null) data['first_name'] = firstName;
      if (lastName != null) data['last_name'] = lastName;
      if (phone != null) data['phone'] = phone;
      if (bloodType != null) data['blood_type'] = bloodType;

      final response = await _dio.put(
        '${ApiConfig.users}/${currentUser.id}',
        data: data,
      );
      return User.fromJson(response.data);
    } catch (e) {
      _logger.e('Update profile error: $e');
      rethrow;
    }
  }

  // 2FA
  Future<User> toggleTwoFactorAuth(bool enabled) async {
    try {
      final currentUser = await getCurrentUser();
      final response = await _dio.put(
        '${ApiConfig.users}/${currentUser.id}',
        data: {'two_factor_enabled': enabled},
      );
      return User.fromJson(response.data);
    } catch (e) {
      _logger.e('Toggle 2FA error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    try {
      final response = await _dio.post(
        ApiConfig.changePassword,
        data: {'old_password': oldPassword, 'new_password': newPassword},
      );
      return response.data;
    } catch (e) {
      _logger.e('Change password error: $e');
      rethrow;
    }
  }

  // ===========================================================================
  // COMMENTS
  // ===========================================================================

  /// Récupère les commentaires d'un patient
  Future<List<Comment>> getPatientComments(
    String patientId, {
    int skip = 0,
    int limit = 50,
  }) async {
    try {
      final response = await _dio.get(
        '${ApiConfig.comments}/patient/$patientId', // Route corrigée : /patient/ au lieu de /patients/
        queryParameters: {'skip': skip, 'limit': limit},
      );

      final data = response.data;
      if (data is Map<String, dynamic> && data['comments'] is List) {
        return (data['comments'] as List)
            .map((json) => Comment.fromJson(json))
            .toList();
      }
      throw Exception('Réponse invalide du serveur');
    } on DioException catch (e) {
      String errorMessage;
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout) {
        errorMessage =
            'Impossible de se connecter au serveur. Vérifiez votre connexion internet et l\'URL du backend.';
      } else if (e.response != null) {
        final detail = e.response!.data['detail'];
        if (detail is String) {
          errorMessage = detail;
        } else if (detail is Map && detail.containsKey('message')) {
          errorMessage = detail['message'];
        } else {
          errorMessage = 'Erreur serveur: ${e.response!.statusCode}';
        }
      } else {
        errorMessage = 'Erreur inattendue: ${e.message}';
      }
      _logger.e('Get comments error: $errorMessage');
      throw Exception(errorMessage);
    } catch (e) {
      _logger.e('Get comments error: $e');
      rethrow;
    }
  }

  /// Crée un commentaire pour un patient (médecin/admin)
  Future<Comment> createComment({
    required String patientId,
    required String commentText,
    String? measurementId,
  }) async {
    try {
      final payload = {
        'patient_id': patientId,
        'comment_text': commentText,
        if (measurementId != null) 'measurement_id': measurementId,
      };

      final response = await _dio.post(
        ApiConfig.comments, // POST /api/v1/comments (pas /patients/{id})
        data: payload,
      );

      // La réponse contient {success: true, comment: {...}}
      final data = response.data;
      if (data is Map<String, dynamic> && data['comment'] != null) {
        return Comment.fromJson(data['comment'] as Map<String, dynamic>);
      }
      throw Exception('Réponse invalide du serveur');
    } on DioException catch (e) {
      String errorMessage;
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout) {
        errorMessage =
            'Impossible de se connecter au serveur. Vérifiez votre connexion internet et l\'URL du backend.';
      } else if (e.response != null) {
        final data = e.response!.data;
        final detail = data is Map ? data['detail'] : null;
        if (detail is String) {
          errorMessage = detail;
        } else if (detail is List && detail.isNotEmpty) {
          // Erreur de validation FastAPI (422)
          final first = detail.first;
          if (first is Map && first['msg'] != null) {
            errorMessage = first['msg'] as String;
          } else {
            errorMessage = 'Données invalides (${e.response!.statusCode})';
          }
        } else if (detail is Map && detail.containsKey('message')) {
          errorMessage = detail['message'] as String;
        } else {
          errorMessage = 'Erreur serveur: ${e.response!.statusCode}';
        }
      } else {
        errorMessage = 'Erreur inattendue: ${e.message}';
      }
      _logger.e('Create comment error: $errorMessage');
      throw Exception(errorMessage);
    } catch (e) {
      _logger.e('Create comment error: $e');
      rethrow;
    }
  }

  /// Met à jour un commentaire (médecin/admin)
  Future<Comment> updateComment({
    required String commentId,
    required String commentText,
  }) async {
    try {
      final response = await _dio.put(
        '${ApiConfig.comments}/$commentId',
        data: {'comment_text': commentText},
      );

      // La réponse contient directement le commentaire
      return Comment.fromJson(response.data);
    } on DioException catch (e) {
      String errorMessage;
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout) {
        errorMessage =
            'Impossible de se connecter au serveur. Vérifiez votre connexion internet et l\'URL du backend.';
      } else if (e.response != null) {
        final detail = e.response!.data['detail'];
        if (detail is String) {
          errorMessage = detail;
        } else if (detail is Map && detail.containsKey('message')) {
          errorMessage = detail['message'];
        } else {
          errorMessage = 'Erreur serveur: ${e.response!.statusCode}';
        }
      } else {
        errorMessage = 'Erreur inattendue: ${e.message}';
      }
      _logger.e('Update comment error: $errorMessage');
      throw Exception(errorMessage);
    } catch (e) {
      _logger.e('Update comment error: $e');
      rethrow;
    }
  }

  /// Supprime un commentaire (médecin/admin)
  Future<void> deleteComment(String commentId) async {
    try {
      await _dio.delete('${ApiConfig.comments}/$commentId');
    } on DioException catch (e) {
      String errorMessage;
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout) {
        errorMessage =
            'Impossible de se connecter au serveur. Vérifiez votre connexion internet et l\'URL du backend.';
      } else if (e.response != null) {
        final detail = e.response!.data['detail'];
        if (detail is String) {
          errorMessage = detail;
        } else if (detail is Map && detail.containsKey('message')) {
          errorMessage = detail['message'];
        } else {
          errorMessage = 'Erreur serveur: ${e.response!.statusCode}';
        }
      } else {
        errorMessage = 'Erreur inattendue: ${e.message}';
      }
      _logger.e('Delete comment error: $errorMessage');
      throw Exception(errorMessage);
    } catch (e) {
      _logger.e('Delete comment error: $e');
      rethrow;
    }
  }

  /// Récupère le nombre de commentaires non lus d'un patient
  Future<int> getUnreadCommentsCount(String patientId) async {
    try {
      final response = await _dio.get(
        '${ApiConfig.comments}/unread/patient/$patientId',
      );

      final data = response.data;
      if (data is Map<String, dynamic> && data['unread_count'] != null) {
        final v = data['unread_count'];
        if (v is int) return v;
        if (v is String) return int.tryParse(v) ?? 0;
      }
      return 0;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout) {
        _logger.e('Get unread comments count: connexion impossible');
      } else if (e.response != null) {
        final data = e.response!.data;
        String? msg;
        if (data is Map<String, dynamic> && data['detail'] != null) {
          final d = data['detail'];
          if (d is String)
            msg = d;
          else if (d is List && d.isNotEmpty) msg = d.first.toString();
        }
        _logger.e(
            'Get unread comments count error: ${msg ?? e.response!.statusCode}');
      }
      return 0;
    } catch (e) {
      _logger.e('Get unread comments count error: $e');
      return 0;
    }
  }

  /// Marque un commentaire comme lu (patient uniquement)
  Future<void> markCommentAsRead(String commentId) async {
    try {
      await _dio.put('${ApiConfig.comments}/$commentId/read');
    } on DioException catch (e) {
      String errorMessage;
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout) {
        errorMessage =
            'Impossible de se connecter au serveur. Vérifiez votre connexion internet et l\'URL du backend.';
      } else if (e.response != null) {
        final detail = e.response!.data['detail'];
        if (detail is String) {
          errorMessage = detail;
        } else if (detail is Map && detail.containsKey('message')) {
          errorMessage = detail['message'];
        } else {
          errorMessage = 'Erreur serveur: ${e.response!.statusCode}';
        }
      } else {
        errorMessage = 'Erreur inattendue: ${e.message}';
      }
      _logger.e('Mark comment as read error: $errorMessage');
      throw Exception(errorMessage);
    } catch (e) {
      _logger.e('Mark comment as read error: $e');
      rethrow;
    }
  }
}
