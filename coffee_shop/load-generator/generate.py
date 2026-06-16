"""
Continuously generates traffic against the coffee shop API.
Run: python generate.py
"""
import os
import time
import random
import httpx
import logging

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)

BASE_URL = os.getenv("APP_URL", "http://app:8000")

MENU = [
    {"name": "espresso", "price": 2.50},
    {"name": "latte", "price": 4.00},
    {"name": "cappuccino", "price": 4.50},
    {"name": "americano", "price": 3.00},
    {"name": "croissant", "price": 3.50},
    {"name": "muffin", "price": 2.75},
]

CUSTOMERS = ["alice", "bob", "carol", "dave", "eve", "frank"]


def random_order():
    items = random.sample(MENU, k=random.randint(1, 3))
    return {
        "customer": random.choice(CUSTOMERS),
        "items": [
            {"name": item["name"], "quantity": random.randint(1, 2), "price": item["price"]}
            for item in items
        ],
    }


def main():
    logger.info("Starting load generator, target: %s", BASE_URL)
    while True:
        try:
            order = random_order()
            resp = httpx.post(f"{BASE_URL}/order", json=order, timeout=10)
            if resp.status_code == 200:
                data = resp.json()
                logger.info("Order %s created: status=%s total=%.2f", data["id"], data["status"], data["total_price"])
            else:
                logger.warning("Order failed: %s %s", resp.status_code, resp.text)
        except Exception as e:
            logger.error("Request error: %s", e)

        time.sleep(random.uniform(0.5, 2.0))


if __name__ == "__main__":
    main()
