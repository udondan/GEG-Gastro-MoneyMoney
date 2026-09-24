-- GEG-Gastro.lua
--
-- MoneyMoney WebBanking extension for the GEG Gastro meal ordering portal
-- (https://www.bestellung-geggastro.de). The portal has no API, so this
-- extension logs in with the customer's credentials, loads the order
-- overview page and scrapes the balance ("Guthaben") and the meal orders
-- of all children on the account.
--
-- Account model: one MoneyMoney account per portal login. Every meal order
-- becomes one transaction; the meal is the transaction's "name", the menu
-- type is the booking text and the child's name is the purpose.
-- Orders on future days are delivered as pending transactions
-- (booked = false). The portal does not show prices, so the price per order
-- comes from the account attribute "pricePerOrder" (default 3.00 EUR).
--
-- MIT License, see LICENSE.

local BASE_URL = "https://www.bestellung-geggastro.de"
local LOGIN_PATH = "/login/"
local OVERVIEW_PATH = "/kunden/bestelluebersicht/"
local LOGOUT_PATH = "/logout/"
local SERVICE_NAME = "GEG Gastro"

-- Globals on purpose: the offline test harness reads them.
DEFAULT_PRICE = 3.00
ATTR_PRICE = "pricePerOrder"
INITIAL_LOOKBACK_YEARS = 10
FUTURE_WEEKS = 10
RESYNC_OVERLAP_DAYS = 7

local SECONDS_PER_DAY = 24 * 60 * 60

WebBanking{
  version = 1.00,
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

-- Price per order from the account attribute. Falls back to DEFAULT_PRICE
-- when the attribute is missing, empty or not a positive number.
function parsePrice(value)
  if value == nil then
    return DEFAULT_PRICE
  end
  local price = parseAmount(value)
  if price == nil or price <= 0 then
    return DEFAULT_PRICE
  end
  return price
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

-- Converts orders into MoneyMoney transactions. Orders up to and including
-- today are booked, later ones are pending. Returns the transaction list
-- (newest first) and the sum of the pending amounts.
function buildTransactions(orders, price, today)
  local transactions = {}
  local pendingBalance = 0
  local todayStart = dayStart(today)
  for _, order in ipairs(orders) do
    local booked = dayStart(order.date) <= todayStart
    local amount = -price * order.quantity
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
      -- Shown as editable attributes in the account settings of MoneyMoney
      -- and handed back as account.attributes in RefreshAccount.
      attributes = { [ATTR_PRICE] = string.format("%.2f", DEFAULT_PRICE) },
    },
  }
end

function RefreshAccount(account, since)
  local price = parsePrice(account.attributes and account.attributes[ATTR_PRICE])
  local now = os.time()
  local from, to = computeDateRange(LocalStorage.lastSuccessfulSync, since, now)

  local url = BASE_URL .. OVERVIEW_PATH .. "?date_from=" .. formatDate(from) .. "&date_to=" .. formatDate(to)
  MM.printStatus("Rufe Bestellungen ab (" .. formatDate(from) .. " bis " .. formatDate(to) .. ")")
  local html = HTML(connection:get(url))

  if not hasBalance(html) then
    return "Bestellübersicht konnte nicht geladen werden (Sitzung abgelaufen?)."
  end

  local balance = parseBalance(html)
  local orders = parseOrders(html)
  local transactions, pendingBalance = buildTransactions(orders, price, now)

  LocalStorage.lastSuccessfulSync = now
  MM.printStatus(#transactions .. " Bestellungen gefunden, Guthaben " .. MM.localizeAmount(balance, "EUR"))

  return {
    balance = balance,
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
