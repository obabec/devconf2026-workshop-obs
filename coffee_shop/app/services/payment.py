import time
import random
import logging
from opentelemetry import trace

logger = logging.getLogger(__name__)
tracer = trace.get_tracer(__name__)


class PaymentService:
    def process(self, order_id: str, amount: float) -> bool:
        with tracer.start_as_current_span("process_payment") as span:
            span.set_attribute("payment.order_id", order_id)
            span.set_attribute("payment.amount", amount)

            start = time.time()

            # Intentional latency bug — simulates slow payment gateway
            if random.random() < 0.1:
                time.sleep(4)

            # Simulate occasional payment failure
            if random.random() < 0.05:
                span.set_attribute("payment.success", False)
                span.set_attribute("payment.failure_reason", "card_declined")
                logger.warning(f"Payment declined for order {order_id}")
                return False

            duration_ms = (time.time() - start) * 1000
            span.set_attribute("payment.success", True)
            span.set_attribute("payment.duration_ms", duration_ms)
            logger.info(f"Payment processed for order {order_id}, amount={amount}, duration={duration_ms:.1f}ms")
            return True
