import os
import json
import logging
import time
from fastapi import FastAPI, HTTPException
from opentelemetry import trace, metrics
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.exporter.otlp.proto.http.metric_exporter import OTLPMetricExporter
from opentelemetry.sdk.metrics._internal.exemplar.exemplar_filter import TraceBasedExemplarFilter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor

from models import OrderRequest, OrderResponse, PaymentRequest, PaymentResponse
from services.order import OrderService

logging.basicConfig(
    level=logging.INFO,
    format='{"time": "%(asctime)s", "level": "%(levelname)s", "message": "%(message)s"}',
)
logger = logging.getLogger(__name__)

OTEL_ENDPOINT = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://otel-collector:4318")

tracer_provider = TracerProvider()
tracer_provider.add_span_processor(
    BatchSpanProcessor(OTLPSpanExporter(endpoint=f"{OTEL_ENDPOINT}/v1/traces"))
)
trace.set_tracer_provider(tracer_provider)

meter_provider = MeterProvider(
    metric_readers=[
        PeriodicExportingMetricReader(
            OTLPMetricExporter(endpoint=f"{OTEL_ENDPOINT}/v1/metrics"),
            export_interval_millis=5000,
        )
    ],
    exemplar_filter=TraceBasedExemplarFilter(),
)
metrics.set_meter_provider(meter_provider)

app = FastAPI(title="Coffee Shop Order System", version="1.0.0")
FastAPIInstrumentor.instrument_app(app)

order_service = OrderService()


@app.post("/order", response_model=OrderResponse)
async def create_order(request: OrderRequest):
    try:
        order = order_service.create(request)
        return order
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@app.get("/order/{order_id}", response_model=OrderResponse)
async def get_order(order_id: str):
    order = order_service.get(order_id)
    if not order:
        raise HTTPException(status_code=404, detail=f"Order {order_id} not found")
    return order


@app.post("/payment", response_model=PaymentResponse)
async def process_payment(request: PaymentRequest):
    order = order_service.get(request.order_id)
    if not order:
        raise HTTPException(status_code=404, detail=f"Order {request.order_id} not found")

    from services.payment import PaymentService
    svc = PaymentService()
    success = svc.process(request.order_id, request.amount)

    return PaymentResponse(
        order_id=request.order_id,
        success=success,
        message="Payment accepted" if success else "Payment declined",
    )


@app.get("/stats")
async def get_stats():
    return {
        "service": "coffee-shop",
        "status": "running",
        "otel_endpoint": OTEL_ENDPOINT,
    }


@app.get("/health")
async def health():
    return {"status": "ok"}
