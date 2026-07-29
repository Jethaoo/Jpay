String? serializeTimestamptz(DateTime? value) {
  return value?.toUtc().toIso8601String();
}
