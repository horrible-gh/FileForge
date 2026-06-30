/// SecureBolt vault domain models (fileforge.securebolt.0001 / L0006 §1.4).
///
/// A vault holds two bundles: a list of password entries and a list of
/// categories. Each bundle is serialized to a JSON array and locked as a whole
/// (item-level encryption is NOT used) before it is pushed to the server as an
/// opaque blob (L0006 §1.4). The shapes here must stay JSON-compatible with the
/// legacy SecureBolt web client so blobs round-trip across both clients.
library;

/// A single password record (L0006 §1.4: `{id, title, username, password, url,
/// category, notes}`).
class VaultPasswordEntry {
  final int id;
  final String title;
  final String username;
  final String password;
  final String url;
  final String category;
  final String notes;

  const VaultPasswordEntry({
    required this.id,
    required this.title,
    this.username = '',
    this.password = '',
    this.url = '',
    this.category = 'work',
    this.notes = '',
  });

  VaultPasswordEntry copyWith({
    String? title,
    String? username,
    String? password,
    String? url,
    String? category,
    String? notes,
  }) {
    return VaultPasswordEntry(
      id: id,
      title: title ?? this.title,
      username: username ?? this.username,
      password: password ?? this.password,
      url: url ?? this.url,
      category: category ?? this.category,
      notes: notes ?? this.notes,
    );
  }

  factory VaultPasswordEntry.fromJson(Map<String, dynamic> j) {
    return VaultPasswordEntry(
      // legacy ids are Date.now() ints; tolerate string ids too.
      id: j['id'] is int
          ? j['id'] as int
          : int.tryParse('${j['id']}') ?? 0,
      title: (j['title'] ?? '') as String,
      username: (j['username'] ?? '') as String,
      password: (j['password'] ?? '') as String,
      url: (j['url'] ?? '') as String,
      category: (j['category'] ?? 'work') as String,
      notes: (j['notes'] ?? '') as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'username': username,
        'password': password,
        'url': url,
        'category': category,
        'notes': notes,
      };
}

/// A category record (L0006 §1.4: `{id, name, icon, color, isDefault}`).
class VaultCategory {
  final String id;
  final String name;
  final String icon;
  final String color;
  final bool isDefault;

  const VaultCategory({
    required this.id,
    required this.name,
    this.icon = '📁',
    this.color = '#718096',
    this.isDefault = false,
  });

  factory VaultCategory.fromJson(Map<String, dynamic> j) {
    return VaultCategory(
      id: '${j['id']}',
      name: (j['name'] ?? '') as String,
      icon: (j['icon'] ?? '📁') as String,
      color: (j['color'] ?? '#718096') as String,
      isDefault: j['isDefault'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'icon': icon,
        'color': color,
        'isDefault': isDefault,
      };
}

/// DEFAULT_CATEGORIES (L0006 §1.3) — always present, never deletable, and they
/// win on merge. The id set {work, personal, entertainment} is fixed.
// The `name` here is only a non-localized fallback: the UI shows a localized
// label keyed on the fixed id (see `vaultCategoryName` in vault_screen.dart),
// so these names are never rendered for the default ids.
const List<VaultCategory> kDefaultVaultCategories = [
  VaultCategory(
      id: 'work', name: 'Work', icon: '💼', color: '#667eea', isDefault: true),
  VaultCategory(
      id: 'personal',
      name: 'Personal',
      icon: '👤',
      color: '#48bb78',
      isDefault: true),
  VaultCategory(
      id: 'entertainment',
      name: 'Entertainment',
      icon: '🎮',
      color: '#ed8936',
      isDefault: true),
];

/// The decrypted vault content held in memory while UNLOCKED.
class VaultData {
  final List<VaultPasswordEntry> passwords;
  final List<VaultCategory> categories;

  const VaultData({required this.passwords, required this.categories});

  VaultData copyWith({
    List<VaultPasswordEntry>? passwords,
    List<VaultCategory>? categories,
  }) {
    return VaultData(
      passwords: passwords ?? this.passwords,
      categories: categories ?? this.categories,
    );
  }

  static VaultData empty() => VaultData(
        passwords: const [],
        categories: List<VaultCategory>.from(kDefaultVaultCategories),
      );
}
