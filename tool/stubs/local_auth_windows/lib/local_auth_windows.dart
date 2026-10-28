import 'package:local_auth_platform_interface/local_auth_platform_interface.dart';

export 'types/auth_messages_windows.dart';

/// Reports "no biometrics" on Windows so the app hides the lock option.
class LocalAuthWindows extends LocalAuthPlatform {
  static void registerWith() => LocalAuthPlatform.instance = LocalAuthWindows();

  @override
  Future<bool> authenticate({
    required String localizedReason,
    required Iterable<AuthMessages> authMessages,
    AuthenticationOptions options = const AuthenticationOptions(),
  }) async =>
      false;

  @override
  Future<bool> deviceSupportsBiometrics() async => false;

  @override
  Future<List<BiometricType>> getEnrolledBiometrics() async => const [];

  @override
  Future<bool> isDeviceSupported() async => false;

  @override
  Future<bool> stopAuthentication() async => false;
}
