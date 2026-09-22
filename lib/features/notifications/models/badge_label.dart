String compactBadgeLabel(int count) {
  if (count > 99) {
    return '99+';
  }

  return '$count';
}
