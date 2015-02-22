
---
--- JMTradingHouseSnapshot
--- https://github.com/JordyMoos/JMTradingHouseSnapshot
---

--[[

    Variable declaration

 ]]

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
}

---
-- @field tradingHouseItemList
-- @field guildList
-- @field creationTimestamp
--
local snapshotData = {
    tradingHouseItemList = {},
    guildList = {},
    creationTimestamp = nil,
}

local savedVariables = {

}

---
-- @field mainWindow
-- @field scanButton
-- @field abortButton
-- @field leftLabel
-- @field rightLabel
--
local Gui = {
    mainWindow = JMTradingHouseSnapshotGuiMainWindow,
    scanButton = JMTradingHouseSnapshotGuiMainWindowScanButton,
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
function Scanner:startScanning()
    if self.isScanning then
        d('Already scanning')
        EventManager:FireCallbacks(Events.SCAN_ALREADY_RUNNING)
        return
    end

    Gui.leftLabel:SetText('Starting..')

    self.isScanning = true
    self.currentGuild = 0
    self.currentPage = 0

    Gui.scanButton:SetEnabled(false)
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
    Gui.abortButton:SetEnabled(false)

    EventManager:FireCallbacks(Events.SCAN_FAILED)
end

---
--
function Scanner:prepareSnapshotData()
    snapshotData = {
        tradingHouseItemList = {},
        guildList = {},
        creationTimestamp = nil,
    }
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
    snapshotData.tradingHouseItemList[guildId] = {}

    -- Switching of guilds also refreshed the cooldown
    zo_callLater(function()
        if not Scanner:canContinueScanning() then
            return
        end

        SelectTradingHouseGuildId(guildId)

        -- Store the guilds information
        snapshotData.guildList[guildId] = {
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

        ExecuteTradingHouseSearch(pageNumber, TRADING_HOUSE_SORT_SALE_PRICE, true)
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

    for index = 1, itemCount do
        -- Get item from the current row
        local icon, itemName, quality, stackCount, sellerName, timeRemaining, price = GetTradingHouseSearchResultItemInfo(index)
        local itemLink = GetTradingHouseSearchResultItemLink(index)
        local _, _, _, itemId = ZO_LinkHandler_ParseLink(itemLink)

        -- Insert row in the guilds snapshot
        table.insert(
            snapshotData.tradingHouseItemList[guildId],
            {
                -- @depriced guildId. Use guildName
                guildId = guildId,
                guildName  = snapshotData.guildList[guildId].name,
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
    end

    if hasMorePages then
        self:scanPage(guildId, pageNumber + 1)
    else
        self:finishedGuild(guildId)
    end
end

---
-- @param guildId
--
function Scanner:finishedGuild(guildId)
    Gui.leftLabel:SetText('Finishing..')

    local guildIndex = snapshotData.guildList[guildId].index

    -- Do next guild if we have more guilds
    if guildIndex < GetNumTradingHouseGuilds() then
        return self:scanGuild(guildIndex + 1)
    end

    -- Add creation timestamp to the snapshot
    snapshotData.creationTimestamp = GetTimeStamp()

    -- Store the snapshot
    savedVariables.snapshot = Util.copyTable(snapshotData)

    -- Say we are done
    Scanner.isScanning = false

    -- Disable/enable the buttons
    Gui.scanButton:SetEnabled(true)
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
        snapshot = {},
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
        if addonName ~= Config.name then
            return
        end

        Initialize()
        EVENT_MANAGER:UnregisterForEvent(Config.name, EVENT_ADD_ON_LOADED)
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
        Scanner:startScanning()
    end,

    ---
    -- Return the latest snapshot
    --
    getSnapshot = function()
        if not addonLoaded then
            return false
        end

        -- We do not have a snapshot
        if not savedVariables.snapshot.creationTimestamp then
            return false
        end

        -- Copy the savedVariables so he cannot change our data
        return Util.copyTable(savedVariables.snapshot)
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
