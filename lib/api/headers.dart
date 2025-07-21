// lib/api/headers.dart
import '../config_loader.dart';

Map<String, String> headers(AppConfig config) => {
  'Content-Type': 'application/json',
  'applicationId': config.applicationId
};
