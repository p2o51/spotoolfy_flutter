String getLeadingText(String dateString) {
  final date = DateTime.parse(dateString);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final thoughtDate = DateTime(date.year, date.month, date.day);

  if (thoughtDate == today) {
    return '今';
  } else if (thoughtDate == yesterday) {
    return '昨';
  } else {
    final difference = today.difference(thoughtDate).inDays;
    return '$difference';
  }
}