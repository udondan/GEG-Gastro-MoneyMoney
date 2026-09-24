-- Offline tests for GEG-Gastro.lua. Run with: test/run.sh test/test_geg_gastro.lua

package.path = "test/?.lua;" .. package.path
local mm = require("mm_shim")

local failures = 0
local checks = 0

local function check(cond, message)
  checks = checks + 1
  if not cond then
    failures = failures + 1
    print("FAIL: " .. message)
  end
end

local function eq(actual, expected, message)
  check(actual == expected, message .. " (expected " .. tostring(expected) .. ", got " .. tostring(actual) .. ")")
end

local function ymd(ts)
  return os.date("%Y-%m-%d", ts)
end

local storage = {}
local env = mm.loadPlugin("GEG-Gastro.lua", storage)

-- WebBanking header --------------------------------------------------------
check(env.webBankingArgs ~= nil, "WebBanking{} was called")
eq(type(env.webBankingArgs.version), "number", "version is a number")
eq(env.webBankingArgs.services[1], "GEG Gastro", "service name")
eq(env.SupportsBank("ProtocolWebBanking", "GEG Gastro"), true, "SupportsBank matches service")
eq(env.SupportsBank("ProtocolWebBanking", "Other"), false, "SupportsBank rejects other services")

-- String / amount helpers ---------------------------------------------------
eq(env.trim("  a b \n"), "a b", "trim")
eq(env.normalizeMultiline("  Testsuppe \r\n***\n\n  Nudeln mit\nSoße  "), "Testsuppe\n***\nNudeln mit\nSoße", "normalizeMultiline")
eq(env.singleLine("  Testsuppe \r\n***\n\n  Nudeln mit\nSoße  "), "Testsuppe | Nudeln mit Soße", "singleLine")
eq(env.singleLine("Einzeiler"), "Einzeiler", "singleLine keeps single line")
eq(env.parseAmount("98,00"), 98.0, "parseAmount German")
eq(env.parseAmount("1.234,56"), 1234.56, "parseAmount thousands separator")
eq(env.parseAmount("3.50"), 3.5, "parseAmount dot decimal")
eq(env.parseAmount("abc"), nil, "parseAmount garbage")
eq(env.parseAmount("-3,20 EUR"), -3.2, "parseAmount negative with currency")
eq(env.parseAmount("24,00 EUR"), 24.0, "parseAmount positive with currency")

eq(env.childKey("Muster, Anna"), "anna muster", "childKey swaps last and first name")
eq(env.childKey("Anna Muster"), "anna muster", "childKey keeps first-last order")
eq(env.childKey("Muster-Beispiel,  Anna Lena "), "anna lena muster-beispiel", "childKey double name and second first name")
eq(env.childKey("Anna  Lena Muster-Beispiel"), "anna lena muster-beispiel", "childKey collapses whitespace")

-- Date helpers ---------------------------------------------------------------
local d = env.parseOrderDate("Mo 03.03.31\n                        ")
eq(ymd(d), "2031-03-03", "parseOrderDate")
eq(env.parseOrderDate("kein Datum"), nil, "parseOrderDate without date")
eq(env.formatDate(d), "03.03.2031", "formatDate")
eq(ymd(env.parseLedgerDate("23.09.2031 13:40:25")), "2031-09-23", "parseLedgerDate")
eq(env.parseLedgerDate("kein Datum"), nil, "parseLedgerDate without date")

local lt = env.parseLedgerText("Veggie, 23.09.2031, Anna Muster")
eq(lt.menu, "Veggie", "parseLedgerText menu")
eq(ymd(lt.date), "2031-09-23", "parseLedgerText meal date")
eq(lt.child, "Anna Muster", "parseLedgerText child")
lt = env.parseLedgerText("Großer Testsalat, mit Brötchen, 06.03.2031, Anna Lena Muster")
eq(lt.menu, "Großer Testsalat, mit Brötchen", "parseLedgerText keeps commas in the menu")
eq(lt.child, "Anna Lena Muster", "parseLedgerText child after menu with commas")
eq(env.parseLedgerText("Überweisungseingang vom 22.09.2031"), nil, "parseLedgerText top-up is no order")

local now = os.time{ year = 2031, month = 3, day = 5, hour = 9, min = 30 }
local from, to = env.computeDateRange(nil, nil, now)
eq(ymd(from), "2021-03-05", "first sync: 10 years back")
eq(ymd(to), "2031-05-14", "range end: +10 weeks")

local lastSync = os.time{ year = 2031, month = 2, day = 20, hour = 8 }
from, to = env.computeDateRange(lastSync, nil, now)
eq(ymd(from), "2031-02-13", "resync: last sync minus 7 days")

local since = os.time{ year = 2030, month = 12, day = 1, hour = 12 }
from = env.computeDateRange(lastSync, since, now)
eq(ymd(from), "2030-12-01", "resync: earlier 'since' from MoneyMoney wins")

local laterSince = os.time{ year = 2031, month = 3, day = 1, hour = 12 }
from = env.computeDateRange(lastSync, laterSince, now)
eq(ymd(from), "2031-02-13", "resync: later 'since' is ignored")

-- Login page -----------------------------------------------------------------
local loginHtml = env.HTML(mm.readFile("test/fixtures/login.html"))
eq(env.hasBalance(loginHtml), false, "login page has no balance")
eq(env.isLoginPage(loginHtml), true, "login page detected")
local form = env.findLoginForm(loginHtml)
eq(form:length(), 1, "login form found")
eq(form:xpath(".//input[@name='next']"):attr("value"), "/kunden/bestelluebersicht/", "login form carries next")
eq(form:xpath(".//input[@name='csrfmiddlewaretoken']"):attr("value"), "TESTTOKEN", "login form carries CSRF token")
form:xpath(".//input[@name='username']"):attr("value", "user@example.com")
eq(form:xpath(".//input[@name='username']"):attr("value"), "user@example.com", "username can be filled")

-- Order overview -------------------------------------------------------------
local html = env.HTML(mm.readFile("test/fixtures/bestelluebersicht.html"))
eq(env.hasBalance(html), true, "overview has balance")
eq(env.isLoginPage(html), false, "overview is not the login page")
eq(env.parseBalance(html), 123.45, "parseBalance")

local orders = env.parseOrders(html)
eq(#orders, 5, "number of orders")
eq(orders[1].child, "Muster, Anna", "child of first order")
eq(ymd(orders[1].date), "2031-03-03", "date of first order")
eq(orders[1].menu, "Zertifiziert", "menu of first order")
eq(orders[1].description, "Testsuppe\n***\nBeispielnudeln mit\nMustersoße", "description of first order")
eq(orders[1].quantity, 1, "quantity of first order")
eq(orders[2].quantity, 1, "quantity of second order")
eq(orders[2].menu, "Veggie", "menu of second order")
eq(orders[3].child, "Muster, Ben", "child of third order")
eq(orders[5].description, "Mustereintopf\nmit Karotten, Erbsen & Nudeln\nTestbrötchen", "entity and multiline description")
eq(ymd(orders[5].date), "2031-03-07", "date of last order")

-- Balance pages --------------------------------------------------------------
local ledgerPages = {
  env.HTML(mm.readFile("test/fixtures/guthaben_1.html")),
  env.HTML(mm.readFile("test/fixtures/guthaben_2.html")),
}
eq(env.hasBalance(ledgerPages[1]), true, "balance page has balance")
eq(env.hasNextLedgerPage(ledgerPages[1]), true, "page 1 has a next page")
eq(env.hasNextLedgerPage(ledgerPages[2]), false, "page 2 is the last page")

local page1 = env.parseLedger(ledgerPages[1])
eq(#page1, 4, "entries on page 1 (IBAN table is skipped)")
eq(ymd(page1[1].date), "2031-03-04", "date of first entry")
eq(page1[1].amount, -3.2, "amount of first entry")
eq(page1[1].order.child, "Ben Muster", "order of first entry")
eq(page1[2].amount, 25.0, "top-up amount")
eq(page1[2].text, "Überweisungseingang vom 03.03.2031", "top-up text")
eq(page1[2].order, nil, "top-up has no order")
eq(page1[3].order.menu, "Großer Testsalat, mit Brötchen", "menu with commas")

local fetched
local function fetchPage(page)
  fetched = fetched + 1
  return ledgerPages[page]
end
local function keysOf(list)
  local keys = {}
  for _, o in ipairs(list) do
    keys[env.orderKey(o.child, o.date)] = true
  end
  return keys
end

local march2 = os.time{ year = 2031, month = 3, day = 2, hour = 8 }
fetched = 0
local ledger = env.collectLedger(fetchPage, march2, keysOf(orders))
eq(fetched, 2, "open orders continue to page 2 although page 1 reaches 'from'")
eq(#ledger, 8, "entries of both pages")

fetched = 0
ledger = env.collectLedger(fetchPage, march2, {})
eq(fetched, 1, "stops after the page that reaches 'from'")
eq(#ledger, 4, "entries of page 1")

fetched = 0
ledger = env.collectLedger(fetchPage, os.time{ year = 2021, month = 3, day = 5, hour = 9 }, {})
eq(fetched, 2, "first sync loads up to the last page")

local march4 = os.time{ year = 2031, month = 3, day = 4, hour = 8 }
fetched = 0
env.collectLedger(fetchPage, march4, { [env.orderKey("Muster, Ben", env.parseOrderDate("07.03.31"))] = true })
eq(fetched, 1, "all open orders priced on page 1")

-- Transactions ---------------------------------------------------------------
ledger = env.collectLedger(function(page) return ledgerPages[page] end, march2, keysOf(orders))
from, to = env.computeDateRange(lastSync, nil, now)
local transactions, pendingBalance = env.buildTransactions(orders, ledger, now, from, to)
eq(#transactions, 7, "5 orders and 2 top-ups")
eq(ymd(transactions[1].bookingDate), "2031-03-07", "sorted newest first")
eq(ymd(transactions[7].bookingDate), "2031-02-20", "oldest last")

local byKey = {}
for _, t in ipairs(transactions) do
  byKey[t.purpose .. " " .. ymd(t.bookingDate)] = t
end
eq(byKey["Muster, Anna 2031-03-03"].booked, true, "past order is booked")
eq(byKey["Muster, Anna 2031-03-03"].amount, -3.0, "amount from the debit (old price)")
eq(byKey["Muster, Anna 2031-03-03"].bookingText, "Zertifiziert", "menu in bookingText")
eq(byKey["Muster, Anna 2031-03-03"].name, "Testsuppe | Beispielnudeln mit Mustersoße", "meal in name, single line")
eq(byKey["Muster, Anna 2031-03-03"].purpose, "Muster, Anna", "child in purpose")
eq(byKey["Muster, Ben 2031-03-03"].amount, -3.2, "amount from the debit (new price)")
eq(byKey["Muster, Ben 2031-03-05"].booked, true, "order of today is booked")
eq(byKey["Muster, Anna 2031-03-06"].booked, false, "future order is pending")
eq(byKey["Muster, Anna 2031-03-06"].amount, -3.2, "future order matched despite commas in the menu")
eq(byKey["Muster, Anna 2031-03-06"].name, "Musterauflauf mit Gemüse", "name from the overview")
eq(byKey["Muster, Ben 2031-03-07"].booked, false, "future order is pending")

local topup = byKey[" 2031-03-03"]
eq(topup.amount, 25.0, "top-up amount")
eq(topup.name, "Überweisungseingang vom 03.03.2031", "top-up name")
eq(topup.bookingText, "Guthaben", "top-up bookingText")
eq(topup.booked, true, "top-up is booked")
eq(byKey[" 2031-02-20"].amount, 30.0, "older top-up after 'from'")
eq(pendingBalance, -6.4, "pending balance is the sum of pending amounts")
for _, t in ipairs(transactions) do
  eq(t.currency, "EUR", "currency set")
  check(type(t.booked) == "boolean", "booked is set explicitly")
end

-- Debit without an order inside the range becomes its own transaction.
local january = os.time{ year = 2031, month = 1, day = 1, hour = 8 }
transactions = env.buildTransactions(orders, ledger, now, january, to)
eq(#transactions, 8, "debit without order in range is added")
local orphan = transactions[8]
eq(ymd(orphan.bookingDate), "2031-01-10", "orphan debit on its booking day")
eq(orphan.amount, -3.0, "orphan debit amount")
eq(orphan.name, "Zertifiziert", "orphan debit name is the menu")
eq(orphan.purpose, "Muster, Anna", "orphan debit child as in the overview")
eq(orphan.booked, true, "orphan debit is booked")

-- An order without a debit falls back to the most recent price.
local extra = {
  { child = "Muster, Ben", date = env.parseOrderDate("12.03.31"), menu = "Veggie", description = "Testauflauf", quantity = 2 },
}
transactions, pendingBalance = env.buildTransactions(extra, ledger, now, from, to)
eq(transactions[1].amount, -6.4, "missing debit uses the last price times quantity")
eq(transactions[1].name, "2x Testauflauf", "quantity prefix in name")
eq(pendingBalance, -6.4, "fallback order is pending")
transactions = env.buildTransactions(extra, {}, now, from, to)
eq(#transactions, 0, "order without any known price is skipped")

-- ListAccounts ------------------------------------------------------------
local accounts = env.ListAccounts({})
eq(#accounts, 1, "one account")
eq(accounts[1].attributes, nil, "no account attributes")
eq(accounts[1].type, "AccountTypeOther", "account type")
eq(accounts[1].currency, "EUR", "account currency")

-- Summary ----------------------------------------------------------------------
print(string.format("%d checks, %d failures", checks, failures))
if failures > 0 then
  os.exit(1)
end
