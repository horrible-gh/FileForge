import 'dart:developer' as dev;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../config/env.dart';

/// text text — error > warn > info > debug translated text parent translated text text.
enum LogLevel { debug, info, warn, error }

/// text text text.
///
/// translated text:
/// ```dart
/// AppLogger.debug('FileProvider', 'loadChildren called');
/// AppLogger.info('AuthProvider', 'login success: user_id=admin');
/// AppLogger.warn('ApiClient',  'HTTP 413 capacity exceeded');
/// AppLogger.error('AuthService', 'token translated text failed: $e');
/// ```
///
/// text translated text Env translated text translated text.
/// - Env.logConsole = true  → text text (release buildtranslated text prod.json text false text)
/// - Env.logFile    = true  → text text savetext file save
///
/// file text: `[LEVEL] YYYY-MM-DD HH:mm:ss.SSS [tag] message`
/// file name: fileforge_YYYY-MM-DD.log  (text translated text)
/// preserved text: text 7text
class AppLogger {
  AppLogger._();
  static final AppLogger _instance = AppLogger._();

  static const int _retentionDays = 7;
  bool _pruned = false;

  // ── translated text API ────────────────────────────────────────────────────────────

  static void debug(String tag, String message) =>
      _instance._log(LogLevel.debug, tag, message);

  static void info(String tag, String message) =>
      _instance._log(LogLevel.info, tag, message);

  static void warn(String tag, String message) =>
      _instance._log(LogLevel.warn, tag, message);

  static void error(String tag, String message) =>
      _instance._log(LogLevel.error, tag, message);

  // ── text text ─────────────────────────────────────────────────────────────

  LogLevel get _minLevel {
    switch (Env.logLevel.toLowerCase()) {
      case 'error':
        return LogLevel.error;
      case 'warn':
        return LogLevel.warn;
      case 'info':
        return LogLevel.info;
      default:
        return LogLevel.debug;
    }
  }

  void _log(LogLevel level, String tag, String message) {
    if (level.index < _minLevel.index) return;

    final now = DateTime.now();
    final ts = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}.'
        '${now.millisecond.toString().padLeft(3, '0')}';

    final lvl = level.name.toUpperCase().padRight(5);
    final line = '[$lvl] $ts [$tag] $message';

    if (Env.logConsole) {
      dev.log(line);
    }

    if (Env.logFile) {
      _writeToFile(line);
    }
  }

  void _writeToFile(String line) {
    _getLogFile().then((file) async {
      await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
      if (!_pruned) {
        _pruned = true;
        await _pruneOldLogs();
      }
    }).catchError((_) {});
  }

  Future<File> _getLogFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final now = DateTime.now();
    final date = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    return File('${dir.path}/fileforge_$date.log');
  }

  Future<void> _pruneOldLogs() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final cutoff =
          DateTime.now().subtract(const Duration(days: _retentionDays));
      final entries = dir.listSync().whereType<File>().where(
            (f) =>
                f.path.contains('fileforge_') && f.path.endsWith('.log'),
          );
      for (final f in entries) {
        final stat = f.statSync();
        if (stat.modified.isBefore(cutoff)) {
          f.deleteSync();
        }
      }
    } catch (_) {
      // file translated text errortext translated text.
    }
  }
}
