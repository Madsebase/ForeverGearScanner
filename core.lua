local addonName, AGS = ...

_G["ForeverGearScanner"] = AGS
local L = AGS.L or {}

AGS.Results = {}
AGS.RawResults = {}
AGS.Filters = {
    name = "",
    minLevel = 0, maxLevel = 0,
    classID = nil,      -- nil = Both Weapon & Armor, or Enum.ItemClass.Weapon / Armor
    subClassID = nil,   -- subclass ID from C_AuctionHouse.GetAuctionItemSubClasses
    invTypeFilter = "", -- INVTYPE string, e.g. "INVTYPE_HEAD"
    qualityIndex = 0,   -- 0 = Any, 1 = Poor(0), 2 = Common(1), etc.
    usableOnly = false,
    upgradesOnly = false,
    pawnScale = nil,    -- nil = Any visible Pawn spec (highest %), or ScaleName

    maxBuyout = 0,
    minDamage = 0, maxDamage = 0,
    minDPS = 0, maxDPS = 0,
    minSpeed = 0, maxSpeed = 0,
    minArmor = 0, maxArmor = 0,
    stats = {}
}

AGS.IsScanning = false
AGS.SortKey = "buyout"
AGS.SortDescending = false

-- Fallback hidden tooltip if C_TooltipInfo isn't available for an itemKey
local scanTip = CreateFrame("GameTooltip", "FGS_ScanTip", UIParent, "GameTooltipTemplate")
scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
f:RegisterEvent("AUCTION_HOUSE_SHOW")
f:RegisterEvent("AUCTION_HOUSE_CLOSED")
f:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
f:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
f:RegisterEvent("ITEM_KEY_ITEM_INFO_RECEIVED")
f:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
f:RegisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
f:RegisterEvent("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED")
f:RegisterEvent("AUCTION_HOUSE_BROWSE_FAILURE")

local SCAN_STATE_IDLE       = 0
local SCAN_STATE_BROWSING   = 1
local SCAN_STATE_PROCESSING = 2
local SCAN_STATE_THROTTLED  = 3

local scanState = {
    phase = SCAN_STATE_IDLE,
    pendingResults = {},
    batchIndex = 0,
    batchPerFrame = 20, -- C_TooltipInfo is data-only and fast
    lastRequestTime = 0,
    pendingBuyItem = nil,
    pendingQuery = nil,
    pendingMore = false,
}

---------------------------------------------------------------------------
-- Map INVTYPE string to Enum.InventoryType for server-side pre-filtering
---------------------------------------------------------------------------
local INVTYPE_TO_ENUM = {
    INVTYPE_HEAD           = Enum.InventoryType and Enum.InventoryType.IndexHeadType,
    INVTYPE_NECK           = Enum.InventoryType and Enum.InventoryType.IndexNeckType,
    INVTYPE_SHOULDER       = Enum.InventoryType and Enum.InventoryType.IndexShoulderType,
    INVTYPE_BODY           = Enum.InventoryType and Enum.InventoryType.IndexBodyType,
    INVTYPE_CHEST          = Enum.InventoryType and Enum.InventoryType.IndexChestType,
    INVTYPE_ROBE           = Enum.InventoryType and Enum.InventoryType.IndexRobeType,
    INVTYPE_WAIST          = Enum.InventoryType and Enum.InventoryType.IndexWaistType,
    INVTYPE_LEGS           = Enum.InventoryType and Enum.InventoryType.IndexLegsType,
    INVTYPE_FEET           = Enum.InventoryType and Enum.InventoryType.IndexFeetType,
    INVTYPE_WRIST          = Enum.InventoryType and Enum.InventoryType.IndexWristType,
    INVTYPE_HAND           = Enum.InventoryType and Enum.InventoryType.IndexHandType,
    INVTYPE_FINGER         = Enum.InventoryType and Enum.InventoryType.IndexFingerType,
    INVTYPE_TRINKET        = Enum.InventoryType and Enum.InventoryType.IndexTrinketType,
    INVTYPE_CLOAK          = Enum.InventoryType and Enum.InventoryType.IndexCloakType,
    INVTYPE_WEAPON         = Enum.InventoryType and Enum.InventoryType.IndexWeaponType,
    INVTYPE_SHIELD         = Enum.InventoryType and Enum.InventoryType.IndexShieldType,
    INVTYPE_2HWEAPON       = Enum.InventoryType and Enum.InventoryType.Index2HweaponType,
    INVTYPE_WEAPONMAINHAND = Enum.InventoryType and Enum.InventoryType.IndexWeaponmainhandType,
    INVTYPE_WEAPONOFFHAND  = Enum.InventoryType and Enum.InventoryType.IndexWeaponoffhandType,
    INVTYPE_HOLDABLE       = Enum.InventoryType and Enum.InventoryType.IndexHoldableType,
    INVTYPE_RANGED         = Enum.InventoryType and Enum.InventoryType.IndexRangedType,
    INVTYPE_RANGEDRIGHT    = Enum.InventoryType and Enum.InventoryType.IndexRangedrightType,
    INVTYPE_THROWN         = Enum.InventoryType and Enum.InventoryType.IndexThrownType,
    INVTYPE_RELIC          = Enum.InventoryType and Enum.InventoryType.IndexRelicType,
    INVTYPE_TABARD         = Enum.InventoryType and Enum.InventoryType.IndexTabardType,
}

---------------------------------------------------------------------------
-- Utility & Canonical Forever Stat Parser
---------------------------------------------------------------------------
local function CleanString(text)
    if not text then return "" end
    text = string.gsub(text, "\194\160", " ")
    text = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
    text = string.gsub(text, "|r", "")
    text = string.gsub(text, "|H.-|h(.-)|h", "%1")
    text = string.gsub(text, "[ \t\r\n]+", " ")
    text = string.gsub(text, "^[ \t\r\n]*(.-)[ \t\r\n]*$", "%1")
    return text
end

local function ToNumber(str)
    if AGS.ParseNumber then return AGS.ParseNumber(str, false) end
    if not str then return 0 end
    str = string.gsub(str, ",", "")
    return tonumber(str) or 0
end

local function ToFloat(str)
    if AGS.ParseNumber then return AGS.ParseNumber(str, true) end
    if not str then return 0 end
    str = string.gsub(str, ",", ".")
    return tonumber(str) or 0
end

local function AddStat(stats, key, amount)
    if not key or key == "" or not amount or amount == 0 then return end
    stats[key] = (stats[key] or 0) + amount
end

local STAT_CANONICAL_NAMES = {
    ["str"]                         = "strength",
    ["agi"]                         = "agility",
    ["sta"]                         = "stamina",
    ["int"]                         = "intellect",
    ["spi"]                         = "spirit",
    ["spell damage"]                = "spell power",
    ["spell dmg"]                   = "spell power",
    ["sp"]                          = "spell power",
    ["spell power"]                 = "spell power",
    ["healing"]                     = "healing",
    ["healing spells"]              = "healing",
    ["heal"]                        = "healing",
    ["attack power"]                = "attack power",
    ["ap"]                          = "attack power",
    ["ranged attack power"]         = "ranged attack power",
    ["rap"]                         = "ranged attack power",
    ["feral attack power"]          = "feral attack power",
    ["critical strike"]             = "crit",
    ["critical strike rating"]      = "crit",
    ["crit"]                        = "crit",
    ["spell critical strike"]       = "spell crit",
    ["spell critical strike rating"]= "spell crit",
    ["spell crit"]                  = "spell crit",
    ["hit"]                         = "hit",
    ["hit rating"]                  = "hit",
    ["spell hit"]                   = "spell hit",
    ["spell hit rating"]            = "spell hit",
    ["haste"]                       = "haste",
    ["haste rating"]                = "haste",
    ["spell haste"]                 = "spell haste",
    ["spell haste rating"]          = "spell haste",
    ["armor penetration"]           = "armor penetration",
    ["armor penetration rating"]    = "armor penetration",
    ["spell penetration"]           = "spell penetration",
    ["defense"]                     = "defense",
    ["defense rating"]              = "defense",
    ["dodge"]                       = "dodge",
    ["dodge rating"]                = "dodge",
    ["parry"]                       = "parry",
    ["parry rating"]                = "parry",
    ["block"]                       = "block",
    ["block rating"]                = "block",
    ["block value"]                 = "block value",
    ["shield block value"]          = "block value",
    ["expertise"]                   = "expertise",
    ["expertise rating"]            = "expertise",
    ["resilience"]                  = "resilience",
    ["resilience rating"]           = "resilience",
    ["mana per 5 sec"]              = "mp5",
    ["mana every 5 sec"]            = "mp5",
    ["mp5"]                         = "mp5",
    ["health per 5 sec"]            = "hp5",
    ["health every 5 sec"]          = "hp5",
    ["hp5"]                         = "hp5",
    ["all stats"]                   = "all stats",
    ["all resistances"]             = "all resistances",
    ["min damage"]                  = "min damage",
    ["min dmg"]                     = "min damage",
    ["minimum damage"]              = "min damage",
    ["max damage"]                  = "max damage",
    ["max dmg"]                     = "max damage",
    ["maximum damage"]              = "max damage",
    ["dps"]                         = "dps",
    ["weapon dps"]                  = "dps",
    ["speed"]                       = "speed",
    ["attack speed"]                = "speed",
    ["weapon speed"]                = "speed",
}

local function CanonicalizeStatName(rawName)
    local lower = string.lower(CleanString(rawName or ""))
    lower = string.gsub(lower, "%.+$", "")
    while string.sub(lower, -3) == "：" do
        lower = string.sub(lower, 1, -4)
    end
    lower = string.gsub(lower, "%.+$", "")
    lower = string.gsub(lower, "^[ \t\r\n]*(.-)[ \t\r\n]*$", "%1")
    if STAT_CANONICAL_NAMES[lower] then
        return STAT_CANONICAL_NAMES[lower]
    end
    if AGS.LocalizedStatAliases and AGS.LocalizedStatAliases[lower] then
        return AGS.LocalizedStatAliases[lower]
    end
    -- Normalize "X Spell Damage" / "X Damage" variants
    local school = string.match(lower, "^([A-Za-z]+)[ \t\r\n]+damage$")
    if school and school ~= "spell" then
        return school .. " spell damage"
    end
    return lower
end

-- Ordered most-specific first so combined lines aren't swallowed by generic rules
local EQUIP_STAT_RULES = {
    -- "Equip: Increases healing done by up to 9 and damage done by up to 3 for all magical spells and effects."
    { pattern = "[Ii]ncreases healing done by up to ([%d,]+) and damage done by up to ([%d,]+)", fn = function(stats, v1, v2)
        AddStat(stats, "healing", ToNumber(v1))
        AddStat(stats, "spell power", ToNumber(v2))
    end },
    -- "Equip: Increases damage and healing done by magical spells and effects by up to 6."
    { pattern = "[Ii]ncreases .-damage and healing .-by up to ([%d,]+)", fn = function(stats, v1)
        AddStat(stats, "spell power", ToNumber(v1))
    end },
    -- School spell damage: "Equip: Increases damage done by Fire spells and effects by up to 12."
    { pattern = "[Ii]ncreases damage done by (%a+) spells .-by up to ([%d,]+)", fn = function(stats, school, v1)
        AddStat(stats, string.lower(school) .. " spell damage", ToNumber(v1))
    end },
    -- Healing only: handles both "by spells and effects by up to X" and "by up to X for all magical spells and effects"
    { pattern = "[Ii]ncreases healing done .-by up to ([%d,]+)", fn = function(stats, v1)
        AddStat(stats, "healing", ToNumber(v1))
    end },
    { pattern = "[Ii]ncreases spell power by ([%d,]+)", fn = function(stats, v1)
        AddStat(stats, "spell power", ToNumber(v1))
    end },
    -- Attack power variants
    { pattern = "%+([%d,]+) ranged [Aa]ttack [Pp]ower", fn = function(stats, v1)
        AddStat(stats, "ranged attack power", ToNumber(v1))
    end },
    { pattern = "%+([%d,]+) [Aa]ttack [Pp]ower in [Cc]at", fn = function(stats, v1)
        AddStat(stats, "feral attack power", ToNumber(v1))
    end },
    { pattern = "[Ii]ncreases attack power by ([%d,]+)", fn = function(stats, v1)
        AddStat(stats, "attack power", ToNumber(v1))
    end },
    -- Crit / Hit / Haste (spell variants before generic)
    { pattern = "[Ii]mproves your chance to get a critical strike with spells by ([%d%.,]+)%%", fn = function(stats, v1)
        AddStat(stats, "spell crit", ToFloat(v1))
    end },
    { pattern = "[Ii]ncreases your spell critical strike rating by ([%d,%.]+)", fn = function(stats, v1)
        AddStat(stats, "spell crit", ToNumber(v1))
    end },
    { pattern = "[Ii]mproves your chance to get a critical strike by ([%d%.,]+)%%", fn = function(stats, v1)
        AddStat(stats, "crit", ToFloat(v1))
    end },
    { pattern = "[Ii]ncreases your critical strike rating by ([%d,%.]+)", fn = function(stats, v1)
        AddStat(stats, "crit", ToNumber(v1))
    end },
    { pattern = "[Ii]mproves your chance to hit with spells by ([%d%.,]+)%%", fn = function(stats, v1)
        AddStat(stats, "spell hit", ToFloat(v1))
    end },
    { pattern = "[Ii]ncreases your spell hit rating by ([%d,%.]+)", fn = function(stats, v1)
        AddStat(stats, "spell hit", ToNumber(v1))
    end },
    { pattern = "[Ii]mproves your chance to hit by ([%d%.,]+)%%", fn = function(stats, v1)
        AddStat(stats, "hit", ToFloat(v1))
    end },
    { pattern = "[Ii]ncreases your hit rating by ([%d,%.]+)", fn = function(stats, v1)
        AddStat(stats, "hit", ToNumber(v1))
    end },
    { pattern = "[Ii]ncreases your spell casting speed by ([%d%.,]+)%%", fn = function(stats, v1)
        AddStat(stats, "spell haste", ToFloat(v1))
    end },
    { pattern = "[Ii]ncreases your spell haste rating by ([%d,%.]+)", fn = function(stats, v1)
        AddStat(stats, "spell haste", ToNumber(v1))
    end },
    { pattern = "[Ii]ncreases your attack speed by ([%d%.,]+)%%", fn = function(stats, v1)
        AddStat(stats, "haste", ToFloat(v1))
    end },
    { pattern = "[Ii]ncreases your .*haste rating by ([%d,%.]+)", fn = function(stats, v1)
        AddStat(stats, "haste", ToNumber(v1))
    end },
    -- MP5 / HP5
    { pattern = "[Rr]estores ([%d,%.]+) mana per 5 sec", fn = function(stats, v1)
        AddStat(stats, "mp5", ToNumber(v1))
    end },
    { pattern = "[Rr]estores ([%d,%.]+) health per 5 sec", fn = function(stats, v1)
        AddStat(stats, "hp5", ToNumber(v1))
    end },
    -- Tank / Mitigation / Penetration
    { pattern = "[Ii]ncreased [Dd]efense %+([%d,%.]+)", fn = function(stats, v1)
        AddStat(stats, "defense", ToNumber(v1))
    end },
    { pattern = "[Ii]ncreases defense rating by ([%d,%.]+)", fn = function(stats, v1)
        AddStat(stats, "defense", ToNumber(v1))
    end },
    { pattern = "[Ii]ncreases your chance to dodge.-by ([%d%.,]+)%%", fn = function(stats, v1)
        AddStat(stats, "dodge", ToFloat(v1))
    end },
    { pattern = "[Ii]ncreases your dodge rating by ([%d,%.]+)", fn = function(stats, v1)
        AddStat(stats, "dodge", ToNumber(v1))
    end },
    { pattern = "[Ii]ncreases your chance to parry.-by ([%d%.,]+)%%", fn = function(stats, v1)
        AddStat(stats, "parry", ToFloat(v1))
    end },
    { pattern = "[Ii]ncreases your parry rating by ([%d,%.]+)", fn = function(stats, v1)
        AddStat(stats, "parry", ToNumber(v1))
    end },
    { pattern = "[Ii]ncreases your chance to block.-by ([%d%.,]+)%%", fn = function(stats, v1)
        AddStat(stats, "block", ToFloat(v1))
    end },
    { pattern = "[Ii]ncreases your block rating by ([%d,%.]+)", fn = function(stats, v1)
        AddStat(stats, "block", ToNumber(v1))
    end },
    { pattern = "[Ii]ncreases the block value of your shield by ([%d,]+)", fn = function(stats, v1)
        AddStat(stats, "block value", ToNumber(v1))
    end },
    { pattern = "[Ii]ncreases your expertise.-by ([%d,]+)", fn = function(stats, v1)
        AddStat(stats, "expertise", ToNumber(v1))
    end },
    { pattern = "[Dd]ecreases the magical resistances of your spell targets by ([%d,]+)", fn = function(stats, v1)
        AddStat(stats, "spell penetration", ToNumber(v1))
    end },
    { pattern = "[Ii]ncreases your spell penetration by ([%d,]+)", fn = function(stats, v1)
        AddStat(stats, "spell penetration", ToNumber(v1))
    end },
    { pattern = "[Ii]ncreases your armor penetration rating by ([%d,]+)", fn = function(stats, v1)
        AddStat(stats, "armor penetration", ToNumber(v1))
    end },
    { pattern = "attacks ignore ([%d,]+) of your opponent's armor", fn = function(stats, v1)
        AddStat(stats, "armor penetration", ToNumber(v1))
    end },
}

local LOCALE_RULES = {}

local function EscapeLuaPattern(text)
    return (string.gsub(text, "([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"))
end

local function BuildPrefixRegex(globalKey)
    local tmpl = _G[globalKey]
    if type(tmpl) ~= "string" or tmpl == "" then return nil end
    local s = CleanString(tmpl)
    local before = string.match(s, "^(.-)%%s") or s
    if before == "" then return nil end
    if AGS.TemplateToPattern then
        local pat = AGS.TemplateToPattern(before, true)
        if pat then return string.sub(pat, 1, -2) end
    end
    return "^" .. EscapeLuaPattern(before)
end

local function MakeLocaleStatFn(kind)
    if kind == "dual_heal_sp" then
        return function(stats, v1, v2)
            AddStat(stats, "healing", ToNumber(v1))
            AddStat(stats, "spell power", ToNumber(v2))
        end
    elseif kind == "sp" then
        return function(stats, v1)
            AddStat(stats, "spell power", ToNumber(v1))
        end
    end
    return function(stats, v1)
        local val = (string.find(tostring(v1), "[%.,]%d%d?$")) and ToFloat(v1) or ToNumber(v1)
        AddStat(stats, kind, val)
    end
end

local ITEM_MOD_GLOBAL_STAT = {
    { "ITEM_MOD_SPELL_POWER",            "spell power" },
    { "ITEM_MOD_SPELL_DAMAGE_DONE",      "spell power" },
    { "ITEM_MOD_SPELL_HEALING_DONE",     "healing" },
    { "ITEM_MOD_ATTACK_POWER",           "attack power" },
    { "ITEM_MOD_RANGED_ATTACK_POWER",    "ranged attack power" },
    { "ITEM_MOD_FERAL_ATTACK_POWER",     "feral attack power" },
    { "ITEM_MOD_CRIT_SPELL_RATING",      "spell crit" },
    { "ITEM_MOD_CRIT_RATING",            "crit" },
    { "ITEM_MOD_HIT_SPELL_RATING",       "spell hit" },
    { "ITEM_MOD_HIT_RATING",             "hit" },
    { "ITEM_MOD_HASTE_SPELL_RATING",     "spell haste" },
    { "ITEM_MOD_HASTE_RATING",           "haste" },
    { "ITEM_MOD_MANA_REGENERATION",      "mp5" },
    { "ITEM_MOD_HEALTH_REGENERATION",    "hp5" },
    { "ITEM_MOD_DEFENSE_SKILL_RATING",   "defense" },
    { "ITEM_MOD_DODGE_RATING",           "dodge" },
    { "ITEM_MOD_PARRY_RATING",           "parry" },
    { "ITEM_MOD_BLOCK_RATING",           "block" },
    { "ITEM_MOD_BLOCK_VALUE",            "block value" },
    { "ITEM_MOD_EXPERTISE_RATING",       "expertise" },
    { "ITEM_MOD_SPELL_PENETRATION",      "spell penetration" },
    { "ITEM_MOD_ARMOR_PENETRATION_RATING","armor penetration" },
}

local function RebuildLocaleRules()
    if AGS.RefreshBlizzardAliases then AGS.RefreshBlizzardAliases() end

    local lr = {
        setPrefixes = { "^%(%d+%)%s*[Ss]et:", "^[Ss]et:" },
        equipPrefixes = { "^[Ee]quip:%s*" },
        usePrefixes = { "^[Uu]se:%s*" },
        procTerms = {
            "chance on ", "have a chance", "has a [%d%% ]*chance",
            "chance to increase", "chance to restore", "for %d+ sec",
        },
        ilvlPatterns = { "^Item Level (%d+)$" },
        reqLvlPatterns = { "^Requires Level (%d+)$" },
        armorPatterns = { "^([%d,%. ]+) Armor$" },
        blockPatterns = { "^([%d,%. ]+) Block$" },
        dmgPatterns = {},
        dpsPatterns = { "%(([%d%.,]+) damage per second%)" },
        speedPatterns = { "^Speed ([%d%.,]+)$" },
        equipRules = {},
        allStatsPatterns = {},
        allResPatterns = {},
    }

    local setGrayPat = BuildPrefixRegex("ITEM_SET_BONUS_GRAY")
    if setGrayPat then table.insert(lr.setPrefixes, setGrayPat) end
    local setPat = BuildPrefixRegex("ITEM_SET_BONUS")
    if setPat then table.insert(lr.setPrefixes, setPat) end

    local eqTrig = _G["ITEM_SPELL_TRIGGER_ONEQUIP"]
    if type(eqTrig) == "string" and eqTrig ~= "" then
        table.insert(lr.equipPrefixes, "^" .. EscapeLuaPattern(CleanString(eqTrig)) .. "%s*")
    end
    local useTrig = _G["ITEM_SPELL_TRIGGER_ONUSE"]
    if type(useTrig) == "string" and useTrig ~= "" then
        table.insert(lr.usePrefixes, "^" .. EscapeLuaPattern(CleanString(useTrig)) .. "%s*")
    end
    local procTrig = _G["ITEM_SPELL_TRIGGER_ONPROC"]
    if type(procTrig) == "string" and procTrig ~= "" then
        table.insert(lr.procTerms, string.lower(CleanString(procTrig)))
    end

    if AGS.TemplateToPattern then
        local pIlvl = AGS.TemplateToPattern(_G["ITEM_LEVEL"], true)
        if pIlvl then table.insert(lr.ilvlPatterns, 1, pIlvl) end
        local pReq = AGS.TemplateToPattern(_G["ITEM_MIN_LEVEL"], true)
        if pReq then table.insert(lr.reqLvlPatterns, 1, pReq) end
        local pArmor = AGS.TemplateToPattern(_G["ARMOR_TEMPLATE"], false)
        if pArmor then table.insert(lr.armorPatterns, 1, pArmor) end
        local pBlock = AGS.TemplateToPattern(_G["SHIELD_BLOCK_TEMPLATE"], false)
        if pBlock then table.insert(lr.blockPatterns, 1, pBlock) end
        local pDmg = AGS.TemplateToPattern(_G["DAMAGE_TEMPLATE"], false)
        if pDmg then table.insert(lr.dmgPatterns, pDmg) end
        local pDps = AGS.TemplateToPattern(_G["DPS_TEMPLATE"], true)
        if pDps then table.insert(lr.dpsPatterns, 1, string.sub(pDps, 2, -2)) end
    end

    local speedWord = _G["SPEED"]
    if type(speedWord) == "string" and speedWord ~= "" then
        table.insert(lr.speedPatterns, 1, "^" .. EscapeLuaPattern(CleanString(speedWord)) .. "%s*([%d%.,]+)$")
    end

    local locData = AGS.GetLocaleTooltipData and AGS.GetLocaleTooltipData() or nil
    if locData then
        if locData.equipPrefix then
            if type(locData.equipPrefix) == "table" then
                for _, p in ipairs(locData.equipPrefix) do table.insert(lr.equipPrefixes, p) end
            else
                table.insert(lr.equipPrefixes, locData.equipPrefix)
            end
        end
        if locData.usePrefix then
            if type(locData.usePrefix) == "table" then
                for _, p in ipairs(locData.usePrefix) do table.insert(lr.usePrefixes, p) end
            else
                table.insert(lr.usePrefixes, locData.usePrefix)
            end
        end
        if locData.procTerms then
            for _, term in ipairs(locData.procTerms) do
                table.insert(lr.procTerms, term)
            end
        end
        if locData.allStats then
            for _, p in ipairs(locData.allStats) do table.insert(lr.allStatsPatterns, p) end
        end
        if locData.allRes then
            for _, p in ipairs(locData.allRes) do table.insert(lr.allResPatterns, p) end
        end
        if locData.rules then
            for _, r in ipairs(locData.rules) do
                if r[1] and r[2] then
                    table.insert(lr.equipRules, { pattern = r[1], fn = MakeLocaleStatFn(r[2]) })
                end
            end
        end
    end

    -- Auto-compiled Blizzard ITEM_MOD_* patterns (works across all 11 official locales)
    if AGS.TemplateToPattern then
        for _, entry in ipairs(ITEM_MOD_GLOBAL_STAT) do
            local tmpl = _G[entry[1]]
            if type(tmpl) == "string" and tmpl ~= "" then
                local pat = AGS.TemplateToPattern(tmpl, false)
                if pat then
                    table.insert(lr.equipRules, { pattern = string.sub(pat, 2, -2), fn = MakeLocaleStatFn(entry[2]) })
                end
            end
        end
    end

    for _, r in ipairs(EQUIP_STAT_RULES) do
        table.insert(lr.equipRules, r)
    end

    LOCALE_RULES = lr
end

RebuildLocaleRules()
AGS.RebuildLocaleRules = RebuildLocaleRules

local function MatchesAny(text, patterns)
    for _, pat in ipairs(patterns) do
        local a, b = string.match(text, pat)
        if a then return a, b end
    end
    return nil
end

local function StripFirstPrefix(text, prefixes)
    for _, pat in ipairs(prefixes) do
        local stripped, n = string.gsub(text, pat, "", 1)
        if n > 0 then return stripped, true end
    end
    return text, false
end

local function ParseLine(leftText, rightText, parsed)
    leftText = CleanString(leftText)
    rightText = CleanString(rightText)

    if leftText ~= "" then
        local lowerLeft = string.lower(leftText)
        local isSetBonus = MatchesAny(leftText, LOCALE_RULES.setPrefixes) ~= nil
            or MatchesAny(lowerLeft, LOCALE_RULES.setPrefixes) ~= nil

        if not isSetBonus then
            table.insert(parsed.allLines, leftText)

            local ilvlMatch = MatchesAny(leftText, LOCALE_RULES.ilvlPatterns)
            if ilvlMatch then parsed.ilvl = ToNumber(ilvlMatch) end

            local reqMatch = MatchesAny(leftText, LOCALE_RULES.reqLvlPatterns)
            if reqMatch then parsed.reqLevel = ToNumber(reqMatch) end

            local armor = MatchesAny(leftText, LOCALE_RULES.armorPatterns)
            if armor then
                parsed.armor = ToNumber(armor)
            end

            local block = MatchesAny(leftText, LOCALE_RULES.blockPatterns)
            if block then
                parsed.block = ToNumber(block)
            end

            local minDmg, maxDmg = MatchesAny(leftText, LOCALE_RULES.dmgPatterns)
            if not minDmg then
                minDmg, maxDmg = string.match(leftText, "^([%d,]+)%s*%-%s*([%d,]+)%s+.-Damage")
                if not minDmg and string.find(leftText, "Damage") then
                    minDmg, maxDmg = string.match(leftText, "^([%d,]+)%s*%-%s*([%d,]+)")
                end
            end
            if minDmg and maxDmg then
                parsed.dmgMin = ToNumber(minDmg)
                parsed.dmgMax = ToNumber(maxDmg)
            end

            local dps = MatchesAny(leftText, LOCALE_RULES.dpsPatterns)
            if dps then
                parsed.dps = ToFloat(dps)
            end

            local strippedEquip, isEquipLine = StripFirstPrefix(leftText, LOCALE_RULES.equipPrefixes)
            local _, isUseLine = StripFirstPrefix(leftText, LOCALE_RULES.usePrefixes)
            local isProcLine = false
            for _, term in ipairs(LOCALE_RULES.procTerms) do
                if string.find(lowerLeft, term, 1, not string.find(term, "[%%^%$]")) then
                    isProcLine = true
                    break
                end
            end

            -- Try verbose Forever/Classic Equip rules before generic +X Stat (skip Use:/proc/set bonuses)
            local consumedEquipStat = false
            if not isUseLine and not isProcLine then
                for _, rule in ipairs(LOCALE_RULES.equipRules) do
                    local a, b = string.match(leftText, rule.pattern)
                    if not a and isEquipLine then
                        a, b = string.match(strippedEquip, rule.pattern)
                    end
                    if a then
                        rule.fn(parsed.stats, a, b)
                        consumedEquipStat = true
                        break
                    end
                end

                if not consumedEquipStat then
                    local allStatVal = MatchesAny(string.lower(strippedEquip), LOCALE_RULES.allStatsPatterns)
                    if allStatVal then
                        AddStat(parsed.stats, "all stats", ToNumber(allStatVal))
                        if isEquipLine then consumedEquipStat = true end
                    end
                end
                if not consumedEquipStat then
                    local allResVal = MatchesAny(string.lower(strippedEquip), LOCALE_RULES.allResPatterns)
                    if allResVal then
                        AddStat(parsed.stats, "all resistances", ToNumber(allResVal))
                        if isEquipLine then consumedEquipStat = true end
                    end
                end

                if not consumedEquipStat then
                    local statValue, statName = string.match(strippedEquip, "^%+([%d,%.]+)%%?[ \t\r\n]*(.+)$")
                    if not statValue then
                        -- Handle reversed suffix form e.g. "Stamina +5", "체력 +5"
                        local revName, revVal = string.match(strippedEquip, "^(.-)[ \t\r\n]*:?[ \t\r\n]*%+([%d,%.]+)%%?$")
                        if revName and string.sub(revName, -3) == "：" then
                            revName = string.gsub(string.sub(revName, 1, -4), "^[ \t\r\n]*(.-)[ \t\r\n]*$", "%1")
                        end
                        if revName and revName ~= "" then
                            local revLower = string.lower(revName)
                            local knownAlias = STAT_CANONICAL_NAMES[revLower]
                                or (AGS.LocalizedStatAliases and AGS.LocalizedStatAliases[revLower])
                            if knownAlias or (AGS.Locale == "enUS" and string.match(revName, "^[A-Za-z \t\r\n]+$")) then
                                statName, statValue = revName, revVal
                            end
                        end
                    end
                    if statValue and statName then
                        local canonical = CanonicalizeStatName(statName)
                        AddStat(parsed.stats, canonical, ToFloat(string.gsub(statValue, "%.+$", "")))
                        if isEquipLine then
                            consumedEquipStat = true
                        end
                    end
                end
            end

            -- Only show non-stat procs/uses in green effects pills so cards stay clean
            if not consumedEquipStat and (isEquipLine or isUseLine or isProcLine) then
                table.insert(parsed.effects, leftText)
            end
        end
    end

    if rightText ~= "" then
        table.insert(parsed.allLines, rightText)
        local speed = MatchesAny(rightText, LOCALE_RULES.speedPatterns)
        if speed then
            parsed.speed = ToFloat(speed)
        end
    end
end

-- Expose parser & alias resolver so UI pills and self-checks can reuse them
AGS.CanonicalizeStatName = CanonicalizeStatName
AGS.ParseLine = ParseLine

---------------------------------------------------------------------------
-- Tooltip Parser (Modern C_TooltipInfo with GameTooltip fallback)
---------------------------------------------------------------------------
local function IsRedRGB(r, g, b)
    return r and g and b and (r > 0.85 and g < 0.35 and b < 0.35)
end

local function GetTooltipColorRGB(c)
    if not c then return nil end
    if c.GetRGB then return c:GetRGB() end
    return c.r, c.g, c.b
end

local function RecordRedTooltipText(text, isRight, parsed)
    if not text or text == "" then return end
    local trimmed = text:match("^[ \t\r\n]*(.-)[ \t\r\n]*$")
    if trimmed == "" then return end
    local u = parsed.unusable
    for _, existing in ipairs(u.reasons) do
        if existing == trimmed then return end
    end
    table.insert(u.reasons, trimmed)
    local cleaned = CleanString(trimmed)
    local lower = string.lower(cleaned)
    if MatchesAny(cleaned, LOCALE_RULES.reqLvlPatterns) or string.find(lower, "requires level", 1, true) then
        u.level = true
    elseif isRight then
        u.subType = true
    elseif not u.other then
        u.other = trimmed
    end
end

local function ParseItemKeyTooltip(itemKey)
    local parsed = {
        armor = 0, block = 0,
        dps = 0, dmgMin = 0, dmgMax = 0, speed = 0,
        ilvl = itemKey.itemLevel or 0, reqLevel = 0,
        stats = {},
        effects = {},
        allLines = {},
        unusable = { level = false, subType = false, other = nil, reasons = {} },
        itemLink = nil,
    }

    if C_TooltipInfo and C_TooltipInfo.GetItemKey then
        local data = C_TooltipInfo.GetItemKey(itemKey.itemID, itemKey.itemLevel or 0, itemKey.itemSuffix or 0, itemKey.requiredLevel or 0)
        if data and data.lines then
            parsed.itemLink = data.hyperlink
            for _, line in ipairs(data.lines) do
                ParseLine(line.leftText, line.rightText, parsed)
                if IsRedRGB(GetTooltipColorRGB(line.leftColor)) then
                    RecordRedTooltipText(line.leftText, false, parsed)
                end
                if IsRedRGB(GetTooltipColorRGB(line.rightColor)) then
                    RecordRedTooltipText(line.rightText, true, parsed)
                end
            end
            return parsed
        end
    end

    -- Fallback to hidden GameTooltip
    scanTip:ClearLines()
    scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    if scanTip.SetItemKey then
        scanTip:SetItemKey(itemKey.itemID, itemKey.itemLevel or 0, itemKey.itemSuffix or 0, itemKey.requiredLevel or 0)
    else
        scanTip:SetItemByID(itemKey.itemID)
    end
    local _, link = scanTip:GetItem()
    parsed.itemLink = link

    for i = 1, scanTip:NumLines() do
        local leftLine = _G["FGS_ScanTipTextLeft"..i]
        local rightLine = _G["FGS_ScanTipTextRight"..i]
        local lText = leftLine and leftLine:GetText()
        local rText = rightLine and rightLine:GetText()
        ParseLine(lText, rText, parsed)
        if leftLine and leftLine.GetTextColor and IsRedRGB(leftLine:GetTextColor()) then
            RecordRedTooltipText(lText, false, parsed)
        end
        if rightLine and rightLine.GetTextColor and IsRedRGB(rightLine:GetTextColor()) then
            RecordRedTooltipText(rText, true, parsed)
        end
    end

    return parsed
end

---------------------------------------------------------------------------
-- Pawn Integration (OptionalDependency)
---------------------------------------------------------------------------
function AGS:HasPawn()
    return (PawnIsReady and PawnIsReady() and PawnGetItemData and PawnIsItemAnUpgrade) and true or false
end

function AGS:GetVisiblePawnScales()
    local scales = {}
    if not self:HasPawn() or not PawnGetAllScalesEx then return scales end
    local ok, allScales = pcall(PawnGetAllScalesEx)
    if not ok or not allScales then return scales end
    for _, s in ipairs(allScales) do
        if s.IsVisible and s.Name then
            table.insert(scales, {
                name = s.Name,
                localizedName = s.LocalizedName or s.Name,
            })
        end
    end
    return scales
end

local function PickPawnUpgrade(upgradesByScale, targetScale)
    if not upgradesByScale then return 0, nil, nil end
    if targetScale then
        local entry = upgradesByScale[targetScale]
        if entry then
            return entry.pct, entry.scale, entry.existing
        end
        return 0, nil, nil
    end
    local bestPct, bestScale, bestExisting = 0, nil, nil
    for _, entry in pairs(upgradesByScale) do
        if entry.pct > bestPct then
            bestPct = entry.pct
            bestScale = entry.scale
            bestExisting = entry.existing
        end
    end
    return bestPct, bestScale, bestExisting
end

local function EvaluatePawnUpgrade(itemLink, itemID)
    if not AGS:HasPawn() then
        return 0, nil, nil, nil
    end
    local linkToCheck = itemLink or (itemID and ("item:" .. itemID))
    if not linkToCheck then return 0, nil, nil, nil end

    local ok, itemData = pcall(PawnGetItemData, linkToCheck)
    if not ok or not itemData then return 0, nil, nil, nil end

    local okUp, upgradeTable = pcall(PawnIsItemAnUpgrade, itemData)
    if not okUp or not upgradeTable or #upgradeTable == 0 then return 0, nil, nil, nil end

    local byScale = {}
    for _, entry in ipairs(upgradeTable) do
        local key = entry.ScaleName or entry.LocalizedScaleName
        if key then
            byScale[key] = {
                pct = (entry.PercentUpgrade or 0) * 100,
                scale = entry.LocalizedScaleName or entry.ScaleName,
                existing = entry.ExistingItemLink,
            }
        end
    end
    local pct, scale, existing = PickPawnUpgrade(byScale, AGS.Filters.pawnScale)
    return pct, scale, existing, byScale
end

function AGS:RebuildResults()
    local filtered = {}
    for _, item in ipairs(self.RawResults) do
        if not self.Filters.upgradesOnly or (item.pawnUpgrade or 0) > 0 then
            table.insert(filtered, item)
        end
    end
    self.Results = filtered
    self:SortResults()
end

function AGS:SetPawnScale(scaleName)
    self.Filters.pawnScale = scaleName
    for _, item in ipairs(self.RawResults) do
        local pct, scale, existing = PickPawnUpgrade(item.pawnUpgrades, scaleName)
        item.pawnUpgrade = pct
        item.pawnScale = scale
        item.pawnExisting = existing
    end
    self:RebuildResults()
end

---------------------------------------------------------------------------
-- Client-side Filter
---------------------------------------------------------------------------
local function ResolveStatValue(parsed, statQuery)
    local canonical = CanonicalizeStatName(statQuery)
    if canonical == "dps" then return (parsed.dps and parsed.dps > 0) and parsed.dps or nil end
    if canonical == "speed" then return (parsed.speed and parsed.speed > 0) and parsed.speed or nil end
    if canonical == "min damage" then return (parsed.dmgMin and parsed.dmgMin > 0) and parsed.dmgMin or nil end
    if canonical == "max damage" then return (parsed.dmgMax and parsed.dmgMax > 0) and parsed.dmgMax or nil end
    local val = parsed.stats[canonical]
    if val then return val end
    if canonical == "healing" and parsed.stats["spell power"] then
        return parsed.stats["spell power"]
    end
    return nil
end

local function PassesFilter(item, ignoreUpgradesOnly)
    local fl = AGS.Filters

    -- Gear-only: reject items without an equipment slot
    local itemSlot = item.equipSlot or ""
    if itemSlot == "" or itemSlot == "INVTYPE_NON_EQUIP" or itemSlot == "INVTYPE_BAG" then return false end

    -- Quality filter
    if fl.qualityIndex and fl.qualityIndex > 0 then
        local requiredQuality = fl.qualityIndex - 1
        if (item.quality or 0) < requiredQuality then return false end
    end

    -- Slot filter
    if fl.invTypeFilter and fl.invTypeFilter ~= "" then
        if fl.invTypeFilter == "INVTYPE_CHEST" then
            if itemSlot ~= "INVTYPE_CHEST" and itemSlot ~= "INVTYPE_ROBE" then return false end
        elseif fl.invTypeFilter == "INVTYPE_RANGED" then
            if itemSlot ~= "INVTYPE_RANGED" and itemSlot ~= "INVTYPE_RANGEDRIGHT" then return false end
        else
            if itemSlot ~= fl.invTypeFilter then return false end
        end
    end

    -- Required level safeguard
    if fl.minLevel > 0 and (item.reqLevel or 0) < fl.minLevel then return false end
    if fl.maxLevel > 0 and (item.reqLevel or 0) > fl.maxLevel then return false end

    -- Price filter (require buyable price)
    if item.buyoutPrice <= 0 then return false end
    if fl.maxBuyout > 0 and item.buyoutPrice > fl.maxBuyout then return false end

    -- Pawn Upgrades Only filter
    if not ignoreUpgradesOnly and fl.upgradesOnly and (item.pawnUpgrade or 0) <= 0 then return false end

    -- Tooltip-based filters
    local p = item.parsed
    if fl.minArmor > 0 and p.armor < fl.minArmor then return false end
    if fl.maxArmor > 0 and p.armor > fl.maxArmor then return false end

    if fl.minDPS > 0 and p.dps < fl.minDPS then return false end
    if fl.maxDPS > 0 and p.dps > fl.maxDPS then return false end

    if fl.minSpeed > 0 and (p.speed or 0) < fl.minSpeed then return false end
    if fl.maxSpeed > 0 and ((p.speed or 0) <= 0 or p.speed > fl.maxSpeed) then return false end

    if fl.minDamage > 0 or fl.maxDamage > 0 then
        local wMin = p.dmgMin or 0
        local wMax = p.dmgMax or 0
        if fl.minDamage > 0 and wMax < fl.minDamage then return false end
        if fl.maxDamage > 0 and wMin > fl.maxDamage then return false end
    end

    -- Stat filters (canonical + aliases + raw text fallback)
    for _, statF in ipairs(fl.stats) do
        local val = ResolveStatValue(p, statF.name)
        local passedStat = false
        if val then
            if (statF.min == 0 or val >= statF.min) and (statF.max == 0 or val <= statF.max) then
                passedStat = true
            end
        elseif statF.min == 0 and statF.max == 0 then
            local needle = string.lower(statF.name)
            for _, line in ipairs(p.allLines) do
                if string.find(string.lower(line), needle, 1, true) then
                    passedStat = true
                    break
                end
            end
        end
        if not passedStat then return false end
    end

    return true
end

---------------------------------------------------------------------------
-- Build Item Record from BrowseResultInfo
---------------------------------------------------------------------------
local function BuildBrowseItem(browseResult)
    local itemKey = browseResult.itemKey
    if not itemKey or not itemKey.itemID then return nil end
    if (browseResult.minPrice or 0) <= 0 then return nil end

    local _, itemType, itemSubType, itemEquipLoc, icon, classID, subClassID = C_Item.GetItemInfoInstant(itemKey.itemID)
    if not itemEquipLoc or itemEquipLoc == "" then return nil end

    local keyInfo = C_AuctionHouse.GetItemKeyInfo(itemKey)
    local itemName, itemLink, itemQuality, itemLevel, itemMinLevel = C_Item.GetItemInfo(itemKey.itemID)

    local parsed = ParseItemKeyTooltip(itemKey)
    local link = parsed.itemLink or itemLink
    local name = (keyInfo and keyInfo.itemName) or itemName
    if not name then
        if C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(itemKey.itemID)
        end
        return false -- signals item info not cached yet
    end

    local quality = (keyInfo and keyInfo.quality) or itemQuality or 1
    local finalIlvl = (itemKey.itemLevel and itemKey.itemLevel > 0 and itemKey.itemLevel)
        or (parsed.ilvl > 0 and parsed.ilvl)
        or itemLevel or 0
    local finalReqLevel = (parsed.reqLevel > 0 and parsed.reqLevel) or itemMinLevel or 0

    local pawnPct, pawnScale, pawnExisting, pawnUpgrades = EvaluatePawnUpgrade(link, itemKey.itemID)

    local u = parsed.unusable or { level = false, subType = false, other = nil, reasons = {} }
    local playerLevel = (UnitLevel and UnitLevel("player")) or 999
    if finalReqLevel > 0 and playerLevel < finalReqLevel then
        u.level = true
    end
    if u.other and itemSubType and itemSubType ~= "" and string.find(string.lower(u.other), string.lower(itemSubType), 1, true) then
        u.subType = true
        u.other = nil
    end
    u.any = (u.level or u.subType or (u.other ~= nil) or (#u.reasons > 0)) and true or false

    return {
        itemKey = itemKey,
        itemID = itemKey.itemID,
        name = name,
        link = link or name,
        texture = (keyInfo and keyInfo.iconFileID) or icon,
        quality = quality,
        ilvl = finalIlvl,
        reqLevel = finalReqLevel,
        equipSlot = itemEquipLoc,
        itemType = itemType or "",
        itemSubType = itemSubType or "",
        classID = classID,
        subClassID = subClassID,
        buyoutPrice = browseResult.minPrice or 0,
        minBid = browseResult.minPrice or 0,
        totalQuantity = browseResult.totalQuantity or 1,
        pawnUpgrade = pawnPct,
        pawnScale = pawnScale,
        pawnExisting = pawnExisting,
        pawnUpgrades = pawnUpgrades,
        unusable = u,
        parsed = parsed,
    }
end

---------------------------------------------------------------------------
-- Sorting
---------------------------------------------------------------------------
function AGS:SortResults()
    table.sort(self.Results, function(a, b)
        local valA, valB
        if self.SortKey == "buyout" then
            valA = a.buyoutPrice > 0 and a.buyoutPrice or 99999999999
            valB = b.buyoutPrice > 0 and b.buyoutPrice or 99999999999
        elseif self.SortKey == "pawn" then
            valA = a.pawnUpgrade or 0
            valB = b.pawnUpgrade or 0
        elseif self.SortKey == "name" then
            valA = a.name
            valB = b.name
        else
            valA = ResolveStatValue(a.parsed, self.SortKey) or 0
            valB = ResolveStatValue(b.parsed, self.SortKey) or 0
        end

        if valA == valB then
            return a.name < b.name
        end

        if self.SortDescending then
            return valA > valB
        else
            return valA < valB
        end
    end)

    if self.UI and self.UI.UpdateResults then
        self.UI:UpdateResults()
    end
end

function AGS:SetSort(key)
    if self.SortKey == key then
        self.SortDescending = not self.SortDescending
    else
        self.SortKey = key
        self.SortDescending = (key ~= "buyout")
    end
    self:SortResults()
end

---------------------------------------------------------------------------
-- Build C_AuctionHouse BrowseQuery
---------------------------------------------------------------------------
local function BuildClassFilters()
    local fl = AGS.Filters
    local invEnum = fl.invTypeFilter ~= "" and INVTYPE_TO_ENUM[fl.invTypeFilter] or nil
    local filters = {}

    if invEnum then
        -- Match Blizzard/TSM special slot rules
        if invEnum == Enum.InventoryType.IndexChestType or invEnum == Enum.InventoryType.IndexRobeType then
            table.insert(filters, { classID = Enum.ItemClass.Armor, subClassID = fl.subClassID, inventoryType = Enum.InventoryType.IndexChestType })
            table.insert(filters, { classID = Enum.ItemClass.Armor, subClassID = fl.subClassID, inventoryType = Enum.InventoryType.IndexRobeType })
            return filters
        elseif invEnum == Enum.InventoryType.IndexNeckType
            or invEnum == Enum.InventoryType.IndexFingerType
            or invEnum == Enum.InventoryType.IndexTrinketType
            or invEnum == Enum.InventoryType.IndexHoldableType
            or invEnum == Enum.InventoryType.IndexBodyType then
            table.insert(filters, { classID = Enum.ItemClass.Armor, subClassID = Enum.ItemArmorSubclass.Generic, inventoryType = invEnum })
            return filters
        elseif invEnum == Enum.InventoryType.IndexCloakType then
            table.insert(filters, { classID = Enum.ItemClass.Armor, subClassID = Enum.ItemArmorSubclass.Cloth, inventoryType = invEnum })
            return filters
        elseif Enum.InventoryType.IndexRangedType and (invEnum == Enum.InventoryType.IndexRangedType or invEnum == Enum.InventoryType.IndexRangedrightType) then
            local weaponClass = fl.classID or Enum.ItemClass.Weapon
            table.insert(filters, { classID = weaponClass, subClassID = fl.subClassID, inventoryType = Enum.InventoryType.IndexRangedType })
            if Enum.InventoryType.IndexRangedrightType then
                table.insert(filters, { classID = weaponClass, subClassID = fl.subClassID, inventoryType = Enum.InventoryType.IndexRangedrightType })
            end
            return filters
        end
    end

    if fl.classID then
        table.insert(filters, {
            classID = fl.classID,
            subClassID = fl.subClassID,
            inventoryType = invEnum,
        })
    else
        -- Default: Both Weapons and Armor
        table.insert(filters, { classID = Enum.ItemClass.Weapon, inventoryType = invEnum })
        table.insert(filters, { classID = Enum.ItemClass.Armor, inventoryType = invEnum })
    end

    return filters
end

local function IsAHReady()
    return not C_AuctionHouse.IsThrottledMessageSystemReady or C_AuctionHouse.IsThrottledMessageSystemReady()
end

local function DispatchBrowseOrWait(query)
    scanState.lastRequestTime = GetTime()
    if IsAHReady() then
        scanState.pendingQuery = nil
        scanState.pendingMore = false
        scanState.phase = SCAN_STATE_BROWSING
        if query then
            C_AuctionHouse.SendBrowseQuery(query)
        else
            C_AuctionHouse.RequestMoreBrowseResults()
        end
    else
        scanState.phase = SCAN_STATE_THROTTLED
        if query then
            scanState.pendingQuery = query
            scanState.pendingMore = false
        else
            scanState.pendingMore = true
            scanState.pendingQuery = nil
        end
        if AGS.UI then AGS.UI:SetStatus(L.STATUS_THROTTLE_WAIT or "Waiting for AH throttle...") end
    end
end

function AGS:StartSearch()
    if not C_AuctionHouse or not C_AuctionHouse.SendBrowseQuery then
        if self.UI then self.UI:SetStatus(L.STATUS_AH_UNAVAILABLE or "Auction House API unavailable.") end
        return
    end

    self.Results = {}
    self.RawResults = {}
    self.IsScanning = true
    scanState.pendingResults = {}
    scanState.batchIndex = 0
    scanState.pendingBuyItem = nil
    scanState.lastQuery = nil

    if self.UI and self.UI.UpdateResults then
        self.UI:UpdateResults()
    end
    if self.UI and self.UI.SetStatus then
        self.UI:SetStatus(L.STATUS_SENDING or "Sending query to Auction House...")
    end

    local fl = self.Filters
    local ahFilters = {}
    if fl.usableOnly and Enum.AuctionHouseFilter and Enum.AuctionHouseFilter.UsableOnly then
        table.insert(ahFilters, Enum.AuctionHouseFilter.UsableOnly)
    end
    if Enum.AuctionHouseFilter and Enum.AuctionHouseFilter.PoorQuality then
        -- Send full [Poor..Artifact] range when "Any" is chosen, matching TSM's working Forever query builder
        local minQ = (fl.qualityIndex and fl.qualityIndex > 0)
            and ((fl.qualityIndex - 1) + Enum.AuctionHouseFilter.PoorQuality)
            or Enum.AuctionHouseFilter.PoorQuality
        local maxQ = Enum.AuctionHouseFilter.ArtifactQuality or (Enum.AuctionHouseFilter.PoorQuality + 6)
        for q = minQ, maxQ do
            table.insert(ahFilters, q)
        end
    end

    local query = {
        searchString = fl.name or "",
        minLevel = (fl.minLevel and fl.minLevel > 0) and fl.minLevel or 0,
        maxLevel = (fl.maxLevel and fl.maxLevel > 0) and fl.maxLevel or 0,
        filters = ahFilters,
        itemClassFilters = BuildClassFilters(),
        sorts = {
            { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false },
            { sortOrder = Enum.AuctionHouseSortOrder.Name, reverseSort = false },
        },
    }

    scanState.lastQuery = query
    DispatchBrowseOrWait(query)
end

---------------------------------------------------------------------------
-- Quick-Buy (Hardware-event safe two-click flow: Search -> Confirm Buy)
---------------------------------------------------------------------------
local function ItemKeysMatch(a, b)
    if not a or not b or a.itemID ~= b.itemID then return false end
    if (a.itemLevel or 0) ~= (b.itemLevel or 0) then return false end
    if (a.itemSuffix or 0) ~= (b.itemSuffix or 0) then return false end
    return true
end

function AGS:QuickBuyOrInspect(item)
    if not item or not item.itemKey then return end
    if AuctionHouseFrame and AuctionHouseFrame.IsShown and not AuctionHouseFrame:IsShown() then
        if self.UI then self.UI:SetStatus(L.STATUS_OPEN_AH_BUY or "Open the Auction House to buy items.") end
        return
    end

    -- Click 2: PlaceBid MUST execute directly inside OnClick (#hwevent protected on Forever)
    if item.readyAuctionID and item.readyBuyoutAmount and item.readyBuyoutAmount > 0 then
        local auctionID = item.readyAuctionID
        local amount = item.readyBuyoutAmount
        item.readyAuctionID = nil
        item.readyBuyoutAmount = nil
        C_AuctionHouse.PlaceBid(auctionID, amount)
        if self.UI then
            self.UI:SetStatus(string.format(L.STATUS_PURCHASED or "Purchased %s for %s!", item.link or item.name, GetMoneyString(amount, true)))
            if self.UI.UpdateResults then self.UI:UpdateResults() end
        end
        return
    end

    -- Click 1: Fetch cheapest exact listing to resolve auctionID & buyoutAmount
    scanState.pendingBuyItem = item
    C_AuctionHouse.SendSearchQuery(item.itemKey, {
        { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false }
    }, false)
    if self.UI then
        self.UI:SetStatus(string.format(L.STATUS_FETCHING_CHEAPEST or "Fetching cheapest listing for %s...", item.link or item.name))
    end
end

---------------------------------------------------------------------------
-- Batched Processing OnUpdate
---------------------------------------------------------------------------
local function OnUpdate(self, elapsed)
    if not AGS.IsScanning then return end

    if scanState.phase == SCAN_STATE_BROWSING or scanState.phase == SCAN_STATE_THROTTLED then
        if GetTime() - scanState.lastRequestTime > 15.0 then
            AGS.IsScanning = false
            scanState.phase = SCAN_STATE_IDLE
            scanState.pendingQuery = nil
            scanState.pendingMore = false
            if AGS.UI then AGS.UI:SetStatus(L.STATUS_TIMED_OUT or "Scan timed out. Try again.") end
        end
        return
    end

    if scanState.phase == SCAN_STATE_PROCESSING then
        local batch = scanState.pendingResults
        local startIdx = scanState.batchIndex
        local endIdx = math.min(startIdx + scanState.batchPerFrame - 1, #batch)

        for i = startIdx, endIdx do
            local item = BuildBrowseItem(batch[i])
            if item == false then
                -- Item info not cached yet; re-queue once
                if not batch[i]._retried then
                    batch[i]._retried = true
                    table.insert(batch, batch[i])
                end
            elseif item and PassesFilter(item, true) then
                table.insert(AGS.RawResults, item)
                if not AGS.Filters.upgradesOnly or (item.pawnUpgrade or 0) > 0 then
                    table.insert(AGS.Results, item)
                end
            end
        end

        scanState.batchIndex = endIdx + 1

        if scanState.batchIndex > #batch then
            scanState.pendingResults = {}
            scanState.batchIndex = 0

            if not C_AuctionHouse.HasFullBrowseResults() then
                DispatchBrowseOrWait(nil)
                if scanState.phase == SCAN_STATE_BROWSING and AGS.UI then
                    AGS.UI:SetStatus(string.format(L.STATUS_SCAN_MORE or "Scanning more results... (%d matches so far)", #AGS.Results))
                end
            else
                AGS.IsScanning = false
                scanState.phase = SCAN_STATE_IDLE
                AGS:SortResults()
                if AGS.UI then
                    AGS.UI:SetStatus(string.format(L.STATUS_COMPLETE or "Scan complete. Found %d matching gear items.", #AGS.Results))
                end
            end
        else
            if AGS.UI then
                AGS.UI:SetStatus(string.format(L.STATUS_PARSING or "Parsing tooltips... (%d / %d, %d matches)", scanState.batchIndex - 1, #batch, #AGS.Results))
            end
        end
    end
end

f:SetScript("OnUpdate", OnUpdate)

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local function QueueBrowseBatch(results)
    if not results or #results == 0 then
        if C_AuctionHouse.HasFullBrowseResults() then
            AGS.IsScanning = false
            scanState.phase = SCAN_STATE_IDLE
            AGS:SortResults()
            if AGS.UI then
                AGS.UI:SetStatus(string.format(L.STATUS_COMPLETE or "Scan complete. Found %d matching gear items.", #AGS.Results))
            end
        end
        return
    end

    for _, r in ipairs(results) do
        table.insert(scanState.pendingResults, r)
    end
    if scanState.batchIndex == 0 then
        scanState.batchIndex = 1
    end
    scanState.phase = SCAN_STATE_PROCESSING
end

f:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == addonName then
            ForeverGearScannerDB = ForeverGearScannerDB or {}
            ForeverGearScannerDB.presets = ForeverGearScannerDB.presets or {}
        end
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        local interactionType = ...
        if Enum.PlayerInteractionType and interactionType == Enum.PlayerInteractionType.Auctioneer then
            if AGS.UI and AGS.UI.Initialize and not AGS.UI.initialized then
                C_Timer.After(0.05, function() AGS.UI:Initialize() end)
            end
        end
    elseif event == "AUCTION_HOUSE_SHOW" then
        if AGS.UI and AGS.UI.Initialize and not AGS.UI.initialized then
            C_Timer.After(0.05, function() AGS.UI:Initialize() end)
        end
    elseif event == "AUCTION_HOUSE_CLOSED" then
        AGS.IsScanning = false
        scanState.phase = SCAN_STATE_IDLE
        scanState.pendingResults = {}
        scanState.batchIndex = 0
        scanState.pendingQuery = nil
        scanState.pendingMore = false
        scanState.pendingBuyItem = nil
        for _, it in ipairs(AGS.RawResults) do
            it.readyAuctionID = nil
            it.readyBuyoutAmount = nil
        end
    elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
        if not AGS.IsScanning then return end
        QueueBrowseBatch(C_AuctionHouse.GetBrowseResults())
    elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
        if not AGS.IsScanning then return end
        local addedResults = ...
        QueueBrowseBatch(addedResults)
    elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
        if not AGS.IsScanning or scanState.phase ~= SCAN_STATE_THROTTLED then return end
        if scanState.pendingQuery then
            DispatchBrowseOrWait(scanState.pendingQuery)
        elseif scanState.pendingMore then
            DispatchBrowseOrWait(nil)
        end
    elseif event == "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED" then
        if not AGS.IsScanning then return end
        if scanState.phase == SCAN_STATE_BROWSING then
            -- Re-queue dropped query/page when AH throttle clears
            scanState.phase = SCAN_STATE_THROTTLED
            if #scanState.pendingResults == 0 and #AGS.Results == 0 and scanState.lastQuery then
                scanState.pendingQuery = scanState.lastQuery
            else
                scanState.pendingMore = true
            end
            if AGS.UI then AGS.UI:SetStatus(L.STATUS_THROTTLE_RETRY or "AH throttled – retrying automatically...") end
        end
    elseif event == "AUCTION_HOUSE_BROWSE_FAILURE" then
        if not AGS.IsScanning then return end
        AGS.IsScanning = false
        scanState.phase = SCAN_STATE_IDLE
        scanState.pendingQuery = nil
        scanState.pendingMore = false
        if AGS.UI then AGS.UI:SetStatus(L.STATUS_BROWSE_FAILED or "Auction House browse failed. Wait a moment and retry.") end
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
        local itemKey = ...
        local pending = scanState.pendingBuyItem
        if pending and ItemKeysMatch(itemKey, pending.itemKey) then
            scanState.pendingBuyItem = nil
            local numResults = C_AuctionHouse.GetNumItemSearchResults(itemKey)
            if numResults and numResults > 0 then
                local info = C_AuctionHouse.GetItemSearchResultInfo(itemKey, 1)
                if info and info.auctionID and info.buyoutAmount and info.buyoutAmount > 0 then
                    pending.readyAuctionID = info.auctionID
                    pending.readyBuyoutAmount = info.buyoutAmount
                    pending.buyoutPrice = info.buyoutAmount
                    if AGS.UI then
                        AGS.UI:SetStatus(string.format(L.STATUS_READY_CONFIRM or "Cheapest listing ready (%s). Click 'Confirm Buy' to purchase %s.", GetMoneyString(info.buyoutAmount, true), pending.link or pending.name))
                        if AGS.UI.UpdateResults then AGS.UI:UpdateResults() end
                    end
                    return
                end
            end
            if AGS.UI then
                AGS.UI:SetStatus(string.format(L.STATUS_NO_BUYOUT or "No active buyout listing found for %s.", pending.link or pending.name))
            end
        end
    end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
SLASH_FGS1 = "/fgs"
SLASH_FGS2 = "/gearscanner"
SlashCmdList["FGS"] = function()
    print("|cFFFFD700ForeverGearScanner|r: " .. (L.SLASH_HELP or "Open the Auction House and click the 'Gear Scanner' tab."))
end
