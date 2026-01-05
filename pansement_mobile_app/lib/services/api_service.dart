import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import '../config/api_config.dart';
import '../models/user.dart';
import '../models/device.dart';
import '../models/measurement.dart';

/// Service API pour communiquer avec le backend FastAPI
class ApiService {
  final Dio _dio;
  final Logger _logger = Logger();
  String? _accessToken;

  ApiService()
      : _dio = Dio(BaseOptions(
          baseUrl: ApiConfig.baseUrl,
          connectTimeout: ApiConfig.timeout,
          receiveTimeout: ApiConfig.timeout,
          headers: {
            'Content-Type': 'application/json; charset=utf-8',
            'Accept': 'application/json; charset=utf-8',
          },
          // Options pour Flutter Web
          validateStatus: (status) => status! < 500,
          // Forcer l'encodage UTF-8
          responseType: ResponseType.json,
        )) {
    // Interceptor pour ajouter le token à chaque requête
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (_accessToken != null) {
          options.headers['Authorization'] = 'Bearer $_accessToken';
        }
        _logger.d('Request: ${options.method} ${options.path}');
        return handler.next(options);
      },
      onError: (error, handler) {
        _logger.e('Error: ${error.response?.statusCode} ${error.message}');
        _logger.e('Error details: ${error.toString()}');
        return handler.next(error);
      },
    ));
  }

  void setToken(String token) {
    _accessToken = token;
  }

  void clearToken() {
    _accessToken = null;
  }

  // AUTH
  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final response = await _dio.post(ApiConfig.login, data: {
        'email': email,
        'password': password,
      });

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
        final errorMessage =
            e.response!.data['detail'] ?? 'Erreur de connexion';
        _logger.e('Login error: $errorMessage');
        throw Exception(errorMessage);
      }
      _logger.e('Login error: ${e.message}');
      throw Exception('Erreur de connexion au serveur');
    } catch (e) {
      _logger.e('Login error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String role,
    required String firstName,
    required String lastName,
    String? phone,
    String? rppsNumber,
    String? specialty,
    String? establishment,
  }) async {
    try {
      final data = {
        'email': email,
        'password': password,
        'role': role,
        'first_name': firstName,
        'last_name': lastName,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        if (rppsNumber != null && rppsNumber.isNotEmpty)
          'rpps_number': rppsNumber,
        if (specialty != null && specialty.isNotEmpty) 'specialty': specialty,
        if (establishment != null && establishment.isNotEmpty)
          'establishment': establishment,
      };

      final response = await _dio.post(ApiConfig.register, data: data);

      // Vérifier le status code
      if (response.statusCode != 201) {
        final errorMessage =
            response.data['detail'] ?? 'Erreur lors de l\'inscription';
        throw Exception(errorMessage);
      }

      return response.data;
    } on DioException catch (e) {
      if (e.response != null) {
        final errorMessage =
            e.response!.data['detail'] ?? 'Erreur lors de l\'inscription';
        _logger.e('Register error: $errorMessage');
        throw Exception(errorMessage);
      }
      _logger.e('Register error: ${e.message}');
      throw Exception('Erreur de connexion au serveur');
    } catch (e) {
      _logger.e('Register error: $e');
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
      final List users = response.data['users'];
      return users.map((json) => User.fromJson(json)).toList();
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
      final response =
          await _dio.patch('${ApiConfig.devices}/$deviceId', data: data);
      _logger.d('Update device response: ${response.statusCode}');
      if (response.statusCode != 200) {
        throw Exception('Erreur ${response.statusCode}: ${response.data}');
      }
      return Device.fromJson(response.data);
    } catch (e) {
      _logger.e('Update device error: $e');
      if (e is DioException) {
        final statusCode = e.response?.statusCode;
        final errorMessage = e.response?.data?['detail'] ?? e.message;
        throw Exception('Erreur ${statusCode ?? 'inconnu'}: $errorMessage');
      }
      rethrow;
    }
  }

  Future<Device> assignDeviceToPatient(
      String deviceId, String patientId) async {
    try {
      _logger.d(
          'POST ${ApiConfig.devices}/$deviceId/assign with patient_id: $patientId');
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
      final response =
          await _dio.delete('${ApiConfig.devices}/$deviceId/assign');
      _logger.d('Unassign device response: ${response.statusCode}');
      if (response.statusCode != 204 && response.statusCode != 200) {
        throw Exception('Erreur ${response.statusCode}: ${response.data}');
      }
    } catch (e) {
      _logger.e('Unassign device error: $e');
      if (e is DioException) {
        final statusCode = e.response?.statusCode;
        final errorMessage = e.response?.data?['detail'] ?? e.message;
        throw Exception('Erreur ${statusCode ?? 'inconnu'}: $errorMessage');
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
      final List measurements = response.data['measurements'];
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

  // ALERTS
  Future<Map<String, dynamic>> getAlerts({
    String? severity,
    String? alertType,
    bool unacknowledgedOnly = false,
    int limit = 50,
  }) async {
    try {
      final response = await _dio.get(
        ApiConfig.alerts,
        queryParameters: {
          if (severity != null) 'severity': severity,
          if (alertType != null) 'alert_type': alertType,
          if (unacknowledgedOnly) 'unacknowledged_only': true,
          'limit': limit,
        },
      );
      return response.data;
    } catch (e) {
      _logger.e('Get alerts error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getPatientAlerts(
    String patientId, {
    String? severity,
    bool unacknowledgedOnly = false,
    int limit = 50,
  }) async {
    try {
      final response = await _dio.get(
        '${ApiConfig.alerts}/patient/$patientId',
        queryParameters: {
          if (severity != null) 'severity': severity,
          if (unacknowledgedOnly) 'unacknowledged_only': true,
          'limit': limit,
        },
      );
      return response.data;
    } catch (e) {
      _logger.e('Get patient alerts error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> acknowledgeAlert(String alertId,
      {String? note}) async {
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
        data: {
          'old_password': oldPassword,
          'new_password': newPassword,
        },
      );
      return response.data;
    } catch (e) {
      _logger.e('Change password error: $e');
      rethrow;
    }
  }
}
