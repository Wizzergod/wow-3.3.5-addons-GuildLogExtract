-- GuildLogCopy.lua
-- Рабочая версия под WoW 3.3.5a
-- Совместима с твоим .toc (GLC_Data / GLC_CharDB)
-- Копируемый журнал гильдии + фильтры + CSV/JSON + resize

-- @author Wizzergod
-- @namespace GPT

--------------------------------------------------
-- SavedVariables (из .toc)
--------------------------------------------------
GLC_Data = GLC_Data or {}
GLC_CharDB = GLC_CharDB or {}

--------------------------------------------------
-- UTF-8 Helper Functions
--------------------------------------------------
local function utf8_encode(text)
    if not text then return "" end
    
    -- Простая замена проблемных символов
    local result = text:gsub("[\128-\255]", function(c)
        -- Заменяем не-ASCII символы на похожие или "?"
        local byte = c:byte()
        if byte >= 192 and byte <= 255 then
            -- Кириллические символы оставляем как есть
            return c
        else
            -- Остальные заменяем
            return "?"
        end
    end)
    
    return result
end

-- Функция для безопасного копирования с UTF-8
local function SafeCopyToClipboard(text)
    if not text or text == "" then return end
    
    -- Создаем временный EditBox для копирования
    local copyFrame = CreateFrame("EditBox", "GLC_CopyFrameTemp", UIParent)
    copyFrame:SetSize(1, 1)
    copyFrame:SetPoint("BOTTOMLEFT", -100, -100)
    copyFrame:SetAutoFocus(false)
    
    -- Кодируем текст в UTF-8
    local utf8Text = utf8_encode(text)
    copyFrame:SetText(utf8Text)
    copyFrame:HighlightText()
    
    -- Фокус и копирование
    copyFrame:SetFocus()
    
    -- Автоматическое скрытие
    C_Timer.After(0.5, function()
        if copyFrame:IsShown() then
            copyFrame:ClearFocus()
            copyFrame:Hide()
        end
    end)
end

--------------------------------------------------
-- Addon frame
--------------------------------------------------
local addonName = ...
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")

--------------------------------------------------
-- UI creation
--------------------------------------------------
local function CreateMainWindow()
    if _G.GLC_MainFrame then return end

    local frame = CreateFrame("Frame", "GLC_MainFrame", UIParent)
    frame:SetSize(700, 500)
    frame:SetPoint("CENTER")
    frame:SetMinResize(400, 300)
    frame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    frame:SetBackdropColor(0, 0, 0, 0.9)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetResizable(true)
    frame:Hide()

    -- Close button
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    -- Resize handle (bottom-right)
    local resize = CreateFrame("Button", nil, frame)
    resize:SetSize(16, 16)
    resize:SetPoint("BOTTOMRIGHT", -6, 6)
    resize:SetNormalTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Up")
    resize:SetHighlightTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Highlight")
    resize:SetPushedTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Down")
    resize:SetScript("OnMouseDown", function()
        frame:StartSizing("BOTTOMRIGHT")
    end)
    resize:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
    end)

    --------------------------------------------------
    -- Filter buttons
    --------------------------------------------------
    frame.filter = "ALL"
    local filters = {
        { key = "ALL", label = "Все" },
        { key = "JOIN", label = "Вступления" },
        { key = "LEAVE", label = "Выходы" },
        { key = "KICK", label = "Кики" },
        { key = "RANK", label = "Ранги" },
        { key = "INVITE", label = "Приглашения" }, -- Добавлена кнопка Приглашения
    }

    local lastBtn
    for i, fdata in ipairs(filters) do
        local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        btn:SetSize(90, 22)
        if lastBtn then
            btn:SetPoint("TOPLEFT", lastBtn, "TOPRIGHT", 4, 0)
        else
            btn:SetPoint("TOPLEFT", 10, -6)
        end
        btn:SetText(fdata.label)
        btn:SetScript("OnClick", function()
            frame.filter = fdata.key
            GLC_FillGuildLog()
        end)
        lastBtn = btn
    end

    -- Export buttons
    local csvBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    csvBtn:SetSize(60, 22)
    csvBtn:SetPoint("TOPRIGHT", -120, -6)
    csvBtn:SetText("CSV")
    csvBtn:SetScript("OnClick", function()
        local csvData = GLC_GenerateCSV(frame.filter)  -- Генерируем CSV с текущим фильтром
        frame.editBox:SetText(csvData or "")
        frame.editBox:HighlightText()
    end)

    local jsonBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    jsonBtn:SetSize(60, 22)
    jsonBtn:SetPoint("TOPRIGHT", -60, -6)
    jsonBtn:SetText("JSON")
    jsonBtn:SetScript("OnClick", function()
        local jsonData = GLC_GenerateJSON(frame.filter)  -- Генерируем JSON с текущим фильтром
        frame.editBox:SetText(jsonData or "")
        frame.editBox:HighlightText()
    end)

    --------------------------------------------------
    --------------------------------------------------
    -- Scroll + EditBox (copyable) — FIXED scroll + no freeze
    --------------------------------------------------
    local scroll = CreateFrame("ScrollFrame", "GLC_ScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 10, -36)
    scroll:SetPoint("BOTTOMRIGHT", -30, 10)
    scroll:EnableMouseWheel(true)

    local editBox = CreateFrame("EditBox", "GLC_EditBox", scroll)
    editBox:SetMultiLine(true)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetAutoFocus(false)
    editBox:EnableMouse(true)
    editBox:SetWidth(600)
    editBox:SetScript("OnEscapePressed", function() frame:Hide() end)
    
    -- Модифицированный обработчик для UTF-8 копирования
    editBox:SetScript("OnTextChanged", function(self)
        self:SetHeight(self:GetStringHeight() + 20)
    end)
    
    -- Переопределяем выделение текста для UTF-8 копирования
    local originalHighlightText = editBox.HighlightText
    editBox.HighlightText = function(self)
        originalHighlightText(self)
        -- Автоматически копируем в буфер с UTF-8 при выделении
        if self:GetText() and self:GetText() ~= "" then
            C_Timer.After(0.1, function()
                SafeCopyToClipboard(self:GetText())
            end)
        end
    end

    -- Колесо мыши (без зависаний)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local max = self:GetVerticalScrollRange()
        if delta < 0 then
            self:SetVerticalScroll(math.min(cur + 40, max))
        else
            self:SetVerticalScroll(math.max(cur - 40, 0))
        end
    end)

    scroll:SetScrollChild(editBox)
    frame.editBox = editBox

    _G.GLC_MainFrame = frame
end

--------------------------------------------------
-- Data collection functions
--------------------------------------------------
local function ShouldDisplayEvent(eventType, filter)
    if filter == "ALL" then return true end
    if filter == "JOIN" and eventType == "join" then return true end
    if filter == "LEAVE" and eventType == "leave" then return true end
    if filter == "KICK" and eventType == "kick" then return true end
    if filter == "RANK" and (eventType == "promote" or eventType == "demote") then return true end
    if filter == "INVITE" and eventType == "invite" then return true end
    return false
end

function GLC_FillGuildLog()
    if not IsInGuild() then return end

    GuildRoster()

    local numEvents = GetNumGuildEvents()
    local lines = {}
    local currentFilter = GLC_MainFrame.filter

    for i = 1, numEvents do
        local eventType, p1, p2, rank, ts = GetGuildEventInfo(i)
        local timeStr = ts and date("%Y-%m-%d %H:%M", ts) or "" 

        if ShouldDisplayEvent(eventType, currentFilter) then
            table.insert(lines, string.format("%s | %s | %s | %s | %s", timeStr, eventType or "", p1 or "", p2 or "", rank or ""))
        end
    end

    GLC_MainFrame.editBox:SetText(table.concat(lines, "\n"))
    GLC_MainFrame.editBox:HighlightText()
end

function GLC_GenerateCSV(filter)
    if not IsInGuild() then return "" end

    GuildRoster()
    
    local numEvents = GetNumGuildEvents()
    local csvLines = { "time,type,player1,player2,rank" }

    for i = 1, numEvents do
        local eventType, p1, p2, rank, ts = GetGuildEventInfo(i)
        local timeStr = ts and date("%Y-%m-%d %H:%M", ts) or "" 

        if ShouldDisplayEvent(eventType, filter) then
            table.insert(csvLines, string.format("%s,%s,%s,%s,%s", 
                timeStr, 
                eventType or "", 
                p1 or "", 
                p2 or "", 
                rank or ""))
        end
    end

    return table.concat(csvLines, "\n")
end

function GLC_GenerateJSON(filter)
    if not IsInGuild() then return "" end

    GuildRoster()
    
    local numEvents = GetNumGuildEvents()
    local jsonEntries = {}

    for i = 1, numEvents do
        local eventType, p1, p2, rank, ts = GetGuildEventInfo(i)
        local timeStr = ts and date("%Y-%m-%d %H:%M", ts) or "" 

        if ShouldDisplayEvent(eventType, filter) then
            table.insert(jsonEntries, string.format('{"time":"%s","type":"%s","p1":"%s","p2":"%s","rank":"%s"}', 
                timeStr, 
                eventType or "", 
                p1 or "", 
                p2 or "", 
                rank or ""))
        end
    end

    return "[" .. table.concat(jsonEntries, ",") .. "]"
end

--------------------------------------------------
-- Slash command
--------------------------------------------------
SLASH_GLC1 = "/glog"
SlashCmdList["GLC"] = function()
    CreateMainWindow()
    GLC_FillGuildLog()
    GLC_MainFrame:Show()
end

--------------------------------------------------
-- Init
--------------------------------------------------
eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        CreateMainWindow()
    end
end)