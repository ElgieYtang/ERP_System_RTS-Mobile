import 'package:flutter/foundation.dart';

import '../services/api_client.dart';
import '../services/api_errors.dart';

class AuthState extends ChangeNotifier {
  AuthState(this.api);

  final ApiClient api;

  bool bootstrapping = true;
  bool busy = false;
  String? error;

  bool get isAuthenticated => api.isAuthenticated;
  Map<String, dynamic>? get user => api.user;

  Future<void> bootstrap() async {
    bootstrapping = true;
    error = null;
    notifyListeners();

    try {
      await api.ensureConfigured();
      await api.restoreSession();
      if (api.isAuthenticated) {
        await api.me();
      }
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        error = friendlyApiError(e);
        await api.clearSession();
      } else if (isTransientNetworkError(e)) {
        // Keep session; dashboard can use cached data until API is back.
        error = null;
      } else {
        error = friendlyApiError(e);
        await api.clearSession();
      }
    } catch (e) {
      if (isTransientNetworkError(e)) {
        error = null;
      } else {
        error = friendlyApiError(e);
        await api.clearSession();
      }
    } finally {
      bootstrapping = false;
      notifyListeners();
    }
  }

  Future<bool> login(String login, String password) async {
    busy = true;
    error = null;
    notifyListeners();

    try {
      await api.ensureConfigured();
      await api.login(login.trim(), password);
      busy = false;
      notifyListeners();
      return true;
    } catch (e) {
      error = friendlyApiError(e);
      busy = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    busy = true;
    notifyListeners();
    await api.logout();
    busy = false;
    notifyListeners();
  }

  void handleSessionExpired(String message) {
    error = message;
    busy = false;
    bootstrapping = false;
    notifyListeners();
  }
}
