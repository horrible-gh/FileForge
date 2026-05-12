class User {
  final String userId;
  final String username;
  final String? userUuid;
  final String? status;

  const User({
    required this.userId,
    required this.username,
    this.userUuid,
    this.status,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      userId: json['user_id'] as String? ?? '',
      username: json['user_name'] as String? ?? '',
      userUuid: json['user_uuid'] as String?,
      status: json['status'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'username': username,
        if (userUuid != null) 'user_uuid': userUuid,
        if (status != null) 'status': status,
      };
}
