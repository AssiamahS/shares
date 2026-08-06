# Shares

iOS portfolio tracker that fixes what the popular ones get wrong:

- **Merged per-ticker view** — hold AAPL in three portfolios, see one combined position (plus the per-portfolio breakdown)
- **Lot-level sells** — you pick which lots to sell from, no forced FIFO, so cost basis matches your brokerage
- **Realized vs unrealized P&L**, per lot and overall
- **Cash line** per portfolio, so the total is real net worth
- **Honest timestamps** — every price shows when it was actually fetched, with a stale warning

Live quotes via [Alpaca](https://alpaca.markets) market data (free real-time IEX feed).
Paste your API key pair in Settings; they're stored in the Keychain only.

## Build

XcodeGen project — `project.yml` is the source of truth:

```
xcodegen generate
open Shares.xcodeproj
```

CI builds an unsigned compile check on every push and uploads to TestFlight
when ASC secrets are present.
