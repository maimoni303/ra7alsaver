import 'package:flutter/foundation.dart';
import 'package:local_auth_platform_interface/types/auth_messages.dart';

@immutable
class WindowsAuthMessages extends AuthMessages {
  const WindowsAuthMessages();
  @override
  Map<String, String> get args => const <String, String>{};
}
