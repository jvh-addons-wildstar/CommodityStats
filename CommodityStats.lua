-- Got questions/comments? contact me at jimmy@boe2.be or send me a message through Curse
require "Window"
 
local PixiePlot, GeminiLogging, glog, GeminiLocale, L
local CommodityStats = {}

local secondsInDay = 86400
local secondsInHour = 3600
local clrSellTop1 = {a=1,r=1,g=0,b=0}
local clrSellTop10 = {a=1,r=1,g=0.5,b=0.5}
local clrSellTop50 = {a=1,r=1,g=0.8,b=0.8}
local clrBuyTop1 = {a=1,r=0,g=1,b=0}
local clrBuyTop10 = {a=1,r=0.5,g=1,b=0.5}
local clrBuyTop50 = {a=1,r=0.8,g=1,b=0.8}
local CREDDid = "999999"
local transactionListItems = {}

-- OrderTypes
CommodityStats.OrderType = {
    BOTH = 0,
    BUY = 1,
    SELL = 2
}

-- Transaction results
CommodityStats.Result = {
    BUYSUCCESS = 0,
    SELLSUCCESS = 1,
    BUYEXPIRED = 2,
    SELLEXPIRED = 3
}

-- DateTime formats
CommodityStats.DateFormat = {
    DDMM = "%d/%m %H:%M",
    MMDD = "%m/%d %H:%M"
}

-- categories
CommodityStats.Category = {
    SELLORDER = "HeaderSellOrderBtn",
    BUYORDER = "HeaderBuyOrderBtn",
    SELLNOW = "HeaderSellNowBtn",
    BUYNOW = "HeaderBuyNowBtn"
}

-- Price Undercut/Increase strategies
CommodityStats.Strategy = {
    MATCH = 0,
    FIXED = 1,
    PERCENTAGE = 2
}

-- Price groups
CommodityStats.Pricegroup = {
    TOP1 = 1,
    TOP10 = 2,
    TOP50 = 3
}

 
function CommodityStats:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    self.categoryQueue = {}
    self.statistics = {}
    self.transactions = {}
    self.settings = {}
    self.currentItemID = 0
    self.queueSize = 0
    self.lastAverageRun = 0
    self.isScanning = false

    -- default values
    self.settings = {
        daysToKeep = 60,
        daysUntilAverage = 7,
        dateFormatString = CommodityStats.DateFormat.DDMM,
        orderType = CommodityStats.OrderType.BOTH,
        baseSellPrice = CommodityStats.Pricegroup.TOP1,
        sellStrategy = CommodityStats.Strategy.MATCH,
        sellUndercutPercentage = 5,
        sellUndercutFixed = 100,
        baseBuyPrice = CommodityStats.Pricegroup.TOP1,
        buyStrategy = CommodityStats.Strategy.MATCH,
        buyIncreasePercentage = 5,
        buyIncreaseFixed = 100,
        lastSelectedTab = nil
    }

    return o
end

function CommodityStats:Init()
    Apollo.RegisterAddon(self, true, "CommodityStats", {"MarketplaceCommodity", "MarketplaceCREDD", "Gemini:Logging-1.2", "Gemini:Locale-1.0"})
    Apollo.RegisterEventHandler("MailBoxActivate", "OnMailboxOpen", self)
    Apollo.RegisterEventHandler("ToggleMailWindow", "OnMailboxOpen", self)
    Apollo.RegisterEventHandler("CommodityInfoResults", "OnCommodityInfoResults", self)
    Apollo.RegisterEventHandler("CREDDExchangeInfoResults", "OnCREDDExchangeInfoResults", self)
    Apollo.RegisterSlashCommand("commoditystats", "OnConfigure", self)
    Apollo.RegisterSlashCommand("cs", "OnConfigure", self)
end

function CommodityStats:OnLoad()
    PixiePlot = Apollo.GetPackage("Drafto:Lib:PixiePlot-1.4").tPackage
    GeminiLogging = Apollo.GetPackage("Gemini:Logging-1.2").tPackage
    glog = GeminiLogging:GetLogger({
        level = GeminiLogging.WARN,
        pattern = "%d %n %c %l - %m",
        appender = "GeminiConsole"
    })

    GeminiLocale = Apollo.GetPackage("Gemini:Locale-1.0").tPackage
    L = GeminiLocale:GetLocale("CommodityStats", false)

    self.Xml = XmlDoc.CreateFromFile("CommodityStats.xml")
    self.wndMain = Apollo.LoadForm(self.Xml, "MainContainer", nil, self)
    GeminiLocale:TranslateWindow(L, self.wndMain)

    self.MarketplaceCommodity = Apollo.GetAddon("MarketplaceCommodity")
    self.MarketplaceCREDD = Apollo.GetAddon("MarketplaceCREDD")
    self:InitializeHooks()
end

function CommodityStats:InitializeHooks()
    local fnOldCREDDinitialize = self.MarketplaceCREDD.Initialize
    -- Add statistics button to CREDD Exchange
    self.MarketplaceCREDD.Initialize = function(tMarketPlaceCREDD)
        fnOldCREDDinitialize(tMarketPlaceCREDD)
        if self.CREDDStatButton ~= nil then self.CREDDStatButton:Destroy() end
        self.CREDDStatButton = Apollo.LoadForm(self.Xml, "CREDDStatButton", tMarketPlaceCREDD.wndMain:FindChild("ActLater"), self)
        self.CREDDStatButton:SetTooltip(L["Show price/transaction history"])
    end

    local fnOldInitialize = self.MarketplaceCommodity.Initialize
    -- Add scanbutton to Commodity Exchange
    self.MarketplaceCommodity.Initialize = function(tMarketPlaceCommodity)
        fnOldInitialize(tMarketPlaceCommodity)
        if self.ScanButton ~= nil then self.ScanButton:Destroy() end
        self.ScanButton = Apollo.LoadForm(self.Xml, "ScanButton", tMarketPlaceCommodity.wndMain, self)
        self.ScanButton:SetText(L["Scan all data"])
        -- restore previous window position (which it really should do out of the box imo)
        if self.commPosition ~= nil then
            tMarketPlaceCommodity.wndMain:Move(self.commPosition.left, self.commPosition.top, tMarketPlaceCommodity.wndMain:GetWidth(), tMarketPlaceCommodity.wndMain:GetHeight())
        end
        -- Get CREDD info separately since it's not part of the CX, but we want the history on it.
        CREDDExchangeLib.RequestExchangeInfo()
    end
    -- Add statistics button to every listed commodity item
    local fnOldHeaderBtnToggle = self.MarketplaceCommodity.OnHeaderBtnToggle
    self.MarketplaceCommodity.OnHeaderBtnToggle = function(tMarketPlaceCommodity)
        fnOldHeaderBtnToggle(tMarketPlaceCommodity)
        local children = tMarketPlaceCommodity.wndMain:FindChild("MainScrollContainer"):GetChildren()
        for i, child in ipairs(children) do
            if child:GetText() == "" then
                local stat = Apollo.LoadForm(self.Xml, "StatButton", child, self)
                stat:SetTooltip(L["Show price/transaction history"])
            end
        end
    end
    -- Fill in the best available price for buy/sell orders
    local fnOldOnCommodityInfoResults = self.MarketplaceCommodity.OnCommodityInfoResults
    self.MarketplaceCommodity.OnCommodityInfoResults = function(tMarketPlaceCommodity, nItemId, tStats, tOrders)
        fnOldOnCommodityInfoResults(tMarketPlaceCommodity, nItemId, tStats, tOrders)
        local scrollContainer = tMarketPlaceCommodity.wndMain:FindChild("MainScrollContainer")
        if not scrollContainer then return end
        local wndMatch = scrollContainer:FindChild(nItemId)
        if not wndMatch or not wndMatch:IsValid() then
            return
        end

        local price = 0
        local hasPreviousQuantity
        local selectedCategory = self:GetSelectedCategory(tMarketPlaceCommodity);
        if self[selectedCategory] ~= nil then -- do we have previously saved prices/quantities?
            scrollContainer:SetVScrollPos(self[selectedCategory].lastScrollPos)
            if self[selectedCategory].lastItemID == nItemId then
                price = self[selectedCategory].lastPricePerUnit:GetAmount()
                wndMatch:FindChild("ListInputNumber"):SetText(self[selectedCategory].lastQuantity)
                hasPreviousQuantity = true
            end
        end
        if price == 0 then
            price = self:GetPrice(nItemId, tStats, selectedCategory)
        end

        local listSubmitBtn = wndMatch:FindChild("ListSubmitBtn")
        wndMatch:FindChild("ListInputPrice"):SetAmount(price)
        listSubmitBtn:Enable(price > 0)

        if self.settings.autoQuantity and not hasPreviousQuantity and (selectedCategory == CommodityStats.Category.SELLORDER or selectedCategory == CommodityStats.Category.SELLNOW) then
            local maxOrder = MarketplaceLib.kMaxCommodityOrder
            local sellQuantity = wndMatch:FindChild("ListCount"):GetData() or 0
            if sellQuantity > maxOrder then sellQuantity = maxOrder end
            wndMatch:FindChild("ListInputNumber"):SetText(sellQuantity)
            tMarketPlaceCommodity:OnListInputNumberHelper(wndMatch, sellQuantity)
        end

        -- Add an extra invisible window to the Submit button so that we can intercept the click event on an otherwise protected ActionConfirmButton
        Apollo.LoadForm(self.Xml, "ListSubmitButtonOverlay", listSubmitBtn, self)
    end
    -- Use a non-blocking infobox to display the transaction result info (no more waiting 4 seconds between every buy/sell attempt)
    self.MarketplaceCommodity.OnPostCustomMessage = function(tMarketPlaceCommodity, strMessage, bResultOK, nDuration)
        local tParameters= { iWindowType = GameLib.CodeEnumStoryPanel.Center, tLines = { strMessage }, nDisplayLength = nDuration }
        MessageManagerLib.DisplayStoryPanel(tParameters)
    end

    -- Fix the error that occurs when you empty the quantity box
    local fnOldOnListInputNumberHelper = self.MarketplaceCommodity.OnListInputNumberHelper
    self.MarketplaceCommodity.OnListInputNumberHelper = function(tMarketPlaceCommodity, wndParent, nNewValue)
        fnOldOnListInputNumberHelper(tMarketPlaceCommodity, wndParent, nNewValue or 0)
    end
end

function CommodityStats:OnListSubmitBtn( wndHandler, wndControl, eMouseButton, nLastRelativeMouseX, nLastRelativeMouseY )
    -- Save the last used params and scrollposition
    local containername = self:GetSelectedCategory(self.MarketplaceCommodity)
    wndHandler = wndHandler:GetParent()
    if containername ~= nil then
        local tCurrItem = wndHandler:GetData()[1]
        local wndParent = wndHandler:GetData()[2]
        self[containername] = {}
        self[containername].lastItemID = tCurrItem:GetItemId()
        self[containername].lastPricePerUnit = wndParent:FindChild("ListInputPrice"):GetCurrency()
        self[containername].lastQuantity = wndParent:FindChild("ListInputNumber"):GetText()
        self[containername].lastScrollPos = self.MarketplaceCommodity.wndMain:FindChild("MainScrollContainer"):GetVScrollPos()
    end
end

function CommodityStats:SaveLastUsedParams(tMarketPlaceCommodity, wndHandler)
    local containername = self:GetSelectedCategory(tMarketPlaceCommodity)
    if containername ~= nil then
        local tCurrItem = wndHandler:GetData()[1]
        local wndParent = wndHandler:GetData()[2]
        self[containername] = {}
        self[containername].lastItemID = tCurrItem:GetItemId()
        self[containername].lastPricePerUnit = wndParent:FindChild("ListInputPrice"):GetCurrency()
        self[containername].lastQuantity = wndParent:FindChild("ListInputNumber"):GetText()
        self[containername].lastScrollPos = tMarketPlaceCommodity.wndMain:FindChild("MainScrollContainer"):GetVScrollPos()
    end
end

function CommodityStats:GetSelectedCategory(tMarketPlaceCommodity)
    if tMarketPlaceCommodity.wndMain:FindChild("HeaderSellOrderBtn"):IsChecked() then return CommodityStats.Category.SELLORDER end
    if tMarketPlaceCommodity.wndMain:FindChild("HeaderBuyOrderBtn"):IsChecked() then return CommodityStats.Category.BUYORDER end
    if tMarketPlaceCommodity.wndMain:FindChild("HeaderSellNowBtn"):IsChecked() then return CommodityStats.Category.SELLNOW end
    if tMarketPlaceCommodity.wndMain:FindChild("HeaderBuyNowBtn"):IsChecked() then return CommodityStats.Category.BUYNOW end
    return nil
end

function CommodityStats:GetPrice(nItemId, tStats, selectedCategory)
    local price = 0
    if selectedCategory == CommodityStats.Category.SELLORDER or selectedCategory == CommodityStats.Category.BUYNOW then
        local sellPriceGroup = self.settings.baseSellPrice or CommodityStats.Pricegroup.TOP10
        local strategy = self.settings.sellStrategy or CommodityStats.Strategy.MATCH
        if selectedCategory == CommodityStats.Category.BUYNOW then
            sellPriceGroup = CommodityStats.Pricegroup.TOP1
            strategy = CommodityStats.Strategy.MATCH
        end
        price = tStats.arSellOrderPrices[sellPriceGroup].monPrice:GetAmount()
        if strategy == CommodityStats.Strategy.FIXED then
            price = price - self.settings.sellUndercutFixed or 0
            if price < 1 then price = 1 end
        end
        if strategy == CommodityStats.Strategy.PERCENTAGE then
            price = math.floor(price - (price / 100 * self.settings.sellUndercutPercentage or 0))
        end
    else
        local buyPriceGroup = self.settings.baseBuyPrice or CommodityStats.Pricegroup.TOP10
        local strategy = self.settings.buyStrategy or CommodityStats.Strategy.MATCH
        if selectedCategory == CommodityStats.Category.SELLNOW then
            buyPriceGroup = CommodityStats.Pricegroup.TOP1
            strategy = CommodityStats.Strategy.MATCH
        end

        price = tStats.arBuyOrderPrices[buyPriceGroup].monPrice:GetAmount()
        if strategy == CommodityStats.Strategy.FIXED then
            price = price + self.settings.buyIncreaseFixed or 0
        end
        if strategy == CommodityStats.Strategy.PERCENTAGE then
            price = math.floor(price + (price / 100 * self.settings.buyIncreasePercentage or 0))
        end
    end
    return price
end

function CommodityStats:OnCommodityInfoResults(nItemId, tStats, tOrders)
    glog:debug("Commodity info received for item ID " .. tostring(nItemId) .. ".")
    local stat = self:CreateCommodityStat(tStats)
    if stat.buyOrderCount ~= 0 or stat.sellOrderCount ~= 0 then
        if self.statistics[nItemId] == nil then
            self.statistics[nItemId] = {}
        end
        local timestamp = GetTime()
        stat.time = timestamp
        if self.statistics[nItemId][timestamp] == nil then
            self.statistics[nItemId][timestamp] = stat
        end
    end
    if self.isScanning then
        self.queueSize = self.queueSize - 1
        if self.queueSize == 0 then
            self.ScanButton:SetText(L["Finished!"])
            self.ScanButton:Enable(true)
            self.isScanning = false
        end
    end
end

function CommodityStats:OnCREDDExchangeInfoResults(arMarketStats, arOrders)
    glog:debug("Received CREDD info")
    local stat = self:CreateCommodityStat(arMarketStats)
    if stat.buyOrderCount ~= 0 or stat.sellOrderCount ~= 0 then
        if self.statistics[CREDDid] == nil then
            self.statistics[CREDDid] = {}
        end
        local timestamp = GetTime()
        stat.time = timestamp
        if self.statistics[CREDDid][timestamp] == nil then
            self.statistics[CREDDid][timestamp] = stat
        end
    end
end

function CommodityStats:CreateCommodityStat(tStats)
    local stat = {}
    stat.buyOrderCount = tStats.nBuyOrderCount
    stat.sellOrderCount = tStats.nSellOrderCount
    stat.buyPrices = {}
    stat.buyPrices.top1 = tStats.arBuyOrderPrices[CommodityStats.Pricegroup.TOP1].monPrice:GetAmount()
    stat.buyPrices.top10 = tStats.arBuyOrderPrices[CommodityStats.Pricegroup.TOP10].monPrice:GetAmount()
    stat.buyPrices.top50 = tStats.arBuyOrderPrices[CommodityStats.Pricegroup.TOP50].monPrice:GetAmount()
    stat.sellPrices = {}
    stat.sellPrices.top1 = tStats.arSellOrderPrices[CommodityStats.Pricegroup.TOP1].monPrice:GetAmount()
    stat.sellPrices.top10 = tStats.arSellOrderPrices[CommodityStats.Pricegroup.TOP10].monPrice:GetAmount()
stat.sellPrices.top50 = tStats.arSellOrderPrices[CommodityStats.Pricegroup.TOP50].monPrice:GetAmount()
    return stat
end

function CommodityStats:OnSave(eLevel)
    if eLevel ~= GameLib.CodeEnumAddonSaveLevel.Realm then
        return nil
    end 

    local save = {
        statistics = self.statistics,
        transactions = self.transactions,
        settings = self.settings,
        lastAverageRun = self.lastAverageRun
    }

    -- save window positions
    local mainPosLeft, mainPosTop = self.wndMain:GetPos()
    local commPosLeft, commPosTop = self.MarketplaceCommodity.wndMain:GetPos()
    save.mainPosition = { left = mainPosLeft, top = mainPosTop }
    save.commPosition = { left = commPosLeft, top = commPosTop }

    return save
end

function CommodityStats:OnRestore(eLevel, tData)
    self.transactions = tData.transactions or {}
    self.statistics = tData.statistics or {}
    self.lastAverageRun = tData.lastAverageRun or 0

    if tData.settings ~= nil then
        self.settings = tData.settings
        self:PurgeExpiredStats()
        self:AverageStatistics()
    end
    -- restore window positions
    if tData.mainPosition ~= nil then
        self.wndMain:Move(tData.mainPosition.left, tData.mainPosition.top, self.wndMain:GetWidth(), self.wndMain:GetHeight())
    end
    if tData.commPosition ~= nil then self.commPosition = tData.commPosition end
end

function CommodityStats:DrawColorNotes()
    DrawLine(self.wndStatistics:FindChild("PixieBuytop1"), 3, clrBuyTop1)
    DrawLine(self.wndStatistics:FindChild("PixieBuytop10"), 3, clrBuyTop10)
    DrawLine(self.wndStatistics:FindChild("PixieBuytop50"), 3, clrBuyTop50)
    DrawLine(self.wndStatistics:FindChild("PixieSelltop1"), 3, clrSellTop1)
    DrawLine(self.wndStatistics:FindChild("PixieSelltop10"), 3, clrSellTop10)
    DrawLine(self.wndStatistics:FindChild("PixieSelltop50"), 3, clrSellTop50)
end

function CommodityStats:LoadStatisticsForm()
    if self.wndStatistics ~= nil then
        self.wndStatistics:Destroy()
    end
    self.wndStatistics = Apollo.LoadForm(self.Xml, "StatisticsForm", self.wndMain:FindChild("MainForm"), self)
    GeminiLocale:TranslateWindow(L, self.wndStatistics)
    self:DrawColorNotes()
    self:SetOrderTypeSelection()
    self.plot = PixiePlot:New(self.wndStatistics:FindChild("Plot"))

    self.plot:RemoveAllDataSets()
    local stats = self.statistics[self.currentItemID]
    if stats == nil then
        local monTopBuy = self.wndStatistics:FindChild("monTopBuyPrice"):Show(false)
        local monTopSell = self.wndStatistics:FindChild("monTopSellPrice"):Show(false)
        local monPotentialProfit = self.wndStatistics:FindChild("monPotentialProfit"):Show(false)
        glog:debug("No statistics, showing an empty plot")
        -- show an empty plot
        self.plot:Redraw()
        return
    end
    local dsSellTop1 = { xStart = 0, values = {} }
    local dsSellTop10 = { xStart = 0, values = {} }
    local dsSellTop50 = { xStart = 0, values = {} }
    local dsBuyTop1 = { xStart = 0, values = {} }
    local dsBuyTop10 = { xStart = 0, values = {} }
    local dsBuyTop50 = { xStart = 0, values = {} }
    local earliest, minPrice, maxPrice = self:GetValueBoundaries(stats)
    local current = earliest
    local now = GetTime()
    self.plot:SetXMin(earliest)
    self.plot:SetXMax(now)
    self.plot:SetYMin(minPrice)
    self.plot:SetYMax(maxPrice)
    while current <= now do
        local stat = stats[current]
        if stat ~= nil then
            if self.settings.orderType == CommodityStats.OrderType.SELL or self.settings.orderType == CommodityStats.OrderType.BOTH then
                if stat.sellPrices.top1 ~= 0 then table.insert(dsSellTop1.values, { x = current, y = stat.sellPrices.top1 }) end
                if stat.sellPrices.top10 ~= 0 then table.insert(dsSellTop10.values, { x = current, y = stat.sellPrices.top10 }) end
                if stat.sellPrices.top50 ~= 0 then table.insert(dsSellTop50.values, { x = current, y = stat.sellPrices.top50 }) end
            end
            if self.settings.orderType == CommodityStats.OrderType.BUY or self.settings.orderType == CommodityStats.OrderType.BOTH then
                if stat.buyPrices.top1 ~= 0 then table.insert(dsBuyTop1.values, { x = current, y = stat.buyPrices.top1 }) end
                if stat.buyPrices.top10 ~= 0 then table.insert(dsBuyTop10.values, { x = current, y = stat.buyPrices.top10 }) end
                if stat.buyPrices.top50 ~= 0 then table.insert(dsBuyTop50.values, { x = current, y = stat.buyPrices.top50 }) end
            end
        end
        current = current + secondsInHour
    end

    self:EstimateProfits(stats[now])

    self.plot:SetXInterval(3600)

    self.plot:SetOption("ePlotStyle", PixiePlot.SCATTER)
    self.plot:SetOption("eCoordinateSystem", PixiePlot.CARTESIAN)
    self.plot:SetOption("bScatterLine", true)
    self.plot:SetOption("fLineWidth", 2)
    self.plot:SetOption("bDrawSymbol", true)
    self.plot:SetOption("fSymbolSize", 4)
    self.plot:SetOption("bDrawYValueLabels", true)
    self.plot:SetOption("bDrawXValueLabels", true)
    self.plot:SetOption("nLabelDecimals", 0)
    self.plot:SetOption("bDrawXGridLines", true)
    self.plot:SetOption("bDrawYGridLines", true)
    self.plot:SetOption("fXLabelMargin", 50)
    self.plot:SetOption("fYLabelMargin", 75)
    self.plot:SetOption("fPlotMargin", 15)
    self.plot:SetOption("nXValueLabels", 5)
    self.plot:SetOption("nYValueLabels", 5)
    self.plot:SetOption("xValueFormatter", function(value) return os.date(self.settings.dateFormatString, value) end)
    self.plot:SetOption("yValueFormatter", function(value) return FormatMoney(value) end)
    self.plot:SetOption("fXValueLabelTilt", 45)
    self.plot:SetOption("fYValueLabelTilt", 60)
    self.plot:SetOption("bWndOverlays", true)
    self.plot:SetOption("fWndOverlaySize", 15)
    self.plot:SetOption("wndOverlayLoadCallback", function(tData, wnd)
        local wndTooltip = wnd:LoadTooltipForm("CommodityStats.xml", "TooltipForm", self)
        GeminiLocale:TranslateWindow(L, wndTooltip)
        wndTooltip:FindChild("txtTime"):SetText(os.date(self.settings.dateFormatString, tData.x))
        wndTooltip:FindChild("monPrice"):SetAmount(tData.y)
        wnd:SetTooltipForm(wndTooltip)
    end)
    self.plot:SetOption("aPlotColors", self:GetPlotColors(self.settings.orderType))
    self.plot:SetOption("wndOverlayMouseEventCallback", function(tData, eType)
        glog:debug("Mouse event " .. eType)
        glog:debug(tData)
    end)


    if self.settings.orderType == CommodityStats.OrderType.SELL or self.settings.orderType == CommodityStats.OrderType.BOTH then
        self.plot:AddDataSet(dsSellTop1)
        self.plot:AddDataSet(dsSellTop10)
        self.plot:AddDataSet(dsSellTop50)
    end
    if self.settings.orderType == CommodityStats.OrderType.BUY or self.settings.orderType == CommodityStats.OrderType.BOTH then
        self.plot:AddDataSet(dsBuyTop1)
        self.plot:AddDataSet(dsBuyTop10)
        self.plot:AddDataSet(dsBuyTop50)
    end
    self.plot:Redraw()
end

function CommodityStats:GetPlotColors(nOrderType)
    if nOrderType == CommodityStats.OrderType.BOTH then
        return {clrSellTop1, clrSellTop10, clrSellTop50, clrBuyTop1, clrBuyTop10, clrBuyTop50 }
    end

    if nOrderType == CommodityStats.OrderType.SELL then
        return {clrSellTop1, clrSellTop10, clrSellTop50 }
    end

    if nOrderType == CommodityStats.OrderType.BUY then
        return {clrBuyTop1, clrBuyTop10, clrBuyTop50 }
    end
end

function CommodityStats:EstimateProfits(prices)
    local monTopBuy = self.wndStatistics:FindChild("monTopBuyPrice")
    local monTopSell = self.wndStatistics:FindChild("monTopSellPrice")
    local monPotentialProfit = self.wndStatistics:FindChild("monPotentialProfit")
    monTopBuy:Show(false)
    monTopSell:Show(false)
    monPotentialProfit:Show(false)

    if prices ~= nil then
        if prices.buyPrices.top1 > 0 then
            self.wndStatistics:FindChild("txtTopBuyPrice"):Show(false)
            monTopBuy:Show(true)
            monTopBuy:SetAmount(prices.buyPrices.top1)
        end
        if prices.sellPrices.top1 > 0 then
            self.wndStatistics:FindChild("txtTopSellPrice"):Show(false)
            monTopSell:Show(true)
            monTopSell:SetAmount(prices.sellPrices.top1)
        end
        if prices.buyPrices.top1 > 0 and prices.sellPrices.top1 > 0 then
            local estimatedProfit = prices.sellPrices.top1 - prices.buyPrices.top1
            if estimatedProfit > 0 then
                self.wndStatistics:FindChild("txtPotentialProfit"):Show(false)
                monPotentialProfit:Show(true)
                monPotentialProfit:SetAmount(estimatedProfit)
            end
        end
    end
end

function CommodityStats:SetOrderTypeSelection()
    if self.settings.orderType == CommodityStats.OrderType.BUY then self.wndStatistics:FindChild("btnBuy"):SetCheck(true) end
    if self.settings.orderType == CommodityStats.OrderType.SELL then self.wndStatistics:FindChild("btnSell"):SetCheck(true) end
    if self.settings.orderType == CommodityStats.OrderType.BOTH then self.wndStatistics:FindChild("btnBoth"):SetCheck(true) end
end

function CommodityStats:GetValueBoundaries(t)
    local earliest = -1
    local minPrice = -1
    local maxPrice = -1
    
    for i, data in pairs(t) do
    	local timestamp = tonumber(i)
    	if timestamp ~= nil then
	        if earliest == -1 or earliest > timestamp then
	            earliest = timestamp
	        end

	        if self.settings.orderType == CommodityStats.OrderType.SELL or self.settings.orderType == CommodityStats.OrderType.BOTH then
	            if data.sellPrices.top1 > maxPrice then maxPrice = data.sellPrices.top1 end
	            if data.sellPrices.top10 > maxPrice then maxPrice = data.sellPrices.top10 end
	            if data.sellPrices.top50 > maxPrice then maxPrice = data.sellPrices.top50 end
	        end
	        if self.settings.orderType == CommodityStats.OrderType.BUY or self.settings.orderType == CommodityStats.OrderType.BOTH then
	            if data.buyPrices.top1 > maxPrice then maxPrice = data.buyPrices.top1 end
	            if data.buyPrices.top10 > maxPrice then maxPrice = data.buyPrices.top10 end
	            if data.buyPrices.top50 > maxPrice then maxPrice = data.buyPrices.top50 end
	        end

	        minPrice = maxPrice

	        if self.settings.orderType == CommodityStats.OrderType.SELL or self.settings.orderType == CommodityStats.OrderType.BOTH then
	            if data.sellPrices.top1 < minPrice and data.sellPrices.top1 ~= 0 then minPrice = data.sellPrices.top1 end
	            if data.sellPrices.top10 < minPrice and data.sellPrices.top10 ~= 0 then minPrice = data.sellPrices.top10 end
	            if data.sellPrices.top50 < minPrice and data.sellPrices.top50 ~= 0 then minPrice = data.sellPrices.top50 end
	        end
	        if self.settings.orderType == CommodityStats.OrderType.BUY or self.settings.orderType == CommodityStats.OrderType.BOTH then
	            if data.buyPrices.top1 < minPrice and data.buyPrices.top1 ~= 0 then minPrice = data.buyPrices.top1 end
	            if data.buyPrices.top10 < minPrice and data.buyPrices.top10 ~= 0 then minPrice = data.buyPrices.top10 end
	            if data.buyPrices.top50 < minPrice and data.buyPrices.top50 ~= 0 then minPrice = data.buyPrices.top50 end
	        end
	    end
    end
    return earliest, minPrice, maxPrice
end

function CommodityStats:PurgeExpiredStats()
    if self.settings.daysToKeep > 0 then
        local counter = 0
        local minimumTime = GetTime() - (self.settings.daysToKeep * secondsInDay)
        for index, item in pairs(self.statistics) do
            if type(index) == 'number' then
                for timestamp, stat in pairs(item) do
                    if type(timestamp) == 'number' then
                        if timestamp <= minimumTime then
                            item[timestamp] = nil
                            counter = counter + 1
                        end
                    end
                end
            end
        end
        if counter > 0 then
            glog:debug("Removed " .. tostring(counter) .. " statistics that were older than " .. tostring(self.settings.daysToKeep) .. ".")
        end
    end
end

function CommodityStats:AverageStatistics()
	if self.settings.daysUntilAverage > 0 and (os.time() - self.lastAverageRun) > secondsInDay then
		local treshold = GetTime() - (secondsInDay * self.settings.daysUntilAverage)
		for itemid, stats in pairs(self.statistics) do 
            if type(itemid) == 'number' then
    			if stats.earliest == nil then
    				local earliest, minPrice, maxPrice = self:GetValueBoundaries(stats)
    				stats.earliest = earliest
    			end
    			while stats.earliest < treshold do
    				local firstStat = stats.earliest
    				local newStats = {}
    				while stats.earliest < firstStat + secondsInDay and stats.earliest < treshold do
    					local stat = stats[stats.earliest]
    					if stat ~= nil then
    						table.insert(newStats, stat)
    						stats[stats.earliest] = nil
    					end
    					stats.earliest = stats.earliest + secondsInHour
    				end
                    if #newStats > 0 then
                        stats[firstStat] = AverageStats(newStats)
                    end
    			end
            end
            self.lastAverageRun = os.time()
		end
	end
end

function CommodityStats:LoadTransactionsForm()
    if self.wndTransactions ~= nil then
        self.wndTransactions:Destroy()
    end
    self.wndTransactions = Apollo.LoadForm(self.Xml, "TransactionsForm", self.wndMain:FindChild("MainForm"), self)
    GeminiLocale:TranslateWindow(L, self.wndTransactions)
    self:DisplayTransactions(self.currentItemID)
end

function CommodityStats:LoadConfigForm()
    if self.wndConfig ~= nil then
        self.wndConfig:Destroy()
    end
    self.wndConfig = Apollo.LoadForm(self.Xml, "ConfigForm", self.wndMain:FindChild("MainForm"), self)
    GeminiLocale:TranslateWindow(L, self.wndConfig)

    -- history settings
    self.wndConfig:FindChild("txtStatisticsAge"):SetText(tostring(self.settings.daysToKeep))
    self.wndConfig:FindChild("txtStatisticsAverage"):SetText(tostring(self.settings.daysUntilAverage))

    -- date format settings
    self.wndConfig:FindChild("txtCustomDateTime"):SetText(self.settings.dateFormatString)
    if self.settings.dateFormatString == CommodityStats.DateFormat.DDMM then
        self.wndConfig:FindChild("chkddmmyyyy"):SetCheck(true)
    elseif self.settings.dateFormatString == CommodityStats.DateFormat.MMDD then
        self.wndConfig:FindChild("chkmmddyyyy"):SetCheck(true)
    else
        self.wndConfig:FindChild("chkCustom"):SetCheck(true)
        self.wndConfig:FindChild("CustomDateTimeContainer"):Show(true)
    end

    -- sellorder pricing
    self:SetSelectedBaseSellPrice()
    self:SetSelectedSellStrategy()
    self.wndConfig:FindChild("txtUndercutPercentage"):SetText(tostring(self.settings.sellUndercutPercentage or 0))
    self.wndConfig:FindChild("monSellUndercutFixed"):SetAmount(self.settings.sellUndercutFixed or 0)
    self.wndConfig:FindChild("chkAutoQuantity"):SetCheck(self.settings.autoQuantity)
    -- buyorder pricing
    self:SetSelectedBaseBuyPrice()
    self:SetSelectedBuyStrategy()
    self.wndConfig:FindChild("txtIncreasePercentage"):SetText(tostring(self.settings.buyIncreasePercentage or 0))
    self.wndConfig:FindChild("monBuyIncreaseFixed"):SetAmount(self.settings.buyIncreaseFixed or 0)

    self.wndConfig:Show(true)
end

function FormatMoney(nAmount)
    -- careful with negative amounts when calculating modulo
    local isNegative = nAmount < 0
    if isNegative then nAmount = nAmount * -1 end

    local platinum = math.floor(nAmount / 1000000)
    nAmount = nAmount % 1000000
    local gold = math.floor(nAmount / 10000)
    nAmount = nAmount % 10000
    local silver = math.floor(nAmount / 100)
    local copper = nAmount % 100
    local output = ""
    if platinum > 0 then output = output .. tostring(platinum) .. "p " end
    if gold > 0 then output = output .. tostring(gold) .. "g " end
    if silver > 0 then output = output .. tostring(silver) .. "s " end
    output = output .. tostring(math.floor(copper)) .. "c"
    if isNegative then output = "-" .. output end
    return output
end

function AverageStats(tCollection)
    -- we have to make sure we don't take '0' values (no defined price) along in our averaging.
    -- that means each stat can have a different collection size.
    -- The exception is buy/sell order count
    local buyOrderCountCollection = {}
    local sellOrderCountCollection = {}
    local buyTop1Collection = {}
    local buyTop10Collection = {}
    local buyTop50Collection = {}
    local sellTop1Collection = {}
    local sellTop10Collection = {}
    local sellTop50Collection = {}

    for i, item in ipairs(tCollection) do
    	if tonumber(i) then
	        table.insert(buyOrderCountCollection, item.buyOrderCount)
	        table.insert(sellOrderCountCollection, item.sellOrderCount)
	        if item.buyPrices.top1 > 0 then table.insert(buyTop1Collection, item.buyPrices.top1) end
	        if item.buyPrices.top10 > 0 then table.insert(buyTop10Collection, item.buyPrices.top10) end
	        if item.buyPrices.top50 > 0 then table.insert(buyTop50Collection, item.buyPrices.top50) end
	        if item.sellPrices.top1 > 0 then table.insert(sellTop1Collection, item.sellPrices.top1) end
	        if item.sellPrices.top10 > 0 then table.insert(sellTop10Collection, item.sellPrices.top10) end
	        if item.sellPrices.top50 > 0 then table.insert(sellTop50Collection, item.sellPrices.top50) end
	    end
    end

    return { buyOrderCount = AverageNumbers(buyOrderCountCollection), sellOrderCount = AverageNumbers(sellOrderCountCollection), 
        sellPrices = { top1 = AverageNumbers(sellTop1Collection), top10 = AverageNumbers(sellTop10Collection), top50 = AverageNumbers(sellTop50Collection)},
        buyPrices = { top1 = AverageNumbers(buyTop1Collection), top10 = AverageNumbers(buyTop10Collection), top50 = AverageNumbers(buyTop50Collection)}
    }
end

function AverageNumbers(tCollection)
	if #tCollection == 0 then return 0 end
    local total = 0
    for i, val in ipairs(tCollection) do
        total = total + val
    end
    return math.floor(total / #tCollection)
end

function CommodityStats:CleanItemDatabase()
    -- needed to clean zero values when I mess up
    for id, stats in pairs(self.statistics) do
        local highest = 0
        for time, stat in pairs(stats) do
            if stat.buyOrderCount == nil then stat.buyOrderCount = 0 end
            if stat.sellOrderCount == nil then stat.sellOrderCount = 0 end
            if stat.buyOrderCount > highest then highest = stat.buyOrderCount end
            if stat.sellOrderCount > highest then highest = stat.sellOrderCount end
        end
        if highest == 0 then
            glog:debug("Deleting item ID " .. tostring(id))
            self.statistics[id] = nil
        end
    end
end

function DrawLine(wndTarget, height, color)
    local width = wndTarget:GetWidth()
    local center = math.floor(wndTarget:GetHeight() / 2)
    wndTarget:AddPixie({
        bLine = true,
        fWidth = height,
        cr = color,
        loc = {
            fPoints = {0,0,0,0},
            nOffsets = {
                0,
                center,
                width,
                center
            }
        },
    })
end

function GetTime()
    -- this function returns unix epoch time. We do some extra trickery to round the time to hours, since we don't need stats as detailed as every minute/second
    local time = GameLib.GetLocalTime()
    timeargs = {}
    timeargs.year = time.nYear
    timeargs.month = time.nMonth
    timeargs.day = time.nDay
    timeargs.hour = time.nHour
    timeargs.min = 0
    timeargs.sec = 0
    return os.time(timeargs)
end

function CommodityStats:OnMailboxOpen()
    -- Disabling it for non-US locales for now
    if L["Locale"] == "enUS" then
        local mails = MailSystemLib.GetInbox()
        for i, mail in pairs(mails) do
            local info = mail:GetMessageInfo()
            local itemID, transaction
            if info.eSenderType == MailSystemLib.EmailType_CommodityAuction and info.bIsRead == false then
                if info.strBody:lower():find("seller has been found") then
                    itemID, transaction = processTransaction(info, CommodityStats.Result.BUYSUCCESS)
                elseif info.strBody:lower():find("buyer has been found") then
                    itemID, transaction = processTransaction(info, CommodityStats.Result.SELLSUCCESS)
                elseif info.strBody:lower():find("buy order") then
                    itemID, transaction = processTransaction(info, CommodityStats.Result.BUYEXPIRED)
                elseif info.strBody:lower():find("sell order") then
                    itemID, transaction = processTransaction(info, CommodityStats.Result.SELLEXPIRED)
                end
                if transaction ~= nil and itemID ~= nil then
                    if self.transactions[itemID] == nil then self.transactions[itemID] = {} end
                    table.insert(self.transactions[itemID], transaction)
                end
                mail:MarkAsRead()
            end
        end
    end
end

function CommodityStats:DisplayTransactions(itemID)
    for i, listitem in ipairs(transactionListItems) do
        listitem:Destroy()
    end
    transactionListItems = {}
    local buyTotal = 0
    local sellTotal = 0
    local buyQuantity = 0
    local sellQuantity = 0

    local wndItems = self.wndTransactions:FindChild("ItemList")
    if itemID == nil then
        for id, transactions in pairs(self.transactions) do
            for i, transaction in ipairs(self.transactions[id]) do
                table.insert(transactionListItems, self:AddTransactionItem(wndItems, id, transaction))
            end
        end
    else
        if self.transactions[itemID] ~= nil then
            for i, transaction in ipairs(self.transactions[itemID]) do
                if transaction.result == CommodityStats.Result.BUYSUCCESS then 
                    buyQuantity = buyQuantity + transaction.quantity
                    buyTotal = buyTotal + (transaction.quantity * transaction.price)
                end
                if transaction.result == CommodityStats.Result.SELLSUCCESS then
                    sellQuantity = sellQuantity + transaction.quantity
                    sellTotal = sellTotal + (transaction.quantity * transaction.price)
                end
                table.insert(transactionListItems, self:AddTransactionItem(wndItems, id, transaction))
            end
        end
    end
    self.wndTransactions:FindChild("txtTotalBuyAmount"):SetText(tostring(buyQuantity))
    self.wndTransactions:FindChild("monTotalBuyPrice"):SetAmount(buyTotal)
    self.wndTransactions:FindChild("txtTotalSellAmount"):SetText(tostring(sellQuantity))
    self.wndTransactions:FindChild("monTotalSellPrice"):SetAmount(sellTotal)
    
    local totalprofit = sellTotal - buyTotal
    local profitColor = "green"
    if totalprofit < 0 then
        totalprofit = totalprofit * -1
        profitColor = "red" 
        self.wndTransactions:FindChild("txtTotalProfit"):SetText(L["Total loss:"])
    end
    self.wndTransactions:FindChild("monProfit"):SetTextColor(profitColor)
    self.wndTransactions:FindChild("monProfit"):SetAmount(totalprofit)
    wndItems:ArrangeChildrenVert()
    self.wndTransactions:Show(true)
    self.wndTransactions:ToFront()
end


function CommodityStats:AddTransactionItem(wndTarget, itemID, transaction)
    local result = ""
    if transaction.result == CommodityStats.Result.BUYSUCCESS then result = L["Buy success"] end
    if transaction.result == CommodityStats.Result.SELLSUCCESS then result = L["Sell success"] end
    if transaction.result == CommodityStats.Result.BUYEXPIRED then result = L["Buy expired"] end
    if transaction.result == CommodityStats.Result.SELLEXPIRED then result = L["Sell expired"] end
    local wndTransaction = Apollo.LoadForm(self.Xml, "TransactionItem", wndTarget, self)
    wndTransaction:FindChild("txtDate"):SetText(os.date(self.settings.dateFormatString, transaction.timestamp))
    wndTransaction:FindChild("txtQuantity"):SetText(tostring(transaction.quantity))
    wndTransaction:FindChild("monPrice"):SetAmount(transaction.price)
    wndTransaction:FindChild("txtResult"):SetText(result)
    return wndTransaction
end

function processTransaction(info, transactionresult)
    glog:info("Processing mail with subject '" .. info.strSubject .."'. Transactionresult: " .. tostring(transactionresult) .. ".")
    local transaction = { result = transactionresult }
    local quantity, name, price, unit
    if transactionresult == CommodityStats.Result.BUYSUCCESS or transactionresult == CommodityStats.Result.SELLSUCCESS then
        quantity, name, price, unit = string.match(info.strBody, '(%d+)[^%s](.-)%.?\n?\r?\n.-(%d+)(.-)\r?\n')
    else
        quantity, name, price = string.match(info.strBody, 'for (%d+)[^%s](.-)at%s(%d+)')
    end
    if quantity == nil or name == nil or price == nil then
        glog:warn("Couldn't parse mail with subject '" .. info.strSubject .. "'.")
        return nil, nil
    end
    transaction.quantity = tonumber(trim(quantity))
    transaction.price = tonumber(trim(price))
    transaction.timestamp = getMailTime(info)
    local item = getItemByName(singularize(trim(name))) 
    if item == nil then
        glog:warn("Couldn't find item ID for " .. name .. ". Transaction not saved.")
        return nil, nil
    end
    return item.nId, transaction
end

function getItemByName(name)
    local results = MarketplaceLib.SearchCommodityItems(name)
    local returnVal = nil
    for i, result in pairs(results) do
        if result.strName:lower() == name:lower() then
            returnVal = result
            break
        end
    end
    return returnVal
end

function getMailTime(mailinfo)
    -- mails don't have info on when the mail was sent, only the time until it expires, represented by a float between 0 and 30
    local elapsedSeconds = math.floor((30 - mailinfo.fExpirationTime) * secondsInDay)
    return os.time() - elapsedSeconds
end

function singularize(s)
    -- Auction mails pluralize certain item names if multiple items were bought/sold.
    -- We need the singular form in order to actually find the item ID.
    -- This is mostly guesswork. If anyone knows a better way to handle this, please let me know.
    local words = { "rune", "bar", "bone", "core", "fragment", "scrap", "sign", "pelt", "chunk", "leather", "dye", "charge", "injector", "pummelgranate", "roast", "breast",
                    "boost", "stimulant", "potion", "cloth", "grenade", "juice", "serum", "extract", "leave", "disruptor", "emitter", "focuser", "spirovine", "root", 
                    "transformer", "acceleron", "ingot", "bladeleave", "coralscale", "zephyrite", "sample", "faerybloom", "sapphire", "yellowbell", "sample"}
    s = s:lower()
    for i, word in pairs(words) do
        s = s:gsub(word .. "s", word)
    end
    return s
end

function trim(s)
    return s:find'^%s*$' and '' or s:match'^%s*(.*%S)'
end

---------------------------------------------------------------------------------------------------
-- Button Functions
---------------------------------------------------------------------------------------------------

function CommodityStats:OnConfigure(sCommand, sArgs)
    if sArgs ~= nil then
        if sArgs:lower() == "rover" then
            Event_FireGenericEvent("SendVarToRover", "Commodity Prices", self.statistics)
            Event_FireGenericEvent("SendVarToRover", "Commodity Transactions", self.transactions)
            glog:info("Sent statistics to Rover")
            return
        end
        if sArgs:lower() == "forceaverage" then
            glog:info("Resetting the last average time of each scan to zero and invoking scan. This could timeout with large collections")
            for itemid, stats in pairs(self.statistics) do 
                stats.earliest = nil
            end
            self:AverageStatistics()
            return
        end
        if sArgs:lower() == "log" then
            self:DisplayTransactions()
            return
        end
    end
    self.wndMain:Show(true)
    self:OnTabSelected(nil, nil, nil, true)
end

function CommodityStats:OnSettingsSave(wndHandler, wndControl, eMouseButton)
    self.settings.daysToKeep = tonumber(self.wndConfig:FindChild("txtStatisticsAge"):GetText())
    self.settings.daysUntilAverage = tonumber(self.wndConfig:FindChild("txtStatisticsAverage"):GetText())
    wndControl:SetText(L["Saved!"])
end

function CommodityStats:OnCancel()
    self.wndMain:Show(false)
end

function CommodityStats:OnScanData( wndHandler, wndControl, eMouseButton )
    self.ScanButton:SetText(L["Scanning..."])
    self.ScanButton:Enable(false)
    local queue = {}
    for idx, tTopCategory in ipairs(MarketplaceLib.GetCommodityFamilies()) do
        for idx2, tMidCategory in ipairs(MarketplaceLib.GetCommodityCategories(tTopCategory.nId)) do
            for idx3, tBotCategory in pairs(MarketplaceLib.GetCommodityTypes(tMidCategory.nId)) do
                for idx4, tItem in pairs(MarketplaceLib.GetCommodityItems(tBotCategory.nId)) do
                    table.insert(queue, tItem.nId)
                end
            end
        end
    end
    self.queueSize = #queue
    glog:info("Requesting price info on " .. tostring(self.queueSize) .. " items.")
    self.isScanning = true
    for i, id in ipairs(queue) do
        MarketplaceLib.RequestCommodityInfo(id)
    end
end

function CommodityStats:OnRequestStatistics( wndHandler, wndControl, eMouseButton )
    local itemID = wndControl:GetParent():GetName()
    if self.wndMain:IsVisible() then
        if self.wndMain:FindChild("txtItemID"):GetText() == itemID then
            self.wndMain:Show(false)
            return
        end
    end
    self.wndMain:Show(true)
    self.wndMain:ToFront()
    if itemID ~= "ActLater" then
        self.currentItemID = tonumber(itemID)
        local item = Item.GetDataFromId(self.currentItemID)
        glog:info("Statistics requested for " .. item:GetName())
        self.wndMain:FindChild("txtItemID"):SetText(tostring(itemID))
        self.wndMain:FindChild("txtTitle"):SetText(item:GetName())
    else
        -- This is CREDD
        self.currentItemID = CREDDid
        glog:info("Statistics requested for CREDD")
        self.wndMain:FindChild("txtItemID"):SetText(tostring(CREDDid))
        self.wndMain:FindChild("txtTitle"):SetText("C.R.E.D.D.")

    end
    self:OnTabSelected()
end

function CommodityStats:OnSelectAuctionType( wndHandler, wndControl, eMouseButton )
    local name = wndControl:GetName()
    if name == "btnBuy" then self.settings.orderType = CommodityStats.OrderType.BUY end
    if name == "btnSell" then self.settings.orderType = CommodityStats.OrderType.SELL end
    if name == "btnBoth" then self.settings.orderType = CommodityStats.OrderType.BOTH end
    self:LoadStatisticsForm()
end

function CommodityStats:OnTabSelected(wndHandler, wndControl, eMouseButton, configOnly)
    self.selectionBox = nil
    if self.wndTransactions ~= nil then self.wndTransactions:Destroy() end
    if self.wndStatistics ~= nil then self.wndStatistics:Destroy() end
    if self.wndConfig ~= nil then self.wndConfig:Destroy() end
    local name = ""
    if wndControl ~= nil then
        name = wndControl:GetName()
        self.settings.lastSelectedTab = name
    else
        name = self.settings.lastSelectedTab
    end
    if name == nil then 
        name = "TabStatistics" 
    end

    if configOnly then
        name = "TabConfig"
    end

    self.wndMain:FindChild("TabStatistics"):Enable(not configOnly)
    self.wndMain:FindChild("TabTransactions"):Enable(not configOnly)

    self.wndMain:FindChild("TabStatistics"):SetCheck(false)
    self.wndMain:FindChild("TabTransactions"):SetCheck(false)
    self.wndMain:FindChild("TabConfig"):SetCheck(false)

    self.wndMain:FindChild(name):SetCheck(true)
    if name == "TabStatistics" then self:LoadStatisticsForm() end
    if name == "TabTransactions" then self:LoadTransactionsForm() end
    if name == "TabConfig" then self:LoadConfigForm() end
end

function CommodityStats:OnTransactionHover( wndHandler, wndControl, x, y )
	if self.selectionBox == nil then
		self.selectionBox = Apollo.LoadForm(self.Xml, "TransactionItemSelector", self.wndTransactions:FindChild("ItemList"), self)
        self.selectionBox:ToFront()
	end
    local scrollPos = wndControl:GetParent():GetVScrollPos()
    local posLeft, posTop = wndHandler:GetPos()
    self.selectionBox:Move(posLeft, posTop + scrollPos, wndHandler:GetWidth() - 20 , wndHandler:GetHeight())
end

---------------------------------------------------------------------------------------------------
-- TransactionsForm Functions
---------------------------------------------------------------------------------------------------

function CommodityStats:OnResetTransactionHistory( wndHandler, wndControl, eMouseButton )
	self.wndTransactions:FindChild("wndConfirm"):Show(true)
end

function CommodityStats:OnConfirmTransactionReset( wndHandler, wndControl, eMouseButton )
	local response = wndControl:GetText()
	if response == "Yes" then
		self.transactions[self.currentItemID] = {}
        self:LoadTransactionsForm()
	end
	
	self.wndTransactions:FindChild("wndConfirm"):Show(false)
end

function CommodityStats:SetSelectedBaseSellPrice()
    local buttonText = "undefined"
    if self.settings.baseSellPrice == nil then self.settings.baseSellPrice = CommodityStats.Pricegroup.TOP1 end
    
    if self.settings.baseSellPrice == CommodityStats.Pricegroup.TOP1 then buttonText = L["top 1 sell price"] end
    if self.settings.baseSellPrice == CommodityStats.Pricegroup.TOP10 then buttonText = L["top 10 sell price"] end
    if self.settings.baseSellPrice == CommodityStats.Pricegroup.TOP50 then buttonText = L["top 50 sell price"] end

    self.wndConfig:FindChild("txtBaseSellPrice"):SetText(buttonText)
end

function CommodityStats:SetSelectedSellStrategy()
    local buttonName = ""
    if self.settings.sellStrategy == nil then self.settings.sellStrategy = CommodityStats.Strategy.MATCH end
    if self.settings.sellStrategy == CommodityStats.Strategy.MATCH then buttonName = "rboSellPriceStrategyMatch" end
    if self.settings.sellStrategy == CommodityStats.Strategy.PERCENTAGE then
        buttonName = "rboSellPriceStrategyPercentage"
        self.wndConfig:FindChild("UndercutPercentageContainer"):Show(true)
    end
    if self.settings.sellStrategy == CommodityStats.Strategy.FIXED then
        buttonName = "rboSellPriceStrategyFixed"
        self.wndConfig:FindChild("UndercutFixedContainer"):Show(true)
    end
    self.wndConfig:FindChild(buttonName):SetCheck(true)
end

function CommodityStats:SetSelectedBaseBuyPrice()
    local buttonText = "undefined"
    if self.settings.baseBuyPrice == nil then self.settings.baseBuyPrice = CommodityStats.Pricegroup.TOP1 end
    
    if self.settings.baseBuyPrice == CommodityStats.Pricegroup.TOP1 then buttonText = L["top 1 buy price"] end
    if self.settings.baseBuyPrice == CommodityStats.Pricegroup.TOP10 then buttonText = L["top 10 buy price"] end
    if self.settings.baseBuyPrice == CommodityStats.Pricegroup.TOP50 then buttonText = L["top 50 buy price"] end

    self.wndConfig:FindChild("txtBaseBuyPrice"):SetText(buttonText)
end

function CommodityStats:SetSelectedBuyStrategy()
    local buttonName = ""
    if self.settings.buyStrategy == nil then self.settings.buyStrategy = CommodityStats.Strategy.MATCH end
    if self.settings.buyStrategy == CommodityStats.Strategy.MATCH then buttonName = "rboBuyPriceStrategyMatch" end
    if self.settings.buyStrategy == CommodityStats.Strategy.PERCENTAGE then
        buttonName = "rboBuyPriceStrategyPercentage"
        self.wndConfig:FindChild("IncreasePercentageContainer"):Show(true)
    end
    if self.settings.buyStrategy == CommodityStats.Strategy.FIXED then
        buttonName = "rboBuyPriceStrategyFixed"
        self.wndConfig:FindChild("IncreaseFixedContainer"):Show(true)
    end
    self.wndConfig:FindChild(buttonName):SetCheck(true)
end

function CommodityStats:ShowMessage(messages)
    local tParameters= {
        iWindowType = GameLib.CodeEnumStoryPanel.Informational,
        tLines = messages,
        nDisplayLength = 3
    }
    MessageManagerLib.DisplayStoryPanel(tParameters)
end

---------------------------------------------------------------------------------------------------
-- ConfigForm Functions
---------------------------------------------------------------------------------------------------

function CommodityStats:OnSelectDateFormat( wndHandler, wndControl, eMouseButton )
    local controlname = wndControl:GetName()
    if controlname == "chkddmmyyyy" then 
        self.settings.dateFormatString = CommodityStats.DateFormat.DDMM
        self.wndConfig:FindChild("CustomDateTimeContainer"):Show(false)
    end
    if controlname == "chkmmddyyyy" then 
        self.settings.dateFormatString = CommodityStats.DateFormat.MMDD
        self.wndConfig:FindChild("CustomDateTimeContainer"):Show(false)
    end
    if controlname == "chkCustom" then
        self.wndConfig:FindChild("CustomDateTimeContainer"):Show(true)
    end
end

function CommodityStats:OnSetCustomDateTimeFormat( wndHandler, wndControl, eMouseButton )
    local formatstring = self.wndConfig:FindChild("txtCustomDateTime"):GetText()
    self.settings.dateFormatString = formatstring
    self:ShowMessage({L["Custom format successfully saved"]})
end

function CommodityStats:OnBaseSellpriceDropDown( wndHandler, wndControl, eMouseButton )
    self.wndConfig:FindChild("BaseSellPriceContainer"):Show(true)    
    wndControl:SetCheck(true)
end

function CommodityStats:OnBaseSellpriceChecked( wndHandler, wndControl, eMouseButton )
    local selectedButton = self.wndConfig:FindChild("BaseSellPriceContainer"):GetRadioSelButton("BaseSellPrice"):GetName()
    local priceGroup = self.settings.baseSellPrice or CommodityStats.Pricegroup.TOP1
    if selectedButton == "btnBaseSellPrice1" then priceGroup = CommodityStats.Pricegroup.TOP1 end
    if selectedButton == "btnBaseSellPrice10" then priceGroup = CommodityStats.Pricegroup.TOP10 end
    if selectedButton == "btnBaseSellPrice50" then priceGroup = CommodityStats.Pricegroup.TOP50 end

    self.settings.baseSellPrice = priceGroup
    self:SetSelectedBaseSellPrice()

    self.wndConfig:FindChild("btnDropBaseSellPrice"):SetCheck(false)
    self.wndConfig:FindChild("BaseSellPriceContainer"):Show(false)
end

function CommodityStats:OnSelectSellpriceStrategy( wndHandler, wndControl, eMouseButton )
    self.wndConfig:FindChild("UndercutPercentageContainer"):Show(false)
    self.wndConfig:FindChild("UndercutFixedContainer"):Show(false)
    local sellStrategy = self.settings.sellStrategy
    local selectedButton = self.wndConfig:FindChild("SellPriceStrategyContainer"):GetRadioSelButton("SellPriceStrategy"):GetName()
    if selectedButton == "rboSellPriceStrategyMatch" then sellStrategy = CommodityStats.Strategy.MATCH end
    if selectedButton == "rboSellPriceStrategyPercentage" then
        sellStrategy = CommodityStats.Strategy.PERCENTAGE
        self.wndConfig:FindChild("UndercutPercentageContainer"):Show(true)
    end
    if selectedButton == "rboSellPriceStrategyFixed" then
        sellStrategy = CommodityStats.Strategy.FIXED
        self.wndConfig:FindChild("UndercutFixedContainer"):Show(true)
    end

    self.settings.sellStrategy = sellStrategy
end

function CommodityStats:btnSaveSellUndercutPercentage( wndHandler, wndControl, eMouseButton )
    local input = tonumber(self.wndConfig:FindChild("txtUndercutPercentage"):GetText())
    if input ~= nil then
        if input >= 0 and input <= 100 then
            self.settings.sellUndercutPercentage = input
            self:ShowMessage({L["Value successfully saved"]})
            return
        end
    end
    self:ShowMessage( { L["Input not valid, percentage not saved"], L["Please enter a numeric value between 0 and 100"] })
end

function CommodityStats:btnSaveSellUndercutFixed( wndHandler, wndControl, eMouseButton )
    local input = self.wndConfig:FindChild("monSellUndercutFixed"):GetAmount()
    self.settings.sellUndercutFixed = input
    self:ShowMessage({L["Value successfully saved"]})
end

function CommodityStats:OnBaseBuypriceDropDown( wndHandler, wndControl, eMouseButton )
    self.wndConfig:FindChild("BaseBuyPriceContainer"):Show(true)    
    wndControl:SetCheck(true)
end

function CommodityStats:OnBaseBuypriceChecked( wndHandler, wndControl, eMouseButton )
    local selectedButton = self.wndConfig:FindChild("BaseBuyPriceContainer"):GetRadioSelButton("BaseBuyPrice"):GetName()
    local priceGroup = self.settings.baseBuyPrice or CommodityStats.Pricegroup.TOP1
    if selectedButton == "btnBaseBuyPrice1" then priceGroup = CommodityStats.Pricegroup.TOP1 end
    if selectedButton == "btnBaseBuyPrice10" then priceGroup = CommodityStats.Pricegroup.TOP10 end
    if selectedButton == "btnBaseBuyPrice50" then priceGroup = CommodityStats.Pricegroup.TOP50 end

    self.settings.baseBuyPrice = priceGroup
    self:SetSelectedBaseBuyPrice()

    self.wndConfig:FindChild("btnDropBaseBuyPrice"):SetCheck(false)
    self.wndConfig:FindChild("BaseBuyPriceContainer"):Show(false)
end

function CommodityStats:OnSelectBuypriceStrategy( wndHandler, wndControl, eMouseButton )
    self.wndConfig:FindChild("IncreasePercentageContainer"):Show(false)
    self.wndConfig:FindChild("IncreaseFixedContainer"):Show(false)
    local buyStrategy = self.settings.buyStrategy
    local selectedButton = self.wndConfig:FindChild("BuyPriceStrategyContainer"):GetRadioSelButton("BuyPriceStrategy"):GetName()
    if selectedButton == "rboBuyPriceStrategyMatch" then buyStrategy = CommodityStats.Strategy.MATCH end
    if selectedButton == "rboBuyPriceStrategyPercentage" then
        buyStrategy = CommodityStats.Strategy.PERCENTAGE
        self.wndConfig:FindChild("IncreasePercentageContainer"):Show(true)
    end
    if selectedButton == "rboBuyPriceStrategyFixed" then
        buyStrategy = CommodityStats.Strategy.FIXED
        self.wndConfig:FindChild("IncreaseFixedContainer"):Show(true)
    end

    self.settings.buyStrategy = buyStrategy
end

function CommodityStats:btnSaveBuyIncreasePercentage( wndHandler, wndControl, eMouseButton )
    local input = tonumber(self.wndConfig:FindChild("txtIncreasePercentage"):GetText())
    if input ~= nil then
        if input >= 0 and input <= 100 then
            self.settings.buyIncreasePercentage = input
            self:ShowMessage({L["Value successfully saved"]})
            return
        end
    end
    self:ShowMessage( { L["Input not valid, percentage not saved"], L["Please enter a numeric value between 0 and 100"] })
end

function CommodityStats:btnSaveBuyIncreaseFixed( wndHandler, wndControl, eMouseButton )
    local input = self.wndConfig:FindChild("monBuyIncreaseFixed"):GetAmount()
    self.settings.buyIncreaseFixed = input
    self:ShowMessage({L["Value successfully saved"]})
end

function CommodityStats:OnChangeAutoQuantity( wndHandler, wndControl, eMouseButton )
    self.settings.autoQuantity = wndControl:IsChecked()
end


local CommodityStatsInst = CommodityStats:new()
CommodityStatsInst:Init()