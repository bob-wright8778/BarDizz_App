import 'dart:convert';

/// Inputs: the raw body of an InsForge `/api/database/records/...` list response.
/// Outputs: the rows as maps, tolerating a bare JSON array or a
/// `{"records":[...]}` envelope (empty when the body is blank).
List<Map<String, dynamic>> parseRecordList(String body) {
  if (body.isEmpty) return const [];
  final decoded = jsonDecode(body);
  final list = decoded is List ? decoded : (decoded as Map<String, dynamic>)['records'] as List? ?? const [];
  return [for (final row in list) row as Map<String, dynamic>];
}
