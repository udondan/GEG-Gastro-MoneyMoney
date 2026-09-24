-- GEG-Gastro.lua
--
-- MoneyMoney WebBanking extension for the GEG Gastro meal ordering portal
-- (https://www.bestellung-geggastro.de). The portal has no API, so this
-- extension logs in with the customer's credentials, loads the order
-- overview page with the meal orders of all children on the account and the
-- balance page ("Guthaben") with every debit and top-up of the balance.
--
-- Account model: one MoneyMoney account per portal login. Every meal order
-- becomes one transaction; the meal is the transaction's "name", the menu
-- type is the booking text and the child's name is the purpose. The amount
-- is the debit of that order on the balance page, matched by child and meal
-- date. Orders on future days are delivered as pending transactions
-- (booked = false). Balance page entries that are not orders (top-ups)
-- become transactions of their own.
--
-- MIT License, see LICENSE.

local BASE_URL = "https://www.bestellung-geggastro.de"
local LOGIN_PATH = "/login/"
local OVERVIEW_PATH = "/kunden/bestelluebersicht/"
local LEDGER_PATH = "/kunden/guthaben/"
local LOGOUT_PATH = "/logout/"
local SERVICE_NAME = "GEG Gastro"

-- Globals on purpose: the offline test harness reads them.
INITIAL_LOOKBACK_YEARS = 10
FUTURE_WEEKS = 10
RESYNC_OVERLAP_DAYS = 7
MAX_LEDGER_PAGES = 1000

local SECONDS_PER_DAY = 24 * 60 * 60

WebBanking{
  version = 1.10,
  url = BASE_URL,
  services = { SERVICE_NAME },
  description = "Guthaben und Essensbestellungen von GEG Gastro (bestellung-geggastro.de)",
}

local connection = nil
local sessionUsername = nil

---------------------------------------------------------------------------
-- String and number helpers
---------------------------------------------------------------------------

function trim(s)
  s = tostring(s or "")
  s = s:gsub("^%s+", "")
  s = s:gsub("%s+$", "")
  return s
end

-- Trims every line, drops empty lines and joins the rest with "\n".
function normalizeMultiline(s)
  s = tostring(s or ""):gsub("\r", "")
  local lines = {}
  for rawLine in (s .. "\n"):gmatch("([^\n]*)\n") do
    local line = trim(rawLine)
    if line ~= "" then
      table.insert(lines, line)
    end
  end
  return table.concat(lines, "\n")
end

-- Collapses a multi-line meal description into one line for the transaction
-- name. The portal separates courses with a "***" line; it becomes " | ".
function singleLine(s)
  local parts = {}
  for line in (normalizeMultiline(s) .. "\n"):gmatch("([^\n]*)\n") do
    if line == "***" then
      table.insert(parts, "|")
    else
      table.insert(parts, line)
    end
  end
  return table.concat(parts, " ")
end

-- Parses a German formatted amount such as "1.234,56" or "3,00" into a number.
-- Returns nil for unparsable input.
function parseAmount(s)
  s = trim(s):gsub("€", ""):gsub("EUR", "")
  s = trim(s)
  if s:find(",", 1, true) then
    s = s:gsub("%.", ""):gsub(",", ".")
  end
  return tonumber(s)
end

---------------------------------------------------------------------------
-- Date helpers
---------------------------------------------------------------------------

-- Midnight (local time) of the day that contains the timestamp.
function dayStart(ts)
  local t = os.date("*t", ts)
  return os.time{ year = t.year, month = t.month, day = t.day, hour = 0 }
end

-- Same calendar day and time of day, shifted by the given number of years.
function addYears(ts, years)
  local t = os.date("*t", ts)
  return os.time{ year = t.year + years, month = t.month, day = t.day, hour = t.hour, min = t.min, sec = t.sec }
end

-- "dd.mm.yyyy" as expected by the portal's date_from / date_to parameters.
function formatDate(ts)
  return os.date("%d.%m.%Y", ts)
end

-- Parses the date cell of an order row, e.g. "Mo 03.03.31". Returns a
-- timestamp at noon of that day (avoids shifting the date across time
-- zones) or nil when the text contains no date.
function parseOrderDate(s)
  local day, month, year = tostring(s or ""):match("(%d%d)%.(%d%d)%.(%d%d)")
  if not day then
    return nil
  end
  return os.time{ year = 2000 + tonumber(year), month = tonumber(month), day = tonumber(day), hour = 12 }
end

-- Parses a date with a four-digit year as used on the balance page, e.g.
-- "23.09.2026 13:40:25". Returns a timestamp at noon of that day or nil.
function parseLedgerDate(s)
  local day, month, year = tostring(s or ""):match("(%d%d)%.(%d%d)%.(%d%d%d%d)")
  if not day then
    return nil
  end
  return os.time{ year = tonumber(year), month = tonumber(month), day = tonumber(day), hour = 12 }
end

-- Decides which date range to request from the portal.
--   lastSync: timestamp of the last successful refresh (nil on first run)
--   since:    timestamp MoneyMoney asks for (may be nil)
--   now:      current time
-- Returns from, to (timestamps).
function computeDateRange(lastSync, since, now)
  local from
  if lastSync then
    from = lastSync - RESYNC_OVERLAP_DAYS * SECONDS_PER_DAY
  else
    from = addYears(now, -INITIAL_LOOKBACK_YEARS)
  end
  if since and since > 0 and since < from then
    from = since
  end
  local to = now + FUTURE_WEEKS * 7 * SECONDS_PER_DAY
  return from, to
end

---------------------------------------------------------------------------
-- HTML parsing
---------------------------------------------------------------------------

function hasBalance(html)
  return html:xpath("//span[@id='header_account_balance_value']"):length() > 0
end

function isLoginPage(html)
  return html:xpath("//form[@action='/login/']"):length() > 0
end

-- The login page contains two login forms; the one in the page body carries
-- the hidden "next" field that sends us straight to the order overview.
function findLoginForm(html)
  local form = html:xpath("//form[@action='/login/'][.//input[@name='next']]")
  if form:length() == 0 then
    form = html:xpath("//form[@action='/login/']")
  end
  return form
end

function parseBalance(html)
  local node = html:xpath("//span[@id='header_account_balance_value']")
  if node:length() == 0 then
    error("Guthaben nicht gefunden. Hat sich die Website geändert?")
  end
  local balance = parseAmount(node:text())
  if balance == nil then
    error("Guthaben konnte nicht gelesen werden: " .. trim(node:text()))
  end
  return balance
end

-- Returns a list of orders:
--   { child = "Nachname, Vorname", date = <timestamp>, menu = "Zertifiziert",
--     description = "...", quantity = 1 }
function parseOrders(html)
  local orders = {}
  html:xpath("//div[contains(@class,'panel-mealplan')]"):each(function(_, panel)
    local child = trim(panel:xpath(".//span[@class='childname']"):text())
    panel:xpath(".//table[contains(@class,'food-order')]/tbody/tr"):each(function(_, row)
      local cells = row:xpath("./td")
      if cells:length() >= 4 then
        local date = parseOrderDate(cells:get(1):text())
        if date then
          table.insert(orders, {
            child = child,
            date = date,
            menu = trim(cells:get(2):text()),
            description = normalizeMultiline(cells:get(3):text()),
            quantity = tonumber(trim(cells:get(4):text())) or 1,
          })
        end
      end
    end)
  end)
  return orders
end

-- Normalizes a child's name so that both spellings of the portal match: the
-- order overview writes "Nachname, Vorname", the balance page
-- "Vorname Nachname".
function childKey(name)
  local s = trim(name)
  local last, first = s:match("^(.-),%s*(.+)$")
  if last then
    s = first .. " " .. last
  end
  s = s:gsub("%s+", " ")
  return s:lower()
end

-- Matching key of an order: child and meal date. A child can order only one
-- meal per day.
function orderKey(child, date)
  return childKey(child) .. "|" .. os.date("%Y-%m-%d", date)
end

-- Splits the text of a balance page entry that belongs to an order, e.g.
-- "Veggie, 23.09.2031, Anna Muster". The menu may contain commas, so the
-- text is split from the right. Returns { menu, date, child } or nil for
-- other entries such as top-ups.
function parseLedgerText(s)
  local text = trim(tostring(s or ""):gsub("%s+", " "))
  local menu, day, month, year, child = text:match("^(.*),%s*(%d%d)%.(%d%d)%.(%d%d%d%d),%s*(.-)$")
  if not menu or trim(menu) == "" or trim(child) == "" then
    return nil
  end
  return {
    menu = trim(menu),
    date = os.time{ year = tonumber(year), month = tonumber(month), day = tonumber(day), hour = 12 },
    child = trim(child),
  }
end

-- Returns the entries of one balance page, newest first:
--   { date = <timestamp>, amount = -3.2, text = "...", order = parseLedgerText(text) }
function parseLedger(html)
  local entries = {}
  html:xpath("//table[.//th[normalize-space()='Betrag']]//tr[count(td)=3]"):each(function(_, row)
    local cells = row:xpath("./td")
    local date = parseLedgerDate(cells:get(1):xpath(".//span"):attr("title")) or parseLedgerDate(cells:get(1):text())
    local amount = parseAmount(cells:get(2):text())
    local text = trim(cells:get(3):text():gsub("%s+", " "))
    if date and amount then
      table.insert(entries, {
        date = date,
        amount = amount,
        text = text,
        order = parseLedgerText(text),
      })
    end
  end)
  return entries
end

function hasNextLedgerPage(html)
  return html:xpath("//ul[contains(@class,'pagination')]//a[@aria-label='Next']"):length() > 0
end

-- Loads balance pages, newest first, via fetchPage(page) -> HTML. Stops at
-- the last page, or once a page reaches back before "from" and every key in
-- openKeys (orderKey of the orders to price) has been seen.
function collectLedger(fetchPage, from, openKeys)
  local entries = {}
  local open = {}
  local openCount = 0
  for key in pairs(openKeys or {}) do
    open[key] = true
    openCount = openCount + 1
  end
  local fromDay = dayStart(from)
  local page = 1
  while page <= MAX_LEDGER_PAGES do
    local html = fetchPage(page)
    local rows = parseLedger(html)
    local reachedFrom = false
    for _, entry in ipairs(rows) do
      table.insert(entries, entry)
      if entry.order then
        local key = orderKey(entry.order.child, entry.order.date)
        if open[key] then
          open[key] = nil
          openCount = openCount - 1
        end
      end
      if dayStart(entry.date) < fromDay then
        reachedFrom = true
      end
    end
    if #rows == 0 or not hasNextLedgerPage(html) or (reachedFrom and openCount == 0) then
      break
    end
    page = page + 1
  end
  return entries
end

-- Converts orders and balance page entries into MoneyMoney transactions.
--   orders: from parseOrders, covering the days from..to
--   ledger: from collectLedger, newest first
-- Every order takes its amount from the matching debit. Orders up to and
-- including today are booked, later ones are pending. Balance entries that
-- belong to no order (top-ups) become booked transactions of their own when
-- they were booked on or after "from". Returns the transaction list (newest
-- first) and the sum of the pending amounts.
function buildTransactions(orders, ledger, today, from, to)
  local transactions = {}
  local pendingBalance = 0
  local todayStart = dayStart(today)
  local fromDay = dayStart(from)
  local toDay = dayStart(to)

  -- The ledger is newest first, so the newest debit of a key wins and
  -- lastPrice is the most recent price of any order.
  local debits = {}
  local lastPrice = nil
  for i, entry in ipairs(ledger) do
    if entry.order and entry.amount < 0 then
      local key = orderKey(entry.order.child, entry.order.date)
      if debits[key] == nil then
        debits[key] = i
      end
      if lastPrice == nil then
        lastPrice = entry.amount
      end
    end
  end

  local used = {}
  local childNames = {}
  for _, order in ipairs(orders) do
    childNames[childKey(order.child)] = order.child
    local index = debits[orderKey(order.child, order.date)]
    local amount = nil
    if index then
      used[index] = true
      amount = ledger[index].amount
    elseif lastPrice then
      amount = lastPrice * order.quantity
      print("Keine Buchung für die Bestellung von " .. order.child .. " am " .. formatDate(order.date)
        .. " gefunden, verwende den letzten Preis " .. string.format("%.2f", -lastPrice))
    else
      print("Keine Buchung für die Bestellung von " .. order.child .. " am " .. formatDate(order.date)
        .. " gefunden, Bestellung wird übersprungen")
    end
    if amount then
      local booked = dayStart(order.date) <= todayStart
      local name = singleLine(order.description)
      if order.quantity > 1 then
        name = order.quantity .. "x " .. name
      end
      if not booked then
        pendingBalance = pendingBalance + amount
      end
      table.insert(transactions, {
        name = name,
        amount = amount,
        currency = "EUR",
        bookingDate = order.date,
        purpose = order.child,
        bookingText = order.menu,
        booked = booked,
      })
    end
  end

  for i, entry in ipairs(ledger) do
    if not used[i] and dayStart(entry.date) >= fromDay then
      local transaction = nil
      if entry.order == nil then
        transaction = { name = entry.text, purpose = "" }
      else
        -- A debit without an order in the overview. Only possible when the
        -- meal date lies inside the requested range; outside it the order
        -- was or will be delivered by another refresh.
        local mealDay = dayStart(entry.order.date)
        if mealDay >= fromDay and mealDay <= toDay then
          transaction = {
            name = entry.order.menu,
            purpose = childNames[childKey(entry.order.child)] or entry.order.child,
          }
        end
      end
      if transaction then
        transaction.amount = entry.amount
        transaction.currency = "EUR"
        transaction.bookingDate = entry.date
        transaction.bookingText = "Guthaben"
        transaction.booked = true
        table.insert(transactions, transaction)
      end
    end
  end

  table.sort(transactions, function(a, b)
    if a.bookingDate ~= b.bookingDate then
      return a.bookingDate > b.bookingDate
    end
    return a.purpose < b.purpose
  end)
  return transactions, pendingBalance
end

---------------------------------------------------------------------------
-- MoneyMoney entry points
---------------------------------------------------------------------------

function SupportsBank(protocol, bankCode)
  return protocol == ProtocolWebBanking and bankCode == SERVICE_NAME
end

function InitializeSession(protocol, bankCode, username, customer, password, credential)
  sessionUsername = username
  connection = Connection()
  connection.language = "de-de"

  local loginUrl = BASE_URL .. LOGIN_PATH .. "?next=" .. OVERVIEW_PATH
  MM.printStatus("Lade Login-Seite")
  local html = HTML(connection:get(loginUrl))

  local form = findLoginForm(html)
  if form:length() == 0 then
    return "Login-Formular nicht gefunden. Hat sich die Website geändert?"
  end
  form:xpath(".//input[@name='username']"):attr("value", username)
  form:xpath(".//input[@name='password']"):attr("value", password)

  MM.printStatus("Melde an")
  local method, url, postContent, postContentType = form:submit()
  -- Django checks the Referer header on HTTPS POSTs, so send it explicitly.
  local content = connection:request(method, url, postContent, postContentType, { Referer = loginUrl })
  html = HTML(content)

  if hasBalance(html) then
    return nil
  end
  if isLoginPage(html) then
    return LoginFailed
  end
  return "Anmeldung fehlgeschlagen: unerwartete Antwort der Website."
end

function ListAccounts(knownAccounts)
  return {
    {
      name = "GEG Gastro Essensbestellung",
      owner = sessionUsername,
      accountNumber = "GEG-GASTRO-" .. tostring(sessionUsername),
      type = AccountTypeOther,
      currency = "EUR",
    },
  }
end

function RefreshAccount(account, since)
  local now = os.time()
  local from, to = computeDateRange(LocalStorage.lastSuccessfulSync, since, now)

  local url = BASE_URL .. OVERVIEW_PATH .. "?date_from=" .. formatDate(from) .. "&date_to=" .. formatDate(to)
  MM.printStatus("Rufe Bestellungen ab (" .. formatDate(from) .. " bis " .. formatDate(to) .. ")")
  local html = HTML(connection:get(url))

  if not hasBalance(html) then
    return "Bestellübersicht konnte nicht geladen werden (Sitzung abgelaufen?)."
  end

  local portalBalance = parseBalance(html)
  local orders = parseOrders(html)

  local openKeys = {}
  for _, order in ipairs(orders) do
    openKeys[orderKey(order.child, order.date)] = true
  end
  local ledger = collectLedger(function(page)
    MM.printStatus("Rufe Guthaben-Umsätze ab (Seite " .. page .. ")")
    local ledgerHtml = HTML(connection:get(BASE_URL .. LEDGER_PATH .. "?page=" .. page))
    if not hasBalance(ledgerHtml) then
      error("Guthaben-Seite konnte nicht geladen werden (Sitzung abgelaufen?).")
    end
    return ledgerHtml
  end, from, openKeys)

  local transactions, pendingBalance = buildTransactions(orders, ledger, now, from, to)

  LocalStorage.lastSuccessfulSync = now
  MM.printStatus(#orders .. " Bestellungen und " .. #ledger .. " Guthaben-Umsätze gefunden, Guthaben "
    .. MM.localizeAmount(portalBalance, "EUR"))

  -- The portal deducts an order from its balance when it is placed, but
  -- orders for future days are pending here. Add them back so that the
  -- booked transactions sum up to the booked balance; booked plus pending
  -- is the portal balance again.
  return {
    balance = portalBalance - pendingBalance,
    pendingBalance = pendingBalance,
    transactions = transactions,
  }
end

function EndSession()
  if connection then
    pcall(function()
      connection:get(BASE_URL .. LOGOUT_PATH)
    end)
  end
  connection = nil
  sessionUsername = nil
end
