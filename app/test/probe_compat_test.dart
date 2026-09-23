import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:x_app/core/api.dart';
import 'package:x_app/core/app_config.dart';
import 'package:x_app/core/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test('probe', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await Store.init();
    await AppConfig.instance.load();
    final api = Api(store);
    await api.initSigningKey();
    final g = await api.guest();
    await store.setToken(g['token'] as String);
    await store.setUser(g['user'] as Map<String, dynamic>);
    try {
      final ok = await api.searchCompatCharged('11', brand: '01xiaomi.json', type: 'SCREEN');
      print('OK charged=${ok.charged} source=${ok.source} n=${ok.records.length}');
    } on ApiException catch (e) {
      print('APIEXC status=${e.status} msg=${e.message}');
    } catch (e) {
      print('OTHER $e');
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
