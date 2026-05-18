// Licensed under the Dartastic Pro Software License Agreement.
// Copyright 2025-2026 Mindful Software LLC d/b/a Dartastic.io, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';

import 'otel_defer_suppression.dart';

const _tracerName = 'dartastic_otel_libs_defer';

Tracer _tracer() => OTel.tracerProvider().getTracer(_tracerName);

class DeferResult {
  const DeferResult({
    this.executionId,
    this.functionName,
    this.queue,
    this.scheduleType,
    this.state,
    this.retryCount,
    this.maxConcurrency,
    this.executionTimeMs,
    this.scheduledForSec,
    this.statusCode,
  });

  final String? executionId;
  final String? functionName;

  /// Named queue inside the Defer project (Defer routes by queue).
  final String? queue;

  /// `enqueue` / `delay` / `cron` / `recurring` / `chained`.
  final String? scheduleType;

  /// `created` / `started` / `succeed` / `failed` / `cancelled` /
  /// `aborting` / `aborted` / `discarded`.
  final String? state;

  final int? retryCount;

  /// Concurrency limit configured on the function.
  final int? maxConcurrency;

  final int? executionTimeMs;

  /// For delayed/cron jobs — seconds until scheduled run time.
  final int? scheduledForSec;

  final int? statusCode;
}

class DeferCallResult<T> {
  const DeferCallResult({required this.value, this.result});
  final T value;
  final DeferResult? result;
}

/// Wraps a Defer.run API call in a CLIENT span. [operation] is one of
/// `function.enqueue`, `function.delay`, `function.schedule`,
/// `execution.cancel`, `execution.rerun`, `execution.get`,
/// `executions.list`.
Future<T> tracedDefer<T>({
  required String operation,
  required Future<DeferCallResult<T>> Function() invoke,
}) async {
  if (deferInstrumentationSuppressed()) {
    final r = await invoke();
    return r.value;
  }
  final m = <String, Object>{
    'rpc.system': 'defer',
    'rpc.method': operation,
    'defer.operation': operation,
  };

  final span = _tracer().startSpan(
    'defer $operation',
    kind: SpanKind.client,
    attributes: OTel.attributesFromMap(m),
  );
  try {
    final r = await invoke();
    if (r.result != null) {
      final extras = <Attribute<Object>>[];
      if (r.result!.executionId != null) {
        extras.add(OTel.attributeString(
          'defer.execution.id',
          r.result!.executionId!,
        ));
      }
      if (r.result!.functionName != null) {
        extras.add(OTel.attributeString(
          'defer.function.name',
          r.result!.functionName!,
        ));
      }
      if (r.result!.queue != null) {
        extras.add(OTel.attributeString('defer.queue', r.result!.queue!));
      }
      if (r.result!.scheduleType != null) {
        extras.add(OTel.attributeString(
          'defer.schedule.type',
          r.result!.scheduleType!,
        ));
      }
      if (r.result!.state != null) {
        extras.add(OTel.attributeString('defer.state', r.result!.state!));
        if (r.result!.state == 'failed' ||
            r.result!.state == 'aborted' ||
            r.result!.state == 'discarded') {
          span.setStatus(
            SpanStatusCode.Error,
            'Defer state ${r.result!.state}',
          );
        }
      }
      if (r.result!.retryCount != null) {
        extras.add(OTel.attributeInt(
          'defer.retry.count',
          r.result!.retryCount!,
        ));
      }
      if (r.result!.maxConcurrency != null) {
        extras.add(OTel.attributeInt(
          'defer.max_concurrency',
          r.result!.maxConcurrency!,
        ));
      }
      if (r.result!.executionTimeMs != null) {
        extras.add(OTel.attributeInt(
          'defer.execution.time_ms',
          r.result!.executionTimeMs!,
        ));
      }
      if (r.result!.scheduledForSec != null) {
        extras.add(OTel.attributeInt(
          'defer.scheduled_for_sec',
          r.result!.scheduledForSec!,
        ));
      }
      if (r.result!.statusCode != null) {
        extras.add(OTel.attributeInt(
          'http.response.status_code',
          r.result!.statusCode!,
        ));
        if (r.result!.statusCode! >= 400) {
          span.setStatus(
            SpanStatusCode.Error,
            'Defer HTTP ${r.result!.statusCode}',
          );
        }
      }
      if (extras.isNotEmpty) span.addAttributes(OTel.attributes(extras));
    }
    return r.value;
  } catch (e, st) {
    span.addAttributes(OTel.attributes([
      OTel.attributeString(
        ErrorResource.errorType.key,
        e.runtimeType.toString(),
      ),
    ]));
    span.recordException(e, stackTrace: st);
    span.setStatus(SpanStatusCode.Error, e.toString());
    rethrow;
  } finally {
    span.end();
  }
}
