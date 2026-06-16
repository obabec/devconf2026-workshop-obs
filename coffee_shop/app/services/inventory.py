import time
import logging
from opentelemetry import trace

logger = logging.getLogger(__name__)
tracer = trace.get_tracer(__name__)

INVENTORY = {
    "espresso": 100,
    "latte": 80,
    "cappuccino": 80,
    "americano": 100,
    "croissant": 50,
    "muffin": 40,
}


class InventoryService:
    def reserve(self, items: list) -> bool:
        with tracer.start_as_current_span("reserve_inventory") as span:
            span.set_attribute("inventory.items_count", len(items))

            for item in items:
                name = item.name.lower()
                span.set_attribute(f"inventory.item.{name}", item.quantity)

                available = INVENTORY.get(name, 0)
                if available < item.quantity:
                    span.set_attribute("inventory.reservation_failed", True)
                    span.set_attribute("inventory.failed_item", name)
                    logger.warning(f"Insufficient inventory for {name}: requested {item.quantity}, available {available}")
                    return False

            for item in items:
                name = item.name.lower()
                INVENTORY[name] = INVENTORY.get(name, 0) - item.quantity

            span.set_attribute("inventory.reservation_success", True)
            logger.info(f"Reserved inventory for {len(items)} items")
            return True

    def restore(self, items: list) -> None:
        with tracer.start_as_current_span("restore_inventory") as span:
            span.set_attribute("inventory.items_count", len(items))
            for item in items:
                name = item.name.lower()
                INVENTORY[name] = INVENTORY.get(name, 0) + item.quantity
                span.set_attribute(f"inventory.item.{name}", item.quantity)
            span.set_attribute("inventory.restore_success", True)
            logger.info(f"Restored inventory for {len(items)} items")
