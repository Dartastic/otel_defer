// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:dartastic_opentelemetry/testing.dart';
import 'package:otel_defer/otel_defer.dart';
import 'package:test/test.dart';

void main() {
  late TestHarness harness;
  late InMemorySpanExporter spans;

  setUpAll(() async {
    harness = await maybeInitializeOtelForTest(
      serviceName: 'otel_defer-test',
    );
    spans = harness.spans;
  });

  setUp(() => harness.clear());

  Map<String, Object> attrsOf(Span s) =>
      {for (final a in s.attributes.toList()) a.key: a.value};

  test('function.delay records schedule + queue + concurrency', () async {
    await tracedDefer<String>(
      operation: 'function.delay',
      invoke: () async => const DeferCallResult(
        value: 'ok',
        result: DeferResult(
          executionId: 'exec_1',
          functionName: 'sendEmail',
          queue: 'mailers',
          scheduleType: 'delay',
          state: 'created',
          maxConcurrency: 5,
          scheduledForSec: 3600,
          statusCode: 201,
        ),
      ),
    );
    final a = attrsOf(spans.findSpanByName('defer function.delay')!);
    expect(a['defer.function.name'], 'sendEmail');
    expect(a['defer.queue'], 'mailers');
    expect(a['defer.schedule.type'], 'delay');
    expect(a['defer.state'], 'created');
    expect(a['defer.max_concurrency'], 5);
    expect(a['defer.scheduled_for_sec'], 3600);
  });

  test('failed state sets span error', () async {
    await tracedDefer<String>(
      operation: 'execution.get',
      invoke: () async => const DeferCallResult(
        value: 'ok',
        result: DeferResult(
          state: 'failed',
          retryCount: 3,
          executionTimeMs: 4500,
        ),
      ),
    );
    expect(
      spans.findSpanByName('defer execution.get')!.status,
      SpanStatusCode.Error,
    );
  });

  test('suppression skips spans', () async {
    await runWithoutDeferInstrumentationAsync(() async {
      await tracedDefer<String>(
        operation: 'function.enqueue',
        invoke: () async => const DeferCallResult(value: 'v'),
      );
    });
    expect(spans.findSpansStartingWith('defer '), isEmpty);
  });
}
