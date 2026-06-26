import 'package:shared_preferences/shared_preferences.dart';

/// account text(presence) text — TR0005 §symptom1(text text) translated text translated text.
///
/// text translated text text translated text `GET /accounts` translated text translated text translated text
/// translated text/translated text translated text text "translated text compose screentext text translated text"text text translated text.
/// translated text translated text "accounttext translated text" text translated text translated text text, text translated text screentext
/// text translated text(translated text text) translated text translated text translated text text text.
///
/// interfacetext translated text text translated text translated text(SharedPreferences) text textnotetext
/// translated text translated text translated text verifytext text.
abstract class AccountPresenceCache {
  /// translated text translated text account text. text text translated text text translated text null.
  Future<bool?> getHasAccounts();

  /// successtext text/text/text text account translated text refreshtext(translated text).
  Future<void> setHasAccounts(bool value);
}

/// SharedPreferences backend text text(text pubspec translated text).
class SharedPrefsAccountCache implements AccountPresenceCache {
  static const String _key = 'mail_has_accounts_v1';

  @override
  Future<bool?> getHasAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key);
  }

  @override
  Future<void> setHasAccounts(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }
}
