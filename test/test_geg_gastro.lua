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
eq(env.parseAmount("98,00"), 98.0, "parseAmount German")
eq(env.parseAmount("1.234,56"), 1234.56, "parseAmount thousands separator")
eq(env.parseAmount("3.50"), 3.5, "parseAmount dot decimal")
eq(env.parseAmount("abc"), nil, "parseAmount garbage")

eq(env.parsePrice("3.00"), 3.0, "parsePrice dot")
eq(env.parsePrice("3,50"), 3.5, "parsePrice comma")
eq(env.parsePrice(nil), 3.0, "parsePrice nil falls back to default")
eq(env.parsePrice("abc"), 3.0, "parsePrice garbage falls back to default")
eq(env.parsePrice("0"), 3.0, "parsePrice zero falls back to default")
eq(env.parsePrice(" 2,80 € "), 2.8, "parsePrice with currency sign")

-- Date helpers ---------------------------------------------------------------
local d = env.parseOrderDate("Mo 03.03.31\n                        ")
eq(ymd(d), "2031-03-03", "parseOrderDate")
eq(env.parseOrderDate("kein Datum"), nil, "parseOrderDate without date")
eq(env.formatDate(d), "03.03.2031", "formatDate")

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
eq(orders[2].quantity, 2, "quantity of second order")
eq(orders[2].menu, "Veggie", "menu of second order")
eq(orders[3].child, "Muster, Ben", "child of third order")
eq(orders[5].description, "Mustereintopf\nmit Karotten, Erbsen & Nudeln\nTestbrötchen", "entity and multiline description")
eq(ymd(orders[5].date), "2031-03-07", "date of last order")

-- Transactions ---------------------------------------------------------------
local transactions, pendingBalance = env.buildTransactions(orders, 3.0, now)
eq(#transactions, 5, "number of transactions")
eq(ymd(transactions[1].bookingDate), "2031-03-07", "sorted newest first")
eq(ymd(transactions[5].bookingDate), "2031-03-03", "oldest last")

local byKey = {}
for _, t in ipairs(transactions) do
  byKey[t.name .. " " .. ymd(t.bookingDate)] = t
end
eq(byKey["Muster, Anna 2031-03-03"].booked, true, "past order is booked")
eq(byKey["Muster, Anna 2031-03-03"].amount, -3.0, "amount is minus price")
eq(byKey["Muster, Anna 2031-03-03"].bookingText, "Zertifiziert", "menu in bookingText")
eq(byKey["Muster, Anna 2031-03-03"].purpose, "Testsuppe\n***\nBeispielnudeln mit\nMustersoße", "description in purpose")
eq(byKey["Muster, Ben 2031-03-05"].booked, true, "order of today is booked")
eq(byKey["Muster, Anna 2031-03-06"].booked, false, "future order is pending")
eq(byKey["Muster, Anna 2031-03-06"].amount, -6.0, "quantity 2 doubles the amount")
eq(byKey["Muster, Anna 2031-03-06"].purpose, "2x Musterauflauf mit Gemüse", "quantity prefix in purpose")
eq(byKey["Muster, Ben 2031-03-07"].booked, false, "future order is pending")
eq(pendingBalance, -9.0, "pending balance is the sum of pending amounts")
for _, t in ipairs(transactions) do
  eq(t.currency, "EUR", "currency set")
  check(type(t.booked) == "boolean", "booked is set explicitly")
end

local transactions2 = env.buildTransactions(orders, 2.5, now)
eq(transactions2[5].amount, -2.5, "price is configurable")

-- ListAccounts ------------------------------------------------------------
local accounts = env.ListAccounts({})
eq(#accounts, 1, "one account")
eq(accounts[1].attributes[env.ATTR_PRICE], "3.00", "default price attribute")
eq(accounts[1].type, "AccountTypeOther", "account type")
eq(accounts[1].currency, "EUR", "account currency")

-- Summary ----------------------------------------------------------------------
print(string.format("%d checks, %d failures", checks, failures))
if failures > 0 then
  os.exit(1)
end
