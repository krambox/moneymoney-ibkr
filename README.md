# MoneyMoney-IBKR Extension

Inofficial IBKR Extension for MoneyMoney and EUR Accounts.

## Release Notes

### 0.3

- Update IB Endpoint

### 0.2

Attention: You must extend your Flex query Statement Of Funds

- Support Statements
- Quote XML Chars
- Ignore 'ADJ' activities in Statements
- Fix (some) foreign currencies issues

### 0.1

- Initial Version

## Setup

1. Download the extension via  GitHub  https://github.com/krambox/moneymoney-ibkr/releases
2. Once downloaded, move `ibkr.lua` to your MoneyMoney Extensions folder.
3. Setup a IBKR Flex Query and activate Flex-Web-Service
    1. Flexquery Section
      <img src="Flexquery Sections.png" align="middle"/>
    2. Flexquery NAC
      <img src="Flexquery NAC.png" align="middle"/>
    3. Flexquery Open Positions
      <img src="Flexquery Open Positions.png" align="middle"/>
    4. Flexquery Statement Of Funds
      <img src="Flexquery StatementOfFunds.png" align="middle"/>
    4. Flexquery Configuration
      <img src="Flexquery Configuration.png" align="middle"/>
    
4.  Use the Flex Query ID as User and the Flex-Web-Service token as password
5.  Add a new account with the type `IBKR`
6.  The extension provides 2 accounts. One AccountTypePortfolio for the open positions and one  AccountTypeOther for the cash balance. 
