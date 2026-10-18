import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  static const String supabaseUrl = 'https://owcnqjddeurixwlcdrjv.supabase.co';
  static const String supabasePublishableKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im93Y25xamRkZXVyaXh3bGNkcmp2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTIyOTM2MjMsImV4cCI6MjEwNzg2OTYyM30.Wp1p5-4kYs6o89Ri0Xvz4saT0c2xaKzqKGcI_-3qxjw';

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabasePublishableKey,
    );
  }
}