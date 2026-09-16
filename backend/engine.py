from sqlalchemy.orm import Session
from database import Order, Position, User, OrderSide, OrderStatus, OrderProduct, OrderType

SLIPPAGE_RATE = 0.0005  # 0.05% realistic fill slippage
BROKERAGE_FLAT = 20.0   # Zerodha style ₹20 or 0.03%
STT_DELIVERY = 0.001    # 0.1% STT on Delivery
STT_INTRADAY = 0.00025  # 0.025% STT on Intraday Sell
GST_RATE = 0.18         # 18% on Brokerage + Exchange turnover

def calculate_statutory_charges(price: float, quantity: int, side: OrderSide, product: OrderProduct):
    turnover = price * quantity
    brokerage = min(BROKERAGE_FLAT, turnover * 0.0003)
    gst = brokerage * GST_RATE
    stt = (turnover * STT_DELIVERY) if product == OrderProduct.CNC else (turnover * STT_INTRADAY if side == OrderSide.SELL else 0.0)
    total_charges = round(brokerage + gst + stt, 2)
    return turnover, total_charges

def execute_order(db: Session, order: Order, current_market_price: float):
    user = db.query(User).filter(User.id == order.user_id).first()
    if not user:
        order.status = OrderStatus.REJECTED
        order.rejection_reason = "User account not found"
        db.commit()
        return {"status": "REJECTED", "message": order.rejection_reason}

    # Verify Limit & SL Triggers
    if order.order_type == OrderType.LIMIT and order.limit_price is not None:
        if order.side == OrderSide.BUY and current_market_price > order.limit_price:
            order.status = OrderStatus.PENDING
            db.commit()
            return {"status": "PENDING", "message": "Limit buy placed below market"}
        elif order.side == OrderSide.SELL and current_market_price < order.limit_price:
            order.status = OrderStatus.PENDING
            db.commit()
            return {"status": "PENDING", "message": "Limit sell placed above market"}

    fill_price = current_market_price
    if order.order_type == OrderType.MARKET:
        fill_price = round(current_market_price * (1.0 + SLIPPAGE_RATE if order.side == OrderSide.BUY else 1.0 - SLIPPAGE_RATE), 2)

    turnover, charges = calculate_statutory_charges(fill_price, order.quantity, order.side, order.product)
    margin_required = (turnover / 5.0) if order.product == OrderProduct.MIS else turnover
    total_outlay = margin_required + charges

    if order.side == OrderSide.BUY:
        if user.virtual_cash < total_outlay:
            order.status = OrderStatus.REJECTED
            order.rejection_reason = f"Insufficient margin. Required ₹{total_outlay:.2f}, Available ₹{user.virtual_cash:.2f}"
            db.commit()
            return {"status": "REJECTED", "message": order.rejection_reason}

        user.virtual_cash -= total_outlay
        pos = db.query(Position).filter(
            Position.user_id == order.user_id,
            Position.symbol == order.symbol,
            Position.product == order.product
        ).first()

        if pos:
            new_qty = pos.quantity + order.quantity
            pos.avg_price = round(((pos.avg_price * pos.quantity) + (fill_price * order.quantity)) / new_qty, 2)
            pos.quantity = new_qty
        else:
            pos = Position(
                user_id=order.user_id,
                symbol=order.symbol,
                product=order.product,
                quantity=order.quantity,
                avg_price=fill_price
            )
            db.add(pos)

    elif order.side == OrderSide.SELL:
        pos = db.query(Position).filter(
            Position.user_id == order.user_id,
            Position.symbol == order.symbol,
            Position.product == order.product
        ).first()

        if not pos or pos.quantity < order.quantity:
            order.status = OrderStatus.REJECTED
            order.rejection_reason = "Insufficient stock holding to sell"
            db.commit()
            return {"status": "REJECTED", "message": order.rejection_reason}

        user.virtual_cash += (turnover - charges)
        pos.quantity -= order.quantity
        if pos.quantity == 0:
            db.delete(pos)

    order.executed_price = fill_price
    order.status = OrderStatus.FILLED
    db.commit()
    db.refresh(order)
    db.refresh(user)

    return {
        "status": "FILLED",
        "fill_price": fill_price,
        "charges": charges,
        "product": order.product.value,
        "remaining_cash": round(user.virtual_cash, 2)
    }