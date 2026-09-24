# GEG Gastro MoneyMoney extension

MoneyMoney WebBanking extension (single Lua file, `GEG-Gastro.lua`) that scrapes
https://www.bestellung-geggastro.de. API reference: https://moneymoney.app/api/webbanking/

## Layout

- `GEG-Gastro.lua` — the extension. Helper and parser functions are globals on
  purpose so the offline tests can call them.
- `test/mm_shim.lua` — emulates the MoneyMoney host (`HTML()` via xmlua,
  `MM`, `LocalStorage`, `WebBanking`, constants). `Connection()` and
  `:submit()`/`:click()` are not available offline.
- `test/test_geg_gastro.lua` — assert-style tests, run with `test/run.sh`.
- `test/fixtures/` — synthetic HTML pages (login page, order overview,
  two balance pages).
- `link_ext.sh` — hard-links the extension into MoneyMoney's Extensions folder.
- `docs/screenshot.png` — anonymized screenshot for the README.

## Tests

```sh
brew install luajit luarocks
luarocks --lua-version=5.1 install xmlua
test/run.sh
```

Syntax check for the host runtime: `luac -p GEG-Gastro.lua` (Lua 5.4 or newer).

## Rules

- **Fixtures must be fully synthetic.** Never commit real names, meals, dates,
  child IDs or balances from the portal; they could identify the account.
  Saved real pages (`test.html`, `test.htm`, `test/pages/`) are gitignored and stay local.
  Before committing, `git grep` for real values.
- Write Lua that runs under both LuaJIT (tests) and Lua 5.4 (MoneyMoney): no
  `goto`, no `//`, no bit operators, no `utf8` module, do not reassign for-loop
  variables.
- Keep the values of delivered transactions (name, purpose, amount,
  bookingDate) stable between runs; MoneyMoney deduplicates by comparing them.
  Changing the mapping means users have to re-create the account.
- `booked` must be set explicitly on every transaction; pending transactions
  go into `transactions` with `booked = false` (there is no
  `pendingTransactions` field).
- `LocalStorage` is per bank access and empty on first run; guard for `nil`.
- Amounts come from the balance page `/kunden/guthaben/?page=N` (newest
  first, 20 rows per page). An order row reads "Menü, dd.mm.yyyy, Vorname
  Nachname"; it is matched to the overview ("Nachname, Vorname") by child and
  meal date via `orderKey`. A child can order only one meal per day. The
  portal has no cancellation rows: a cancelled order's debit just disappears.
- The portal deducts orders when they are placed; `balance` is the portal
  balance minus `pendingBalance` so booked transactions sum up to it.

## Manual test in MoneyMoney

1. `./link_ext.sh`, then disable the signature check under
   Einstellungen → Erweiterungen.
2. Add an account via Konto hinzufügen → Andere → "GEG Gastro".
3. Watch Fenster → Protokollfenster for `MM.printStatus` output and errors.
