
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> testSupabaseConnection() async {
  try {
final data = await Supabase.instance.client
    .from('products')
    .select()
    .limit(5);

debugPrint('ĐỌC SẢN PHẨM THÀNH CÔNG: ${data.length} dòng');
debugPrint('DỮ LIỆU: $data');
  } on PostgrestException catch (e) {
    debugPrint('SUPABASE_DATABASE_ERROR: ${e.message}');
    debugPrint('Code: ${e.code}');
  } catch (e) {
    debugPrint('SUPABASE_CONNECTION_ERROR: $e');
  }
}