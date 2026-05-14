WebBanking {
  version = 0.5,
  country = "de",
  description = "Include your IBKR stock portfolio in MoneyMoney.",
  services = {"IBKR"}
}

local FLEX_BASE_URL = "https://ndcdyn.interactivebrokers.com/AccountManagement/FlexWebService"
local FLEX_VERSION = "3"
local FLEX_USER_AGENT = "Java/1.8"

local MAX_ATTEMPTS = 8
local INITIAL_WAIT_SECONDS = 5
local MAX_WAIT_SECONDS = 60

local retryableErrors = {
  ["1001"] = true,
  ["1004"] = true,
  ["1005"] = true,
  ["1006"] = true,
  ["1007"] = true,
  ["1008"] = true,
  ["1009"] = true,
  ["1018"] = true,
  ["1019"] = true,
  ["1021"] = true
}

local parseargs = function(s)
  local arg = {}
  string.gsub(s, "([%-%w]+)=([\"'])(.-)%2", function(w, _, value)
      value = string.gsub(value, "&quot;", "\"");
      value = string.gsub(value, "&apos;", "'");
      value = string.gsub(value, "&gt;", ">");
      value = string.gsub(value, "&lt;", "<");
      value = string.gsub(value, "&amp;", "&");
      arg[w] = value
  end)
  return arg
end

local parseBlock = function(content, k)
  if content == nil then
      return nil
  end
  return string.match(content, "<" .. k .. "[^>]*>(.-)</" .. k .. ">")
end

local function requiredBlock(content, k, context)
  local block = parseBlock(content, k)
  if block ~= nil then
      return block
  end
  if content ~= nil and string.find(content, "<" .. k .. "[^>]*/>") ~= nil then
      return ""
  end
  return nil, "IBKR Flex " .. context .. " failed: Missing required section <" .. k .. ">."
end

local function newConnection()
  local c = Connection()
  c.useragent = FLEX_USER_AGENT
  return c
end

local connection = newConnection()
local token
local query
local code
local statementContent

local function encodeParam(value)
  return MM.urlencode(tostring(value), "UTF-8")
end

local function sendRequestUrl()
  return FLEX_BASE_URL .. "/SendRequest?t=" .. encodeParam(token) ..
      "&q=" .. encodeParam(query) .. "&v=" .. FLEX_VERSION
end

local function getStatementUrl()
  return FLEX_BASE_URL .. "/GetStatement?t=" .. encodeParam(token) ..
      "&q=" .. encodeParam(code) .. "&v=" .. FLEX_VERSION
end

local function getFlexError(content)
  local status = parseBlock(content, "Status")
  local errorCode = parseBlock(content, "ErrorCode")
  local errorMessage = parseBlock(content, "ErrorMessage")
  return status, errorCode, errorMessage
end

local function formatFlexError(context, errorCode, errorMessage)
  if errorCode ~= nil then
      return "IBKR Flex " .. context .. " failed with error " ..
          errorCode .. ": " .. (errorMessage or "No error message returned.")
  end
  return "IBKR Flex " .. context .. " failed: No valid response returned."
end

local function isFlexStatement(content)
  if content == nil or content == "" then
      return false
  end
  return string.find(content, "<FlexQueryResponse", 1, true) ~= nil or
      string.find(content, "<FlexStatement ", 1, true) ~= nil or
      string.find(content, "<FlexStatements", 1, true) ~= nil
end

local function getWithRetry(urlBuilder, context)
  local waitSeconds = INITIAL_WAIT_SECONDS

  for attempt = 1, MAX_ATTEMPTS do
      local content, charset, mimeType = connection:get(urlBuilder())
      local status, errorCode, errorMessage = getFlexError(content)

      if errorCode == nil then
          return content, charset, mimeType
      end

      if not retryableErrors[errorCode] then
          return nil, nil, nil, formatFlexError(context, errorCode, errorMessage)
      end

      print("IBKR Flex " .. context .. " temporary error " ..
          tostring(errorCode) .. " on attempt " .. tostring(attempt) ..
          " of " .. tostring(MAX_ATTEMPTS))

      if attempt < MAX_ATTEMPTS then
          if errorCode == "1018" then
              MM.sleep(60)
          else
              MM.sleep(waitSeconds)
              waitSeconds = math.min(waitSeconds * 2, MAX_WAIT_SECONDS)
          end
      end
  end

  return nil, nil, nil, "IBKR Flex " .. context ..
      " failed after " .. tostring(MAX_ATTEMPTS) .. " attempts."
end

function SupportsBank(protocol, bankCode)
  return protocol == ProtocolWebBanking and bankCode == "IBKR"
end

function InitializeSession(protocol, bankCode, username, customer, password)
  token = password
  query = username
  code = nil
  statementContent = nil
  connection = newConnection()

  local content, charset, mimeType, err = getWithRetry(sendRequestUrl, "SendRequest")
  if err ~= nil then
      return err
  end

  local status = parseBlock(content, "Status")
  if status == "Success" then
      code = parseBlock(content, "ReferenceCode")
      if code == nil or code == "" then
          return "IBKR Flex SendRequest succeeded but no ReferenceCode was returned."
      end
      print("IBKR Flex SendRequest succeeded.")
  else
      local _, errorCode, errorMessage = getFlexError(content)
      return formatFlexError("SendRequest", errorCode, errorMessage)
  end
end

function ListAccounts(knownAccounts)
  local account = {
      name = "IBKR",
      accountNumber = "1",
      currency = "EUR",
      portfolio = true,
      type = AccountTypePortfolio
  }
  local account2 = {
      name = "IBKR Cash",
      accountNumber = "2",
      currency = "EUR",
      type = AccountTypeOther
  }

  return {account, account2}
end

function stringToTimestamp(str)
  if str == nil then
      return nil
  end
  local datePattern = '(%d%d%d%d)(%d%d)(%d%d)'
  local year, month, day  = str:match(datePattern)
  if year and month and day then
      local timestamp = os.time{day=day,month=month,year=year}
      return timestamp
  end
end

function RefreshAccount(account, since)
  print("RefreshAccount " .. JSON():set(account):json())

  if statementContent == nil then
      local content
      local charset, mimeType, err
      content, charset, mimeType, err = getWithRetry(getStatementUrl, "GetStatement")
      if err ~= nil then
          return err
      end

      local status, errorCode, errorMessage = getFlexError(content)
      if status == "Fail" then
          return formatFlexError("GetStatement", errorCode, errorMessage)
      end
      if not isFlexStatement(content) then
          return "IBKR Flex GetStatement failed: Response did not contain a Flex statement."
      end

      statementContent = content
  end
  local accountNumber = tostring(account.accountNumber)
  if accountNumber == "1" then
      local positions, err = requiredBlock(statementContent, 'OpenPositions', "GetStatement")
      if err ~= nil then
          return err
      end
      local securities = {}
      for p in positions:gmatch("<OpenPosition(.-)/>") do
          print(p)
          local pos = parseargs(p)
          local position = tonumber(pos.position) or 0
          local multiplier = tonumber(pos.multiplier) or 1
          local positionValue = tonumber(pos.positionValue) or 0
          local markPrice = tonumber(pos.markPrice) or 0
          local costBasisPrice = tonumber(pos.costBasisPrice) or 0
          local fxRateToBase = tonumber(pos.fxRateToBase) or 1
          local fifoPnlUnrealized = tonumber(pos.fifoPnlUnrealized) or 0
          local costBasisMoney = tonumber(pos.costBasisMoney) or 0
          local profitPercent = 0
          if costBasisMoney ~= 0 then
              profitPercent = 100 / costBasisMoney * positionValue - 100
          end
          securities[#securities + 1] = {
              name = pos.description,
              isin = pos.isin,
              securityNumber = pos.isin,
              market = pos.listingExchange,
              quantity = position * multiplier,
              originalAmount = positionValue,
              originalCurrencyAmount = positionValue,
              currencyOfOriginalAmount = pos.currency,
              price = markPrice,
              currencyOfPrice = pos.currency,
              purchasePrice = costBasisPrice,
              currencyOfPurchasePrice = pos.currency,
              exchangeRateOfPrice = fxRateToBase,
              exchangeRateOfPurchasePrice = fxRateToBase,
              exchangeRate = 1 / fxRateToBase,
              amount = positionValue * fxRateToBase,
              userdata = {{key="_profit",value=string.format("%.02f", fifoPnlUnrealized*fxRateToBase) .. " EUR / " .. string.format("%.05f", profitPercent) .. " %"}}
              --userdata = {{key="_profit",value=string.format("%.02f", pos.fifoPnlUnrealized) .. " USD / " .. string.format("%.05f", 100/pos.costBasisMoney*pos.positionValue-100) .. " %"}}

          }

      end
      -- Return balance and array of transactions.
      return {
          securities = securities
      }
  elseif accountNumber == "2" then
      local summary, err = requiredBlock(statementContent, 'EquitySummaryInBase', "GetStatement")
      if err ~= nil then
          return err
      end
      local cash = 0
      for p in summary:gmatch("<EquitySummaryByReportDateInBase(.-)/>") do
          print(p)
          local pos = parseargs(p)
          cash = tonumber(pos.cash) or 0
      end
      --  array of transactions.
      local summary, err = requiredBlock(statementContent, 'StmtFunds', "GetStatement")
      if err ~= nil then
          return err
      end
      local transactions = {}
      for p in summary:gmatch("<StatementOfFundsLine(.-)/>") do
          --print(p)
          local sm = parseargs(p)
          print(#transactions,sm.transactionID,sm.reportDate,sm.settleDate,sm.description,sm.activityDescription,sm.amount,sm.activityCode)
          if sm.activityCode  ~=  'ADJ' then
              transactions[#transactions + 1] = {
                  name=sm.description,
                  amount=tonumber(sm.amount) or 0,
                  currency="EUR",
                  bookingDate=stringToTimestamp(sm.reportDate),
                  valueDate=stringToTimestamp(sm.settleDate),
                  transactionCode=sm.transactionID,
                  purpose=sm.activityDescription,
                  bookingText=sm.activityCode
              }
          end
      end
      -- Return balance and array of transactions.
      --print(JSON():set(transactions):json())
      return {
          balance = cash,
          transactions = transactions
      }
  end
end

function EndSession()
  -- Logout.
end
