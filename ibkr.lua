WebBanking {
  version = 0.3,
  country = "de",
  description = "Include your IBKR stock portfolio in MoneyMoney.",
  services = {"IBKR"}
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
  return string.match(content, "^.+<" .. k .. ">(.+)</" .. k .. ">.+$")
end

local connection = Connection()
local token
local query
local code

function SupportsBank(protocol, bankCode)
  return protocol == ProtocolWebBanking and bankCode == "IBKR"
end

function InitializeSession(protocol, bankCode, username, customer, password)
  token = password
  query = username
  connection = Connection()
  local content, charset, mimeType = connection:get(
      "https://ndcdyn.interactivebrokers.com/Universal/servlet/FlexStatementService.SendRequest?t=" .. token .. "&q=" ..
          query .. "&v=3")
  local status = string.match(content, "^.+<Status>(.+)</Status>.+$")
  if status == "Success" then
      code = string.match(content, "^.+<ReferenceCode>(.+)</ReferenceCode>.+$")
      print("8:" .. code)
  else
      return content
  end
end

function ListAccounts(knownAccounts)
  local account = {
      name = "IBKR",
      accountNumber = 1,
      currency = "EUR",
      portfolio = true,
      type = "AccountTypePortfolio"
  }
  local account2 = {
      name = "IBKR Cash",
      accountNumber = 2,
      currency = "EUR",
      type = "AccountTypeOther"
  }

  return {account, account2}
end

local statementContent

function stringToTimestamp(str)
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
      local ec
      repeat
          statementContent, charset, mimeType = connection:get(
              "https://ndcdyn.interactivebrokers.com/Universal/servlet/FlexStatementService.GetStatement?t=" .. token ..
                  "&q=" .. code .. "&v=3")
          local ec=parseBlock(statementContent, 'ErrorCode')
          if ec=="1019" then
              MM.sleep(1)
          end

      until ec ~="1019"

  end
  if account.accountNumber == "1" then
      local positions = parseBlock(statementContent, 'OpenPositions')
      local securities = {}
      for p in positions:gmatch("<OpenPosition(.-)/>") do
          print(p)
          local pos = parseargs(p)
          securities[#securities + 1] = {
              name = pos.description,
              isin = pos.isin,
              securityNumber = pos.isin,
              market = pos.listingExchange,
              quantity = pos.position * pos.multiplier,
              originalCurrencyAmount = pos.positionValue,
              currencyOfOriginalAmount = pos.currency,
              price = pos.markPrice,
              currencyOfPrice = pos.currency,
              purchasePrice = pos.costBasisPrice,
              currencyOfPurchasePrice = pos.currency,
              exchangeRate = 1 / pos.fxRateToBase,
              userdata = {{key="_profit",value=string.format("%.02f", pos.fifoPnlUnrealized*pos.fxRateToBase) .. " EUR / " .. string.format("%.05f", 100/pos.costBasisMoney*pos.positionValue-100) .. " %"}}
              --userdata = {{key="_profit",value=string.format("%.02f", pos.fifoPnlUnrealized) .. " USD / " .. string.format("%.05f", 100/pos.costBasisMoney*pos.positionValue-100) .. " %"}}

          }

      end
      -- Return balance and array of transactions.
      return {
          securities = securities
      }
  elseif account.accountNumber == "2" then
      local summary = parseBlock(statementContent, 'EquitySummaryInBase')
      local cash = 0
      for p in summary:gmatch("<EquitySummaryByReportDateInBase(.-)/>") do
          print(p)
          local pos = parseargs(p)
          cash = pos.cash
      end
      --  array of transactions.
      local summary = parseBlock(statementContent, 'StmtFunds')
      local transactions = {}
      for p in summary:gmatch("<StatementOfFundsLine(.-)/>") do
          --print(p)
          local sm = parseargs(p)
          print(#transactions,sm.transactionID,sm.reportDate,sm.settleDate,sm.description,sm.activityDescription,sm.amount,sm.activityCode)
          if sm.activityCode  ~=  'ADJ' then
              transactions[#transactions + 1] = {
                  name=sm.description,
                  amount=sm.amount,
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

-- SIGNATURE: MCsCFHF+25SfP/5FOEXYuH4H1XCoVDF7AhNF3D9StNKYUYIheUUOaFSh8dDr
