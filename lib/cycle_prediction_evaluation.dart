import 'cycle_tracking_page.dart';

DateTime _day(DateTime date) => DateTime(date.year, date.month, date.day);
DateTime _addDays(DateTime date, int days) =>
    DateTime(date.year, date.month, date.day + days);
int _daysBetween(DateTime first, DateTime second) => DateTime.utc(
  first.year,
  first.month,
  first.day,
).difference(DateTime.utc(second.year, second.month, second.day)).inDays;
String? _dateJson(DateTime? date) => date == null ? null : cycleDateKey(date);

/// Reasons retained in the report instead of silently removing difficult cases.
enum CycleEvaluationExclusion {
  beforeContextStart,
  checkpointNotReached,
  outcomeAlreadyObserved,
  missingOutcome,
  outcomeTooShort,
  outcomeAfterShortInterval,
  outcomeHistoryBreak,
  ambiguousTrackingHistory,
}

enum CycleForecastUnavailable {
  personalContext,
  ambiguousBleeding,
  possibleTrackingGap,
  insufficientHistory,
}

/// One predeclared checkpoint in one recorded cycle, including exclusions.
class CyclePredictionEvaluationCase {
  final DateTime cycleStart;
  final int evaluationCycleDay;
  final DateTime asOf;
  final DateTime? observedNextPeriod;
  final bool checkpointEligible;
  final CycleEvaluationExclusion? exclusion;
  final CycleForecastUnavailable? forecastUnavailable;
  final DateTime? predictedNextPeriod;
  final DateTime? earliest;
  final DateTime? latest;
  final int? trainingCycleCount;
  final CycleHistoryQuality? historyQuality;
  final bool usedSymptomAdjustment;
  final bool usedPhysiologyAdjustment;

  const CyclePredictionEvaluationCase._({
    required this.cycleStart,
    required this.evaluationCycleDay,
    required this.asOf,
    required this.observedNextPeriod,
    required this.checkpointEligible,
    required this.exclusion,
    required this.forecastUnavailable,
    required this.predictedNextPeriod,
    required this.earliest,
    required this.latest,
    required this.trainingCycleCount,
    required this.historyQuality,
    required this.usedSymptomAdjustment,
    required this.usedPhysiologyAdjustment,
  });

  bool get hasForecast => predictedNextPeriod != null;
  bool get hasScorableOutcome => checkpointEligible && exclusion == null;
  bool get isScored => hasScorableOutcome && hasForecast;
  int? get absoluteErrorDays => !isScored
      ? null
      : _daysBetween(predictedNextPeriod!, observedNextPeriod!).abs();
  bool? get withinTwoDays => !isScored ? null : absoluteErrorDays! <= 2;
  bool? get withinWindow => !isScored
      ? null
      : !observedNextPeriod!.isBefore(earliest!) &&
            !observedNextPeriod!.isAfter(latest!);
  int? get windowWidthDays =>
      !hasForecast ? null : _daysBetween(latest!, earliest!) + 1;

  Map<String, Object?> toJson() => {
    'cycle_start': _dateJson(cycleStart),
    'evaluation_cycle_day': evaluationCycleDay,
    'as_of': _dateJson(asOf),
    'observed_next_period': _dateJson(observedNextPeriod),
    'checkpoint_eligible': checkpointEligible,
    'exclusion': exclusion?.name,
    'forecast_unavailable': forecastUnavailable?.name,
    'predicted_next_period': _dateJson(predictedNextPeriod),
    'earliest': _dateJson(earliest),
    'latest': _dateJson(latest),
    'training_cycle_count': trainingCycleCount,
    'history_quality': historyQuality?.name,
    'used_symptom_adjustment': usedSymptomAdjustment,
    'used_physiology_adjustment': usedPhysiologyAdjustment,
    'is_scored': isScored,
    'absolute_error_days': absoluteErrorDays,
    'within_two_days': withinTwoDays,
    'within_window': withinWindow,
    'window_width_days': windowWidthDays,
  };
}

class CyclePredictionEvaluationSummary {
  /// Counts checkpoints, which are not independent people or independent cycles.
  final int candidateCheckpointCount;
  final int distinctCycleCount;
  final int eligibleCheckpointCount;
  final int forecastCount;
  final int scorableOutcomeCount;
  final int scoredForecastCount;
  final int distinctScoredCycleCount;
  final int withinTwoDaysCount;
  final int withinWindowCount;
  final double? meanAbsoluteErrorDays;
  final double? meanScoredWindowWidthDays;
  final Map<CycleEvaluationExclusion, int> exclusions;
  final Map<CycleForecastUnavailable, int> unavailableForecasts;

  CyclePredictionEvaluationSummary._(List<CyclePredictionEvaluationCase> rows)
    : candidateCheckpointCount = rows.length,
      distinctCycleCount = rows.map((row) => row.cycleStart).toSet().length,
      eligibleCheckpointCount = rows
          .where((row) => row.checkpointEligible)
          .length,
      forecastCount = rows.where((row) => row.hasForecast).length,
      scorableOutcomeCount = rows.where((row) => row.hasScorableOutcome).length,
      scoredForecastCount = rows.where((row) => row.isScored).length,
      distinctScoredCycleCount = rows
          .where((row) => row.isScored)
          .map((row) => row.cycleStart)
          .toSet()
          .length,
      withinTwoDaysCount = rows
          .where((row) => row.withinTwoDays == true)
          .length,
      withinWindowCount = rows.where((row) => row.withinWindow == true).length,
      meanAbsoluteErrorDays = _mean(
        rows.where((row) => row.isScored).map((row) => row.absoluteErrorDays!),
      ),
      meanScoredWindowWidthDays = _mean(
        rows.where((row) => row.isScored).map((row) => row.windowWidthDays!),
      ),
      exclusions = Map.unmodifiable({
        for (final reason in CycleEvaluationExclusion.values)
          if (rows.any((row) => row.exclusion == reason))
            reason: rows.where((row) => row.exclusion == reason).length,
      }),
      unavailableForecasts = Map.unmodifiable({
        for (final reason in CycleForecastUnavailable.values)
          if (rows.any((row) => row.forecastUnavailable == reason))
            reason: rows
                .where((row) => row.forecastUnavailable == reason)
                .length,
      });

  /// Availability includes pending and ambiguous outcomes when their checkpoint
  /// was reached. An unavailable forecast is never counted as a correct one.
  double? get forecastAvailabilityRate => eligibleCheckpointCount == 0
      ? null
      : forecastCount / eligibleCheckpointCount;

  /// Both accuracy rates use only forecasts with an accepted observed outcome.
  double? get withinTwoDaysRate => scoredForecastCount == 0
      ? null
      : withinTwoDaysCount / scoredForecastCount;
  double? get windowCoverageRate =>
      scoredForecastCount == 0 ? null : withinWindowCount / scoredForecastCount;

  Map<String, Object?> toJson() => {
    'candidate_checkpoint_count': candidateCheckpointCount,
    'distinct_cycle_count': distinctCycleCount,
    'eligible_checkpoint_count': eligibleCheckpointCount,
    'forecast_count': forecastCount,
    'scorable_outcome_count': scorableOutcomeCount,
    'scored_forecast_count': scoredForecastCount,
    'distinct_scored_cycle_count': distinctScoredCycleCount,
    'within_two_days_count': withinTwoDaysCount,
    'within_window_count': withinWindowCount,
    'mean_absolute_error_days': meanAbsoluteErrorDays,
    'mean_scored_window_width_days': meanScoredWindowWidthDays,
    'forecast_availability_rate': forecastAvailabilityRate,
    'within_two_days_rate': withinTwoDaysRate,
    'window_coverage_rate': windowCoverageRate,
    'exclusions': {
      for (final item in exclusions.entries) item.key.name: item.value,
    },
    'unavailable_forecasts': {
      for (final item in unavailableForecasts.entries)
        item.key.name: item.value,
    },
  };
}

double? _mean(Iterable<int> values) {
  final samples = values.toList();
  return samples.isEmpty
      ? null
      : samples.fold(0, (sum, value) => sum + value) / samples.length;
}

class CyclePredictionEvaluation {
  final DateTime asOf;
  final CyclePersonalContext context;
  final bool stableContextExplicitlyProvided;
  final List<int> evaluationCycleDays;
  final List<CyclePredictionEvaluationCase> cases;
  final CyclePredictionEvaluationSummary summary;
  final Map<int, CyclePredictionEvaluationSummary> byCycleDay;

  CyclePredictionEvaluation._({
    required this.asOf,
    required this.context,
    required this.stableContextExplicitlyProvided,
    required List<int> evaluationCycleDays,
    required List<CyclePredictionEvaluationCase> cases,
  }) : evaluationCycleDays = List.unmodifiable(evaluationCycleDays),
       cases = List.unmodifiable(cases),
       summary = CyclePredictionEvaluationSummary._(cases),
       byCycleDay = Map.unmodifiable({
         for (final day in evaluationCycleDays)
           day: CyclePredictionEvaluationSummary._(
             cases.where((row) => row.evaluationCycleDay == day).toList(),
           ),
       });

  /// Can be used to stratify separate reports without erasing complex contexts.
  String get contextKey => [
    context.lifeStage.name,
    context.contraception.name,
    if (context.breastfeeding) 'breastfeeding',
    if (context.hasPcos) 'pcos',
  ].join('/');

  /// Contains sensitive date-only health data. No entry IDs, notes or raw symptom
  /// observations are exported; this does not make the output anonymous.
  Map<String, Object?> toJson() => {
    'method': 'retrospective_calendar_day_replay_v1',
    'as_of': _dateJson(asOf),
    'context_key': contextKey,
    'context': context.toRow(),
    'stable_context_explicitly_provided': stableContextExplicitlyProvided,
    'evaluation_cycle_days': evaluationCycleDays,
    'summary': summary.toJson(),
    'by_cycle_day': {
      for (final entry in byCycleDay.entries)
        entry.key.toString(): entry.value.toJson(),
    },
    'cases': cases.map((row) => row.toJson()).toList(),
  };
}

/// Offline retrospective evaluation. It reads no storage and makes no requests.
///
/// Checkpoints must be chosen before inspecting outcomes. Day 1 is the first
/// recorded day of bleeding. Each forecast sees only entries dated on/before
/// that checkpoint; its target is the next recorded period start, never an
/// invented intermediate period. Ambiguous targets remain visible as exclusions.
///
/// [stableContext] explicitly asserts that this context applied throughout the
/// evaluated segment. Do not pass today's context without that knowledge. Set
/// its historyStart for a known transition; earlier episodes are then excluded.
/// Omitting it evaluates the unspecified-context model, without inferring a
/// natural cycle or retroactively applying a profile from a database.
///
/// Entries lack historical recorded-at/edit timestamps. This is therefore a
/// date-limited replay, not proof that an entry was available on its recorded
/// date. A prospective study needs saved forecasts and observed outcomes.
class CyclePredictionEvaluator {
  const CyclePredictionEvaluator._();

  static CyclePredictionEvaluation evaluate(
    Iterable<CycleEntry> entries, {
    required DateTime now,
    CyclePersonalContext? stableContext,
    List<int> evaluationCycleDays = const [10, 20],
  }) {
    if (evaluationCycleDays.isEmpty ||
        evaluationCycleDays.any((day) => day < 1) ||
        evaluationCycleDays.toSet().length != evaluationCycleDays.length) {
      throw ArgumentError.value(
        evaluationCycleDays,
        'evaluationCycleDays',
        'Provide distinct, positive cycle days chosen before evaluation.',
      );
    }
    final today = _day(now);
    final context = stableContext ?? const CyclePersonalContext();
    final recorded = entries
        .where((entry) => !_day(entry.date).isAfter(today))
        .toList();
    // Obtain all episodes first so a context transition cannot silently erase
    // excluded candidates or turn the middle of an episode into a new start.
    final starts = CycleInsights.fromEntries(recorded, now: today).periodStarts;
    final days = evaluationCycleDays.toList()..sort();
    final cases = <CyclePredictionEvaluationCase>[];
    for (var index = 0; index < starts.length; index++) {
      final start = _day(starts[index]);
      final target = index + 1 < starts.length ? _day(starts[index + 1]) : null;
      CycleInsights? outcomeInsights;
      for (final day in days) {
        final asOf = _addDays(start, day - 1);
        CycleEvaluationExclusion? exclusion;
        if (context.historyStart != null &&
            start.isBefore(_day(context.historyStart!))) {
          exclusion = CycleEvaluationExclusion.beforeContextStart;
        } else if (target != null && !asOf.isBefore(target)) {
          exclusion = CycleEvaluationExclusion.outcomeAlreadyObserved;
        } else if (asOf.isAfter(today)) {
          exclusion = CycleEvaluationExclusion.checkpointNotReached;
        }
        final checkpointEligible = exclusion == null;
        CycleInsights? forecast;
        CycleForecastUnavailable? unavailable;
        if (checkpointEligible) {
          forecast = CycleInsights.fromEntries(
            recorded.where((entry) => !_day(entry.date).isAfter(asOf)),
            now: asOf,
            personalContext: context,
          );
          if (!forecast.hasPrediction) {
            unavailable = context.suspensionReason != null
                ? CycleForecastUnavailable.personalContext
                : forecast.hasRecentAmbiguousBleeding
                ? CycleForecastUnavailable.ambiguousBleeding
                : forecast.hasPossibleTrackingGap
                ? CycleForecastUnavailable.possibleTrackingGap
                : CycleForecastUnavailable.insufficientHistory;
          }
          if (target == null) {
            exclusion = CycleEvaluationExclusion.missingOutcome;
          } else {
            final length = _daysBetween(target, start);
            if (length < 15) {
              exclusion = CycleEvaluationExclusion.outcomeTooShort;
            } else if (length > 90) {
              exclusion = CycleEvaluationExclusion.outcomeHistoryBreak;
            } else if (index > 0 &&
                _daysBetween(start, starts[index - 1]) < 15) {
              exclusion = CycleEvaluationExclusion.outcomeAfterShortInterval;
            } else {
              // Outcome-only quality assessment. Never pass this later snapshot
              // to the forecast or use it to select a more favorable checkpoint.
              outcomeInsights ??= CycleInsights.fromEntries(
                recorded.where((entry) => !_day(entry.date).isAfter(target)),
                now: target,
                personalContext: context,
              );
              if (outcomeInsights.hasPossibleTrackingGap) {
                exclusion = CycleEvaluationExclusion.ambiguousTrackingHistory;
              }
            }
          }
        }
        cases.add(
          CyclePredictionEvaluationCase._(
            cycleStart: start,
            evaluationCycleDay: day,
            asOf: asOf,
            observedNextPeriod: target,
            checkpointEligible: checkpointEligible,
            exclusion: exclusion,
            forecastUnavailable: unavailable,
            predictedNextPeriod: forecast?.hasPrediction == true
                ? forecast!.nextPeriodStart
                : null,
            earliest: forecast?.hasPrediction == true
                ? forecast!.nextPeriodEarliest
                : null,
            latest: forecast?.hasPrediction == true
                ? forecast!.nextPeriodLatest
                : null,
            trainingCycleCount: forecast?.cycleSampleCount,
            historyQuality: forecast?.historyQuality,
            usedSymptomAdjustment: forecast?.usedSymptomAdjustment ?? false,
            usedPhysiologyAdjustment:
                forecast?.usedPhysiologyAdjustment ?? false,
          ),
        );
      }
    }
    return CyclePredictionEvaluation._(
      asOf: today,
      context: context,
      stableContextExplicitlyProvided: stableContext != null,
      evaluationCycleDays: days,
      cases: cases,
    );
  }
}
