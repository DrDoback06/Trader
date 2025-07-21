import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:crypto/crypto.dart';
import 'dart:math';

import '../config.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final Logger _logger = Logger();
  
  String? _accessToken;
  String? _refreshToken;
  DateTime? _tokenExpiry;
  User? _currentUser;
  Timer? _refreshTimer;

  /// Stream of authentication state changes
  final StreamController<AuthState> _authStateController = StreamController<AuthState>.broadcast();
  Stream<AuthState> get authStateStream => _authStateController.stream;

  /// Current authentication state
  AuthState get currentState {
    if (_accessToken == null || _currentUser == null) {
      return AuthState.unauthenticated;
    }
    
    if (_tokenExpiry != null && DateTime.now().isAfter(_tokenExpiry!)) {
      return AuthState.tokenExpired;
    }
    
    return AuthState.authenticated;
  }

  /// Current authenticated user
  User? get currentUser => _currentUser;

  /// Access token for API requests
  String? get accessToken => _accessToken;

  /// Initialize auth service and check for existing session
  Future<void> initialize() async {
    try {
      _logger.i('Initializing authentication service');
      
      // Try to restore session from secure storage
      await _restoreSession();
      
      // Start token refresh timer if authenticated
      if (currentState == AuthState.authenticated) {
        _startTokenRefreshTimer();
        _authStateController.add(AuthState.authenticated);
      } else {
        _authStateController.add(AuthState.unauthenticated);
      }
      
    } catch (e) {
      _logger.e('Failed to initialize auth service: $e');
      _authStateController.add(AuthState.unauthenticated);
    }
  }

  /// Login with username and password
  Future<LoginResult> login({
    required String username,
    required String password,
    String? mfaCode,
  }) async {
    try {
      _logger.i('Attempting login for user: $username');
      
      // Hash password client-side for basic security
      final hashedPassword = _hashPassword(password);
      
      final response = await http.post(
        Uri.parse('${AppConfig.authApiUrl}/login'),
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': 'TradingBot-Flutter/1.0',
        },
        body: jsonEncode({
          'username': username,
          'password': hashedPassword,
          'mfa_code': mfaCode,
          'device_info': await _getDeviceInfo(),
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        
        _accessToken = data['access_token'];
        _refreshToken = data['refresh_token'];
        _tokenExpiry = DateTime.now().add(Duration(seconds: data['expires_in']));
        _currentUser = User.fromJson(data['user']);

        // Store session securely
        await _storeSession();
        
        // Start token refresh timer
        _startTokenRefreshTimer();
        
        _authStateController.add(AuthState.authenticated);
        _logger.i('Login successful for user: ${_currentUser!.username}');
        
        return LoginResult.success();
        
      } else if (response.statusCode == 202) {
        // MFA required
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return LoginResult.mfaRequired(data['mfa_token']);
        
      } else if (response.statusCode == 401) {
        return LoginResult.invalidCredentials();
        
      } else if (response.statusCode == 423) {
        return LoginResult.accountLocked();
        
      } else {
        final error = jsonDecode(response.body)['error'] ?? 'Unknown error';
        return LoginResult.error(error);
      }
      
    } catch (e) {
      _logger.e('Login error: $e');
      return LoginResult.error('Network error: $e');
    }
  }

  /// Complete MFA login
  Future<LoginResult> completeMfaLogin({
    required String mfaToken,
    required String mfaCode,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.authApiUrl}/mfa/verify'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $mfaToken',
        },
        body: jsonEncode({
          'mfa_code': mfaCode,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        
        _accessToken = data['access_token'];
        _refreshToken = data['refresh_token'];
        _tokenExpiry = DateTime.now().add(Duration(seconds: data['expires_in']));
        _currentUser = User.fromJson(data['user']);

        await _storeSession();
        _startTokenRefreshTimer();
        _authStateController.add(AuthState.authenticated);
        
        return LoginResult.success();
      } else {
        return LoginResult.invalidMfaCode();
      }
    } catch (e) {
      _logger.e('MFA verification error: $e');
      return LoginResult.error('MFA verification failed: $e');
    }
  }

  /// Refresh access token
  Future<bool> refreshToken() async {
    if (_refreshToken == null) {
      return false;
    }

    try {
      _logger.d('Refreshing access token');
      
      final response = await http.post(
        Uri.parse('${AppConfig.authApiUrl}/refresh'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_refreshToken',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        
        _accessToken = data['access_token'];
        _tokenExpiry = DateTime.now().add(Duration(seconds: data['expires_in']));
        
        // Update refresh token if provided
        if (data.containsKey('refresh_token')) {
          _refreshToken = data['refresh_token'];
        }

        await _storeSession();
        _logger.d('Token refreshed successfully');
        return true;
        
      } else {
        _logger.w('Token refresh failed: ${response.statusCode}');
        await logout();
        return false;
      }
    } catch (e) {
      _logger.e('Token refresh error: $e');
      return false;
    }
  }

  /// Logout and clear session
  Future<void> logout() async {
    try {
      _logger.i('Logging out user: ${_currentUser?.username}');
      
      // Invalidate token on server
      if (_accessToken != null) {
        try {
          await http.post(
            Uri.parse('${AppConfig.authApiUrl}/logout'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_accessToken',
            },
          ).timeout(const Duration(seconds: 5));
        } catch (e) {
          _logger.w('Server logout failed: $e');
        }
      }
      
      // Clear local session
      await _clearSession();
      
      _accessToken = null;
      _refreshToken = null;
      _tokenExpiry = null;
      _currentUser = null;
      
      _refreshTimer?.cancel();
      _refreshTimer = null;
      
      _authStateController.add(AuthState.unauthenticated);
      _logger.i('Logout completed');
      
    } catch (e) {
      _logger.e('Logout error: $e');
    }
  }

  /// Check if user has specific permission
  bool hasPermission(String permission) {
    return _currentUser?.permissions.contains(permission) ?? false;
  }

  /// Check if user has specific role
  bool hasRole(String role) {
    return _currentUser?.roles.contains(role) ?? false;
  }

  /// Add Authorization header to HTTP requests
  Map<String, String> getAuthHeaders() {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    
    if (_accessToken != null) {
      headers['Authorization'] = 'Bearer $_accessToken';
    }
    
    return headers;
  }

  // Private methods

  void _startTokenRefreshTimer() {
    _refreshTimer?.cancel();
    
    if (_tokenExpiry == null) return;
    
    // Refresh 5 minutes before expiry
    final refreshTime = _tokenExpiry!.subtract(const Duration(minutes: 5));
    final delay = refreshTime.difference(DateTime.now());
    
    if (delay.isNegative) {
      // Token already expired, refresh immediately
      refreshToken();
    } else {
      _refreshTimer = Timer(delay, () {
        refreshToken();
      });
    }
  }

  String _hashPassword(String password) {
    // Simple SHA-256 hash with salt for client-side hashing
    final salt = Env.passwordSalt;
    final bytes = utf8.encode(password + salt);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<Map<String, dynamic>> _getDeviceInfo() async {
    return {
      'platform': kIsWeb ? 'web' : 'mobile',
      'user_agent': kIsWeb ? 'Flutter-Web' : 'Flutter-Mobile',
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  Future<void> _storeSession() async {
    try {
      // In a real app, use secure storage like flutter_secure_storage
      // For now, using basic local storage simulation
      _logger.d('Storing session data securely');
      // Implementation would go here
    } catch (e) {
      _logger.e('Failed to store session: $e');
    }
  }

  Future<void> _restoreSession() async {
    try {
      // In a real app, restore from secure storage
      _logger.d('Attempting to restore session');
      // Implementation would go here
    } catch (e) {
      _logger.e('Failed to restore session: $e');
    }
  }

  Future<void> _clearSession() async {
    try {
      // Clear secure storage
      _logger.d('Clearing session data');
      // Implementation would go here
    } catch (e) {
      _logger.e('Failed to clear session: $e');
    }
  }

  void dispose() {
    _refreshTimer?.cancel();
    _authStateController.close();
  }
}

// Data classes
enum AuthState {
  unauthenticated,
  authenticated,
  tokenExpired,
  loading,
}

class User {
  final String id;
  final String username;
  final String email;
  final String displayName;
  final List<String> roles;
  final List<String> permissions;
  final bool mfaEnabled;
  final DateTime? lastLogin;

  User({
    required this.id,
    required this.username,
    required this.email,
    required this.displayName,
    required this.roles,
    required this.permissions,
    required this.mfaEnabled,
    this.lastLogin,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      username: json['username'],
      email: json['email'],
      displayName: json['display_name'] ?? json['username'],
      roles: List<String>.from(json['roles'] ?? []),
      permissions: List<String>.from(json['permissions'] ?? []),
      mfaEnabled: json['mfa_enabled'] ?? false,
      lastLogin: json['last_login'] != null 
          ? DateTime.parse(json['last_login'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'display_name': displayName,
      'roles': roles,
      'permissions': permissions,
      'mfa_enabled': mfaEnabled,
      'last_login': lastLogin?.toIso8601String(),
    };
  }
}

class LoginResult {
  final bool success;
  final String? error;
  final LoginResultType type;
  final String? mfaToken;

  LoginResult._(this.success, this.type, this.error, this.mfaToken);

  factory LoginResult.success() => LoginResult._(true, LoginResultType.success, null, null);
  factory LoginResult.mfaRequired(String token) => LoginResult._(false, LoginResultType.mfaRequired, null, token);
  factory LoginResult.invalidCredentials() => LoginResult._(false, LoginResultType.invalidCredentials, 'Invalid username or password', null);
  factory LoginResult.invalidMfaCode() => LoginResult._(false, LoginResultType.invalidMfaCode, 'Invalid MFA code', null);
  factory LoginResult.accountLocked() => LoginResult._(false, LoginResultType.accountLocked, 'Account is locked', null);
  factory LoginResult.error(String message) => LoginResult._(false, LoginResultType.error, message, null);
}

enum LoginResultType {
  success,
  mfaRequired,
  invalidCredentials,
  invalidMfaCode,
  accountLocked,
  error,
}

// Add to AppConfig
extension AppConfigAuth on AppConfig {
  static String get authApiUrl => '${restApiUrl}/auth';
  static String get restApiUrl => Env.debugMode 
      ? 'http://localhost:5000/api'
      : 'https://api.yourdomain.com';
}

// Add to Env class
extension EnvAuth on Env {
  static const String passwordSalt = String.fromEnvironment(
    'PASSWORD_SALT',
    defaultValue: 'trading_bot_salt_2024',
  );
}