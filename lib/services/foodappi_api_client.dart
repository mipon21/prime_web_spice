import 'package:dio/dio.dart';
import 'package:prime_web/utils/constants.dart';

class FoodappiApiClient {
  FoodappiApiClient._();

  static final Dio _dio = Dio(
    BaseOptions(
      baseUrl: foodappiApiUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Accept': 'application/json',
        'x-api-key': foodappiApiKey,
      },
    ),
  );

  static Map<String, String> authHeaders(String bearerToken) => {
        'Authorization': 'Bearer $bearerToken',
        'Accept': 'application/json',
        'x-api-key': foodappiApiKey,
      };

  static Future<Response<dynamic>> post(
    String path, {
    required Map<String, dynamic> body,
    String? bearerToken,
  }) {
    return _dio.post(
      path,
      data: body,
      options: Options(
        headers: bearerToken != null ? authHeaders(bearerToken) : null,
      ),
    );
  }

  static Future<Response<dynamic>> delete(
    String path, {
    Map<String, dynamic>? queryParameters,
    String? bearerToken,
  }) {
    return _dio.delete(
      path,
      queryParameters: queryParameters,
      options: Options(
        headers: bearerToken != null ? authHeaders(bearerToken) : null,
      ),
    );
  }
}
