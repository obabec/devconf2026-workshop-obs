"""
Runs observability-sanity-test-tempo and observability-sanity-test-mimir in a continuous loop until Ctrl+C.
"""

import time
import random
import signal
import sys
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.resources import Resource
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.trace import SpanKind
from opentelemetry.trace.propagation.tracecontext import TraceContextTextMapPropagator
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.exporter.otlp.proto.http.metric_exporter import OTLPMetricExporter

TEMPO_ENDPOINT = "http://tempo-gateway.k8s.orb.local/otlp/v1/traces"
MIMIR_ENDPOINT = "http://mimir.k8s.orb.local/otlp/v1/metrics"

running = True


def handle_stop(sig, frame):
    global running
    print("\nStopping...")
    running = False


signal.signal(signal.SIGINT, handle_stop)
signal.signal(signal.SIGTERM, handle_stop)


def make_trace_provider(service_name: str) -> TracerProvider:
    provider = TracerProvider(resource=Resource({"service.name": service_name}))
    provider.add_span_processor(
        BatchSpanProcessor(OTLPSpanExporter(endpoint=TEMPO_ENDPOINT))
    )
    return provider


frontend_provider = make_trace_provider("frontend")
api_provider = make_trace_provider("api")
db_provider = make_trace_provider("database")

frontend_tracer = frontend_provider.get_tracer("frontend")
api_tracer = api_provider.get_tracer("api")
db_tracer = db_provider.get_tracer("database")

propagator = TraceContextTextMapPropagator()

metric_exporter = OTLPMetricExporter(
    endpoint=MIMIR_ENDPOINT,
    headers={"X-Scope-OrgID": "anonymous"},
)
metric_reader = PeriodicExportingMetricReader(metric_exporter, export_interval_millis=2000)
metric_provider = MeterProvider(
    resource=Resource({"service.name": "observability-sanity-test-mimir"}),
    metric_readers=[metric_reader],
)
meter = metric_provider.get_meter("observability-sanity-test-mimir")
requests_counter = meter.create_counter("test_requests_total")
latency_histogram = meter.create_histogram(
    "test_latency_ms",
    description="Simulated request latency in milliseconds",
    unit="ms",
)

print("Running — press Ctrl+C to stop\n")

iteration = 0
while running:
    iteration += 1

    # traces
    carrier = {}
    with frontend_tracer.start_as_current_span(
        "GET /products", kind=SpanKind.CLIENT,
        attributes={"http.method": "GET", "http.url": "http://api/products"},
    ):
        propagator.inject(carrier)
        ctx = propagator.extract(carrier)
        with api_tracer.start_as_current_span(
            "api.list_products", context=ctx, kind=SpanKind.SERVER,
            attributes={"http.method": "GET", "http.route": "/products"},
        ):
            carrier2 = {}
            propagator.inject(carrier2)
            ctx2 = propagator.extract(carrier2)
            with db_tracer.start_as_current_span(
                "db.query", context=ctx2, kind=SpanKind.SERVER,
                attributes={"db.system": "postgresql", "db.statement": "SELECT * FROM products"},
            ):
                time.sleep(random.uniform(0.01, 0.05))

    # metrics
    latency = random.uniform(10, 500)
    requests_counter.add(1, {"status": "ok"})
    latency_histogram.record(latency, {"endpoint": "/products"})

    print(f"[{iteration}] trace sent, latency={latency:.1f}ms")
    time.sleep(5)

frontend_provider.shutdown()
api_provider.shutdown()
db_provider.shutdown()
metric_provider.shutdown()
print("Done.")
