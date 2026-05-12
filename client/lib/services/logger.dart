import 'dart:developer' as dev;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../config/env.dart';

/// 로그 레벨 — error > warn > info > debug 순으로 상위 레벨만 출력.
enum LogLevel { debug, info, warn, error }

/// 앱 전역 로거.
///
/// 사용법:
/// ```dart
/// AppLogger.debug('FileProvider', 'loadChildren called');
/// AppLogger.info('AuthProvider', '로그인 성공: user_id=admin');
/// AppLogger.warn('ApiClient',  'HTTP 413 용량 초과');
/// AppLogger.error('AuthService', '토큰 리프레시 실패: $e');
/// ```
///
/// 출력 대상은 Env 값으로 제어한다.
/// - Env.logConsole = true  → 콘솔 출력 (release 빌드에서는 prod.json 으로 false 주입)
/// - Env.logFile    = true  → 앱 내부 저장소에 파일 저장
///
/// 파일 형식: `[LEVEL] YYYY-MM-DD HH:mm:ss.SSS [tag] message`
/// 파일 이름: fileforge_YYYY-MM-DD.log  (일별 로테이션)
/// 보존 기간: 최근 7일
class AppLogger {
  AppLogger._();
  static final AppLogger _instance = AppLogger._();

  static const int _retentionDays = 7;
  bool _pruned = false;

  // ── 퍼블릭 API ────────────────────────────────────────────────────────────

  static void debug(String tag, String message) =>
      _instance._log(LogLevel.debug, tag, message);

  static void info(String tag, String message) =>
      _instance._log(LogLevel.info, tag, message);

  static void warn(String tag, String message) =>
      _instance._log(LogLevel.warn, tag, message);

  static void error(String tag, String message) =>
      _instance._log(LogLevel.error, tag, message);

  // ── 내부 구현 ─────────────────────────────────────────────────────────────

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
      // 파일 시스템 오류는 무시한다.
    }
  }
}
