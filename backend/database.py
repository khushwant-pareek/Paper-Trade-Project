from datetime import datetime
import enum
from sqlalchemy import Column, Integer, String, Float, DateTime, ForeignKey, Enum, create_engine
from sqlalchemy.orm import declarative_base, sessionmaker

DATABASE_URL = "sqlite:///./trading.db"
engine = create_engine(DATABASE_URL, connect_args={"check_same_thread": False})
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

class OrderProduct(str, enum.Enum):
    CNC = "CNC"  # Delivery (1x)
    MIS = "MIS"  # Intraday (5x Leverage)

class OrderType(str, enum.Enum):
    MARKET = "MARKET"
    LIMIT = "LIMIT"
    SL = "SL"

class OrderSide(str, enum.Enum):
    BUY = "BUY"
    SELL = "SELL"

class OrderStatus(str, enum.Enum):
    PENDING = "PENDING"
    FILLED = "FILLED"
    REJECTED = "REJECTED"
    CANCELLED = "CANCELLED"

class User(Base):
    __tablename__ = "users"
    id = Column(Integer, primary_key=True, index=True)
    virtual_cash = Column(Float, default=1000000.0)

class Order(Base):
    __tablename__ = "orders"
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"))
    symbol = Column(String, nullable=False)
    side = Column(Enum(OrderSide), nullable=False)
    product = Column(Enum(OrderProduct), default=OrderProduct.CNC)
    order_type = Column(Enum(OrderType), default=OrderType.MARKET)
    quantity = Column(Integer, nullable=False)
    limit_price = Column(Float, nullable=True)
    trigger_price = Column(Float, nullable=True)
    executed_price = Column(Float, nullable=True)
    status = Column(Enum(OrderStatus), default=OrderStatus.PENDING)
    rejection_reason = Column(String, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)

class Position(Base):
    __tablename__ = "positions"
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"))
    symbol = Column(String, nullable=False)
    product = Column(Enum(OrderProduct), default=OrderProduct.CNC)
    quantity = Column(Integer, default=0)
    avg_price = Column(Float, default=0.0)

Base.metadata.create_all(bind=engine)