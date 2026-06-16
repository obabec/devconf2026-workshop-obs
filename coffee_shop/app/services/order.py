import time
import uuid
import logging
from opentelemetry import trace, metrics

from models import OrderRequest, OrderResponse, OrderStatus
from services.inventory import InventoryService
from services.payment import PaymentService

logger = logging.getLogger(__name__)
tracer = trace.get_tracer(__name__)
meter = metrics.get_meter(__name__)

orders_created = meter.create_counter(
    "orders_created_total",
    description="Total number of orders created",
)
orders_failed = meter.create_counter(
    "orders_failed_total",
    description="Total number of failed orders",
)
order_latency = meter.create_histogram(
    "order_latency_ms",
    description="Order processing latency in milliseconds",
    unit="ms",
)
payment_latency = meter.create_histogram(
    "payment_latency_ms",
    description="Payment processing latency in milliseconds",
    unit="ms",
)

_orders: dict[str, OrderResponse] = {}


class OrderService:
    def __init__(self):
        self.inventory = InventoryService()
        self.payment = PaymentService()

    def create(self, request: OrderRequest) -> OrderResponse:
        with tracer.start_as_current_span("POST /order") as span:
            start = time.time()
            order_id = str(uuid.uuid4())[:8]
            span.set_attribute("order.id", order_id)
            span.set_attribute("order.customer", request.customer)
            span.set_attribute("order.items_count", len(request.items))

            total_price = sum(item.price * item.quantity for item in request.items)
            span.set_attribute("order.total_price", total_price)

            with tracer.start_as_current_span("validate_order") as validate_span:
                if not request.items:
                    validate_span.set_attribute("validation.failed", True)
                    orders_failed.add(1, {"reason": "empty_order"})
                    raise ValueError("Order must have at least one item")
                validate_span.set_attribute("validation.passed", True)

            reserved = self.inventory.reserve(request.items)
            if not reserved:
                orders_failed.add(1, {"reason": "inventory_unavailable"})
                order = OrderResponse(
                    id=order_id,
                    customer=request.customer,
                    items=request.items,
                    total_price=total_price,
                    status=OrderStatus.failed,
                )
                _orders[order_id] = order
                return order

            payment_start = time.time()
            paid = self.payment.process(order_id, total_price)
            payment_duration = (time.time() - payment_start) * 1000
            payment_latency.record(payment_duration, {"status": "ok" if paid else "failed"})

            if not paid:
                self.inventory.restore(request.items)

            with tracer.start_as_current_span("update_status") as status_span:
                status = OrderStatus.paid if paid else OrderStatus.failed
                status_span.set_attribute("order.status", status.value)

                if not paid:
                    orders_failed.add(1, {"reason": "payment_failed"})

            order = OrderResponse(
                id=order_id,
                customer=request.customer,
                items=request.items,
                total_price=total_price,
                status=status,
            )
            _orders[order_id] = order

            duration = (time.time() - start) * 1000
            order_latency.record(duration, {"status": status.value})
            orders_created.add(1, {"status": status.value})
            span.set_attribute("order.duration_ms", duration)
            logger.info(f"Order {order_id} created: status={status.value}, total={total_price}, duration={duration:.1f}ms")
            return order

    def get(self, order_id: str) -> OrderResponse | None:
        return _orders.get(order_id)
