enum UserRole { admin, moderator, user }

String roleName(UserRole role) {
  switch (role) {
    case UserRole.admin:
      return 'admin';
    case UserRole.moderator:
      return 'moderator';
    case UserRole.user:
      return 'user';
  }
}

UserRole roleFromFirebase(Object? value) {
  switch (value) {
    case 'admin':
      return UserRole.admin;
    case 'moderator':
      return UserRole.moderator;
    default:
      return UserRole.user;
  }
}

bool userRoleIsAdmin(UserRole role) {
  return role == UserRole.admin;
}

bool userRoleIsModerator(UserRole role) {
  return role == UserRole.moderator;
}

bool userRoleIsStaff(UserRole role) {
  return role == UserRole.admin || role == UserRole.moderator;
}
