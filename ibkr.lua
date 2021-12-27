WebBanking {
    version = 0.1,
    country = "de",
    description = "Include your IBKR stock portfolio in MoneyMoney.",
    services = {"IBKR"}
}

local parseargs = function(s)
    local arg = {}
    string.gsub(s, "([%-%w]+)=([\"'])(.-)%2", function(w, _, a)
        arg[w] = a
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
    local content = connection:get(
        "https://gdcdyn.interactivebrokers.com/Universal/servlet/FlexStatementService.SendRequest?t=" .. token .. "&q=" ..
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

function RefreshAccount(account, since)
    print("RefreshAccount " .. JSON():set(account):json())

    if statementContent == nil then
        statementContent = connection:get(
            "https://gdcdyn.interactivebrokers.com/Universal/servlet/FlexStatementService.GetStatement?t=" .. token ..
                "&q=" .. code .. "&v=3")
    end
    if account.accountNumber == "1" then
        local positions = parseBlock(statementContent, 'OpenPositions')
        local securities = {}
        for p in positions:gmatch("<OpenPosition(.-)/>") do
            print(p)
            local pos = parseargs(p)
            securities[#securities + 1] = {
                name = pos.symbol,
                securityNumber = pos.isin,
                market = pos.listingExchange,
                quantity = pos.position * pos.multiplier,
                price = pos.markPrice,
                currencyOfPrice = pos.currency,
                purchasePrice = pos.costBasisPrice,
                currencyOfPurchasePrice = pos.currency,
                exchangeRate = pos.fxRateToBase
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
        -- Return balance and array of transactions.
        return {
            balance = cash,
            transactions = {}
        }
    end
end

function EndSession()
    -- Logout.
end

-- SIGNATURE: MC0CFBZyTf3ayQ3lCZahDjxYsb8DbWX8AhUAkLzNi07pLujOVhGhtD6HhjjsJeM=
