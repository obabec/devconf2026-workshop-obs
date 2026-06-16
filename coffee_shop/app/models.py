from pydantic import BaseModel
from typing import List, Optional
from enum import Enum


class OrderStatus(str, Enum):
    created = "created"
    paid = "paid"
    failed = "failed"
    completed = "completed"


class OrderItem(BaseModel):
    name: str
    quantity: int
    price: float


class OrderRequest(BaseModel):
    customer: str
    items: List[OrderItem]


class OrderResponse(BaseModel):
    id: str
    customer: str
    items: List[OrderItem]
    total_price: float
    status: OrderStatus


class PaymentRequest(BaseModel):
    order_id: str
    amount: float


class PaymentResponse(BaseModel):
    order_id: str
    success: bool
    message: str
