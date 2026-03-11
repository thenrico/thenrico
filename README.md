# Crypto Trading Bot — Bybit Demo (n8n Automation)

Autonomous 4-agent crypto trading system running on local n8n, using Bybit demo API.

## Architecture

```
Schedule (5min)
  └─► Market Data (Bybit Klines + OrderBook)
        └─► Compute TA (RSI, MACD, EMA, Patterns)
              └─► CryptoPanic News
                    └─► Agent 1: News AI      (gpt-4o-mini)
                          └─► Agent 2: Sentiment AI  (llama-3.1)
                                └─► Agent 3: TA/Trader AI  (claude-opus-4-6)
                                      └─► Fetch Balance
                                            └─► Kelly Position Sizing
                                                  └─► Agent 4: Risk AI  (gpt-4o-mini)
                                                        └─► IF Approved
                                                              ├─ YES ─► Place Order ─► Set TP/SL
                                                              └─ NO  ─► Log Rejection
                                                                    └─► Postgres ─► Telegram
```

## Setup

### 1. Prerequisites

```bash
# Install n8n globally
npm install -g n8n

# Install Postgres (Ubuntu/Debian)
sudo apt install postgresql postgresql-contrib

# Create database
sudo -u postgres psql -c "CREATE DATABASE crypto_trading;"
sudo -u postgres psql -d crypto_trading -f db/init.sql
```

### 2. Environment variables

Copy `.env.example` to `.env` and fill in your values:

```bash
cp .env.example .env
```

Add to your `.env` (or export before starting n8n):

```bash
export N8N_ENCRYPTION_KEY=64a33f15b3b8462a74597d553d751b4811bb6472e5b961cdb2df61848048dd45
export OPENROUTER_API_KEY=sk-or-v1-...
export BYBIT_API_KEY=...
export BYBIT_API_SECRET=...
export BYBIT_BASE_URL=https://api-demo.bybit.com
export CRYPTOPANIC_API_KEY=...
export POSTGRES_PASSWORD=...
export TG_TOKEN=...
export TG_CHAT_IDS=...

# Risk
export MAX_RISK_PER_TRADE_PCT=0.005
export MAX_DAILY_LOSS_PCT=0.02
export MAX_OPEN_POSITIONS=3
export MAX_LEVERAGE=3.0
export MIN_CONFIDENCE=0.60
export LIVE_TRADING_ENABLED=false

# Models
export NEWS_MODEL=openai/gpt-4o-mini
export SENTIMENT_MODEL=meta-llama/llama-3.1-8b-instruct
export TA_MODEL=anthropic/claude-opus-4-6
export RISK_MODEL=openai/gpt-4o-mini
```

### 3. Start n8n

```bash
# Load env and start
source .env && n8n start
# Or with dotenv:
n8n start --tunnel  # optional: for webhook access
```

Open: http://localhost:5678

### 4. Import workflow

1. Open n8n → **Settings** → **Import Workflow** (or use the menu icon)
2. Upload `workflows/crypto_trading_bot.json`
3. The workflow will be imported in **inactive** state

### 5. Configure credentials in n8n UI

Go to **Credentials** and create:

| Credential Name      | Type         | Fields                           |
|----------------------|--------------|----------------------------------|
| `Postgres account`   | Postgres     | host, port, db, user, password   |
| `Telegram account`   | Telegram API | token (from BotFather)           |

After creating credentials:
- Open the **DB: Log Signal** node → select your Postgres credential
- Open the **Telegram: Send Alert** node → select your Telegram credential
- All other nodes use env vars directly (no n8n credentials needed)

### 6. Test the workflow

**Before enabling**, run manually:

1. Open the workflow canvas
2. Click **Execute Workflow** (play button, top right)
3. Watch the execution step by step
4. Check Postgres: `SELECT * FROM signals ORDER BY created_at DESC LIMIT 5;`
5. Check Telegram for your notification

### 7. Activate

Once tested, toggle **Active** in the top-right of the workflow canvas.
The bot will run every 5 minutes automatically.

## Safety

- `LIVE_TRADING_ENABLED=false` → all orders are **simulated** and logged, no real API calls to place orders
- Bybit base URL `https://api-demo.bybit.com` → demo account only
- Hard guards: confidence threshold, Kelly half-fraction, max leverage cap
- Risk AI double-checks every signal before approval

## Models Used

| Agent      | Model                               | Role                          |
|------------|-------------------------------------|-------------------------------|
| News AI    | `openai/gpt-4o-mini`                | Summarize + impact score      |
| Sentiment  | `meta-llama/llama-3.1-8b-instruct`  | Sentiment -100 to +100        |
| TA/Trader  | `anthropic/claude-opus-4-6`         | Signal + entry/TP/SL          |
| Risk Mgmt  | `openai/gpt-4o-mini`                | Approve/reject + position adj |

## DB Tables

| Table         | Purpose                                  |
|---------------|------------------------------------------|
| `signals`     | Every TA signal with all indicators      |
| `trades`      | Executed/simulated orders                |
| `agent_logs`  | Per-agent invocation logs                |
| `daily_stats` | Aggregated P&L stats by day              |
| `kline_cache` | Optional OHLCV cache for backtesting     |

## File Structure

```
.
├── .env.example              # Template for environment variables
├── README.md                 # This file
├── db/
│   └── init.sql              # Postgres schema (run once)
└── workflows/
    └── crypto_trading_bot.json  # n8n workflow (import via UI)
```
