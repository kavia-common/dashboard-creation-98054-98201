"""
SQLAlchemy ORM models for the Dashboard application database.

These models mirror the PostgreSQL schema defined in schema.sql and are meant
to be imported by the FastAPI BackendAPIService. They include relationships,
indexes, and constraints to support:
- Authentication (users with roles, password hashes, active flags)
- CRUD for users and reports
- Charts and data sources (line, bar, pie) with configurable visualization and origins
"""

from __future__ import annotations

import enum
from datetime import datetime
from typing import Optional, List

from sqlalchemy import (
    Column,
    String,
    Text,
    Enum,
    Boolean,
    DateTime,
    ForeignKey,
    Integer,
    JSON,
    UniqueConstraint,
    Index,
    BigInteger,
)
from sqlalchemy.dialects.postgresql import UUID, JSONB, CITEXT
from sqlalchemy.orm import declarative_base, relationship, Mapped, mapped_column

Base = declarative_base()


class UserRole(str, enum.Enum):
    admin = "admin"
    user = "user"


class ChartType(str, enum.Enum):
    line = "line"
    bar = "bar"
    pie = "pie"


class DataSourceType(str, enum.Enum):
    static = "static"
    sql = "sql"
    api = "api"


# PUBLIC_INTERFACE
class User(Base):
    """User account with authentication fields and roles."""
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(UUID(as_uuid=False), primary_key=True)
    email: Mapped[str] = mapped_column(CITEXT, unique=True, nullable=False)
    password_hash: Mapped[str] = mapped_column(Text, nullable=False)
    full_name: Mapped[Optional[str]] = mapped_column(String(255))
    role: Mapped[UserRole] = mapped_column(Enum(UserRole, name="user_role"), default=UserRole.user, nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    last_login_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow, nullable=False)
    is_deleted: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    deleted_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))

    # relationships
    owned_reports: Mapped[List["Report"]] = relationship("Report", back_populates="owner", cascade="all, delete-orphan")
    created_sources: Mapped[List["ChartDataSource"]] = relationship("ChartDataSource", back_populates="creator")

    __table_args__ = (
        Index("idx_users_email", "email"),
        Index("idx_users_active", "is_active", postgresql_where=(Column("is_active") == True)),  # type: ignore
    )


# PUBLIC_INTERFACE
class Report(Base):
    """Report groups multiple charts and is owned by a user."""
    __tablename__ = "reports"

    id: Mapped[str] = mapped_column(UUID(as_uuid=False), primary_key=True)
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    description: Mapped[Optional[str]] = mapped_column(Text)
    owner_id: Mapped[str] = mapped_column(UUID(as_uuid=False), ForeignKey("users.id", onupdate="CASCADE", ondelete="RESTRICT"), nullable=False)
    is_public: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow, nullable=False)
    is_deleted: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    deleted_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))

    # relationships
    owner: Mapped[User] = relationship("User", back_populates="owned_reports")
    charts: Mapped[List["Chart"]] = relationship("Chart", back_populates="report", cascade="all, delete-orphan")
    collaborators: Mapped[List["ReportCollaborator"]] = relationship("ReportCollaborator", back_populates="report", cascade="all, delete-orphan")

    __table_args__ = (
        Index("idx_reports_owner_id", "owner_id"),
        Index("idx_reports_public", "is_public"),
    )


# PUBLIC_INTERFACE
class ChartDataSource(Base):
    """Defines where chart data originates (static JSON, SQL query, or external API)."""
    __tablename__ = "chart_data_sources"

    id: Mapped[str] = mapped_column(UUID(as_uuid=False), primary_key=True)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    source_type: Mapped[DataSourceType] = mapped_column(Enum(DataSourceType, name="data_source_type"), nullable=False)
    static_payload = mapped_column(JSONB)  # Only for 'static'
    sql_query = mapped_column(Text)        # Only for 'sql'
    api_endpoint = mapped_column(Text)     # Only for 'api'
    api_method: Mapped[Optional[str]] = mapped_column(String(10), default="GET")
    api_headers = mapped_column(JSONB)
    filters_schema = mapped_column(JSONB)

    created_by: Mapped[str] = mapped_column(UUID(as_uuid=False), ForeignKey("users.id", onupdate="CASCADE", ondelete="RESTRICT"), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow, nullable=False)
    is_deleted: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    deleted_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))

    # relationships
    creator: Mapped[User] = relationship("User", back_populates="created_sources")
    charts: Mapped[List["Chart"]] = relationship("Chart", back_populates="data_source")

    __table_args__ = (
        Index("idx_chart_data_sources_type", "source_type"),
        Index("idx_chart_data_sources_creator", "created_by"),
    )


# PUBLIC_INTERFACE
class Chart(Base):
    """A chart inside a report with configuration and link to its data source."""
    __tablename__ = "charts"

    id: Mapped[str] = mapped_column(UUID(as_uuid=False), primary_key=True)
    report_id: Mapped[str] = mapped_column(UUID(as_uuid=False), ForeignKey("reports.id", onupdate="CASCADE", ondelete="CASCADE"), nullable=False)
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    chart_kind: Mapped[ChartType] = mapped_column(Enum(ChartType, name="chart_type"), nullable=False)
    data_source_id: Mapped[str] = mapped_column(UUID(as_uuid=False), ForeignKey("chart_data_sources.id", onupdate="CASCADE", ondelete="RESTRICT"), nullable=False)
    visualization = mapped_column(JSONB)   # Frontend config (labels, colors, axes)
    default_params = mapped_column(JSONB)
    position: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow, nullable=False)
    is_deleted: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    deleted_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))

    # relationships
    report: Mapped["Report"] = relationship("Report", back_populates="charts")
    data_source: Mapped["ChartDataSource"] = relationship("ChartDataSource", back_populates="charts")
    cache_entries: Mapped[List["ChartDataCache"]] = relationship("ChartDataCache", back_populates="chart", cascade="all, delete-orphan")

    __table_args__ = (
        Index("idx_charts_report_id", "report_id"),
        Index("idx_charts_data_source_id", "data_source_id"),
        Index("idx_charts_position", "report_id", "position"),
    )


# PUBLIC_INTERFACE
class ReportCollaborator(Base):
    """User-specific access control to a report (beyond owner)."""
    __tablename__ = "report_collaborators"

    report_id: Mapped[str] = mapped_column(UUID(as_uuid=False), ForeignKey("reports.id", onupdate="CASCADE", ondelete="CASCADE"), primary_key=True)
    user_id: Mapped[str] = mapped_column(UUID(as_uuid=False), ForeignKey("users.id", onupdate="CASCADE", ondelete="CASCADE"), primary_key=True)
    can_edit: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    added_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow, nullable=False)

    # relationships
    report: Mapped["Report"] = relationship("Report", back_populates="collaborators")
    user: Mapped["User"] = relationship("User")


# PUBLIC_INTERFACE
class ChartDataCache(Base):
    """Cache for computed chart data for specific parameter sets."""
    __tablename__ = "chart_data_cache"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    chart_id: Mapped[str] = mapped_column(UUID(as_uuid=False), ForeignKey("charts.id", onupdate="CASCADE", ondelete="CASCADE"), nullable=False)
    params_hash: Mapped[str] = mapped_column(Text, nullable=False)
    payload = mapped_column(JSONB, nullable=False)
    computed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow, nullable=False)
    expires_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))

    # relationships
    chart: Mapped["Chart"] = relationship("Chart", back_populates="cache_entries")

    __table_args__ = (
        UniqueConstraint("chart_id", "params_hash", name="uq_chart_params_hash"),
        Index("idx_chart_data_cache_chart_expires", "chart_id", "expires_at"),
    )


# PUBLIC_INTERFACE
class AuthToken(Base):
    """Optional JWT token tracking/blacklist table."""
    __tablename__ = "auth_tokens"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    user_id: Mapped[str] = mapped_column(UUID(as_uuid=False), ForeignKey("users.id", onupdate="CASCADE", ondelete="CASCADE"), nullable=False)
    jti: Mapped[str] = mapped_column(Text, unique=True, nullable=False)
    issued_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    revoked: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    revoked_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow, nullable=False)

    # relationships
    user: Mapped["User"] = relationship("User")

    __table_args__ = (
        Index("idx_auth_tokens_user", "user_id"),
        Index("idx_auth_tokens_valid", "revoked", "expires_at"),
    )


# PUBLIC_INTERFACE
def get_public_models():
    """Return all ORM models intended for external import."""
    return {
        "User": User,
        "Report": Report,
        "Chart": Chart,
        "ChartDataSource": ChartDataSource,
        "ReportCollaborator": ReportCollaborator,
        "ChartDataCache": ChartDataCache,
        "AuthToken": AuthToken,
        "UserRole": UserRole,
        "ChartType": ChartType,
        "DataSourceType": DataSourceType,
        "Base": Base,
    }
