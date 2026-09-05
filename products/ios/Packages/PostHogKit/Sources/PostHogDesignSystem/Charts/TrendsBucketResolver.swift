import PostHogQueries

/// Resolves the date behind a trends bucket, so a tap can ask the API for the
/// people in that bucket. The API puts ISO dates in `days` and display text in
/// `labels`; older saved insights send only `labels`, so that is the fallback.
enum TrendsBucketResolver {
  /// The comparison series repeats the same buckets shifted back one period,
  /// so the current series is the one that dates a drill-down.
  static func day(for index: Int, in series: [SeriesResult]) -> String? {
    guard index >= 0, let reference = series.first(where: { !$0.isPrevious }) ?? series.first else {
      return nil
    }
    if reference.days.indices.contains(index) { return reference.days[index] }
    if reference.labels.indices.contains(index) { return reference.labels[index] }
    return nil
  }
}
