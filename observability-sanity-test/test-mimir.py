"""
Sends OTLP metrics to Mimir via the ingress.
Emits a counter and a gauge to verify ingestion end-to-end.
"""

import time
import random
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.sdk.resources import Resource
from opentelemetry.exporter.otlp.proto.http.metric_exporter import OTLPMetricExporter

ENDPOINT = "http://mimir.k8s.orb.local/otlp/v1/metrics"
ITERATIONS = 10
INTERVAL_MS = 2000


def main():
    resource = Resource({"service.name": "observability-sanity-test-mimir"})

    exporter = OTLPMetricExporter(endpoint=ENDPOINT, headers={"X-Scope-OrgID": "anonymous"})
    reader = PeriodicExportingMetricReader(exporter, export_interval_millis=INTERVAL_MS)
    provider = MeterProvider(resource=resource, metric_readers=[reader])

    meter = provider.get_meter("observability-sanity-test-mimir")

    requests_counter = meter.create_counter(
        "test_requests_total",
        description="Total number of observability-sanity-test requests",
    )
    latency_histogram = meter.create_histogram(
        "test_latency_ms",
        description="Simulated request latency in milliseconds",
        unit="ms",
    )

    print(f"Sending metrics to {ENDPOINT} ({ITERATIONS} iterations) ...")

    for i in range(ITERATIONS):
        latency = random.uniform(10, 500)
        requests_counter.add(1, {"status": "ok"})
        latency_histogram.record(latency, {"endpoint": "/products"})
        print(f"  [{i+1}/{ITERATIONS}] latency={latency:.1f}ms")
        time.sleep(INTERVAL_MS / 1000)

    provider.shutdown()
    print("Done.")


if __name__ == "__main__":
    main()
