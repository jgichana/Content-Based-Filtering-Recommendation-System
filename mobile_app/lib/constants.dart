import 'package:flutter/material.dart';

/// Must match VALID_INTERESTS in backend/Api.py and the `interest` column of
/// the activities dataset.
const List<String> kInterests = [
  'General Play',
  'Games',
  'Reading',
  'Music',
  'Art',
];

IconData interestIcon(String interest) {
  switch (interest) {
    case 'General Play':
      return Icons.toys_outlined;
    case 'Games':
      return Icons.extension_outlined;
    case 'Reading':
      return Icons.menu_book_outlined;
    case 'Music':
      return Icons.music_note_outlined;
    case 'Art':
      return Icons.palette_outlined;
    default:
      return Icons.star_outline;
  }
}

/// "13 months", "2 years", "3 years 4 months".
String formatAge(int months) {
  if (months < 24) return months == 1 ? '1 month' : '$months months';
  final years = months ~/ 12;
  final rest = months % 12;
  final y = '$years years';
  if (rest == 0) return y;
  return rest == 1 ? '$y 1 month' : '$y $rest months';
}
