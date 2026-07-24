local ADDON_NAME = ...

-- WoW addons cannot open sockets or write arbitrary files.  This addon therefore
-- exposes live data to other addons through _G.JustACBridge, and exposes data to
-- desktop programs through the JustACBridgeExport SavedVariables table.  The
-- game writes that table to disk on logout or /reload (/jacb flush).

-- Sample once per rendered frame for minimum bridge latency. JustAC applies its
-- own 30/50 ms safety throttle internally, so most calls return its cached table.
local UPDATE_INTERVAL = 0
local ROW_COUNT = 2
local QUEUE_SCAN_COUNT = 8
local PIXEL_PROTOCOL_VERSION = 2
local PIXEL_BYTE_COUNT = 72
local PIXEL_BIT_COUNT = PIXEL_BYTE_COUNT * 8
local PIXEL_COLUMNS = 48
local PIXEL_ROWS = 12
local PIXEL_CELL_SIZE = 3
local HOTKEY_BYTES = 24

JustACBridgeDB = JustACBridgeDB or {}
JustACBridgeExport = JustACBridgeExport or {}

local SpellQueue
local ActionBarScanner
local BlizzardAPI
local BurstInjectionEngine
local JustACAddon
local bridgeFrame
local rows = {}
local exportBox
local statusText
local pixelFrame
local pixelCells = {}
local elapsed = 0
local sequence = tonumber(JustACBridgeExport.sequence) or 0
local lastSignature
local currentRows = {}
local playerIsChanneling = false
local playerIsCasting = false
local reservedSpellIDs = {}
local currentSpecKey

-- Only major burst activators/sequencing skills are reserved by default.
-- Short rotational cooldowns intentionally stay available in reserve mode:
-- Frozen Orb is used on cooldown in TWW S3 Frost, and Meteor is not forced
-- into Combustion in TWW S3 Fire.
local DEFAULT_RESERVED_SPELLS = {
    MAGE_1 = { 365350, 12051, 321507 },                  -- Arcane Surge, Evocation, Touch of the Magi
    MAGE_2 = { 190319 },                                -- Combustion
    MAGE_3 = { 12472 },                                 -- Icy Veins
    DEATHKNIGHT_1 = { 49028 },                          -- Dancing Rune Weapon
    DEATHKNIGHT_2 = { 51271, 152279, 47568, 279302, 439843 }, -- Pillar, Breath, ERW, Frostwyrm, Reaper's Mark
    DEATHKNIGHT_3 = { 63560, 42650, 275699, 207289, 49206, 390279 }, -- DT, Army, Apocalypse, UA, Gargoyle, Vile Contagion
}
local getSpellData

local PAD_ATLAS_TO_KEY = {
    Gamepad_Gen_1_64 = "PAD1",
    Gamepad_Gen_2_64 = "PAD2",
    Gamepad_Gen_3_64 = "PAD3",
    Gamepad_Gen_4_64 = "PAD4",
    Gamepad_Gen_5_64 = "PAD5",
    Gamepad_Gen_6_64 = "PAD6",
    Gamepad_Ltr_A_64 = "PAD1",
    Gamepad_Ltr_B_64 = "PAD2",
    Gamepad_Ltr_X_64 = "PAD3",
    Gamepad_Ltr_Y_64 = "PAD4",
    Gamepad_Shp_Cross_64 = "PAD1",
    Gamepad_Shp_Circle_64 = "PAD2",
    Gamepad_Shp_Square_64 = "PAD3",
    Gamepad_Shp_Triangle_64 = "PAD4",
    Gamepad_Shp_MicMute_64 = "PAD5",
    Gamepad_Shp_TouchpadR_64 = "PAD6",
}

local function copyTable(source)
    if not source then
        return nil
    end

    local result = {}
    for key, value in pairs(source) do
        result[key] = value
    end
    return result
end

local function getSpecKey()
    local _, classFile = UnitClass("player")
    local spec = GetSpecialization and GetSpecialization()
    if not classFile or not spec then
        return nil
    end
    return classFile .. "_" .. tostring(spec)
end

local function addReservedSpell(spellID)
    spellID = tonumber(spellID)
    if not spellID or spellID <= 0 then
        return
    end

    reservedSpellIDs[spellID] = true
    if BlizzardAPI and BlizzardAPI.GetDisplaySpellID then
        local ok, displayID = pcall(BlizzardAPI.GetDisplaySpellID, spellID)
        if ok and type(displayID) == "number" and displayID > 0 then
            reservedSpellIDs[displayID] = true
        end
    end
end

local function removeReservedSpell(spellID)
    spellID = tonumber(spellID)
    if not spellID or spellID <= 0 then
        return
    end
    reservedSpellIDs[spellID] = nil
    if BlizzardAPI and BlizzardAPI.GetDisplaySpellID then
        local ok, displayID = pcall(BlizzardAPI.GetDisplaySpellID, spellID)
        if ok and type(displayID) == "number" and displayID > 0 then
            reservedSpellIDs[displayID] = nil
        end
    end
end

local function refreshReservedSpells()
    reservedSpellIDs = {}
    currentSpecKey = getSpecKey()
    if not currentSpecKey then
        return
    end

    for _, spellID in ipairs(DEFAULT_RESERVED_SPELLS[currentSpecKey] or {}) do
        addReservedSpell(spellID)
    end

    -- Follow JustAC's current per-spec trigger configuration. This keeps the
    -- bridge aligned with future JustAC DK/Mage defaults without rebuilding an
    -- APL in this low-latency transport addon.
    if BurstInjectionEngine and BurstInjectionEngine.GetDetectedTriggers and JustACAddon then
        local ok, triggers = pcall(BurstInjectionEngine.GetDetectedTriggers, JustACAddon)
        if ok and type(triggers) == "table" then
            for _, trigger in ipairs(triggers) do
                addReservedSpell(type(trigger) == "table" and trigger.spellID or trigger)
            end
        end
    end

    JustACBridgeDB.reserveOverrides = JustACBridgeDB.reserveOverrides or {}
    local overrides = JustACBridgeDB.reserveOverrides[currentSpecKey]
    if overrides then
        for spellID, enabled in pairs(overrides.include or {}) do
            if enabled then
                addReservedSpell(spellID)
            end
        end
        for spellID, excluded in pairs(overrides.exclude or {}) do
            if excluded then
                removeReservedSpell(spellID)
            end
        end
    end
end

local function isReservedQueueValue(queueValue)
    if type(queueValue) ~= "number" or queueValue == 0 then
        return false
    end
    -- Items in an offensive queue are normally potions/on-use trinkets. Keep
    -- all of them for the player's chosen burst window in reserve mode.
    return queueValue < 0 or reservedSpellIDs[queueValue] == true
end

local function isUsableNow(spellID)
    if not BlizzardAPI or not BlizzardAPI.IsSpellUsable then
        return true
    end

    -- JustAC positions 2+ may include ready-but-resource-starved or cooldown
    -- entries for display purposes. Never replace a reserved cooldown with an
    -- action JustAC already knows cannot be cast right now.
    local ok, isUsable = pcall(BlizzardAPI.IsSpellUsable, spellID)
    return not ok or isUsable ~= false
end

local function findReserveRecommendation(queue, startIndex)
    local count = math.min(#queue, QUEUE_SCAN_COUNT)
    for index = startIndex or 1, count do
        local queueValue = queue[index]
        if type(queueValue) == "number" and queueValue > 0
            and not isReservedQueueValue(queueValue) and isUsableNow(queueValue) then
            local data = getSpellData(queueValue, 2)
            if data and data.plainHotkey ~= "" then
                return data
            end
        end
    end

    if type(queue[1]) ~= "number" or queue[1] == 0 then
        return nil
    end

    -- Highlight mode can expose the next valid Blizzard recommendation when
    -- the primary button is hidden/blacklisted. Use it only as a bounded
    -- fallback; the normal hot path above remains a table scan.
    if BlizzardAPI and BlizzardAPI.GetHighlightCastSpell then
        local ok, spellID = pcall(BlizzardAPI.GetHighlightCastSpell)
        if ok and type(spellID) == "number" and spellID > 0
            and spellID ~= queue[1] and not isReservedQueueValue(spellID)
            and isUsableNow(spellID) then
            local data = getSpellData(spellID, 2)
            if data and data.plainHotkey ~= "" then
                return data
            end
        end
    end

    return nil
end

local function toPlainHotkey(hotkey)
    if not hotkey or hotkey == "" then
        return ""
    end

    return (hotkey:gsub("|A:([^:]+):.-|a", function(atlas)
        return PAD_ATLAS_TO_KEY[atlas] or ("[" .. atlas .. "]")
    end))
end

getSpellData = function(queueValue, position)
    if type(queueValue) ~= "number" or queueValue == 0 then
        return nil
    end

    local data = {
        position = position,
        queueValue = queueValue,
        kind = queueValue < 0 and "item" or "spell",
        spellID = nil,
        itemID = nil,
        name = "Unknown",
        icon = 134400,
        hotkey = "",
        plainHotkey = "",
    }

    if queueValue < 0 then
        local itemID = -queueValue
        data.itemID = itemID

        if C_Item then
            if C_Item.GetItemNameByID then
                data.name = C_Item.GetItemNameByID(itemID) or data.name
            end
            if C_Item.GetItemIconByID then
                data.icon = C_Item.GetItemIconByID(itemID) or data.icon
            end
        elseif GetItemInfo then
            local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemID)
            data.name = name or data.name
            data.icon = icon or data.icon
        end

        if ActionBarScanner and ActionBarScanner.GetItemHotkey then
            data.hotkey = ActionBarScanner.GetItemHotkey(itemID) or ""
        end
    else
        data.spellID = queueValue

        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(queueValue)
        if info then
            data.name = info.name or data.name
            data.icon = info.iconID or data.icon
        end

        if ActionBarScanner and ActionBarScanner.GetSpellHotkey then
            data.hotkey = ActionBarScanner.GetSpellHotkey(queueValue) or ""
        end
    end

    data.plainHotkey = toPlainHotkey(data.hotkey)
    return data
end

local function makeSignature(dataRows)
    local parts = {}
    for index = 1, ROW_COUNT do
        local data = dataRows[index]
        if data then
            parts[index] = table.concat({
                data.kind,
                tostring(data.queueValue),
                data.hotkey,
                data.name,
            }, "\031")
        else
            parts[index] = "-"
        end
    end
    parts[ROW_COUNT + 1] = playerIsChanneling and "channeling" or "not-channeling"
    parts[ROW_COUNT + 2] = playerIsCasting and "casting" or "not-casting"
    return table.concat(parts, "\030")
end

local function makeExternalLine(first)
    if not first then
        return table.concat({
            "JACB1",
            tostring(sequence),
            tostring(time()),
            "none",
            "0",
            "",
            "",
        }, "\t")
    end

    return table.concat({
        "JACB1",
        tostring(sequence),
        tostring(time()),
        first.kind,
        tostring(first.spellID or first.itemID or 0),
        first.plainHotkey ~= "" and first.plainHotkey or "UNBOUND",
        ((first.name or "Unknown"):gsub("[\t\r\n]", " ")),
    }, "\t")
end

local function putU24(bytes, offset, value)
    value = math.max(0, math.floor(tonumber(value) or 0)) % 16777216
    bytes[offset] = value % 256
    bytes[offset + 1] = math.floor(value / 256) % 256
    bytes[offset + 2] = math.floor(value / 65536) % 256
end

local function putFixedString(bytes, lengthOffset, dataOffset, value)
    value = tostring(value or "")
    local length = math.min(#value, HOTKEY_BYTES)
    bytes[lengthOffset] = length

    for index = 1, HOTKEY_BYTES do
        bytes[dataOffset + index - 1] = index <= length and string.byte(value, index) or 0
    end
end

-- Encodes both recommendations into a 48x12 monochrome bit matrix (72 bytes).
-- Binary black/white cells survive WoW's color-space conversion, HDR tonemapping,
-- and screen-capture gamma changes much better than byte-exact RGB colors.
local function updatePixelProtocol(dataRows)
    if not pixelFrame then
        return
    end

    local bytes = {}
    for index = 1, PIXEL_BYTE_COUNT do
        bytes[index] = 0
    end

    -- Header: ASCII "JAC", protocol version, 16-bit change sequence, flags.
    bytes[1], bytes[2], bytes[3] = 74, 65, 67
    bytes[4] = PIXEL_PROTOCOL_VERSION
    bytes[5] = sequence % 256
    bytes[6] = math.floor(sequence / 256) % 256

    local first = dataRows[1]
    local second = dataRows[2]
    local flags = 0
    if first then flags = flags + 1 end
    if first and first.kind == "item" then flags = flags + 2 end
    if first and first.plainHotkey ~= "" then flags = flags + 4 end
    if second then flags = flags + 8 end
    if second and second.kind == "item" then flags = flags + 16 end
    if second and second.plainHotkey ~= "" then flags = flags + 32 end
    if playerIsChanneling then flags = flags + 64 end
    if playerIsCasting then flags = flags + 128 end
    bytes[7] = flags

    -- Bytes 8..35: first ID and up to 24 hotkey bytes.
    putU24(bytes, 8, first and (first.spellID or first.itemID) or 0)
    putFixedString(bytes, 11, 12, first and first.plainHotkey or "")

    -- Bytes 36..63: second ID and up to 24 hotkey bytes.
    putU24(bytes, 36, second and (second.spellID or second.itemID) or 0)
    putFixedString(bytes, 39, 40, second and second.plainHotkey or "")

    -- 24-bit game tick in milliseconds helps readers reject stale captures.
    putU24(bytes, 64, math.floor(GetTime() * 1000))

    -- Fletcher-style checks plus an independent rolling byte checksum.
    local sum1, sum2, rolling = 0, 0, 0
    for index = 1, 66 do
        sum1 = (sum1 + bytes[index]) % 255
        sum2 = (sum2 + sum1) % 255
        rolling = (rolling * 33 + bytes[index]) % 256
    end
    bytes[67], bytes[68], bytes[69] = sum1, sum2, rolling
    bytes[70], bytes[71], bytes[72] = 69, 78, 68 -- ASCII "END"

    for bitIndex = 1, PIXEL_BIT_COUNT do
        local byteIndex = math.floor((bitIndex - 1) / 8) + 1
        local bitOffset = 7 - ((bitIndex - 1) % 8)
        local bitValue = math.floor(bytes[byteIndex] / (2 ^ bitOffset)) % 2
        pixelCells[bitIndex]:SetColorTexture(bitValue, bitValue, bitValue, 1)
    end
end

local function updatePixelGeometry()
    if not pixelFrame then
        return
    end

    -- Convert physical pixels to WoW UI units so the reader always sees a
    -- 144x36 matrix at client-area coordinate (2, 2). Multiplication is required
    -- here because the rendered client surface maps UI units inversely through
    -- UIParent's effective scale (including Windows DPI composition).
    local scale = UIParent:GetEffectiveScale()
    if not scale or scale <= 0 then
        scale = 1
    end
    local cellSize = PIXEL_CELL_SIZE * scale

    pixelFrame:ClearAllPoints()
    pixelFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 2 * scale, -2 * scale)
    pixelFrame:SetSize(PIXEL_COLUMNS * cellSize, PIXEL_ROWS * cellSize)

    for index = 1, PIXEL_BIT_COUNT do
        local cell = pixelCells[index]
        if cell then
            local zeroIndex = index - 1
            local column = zeroIndex % PIXEL_COLUMNS
            local row = math.floor(zeroIndex / PIXEL_COLUMNS)
            cell:ClearAllPoints()
            cell:SetSize(cellSize, cellSize)
            cell:SetPoint("TOPLEFT", pixelFrame, "TOPLEFT", column * cellSize, -row * cellSize)
        end
    end
end

local function updateSavedExport(dataRows)
    sequence = sequence + 1

    JustACBridgeExport = JustACBridgeExport or {}
    JustACBridgeExport.schemaVersion = PIXEL_PROTOCOL_VERSION
    JustACBridgeExport.sequence = sequence
    JustACBridgeExport.updatedAt = time()
    JustACBridgeExport.updatedAtGame = GetTime()
    JustACBridgeExport.addon = ADDON_NAME
    JustACBridgeExport.isChanneling = playerIsChanneling
    JustACBridgeExport.isCasting = playerIsCasting
    JustACBridgeExport.playerState = playerIsChanneling and "channeling"
        or (playerIsCasting and "casting" or "idle")
    JustACBridgeExport.first = copyTable(dataRows[1])
    JustACBridgeExport.lossless = copyTable(dataRows[1])
    JustACBridgeExport.reserveBurst = copyTable(dataRows[2])
    JustACBridgeExport.rows = {}

    for index = 1, ROW_COUNT do
        JustACBridgeExport.rows[index] = copyTable(dataRows[index])
    end

    JustACBridgeExport.line = makeExternalLine(dataRows[1])
    updatePixelProtocol(dataRows)
end

local function updateUI(dataRows)
    if not bridgeFrame then
        return
    end

    for index = 1, ROW_COUNT do
        local row = rows[index]
        local data = dataRows[index]

        if data then
            row.icon:SetTexture(data.icon)
            row.icon:SetDesaturated(false)
            row.name:SetText(data.name)
            row.id:SetText(data.kind == "item"
                and ("物品 " .. tostring(data.itemID))
                or ("法术 " .. tostring(data.spellID)))
            row.hotkey:SetText(data.hotkey ~= "" and data.hotkey or "未绑定")
            if data.hotkey ~= "" then
                row.hotkey:SetTextColor(1, 0.82, 0)
            else
                row.hotkey:SetTextColor(1, 0.25, 0.25)
            end
        else
            row.icon:SetTexture(134400)
            row.icon:SetDesaturated(true)
            row.name:SetText("暂无推荐")
            row.id:SetText("-")
            row.hotkey:SetText("-")
            row.hotkey:SetTextColor(0.55, 0.55, 0.55)
        end
    end

    if exportBox then
        exportBox:SetText(JustACBridgeExport.line or "")
        exportBox:SetCursorPosition(0)
        exportBox:ClearFocus()
    end

    if statusText then
        local castState = playerIsChanneling and " · 持续引导中"
            or (playerIsCasting and " · 施法中" or "")
        statusText:SetText(dataRows[1]
            and ("实时内存接口已更新 · 序号 " .. sequence .. castState)
            or ("等待 JustAC 推荐队列" .. castState))
    end
end

local function refresh()
    if not SpellQueue or not SpellQueue.GetCurrentSpellQueue then
        return false, "JustAC-SpellQueue unavailable"
    end

    local ok, queue = pcall(SpellQueue.GetCurrentSpellQueue)
    if not ok or type(queue) ~= "table" then
        return false, ok and "Invalid JustAC queue" or tostring(queue)
    end

    local lossless = getSpellData(queue[1], 1)
    local preserve
    if lossless and lossless.plainHotkey ~= "" and not isReservedQueueValue(lossless.queueValue) then
        preserve = copyTable(lossless)
        preserve.position = 2
    else
        preserve = findReserveRecommendation(queue, lossless and 2 or 1)
    end
    local nextRows = { lossless, preserve }

    local signature = makeSignature(nextRows)
    if signature == lastSignature then
        return true
    end

    lastSignature = signature
    currentRows = nextRows
    updateSavedExport(currentRows)
    updateUI(currentRows)
    return true
end

local function savePosition()
    if not bridgeFrame then
        return
    end

    local point, _, relativePoint, x, y = bridgeFrame:GetPoint(1)
    JustACBridgeDB.point = point
    JustACBridgeDB.relativePoint = relativePoint
    JustACBridgeDB.x = x
    JustACBridgeDB.y = y
end

local function createRow(parent, index, topOffset)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", 12, topOffset)
    row:SetPoint("TOPRIGHT", -12, topOffset)
    row:SetHeight(42)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(36, 36)
    row.icon:SetPoint("LEFT", 2, 0)
    row.icon:SetTexture(134400)

    row.rank = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.rank:SetPoint("TOPLEFT", row.icon, "TOPLEFT", 2, -2)
    row.rank:SetText(tostring(index))

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 9, -2)
    row.name:SetPoint("RIGHT", -92, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetText("暂无推荐")

    row.id = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.id:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 9, 2)
    row.id:SetText("-")

    row.hotkey = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    row.hotkey:SetPoint("RIGHT", -4, 0)
    row.hotkey:SetWidth(82)
    row.hotkey:SetJustifyH("RIGHT")
    row.hotkey:SetText("-")

    local divider = row:CreateTexture(nil, "BACKGROUND")
    divider:SetColorTexture(1, 1, 1, 0.08)
    divider:SetPoint("BOTTOMLEFT", 0, 0)
    divider:SetPoint("BOTTOMRIGHT", 0, 0)
    divider:SetHeight(1)

    return row
end

local function createUI()
    bridgeFrame = CreateFrame("Frame", "JustACBridgeFrame", UIParent, "BackdropTemplate")
    bridgeFrame:SetSize(380, 166)
    bridgeFrame:SetFrameStrata("MEDIUM")
    bridgeFrame:SetClampedToScreen(true)
    bridgeFrame:SetMovable(true)
    bridgeFrame:EnableMouse(true)
    bridgeFrame:RegisterForDrag("LeftButton")
    bridgeFrame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    bridgeFrame:SetBackdropColor(0.025, 0.025, 0.035, 0.94)
    bridgeFrame:SetBackdropBorderColor(0.25, 0.65, 1, 0.85)

    bridgeFrame:SetScript("OnDragStart", function(self)
        if not JustACBridgeDB.locked then
            self:StartMoving()
        end
    end)
    bridgeFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition()
    end)

    local title = bridgeFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOPLEFT", 13, -10)
    title:SetText("JustACBridge · 推荐快捷键")

    local close = CreateFrame("Button", nil, bridgeFrame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 1, 1)
    close:SetSize(28, 28)
    close:SetScript("OnClick", function()
        JustACBridgeDB.visible = false
        bridgeFrame:Hide()
    end)

    rows[1] = createRow(bridgeFrame, 1, -30)
    rows[2] = createRow(bridgeFrame, 2, -73)
    rows[1].rank:SetText("全")
    rows[2].rank:SetText("留")

    exportBox = CreateFrame("EditBox", nil, bridgeFrame, "InputBoxTemplate")
    exportBox:SetAutoFocus(false)
    exportBox:SetFontObject("GameFontHighlightSmall")
    exportBox:SetPoint("BOTTOMLEFT", 13, 24)
    exportBox:SetPoint("BOTTOMRIGHT", -13, 24)
    exportBox:SetHeight(20)
    exportBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    exportBox:SetScript("OnMouseUp", function(self)
        self:SetFocus()
        self:HighlightText()
    end)
    exportBox:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
    end)
    exportBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText((JustACBridgeExport and JustACBridgeExport.line) or "")
            self:HighlightText()
        end
    end)

    statusText = bridgeFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    statusText:SetPoint("BOTTOMLEFT", 14, 9)
    statusText:SetText("等待 JustAC 推荐队列")

    bridgeFrame:ClearAllPoints()
    bridgeFrame:SetPoint(
        JustACBridgeDB.point or "CENTER",
        UIParent,
        JustACBridgeDB.relativePoint or "CENTER",
        JustACBridgeDB.x or 0,
        JustACBridgeDB.y or 120
    )

    if JustACBridgeDB.visible == false then
        bridgeFrame:Hide()
    end

    -- Dedicated screen-capture transport. It remains independent from the
    -- normal panel so hiding the panel does not interrupt an external reader.
    pixelFrame = CreateFrame("Frame", "JustACBridgePixelFrame", UIParent)
    pixelFrame:SetFrameStrata("TOOLTIP")
    pixelFrame:SetFrameLevel(10000)
    pixelFrame:EnableMouse(false)

    for index = 1, PIXEL_BIT_COUNT do
        local cell = pixelFrame:CreateTexture(nil, "OVERLAY")
        cell:SetColorTexture(0, 0, 0, 1)
        pixelCells[index] = cell
    end

    updatePixelGeometry()

    if JustACBridgeDB.pixelVisible == false then
        pixelFrame:Hide()
    end

    updatePixelProtocol(currentRows)
end

local API = _G.JustACBridge or {}
_G.JustACBridge = API

function API.GetCurrentHotkey()
    local first = currentRows[1]
    return first and first.plainHotkey or nil
end

function API.GetCurrentRecommendation()
    return copyTable(currentRows[1])
end

function API.GetLosslessRecommendation()
    return copyTable(currentRows[1])
end

function API.GetPreserveBurstRecommendation()
    return copyTable(currentRows[2])
end

function API.GetRecommendations()
    local result = {}
    for index = 1, ROW_COUNT do
        result[index] = copyTable(currentRows[index])
    end
    return result
end

function API.GetExternalLine()
    return JustACBridgeExport and JustACBridgeExport.line or nil
end

function API.IsPlayerChanneling()
    return playerIsChanneling
end

function API.IsPlayerCasting()
    return playerIsCasting
end

function API.GetPlayerCastState()
    return {
        isChanneling = playerIsChanneling,
        isCasting = playerIsCasting,
    }
end

function API.Refresh()
    return refresh()
end

function API.Show()
    JustACBridgeDB.visible = true
    if bridgeFrame then
        bridgeFrame:Show()
        updateUI(currentRows)
    end
end

function API.Hide()
    JustACBridgeDB.visible = false
    if bridgeFrame then
        bridgeFrame:Hide()
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
eventFrame:RegisterEvent("UI_SCALE_CHANGED")
eventFrame:RegisterEvent("DISPLAY_SIZE_CHANGED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_START", "player")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_STOP", "player")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED_QUIET", "player")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        JustACBridgeDB = JustACBridgeDB or {}
        if JustACBridgeDB.visible == nil then
            JustACBridgeDB.visible = true
        end
        if JustACBridgeDB.locked == nil then
            JustACBridgeDB.locked = false
        end
        if JustACBridgeDB.pixelVisible == nil then
            JustACBridgeDB.pixelVisible = true
        end

        SpellQueue = LibStub("JustAC-SpellQueue", true)
        ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)
        BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
        BurstInjectionEngine = LibStub("JustAC-BurstInjectionEngine", true)
        JustACAddon = LibStub("AceAddon-3.0"):GetAddon("JustAssistedCombat", true)
        refreshReservedSpells()
        createUI()

        if not SpellQueue then
            statusText:SetText("错误：找不到 JustAC-SpellQueue")
            statusText:SetTextColor(1, 0.2, 0.2)
            return
        end

        refresh()
    elseif event == "PLAYER_LOGOUT" then
        savePosition()
        refresh()
    elseif event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
        C_Timer.After(0, updatePixelGeometry)
    elseif event == "PLAYER_ENTERING_WORLD" then
        playerIsChanneling = false
        playerIsCasting = false
        lastSignature = nil
        refreshReservedSpells()
    elseif event == "PLAYER_SPECIALIZATION_CHANGED"
        or event == "PLAYER_TALENT_UPDATE"
        or event == "TRAIT_CONFIG_UPDATED" then
        refreshReservedSpells()
        lastSignature = nil
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        playerIsChanneling = true
        playerIsCasting = false
        lastSignature = nil
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        playerIsChanneling = false
        lastSignature = nil
    elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_EMPOWER_START" then
        playerIsCasting = true
        playerIsChanneling = false
        lastSignature = nil
    elseif event == "UNIT_SPELLCAST_STOP"
        or event == "UNIT_SPELLCAST_EMPOWER_STOP"
        or event == "UNIT_SPELLCAST_FAILED"
        or event == "UNIT_SPELLCAST_FAILED_QUIET"
        or event == "UNIT_SPELLCAST_INTERRUPTED" then
        playerIsCasting = false
        lastSignature = nil
    end
end)

eventFrame:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + delta
    if UPDATE_INTERVAL > 0 and elapsed < UPDATE_INTERVAL then
        return
    end
    elapsed = 0
    refresh()
end)

SLASH_JUSTACBRIDGE1 = "/jacb"
SLASH_JUSTACBRIDGE2 = "/justacbridge"
SlashCmdList.JUSTACBRIDGE = function(message)
    local command = (message or ""):lower():match("^%s*(.-)%s*$")
    local reserveAction, reserveID = command:match("^reserve%s+(%a+)%s+(%d+)$")
    if reserveAction ~= "add" and reserveAction ~= "remove" then
        reserveAction, reserveID = nil, nil
    end

    if reserveAction and reserveID then
        currentSpecKey = getSpecKey()
        local spellID = tonumber(reserveID)
        if not currentSpecKey or not spellID then
            print("|cffff4040JustACBridge:|r 当前专精或法术 ID 无效。")
            return
        end
        JustACBridgeDB.reserveOverrides = JustACBridgeDB.reserveOverrides or {}
        local overrides = JustACBridgeDB.reserveOverrides[currentSpecKey] or { include = {}, exclude = {} }
        overrides.include = overrides.include or {}
        overrides.exclude = overrides.exclude or {}
        JustACBridgeDB.reserveOverrides[currentSpecKey] = overrides
        if reserveAction == "add" then
            overrides.include[spellID] = true
            overrides.exclude[spellID] = nil
        else
            overrides.include[spellID] = nil
            overrides.exclude[spellID] = true
        end
        refreshReservedSpells()
        lastSignature = nil
        print(("|cff40a9ffJustACBridge:|r %s保留法术 %d（%s）。")
            :format(reserveAction == "add" and "已添加" or "已移除", spellID, currentSpecKey))
    elseif command == "reserve reset" then
        currentSpecKey = getSpecKey()
        if currentSpecKey and JustACBridgeDB.reserveOverrides then
            JustACBridgeDB.reserveOverrides[currentSpecKey] = nil
        end
        refreshReservedSpells()
        lastSignature = nil
        print("|cff40a9ffJustACBridge:|r 当前专精保留法术已恢复默认。")
    elseif command == "reserve list" then
        local ids = {}
        for spellID in pairs(reservedSpellIDs) do
            ids[#ids + 1] = spellID
        end
        table.sort(ids)
        print(("|cff40a9ffJustACBridge:|r 保留法术（%s）：%s")
            :format(currentSpecKey or "unknown", #ids > 0 and table.concat(ids, ", ") or "无"))
    elseif command == "show" then
        API.Show()
    elseif command == "hide" then
        API.Hide()
    elseif command == "lock" then
        JustACBridgeDB.locked = true
        print("|cff40a9ffJustACBridge:|r 面板已锁定。")
    elseif command == "unlock" then
        JustACBridgeDB.locked = false
        print("|cff40a9ffJustACBridge:|r 面板已解锁，可用鼠标左键拖动。")
    elseif command == "refresh" then
        refreshReservedSpells()
        lastSignature = nil
        local ok, err = refresh()
        print(ok and "|cff40a9ffJustACBridge:|r 已刷新。" or ("|cffff4040JustACBridge:|r " .. tostring(err)))
    elseif command == "flush" then
        print("|cff40a9ffJustACBridge:|r 正在重载界面并把 SavedVariables 写入磁盘……")
        C_Timer.After(0, ReloadUI)
    elseif command == "pixels" or command == "pixels on" or command == "pixels off" then
        if command == "pixels on" then
            JustACBridgeDB.pixelVisible = true
        elseif command == "pixels off" then
            JustACBridgeDB.pixelVisible = false
        else
            JustACBridgeDB.pixelVisible = not JustACBridgeDB.pixelVisible
        end
        if pixelFrame then
            pixelFrame:SetShown(JustACBridgeDB.pixelVisible)
        end
        print(JustACBridgeDB.pixelVisible
            and "|cff40a9ffJustACBridge:|r 实时像素接口已开启。"
            or "|cff40a9ffJustACBridge:|r 实时像素接口已关闭。")
    elseif command == "" or command == "toggle" then
        if bridgeFrame and bridgeFrame:IsShown() then
            API.Hide()
        else
            API.Show()
        end
    else
        print("|cff40a9ffJustACBridge 命令：|r")
        print("/jacb - 显示/隐藏面板")
        print("/jacb lock | unlock - 锁定/解锁面板")
        print("/jacb refresh - 立即刷新")
        print("/jacb pixels [on|off] - 控制实时像素接口")
        print("/jacb reserve list - 查看当前专精保留法术")
        print("/jacb reserve add <法术ID> | remove <法术ID> | reset")
        print("/jacb flush - 重载 UI 并将导出数据写入磁盘")
    end
end
