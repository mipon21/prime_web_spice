import 'package:prime_web/services/foodappi_fcm_service.dart';

class SetFcm {
  Future<void> SetFcmRepo() async {
    await FoodappiFcmService.initialize();
  }
}
