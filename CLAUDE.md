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
- `test/fixtures/` — synthetic HTML pages (login page, order overview).
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
  Saved real pages (`test.html`, `test/pages/`) are gitignored and stay local.
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
- The account attribute `pricePerOrder` comes back as `account.attributes`
  in `RefreshAccount`. MoneyMoney does not create it from the `attributes`
  table returned by `ListAccounts`; the user adds it by hand under
  Konto → Einstellungen → Notizen. Attribute tables must use string keys and
  string values only.

## Manual test in MoneyMoney

1. `./link_ext.sh`, then disable the signature check under
   Einstellungen → Erweiterungen.
2. Add an account via Konto hinzufügen → Andere → "GEG Gastro".
3. Watch Fenster → Protokollfenster for `MM.printStatus` output and errors.
