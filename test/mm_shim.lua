-- mm_shim.lua
-- Emulates the MoneyMoney WebBanking host environment well enough to run the
-- parsing and date functions of GEG-Gastro.lua offline under LuaJIT.
--
-- The real host parses HTML with libxml2 (HTML parser + XPath); we wrap xmlua
-- (a libxml2 binding) to mirror the node-set API the extension relies on:
--   :xpath(q) :text() :attr(n[,v]) :each(fn) :length() :get(n) :children()
-- Form/navigation methods (:submit/:click/:select) are stubbed because the
-- offline tests exercise parsing, not live scraping.
--
-- Based on the shim of https://github.com/rosch100/Amazon-MoneyMoney (MIT).

local xmlua = require("xmlua")

local M = {}

local NodeSet = {}
NodeSet.__index = NodeSet

local function single(node, doc)
  local o = setmetatable({ _nodes = { node }, _doc = doc }, NodeSet)
  o[1] = o
  return o
end

local function wrap(nodes, doc)
  local o = setmetatable({ _nodes = nodes, _doc = doc }, NodeSet)
  for i, n in ipairs(nodes) do
    o[i] = single(n, doc)
  end
  return o
end

function NodeSet:xpath(query)
  local ctx = self._nodes[1]
  if ctx == nil then
    return wrap({}, self._doc)
  end
  local ok, res = pcall(function() return ctx:search(query) end)
  if not ok or res == nil then
    return wrap({}, self._doc)
  end
  local nodes = {}
  for _, n in ipairs(res) do nodes[#nodes + 1] = n end
  return wrap(nodes, self._doc)
end

function NodeSet:text()
  local n = self._nodes[1]
  if n == nil then return "" end
  local ok, t = pcall(function() return n:text() end)
  if not ok or t == nil then return "" end
  return t
end

function NodeSet:attr(name, value)
  local n = self._nodes[1]
  if value ~= nil then
    for _, node in ipairs(self._nodes) do
      pcall(function() node:set_attribute(name, value) end)
    end
    return self
  end
  if n == nil then return "" end
  local ok, v = pcall(function() return n:get_attribute(name) end)
  if not ok or v == nil then return "" end
  return v
end

function NodeSet:each(fn)
  for i = 1, #self._nodes do
    local cont = fn(i, self[i])
    if cont == false then break end
  end
  return self
end

function NodeSet:length()
  return #self._nodes
end

function NodeSet:get(n)
  return self[n] or wrap({}, self._doc)
end

function NodeSet:children()
  return self:xpath("./*")
end

function NodeSet:html()
  local n = self._nodes[1]
  if n == nil then return "" end
  local ok, h = pcall(function() return n:to_html() end)
  if not ok or h == nil then return "" end
  return h
end

local function navStub(name)
  return function()
    error("mm_shim: NodeSet:" .. name .. "() called - not supported offline")
  end
end
NodeSet.select = navStub("select")
NodeSet.submit = navStub("submit")
NodeSet.click = navStub("click")

function M.HTML(content, charset)
  local options = nil
  if charset ~= nil then
    options = { encoding = charset }
  end
  local doc = xmlua.HTML.parse(content or "", options)
  local root = doc:root()
  if root == nil then
    return wrap({}, doc)
  end
  return single(root, doc)
end

function M.readFile(path)
  local f = assert(io.open(path, "rb"))
  local content = f:read("*a")
  f:close()
  return content
end

-- Loads the extension in a sandbox with the host globals stubbed and returns
-- the sandbox environment so tests can call the extension's global functions.
function M.loadPlugin(path, localStorage)
  local env = {}

  local MM = {
    printStatus = function() end,
    printDebug = function() end,
    sleep = function() end,
    urlencode = function(s) return tostring(s) end,
    localizeAmount = function(amount, currency) return string.format("%.2f %s", amount, currency or "") end,
  }

  local overrides = {
    HTML = M.HTML,
    MM = MM,
    LocalStorage = localStorage or {},
    Connection = function() error("Connection() not available offline") end,
    WebBanking = function(t) env.webBankingArgs = t end,
    ProtocolWebBanking = "ProtocolWebBanking",
    AccountTypeOther = "AccountTypeOther",
    LoginFailed = "LoginFailed",
    io = nil,
  }
  setmetatable(env, { __index = function(_, k)
    local v = overrides[k]
    if v ~= nil then return v end
    return _G[k]
  end })

  local chunk, err = loadfile(path)
  if not chunk then error("loadfile failed: " .. tostring(err)) end
  setfenv(chunk, env)
  chunk()
  return env
end

M.NodeSet = NodeSet
M.wrap = wrap
return M
