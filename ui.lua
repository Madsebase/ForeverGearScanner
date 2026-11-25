local addonName, AGS = ...
if not AGS then return end

AGS.UI = AGS.UI or {}
local UI = AGS.UI
local L = AGS.L or {}
local GetSlotLabel = AGS.GetSlotLabel or function(s) return s or "" end
local GetQualityLabel = AGS.GetQualityLabel or function(q) return "Quality " .. tostring(q) end
local GetStatDisplayName = AGS.GetStatDisplayName or function(k) return k or "" end

local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil

local PANEL_BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 }
}

local CARD_BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 }
}

local EDITBOX_BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 8, edgeSize = 8,
    insets = { left = 2, right = 2, top = 2, bottom = 2 }
}

local function ApplyBackdrop(frame, backdrop, r, g, b, a, br, bg, bb, ba)
    if not frame.SetBackdrop and BackdropTemplateMixin then
        Mixin(frame, BackdropTemplateMixin)
    end
    if frame.SetBackdrop then
        frame:SetBackdrop(backdrop)
        if r then frame:SetBackdropColor(r, g, b, a or 1) end
        if br then frame:SetBackdropBorderColor(br, bg, bb, ba or 1) end
    end
end

---------------------------------------------------------------------------
-- Slot & Category Definitions
---------------------------------------------------------------------------
local ARMOR_SLOTS = {
    { invtype = "INVTYPE_HEAD" },
    { invtype = "INVTYPE_NECK" },
    { invtype = "INVTYPE_SHOULDER" },
    { invtype = "INVTYPE_CLOAK" },
    { invtype = "INVTYPE_CHEST" },
    { invtype = "INVTYPE_WRIST" },
    { invtype = "INVTYPE_HAND" },
    { invtype = "INVTYPE_WAIST" },
    { invtype = "INVTYPE_LEGS" },
    { invtype = "INVTYPE_FEET" },
    { invtype = "INVTYPE_FINGER" },
    { invtype = "INVTYPE_TRINKET" },
    { invtype = "INVTYPE_HOLDABLE" },
    { invtype = "INVTYPE_BODY" },
    { invtype = "INVTYPE_TABARD" },
}

local WEAPON_SLOTS = {
    { invtype = "INVTYPE_WEAPON" },
    { invtype = "INVTYPE_2HWEAPON" },
    { invtype = "INVTYPE_WEAPONMAINHAND" },
    { invtype = "INVTYPE_WEAPONOFFHAND" },
    { invtype = "INVTYPE_HOLDABLE" },
    { invtype = "INVTYPE_RANGED" },
    { invtype = "INVTYPE_THROWN" },
    { invtype = "INVTYPE_RELIC" },
    { invtype = "INVTYPE_SHIELD" },
}

local PREDEFINED_STATS = {
    "spell power", "healing",
    "fire spell damage", "frost spell damage", "shadow spell damage",
    "nature spell damage", "arcane spell damage", "holy spell damage",
    "min damage", "max damage", "dps", "speed",
    "strength", "agility", "stamina", "intellect", "spirit",
    "attack power", "ranged attack power", "feral attack power",
    "crit", "spell crit", "hit", "spell hit", "haste", "spell haste",
    "mp5", "hp5", "defense", "dodge", "parry", "block value", "block",
    "expertise", "spell penetration", "armor penetration", "all stats",
    "all resistances", "use:", "chance on hit"
}

local function FormatStatLabel(key)
    return GetStatDisplayName(key)
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function FormatMoney(copper)
    if not copper or copper == 0 then return "--" end
    if GetMoneyString then
        return GetMoneyString(copper, true)
    end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local str = ""
    if g > 0 then str = str .. g .. "|cFFFFD700g|r " end
    if s > 0 then str = str .. s .. "|cFFC0C0C0s|r " end
    if c > 0 and g == 0 then str = str .. c .. "|cFFB87333c|r" end
    return str
end

local function StripScrollbar(scrollFrame)
    local name = scrollFrame:GetName()
    local sb = scrollFrame.ScrollBar or (name and _G[name.."ScrollBar"])
    if sb then
        if sb.ScrollUpButton then sb.ScrollUpButton:Hide() end
        if sb.ScrollDownButton then sb.ScrollDownButton:Hide() end
        if sb.Back then sb.Back:Hide() end
        if sb.Forward then sb.Forward:Hide() end
    end
    if name then
        local up = _G[name.."ScrollBarScrollUpButton"]
        local down = _G[name.."ScrollBarScrollDownButton"]
        if up then up:Hide() end
        if down then down:Hide() end
    end
end

local function GetQualityRGB(quality)
    if C_Item and C_Item.GetItemQualityColor then
        local r, g, b = C_Item.GetItemQualityColor(quality or 1)
        if r then return r, g, b end
    end
    return 1, 1, 1
end

local function FormatExistingItemLabel(existing)
    if not existing or existing == "" then return nil end
    if string.find(existing, "|H", 1, true) then return existing end
    local name, link
    if C_Item and C_Item.GetItemInfo then
        name, link = C_Item.GetItemInfo(existing)
    end
    if link then return link end
    if name then return name end
    local id = tonumber(string.match(existing, "item:(%d+)"))
    if id then
        if C_Item and C_Item.GetItemNameByID then
            local byID = C_Item.GetItemNameByID(id)
            if byID then return byID end
        end
        return string.format(L.ITEM_PREFIX or "Item #%d", id)
    end
    return existing
end

---------------------------------------------------------------------------
-- UI Handles & State
---------------------------------------------------------------------------
local mainFrame, leftPanel, rightPanel, lpScrollChild
local cards = {}
local statFilterRows = {}
local collapsibleSections = {}
local isInitialized = false
local allEditBoxes = {}

local currentQuality = 0
local currentClassID = nil     -- nil = Any Equipment, Enum.ItemClass.Weapon, Enum.ItemClass.Armor
local currentSubClassID = nil
local currentInvTypeFilter = ""
local currentPawnScale = nil

local ddQuality, ddCategory, ddSubtype, ddSlot, ddPawnSpec
local editWeaponMin, editWeaponMax, editDpsMin, editDpsMax, editSpeedMin, editSpeedMax
local editArmorMin, editArmorMax
local editReqLevelMin, editReqLevelMax
local checkUsableOnly, checkPawnUpgrades, editBuyoutGold, editBuyoutSilver, editBuyoutCopper
local btnSearch, btnClear, txtStatus
local statContainer
local sortBar, sortActiveText, emptyText
local sortButtons = {}
local hasSearched = false

---------------------------------------------------------------------------
-- Autocomplete Popup
---------------------------------------------------------------------------
local autoCompleteFrame

local function CreateAutoCompletePopup()
    if autoCompleteFrame then return autoCompleteFrame end

    local f = CreateFrame("Frame", "FGS_AutoCompletePopup", UIParent, BACKDROP_TEMPLATE)
    f:SetSize(140, 120)
    f:SetFrameStrata("TOOLTIP")
    ApplyBackdrop(f, PANEL_BACKDROP, 0.05, 0.05, 0.05, 0.98, 0.5, 0.5, 0.5, 1)
    f:Hide()

    local sc = CreateFrame("ScrollFrame", "FGS_ACScroll", f, "UIPanelScrollFrameTemplate")
    sc:SetPoint("TOPLEFT", 6, -8)
    sc:SetPoint("BOTTOMRIGHT", -26, 8)
    if sc.EnableMouseWheel then sc:EnableMouseWheel(true) end
    StripScrollbar(sc)

    local sChild = CreateFrame("Frame", nil, sc)
    sChild:SetSize(150, 100)
    sc:SetScrollChild(sChild)

    f.sc = sc
    f.buttons = {}
    f.sChild = sChild
    f:SetScript("OnUpdate", function(self)
        if self.currentFocusEditBox and not self.currentFocusEditBox:HasFocus() and not self:IsMouseOver() then
            self:Hide()
        end
    end)
    autoCompleteFrame = f
    return f
end

local function ShowAutoComplete(targetEditBox)
    local query = targetEditBox:GetText()
    local matches = {}
    local lowerQuery = string.lower(query or "")
    for _, statKey in ipairs(PREDEFINED_STATS) do
        local display = GetStatDisplayName(statKey)
        if lowerQuery == ""
            or string.find(string.lower(display), lowerQuery, 1, true)
            or string.find(statKey, lowerQuery, 1, true) then
            table.insert(matches, display)
        end
    end

    if #matches == 0 then
        if autoCompleteFrame then autoCompleteFrame:Hide() end
        return
    end

    local pop = CreateAutoCompletePopup()
    pop.currentFocusEditBox = targetEditBox
    pop:ClearAllPoints()
    pop:SetPoint("TOPLEFT", targetEditBox, "BOTTOMLEFT", 0, -2)
    pop:SetWidth(math.max(190, targetEditBox:GetWidth()))
    pop.sChild:SetWidth(pop:GetWidth() - 34)
    if pop.sc and pop.sc.SetVerticalScroll then
        pop.sc:SetVerticalScroll(0)
    end

    for _, btn in ipairs(pop.buttons) do btn:Hide() end

    local yOff = 0
    for i, matchText in ipairs(matches) do
        local btn = pop.buttons[i]
        if not btn then
            btn = CreateFrame("Button", nil, pop.sChild)
            btn:SetHeight(18)
            local txt = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            txt:SetPoint("LEFT", 4, 0)
            btn.txt = txt

            local bg = btn:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.2, 0.2, 0.2, 0.5)
            bg:Hide()
            btn.bg = bg

            btn:SetScript("OnEnter", function(s) s.bg:Show() end)
            btn:SetScript("OnLeave", function(s) s.bg:Hide() end)

            pop.buttons[i] = btn
        end

        btn:SetWidth(pop.sChild:GetWidth())
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", pop.sChild, "TOPLEFT", 0, yOff)
        btn.txt:SetText(matchText)

        btn:SetScript("OnClick", function()
            targetEditBox:ClearFocus()
            targetEditBox:SetText(matchText)
            pop:Hide()
        end)

        btn:Show()
        yOff = yOff - 18
    end

    pop.sChild:SetHeight(math.abs(yOff))
    local visibleRows = math.min(10, #matches)
    pop:SetHeight(visibleRows * 18 + 16)
    pop:Show()
end

---------------------------------------------------------------------------
-- EditBox Factory & Tab Navigation
---------------------------------------------------------------------------
local function UnregisterEditBoxTabNav(edit)
    for i = #allEditBoxes, 1, -1 do
        if allEditBoxes[i] == edit then
            table.remove(allEditBoxes, i)
            break
        end
    end
end

local function RegisterEditBoxTabNav(edit)
    table.insert(allEditBoxes, edit)
    edit:SetScript("OnTabPressed", function(self)
        local visibleBoxes = {}
        for _, e in ipairs(allEditBoxes) do
            if e:IsVisible() then table.insert(visibleBoxes, e) end
        end
        if #visibleBoxes == 0 then return end

        local currentIdx = 1
        for i, e in ipairs(visibleBoxes) do
            if e == self then currentIdx = i; break end
        end

        if IsShiftKeyDown() then
            local prevIdx = (currentIdx > 1) and (currentIdx - 1) or #visibleBoxes
            visibleBoxes[prevIdx]:SetFocus()
        else
            local nextIdx = (currentIdx < #visibleBoxes) and (currentIdx + 1) or 1
            visibleBoxes[nextIdx]:SetFocus()
        end
    end)
end

local function CreateCleanEditBox(parent, width, height, placeholder)
    local frame = CreateFrame("Frame", nil, parent, BACKDROP_TEMPLATE)
    frame:SetSize(width, height or 20)
    ApplyBackdrop(frame, EDITBOX_BACKDROP, 0.02, 0.02, 0.02, 0.9, 0.35, 0.35, 0.35, 0.9)

    local edit = CreateFrame("EditBox", nil, frame)
    edit:SetAllPoints(frame)
    edit:SetTextInsets(5, 5, 0, 0)
    edit:SetFontObject("GameFontHighlightSmall")
    edit:SetAutoFocus(false)

    local phText
    if placeholder and placeholder ~= "" then
        phText = edit:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        phText:SetPoint("LEFT", 6, 0)
        phText:SetPoint("RIGHT", -4, 0)
        phText:SetJustifyH("LEFT")
        phText:SetText(placeholder)
        phText:SetTextColor(0.45, 0.45, 0.45, 0.85)
    end

    local function UpdatePlaceholder()
        if not phText then return end
        local txt = edit:GetText()
        if (not txt or txt == "") and not edit:HasFocus() then
            phText:Show()
        else
            phText:Hide()
        end
    end

    edit:SetScript("OnEditFocusGained", function()
        if frame.SetBackdropBorderColor then frame:SetBackdropBorderColor(0.8, 0.8, 0.2, 1) end
        UpdatePlaceholder()
    end)
    edit:SetScript("OnEditFocusLost", function()
        if frame.SetBackdropBorderColor then frame:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.9) end
        UpdatePlaceholder()
    end)
    edit:SetScript("OnTextChanged", UpdatePlaceholder)
    edit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    RegisterEditBoxTabNav(edit)
    return edit, frame
end

---------------------------------------------------------------------------
-- Collapsible Sections
---------------------------------------------------------------------------
local function SetSectionExpanded(section, expanded)
    section.isExpanded = expanded and true or false
    if section.isExpanded then
        section.headerText:SetText("|cFFFFD700[-] " .. section.title .. "|r")
        section.content:Show()
    else
        section.headerText:SetText("|cFFFFD700[+] " .. section.title .. "|r")
        section.content:Hide()
    end
end

local function LayoutFilterPanel()
    if not lpScrollChild then return end
    local yOffset = -4
    for _, section in ipairs(collapsibleSections) do
        if section.frame:IsShown() then
            section.frame:ClearAllPoints()
            section.frame:SetPoint("TOPLEFT", lpScrollChild, "TOPLEFT", 4, yOffset)
            section.frame:SetPoint("RIGHT", lpScrollChild, "RIGHT", -4, 0)

            if section.content:IsShown() then
                local height = section.contentHeight + 23
                section.frame:SetHeight(height)
                yOffset = yOffset - height - 4
            else
                section.frame:SetHeight(23)
                yOffset = yOffset - 23 - 4
            end
        end
    end
    lpScrollChild:SetHeight(math.abs(yOffset) + 16)
end

local function CreateCollapsibleSection(parent, title, contentHeight, defaultCollapsed)
    local frame = CreateFrame("Frame", nil, parent, BACKDROP_TEMPLATE)
    ApplyBackdrop(frame, PANEL_BACKDROP, 0.06, 0.06, 0.06, 0.95, 0.25, 0.25, 0.25, 0.9)

    local header = CreateFrame("Button", nil, frame)
    header:SetPoint("TOPLEFT", 4, -4)
    header:SetPoint("TOPRIGHT", -4, -4)
    header:SetHeight(16)

    local headerText = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    headerText:SetPoint("LEFT", 4, 0)

    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", 4, -20)
    content:SetPoint("BOTTOMRIGHT", -4, -4)

    local section = {
        frame = frame,
        content = content,
        header = header,
        headerText = headerText,
        title = title,
        contentHeight = contentHeight,
        isExpanded = not defaultCollapsed
    }

    SetSectionExpanded(section, not defaultCollapsed)

    header:SetScript("OnClick", function()
        SetSectionExpanded(section, not section.isExpanded)
        LayoutFilterPanel()
    end)

    table.insert(collapsibleSections, section)
    return content, section
end

local function CreateLabel(parent, text, x, y)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", x, y)
    lbl:SetText(text)
    return lbl
end

---------------------------------------------------------------------------
-- Contextual Filter Visibility & Slots
---------------------------------------------------------------------------
local function UpdateContextualFilters()
    local showWeapon = (currentClassID == nil or currentClassID == Enum.ItemClass.Weapon)
    local showArmor  = (currentClassID == nil or currentClassID == Enum.ItemClass.Armor)

    for _, sec in ipairs(collapsibleSections) do
        if sec.id == "WEAPON" then
            if showWeapon then
                sec.frame:Show()
                SetSectionExpanded(sec, currentClassID == Enum.ItemClass.Weapon)
            else
                sec.frame:Hide()
            end
        elseif sec.id == "ARMOR" then
            if showArmor then
                sec.frame:Show()
                SetSectionExpanded(sec, currentClassID == Enum.ItemClass.Armor)
            else
                sec.frame:Hide()
            end
        end
    end

    if not showWeapon then
        editWeaponMin:SetText(""); editWeaponMax:SetText("")
        editDpsMin:SetText(""); editDpsMax:SetText("")
        editSpeedMin:SetText(""); editSpeedMax:SetText("")
    end
    if not showArmor then
        editArmorMin:SetText(""); editArmorMax:SetText("")
    end

    LayoutFilterPanel()
end

local function GetSlotsForCurrentCategory()
    if currentClassID == Enum.ItemClass.Weapon then
        return WEAPON_SLOTS
    elseif currentClassID == Enum.ItemClass.Armor then
        return ARMOR_SLOTS
    else
        local combined = {}
        for _, s in ipairs(ARMOR_SLOTS) do table.insert(combined, s) end
        for _, s in ipairs(WEAPON_SLOTS) do
            if s.invtype ~= "INVTYPE_HOLDABLE" then -- already in ARMOR_SLOTS
                table.insert(combined, s)
            end
        end
        return combined
    end
end

---------------------------------------------------------------------------
-- Filter Sections
---------------------------------------------------------------------------
local function CreateTypeFilters(parent)
    local c = CreateCollapsibleSection(parent, L.SEC_TYPE or "Type Filters", 104)

    -- Rarity
    CreateLabel(c, L.LBL_RARITY or "Rarity:", 5, -4)
    ddQuality = CreateFrame("Frame", "FGS_DDQuality", c, "UIDropDownMenuTemplate")
    ddQuality:SetPoint("TOPLEFT", 48, -1)
    UIDropDownMenu_SetWidth(ddQuality, 124)
    UIDropDownMenu_Initialize(ddQuality, function()
        local anyText = L.OPT_ANY or "Any"
        local info = UIDropDownMenu_CreateInfo()
        info.notCheckable = true
        info.text = anyText
        info.arg1 = 0
        info.func = function(_, arg1)
            currentQuality = arg1
            UIDropDownMenu_SetText(ddQuality, anyText)
            CloseDropDownMenus()
        end
        UIDropDownMenu_AddButton(info)

        for qId = 0, 5 do
            local qText = GetQualityLabel(qId)
            local inf = UIDropDownMenu_CreateInfo()
            inf.notCheckable = true
            inf.text = qText
            inf.arg1 = qId + 1
            inf.func = function(_, arg1)
                currentQuality = arg1
                UIDropDownMenu_SetText(ddQuality, qText)
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(inf)
        end
    end)
    UIDropDownMenu_SetText(ddQuality, L.OPT_ANY or "Any")

    -- Category (Weapon / Armor only)
    CreateLabel(c, L.LBL_CAT or "Cat:", 5, -29)
    ddCategory = CreateFrame("Frame", "FGS_DDCategory", c, "UIDropDownMenuTemplate")
    ddCategory:SetPoint("TOPLEFT", 48, -26)
    UIDropDownMenu_SetWidth(ddCategory, 124)
    UIDropDownMenu_Initialize(ddCategory, function()
        local anyEquip = L.OPT_ANY_EQUIP or "Any Equipment"
        local anyText = L.OPT_ANY or "Any"
        local info = UIDropDownMenu_CreateInfo()
        info.notCheckable = true
        info.text = anyEquip
        info.func = function()
            currentClassID = nil
            currentSubClassID = nil
            currentInvTypeFilter = ""
            UIDropDownMenu_SetText(ddCategory, anyEquip)
            UIDropDownMenu_SetText(ddSubtype, anyText)
            UIDropDownMenu_SetText(ddSlot, anyText)
            UpdateContextualFilters()
            CloseDropDownMenus()
        end
        UIDropDownMenu_AddButton(info)

        local equipClasses = { Enum.ItemClass.Weapon, Enum.ItemClass.Armor }
        for _, classID in ipairs(equipClasses) do
            local className = C_Item.GetItemClassInfo(classID)
            if className then
                local inf = UIDropDownMenu_CreateInfo()
                inf.notCheckable = true
                inf.text = className
                inf.func = function()
                    currentClassID = classID
                    currentSubClassID = nil
                    currentInvTypeFilter = ""
                    UIDropDownMenu_SetText(ddCategory, className)
                    UIDropDownMenu_SetText(ddSubtype, anyText)
                    UIDropDownMenu_SetText(ddSlot, anyText)
                    UpdateContextualFilters()
                    CloseDropDownMenus()
                end
                UIDropDownMenu_AddButton(inf)
            end
        end
    end)
    UIDropDownMenu_SetText(ddCategory, L.OPT_ANY_EQUIP or "Any Equipment")

    -- Subcategory
    CreateLabel(c, L.LBL_SUB or "Sub:", 5, -54)
    ddSubtype = CreateFrame("Frame", "FGS_DDSubtype", c, "UIDropDownMenuTemplate")
    ddSubtype:SetPoint("TOPLEFT", 48, -51)
    UIDropDownMenu_SetWidth(ddSubtype, 124)
    UIDropDownMenu_Initialize(ddSubtype, function()
        local anyText = L.OPT_ANY or "Any"
        local info = UIDropDownMenu_CreateInfo()
        info.notCheckable = true
        info.text = anyText
        info.func = function()
            currentSubClassID = nil
            currentInvTypeFilter = ""
            UIDropDownMenu_SetText(ddSubtype, anyText)
            UIDropDownMenu_SetText(ddSlot, anyText)
            CloseDropDownMenus()
        end
        UIDropDownMenu_AddButton(info)

        if currentClassID and C_AuctionHouse and C_AuctionHouse.GetAuctionItemSubClasses then
            local subClasses = C_AuctionHouse.GetAuctionItemSubClasses(currentClassID)
            for _, subID in ipairs(subClasses) do
                local subName = C_Item.GetItemSubClassInfo(currentClassID, subID)
                if subName and not string.find(subName, "OBSOLETE") then
                    local inf = UIDropDownMenu_CreateInfo()
                    inf.notCheckable = true
                    inf.text = subName
                    inf.func = function()
                        currentSubClassID = subID
                        currentInvTypeFilter = ""
                        UIDropDownMenu_SetText(ddSubtype, subName)
                        UIDropDownMenu_SetText(ddSlot, anyText)
                        CloseDropDownMenus()
                    end
                    UIDropDownMenu_AddButton(inf)
                end
            end
        end
    end)
    UIDropDownMenu_SetText(ddSubtype, L.OPT_ANY or "Any")

    -- Slot
    CreateLabel(c, L.LBL_SLOT or "Slot:", 5, -79)
    ddSlot = CreateFrame("Frame", "FGS_DDSlot", c, "UIDropDownMenuTemplate")
    ddSlot:SetPoint("TOPLEFT", 48, -76)
    UIDropDownMenu_SetWidth(ddSlot, 124)
    UIDropDownMenu_Initialize(ddSlot, function()
        local anyText = L.OPT_ANY or "Any"
        local info = UIDropDownMenu_CreateInfo()
        info.notCheckable = true
        info.text = anyText
        info.func = function()
            currentInvTypeFilter = ""
            UIDropDownMenu_SetText(ddSlot, anyText)
            CloseDropDownMenus()
        end
        UIDropDownMenu_AddButton(info)

        local slots = GetSlotsForCurrentCategory()
        for _, slot in ipairs(slots) do
            local slotLabel = GetSlotLabel(slot.invtype)
            local inf = UIDropDownMenu_CreateInfo()
            inf.notCheckable = true
            inf.text = slotLabel
            inf.func = function()
                currentInvTypeFilter = slot.invtype
                UIDropDownMenu_SetText(ddSlot, slotLabel)
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(inf)
        end
    end)
    UIDropDownMenu_SetText(ddSlot, L.OPT_ANY or "Any")
end

local function CreateWeaponFilters(parent)
    local c, sec = CreateCollapsibleSection(parent, L.SEC_WEAPON or "Weapon Filters", 78, true)
    sec.id = "WEAPON"
    local phMin, phMax = L.PH_MIN or "Min", L.PH_MAX or "Max"
    CreateLabel(c, L.LBL_DAMAGE or "Damage:", 5, -4)
    editWeaponMin = CreateCleanEditBox(c, 40, 20, phMin); editWeaponMin:GetParent():SetPoint("TOPLEFT", 70, -1)
    CreateLabel(c, "–", 114, -4)
    editWeaponMax = CreateCleanEditBox(c, 40, 20, phMax); editWeaponMax:GetParent():SetPoint("TOPLEFT", 124, -1)

    CreateLabel(c, L.LBL_DPS or "DPS:", 5, -30)
    editDpsMin = CreateCleanEditBox(c, 40, 20, phMin); editDpsMin:GetParent():SetPoint("TOPLEFT", 70, -27)
    CreateLabel(c, "–", 114, -30)
    editDpsMax = CreateCleanEditBox(c, 40, 20, phMax); editDpsMax:GetParent():SetPoint("TOPLEFT", 124, -27)

    CreateLabel(c, L.LBL_SPEED or "Speed:", 5, -56)
    editSpeedMin = CreateCleanEditBox(c, 40, 20, phMin); editSpeedMin:GetParent():SetPoint("TOPLEFT", 70, -53)
    CreateLabel(c, "–", 114, -56)
    editSpeedMax = CreateCleanEditBox(c, 40, 20, phMax); editSpeedMax:GetParent():SetPoint("TOPLEFT", 124, -53)
end

local function CreateArmorFilters(parent)
    local c, sec = CreateCollapsibleSection(parent, L.SEC_ARMOR or "Armour Filters", 28, true)
    sec.id = "ARMOR"
    CreateLabel(c, L.LBL_ARMOR or "Armour:", 5, -4)
    editArmorMin = CreateCleanEditBox(c, 40, 20, L.PH_MIN or "Min"); editArmorMin:GetParent():SetPoint("TOPLEFT", 70, -1)
    CreateLabel(c, "–", 114, -4)
    editArmorMax = CreateCleanEditBox(c, 40, 20, L.PH_MAX or "Max"); editArmorMax:GetParent():SetPoint("TOPLEFT", 124, -1)
end

local function CreateCoinEditBox(parent, x, y, width, maxLetters, atlasName, fallbackTex)
    local edit, frame = CreateCleanEditBox(parent, width, 20)
    frame:SetPoint("TOPLEFT", x, y)
    edit:SetTextInsets(4, 14, 0, 0)
    if edit.SetNumeric then edit:SetNumeric(true) end
    if edit.SetMaxLetters then edit:SetMaxLetters(maxLetters) end
    local icon = frame:CreateTexture(nil, "OVERLAY")
    icon:SetSize(11, 11)
    icon:SetPoint("RIGHT", -3, 0)
    if icon.SetAtlas then
        icon:SetAtlas(atlasName)
    else
        icon:SetTexture(fallbackTex)
    end
    return edit
end

local function CreateRequirements(parent)
    local hasPawn = AGS.HasPawn and AGS:HasPawn()
    local c = CreateCollapsibleSection(parent, L.SEC_REQ or "Level & Price", hasPawn and 118 or 74)
    CreateLabel(c, L.LBL_REQ_LEVEL or "Req Level:", 5, -4)
    editReqLevelMin = CreateCleanEditBox(c, 40, 20, L.PH_MIN or "Min"); editReqLevelMin:GetParent():SetPoint("TOPLEFT", 70, -1)
    CreateLabel(c, "–", 114, -4)
    editReqLevelMax = CreateCleanEditBox(c, 40, 20, L.PH_MAX or "Max"); editReqLevelMax:GetParent():SetPoint("TOPLEFT", 124, -1)

    CreateLabel(c, L.LBL_MAX_PRICE or "Max price:", 5, -30)
    editBuyoutGold   = CreateCoinEditBox(c, 68,  -27, 48, 6, "auctionhouse-icon-coin-gold",   "Interface\\MoneyFrame\\UI-GoldIcon")
    editBuyoutSilver = CreateCoinEditBox(c, 119, -27, 38, 2, "auctionhouse-icon-coin-silver", "Interface\\MoneyFrame\\UI-SilverIcon")
    editBuyoutCopper = CreateCoinEditBox(c, 160, -27, 38, 2, "auctionhouse-icon-coin-copper", "Interface\\MoneyFrame\\UI-CopperIcon")

    checkUsableOnly = CreateFrame("CheckButton", "FGS_CheckUsable", c, "UICheckButtonTemplate")
    checkUsableOnly:SetPoint("TOPLEFT", 0, -50)
    checkUsableOnly:SetSize(24, 24)
    checkUsableOnly:SetChecked(false)
    local usableTxt = checkUsableOnly.Text or _G[checkUsableOnly:GetName().."Text"]
    if usableTxt then
        usableTxt:SetText(L.CHK_USABLE or "Usable Only")
        usableTxt:SetFontObject("GameFontHighlightSmall")
    end

    if hasPawn then
        checkPawnUpgrades = CreateFrame("CheckButton", "FGS_CheckPawn", c, "UICheckButtonTemplate")
        checkPawnUpgrades:SetPoint("TOPLEFT", 0, -72)
        checkPawnUpgrades:SetSize(24, 24)
        checkPawnUpgrades:SetChecked(false)
        local pawnTxt = checkPawnUpgrades.Text or _G[checkPawnUpgrades:GetName().."Text"]
        if pawnTxt then
            pawnTxt:SetText("|cFFb4fe2c" .. (L.CHK_PAWN or "Pawn Upgrades Only") .. "|r")
            pawnTxt:SetFontObject("GameFontHighlightSmall")
        end

        CreateLabel(c, L.LBL_SPEC or "Spec:", 5, -98)
        ddPawnSpec = CreateFrame("Frame", "FGS_DDPawnSpec", c, "UIDropDownMenuTemplate")
        ddPawnSpec:SetPoint("TOPLEFT", 38, -94)
        UIDropDownMenu_SetWidth(ddPawnSpec, 134)
        UIDropDownMenu_Initialize(ddPawnSpec, function()
            local anyBest = L.OPT_ANY_BEST or "Any (Best)"
            local info = UIDropDownMenu_CreateInfo()
            info.notCheckable = true
            info.text = anyBest
            info.func = function()
                currentPawnScale = nil
                UIDropDownMenu_SetText(ddPawnSpec, anyBest)
                if AGS.SetPawnScale then AGS:SetPawnScale(nil) end
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info)

            local scales = AGS.GetVisiblePawnScales and AGS:GetVisiblePawnScales() or {}
            for _, sc in ipairs(scales) do
                local shortLabel = string.gsub(sc.localizedName, "^[^:]+:%s*", "")
                local inf = UIDropDownMenu_CreateInfo()
                inf.notCheckable = true
                inf.text = shortLabel
                inf.func = function()
                    currentPawnScale = sc.name
                    UIDropDownMenu_SetText(ddPawnSpec, shortLabel)
                    if AGS.SetPawnScale then AGS:SetPawnScale(sc.name) end
                    CloseDropDownMenus()
                end
                UIDropDownMenu_AddButton(inf)
            end
        end)
        UIDropDownMenu_SetText(ddPawnSpec, L.OPT_ANY_BEST or "Any (Best)")
    end
end

---------------------------------------------------------------------------
-- Stat Filters Section
---------------------------------------------------------------------------
local function LayoutStatFilters()
    local y = -5
    for _, row in ipairs(statFilterRows) do
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", statContainer, "TOPLEFT", 0, y)
        y = y - 25
    end
    for _, sec in ipairs(collapsibleSections) do
        if sec.content == statContainer:GetParent() then
            sec.contentHeight = math.abs(y) + 30
            break
        end
    end
    LayoutFilterPanel()
end

local function AddStatFilterRow(statText, minVal, maxVal)
    local row = CreateFrame("Frame", nil, statContainer)
    row:SetSize(220, 22)

    local editStat = CreateCleanEditBox(row, 96, 20, L.PH_STAT or "Stat...")
    editStat:GetParent():SetPoint("TOPLEFT", 0, 0)
    local prevFocusGained = editStat:GetScript("OnEditFocusGained")
    editStat:SetScript("OnEditFocusGained", function(self)
        if prevFocusGained then prevFocusGained(self) end
        ShowAutoComplete(self)
    end)
    local prevTextChanged = editStat:GetScript("OnTextChanged")
    editStat:SetScript("OnTextChanged", function(self)
        if prevTextChanged then prevTextChanged(self) end
        if self:HasFocus() then
            ShowAutoComplete(self)
        end
    end)
    editStat:SetText(statText or "")

    local editMin = CreateCleanEditBox(row, 34, 20, L.PH_MIN or "Min")
    editMin:GetParent():SetPoint("TOPLEFT", 100, 0)
    editMin:SetText(minVal or "")

    local editMax = CreateCleanEditBox(row, 34, 20, L.PH_MAX or "Max")
    editMax:GetParent():SetPoint("TOPLEFT", 138, 0)
    editMax:SetText(maxVal or "")

    local btnRemove = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    btnRemove:SetSize(20, 20)
    btnRemove:SetPoint("TOPLEFT", 176, 0)
    btnRemove:SetText("X")
    btnRemove:SetScript("OnClick", function()
        row:Hide()
        UnregisterEditBoxTabNav(editStat)
        UnregisterEditBoxTabNav(editMin)
        UnregisterEditBoxTabNav(editMax)
        for i, r in ipairs(statFilterRows) do
            if r == row then table.remove(statFilterRows, i); break end
        end
        LayoutStatFilters()
    end)

    row.editStat = editStat
    row.editMin = editMin
    row.editMax = editMax

    table.insert(statFilterRows, row)
    LayoutStatFilters()
    return row
end

local function FocusOrAddStatFilter(statLabel)
    local lowerTarget = string.lower(statLabel or "")
    for _, row in ipairs(statFilterRows) do
        local cur = row.editStat:GetText()
        if cur == "" or string.lower(cur) == lowerTarget then
            if cur == "" then row.editStat:SetText(statLabel) end
            row.editMin:SetFocus()
            return row
        end
    end
    local newRow = AddStatFilterRow(statLabel)
    if newRow and newRow.editMin then newRow.editMin:SetFocus() end
    return newRow
end

local function CreateStatFilters(parent)
    local c = CreateCollapsibleSection(parent, L.SEC_STATS or "Stat Filters", 60)

    local btnAdd = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
    btnAdd:SetSize(145, 22)
    btnAdd:SetPoint("TOPLEFT", 5, -5)
    btnAdd:SetText(L.BTN_ADD_STAT or "+ Add Stat Filter")
    btnAdd:SetScript("OnClick", function() AddStatFilterRow() end)

    statContainer = CreateFrame("Frame", nil, c)
    statContainer:SetPoint("TOPLEFT", 0, -35)
    statContainer:SetPoint("RIGHT", 0, 0)
    statContainer:SetHeight(20)
end

---------------------------------------------------------------------------
-- Clear / Sync
---------------------------------------------------------------------------
local function ClearFilters()
    currentQuality = 0; UIDropDownMenu_SetText(ddQuality, L.OPT_ANY or "Any")
    currentClassID = nil; UIDropDownMenu_SetText(ddCategory, L.OPT_ANY_EQUIP or "Any Equipment")
    currentSubClassID = nil; UIDropDownMenu_SetText(ddSubtype, L.OPT_ANY or "Any")
    currentInvTypeFilter = ""; UIDropDownMenu_SetText(ddSlot, L.OPT_ANY or "Any")

    editWeaponMin:SetText(""); editWeaponMax:SetText("")
    editDpsMin:SetText(""); editDpsMax:SetText("")
    editSpeedMin:SetText(""); editSpeedMax:SetText("")
    editArmorMin:SetText(""); editArmorMax:SetText("")

    editReqLevelMin:SetText(""); editReqLevelMax:SetText("")
    editBuyoutGold:SetText(""); editBuyoutSilver:SetText(""); editBuyoutCopper:SetText("")

    checkUsableOnly:SetChecked(false)
    if checkPawnUpgrades then checkPawnUpgrades:SetChecked(false) end
    currentPawnScale = nil
    if ddPawnSpec then UIDropDownMenu_SetText(ddPawnSpec, L.OPT_ANY_BEST or "Any (Best)") end
    if AGS.SetPawnScale then AGS:SetPawnScale(nil) end

    for _, row in ipairs(statFilterRows) do
        row:Hide()
        UnregisterEditBoxTabNav(row.editStat)
        UnregisterEditBoxTabNav(row.editMin)
        UnregisterEditBoxTabNav(row.editMax)
    end
    statFilterRows = {}
    LayoutStatFilters()
    UpdateContextualFilters()
end

local function SyncFiltersFromUI()
    local function getVal(edit, allowDecimal)
        local t = edit:GetText()
        if not t or t == "" then return 0 end
        if AGS.ParseNumber then return AGS.ParseNumber(t, allowDecimal) end
        return tonumber(t) or 0
    end

    local fl = AGS.Filters
    fl.name = ""
    fl.qualityIndex = currentQuality
    fl.classID = currentClassID
    fl.subClassID = currentSubClassID
    fl.invTypeFilter = currentInvTypeFilter
    fl.usableOnly = checkUsableOnly:GetChecked()
    fl.upgradesOnly = checkPawnUpgrades and checkPawnUpgrades:GetChecked() or false
    fl.pawnScale = currentPawnScale

    fl.minLevel = getVal(editReqLevelMin, false)
    fl.maxLevel = getVal(editReqLevelMax, false)

    local maxGold   = getVal(editBuyoutGold, false)
    local maxSilver = getVal(editBuyoutSilver, false)
    local maxCopper = getVal(editBuyoutCopper, false)
    fl.maxBuyout = (maxGold * 10000) + (maxSilver * 100) + maxCopper

    fl.minDamage = getVal(editWeaponMin, false); fl.maxDamage = getVal(editWeaponMax, false)
    fl.minDPS = getVal(editDpsMin, true); fl.maxDPS = getVal(editDpsMax, true)
    fl.minSpeed = getVal(editSpeedMin, true); fl.maxSpeed = getVal(editSpeedMax, true)

    fl.minArmor = getVal(editArmorMin, false); fl.maxArmor = getVal(editArmorMax, false)

    fl.stats = {}
    for _, row in ipairs(statFilterRows) do
        local statName = row.editStat:GetText()
        if statName and statName ~= "" then
            table.insert(fl.stats, {
                name = statName,
                min = getVal(row.editMin, true),
                max = getVal(row.editMax, true)
            })
        end
    end
end

---------------------------------------------------------------------------
-- Item Cards & Virtual Scroll
---------------------------------------------------------------------------
local CARD_POOL_SIZE = 10
local CARD_HEIGHT = 96
local resultScrollFrame
local resultScrollChild

local function CreateItemCard(parent)
    local card = CreateFrame("Frame", nil, parent, BACKDROP_TEMPLATE)
    card:SetSize(parent:GetWidth() - 15, CARD_HEIGHT - 5)
    ApplyBackdrop(card, CARD_BACKDROP, 0.08, 0.08, 0.08, 0.95, 0.25, 0.25, 0.25, 0.8)

    local qStrip = card:CreateTexture(nil, "OVERLAY")
    qStrip:SetSize(4, CARD_HEIGHT - 11)
    qStrip:SetPoint("TOPLEFT", 3, -3)
    qStrip:SetColorTexture(1, 1, 1, 1)
    card.qStrip = qStrip

    local iconBtn = CreateFrame("Button", nil, card)
    iconBtn:SetSize(40, 40)
    iconBtn:SetPoint("TOPLEFT", 12, -8)
    local iconTex = iconBtn:CreateTexture(nil, "BACKGROUND")
    iconTex:SetAllPoints()
    card.iconTex = iconTex
    card.iconBtn = iconBtn

    iconBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if card.itemKey and GameTooltip.SetItemKey then
            GameTooltip:SetItemKey(card.itemKey.itemID, card.itemKey.itemLevel or 0, card.itemKey.itemSuffix or 0, card.itemKey.requiredLevel or 0)
        elseif card.itemLink then
            GameTooltip:SetHyperlink(card.itemLink)
        end
        GameTooltip:Show()
    end)
    iconBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    iconBtn:SetScript("OnClick", function()
        if card.itemLink and string.find(card.itemLink, "|H", 1, true) and IsModifiedClick() then
            HandleModifiedItemClick(card.itemLink)
        end
    end)

    card.nameText = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    card.nameText:SetPoint("TOPLEFT", 60, -8)
    card.nameText:SetJustifyH("LEFT")
    if card.nameText.SetWordWrap then card.nameText:SetWordWrap(false) end

    card.pawnBadge = CreateFrame("Button", nil, card, BACKDROP_TEMPLATE)
    card.pawnBadge:SetPoint("LEFT", card.nameText, "RIGHT", 8, 0)
    card.pawnBadge:SetHeight(16)
    ApplyBackdrop(card.pawnBadge, EDITBOX_BACKDROP, 0.1, 0.25, 0.05, 0.95, 0.4, 0.9, 0.2, 1)
    card.pawnBadgeText = card.pawnBadge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.pawnBadgeText:SetPoint("CENTER", 0, 0)
    card.pawnBadge:SetScript("OnClick", function()
        if AGS.SetSort then AGS:SetSort("pawn") end
    end)
    card.pawnBadge:SetScript("OnEnter", function(self)
        if not self.item then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText((L.TT_PAWN_TITLE or "Pawn Upgrade") .. (self.item.pawnScale and (" – " .. self.item.pawnScale) or ""), 0.71, 1, 0.17)
        if self.item.pawnUpgrade >= 9999 then
            GameTooltip:AddLine(L.TT_PAWN_DIRECT or "Direct upgrade (empty or 0-score slot)", 1, 1, 1)
        else
            GameTooltip:AddLine(string.format(L.TT_PAWN_PCT or "+%.1f%% score increase", self.item.pawnUpgrade), 1, 1, 1)
        end
        local existingLabel = FormatExistingItemLabel(self.item.pawnExisting)
        if existingLabel then
            GameTooltip:AddLine(string.format(L.TT_PAWN_REPLACES or "Replaces: %s", existingLabel), 0.8, 0.8, 0.8)
        end
        GameTooltip:AddLine(L.TT_PAWN_SORT_HINT or "Click to sort by Pawn upgrade", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    card.pawnBadge:SetScript("OnLeave", function() GameTooltip:Hide() end)
    card.pawnBadge:Hide()

    card.typeText = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.typeText:SetPoint("TOPLEFT", 60, -22)
    card.typeText:SetPoint("RIGHT", card, "RIGHT", -82, 0)
    card.typeText:SetJustifyH("LEFT")
    if card.typeText.SetWordWrap then card.typeText:SetWordWrap(false) end
    card.typeText:SetTextColor(0.6, 0.6, 0.6)

    card.baseStatsText = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.baseStatsText:SetPoint("TOPLEFT", 60, -36)

    card.pillContainer = CreateFrame("Frame", nil, card)
    card.pillContainer:SetPoint("TOPLEFT", 60, -50)
    card.pillContainer:SetPoint("BOTTOMRIGHT", -120, 5)
    card.pills = {}

    card.priceText = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    card.priceText:SetPoint("TOPRIGHT", -10, -10)
    card.priceText:SetJustifyH("RIGHT")

    card.qtyText = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.qtyText:SetPoint("TOPRIGHT", -10, -25)
    card.qtyText:SetTextColor(0.6, 0.6, 0.6)
    card.qtyText:SetJustifyH("RIGHT")

    card.buyBtn = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
    card.buyBtn:SetSize(80, 22)
    card.buyBtn:SetPoint("BOTTOMRIGHT", -10, 8)
    card.buyBtn:SetText(L.BTN_BUYOUT or "Buyout")

    return card
end

local function GetOrCreatePill(container, index)
    if not container.pills then container.pills = {} end
    if container.pills[index] then return container.pills[index] end

    local btn = CreateFrame("Button", nil, container, BACKDROP_TEMPLATE)
    if btn.RegisterForClicks then btn:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    ApplyBackdrop(btn, EDITBOX_BACKDROP, 0.12, 0.12, 0.12, 1, 0.35, 0.35, 0.35, 1)

    local text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("CENTER", 0, 0)
    btn.text = text

    container.pills[index] = btn
    return btn
end

local function AddCardPill(container, state, label, sortKey, filterLabel, tr, tg, tb)
    local pill = GetOrCreatePill(container, state.pIdx)
    pill:Show()
    pill.text:SetText(label)
    pill.text:SetTextColor(tr or 1, tg or 1, tb or 1)
    local pw = math.min(pill.text:GetStringWidth() + 10, state.maxW)
    pill:SetSize(pw, 16)

    if pill.SetBackdropBorderColor then
        if sortKey and AGS.SortKey == sortKey then
            pill:SetBackdropBorderColor(0.8, 0.8, 0.2, 1)
        else
            pill:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
        end
    end

    if sortKey then
        pill:SetScript("OnClick", function(_, button)
            if button == "RightButton" and filterLabel then
                FocusOrAddStatFilter(filterLabel)
            elseif AGS.SetSort then
                AGS:SetSort(sortKey)
            end
        end)
        pill:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(filterLabel or sortKey, 1, 0.82, 0)
            GameTooltip:AddLine(string.format(L.TT_PILL_SORT or "Left-click: Sort by %s", filterLabel or sortKey), 0.8, 0.8, 0.8)
            if filterLabel then
                GameTooltip:AddLine(string.format(L.TT_PILL_FILTER or "Right-click: Add filter for %s", filterLabel), 0.6, 1, 0.6)
            end
            GameTooltip:Show()
        end)
        pill:SetScript("OnLeave", function() GameTooltip:Hide() end)
    else
        pill:SetScript("OnClick", nil)
        pill:SetScript("OnEnter", nil)
        pill:SetScript("OnLeave", nil)
    end

    if not sortKey then
        if state.x > 0 then state.x = 0; state.y = state.y - 18 end
        pill:ClearAllPoints()
        pill:SetPoint("TOPLEFT", container, "TOPLEFT", 0, state.y)
        state.y = state.y - 18
    else
        if state.x + pw > state.maxW then
            state.x = 0
            state.y = state.y - 18
        end
        pill:ClearAllPoints()
        pill:SetPoint("TOPLEFT", container, "TOPLEFT", state.x, state.y)
        state.x = state.x + pw + 5
    end
    state.pIdx = state.pIdx + 1
end

local function PopulateCard(card, item)
    if not item then
        card:Hide()
        return
    end

    card.itemLink = item.link
    card.itemKey = item.itemKey
    card.iconTex:SetTexture(item.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
    local u = item.unusable
    if u and u.any then
        card.iconTex:SetVertexColor(1, 0.35, 0.35)
    else
        card.iconTex:SetVertexColor(1, 1, 1)
    end

    local r, g, b = GetQualityRGB(item.quality)
    card.qStrip:SetVertexColor(r, g, b)
    card.nameText:SetWidth(0)
    card.nameText:SetText(item.link or item.name)
    card.nameText:SetTextColor(r, g, b)

    -- Pawn Upgrade Badge anchored tight to item name and clamped clear of price column
    local cardW = card:GetWidth() or 480
    local reserveRight = 115
    if item.pawnUpgrade and item.pawnUpgrade > 0 then
        local shortScale = item.pawnScale and string.gsub(item.pawnScale, "^[^:]+:%s*", "") or ""
        local pctStr
        if item.pawnUpgrade >= 9999 then
            pctStr = (shortScale ~= "" and (shortScale .. " ") or "") .. (L.BADGE_UPGRADE or "Upgrade")
        else
            pctStr = string.format("+%d%%", math.floor(item.pawnUpgrade + 0.5)) .. (shortScale ~= "" and (" " .. shortScale) or "")
        end
        card.pawnBadgeText:SetText("|cFFb4fe2c" .. pctStr .. "|r")
        local badgeW = card.pawnBadgeText:GetStringWidth() + 12
        card.pawnBadge:SetWidth(badgeW)
        card.pawnBadge.item = item
        card.pawnBadge:Show()
        reserveRight = reserveRight + badgeW + 12
    else
        card.pawnBadge.item = nil
        card.pawnBadge:Hide()
    end

    local maxNameW = math.max(100, cardW - 60 - reserveRight)
    if (card.nameText:GetStringWidth() or 0) > maxNameW then
        card.nameText:SetWidth(maxNameW)
    end

    local slotDisplayName = GetSlotLabel(item.equipSlot)
    local subTypeText = item.itemSubType or ""
    if u and u.subType and subTypeText ~= "" then
        subTypeText = "|cFFFF4040" .. subTypeText .. "|r"
    end
    local extraOther = u and u.other or nil
    if extraOther and slotDisplayName ~= "" and string.lower(extraOther) == string.lower(slotDisplayName) then
        slotDisplayName = "|cFFFF4040" .. slotDisplayName .. "|r"
        extraOther = nil
    end
    local reqStr = ""
    if item.reqLevel and item.reqLevel > 0 then
        local lvlLabel = string.format(L.REQ_LVL_SHORT or "Req Lvl %d", item.reqLevel)
        if u and u.level then
            lvlLabel = "|cFFFF4040" .. lvlLabel .. "|r"
        end
        reqStr = "  •  " .. lvlLabel
    end
    local otherStr = extraOther and ("  •  |cFFFF4040" .. extraOther .. "|r") or ""
    local typeInfo = (item.itemType or "") .. " / " .. subTypeText .. (slotDisplayName ~= "" and (" / " .. slotDisplayName) or "") .. reqStr .. otherStr
    card.typeText:SetText(typeInfo)

    local baseStats = ""
    if item.parsed then
        if item.parsed.armor and item.parsed.armor > 0 then
            baseStats = baseStats .. string.format(L.ARMOR_INLINE or "%d Armor", item.parsed.armor) .. "  "
        end
        if item.parsed.block and item.parsed.block > 0 then
            baseStats = baseStats .. string.format(L.BLOCK_INLINE or "%d Block", item.parsed.block) .. "  "
        end
    end
    card.pillContainer:ClearAllPoints()
    if baseStats ~= "" then
        card.baseStatsText:SetText(baseStats)
        card.baseStatsText:Show()
        card.pillContainer:SetPoint("TOPLEFT", 60, -50)
    else
        card.baseStatsText:SetText("")
        card.baseStatsText:Hide()
        card.pillContainer:SetPoint("TOPLEFT", 60, -38)
    end
    card.pillContainer:SetPoint("BOTTOMRIGHT", -120, 5)

    -- Pills
    if card.pillContainer.pills then
        for _, p in ipairs(card.pillContainer.pills) do p:Hide() end
    end
    local maxW = card.pillContainer:GetWidth()
    if maxW <= 0 then maxW = 360 end
    local pillState = { pIdx = 1, x = 0, y = 0, maxW = maxW }

    if item.parsed then
        if item.parsed.dmgMin and item.parsed.dmgMin > 0 then
            AddCardPill(card.pillContainer, pillState, string.format(L.CARD_MIN_DMG or "Min Dmg %s", item.parsed.dmgMin), "min damage", GetStatDisplayName("min damage"))
        end
        if item.parsed.dmgMax and item.parsed.dmgMax > 0 then
            AddCardPill(card.pillContainer, pillState, string.format(L.CARD_MAX_DMG or "Max Dmg %s", item.parsed.dmgMax), "max damage", GetStatDisplayName("max damage"))
        end
        if item.parsed.dps and item.parsed.dps > 0 then
            AddCardPill(card.pillContainer, pillState, string.format(L.CARD_DPS or "%s DPS", item.parsed.dps), "dps", GetStatDisplayName("dps"))
        end
        if item.parsed.speed and item.parsed.speed > 0 then
            AddCardPill(card.pillContainer, pillState, string.format(L.CARD_SPEED or "Speed %s", item.parsed.speed), "speed", GetStatDisplayName("speed"))
        end
    end

    if item.parsed and item.parsed.stats then
        for statName, statVal in pairs(item.parsed.stats) do
            local label = FormatStatLabel(statName)
            AddCardPill(card.pillContainer, pillState, "+" .. statVal .. " " .. label, statName, label)
        end
    end

    if item.parsed and item.parsed.effects then
        for _, eff in ipairs(item.parsed.effects) do
            AddCardPill(card.pillContainer, pillState, eff, nil, nil, 0.2, 1, 0.2)
        end
    end

    card.priceText:SetText(FormatMoney(item.buyoutPrice))
    card.qtyText:SetText(string.format(L.QTY_AVAILABLE or "%d available", item.totalQuantity or 1))
    local rightColW = math.max(card.priceText:GetStringWidth() or 0, card.qtyText:GetStringWidth() or 0) + 20
    card.typeText:SetPoint("RIGHT", card, "RIGHT", -math.max(78, rightColW), 0)

    card.buyBtn:SetText(item.readyAuctionID and ("|cFF00FF00" .. (L.BTN_CONFIRM_BUY or "Confirm Buy") .. "|r") or (L.BTN_BUYOUT or "Buyout"))
    card.buyBtn:SetScript("OnClick", function()
        if AGS.QuickBuyOrInspect then
            AGS:QuickBuyOrInspect(item)
        end
    end)

    card:Show()
end

local function GetVisibleCardCount()
    local h = resultScrollChild and resultScrollChild:GetHeight() or 0
    if h <= 0 and rightPanel then
        h = (rightPanel:GetHeight() or 0) - 36
    end
    if h <= 0 then h = 414 end
    return math.max(1, math.min(CARD_POOL_SIZE, math.floor((h - 5) / CARD_HEIGHT)))
end

local function UpdateSortBar()
    if not sortBar then return end
    local dirArrow = AGS.SortDescending and " v" or " ^"
    for _, btn in ipairs(sortButtons) do
        local isActive = (AGS.SortKey == btn.sortKey)
        if btn.SetBackdropBorderColor then
            if isActive then
                btn:SetBackdropBorderColor(0.85, 0.75, 0.2, 1)
            else
                btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
            end
        end
        btn.text:SetText(btn.baseLabel .. (isActive and dirArrow or ""))
        if isActive then
            btn.text:SetTextColor(1, 0.85, 0.2)
        else
            btn.text:SetTextColor(0.8, 0.8, 0.8)
        end
    end

    if sortActiveText then
        local count = AGS.Results and #AGS.Results or 0
        local sortName
        if AGS.SortKey == "buyout" then sortName = L.SORT_PRICE or "Price"
        elseif AGS.SortKey == "pawn" then sortName = L.SORT_PAWN or "Pawn %"
        elseif AGS.SortKey == "name" then sortName = L.SORT_NAME or "Name"
        else sortName = FormatStatLabel(AGS.SortKey or "")
        end
        sortActiveText:SetText(string.format(L.SORT_SUMMARY or "%d results  •  Sort: %s%s", count, sortName, dirArrow))
    end
end

local function CreateSortBar(parent)
    local bar = CreateFrame("Frame", nil, parent, BACKDROP_TEMPLATE)
    bar:SetPoint("TOPLEFT", 5, -5)
    bar:SetPoint("TOPRIGHT", -5, -5)
    bar:SetHeight(24)
    ApplyBackdrop(bar, EDITBOX_BACKDROP, 0.08, 0.08, 0.08, 0.95, 0.22, 0.22, 0.22, 1)

    local lbl = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("LEFT", 8, 0)
    lbl:SetText(L.SORT_PREFIX or "Sort:")

    local defs = {
        { key = "buyout", label = L.SORT_PRICE or "Price" },
        { key = "name",   label = L.SORT_NAME or "Name" },
    }
    if AGS.HasPawn and AGS:HasPawn() then
        table.insert(defs, 2, { key = "pawn", label = L.SORT_PAWN or "Pawn %" })
    end

    sortButtons = {}
    local x = math.max(42, (lbl:GetStringWidth() or 30) + 14)
    for _, def in ipairs(defs) do
        local btn = CreateFrame("Button", nil, bar, BACKDROP_TEMPLATE)
        btn:SetPoint("LEFT", x, 0)
        btn:SetHeight(18)
        ApplyBackdrop(btn, EDITBOX_BACKDROP, 0.14, 0.14, 0.14, 1, 0.3, 0.3, 0.3, 1)

        local txt = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        txt:SetPoint("CENTER", 0, 0)
        txt:SetText(def.label)
        btn.text = txt
        btn.baseLabel = def.label
        btn.sortKey = def.key

        local w = math.max(46, (txt:GetStringWidth() or 32) + 20)
        btn:SetWidth(w)
        btn:SetScript("OnClick", function()
            if AGS.SetSort then AGS:SetSort(def.key) end
        end)
        table.insert(sortButtons, btn)
        x = x + w + 5
    end

    sortActiveText = bar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sortActiveText:SetPoint("RIGHT", -8, 0)
    sortActiveText:SetJustifyH("RIGHT")

    sortBar = bar
    UpdateSortBar()
end

local function RefreshVisibleCards()
    if not resultScrollFrame or not AGS.Results then return end

    local visibleCount = GetVisibleCardCount()
    local totalResults = #AGS.Results
    local offset = FauxScrollFrame_GetOffset(resultScrollFrame)

    FauxScrollFrame_Update(resultScrollFrame, totalResults, visibleCount, CARD_HEIGHT)

    local cardWidth = rightPanel:GetWidth() - 35
    for i = 1, CARD_POOL_SIZE do
        local card = cards[i]
        if card then
            local dataIndex = offset + i
            if i <= visibleCount and dataIndex <= totalResults then
                if cardWidth > 100 then card:SetWidth(cardWidth) end
                card:ClearAllPoints()
                card:SetPoint("TOPLEFT", resultScrollChild, "TOPLEFT", 5, -((i - 1) * CARD_HEIGHT) - 5)
                PopulateCard(card, AGS.Results[dataIndex])
            else
                card:Hide()
            end
        end
    end
end

function UI:UpdateResults()
    if not isInitialized then return end
    for _, card in ipairs(cards) do card:Hide() end
    UpdateSortBar()

    if not AGS.Results or #AGS.Results == 0 then
        if resultScrollFrame then
            FauxScrollFrame_Update(resultScrollFrame, 0, GetVisibleCardCount(), CARD_HEIGHT)
        end
        if emptyText then
            if AGS.IsScanning then
                emptyText:Hide()
            else
                emptyText:SetText(hasSearched and (L.EMPTY_NONE or "No matching gear found. Try broadening your filters.") or (L.EMPTY_INITIAL or "Select filters on the left and click Search AH."))
                emptyText:Show()
            end
        end
        return
    end
    if emptyText then emptyText:Hide() end
    RefreshVisibleCards()
end

function UI:SetStatus(text)
    if txtStatus then txtStatus:SetText(text) end
end

---------------------------------------------------------------------------
-- Tab Creation (Supports Retail/Forever AuctionHouseFrame & LibAHTab)
---------------------------------------------------------------------------
local function AttachToAuctionHouse()
    if not AuctionHouseFrame then return nil end

    mainFrame = CreateFrame("Frame", "FGS_MainFrame", AuctionHouseFrame, BACKDROP_TEMPLATE)
    mainFrame:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPLEFT", 15, -70)
    mainFrame:SetPoint("BOTTOMRIGHT", AuctionHouseFrame, "BOTTOMRIGHT", -15, 35)
    mainFrame:SetFrameLevel(AuctionHouseFrame:GetFrameLevel() + 10)
    mainFrame:Hide()

    local LibAHTab = LibStub and LibStub("LibAHTab-1-0", true)
    if LibAHTab then
        if not LibAHTab:DoesIDExist("ForeverGearScanner") then
            LibAHTab:CreateTab("ForeverGearScanner", mainFrame, L.TAB_SHORT or "Gear Scanner", L.TAB_HEADER or "Forever Gear Scanner")
        end
    elseif AuctionHouseFrame.Tabs then
        local numTabs = #AuctionHouseFrame.Tabs + 1
        local prevTab = AuctionHouseFrame.Tabs[#AuctionHouseFrame.Tabs]
        local tabName = _G["FGS_AuctionHouseTab"] and ("FGS_AuctionHouseTab" .. numTabs) or "FGS_AuctionHouseTab"
        local tab = CreateFrame("Button", tabName, AuctionHouseFrame, "AuctionHouseFrameDisplayModeTabTemplate")
        tab:SetID(numTabs)
        tab:SetText(L.TAB_SHORT or "Gear Scanner")
        if prevTab and prevTab ~= tab then
            tab:SetPoint("LEFT", prevTab, "RIGHT", 3, 0)
        else
            tab:SetPoint("TOPLEFT", AuctionHouseFrame, "BOTTOMLEFT", 15, 2)
        end
        PanelTemplates_TabResize(tab, 20, nil, 70)
        PanelTemplates_DeselectTab(tab)

        local selectingOurTab = false
        hooksecurefunc(AuctionHouseFrame, "SetDisplayMode", function()
            if not selectingOurTab then
                mainFrame:Hide()
                PanelTemplates_DeselectTab(tab)
            end
        end)

        tab:SetScript("OnClick", function()
            selectingOurTab = true
            if AuctionHouseFrame.SetDisplayMode then
                AuctionHouseFrame:SetDisplayMode({})
            end
            selectingOurTab = false
            for _, t in ipairs(AuctionHouseFrame.Tabs) do
                PanelTemplates_DeselectTab(t)
            end
            PanelTemplates_SelectTab(tab)
            if AuctionHouseFrame.SetTitle then
                AuctionHouseFrame:SetTitle(L.TAB_HEADER or "Forever Gear Scanner")
            end
            mainFrame:Show()
        end)
    end

    return mainFrame
end

---------------------------------------------------------------------------
-- Initialize
---------------------------------------------------------------------------
function UI:Initialize()
    if isInitialized then return end
    if not AuctionHouseFrame then return end

    if not AttachToAuctionHouse() then return end

    leftPanel = CreateFrame("Frame", nil, mainFrame, BACKDROP_TEMPLATE)
    leftPanel:SetPoint("TOPLEFT", 0, 0)
    leftPanel:SetPoint("BOTTOMLEFT", 0, 0)
    leftPanel:SetWidth(260)
    ApplyBackdrop(leftPanel, PANEL_BACKDROP, 0.04, 0.04, 0.04, 0.95, 0.2, 0.2, 0.2, 1)

    rightPanel = CreateFrame("Frame", nil, mainFrame, BACKDROP_TEMPLATE)
    rightPanel:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", 5, 0)
    rightPanel:SetPoint("BOTTOMRIGHT", 0, 0)
    ApplyBackdrop(rightPanel, PANEL_BACKDROP, 0.04, 0.04, 0.04, 0.95, 0.2, 0.2, 0.2, 1)

    local lpScroll = CreateFrame("ScrollFrame", "FGS_LeftScroll", leftPanel, "UIPanelScrollFrameTemplate")
    lpScroll:SetPoint("TOPLEFT", 5, -5)
    lpScroll:SetPoint("BOTTOMRIGHT", -25, 40)
    StripScrollbar(lpScroll)

    lpScrollChild = CreateFrame("Frame", nil, lpScroll)
    lpScrollChild:SetSize(230, 900)
    lpScroll:SetScrollChild(lpScrollChild)

    CreateTypeFilters(lpScrollChild)
    CreateWeaponFilters(lpScrollChild)
    CreateArmorFilters(lpScrollChild)
    CreateRequirements(lpScrollChild)
    CreateStatFilters(lpScrollChild)

    LayoutFilterPanel()
    UpdateContextualFilters()

    btnSearch = CreateFrame("Button", nil, leftPanel, "UIPanelButtonTemplate")
    btnSearch:SetSize(116, 25)
    btnSearch:SetPoint("BOTTOMLEFT", 10, 10)
    btnSearch:SetText(L.BTN_SEARCH or "Search AH")
    btnSearch:SetScript("OnClick", function()
        hasSearched = true
        SyncFiltersFromUI()
        if AGS.StartSearch then AGS:StartSearch() end
    end)

    btnClear = CreateFrame("Button", nil, leftPanel, "UIPanelButtonTemplate")
    btnClear:SetSize(116, 25)
    btnClear:SetPoint("BOTTOMRIGHT", -10, 10)
    btnClear:SetText(L.BTN_CLEAR or "Clear Filters")
    btnClear:SetScript("OnClick", ClearFilters)

    txtStatus = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    txtStatus:SetPoint("BOTTOMLEFT", mainFrame, "TOPLEFT", 5, 5)
    txtStatus:SetText(L.STATUS_READY or "Ready.")

    CreateSortBar(rightPanel)

    resultScrollChild = CreateFrame("Frame", nil, rightPanel)
    resultScrollChild:SetPoint("TOPLEFT", 5, -31)
    resultScrollChild:SetPoint("BOTTOMRIGHT", -25, 5)
    if resultScrollChild.SetClipsChildren then
        resultScrollChild:SetClipsChildren(true)
    end
    rightPanel:SetScript("OnSizeChanged", RefreshVisibleCards)

    emptyText = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyText:SetPoint("CENTER", resultScrollChild, "CENTER", 0, 0)
    emptyText:SetText(L.EMPTY_INITIAL or "Select filters on the left and click Search AH.")

    resultScrollFrame = CreateFrame("ScrollFrame", "FGS_ResultScroll", resultScrollChild, "FauxScrollFrameTemplate")
    resultScrollFrame:SetPoint("TOPLEFT", 0, 0)
    resultScrollFrame:SetPoint("BOTTOMRIGHT", 0, 0)
    resultScrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, CARD_HEIGHT, RefreshVisibleCards)
    end)

    local cardWidth = math.max(400, rightPanel:GetWidth() - 35)
    for i = 1, CARD_POOL_SIZE do
        local card = CreateItemCard(resultScrollChild)
        card:SetWidth(cardWidth)
        card:SetHeight(CARD_HEIGHT - 5)
        card:Hide()
        table.insert(cards, card)
    end

    isInitialized = true
    UI.initialized = true
end
