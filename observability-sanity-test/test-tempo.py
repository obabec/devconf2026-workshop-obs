"""
Sends OTLP traces to Tempo via the gateway ingress.

Simulates a frontend -> api -> database call chain so that
the service graph shows at least 3 nodes with edges between them.
"""

import time
import random
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.resources import Resource
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.trace import SpanKind
from opentelemetry.trace.propagation.tracecontext import TraceContextTextMapPropagator

ENDPOINT = "http://tempo-gateway.k8s.orb.local/otlp/v1/traces"
TRACE_COUNT = 10


def make_provider(service_name: str) -> TracerProvider:
    resource = Resource({"service.name": service_name})
    provider = TracerProvider(resource=resource)
    provider.add_span_processor(
        BatchSpanProcessor(OTLPSpanExporter(endpoint=ENDPOINT))
    )
    return provider


frontend_provider = make_provider("frontend")
api_provider = make_provider("api")
db_provider = make_provider("database")

frontend_tracer = frontend_provider.get_tracer("frontend")
api_tracer = api_provider.get_tracer("api")
db_tracer = db_provider.get_tracer("database")

propagator = TraceContextTextMapPropagator()

print(f"Sending {TRACE_COUNT} traces to {ENDPOINT} ...")

for i in range(TRACE_COUNT):
    carrier = {}

    # frontend (CLIENT) -> api
    with frontend_tracer.start_as_current_span(
        "GET /products",
        kind=SpanKind.CLIENT,
        attributes={"http.method": "GET", "http.url": "http://api/products"},
    ) as frontend_span:
        propagator.inject(carrier)
        ctx = propagator.extract(carrier)

        # api (SERVER) -> database
        with api_tracer.start_as_current_span(
            "api.list_products",
            context=ctx,
            kind=SpanKind.SERVER,
            attributes={"http.method": "GET", "http.route": "/products"},
        ) as api_span:
            carrier2 = {}
            propagator.inject(carrier2)
            ctx2 = propagator.extract(carrier2)

            # database (SERVER)
            with db_tracer.start_as_current_span(
                "db.query",
                context=ctx2,
                kind=SpanKind.SERVER,
                attributes={
                    "db.system": "postgresql",
                    "db.statement": "SELECT * FROM products",
                },
            ):
                time.sleep(random.uniform(0.01, 0.05))

            time.sleep(random.uniform(0.005, 0.02))

        time.sleep(random.uniform(0.001, 0.01))

    time.sleep(0.2)

frontend_provider.shutdown()
api_provider.shutdown()
db_provider.shutdown()

print("Done.")
