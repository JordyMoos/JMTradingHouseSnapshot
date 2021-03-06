
---
--- JMTradingHouseSnapshot
---

--[[

    Variable declaration

 ]]


JM_DEBUG2 = {
    load_list = {},
}

---
-- @field name
-- @field savedVariablesName
--
local Config = {
    version = '1.3',
    author = 'Jordy Moos',

    name = 'JMTradingHouseSnapshot',
    savedVariablesName = 'JMTradingHouseSnapshotSavedVariables',
}

JM_DEBUG2.config = Config

---
-- We can not do anything for other addons
-- while we are not fully loaded
--
local addonLoaded = false

---
-- Event manager
--
local EventManager = ZO_CallbackObject:New()

---
-- List of possible events
--
local Events = {
    SCAN_STARTED = 'JMTradingHouseSnapshot_Scan_Started',
    SCAN_SUCCEEDED = 'JMTradingHouseSnapshot_Scan_Succeeded',
    SCAN_FAILED = 'JMTradingHouseSnapshot_Scan_Failed',
    SCAN_ALREADY_RUNNING = 'JMTradingHouseSnapshot_Scan_Already_Running',
    ADDON_LOADED = 'JMTradingHouseSnapshot_Addon_Loaded',
}

---
-- Information about the trading house
--
-- @field isOpen
--
local TradingHouse = {
    isOpen = false,
}

---
-- @field isScanning
-- @field currentGuild
-- @field currentPage
--
local Scanner = {
    isScanning = false,
    currentGuild = 0,
    currentPage = 0,

    -- Scanning direction etc
    -- These values are indicational, they will be overwritten
    orderOn = TRADING_HOUSE_SORT_SALE_PRICE,
    orderAsc = true,
    minimumTimeLeft = nil,
}

---
-- @field tradingHouseList
-- @field creationTimestamp
--
local snapshotData = {
    tradingHouseList = {},
    lastChangeTimestamp = nil,
}
local currentGuildSnapshot = {}

local guildList = {}

local savedVariables = {

}

---
-- @field mainWindow
-- @field scanButton
-- @field quickScanButton
-- @field abortButton
-- @field leftLabel
-- @field rightLabel
--
local Gui = {
    mainWindow = JMTradingHouseSnapshotGuiMainWindow,
    scanButton = JMTradingHouseSnapshotGuiMainWindowScanButton,
    quickScanButton = JMTradingHouseSnapshotGuiMainWindowQuickScanButton,
    abortButton = JMTradingHouseSnapshotGuiMainWindowAbortButton,
    leftLabel = JMTradingHouseSnapshotGuiMainWindowStatusAction,
    rightLabel = JMTradingHouseSnapshotGuiMainWindowStatusDetail,
}

--[[

    Utility functions

 ]]

local Util = {}

---
-- @param obj
-- @param seen
--
function Util.copyTable(obj, seen)
    -- Handle non-tables and previously-seen tables.
    if type(obj) ~= 'table' then return obj end
    if seen and seen[obj] then return seen[obj] end

    -- New table; mark it as seen an copy recursively.
    local s = seen or {}
    local res = setmetatable({}, getmetatable(obj))
    s[obj] = res
    for k, v in pairs(obj) do res[Util.copyTable(k, s)] = Util.copyTable(v, s) end
    return res
end

--[[

    Trading house

 ]]

---
--
function TradingHouse:opened()
    self.isOpen = true
end

---
--
function TradingHouse:closed()
    self.isOpen = false
    Scanner:abort()
    Gui.mainWindow:SetHidden(true)
end

--[[

    Scanner

 ]]

---
--
function Scanner:startScanning(orderOn, orderAsc, minimumTimeLeft)
    if self.isScanning then
        d('Already scanning')
        EventManager:FireCallbacks(Events.SCAN_ALREADY_RUNNING)
        return
    end

    Gui.leftLabel:SetText('Starting..')

    -- Set scanning configuration
    self.orderOn = orderOn
    self.orderAsc = orderAsc
    self.minimumTimeLeft = minimumTimeLeft

    self.isScanning = true
    self.currentGuild = 0
    self.currentPage = 0

    Gui.scanButton:SetEnabled(false)
    Gui.quickScanButton:SetEnabled(false)
    Gui.abortButton:SetEnabled(true)

    self.prepareSnapshotData()

    ClearAllTradingHouseSearchTerms()

    EventManager:FireCallbacks(Events.SCAN_STARTED)
    self:scanGuild(1)
end

---
--
function Scanner:abort()
    if not Scanner.isScanning then
        return
    end

    Gui.leftLabel:SetText('Aborted..')

    -- Stop the async scanning process
    Scanner.isScanning = false

    -- Disable/enable the buttons
    Gui.scanButton:SetEnabled(true)
    Gui.quickScanButton:SetEnabled(true)
    Gui.abortButton:SetEnabled(false)

    EventManager:FireCallbacks(Events.SCAN_FAILED)
end

---
--
function Scanner:prepareSnapshotData()
    guildList = {}
--    snapshotData = {
--        tradingHouseList = {},
--        guildList = {},
--        creationTimestamp = nil,
--    }
end

---
-- Some actions require a wait time
-- We add a little more in case it gets called too early
--
function Scanner:getWaitTime()
    return GetTradingHouseCooldownRemaining() + 50
end

---
-- @param guildId
--
function Scanner:scanGuild(guildIndex)
    Gui.leftLabel:SetText('Starting with guild index: ' .. guildIndex)

    local guildId, guildName, alianceId = GetTradingHouseGuildDetails(guildIndex)

    -- Create table for this guild
    snapshotData.tradingHouseList[guildName] = {
        scanTimestamp = nil,
        itemList = {},
    }
    currentGuildSnapshot = snapshotData.tradingHouseList[guildName]

    -- Switching of guilds also refreshed the cooldown
    zo_callLater(function()
        if not Scanner:canContinueScanning() then
            return
        end

        SelectTradingHouseGuildId(guildId)

        -- Store the guilds information
        guildList[guildId] = {
            id = guildId,
            index = guildIndex,
            name = guildName,
            alianceId = alianceId,
        }

        Scanner:scanPage(guildId, 0)
    end, self:getWaitTime())
end

---
-- @param guildId
-- @param pageNumber
--
function Scanner:scanPage(guildId, pageNumber)
    Gui.leftLabel:SetText('Requesting guild ' .. guildId .. ' page ' .. pageNumber)

    -- Execute the search when the cooldown is passed
    zo_callLater(function ()
        if not Scanner:canContinueScanning() then
            return
        end

        ExecuteTradingHouseSearch(pageNumber, self.orderOn, self.orderAsc)
    end, self:getWaitTime())
end

---
-- Should be called on every scan step so that we can abort
-- if something is wrong
--
function Scanner:canContinueScanning ()
    return TradingHouse.isOpen and Scanner.isScanning
end

---
-- @param guildId
-- @param itemCount
-- @param pageNumber
-- @param hasMorePages
--
function Scanner:searchResultReceived(guildId, itemCount, pageNumber, hasMorePages)
    if not self.canContinueScanning() then
        return
    end

    Gui.leftLabel:SetText('Scanning guild ' .. guildId .. ' page ' .. pageNumber)
    local lastTimeRemaining

    for index = 1, itemCount do
        -- Get item from the current row
        local icon, itemName, quality, stackCount, sellerName, timeRemaining, price = GetTradingHouseSearchResultItemInfo(index)
        local itemLink = GetTradingHouseSearchResultItemLink(index)
        local _, _, _, itemId = ZO_LinkHandler_ParseLink(itemLink)

        -- Insert row in the guilds snapshot
        table.insert(
            currentGuildSnapshot.itemList,
            {
                guildName  = guildList[guildId].name,
                itemId = itemId,
                itemLink = itemLink,
                sellerName = sellerName,
                quality = quality,
                stackCount = stackCount,
                price = price,
                pricePerPiece = math.ceil(price / stackCount),
                expiry = timeRemaining + GetTimeStamp(),
            }
        )

        -- Cache the time remaining to determine if we should continue the scan
        lastTimeRemaining = timeRemaining
    end

    if hasMorePages then
        -- If we do not care about the sale time then keep scanning
        if not self.minimumTimeLeft then
            return self:scanPage(guildId, pageNumber + 1)
        end

        -- If want to scan more days
        if lastTimeRemaining and lastTimeRemaining > self.minimumTimeLeft then
            return self:scanPage(guildId, pageNumber + 1)
        end
    end

    -- If nothing wanted to scan more then we stop for this guild
    return self:finishedGuild(guildId)
end

---
-- @param guildId
--
function Scanner:finishedGuild(guildId)
    Gui.leftLabel:SetText('Finishing..')

    local guildIndex = guildList[guildId].index
    local guildName = guildList[guildId].name

    currentGuildSnapshot.timestamp = GetTimeStamp()
    currentGuildSnapshot.canBuy = CanBuyFromTradingHouse(guildId)
    currentGuildSnapshot.canSell = CanSellOnTradingHouse(guildId)
    currentGuildSnapshot.listingPercentage = GetTradingHouseListingPercentage(guildId)
    currentGuildSnapshot.cutPercentage = GetTradingHouseCutPercentage(guildId)
    savedVariables.snapshot.tradingHouseList[guildName] = Util.copyTable(currentGuildSnapshot)

    -- Do next guild if we have more guilds
    if guildIndex < GetNumTradingHouseGuilds() then
        return self:scanGuild(guildIndex + 1)
    end

    -- Add creation timestamp to the snapshot
    savedVariables.snapshot.lastChangeTimestamp = GetTimeStamp()

    -- Say we are done
    Scanner.isScanning = false

    -- Disable/enable the buttons
    Gui.scanButton:SetEnabled(true)
    Gui.quickScanButton:SetEnabled(true)
    Gui.abortButton:SetEnabled(false)

    d('Finished scanning')

    -- Make a copy of the savedVariables to distribute
    -- So the listening addons can not change our savedVariables
    Gui.leftLabel:SetText('Informing other addons')
    local data = Util.copyTable(savedVariables.snapshot)
    EventManager:FireCallbacks(Events.SCAN_SUCCEEDED, data)
    Gui.leftLabel:SetText('')
end

--[[

    Gui

 ]]

function Gui.mainWindow:close()
    self:SetHidden(true)
end

--[[

    Initialize

 ]]

---
-- Start of the addon
--
local function Initialize()

    -- Button to the snapshot creation window
    local showMainWindowButton = JMTradingHouseSnapshotGuiOpenButton
    showMainWindowButton:SetParent(ZO_TradingHouseLeftPaneBrowseItemsCommon)
    showMainWindowButton:SetWidth(ZO_TradingHouseLeftPaneBrowseItemsCommonQuality:GetWidth())

    -- Disable the abort button
    Gui.abortButton:SetEnabled(false)

    -- Load the saved variables
    savedVariables = ZO_SavedVars:NewAccountWide(Config.savedVariablesName, 1, nil, {
        snapshot = {
            tradingHouseList = {},
        },
    })

    -- Store search request finished
    -- So we can now gather the items
    EVENT_MANAGER:RegisterForEvent(
        Config.name,
        EVENT_TRADING_HOUSE_SEARCH_RESULTS_RECEIVED,
        function (eventName, guildId, itemCount, pageNumber, hasMorePages)
            Scanner:searchResultReceived(guildId, itemCount, pageNumber, hasMorePages)
        end
    )

    -- Let the addon know that the trading house is open so we could make a snapshot
    EVENT_MANAGER:RegisterForEvent(
        Config.name,
        EVENT_OPEN_TRADING_HOUSE,
        function ()
            TradingHouse:opened()
        end
    )

    -- Hide the main window if you close the trading house
    EVENT_MANAGER:RegisterForEvent(
        Config.name,
        EVENT_CLOSE_TRADING_HOUSE,
        function ()
            TradingHouse:closed()
        end
    )

    -- Catch trading house errors
    EVENT_MANAGER:RegisterForEvent(
        Config.name,
        EVENT_TRADING_HOUSE_ERROR,
        function (...)
            d('Trading house error:')
            d(...)
        end
    )

    -- Say that our addon is loaded
    addonLoaded = true
    EventManager:FireCallbacks(Events.ADDON_LOADED)
end

--[[

    Events

 ]]

--- Adding the initialize handler
EVENT_MANAGER:RegisterForEvent(
    Config.name,
    EVENT_ADD_ON_LOADED,
    function (event, addonName)
        table.insert(JM_DEBUG2.load_list, addonName)
        if addonName ~= Config.name then
            return
        end

        Initialize()
--        EVENT_MANAGER:UnregisterForEvent(Config.name, EVENT_ADD_ON_LOADED)
    end
)

--[[

    Api

 ]]

---
-- Making some functions public
--
-- @field scan
--
JMTradingHouseSnapshot = {

    ---
    -- Public create snapshot function
    --
    createSnapshot = function()
        Scanner:startScanning(TRADING_HOUSE_SORT_SALE_PRICE, true, nil)
    end,

    ---
    -- Public create a quick snapshot function
    --
    createQuickSnapshot = function()
        Scanner:startScanning(TRADING_HOUSE_SORT_EXPIRY_TIME, false, (60 * 60 * 24 * 25))
    end,

    ---
    -- Return the latest snapshot
    --
    getSnapshot = function()
        if not addonLoaded then
            return false
        end

        -- We do not have a snapshot
        if not savedVariables.snapshot.lastChangeTimestamp then
            return false
        end

        -- Copy the savedVariables so he cannot change our data
        return Util.copyTable(savedVariables.snapshot)
    end,

    ---
    -- Return the latest snapshot
    --
    getByGuildAndItem = function(guildName, itemId)
        if not addonLoaded then
            return false
        end

        -- We do not have a snapshot
        if not savedVariables.snapshot.tradingHouseList[guildName] then
            return false
        end

        local itemList = {}
        for _, item in ipairs(savedVariables.snapshot.tradingHouseList[guildName].itemList) do
            if item.itemId == itemId then
                table.insert(itemList, item)
            end
        end

        -- Copy the saleList so he cannot change our data
        return Util.copyTable(itemList)
    end,

    ---
    -- Public abort function
    --
    abort = function()
        Scanner:abort()
    end,

    ---
    -- Constants of possible events
    --
    events = Events,

    ---
    -- Allow other addons to register for events
    -- See events for possible events
    --
    registerForEvent = function(eventName, callback)
        EventManager:RegisterCallback(eventName, callback)
    end,

    ---
    -- Allow other addons to cancel their registration for events
    --
    unregisterForEvent = function(eventName, callback)
        EventManager:UnregisterCallback(eventName, callback)
    end,
}
