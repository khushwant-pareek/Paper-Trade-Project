import random
from typing import Optional
from fastapi import FastAPI, Depends, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session
from pydantic import BaseModel
import yfinance as yf
import pandas as pd
from database import SessionLocal, Order, Position, User, OrderSide, OrderType, OrderProduct, OrderStatus
from engine import execute_order

app = FastAPI(title="Professional Indian Paper Trading API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

SYMBOLS = ["RELIANCE", "TCS", "HDFCBANK", "INFY", "SBIN", "ICICIBANK", "LT", "BHARTIARTL"]

def fetch_single_price(symbol: str) -> float:
    try:
        t = yf.Ticker(f"{symbol.upper()}.NS")
        price = t.fast_info.get("last_price")
        if price:
            return round(float(price), 2)
        hist = t.history(period="1d")
        if not hist.empty:
            return round(float(hist["Close"].iloc[-1]), 2)
    except Exception:
        pass
    return 1500.0

@app.get("/api/v1/quotes")
def get_watchlist():
    tickers = " ".join([f"{s}.NS" for s in SYMBOLS])
    quotes = []
    try:
        data = yf.download(tickers=tickers, period="5d", interval="1d", group_by="ticker", progress=False)
        for sym in SYMBOLS:
            ticker_ns = f"{sym}.NS"
            try:
                df = data[ticker_ns] if len(SYMBOLS) > 1 else data
                closes = df["Close"].dropna()
                ltp = round(float(closes.iloc[-1]), 2) if len(closes) >= 1 else 1500.0
                prev = round(float(closes.iloc[-2]), 2) if len(closes) >= 2 else ltp
                chg = round(ltp - prev, 2)
                pct = round((chg / prev) * 100, 2) if prev else 0.0
                quotes.append({
                    "symbol": sym,
                    "exchange": "NSE",
                    "ltp": ltp,
                    "change": chg,
                    "percentChange": pct,
                })
            except Exception:
                quotes.append({"symbol": sym, "exchange": "NSE", "ltp": 1500.0, "change": 0.0, "percentChange": 0.0})
    except Exception:
        for sym in SYMBOLS:
            quotes.append({"symbol": sym, "exchange": "NSE", "ltp": 1500.0, "change": 0.0, "percentChange": 0.0})
    return quotes

@app.get("/api/v1/charts/{symbol}")
def get_chart_with_indicators(symbol: str, interval: str = "15m"):
    period_map = {"1m": "1d", "5m": "5d", "15m": "5d", "1h": "1mo", "1d": "6mo"}
    period = period_map.get(interval.lower(), "5d")
    candles = []
    
    try:
        t = yf.Ticker(f"{symbol.upper()}.NS")
        df = t.history(period=period, interval=interval)
        if df.empty or len(df) < 3:
            df = t.history(period="1mo", interval="1d")

        if not df.empty and len(df) >= 3:
            df["EMA9"] = df["Close"].ewm(span=9, adjust=False).mean()
            df["EMA21"] = df["Close"].ewm(span=21, adjust=False).mean()
            for idx, row in df.iterrows():
                candles.append({
                    "timestamp": int(idx.timestamp() * 1000),
                    "open": round(float(row["Open"]), 2),
                    "high": round(float(row["High"]), 2),
                    "low": round(float(row["Low"]), 2),
                    "close": round(float(row["Close"]), 2),
                    "volume": int(row["Volume"]),
                    "ema9": round(float(row["EMA9"]), 2) if pd.notna(row["EMA9"]) else None,
                    "ema21": round(float(row["EMA21"]), 2) if pd.notna(row["EMA21"]) else None,
                })
            return candles
    except Exception:
        pass

    # Guaranteed Fallback: Generate realistic synthetic candles if market feed is closed/empty
    base = fetch_single_price(symbol)
    import time
    now_ms = int(time.time() * 1000)
    for i in range(30, 0, -1):
        step_delta = random.uniform(-0.008, 0.008) * base
        o = round(base + step_delta, 2)
        h = round(o + random.uniform(0.5, 3.0), 2)
        l = round(o - random.uniform(0.5, 3.0), 2)
        c = round(random.uniform(l, h), 2)
        base = c
        candles.append({
            "timestamp": now_ms - (i * 15 * 60 * 1000),
            "open": o,
            "high": h,
            "low": l,
            "close": c,
            "volume": random.randint(1500, 25000),
            "ema9": round(c * 0.998, 2),
            "ema21": round(c * 0.995, 2),
        })
    return candles

@app.get("/api/v1/depth/{symbol}")
def get_market_depth(symbol: str):
    ltp = fetch_single_price(symbol)
    bids, asks = [], []
    for i in range(1, 6):
        bids.append({
            "price": round(ltp - (i * 0.25), 2),
            "orders": random.randint(10, 85),
            "quantity": random.randint(200, 3500)
        })
        asks.append({
            "price": round(ltp + (i * 0.25), 2),
            "orders": random.randint(10, 85),
            "quantity": random.randint(200, 3500)
        })
    return {
        "symbol": symbol,
        "ltp": ltp,
        "bids": bids,
        "asks": asks,
        "total_bid_qty": sum(b["quantity"] for b in bids),
        "total_ask_qty": sum(a["quantity"] for a in asks)
    }

@app.get("/api/v1/portfolio")
def get_portfolio(db: Session = Depends(get_db)):
    user = db.query(User).filter(User.id == 1).first()
    if not user:
        user = User(id=1, virtual_cash=1000000.0)
        db.add(user)
        db.commit()
        db.refresh(user)

    positions = db.query(Position).filter(Position.user_id == 1, Position.quantity > 0).all()
    results = []
    total_unrealized_pnl = 0.0
    for p in positions:
        current_ltp = fetch_single_price(p.symbol)
        pnl = round((current_ltp - p.avg_price) * p.quantity, 2)
        total_unrealized_pnl += pnl
        results.append({
            "symbol": p.symbol,
            "product": p.product.value,
            "quantity": p.quantity,
            "avg_price": p.avg_price,
            "ltp": current_ltp,
            "pnl": pnl
        })

    return {
        "virtual_cash": round(user.virtual_cash, 2),
        "total_pnl": round(total_unrealized_pnl, 2),
        "positions": results
    }

@app.get("/api/v1/orders")
def get_order_book(db: Session = Depends(get_db)):
    orders = db.query(Order).filter(Order.user_id == 1).order_by(Order.created_at.desc()).all()
    return [
        {
            "id": o.id,
            "symbol": o.symbol,
            "side": o.side.value,
            "product": o.product.value,
            "order_type": o.order_type.value,
            "quantity": o.quantity,
            "executed_price": o.executed_price,
            "limit_price": o.limit_price,
            "status": o.status.value,
            "rejection_reason": o.rejection_reason,
            "time": o.created_at.strftime("%H:%M:%S")
        } for o in orders
    ]

class PlaceOrderRequest(BaseModel):
    user_id: int = 1
    symbol: str
    side: OrderSide
    product: OrderProduct = OrderProduct.CNC
    order_type: OrderType = OrderType.MARKET
    quantity: int
    limit_price: Optional[float] = None
    trigger_price: Optional[float] = None

@app.post("/api/v1/orders/place")
def place_order(req: PlaceOrderRequest, db: Session = Depends(get_db)):
    sym = req.symbol.upper()
    current_price = fetch_single_price(sym)

    order = Order(
        user_id=req.user_id,
        symbol=sym,
        side=req.side,
        product=req.product,
        order_type=req.order_type,
        quantity=req.quantity,
        limit_price=req.limit_price,
        trigger_price=req.trigger_price
    )
    db.add(order)
    db.commit()
    db.refresh(order)

    res = execute_order(db, order, current_price)
    return {"order_id": order.id, "result": res}

class SquareOffRequest(BaseModel):
    user_id: int = 1
    symbol: str
    product: OrderProduct

@app.post("/api/v1/positions/square-off")
def square_off(req: SquareOffRequest, db: Session = Depends(get_db)):
    pos = db.query(Position).filter(
        Position.user_id == req.user_id,
        Position.symbol == req.symbol.upper(),
        Position.product == req.product,
        Position.quantity > 0
    ).first()
    if not pos:
        raise HTTPException(status_code=404, detail="Active position not found")

    price = fetch_single_price(pos.symbol)
    order = Order(
        user_id=req.user_id,
        symbol=pos.symbol,
        side=OrderSide.SELL,
        product=req.product,
        order_type=OrderType.MARKET,
        quantity=pos.quantity
    )
    db.add(order)
    db.commit()
    db.refresh(order)
    res = execute_order(db, order, price)
    return {"order_id": order.id, "result": res}