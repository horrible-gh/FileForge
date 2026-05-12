import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'providers/file_provider.dart';

void main() async {
  usePathUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final savedViewMode = prefs.getString('fileforge_viewMode');
  final initialViewMode =
      savedViewMode == 'grid' ? FileViewMode.grid : FileViewMode.list;
  final savedServerUrl = prefs.getString('server_url') ?? '';
  runApp(App(initialViewMode: initialViewMode, initialServerUrl: savedServerUrl));
}
