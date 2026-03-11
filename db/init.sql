-- ═══════════════════════════════════════════════════════════
-- Crypto Trading Bot — Postgres Schema
-- Run once: psql -U postgres -d crypto_trading -f init.sql
-- ═══════════════════════════════════════════════════════════

CREATE DATABASE IF NOT EXISTS crypto_trading;

-- ── Signals table: every TA signal generated ────────────────
CREATE TABLE IF NOT EXISTS signals (
    id              BIGSERIAL PRIMARY KEY,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    symbol          VARCHAR(20)  NOT NULL,
    side            VARCHAR(4)   NOT NULL CHECK (side IN ('BUY','SELL','HOLD')),
    entry_price     NUMERIC(18,8),
    tp_price        NUMERIC(18,8),
    sl_price        NUMERIC(18,8),
    confidence      NUMERIC(5,4),
    rsi             NUMERIC(6,2),
    ema20           NUMERIC(18,8),
    ema50           NUMERIC(18,8),
    ema200          NUMERIC(18,8),
    macd            NUMERIC(18,8),
    news_impact     INTEGER,
    sentiment_score INTEGER,
    risk_approved   BOOLEAN,
    rejection_reason TEXT,
    kelly_fraction  NUMERIC(8,6),
    position_qty    NUMERIC(18,6),
    leverage        NUMERIC(5,2),
    risk_usd        NUMERIC(12,2),
    equity_snapshot NUMERIC(18,2)
);

CREATE INDEX IF NOT EXISTS idx_signals_symbol_time ON signals(symbol, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_signals_side        ON signals(side);

-- ── Trades table: executed orders ───────────────────────────
CREATE TABLE IF NOT EXISTS trades (
    id              BIGSERIAL PRIMARY KEY,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    signal_id       BIGINT REFERENCES signals(id),
    order_id        VARCHAR(50)  UNIQUE,
    symbol          VARCHAR(20)  NOT NULL,
    side            VARCHAR(4)   NOT NULL,
    order_type      VARCHAR(10)  NOT NULL DEFAULT 'Market',
    qty             NUMERIC(18,6) NOT NULL,
    entry_price     NUMERIC(18,8),
    tp_price        NUMERIC(18,8),
    sl_price        NUMERIC(18,8),
    leverage        NUMERIC(5,2),
    status          VARCHAR(20)  NOT NULL DEFAULT 'NEW',
    close_price     NUMERIC(18,8),
    pnl             NUMERIC(18,8),
    pnl_pct         NUMERIC(8,4),
    fees            NUMERIC(18,8),
    bybit_response  JSONB,
    is_simulated    BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE INDEX IF NOT EXISTS idx_trades_symbol_time ON trades(symbol, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_trades_status      ON trades(status);
CREATE INDEX IF NOT EXISTS idx_trades_order_id    ON trades(order_id);

-- ── Agent logs: each AI agent invocation ────────────────────
CREATE TABLE IF NOT EXISTS agent_logs (
    id              BIGSERIAL PRIMARY KEY,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    agent_name      VARCHAR(30)  NOT NULL,
    model           VARCHAR(80),
    symbol          VARCHAR(20),
    input_tokens    INTEGER,
    output_tokens   INTEGER,
    latency_ms      INTEGER,
    prompt_excerpt  TEXT,
    response_excerpt TEXT,
    error           TEXT
);

CREATE INDEX IF NOT EXISTS idx_agent_logs_agent_time ON agent_logs(agent_name, created_at DESC);

-- ── Daily P&L summary ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS daily_stats (
    id              BIGSERIAL PRIMARY KEY,
    trade_date      DATE UNIQUE NOT NULL,
    total_trades    INTEGER DEFAULT 0,
    winning_trades  INTEGER DEFAULT 0,
    losing_trades   INTEGER DEFAULT 0,
    total_pnl       NUMERIC(18,8) DEFAULT 0,
    total_fees      NUMERIC(18,8) DEFAULT 0,
    max_drawdown    NUMERIC(8,4)  DEFAULT 0,
    win_rate        NUMERIC(6,4)  DEFAULT 0,
    starting_equity NUMERIC(18,2),
    ending_equity   NUMERIC(18,2)
);

-- ── Market data cache (optional, for backtesting) ───────────
CREATE TABLE IF NOT EXISTS kline_cache (
    id              BIGSERIAL PRIMARY KEY,
    symbol          VARCHAR(20)  NOT NULL,
    interval_min    INTEGER      NOT NULL,
    open_time       TIMESTAMPTZ  NOT NULL,
    open            NUMERIC(18,8),
    high            NUMERIC(18,8),
    low             NUMERIC(18,8),
    close           NUMERIC(18,8),
    volume          NUMERIC(24,8),
    UNIQUE (symbol, interval_min, open_time)
);

CREATE INDEX IF NOT EXISTS idx_kline_symbol_time ON kline_cache(symbol, interval_min, open_time DESC);

-- ── Trigger: auto-update updated_at on trades ───────────────
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trades_updated_at ON trades;
CREATE TRIGGER trades_updated_at
    BEFORE UPDATE ON trades
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ── Daily stats rollup function ─────────────────────────────
CREATE OR REPLACE FUNCTION upsert_daily_stats(p_date DATE)
RETURNS VOID AS $$
BEGIN
    INSERT INTO daily_stats (
        trade_date, total_trades, winning_trades, losing_trades,
        total_pnl, total_fees, win_rate
    )
    SELECT
        DATE(created_at) AS trade_date,
        COUNT(*) AS total_trades,
        COUNT(*) FILTER (WHERE pnl > 0) AS winning_trades,
        COUNT(*) FILTER (WHERE pnl <= 0) AS losing_trades,
        COALESCE(SUM(pnl), 0) AS total_pnl,
        COALESCE(SUM(fees), 0) AS total_fees,
        CASE WHEN COUNT(*) > 0
             THEN COUNT(*) FILTER (WHERE pnl > 0)::NUMERIC / COUNT(*)
             ELSE 0 END AS win_rate
    FROM trades
    WHERE DATE(created_at) = p_date
      AND status IN ('Filled','PartiallyFilled')
    ON CONFLICT (trade_date) DO UPDATE SET
        total_trades   = EXCLUDED.total_trades,
        winning_trades = EXCLUDED.winning_trades,
        losing_trades  = EXCLUDED.losing_trades,
        total_pnl      = EXCLUDED.total_pnl,
        total_fees     = EXCLUDED.total_fees,
        win_rate       = EXCLUDED.win_rate;
END;
$$ LANGUAGE plpgsql;

COMMENT ON TABLE signals      IS 'Every TA signal produced by the 4-agent pipeline';
COMMENT ON TABLE trades       IS 'Orders placed on Bybit (demo/live)';
COMMENT ON TABLE agent_logs   IS 'Per-invocation logs for all AI agents';
COMMENT ON TABLE daily_stats  IS 'Aggregated daily trading performance';
COMMENT ON TABLE kline_cache  IS 'Local OHLCV cache for backtesting and indicator computation';
