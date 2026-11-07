-- ForeverGuild v1.10.0 - Gilden-Addon fuer WoW Forever
-- Alle Mitglieder brauchen das Addon, damit sie auf der Karte erscheinen.

local PREFIX = "FGUILD"
local DOT = "Interface\\AddOns\\ForeverGuild\\dot"
local members, profs, pings = {}, {}, {}
local DB
local myName = UnitName("player")
local GUILDNAME = "Kritisch Ungemütlich"
local BRAND = "|cffff7a1a" .. GUILDNAME .. "|r"
local rankCache = {}
local groupSet = {}
local function rebuildGroup()
  wipe(groupSet)
  if not (IsInGroup and IsInGroup()) then return end
  local raid = IsInRaid and IsInRaid()
  local n = GetNumGroupMembers and GetNumGroupMembers() or 0
  for i = 1, (raid and n or n - 1) do
    local unit = (raid and "raid" or "party") .. i
    local ok, nm = pcall(UnitName, unit)
    if ok and type(nm) == "string" then groupSet[(strsplit("-", nm))] = true end
  end
end
local fullCache = {}
local function fullName(n)
  local m = members[n]
  return fullCache[n] or (m and m.full) or n
end
local function invitePlayer(name)
  if C_PartyInfo and C_PartyInfo.InviteUnit then C_PartyInfo.InviteUnit(name)
  elseif InviteUnit then InviteUnit(name) end
end
local function whisperTo(name)
  if ChatFrameUtil and ChatFrameUtil.SendTell then ChatFrameUtil.SendTell(name)
  elseif ChatFrame_SendTell then ChatFrame_SendTell(name) end
end
local flushPending
local function scheduleFlush()
  -- LoggingChat(false) kann den Forever-Chatlog leeren/rotieren. Nicht
  -- automatisch toggeln; der Spieler aktiviert das Logging einmal per /chatlog.
end
local function sendChat(msg, channel)
  if C_ChatInfo and C_ChatInfo.SendChatMessage then C_ChatInfo.SendChatMessage(msg, channel)
  elseif SendChatMessage then SendChatMessage(msg, channel) end
  if type(msg) == "string" and msg:sub(1, 4) == "[KU]" then scheduleFlush() end
end
local openSettings
local THEME = {
  bg = { 0.035, 0.035, 0.055, 0.98 },
  header = { 0.08, 0.07, 0.12, 1 },
  panel = { 0.075, 0.07, 0.095, 1 },
  panelAlt = { 0.11, 0.085, 0.12, 1 },
  border = { 0.55, 0.25, 0.06, 0.9 },
  accent = { 1, 0.48, 0.1, 1 },
  text = { 0.92, 0.9, 0.86, 1 },
  muted = { 0.56, 0.54, 0.6, 1 },
}
local function themeTexture(parent, layer, color)
  local t = parent:CreateTexture(nil, layer)
  if t.SetColorTexture then t:SetColorTexture(color[1], color[2], color[3], color[4])
  else t:SetTexture(color[1], color[2], color[3], color[4]) end
  return t
end

local function out(msg) DEFAULT_CHAT_FRAME:AddMessage("|cffff7a1a[" .. GUILDNAME .. "]|r " .. tostring(msg)) end
local function short(n) if not n then return n end return (strsplit("-", n)) end
local function isLocalMember(n)
  return n and myName and short(n) == short(myName)
end
local function setColor(tex, r, g, b, a)
  if tex.SetColorTexture then tex:SetColorTexture(r, g, b, a) else tex:SetTexture(r, g, b, a) end
end
local function classRGB(file)
  local c = file and RAID_CLASS_COLORS and RAID_CLASS_COLORS[file]
  if c then return c.r, c.g, c.b end
  return 0.8, 0.8, 0.8
end
local function classHex(file)
  local r, g, b = classRGB(file)
  return string.format("|cff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

------------------------------------------------------------------ Comms
local function send(msg)
  if not IsInGuild() then return end
  if C_ChatInfo and C_ChatInfo.SendAddonMessage then
    C_ChatInfo.SendAddonMessage(PREFIX, msg, "GUILD")
  elseif SendAddonMessage then
    SendAddonMessage(PREFIX, msg, "GUILD")
  end
end

------------------------------------------------------------------ Position
local function getPos()
  if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return end
  local m = C_Map.GetBestMapForUnit("player")
  if not m then return end
  local p = C_Map.GetPlayerMapPosition(m, "player")
  if not p then return end
  local x, y = p:GetXY()
  if not x or (x == 0 and y == 0) then return end
  return m, x, y
end

-- Retail/modern clients can return secret values from UnitHealth and
-- UnitHealthMax during combat. Never do arithmetic on those values.
local function safeHealthPercent(unit)
  if UnitHealthPercent then
    local ok, pct
    if CurveConstants and CurveConstants.ScaleTo100 then
      ok, pct = pcall(UnitHealthPercent, unit, false, CurveConstants.ScaleTo100)
    else
      ok, pct = pcall(UnitHealthPercent, unit, false)
    end
    if ok then
      local okNumber, number = pcall(function() return pct + 0 end)
      if okNumber and type(number) == "number" then return number end
    end
  end

  -- Legacy fallback for the Forever client. If the values are secret, the
  -- protected calculation fails quietly and the caller keeps the last value.
  if InCombatLockdown and InCombatLockdown() then return end
  local ok, pct = pcall(function()
    local max = UnitHealthMax(unit)
    if max and max > 0 then return UnitHealth(unit) / max * 100 end
  end)
  if ok and type(pct) == "number" then return pct end
end

local function broadcastPos()
  local m, x, y = getPos()
  if not m then return end
  local _, file = UnitClass("player")
  local lvl = UnitLevel("player")
  local hp = math.floor((safeHealthPercent("player") or (members[myName] and members[myName].hp) or 100) + 0.5)
  members[myName] = { map = m, x = x, y = y, file = file, level = lvl, hp = hp, t = GetTime() }
  send(string.format("P:%d:%.4f:%.4f:%s:%d:%d", m, x, y, file or "", lvl, hp))
end

------------------------------------------------------------------ Berufe
local PROFS = {}
for _, n in ipairs({ "Alchemy", "Alchemie", "Blacksmithing", "Schmiedekunst", "Enchanting", "Verzauberkunst",
  "Engineering", "Ingenieurskunst", "Herbalism", "Kräuterkunde", "Leatherworking", "Lederverarbeitung",
  "Mining", "Bergbau", "Skinning", "Kürschnerei", "Tailoring", "Schneiderei", "Cooking", "Kochkunst",
  "First Aid", "Erste Hilfe", "Fishing", "Angeln", "Jewelcrafting", "Juwelenschleifen",
  "Inscription", "Inschriftenkunde" }) do PROFS[n] = true end

local function getSkillLineCount()
  if not (C_SkillInfo and C_SkillInfo.GetNumSkillLines) then return 0 end
  local ok, n = pcall(C_SkillInfo.GetNumSkillLines)
  return ok and type(n) == "number" and n or 0
end

local function getSkillLine(i)
  if not (C_SkillInfo and C_SkillInfo.GetSkillLineInfo) then return end
  local ok, info = pcall(C_SkillInfo.GetSkillLineInfo, i)
  if not ok or type(info) ~= "table" then return end
  return info.name, info.isHeader, info.rank, info.maxRank, info.skillID
end

local function broadcastProfs()
  local count = getSkillLineCount()
  if count <= 0 then return end
  local list = {}
  for i = 1, count do
    local name, isHeader, rank = getSkillLine(i)
    if name and not isHeader and PROFS[name] then list[#list + 1] = name .. "=" .. (rank or 0) end
  end
  if #list > 0 then
    local s = table.concat(list, ";")
    profs[myName] = s
    if DB then DB.profs[myName] = s end
    send("R:" .. s)
  end
end

local function profText(name)
  return profs[name] and profs[name]:gsub("=", " "):gsub(";", ", ") or nil
end

------------------------------------------------------------------ Karte: Canvas & Pins
local function getCanvas()
  if not WorldMapFrame then return end
  if WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child then
    return WorldMapFrame.ScrollContainer.Child
  end
  return WorldMapButton
end

local function viewedMap()
  if WorldMapFrame and WorldMapFrame.GetMapID then return WorldMapFrame:GetMapID() end
  if C_Map and C_Map.GetBestMapForUnit then return C_Map.GetBestMapForUnit("player") end
end

local pinPool, pingPool, miniPool = {}, {}, {}

local function passFilter(d)
  local s = DB.set
  if s.filter == "range" then
    return d.level and d.level >= s.minL and d.level <= s.maxL
  elseif s.filter == "rel" then
    local my = UnitLevel("player")
    return d.level and d.level >= my - s.below and d.level <= my + s.above
  end
  return true
end

-- Rechnet eine Position von einer Karte auf eine andere um (z. B. Stadt-Karte -> Kontinent-Karte)
local function projectToMap(fromMap, x, y, toMap)
  if not fromMap or not toMap then return end
  if fromMap == toMap then return x, y end
  if not (C_Map and C_Map.GetWorldPosFromMapPos and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return end
  local ok, px, py = pcall(function()
    local inst, wpos = C_Map.GetWorldPosFromMapPos(fromMap, CreateVector2D(x, y))
    if not inst or not wpos then return end
    local _, mpos = C_Map.GetMapPosFromWorldPos(inst, wpos, toMap)
    if not mpos then return end
    return mpos:GetXY()
  end)
  if not ok or not px or not py then return end
  if px < 0 or px > 1 or py < 0 or py > 1 then return end
  return px, py
end

local function newPin(canvas, big, withLabel, mouse)
  local f = CreateFrame("Frame", nil, canvas)
  f:SetFrameLevel(canvas:GetFrameLevel() + 60)
  f:SetSize(big and 30 or 13, big and 30 or 13)
  f.tex = f:CreateTexture(nil, "OVERLAY")
  f.tex:SetAllPoints()
  f.tex:SetTexture(DOT)
  if withLabel then
    f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.label:SetPoint("TOP", f, "BOTTOM", 0, -1)
  end
  if not big then
    f:EnableMouse(mouse and true or false)
    if mouse then
      f:SetScript("OnEnter", function(self)
        local d = members[self.name]
        if not d then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local cname = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[d.file]) or d.file or "?"
        GameTooltip:AddLine(classHex(d.file) .. self.name .. "|r")
        GameTooltip:AddLine("Level " .. (d.level or "?") .. " " .. cname, 1, 1, 1)
        if rankCache[self.name] then GameTooltip:AddLine("<" .. rankCache[self.name] .. ">", 0.4, 0.8, 1) end
        if d.hp then GameTooltip:AddLine("Leben: " .. d.hp .. "%", 0.8, 0.8, 0.8) end
        local zi = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(d.map)
        if zi and zi.name then GameTooltip:AddLine(zi.name, 0.6, 0.6, 0.6) end
        local p = profText(self.name)
        if p then GameTooltip:AddLine(p, 0.8, 0.8, 0.8, true) end
        if self.name ~= myName then GameTooltip:AddLine("Links: Flüstern   Rechts: Einladen", 0.5, 0.5, 0.5) end
        GameTooltip:Show()
      end)
      f:SetScript("OnLeave", function() GameTooltip:Hide() end)
      f:SetScript("OnMouseUp", function(self, btn)
        if not self.name or self.name == myName then return end
        local target = fullName(self.name)
        if btn == "LeftButton" then
          whisperTo(target)
        elseif btn == "RightButton" then
          invitePlayer(target)
          out("Einladung an " .. self.name .. " gesendet.")
        end
      end)
    end
  else
    f:SetScript("OnUpdate", function(self)
      self.tex:SetAlpha(0.5 + 0.5 * math.sin(GetTime() * 6))
    end)
  end
  return f
end

local function styleTex(tex, file)
  if DB.set.icons and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[file] then
    tex:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
    tex:SetTexCoord(unpack(CLASS_ICON_TCOORDS[file]))
    tex:SetVertexColor(1, 1, 1)
  else
    tex:SetTexture(DOT)
    tex:SetTexCoord(0, 1, 0, 1)
    tex:SetVertexColor(classRGB(file))
  end
end

local function labelText(name, d)
  local s, parts = DB.set, {}
  if s.showName then parts[#parts + 1] = name end
  if s.showLevel and d.level then parts[#parts + 1] = "L" .. d.level end
  if s.showRank and rankCache[name] then parts[#parts + 1] = "<" .. rankCache[name] .. ">" end
  if s.showHealth and d.hp then parts[#parts + 1] = d.hp .. "%" end
  return table.concat(parts, " ")
end

local function updatePins()
  local canvas = getCanvas()
  local show = canvas and WorldMapFrame:IsShown()
  for _, p in ipairs(pinPool) do p:Hide() end
  for _, p in ipairs(pingPool) do p:Hide() end
  if not show or not DB.set.dots then return end
  local mid, w, h, now = viewedMap(), canvas:GetWidth(), canvas:GetHeight(), GetTime()
  local sz = DB.set.iconSize
  local fpath = (GameFontNormalSmall and GameFontNormalSmall:GetFont()) or STANDARD_TEXT_FONT
  local fsize = (DB.set.labelSize and DB.set.labelSize > 0) and DB.set.labelSize or math.max(9, math.floor(sz * 0.85 + 0.5))
  local i = 0
  for name, d in pairs(members) do
    local mx, my
    if now - d.t < (DB.interval * 3 + 10) and (name == myName or passFilter(d)) and not (DB.set.hideGroup and groupSet[name]) then
      mx, my = projectToMap(d.map, d.x, d.y, mid)
    end
    if mx then
      i = i + 1
      local p = pinPool[i]
      if not p then p = newPin(canvas, false, true, true); pinPool[i] = p end
      p.name = name
      p:SetParent(canvas)
      p:SetSize(sz, sz)
      p:ClearAllPoints()
      p:SetPoint("CENTER", canvas, "TOPLEFT", mx * w, -my * h)
      styleTex(p.tex, d.file)
      if fpath then p.label:SetFont(fpath, fsize, "OUTLINE") end
      p.label:SetText(labelText(name, d))
      p.label:SetTextColor(classRGB(d.file))
      p:Show()
    end
  end
  local j = 0
  for k = #pings, 1, -1 do
    local g = pings[k]
    if now - g.t > 30 then table.remove(pings, k)
    elseif projectToMap(g.map, g.x, g.y, mid) then
      local gx, gy = projectToMap(g.map, g.x, g.y, mid)
      j = j + 1
      local p = pingPool[j]
      if not p then p = newPin(canvas, true); pingPool[j] = p end
      p:SetParent(canvas)
      p:ClearAllPoints()
      p:SetPoint("CENTER", canvas, "TOPLEFT", gx * w, -gy * h)
      p.tex:SetVertexColor(1, 0.85, 0)
      p:Show()
    end
  end
end

------------------------------------------------------------------ Minimap-Punkte
local RAD_OUT = { [0] = 233.33, 200, 166.67, 133.33, 100, 66.67 }
local RAD_IN = { [0] = 150, 120, 90, 60, 40, 25 }

-- Yards pro Karteneinheit (x/y) an der eigenen Position; vorzeichenfrei, daher robust
local function mapScale(m, px, py)
  if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return end
  local dx = px < 0.9 and 0.05 or -0.05
  local dy = py < 0.9 and 0.05 or -0.05
  local _, p0 = C_Map.GetWorldPosFromMapPos(m, CreateVector2D(px, py))
  local _, p1 = C_Map.GetWorldPosFromMapPos(m, CreateVector2D(px + dx, py))
  local _, p2 = C_Map.GetWorldPosFromMapPos(m, CreateVector2D(px, py + dy))
  if not (p0 and p1 and p2) then return end
  local x0, y0 = p0:GetXY()
  local x1, y1 = p1:GetXY()
  local x2, y2 = p2:GetXY()
  local W = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2) / math.abs(dx)
  local H = math.sqrt((x2 - x0) ^ 2 + (y2 - y0) ^ 2) / math.abs(dy)
  if W == 0 or H == 0 then return end
  return W, H
end

local function updateMini()
  for _, p in ipairs(miniPool) do p:Hide() end
  local s = DB.set
  if not s.mini or not Minimap or not Minimap:IsVisible() then return end
  local m, px, py = getPos()
  if not m then return end
  local W, H = mapScale(m, px, py)
  if not W then return end
  local zoom = Minimap:GetZoom() or 0
  local fpath = (GameFontNormalSmall and GameFontNormalSmall:GetFont()) or STANDARD_TEXT_FONT
  local rad = ((IsIndoors and IsIndoors()) and RAD_IN[zoom] or RAD_OUT[zoom]) or 150
  local pix = Minimap:GetWidth() / 2
  local facing = (GetCVar and GetCVar("rotateMinimap") == "1" and GetPlayerFacing) and GetPlayerFacing() or nil
  local sinf, cosf
  if facing then sinf, cosf = math.sin(facing), math.cos(facing) end
  local i, now = 0, GetTime()
  for name, d in pairs(members) do
    local mx, my
    if name ~= myName and now - d.t < (DB.interval * 3 + 10) and passFilter(d) and not (s.hideGroup and groupSet[name]) then
      mx, my = projectToMap(d.map, d.x, d.y, m)
    end
    if mx then
      local ex = (mx - px) * W   -- Yards nach Osten
      local ny = (py - my) * H   -- Yards nach Norden
      if facing then ex, ny = ex * cosf + ny * sinf, -ex * sinf + ny * cosf end
      if ex * ex + ny * ny <= rad * rad then
        i = i + 1
        local p = miniPool[i]
        if not p then p = newPin(Minimap, false, true, false); miniPool[i] = p end
        p.name = name
        p:SetSize(s.miniSize, s.miniSize)
        p:ClearAllPoints()
        p:SetPoint("CENTER", Minimap, "CENTER", ex / rad * pix, ny / rad * pix)
        styleTex(p.tex, d.file)
        if s.miniLabel then
          local fs = (s.labelSize and s.labelSize > 0) and s.labelSize or math.max(8, math.floor(s.miniSize * 0.9 + 0.5))
          if fpath then p.label:SetFont(fpath, fs, "OUTLINE") end
          p.label:SetText(labelText(name, d))
          p.label:SetTextColor(classRGB(d.file))
        else
          p.label:SetText("")
        end
        p:Show()
      end
    end
  end
end

local function sendPing(m, x, y)
  send(string.format("G:%d:%.4f:%.4f", m, x, y))
end

local function hookMap()
  if not WorldMapFrame or FG_HOOKED then return end
  FG_HOOKED = true
  WorldMapFrame:HookScript("OnShow", updatePins)
  if WorldMapFrame.OnMapChanged then hooksecurefunc(WorldMapFrame, "OnMapChanged", updatePins) end
  if hooksecurefunc and WorldMapFrame_UpdateMap then hooksecurefunc("WorldMapFrame_UpdateMap", updatePins) end
  -- Strg+Klick = Ping
  if WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.GetNormalizedCursorPosition then
    WorldMapFrame.ScrollContainer:HookScript("OnMouseUp", function(self, btn)
      if btn == "LeftButton" and IsControlKeyDown() then
        local x, y = self:GetNormalizedCursorPosition()
        if x and x >= 0 and x <= 1 and y >= 0 and y <= 1 then sendPing(viewedMap(), x, y) end
      end
    end)
  elseif WorldMapButton then
    WorldMapButton:HookScript("OnClick", function(self, btn)
      if btn == "LeftButton" and IsControlKeyDown() then
        local cx, cy = GetCursorPosition()
        local s = self:GetEffectiveScale()
        local l, b, w, h = self:GetRect()
        if l then sendPing(viewedMap(), (cx / s - l) / w, (b + h - cy / s) / h) end
      end
    end)
  end
end

------------------------------------------------------------------ Liste "Wer ist wo" + Berufe-Reiter
local ROWS, listFrame, rows, offset = 18, nil, {}, 0
local roster, guildRoster, onlineInfo, view, mode = {}, {}, {}, {}, "who"
local layerPeers = {}
local layerState = {
  map = nil, id = nil, zone = nil, t = 0, status = "unknown",
  changedAt = 0, source = nil,
}
local layerScan, layerSummaryText, layerPeerFresh, layerPeerText
local layerPing, requestLayerHop, layerHopAny
local recipeExpanded = {}
local finderPosts = {}
local refreshList

local function rebuildGuildRoster()
  wipe(guildRoster)
  if not (IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo) then return end
  for i = 1, GetNumGuildMembers() do
    local name, rank, _, level, class, zone, _, _, online, _, file = GetGuildRosterInfo(i)
    if name then
      local n = short(name)
      fullCache[n] = name
      rankCache[n] = rank
      guildRoster[#guildRoster + 1] = {
        name = n, full = name, rank = rank, level = level or 0, class = class or "?",
        zone = zone or "?", online = online and true or isLocalMember(n), file = file
      }
    end
  end
  table.sort(guildRoster, function(a, b) return a.name < b.name end)
end

local function buildRoster()
  rebuildGuildRoster()
  wipe(roster); wipe(onlineInfo)
  for _, d in ipairs(guildRoster) do
    if d.online then
      roster[#roster + 1] = d
      onlineInfo[d.name] = { file = d.file }
    end
  end
  -- The local player can be missing or stale in the asynchronous guild
  -- roster for a short time. A recipe learned by the player must never be
  -- displayed as coming from an offline crafter.
  if myName and not onlineInfo[myName] then
    local _, file = UnitClass and UnitClass("player")
    onlineInfo[myName] = { file = file, localPlayer = true }
  end
  table.sort(roster, function(a, b)
    if a.zone ~= b.zone then return a.zone < b.zone end
    return a.name < b.name
  end)
end

local function nameStr(n)
  local o = onlineInfo[n]
  if o then return classHex(o.file) .. n .. "|r" end
  return "|cff777777" .. n .. "|r"
end

local function onlineStr(n)
  return (isLocalMember(n) or onlineInfo[n]) and "|cff55dd88online|r" or "|cff888888offline|r"
end

local function className(file)
  return (file and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[file]) or file or "?"
end

local function agoText(ts)
  if not ts or ts <= 0 then return "nie gesehen" end
  local delta = math.max(0, time() - ts)
  if delta < 60 then return "gerade eben" end
  if delta < 3600 then return math.floor(delta / 60) .. " Min." end
  if delta < 86400 then return math.floor(delta / 3600) .. " Std." end
  return math.floor(delta / 86400) .. " T."
end

local function toggleFavorite(name)
  DB.favorites[name] = not DB.favorites[name]
  out((DB.favorites[name] and "★ " or "☆ ") .. name .. (DB.favorites[name] and " zu Favoriten hinzugefügt." or " aus Favoriten entfernt."))
  refreshList()
end

local function buildView()
  wipe(view)
  local q = ((listFrame and listFrame.search and listFrame.search:GetText()) or ""):lower()
  if mode == "who" then
    local now = GetTime()
    for _, d in ipairs(roster) do
      local m = members[d.name]
      local hasAddon = m and now - m.t < (DB.interval * 3 + 10)
      view[#view + 1] = { name = d.name, text = string.format("%s%s|r  %d  |cffaaaaaa%s|r %s", classHex(d.file),
        d.name, d.level or 0, d.zone, hasAddon and "|cff00ff00*|r" or "") }
    end
    return
  end

  if mode == "dashboard" then
    local entries = {}
    for _, d in ipairs(guildRoster) do
      local n = d.name
      local info = (DB.memberInfo and DB.memberInfo[n]) or members[n] or {}
      local prof = profText(n) or "Berufe unbekannt"
      local active = members[n] and GetTime() - members[n].t < (DB.interval * 3 + 10)
      local searchText = (n .. " " .. (d.zone or "") .. " " .. className(d.file) .. " " .. prof):lower()
      if q == "" or searchText:find(q, 1, true) then
        local level = d.level or info.level or "?"
        local star = DB.favorites[n] and "|cffffd100★|r " or ""
        local addon = active and "|cff55dd88Addon aktiv|r" or "|cff777777Addon nicht aktuell|r"
        entries[#entries + 1] = {
          name = n, favorite = DB.favorites[n], online = isLocalMember(n) or d.online, sortLevel = level,
          text = star .. nameStr(n) .. "|r  Lvl " .. level .. "  " .. className(d.file) ..
            "  |cffaaaaaa" .. (d.zone or "keine Zone") .. "|r  " .. onlineStr(n) ..
            "  " .. addon .. "  |cff777777Sync: " .. agoText(DB.memberSeen[n]) .. "|r"
        }
      end
    end
    table.sort(entries, function(a, b)
      if a.favorite ~= b.favorite then return a.favorite end
      if a.online ~= b.online then return a.online end
      return a.name < b.name
    end)
    for _, d in ipairs(entries) do view[#view + 1] = d end
    if #view == 0 then view[1] = { text = "|cffaaaaaaKeine passenden Gildenmitglieder gefunden.|r" } end
    return
  end

  if mode == "activity" then
    local activity = DB.activity or {}
    local now = time()
    local today, week = 0, 0
    for _, a in ipairs(activity) do
      if a.ts then
        if now - a.ts < 86400 then today = today + 1 end
        if now - a.ts < 604800 then week = week + 1 end
      end
    end
    if q == "" then
      view[#view + 1] = { text = "|cffffd100Aktivität|r  Heute: " .. today .. "  •  7 Tage: " .. week .. "  •  Gesamt: " .. #activity }
    end
    for i = #activity, math.max(1, #activity - 99), -1 do
      local a = activity[i]
      if a then
        local icon = a.kind == "death" and "|cffff5555☠|r" or a.kind == "loot" and "|cffffd100◆|r" or
          a.kind == "level" and "|cff55dd88↑|r" or a.kind == "recipe" and "|cffc084fc✦|r" or "|cffaaaaaa•|r"
        local line = icon .. " |cff888888" .. (a.date or "") .. "|r  " .. (a.text or "")
        if q == "" or line:lower():find(q, 1, true) then view[#view + 1] = { name = a.name, text = line } end
      end
    end
    if #view == 0 then view[1] = { text = "|cffaaaaaaNoch keine Gildenaktivität gespeichert.|r" } end
    return
  end

  if mode == "orders" then
    local list = {}
    for id, o in pairs(DB.orders or {}) do
      local line = (o.item or "Unbekannt") .. " x" .. (o.qty or 1) .. " " .. (o.note or "") .. " " .. (o.status or "open")
      if q == "" or (line .. " " .. (o.owner or "")):lower():find(q, 1, true) then
        list[#list + 1] = { id = id, name = o.owner, order = o, text =
          "|cffffd100" .. (o.item or "Unbekannt") .. " x" .. (o.qty or 1) .. "|r  " ..
          "|cffaaaaaa" .. (o.statusText or o.status or "offen") .. "|r  " ..
          (o.owner and nameStr(o.owner) or "") .. "  " .. (o.note or "") }
      end
    end
    table.sort(list, function(a, b) return (a.order.created or 0) > (b.order.created or 0) end)
    for _, d in ipairs(list) do view[#view + 1] = d end
    if #view == 0 then view[1] = { text = "|cffaaaaaaKeine offenen Crafting-Aufträge. Über die Felder oben einen Auftrag erstellen.|r" } end
    return
  end

  if mode == "layers" then
    view[#view + 1] = { text = layerSummaryText and layerSummaryText() or "|cffaaaaaaLayer-Daten werden geladen ...|r", layerSummary = true }
    view[#view + 1] = { text = "|cff888888Klick auf einen bekannten Layer für eine Hop-Anfrage. Hop Any nimmt einen anderen bekannten Layer.|r", layerSummary = true }
    local finderQ = ((listFrame and listFrame.finderInput and listFrame.finderInput:GetText()) or ""):lower()
    if finderQ == "zone / layer / spieler" or finderQ == "dungeon / ziel / zone" then finderQ = "" end
    local seen = {}
    for _, d in ipairs(roster) do
      local p = layerPeers[d.name]
      if d.name ~= myName and layerPeerFresh and layerPeerFresh(p) then
        seen[d.name] = true
        local hay = (d.name .. " " .. (d.zone or "") .. " " .. (p.zone or "") .. " " .. tostring(p.layer or "")):lower()
        if finderQ == "" or hay:find(finderQ, 1, true) then
          view[#view + 1] = { name = d.name, layerHop = true, layer = p,
            text = "|cffc084fc⇄ " .. (layerPeerText and layerPeerText(p) or "Layer") .. "|r  " ..
              nameStr(d.name) .. "|r  Lvl " .. (d.level or "?") .. "  |cffaaaaaa" ..
              (p.zone or d.zone or "Zone unbekannt") .. "|r  " .. (p.host and "|cff55dd88Host|r" or "") }
        end
      end
    end
    -- Direkte Layer-Peers können auch außerhalb des aktuellen Gildenrosters
    -- bekannt sein. Sie werden nur angezeigt, wenn sie selbst geantwortet haben.
    for n, p in pairs(layerPeers) do
      if n ~= myName and not seen[n] and layerPeerFresh and layerPeerFresh(p) then
        local hay = (n .. " " .. (p.zone or "") .. " " .. tostring(p.layer or "")):lower()
        if finderQ == "" or hay:find(finderQ, 1, true) then
          view[#view + 1] = { name = n, layerHop = true, layer = p,
            text = "|cffc084fc⇄ " .. (layerPeerText and layerPeerText(p) or "Layer") .. "|r  " ..
              nameStr(n) .. "|r  |cffaaaaaa" .. (p.zone or "Zone unbekannt") .. "|r  " ..
              (p.host and "|cff55dd88Host|r" or "") }
        end
      end
    end
    if #view == 2 then view[#view + 1] = { text = "|cffaaaaaaKeine bestätigten Layer-Peers gefunden. Bitte aktualisieren oder andere Gildenmitglieder ebenfalls /fg layer testen lassen.|r" } end
    return
  end

  if mode == "finder" then
    local now = GetTime()
    local finderQ = ((listFrame and listFrame.finderInput and listFrame.finderInput:GetText()) or ""):lower()
    if finderQ == "dungeon / ziel / zone" then finderQ = "" end
    for id, p in pairs(finderPosts) do
      if now - p.t > 900 then finderPosts[id] = nil
      elseif finderQ == "" or (p.text .. " " .. p.zone .. " " .. p.level .. " " .. p.name):lower():find(finderQ, 1, true) then
        view[#view + 1] = { name = p.name, finderPost = p, text = "|cffffd100⌕ " .. p.text .. "|r  " ..
          "|cffaaaaaaLvl " .. p.level .. " • " .. p.zone .. "|r  " .. nameStr(p.name) }
      end
    end
    for _, d in ipairs(roster) do
      local t = layerPeers[d.name]
      if d.name ~= myName and t and t.t and now - t.t < 120 and (finderQ == "" or (d.name .. " " .. (d.zone or "") .. " " .. (d.level or "")):lower():find(finderQ, 1, true)) then
        view[#view + 1] = { name = d.name, layerHop = true,
          text = "|cffc084fc⇄ Layer-Hop|r  " .. nameStr(d.name) .. "|r  Lvl " .. (d.level or "?") ..
            "  |cffaaaaaa" .. (d.zone or "Zone unbekannt") .. "|r  |cffffcc44[anfragen]|r" }
      end
    end
    if #view == 0 then view[1] = { text = "|cffaaaaaaKeine passenden Gruppen- oder Layer-Spieler gefunden.|r" } end
    return
  end
  -- Rezeptkatalog: nur Rezepte, die ein Gildenmitglied geteilt hat.
  -- Gleiche Rezepte werden zusammengefasst; per Klick werden die Crafter aufgeklappt.
  local groups = {}
  for n, byProf in pairs((DB and DB.recipes) or {}) do
    if type(byProf) == "table" then
      for prof, list in pairs(byProf) do
        if type(list) == "table" then
          local seen = {}
          for _, rec in ipairs(list) do
            rec = tostring(rec or "")
            local localKey = prof .. "\031" .. rec:lower()
            if rec ~= "" and not seen[localKey] then
              seen[localKey] = true
              local searchText = (rec .. " " .. prof .. " " .. n):lower()
              if q == "" or searchText:find(q, 1, true) then
                groups[localKey] = groups[localKey] or { recipe = rec, prof = prof, crafters = {} }
                groups[localKey].crafters[n] = true
              end
            end
          end
        end
      end
    end
  end

  local keys = {}
  for key in pairs(groups) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b)
    local ga, gb = groups[a], groups[b]
    if ga.prof ~= gb.prof then return ga.prof < gb.prof end
    return ga.recipe:lower() < gb.recipe:lower()
  end)

  for idx, key in ipairs(keys) do
    if idx > 200 then break end
    local g = groups[key]
    local crafters = {}
    for n in pairs(g.crafters) do crafters[#crafters + 1] = n end
    table.sort(crafters)
    local expanded = recipeExpanded[key]
    view[#view + 1] = {
      recipeGroup = key,
      recipeCrafters = crafters,
      text = (expanded and "|cffffd100▾ " or "|cffffd100▸ ") .. g.recipe .. "|r  |cffaaaaaa" ..
        g.prof .. " • " .. #crafters .. " Crafter|r"
    }
    if expanded then
      for _, n in ipairs(crafters) do
        view[#view + 1] = { name = n, recipeChild = true, text = "    ↳ " .. nameStr(n) .. "  " .. onlineStr(n) }
      end
    end
  end
  if #view == 0 then
    view[1] = { text = "|cff888888Keine gespeicherten Gildenrezepte gefunden. Ein Crafter muss sein Berufefenster öffnen.|r" }
  end
end

function refreshList()
  if not listFrame or not listFrame:IsShown() then return end
  buildRoster()
  buildView()
  if mode == "who" then listFrame.title:SetText(BRAND .. " - Gildenkarte: online " .. #roster)
  elseif mode == "dashboard" then listFrame.title:SetText(BRAND .. " - Gilden-Dashboard")
  elseif mode == "profs" then listFrame.title:SetText(BRAND .. " - Rezepte & Crafter")
  elseif mode == "activity" then listFrame.title:SetText(BRAND .. " - Gilden-Aktivität")
  elseif mode == "orders" then listFrame.title:SetText(BRAND .. " - Crafting-Aufträge")
  elseif mode == "finder" then listFrame.title:SetText(BRAND .. " - Gruppenfinder")
  elseif mode == "layers" then listFrame.title:SetText(BRAND .. " - Layer-Hop") end
  for i = 1, ROWS do
    local d, row = view[i + offset], rows[i]
    if d then row.data = d; row.text:SetText(d.text); row:Show()
    else row.data = nil; row:Hide() end
  end
end

local function requestRoster()
  if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster()
  elseif GuildRoster then GuildRoster() end
end

local function doInvite(name)
  if C_PartyInfo and C_PartyInfo.InviteUnit then C_PartyInfo.InviteUnit(name) else InviteUnit(name) end
end

local function setMode(m)
  mode = m; offset = 0
  if listFrame then
    local searchable = m == "profs" or m == "dashboard" or m == "activity"
    listFrame.search:SetShown(searchable)
    listFrame.searchLabel:SetShown(searchable)
    listFrame.orderItem:SetShown(m == "orders")
    listFrame.orderQty:SetShown(m == "orders")
    listFrame.orderNote:SetShown(m == "orders")
    listFrame.orderButton:SetShown(m == "orders")
    listFrame.finderInput:SetShown(m == "finder" or m == "layers")
    listFrame.finderButton:SetShown(m == "finder" or m == "layers")
    listFrame.finderButton:SetText(m == "layers" and "Layer aktualisieren" or "Gruppe suchen")
    if listFrame.layerHopButton then listFrame.layerHopButton:SetShown(m == "layers") end
    local tabs = { listFrame.tabWho, listFrame.tabDashboard, listFrame.tabProf, listFrame.tabActivity, listFrame.tabOrders, listFrame.tabLayer, listFrame.tabFinder }
    for _, tab in ipairs(tabs) do
      local active = tab.mode == m
      tab.text:SetTextColor(active and 1 or 0.6, active and 0.82 or 0.6, active and 0 or 0.6)
      tab.bg:SetVertexColor(active and 0.2 or THEME.panel[1], active and 0.12 or THEME.panel[2], active and 0.08 or THEME.panel[3], 1)
    end
    if m == "finder" or m == "layers" then layerPing() end
  end
  refreshList()
end

local function makeTab(parent, label, x, m)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(108, 30)
  b:SetPoint("TOPLEFT", x, -50)
  b.bg = themeTexture(b, "BACKGROUND", THEME.panel)
  b.bg:SetAllPoints()
  b.line = themeTexture(b, "ARTWORK", THEME.border)
  b.line:SetPoint("BOTTOMLEFT"); b.line:SetPoint("BOTTOMRIGHT"); b.line:SetHeight(2)
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  b.text:SetAllPoints(); b.text:SetText(label)
  b.text:SetTextColor(THEME.muted[1], THEME.muted[2], THEME.muted[3])
  b.mode = m
  b:SetScript("OnEnter", function(self) self.bg:SetVertexColor(0.18, 0.12, 0.16, 1) end)
  b:SetScript("OnLeave", function(self) self.bg:SetVertexColor(THEME.panel[1], THEME.panel[2], THEME.panel[3], 1) end)
  b:SetScript("OnClick", function() setMode(m) end)
  return b
end

local function buildList()
  local f = CreateFrame("Frame", "ForeverGuildList", UIParent)
  f:SetSize(800, ROWS * 20 + 138)
  f:SetPoint("CENTER", 300, 0)
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true); f:SetResizable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
  if f.SetResizeBounds then f:SetResizeBounds(620, ROWS * 20 + 138, 1100, 760) end
  f:SetScript("OnSizeChanged", function(self)
    for _, row in ipairs(rows) do
      row:SetWidth(math.max(100, self:GetWidth() - 30))
      row.text:SetWidth(math.max(80, self:GetWidth() - 46))
    end
  end)
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:EnableMouseWheel(true)
  f:SetScript("OnMouseWheel", function(_, delta)
    offset = math.max(0, math.min(math.max(0, #view - ROWS), offset - delta * 3))
    refreshList()
  end)
  local bg = themeTexture(f, "BACKGROUND", THEME.bg); bg:SetAllPoints()
  local borderTop = themeTexture(f, "BORDER", THEME.border)
  borderTop:SetPoint("TOPLEFT"); borderTop:SetPoint("TOPRIGHT"); borderTop:SetHeight(1)
  local borderBottom = themeTexture(f, "BORDER", THEME.border)
  borderBottom:SetPoint("BOTTOMLEFT"); borderBottom:SetPoint("BOTTOMRIGHT"); borderBottom:SetHeight(1)
  local borderLeft = themeTexture(f, "BORDER", THEME.border)
  borderLeft:SetPoint("TOPLEFT"); borderLeft:SetPoint("BOTTOMLEFT"); borderLeft:SetWidth(1)
  local borderRight = themeTexture(f, "BORDER", THEME.border)
  borderRight:SetPoint("TOPRIGHT"); borderRight:SetPoint("BOTTOMRIGHT"); borderRight:SetWidth(1)
  local head = themeTexture(f, "ARTWORK", THEME.header)
  head:SetPoint("TOPLEFT", 2, -2); head:SetPoint("TOPRIGHT", -2, -2); head:SetHeight(46)
  local accent = themeTexture(f, "OVERLAY", THEME.accent)
  accent:SetPoint("TOPLEFT", 2, -48); accent:SetPoint("TOPRIGHT", -2, -48); accent:SetHeight(2)
  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.title:SetPoint("TOPLEFT", 16, -12)
  f.title:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3])
  f.title:SetText(BRAND)
  f.subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.subtitle:SetPoint("TOPLEFT", 18, -31)
  f.subtitle:SetText("Gildenkarte • Dashboard • Berufe • Aktivität • Aufträge • Layer • Finder")
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)
  local ob = CreateFrame("Button", nil, f)
  ob:SetSize(100, 24)
  ob:SetPoint("TOPRIGHT", -34, -14)
  ob.text = ob:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  ob.text:SetAllPoints(); ob.text:SetText("⚙ Optionen")
  ob.text:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3])
  ob:SetScript("OnClick", function() openSettings() end)
  f.tabWho = makeTab(f, "Gildenkarte", 14, "who")
  f.tabDashboard = makeTab(f, "Dashboard", 122, "dashboard")
  f.tabProf = makeTab(f, "Berufe", 230, "profs")
  f.tabActivity = makeTab(f, "Aktivität", 338, "activity")
  f.tabOrders = makeTab(f, "Aufträge", 446, "orders")
  f.tabLayer = makeTab(f, "Layer", 554, "layers")
  f.tabFinder = makeTab(f, "Finder", 662, "finder")

  f.searchLabel = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.searchLabel:SetPoint("TOPLEFT", 18, -88)
  f.searchLabel:SetText("Suche (Beruf/Rezept/Crafter):")
  local sb = CreateFrame("EditBox", nil, f)
  sb:SetSize(240, 18)
  sb:SetPoint("TOPLEFT", 166, -86)
  sb:SetFontObject("ChatFontNormal")
  sb:SetAutoFocus(false)
  sb:SetTextInsets(4, 4, 0, 0)
  local sbg = sb:CreateTexture(nil, "BACKGROUND"); sbg:SetAllPoints(); setColor(sbg, THEME.panelAlt[1], THEME.panelAlt[2], THEME.panelAlt[3], 1)
  sb:SetScript("OnEscapePressed", sb.ClearFocus)
  sb:SetScript("OnEnterPressed", sb.ClearFocus)
  sb:SetScript("OnTextChanged", function() offset = 0; refreshList() end)
  f.search = sb

  local function makeInput(width, x, default)
    local input = CreateFrame("EditBox", nil, f)
    input:SetSize(width, 20); input:SetPoint("TOPLEFT", x, -84); input:SetFontObject("ChatFontNormal")
    input:SetAutoFocus(false); input:SetTextInsets(4, 4, 0, 0); input:SetText(default)
    local bgInput = input:CreateTexture(nil, "BACKGROUND"); bgInput:SetAllPoints(); setColor(bgInput, THEME.panelAlt[1], THEME.panelAlt[2], THEME.panelAlt[3], 1)
    input:SetScript("OnEscapePressed", input.ClearFocus)
    input:SetScript("OnMouseDown", function(self) if self:GetText() == default then self:SetText("") end end)
    return input
  end
  f.orderItem = makeInput(190, 18, "Item / Link")
  f.orderQty = makeInput(48, 214, "1")
  f.orderNote = makeInput(190, 270, "Notiz")
  f.finderInput = makeInput(300, 18, "Dungeon / Ziel / Zone")
  f.orderButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.orderButton:SetSize(120, 22); f.orderButton:SetPoint("TOPLEFT", 474, -83); f.orderButton:SetText("Auftrag senden")
  f.finderButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.finderButton:SetSize(120, 22); f.finderButton:SetPoint("TOPLEFT", 330, -83); f.finderButton:SetText("Gruppe suchen")
  f.finderButton:SetScript("OnClick", function()
    if mode == "layers" then
      layerPing()
      refreshList()
      out("Layer-Daten aktualisiert.")
    end
  end)
  f.layerHopButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.layerHopButton:SetSize(120, 22); f.layerHopButton:SetPoint("TOPLEFT", 456, -83); f.layerHopButton:SetText("Hop Any")
  f.layerHopButton:SetScript("OnClick", function() if mode == "layers" and layerHopAny then layerHopAny() end end)

  for i = 1, ROWS do
    local r = CreateFrame("Button", nil, f)
    r:SetSize(770, 20)
    r:SetPoint("TOPLEFT", 16, -112 - (i - 1) * 20)
    r.bg = themeTexture(r, "BACKGROUND", THEME.panel)
    r.bg:SetAllPoints()
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.text:SetPoint("LEFT", 8, 0); r.text:SetWidth(754); r.text:SetJustifyH("LEFT")
    r.text:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3])
    r:SetScript("OnEnter", function(self) self.bg:SetVertexColor(0.18, 0.12, 0.16, 1) end)
    r:SetScript("OnLeave", function(self) self.bg:SetVertexColor(THEME.panel[1], THEME.panel[2], THEME.panel[3], 1) end)
    if r.text.SetWordWrap then r.text:SetWordWrap(false) end
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:SetScript("OnClick", function(self, btn)
      if not self.data or (not self.data.name and not self.data.recipeGroup) then return end
      if self.data.recipeGroup then
        if btn == "LeftButton" then
          recipeExpanded[self.data.recipeGroup] = not recipeExpanded[self.data.recipeGroup]
          offset = 0
          refreshList()
        end
        return
      end
      if self.data.layerHop then
        if btn == "LeftButton" then
          if requestLayerHop then requestLayerHop(self.data.name, self.data.layer) end
        else whisperTo(fullName(self.data.name)) end
        return
      end
      if btn == "LeftButton" then
        whisperTo(fullName(self.data.name))
      else
        doInvite(fullName(self.data.name))
      end
    end)
    r:SetScript("OnEnter", function(self)
      if not self.data then return end
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:AddLine(self.data.text, 1, 1, 1, true)
      if self.data.recipeGroup then
        GameTooltip:AddLine("Links: Crafter anzeigen/verbergen", 0.5, 0.8, 0.5, true)
        for _, n in ipairs(self.data.recipeCrafters or {}) do
          GameTooltip:AddLine(nameStr(n) .. "  " .. onlineStr(n), 0.8, 0.8, 0.8, true)
        end
        GameTooltip:Show()
        return
      end
      if self.data.name then
        local p = profText(self.data.name)
        GameTooltip:AddLine(p or "Berufe unbekannt (kein Addon?)", 0.8, 0.8, 0.8, true)
        if self.data.layerHop then
          GameTooltip:AddLine("Links: Hop anfragen   Rechts: Fluestern", 0.5, 0.8, 0.5)
          local p = self.data.layer
          GameTooltip:AddLine((layerPeerText and p and layerPeerText(p) or "Layer unbekannt") ..
            " • Gruppenbeitritt kann den Layer wechseln.", 0.8, 0.8, 0.8, true)
        else GameTooltip:AddLine("Links: Flüstern   Rechts: Einladen", 0.5, 0.5, 0.5) end
      end
      GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[i] = r
  end
  f:SetScript("OnShow", function() requestRoster(); setMode(mode) end)
  listFrame = f
  tinsert(UISpecialFrames, "ForeverGuildList")
end

local function openProfs()
  if not listFrame:IsShown() then listFrame:Show() end
  setMode("profs")
end

------------------------------------------------------------------ Rezepte scannen & teilen
local function sendRecipes(prof, names)
  local chunks, cur = {}, ""
  for _, n in ipairs(names) do
    if #cur + #n + 1 > 200 then chunks[#chunks + 1] = cur; cur = "" end
    cur = cur .. ";" .. n
  end
  if cur ~= "" then chunks[#chunks + 1] = cur end
  for i, c in ipairs(chunks) do
    C_Timer.After((i - 1) * 0.4, function()
      send(string.format("C:%s:%d:%d%s", prof, i, #chunks, c))
    end)
  end
end

local function storeAndSend(prof, names)
  DB.recipes[myName] = DB.recipes[myName] or {}
  local old = DB.recipes[myName][prof]
  if old and table.concat(old, ";") == table.concat(names, ";") then return end
  DB.recipes[myName][prof] = names
  sendRecipes(prof, names)
end

local function scanTrade()
  if not (C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo
      and C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetRecipeInfo) then return end

  local okInfo, info = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
  if not okInfo or type(info) ~= "table" then return end
  local prof = info.professionName or info.name
  if not prof or prof == "" then return end

  local okIDs, recipeIDs = pcall(C_TradeSkillUI.GetAllRecipeIDs)
  if not okIDs or type(recipeIDs) ~= "table" then return end

  local names = {}
  for _, recipeID in pairs(recipeIDs) do
    local okRecipe, recipe = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
    if okRecipe and type(recipe) == "table" and recipe.name
        and (recipe.learned == nil or recipe.learned)
        and not recipe.isDummyRecipe then
      names[#names + 1] = tostring(recipe.name):gsub(";", "")
    end
  end
  if #names > 0 then storeAndSend(prof, names) end
end

local scanPending
local function scanLater(fn)
  if scanPending then return end
  scanPending = true
  C_Timer.After(1.5, function() scanPending = nil; fn() end)
end

local function syncMyRecipes()
  local mine = DB.recipes[myName]
  if not mine then out("Noch keine Rezepte gespeichert. Öffne erst deine Berufefenster."); return end
  local delay = 0
  for prof, names in pairs(mine) do
    C_Timer.After(delay, function() sendRecipes(prof, names) end)
    delay = delay + 4
  end
  out("Rezepte werden an die Gilde gesendet.")
end

------------------------------------------------------------------ Weltbuff-Timer
local BUFFS = { "Rallying Cry of the Dragonslayer", "Warchief's Blessing", "Spirit of Zandalar",
  "Songflower Serenade", "Dire Maul Tribute", "Slip'kik's Savvy", "Fengus' Ferocity", "Mol'dar's Moxie" }
local buffFrame

local function getBuff(i)
  if not (C_UnitAuras and C_UnitAuras.GetBuffDataByIndex) then return end
  -- Aura data can be secret while the player is in combat. The worldbuff
  -- display is optional, so skip protected reads instead of tainting the UI.
  if InCombatLockdown and InCombatLockdown() then return end
  local ok, d = pcall(C_UnitAuras.GetBuffDataByIndex, "player", i)
  if not ok or type(d) ~= "table" then return end
  local okName, name = pcall(function() return d.name .. "" end)
  local okExp, exp = pcall(function() return d.expirationTime end)
  if not okName or type(name) ~= "string" or not okExp then return end
  return name, exp
end

local function buildBuffFrame()
  local f = CreateFrame("Frame", "ForeverGuildBuffs", UIParent)
  f:SetSize(220, 20)
  f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -200)
  f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.text:SetPoint("TOPLEFT"); f.text:SetJustifyH("LEFT")
  local acc = 0
  f:SetScript("OnUpdate", function(self, el)
    acc = acc + el
    if acc < 1 then return end
    acc = 0
    local tracked = {}
    for _, n in ipairs(BUFFS) do tracked[n] = true end
    for n in pairs(DB.buffs) do tracked[n] = true end
    local lines, now = {}, GetTime()
    for i = 1, 40 do
      local name, exp = getBuff(i)
      if not name then break end
      -- Do the complete expiration calculation inside pcall: expirationTime
      -- may itself be a secret value on restricted clients.
      local okLeft, left = pcall(function()
        if tracked[name] and exp and exp > 0 then return math.max(0, exp - now) end
      end)
      if okLeft and type(left) == "number" then
        lines[#lines + 1] = string.format("%s: %d:%02d", name, left / 60, left % 60)
      end
    end
    self.text:SetText(table.concat(lines, "\n"))
  end)
  buffFrame = f
end

------------------------------------------------------------------ Einstellungen & Leben-Alarm
local settingsFrame
local ORANGE = { 1, 0.48, 0.1 }

local DEFAULTS = { dots = true, mini = true, icons = false, showName = false, showLevel = false,
  showRank = false, showHealth = false, iconSize = 13, miniSize = 10, filter = "off", minL = 1, maxL = 100,
  below = 5, above = 5, hpAlert = 0, deathChat = true, milestones = true, profMile = true, rareLoot = true,
  autoLog = false, labelSize = 0, miniLabel = true, hideGroup = true, layerHost = false }

local SETTINGS = {
  { section = "Karte" },
  { type = "toggle", key = "dots", label = "Punkte auf der Weltkarte" },
  { type = "toggle", key = "mini", label = "Punkte auf der Minimap" },
  { type = "toggle", key = "icons", label = "Klassen-Icons statt Farbpunkte" },
  { type = "toggle", key = "hideGroup", label = "Gruppenmitglieder ausblenden",
    hint = "Blizzard zeigt Gruppenmitglieder selbst live an" },
  { type = "number", key = "iconSize", label = "Größe auf der Weltkarte", min = 8, max = 32, step = 1 },
  { type = "number", key = "miniSize", label = "Größe auf der Minimap", min = 6, max = 24, step = 1 },

  { section = "Beschriftung an den Punkten" },
  { type = "toggle", key = "showName", label = "Name anzeigen" },
  { type = "toggle", key = "showLevel", label = "Level anzeigen" },
  { type = "toggle", key = "showRank", label = "Gildenrang anzeigen" },
  { type = "toggle", key = "showHealth", label = "Leben in % anzeigen" },
  { type = "number", key = "labelSize", label = "Textgröße", min = 0, max = 28, step = 1,
    fmt = function(v) return v == 0 and "auto" or tostring(v) end },
  { type = "toggle", key = "miniLabel", label = "Beschriftung auch auf der Minimap" },

  { section = "Filter" },
  { type = "cycle", key = "filter", label = "Level-Filter", values = { "off", "range", "rel" },
    names = { "aus", "Bereich", "relativ zu mir" } },
  { type = "number", key = "minL", label = "Level von", min = 1, max = 100, step = 1,
    show = function() return DB.set.filter == "range" end },
  { type = "number", key = "maxL", label = "Level bis", min = 1, max = 100, step = 1,
    show = function() return DB.set.filter == "range" end },
  { type = "number", key = "below", label = "Stufen unter mir", min = 0, max = 50, step = 1,
    show = function() return DB.set.filter == "rel" end },
  { type = "number", key = "above", label = "Stufen über mir", min = 0, max = 50, step = 1,
    show = function() return DB.set.filter == "rel" end },

  { section = "Alarme" },
  { type = "number", key = "hpAlert", label = "Leben-Alarm unter", min = 0, max = 90, step = 5,
    fmt = function(v) return v == 0 and "aus" or (v .. "%") end },

  { section = "Gildenchat & Discord" },
  { type = "toggle", key = "deathChat", label = "Tod im Gildenchat melden" },
  { type = "toggle", key = "milestones", label = "Level-Meilensteine melden", hint = "Alle 5 Level (5, 10, 15 ...)" },
  { type = "toggle", key = "profMile", label = "Beruf-Meilensteine melden", hint = "In 75er-Schritten" },
  { type = "toggle", key = "rareLoot", label = "Epische Funde melden" },
  { type = "toggle", key = "autoLog", label = "Chatlog für die Discord-Bridge",
    hint = "Schreibt den Chat in WoWChatLog.txt (auch Flüstern)" },
  { section = "Layer-Hop" },
  { type = "toggle", key = "layerHost", label = "Layer-Hop-Anfragen automatisch hosten",
    hint = "Lädt passende Spieler nur ein, wenn du auf dem angefragten Layer bist" },
}

local alertT = {}
local function hpAlert(name, hp)
  local th = DB.set.hpAlert
  if not th or th <= 0 or not hp or hp <= 0 or hp > th then return end
  local now = GetTime()
  if now - (alertT[name] or 0) < 20 then return end
  alertT[name] = now
  local msg = name .. " hat nur noch " .. hp .. "% Leben!"
  if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo then
    pcall(RaidNotice_AddMessage, RaidWarningFrame, msg, ChatTypeInfo["RAID_WARNING"])
  end
  out("|cffff4444" .. msg .. "|r")
end

local function refreshSettings()
  if not settingsFrame then return end
  for _, r in ipairs(settingsFrame.rows) do r.update() end
  settingsFrame.layout()
end

local function chatLogState()
  if C_ChatInfo and C_ChatInfo.IsLoggingChat then
    local ok, value = pcall(C_ChatInfo.IsLoggingChat)
    if ok then return value end
  end
  if LoggingChat then
    local ok, value = pcall(LoggingChat)
    if ok then return value end
  end
end

local function applySettings()
  local want = DB.set.autoLog and true or false
  if want ~= DB.logApplied then
    DB.logApplied = want
    if LoggingChat then pcall(LoggingChat, want) end
  end
  updatePins(); updateMini(); refreshSettings()
end

local function rect(parent, layer, r, g, b, a)
  local t = parent:CreateTexture(nil, layer)
  setColor(t, r, g, b, a)
  return t
end

local function buildSettings()
  local W = 412
  local f = CreateFrame("Frame", "ForeverGuildSettings", UIParent)
  f:SetSize(W + 28, 400)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)

  -- Hintergrund, Rahmen, Kopfleiste
  local bg = rect(f, "BACKGROUND", 0.055, 0.055, 0.075, 0.97); bg:SetAllPoints()
  local function edge(p1, p2, w, h)
    local t = rect(f, "BORDER", ORANGE[1], ORANGE[2], ORANGE[3], 0.7)
    t:SetPoint(p1); t:SetPoint(p2)
    if w then t:SetWidth(w) end
    if h then t:SetHeight(h) end
  end
  edge("TOPLEFT", "TOPRIGHT", nil, 1); edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
  edge("TOPLEFT", "BOTTOMLEFT", 1, nil); edge("TOPRIGHT", "BOTTOMRIGHT", 1, nil)
  local head = rect(f, "ARTWORK", 0.09, 0.09, 0.12, 1)
  head:SetPoint("TOPLEFT", 1, -1); head:SetPoint("TOPRIGHT", -1, -1); head:SetHeight(40)
  local accent = rect(f, "OVERLAY", ORANGE[1], ORANGE[2], ORANGE[3], 1)
  accent:SetPoint("TOPLEFT", 1, -41); accent:SetPoint("TOPRIGHT", -1, -41); accent:SetHeight(2)

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -12)
  title:SetText(BRAND)
  local sub = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  sub:SetPoint("LEFT", title, "RIGHT", 8, -1)
  sub:SetText("Einstellungen")

  local close = CreateFrame("Button", nil, f)
  close:SetSize(24, 24)
  close:SetPoint("TOPRIGHT", -8, -9)
  close.t = close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  close.t:SetAllPoints(); close.t:SetText("X"); close.t:SetTextColor(0.7, 0.7, 0.75)
  close:SetScript("OnEnter", function(s) s.t:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3]) end)
  close:SetScript("OnLeave", function(s) s.t:SetTextColor(0.7, 0.7, 0.75) end)
  close:SetScript("OnClick", function() f:Hide() end)

  f.rows = {}
  local function addRow(def, frame, h, update)
    f.rows[#f.rows + 1] = { def = def, frame = frame, h = h, update = update or function() end }
  end

  for _, def in ipairs(SETTINGS) do
    if def.section then
      local fr = CreateFrame("Frame", nil, f)
      fr:SetSize(W, 30)
      local fs = fr:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      fs:SetPoint("BOTTOMLEFT", 4, 7)
      fs:SetText(string.upper(def.section))
      fs:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3])
      local line = rect(fr, "ARTWORK", ORANGE[1], ORANGE[2], ORANGE[3], 0.3)
      line:SetPoint("BOTTOMLEFT", 0, 3); line:SetPoint("BOTTOMRIGHT", 0, 3); line:SetHeight(1)
      addRow(def, fr, 32)

    elseif def.type == "toggle" then
      local h = def.hint and 38 or 28
      local b = CreateFrame("Button", nil, f)
      b:SetSize(W, h)
      local hl = rect(b, "BACKGROUND", 1, 1, 1, 0); hl:SetAllPoints()
      b:SetScript("OnEnter", function() setColor(hl, 1, 1, 1, 0.06) end)
      b:SetScript("OnLeave", function() setColor(hl, 1, 1, 1, 0) end)
      local lab = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      lab:SetPoint("TOPLEFT", 6, -7); lab:SetText(def.label); lab:SetJustifyH("LEFT")
      if def.hint then
        local hf = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hf:SetPoint("TOPLEFT", 6, -23); hf:SetText(def.hint)
      end
      local track = rect(b, "ARTWORK", 0.25, 0.25, 0.3, 1)
      track:SetSize(34, 16); track:SetPoint("TOPRIGHT", -8, -6)
      local knob = rect(b, "OVERLAY", 1, 1, 1, 1)
      knob:SetSize(12, 12)
      b:SetScript("OnClick", function() DB.set[def.key] = not DB.set[def.key]; applySettings() end)
      addRow(def, b, h, function()
        knob:ClearAllPoints()
        if DB.set[def.key] then
          setColor(track, ORANGE[1], ORANGE[2], ORANGE[3], 1)
          knob:SetPoint("RIGHT", track, "RIGHT", -2, 0)
        else
          setColor(track, 0.25, 0.25, 0.3, 1)
          knob:SetPoint("LEFT", track, "LEFT", 2, 0)
        end
      end)

    elseif def.type == "number" then
      local fr = CreateFrame("Frame", nil, f)
      fr:SetSize(W, 30)
      local lab = fr:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      lab:SetPoint("TOPLEFT", 6, -8); lab:SetText(def.label)
      local val = fr:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      val:SetPoint("TOPRIGHT", -8, -8); val:SetWidth(44); val:SetJustifyH("RIGHT")
      local updating = false
      local function show(v) val:SetText(def.fmt and def.fmt(v) or tostring(v)) end
      local ok, slider = pcall(function()
        local s = CreateFrame("Slider", nil, fr)
        s:SetOrientation("HORIZONTAL")
        s:SetSize(170, 16)
        s:SetPoint("TOPRIGHT", -60, -7)
        s:SetMinMaxValues(def.min, def.max)
        s:SetValueStep(def.step)
        if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
        local trk = rect(s, "BACKGROUND", 0.25, 0.25, 0.3, 1)
        trk:SetPoint("LEFT"); trk:SetPoint("RIGHT"); trk:SetHeight(4)
        local th = s:CreateTexture(nil, "OVERLAY")
        setColor(th, ORANGE[1], ORANGE[2], ORANGE[3], 1)
        th:SetSize(9, 16)
        s:SetThumbTexture(th)
        s:SetScript("OnValueChanged", function(_, v)
          if updating then return end
          v = math.floor(v / def.step + 0.5) * def.step
          if v ~= DB.set[def.key] then DB.set[def.key] = v; applySettings() end
        end)
        return s
      end)
      if ok and slider then
        addRow(def, fr, 30, function()
          updating = true
          slider:SetValue(DB.set[def.key])
          updating = false
          show(DB.set[def.key])
        end)
      else -- Ersatz: [-] / [+]
        local function change(d)
          DB.set[def.key] = math.max(def.min, math.min(def.max, (DB.set[def.key] or 0) + d * def.step))
          applySettings()
        end
        local mb = CreateFrame("Button", nil, fr); mb:SetSize(22, 20); mb:SetPoint("TOPRIGHT", -112, -5)
        mb.t = mb:CreateFontString(nil, "OVERLAY", "GameFontNormal"); mb.t:SetAllPoints(); mb.t:SetText("-")
        mb:SetScript("OnClick", function() change(-1) end)
        local pb = CreateFrame("Button", nil, fr); pb:SetSize(22, 20); pb:SetPoint("TOPRIGHT", -60, -5)
        pb.t = pb:CreateFontString(nil, "OVERLAY", "GameFontNormal"); pb.t:SetAllPoints(); pb.t:SetText("+")
        pb:SetScript("OnClick", function() change(1) end)
        addRow(def, fr, 30, function() show(DB.set[def.key]) end)
      end

    else -- cycle
      local b = CreateFrame("Button", nil, f)
      b:SetSize(W, 30)
      local hl = rect(b, "BACKGROUND", 1, 1, 1, 0); hl:SetAllPoints()
      b:SetScript("OnEnter", function() setColor(hl, 1, 1, 1, 0.06) end)
      b:SetScript("OnLeave", function() setColor(hl, 1, 1, 1, 0) end)
      local lab = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      lab:SetPoint("TOPLEFT", 6, -8); lab:SetText(def.label)
      local pill = rect(b, "ARTWORK", 0.18, 0.18, 0.23, 1)
      pill:SetSize(150, 20); pill:SetPoint("TOPRIGHT", -8, -5)
      local vt = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      vt:SetPoint("CENTER", pill, "CENTER", 0, 0)
      b:SetScript("OnClick", function()
        local idx = 1
        for k, v in ipairs(def.values) do if v == DB.set[def.key] then idx = k end end
        DB.set[def.key] = def.values[idx % #def.values + 1]
        applySettings()
      end)
      addRow(def, b, 30, function()
        local idx = 1
        for k, v in ipairs(def.values) do if v == DB.set[def.key] then idx = k end end
        vt:SetText("<  " .. def.names[idx] .. "  >")
        vt:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3])
      end)
    end
  end

  -- Fuss: Zuruecksetzen + Tipp
  local reset = CreateFrame("Button", nil, f)
  reset:SetSize(140, 22)
  reset.t = reset:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  reset.t:SetAllPoints(); reset.t:SetJustifyH("LEFT"); reset.t:SetText("Standard wiederherstellen")
  reset.t:SetTextColor(0.7, 0.7, 0.75)
  reset:SetScript("OnEnter", function(s) s.t:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3]) end)
  reset:SetScript("OnLeave", function(s) s.t:SetTextColor(0.7, 0.7, 0.75) end)
  reset:SetScript("OnClick", function()
    for k, v in pairs(DEFAULTS) do DB.set[k] = v end
    applySettings()
  end)
  local tip = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  tip:SetText("Öffnen mit /ku opt")

  f.layout = function()
    local y = -52
    for _, row in ipairs(f.rows) do
      local vis = (not row.def.show) or row.def.show()
      if vis then
        row.frame:ClearAllPoints()
        row.frame:SetPoint("TOPLEFT", f, "TOPLEFT", 14, y)
        row.frame:Show()
        y = y - row.h
      else
        row.frame:Hide()
      end
    end
    reset:ClearAllPoints(); reset:SetPoint("TOPLEFT", f, "TOPLEFT", 18, y - 12)
    tip:ClearAllPoints(); tip:SetPoint("TOPRIGHT", f, "TOPRIGHT", -18, y - 16)
    f:SetHeight(-y + 46)
  end

  f:Hide()
  settingsFrame = f
  tinsert(UISpecialFrames, "ForeverGuildSettings")
end

openSettings = function()
  if not settingsFrame then buildSettings() end
  if settingsFrame:IsShown() then settingsFrame:Hide()
  else refreshSettings(); settingsFrame:Show() end
end

------------------------------------------------------------------ Events
local handlers = {}

------------------------------------------------------------------ Todes-Log
local VERSION = "1.10.0"
local lastDeath = {}
local deathFrame, deathRows = nil, {}
local DROWS = 15

local function refreshDeaths()
  if not deathFrame or not deathFrame:IsShown() then return end
  local n = #DB.deaths
  for i = 1, DROWS do
    local d, row = DB.deaths[n - i + 1], deathRows[i]
    if d then
      row:SetText(string.format("|cff888888%s|r  %s%s|r  %s|cffaaaaaa%s|r", d.date, classHex(d.file), d.name,
        d.level and ("Lvl " .. d.level .. "  ") or "", d.zone or "?"))
    else
      row:SetText("")
    end
  end
end

local function recordDeath(name, zone, lvl, silent)
  local now = GetTime()
  if lastDeath[name] and now - lastDeath[name] < 15 then return end -- Doppelmeldung (Addon + Chat)
  lastDeath[name] = now
  local file = members[name] and members[name].file
  table.insert(DB.deaths, { name = name, zone = zone, level = lvl, date = date("%d.%m. %H:%M"), file = file })
  while #DB.deaths > 100 do table.remove(DB.deaths, 1) end
  if not silent then out("|cffff4444" .. name .. " ist gestorben|r in " .. (zone or "?") .. ".") end
  refreshDeaths()
end

local function buildDeathLog()
  local f = CreateFrame("Frame", "ForeverGuildDeaths", UIParent)
  f:SetSize(520, DROWS * 20 + 92)
  f:SetPoint("CENTER", -300, 0)
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  local bg = themeTexture(f, "BACKGROUND", THEME.bg); bg:SetAllPoints()
  local head = themeTexture(f, "ARTWORK", THEME.header)
  head:SetPoint("TOPLEFT", 2, -2); head:SetPoint("TOPRIGHT", -2, -2); head:SetHeight(44)
  local accent = themeTexture(f, "OVERLAY", THEME.accent)
  accent:SetPoint("TOPLEFT", 2, -46); accent:SetPoint("TOPRIGHT", -2, -46); accent:SetHeight(2)
  local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  t:SetPoint("TOPLEFT", 16, -12); t:SetText(BRAND .. "  •  Todes-Log")
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", 2, 2)
  for i = 1, DROWS do
    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", 16, -66 - (i - 1) * 20)
    fs:SetWidth(488); fs:SetJustifyH("LEFT")
    deathRows[i] = fs
  end
  f:SetScript("OnShow", refreshDeaths)
  f:Hide()
  deathFrame = f
  tinsert(UISpecialFrames, "ForeverGuildDeaths")
end

local function toggleDeaths()
  if deathFrame:IsShown() then deathFrame:Hide() else deathFrame:Show() end
end

------------------------------------------------------------------ Minimap-Icon
local function placeMM(btn)
  local a = math.rad(DB.mmAngle or 200)
  btn:ClearAllPoints()
  btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * 80, math.sin(a) * 80)
end

local function buildMinimap()
  local b = CreateFrame("Button", "ForeverGuildMM", Minimap)
  b:SetSize(31, 31); b:SetFrameStrata("MEDIUM"); b:SetFrameLevel(8)
  local ic = b:CreateTexture(nil, "ARTWORK")
  ic:SetSize(20, 20); ic:SetPoint("TOPLEFT", 6, -5)
  ic:SetTexture("Interface\\Icons\\Spell_Shadow_DeathCoil")
  local ring = b:CreateTexture(nil, "OVERLAY")
  ring:SetSize(53, 53); ring:SetPoint("TOPLEFT")
  ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetScript("OnClick", function(_, btn)
    if btn == "LeftButton" then
      if IsShiftKeyDown() then openSettings() else toggleDeaths() end
    else if listFrame:IsShown() then listFrame:Hide() else listFrame:Show() end end
  end)
  b:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function(s)
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local sc = Minimap:GetEffectiveScale()
      DB.mmAngle = math.deg((math.atan2 or math.atan)(cy / sc - my, cx / sc - mx))
      placeMM(s)
    end)
  end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(BRAND .. "  v" .. VERSION)
    GameTooltip:AddLine("Linksklick: Todes-Log", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Rechtsklick: Wer ist wo", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Shift+Linksklick: Einstellungen", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Ziehen: Icon verschieben", 0.8, 0.8, 0.8)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  placeMM(b)
end

------------------------------------------------------------------ PvP-Warnsystem
local pvpFrame
local pvpSeen = {}

-- Retail's tooltip and target APIs can return opaque "secret" values while
-- Blizzard is processing a protected world-cursor tooltip.  Never branch on
-- such a value and never pass a secret unit token into another Unit* API.
local function isSecretValue(value)
  if type(issecretvalue) ~= "function" then return false end
  local ok, secret = pcall(issecretvalue, value)
  return ok and secret == true
end

local function publicUnitToken(value)
  if type(value) ~= "string" or isSecretValue(value) then return nil end
  return value
end

local function publicString(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, value = pcall(fn, ...)
  if not ok or type(value) ~= "string" or isSecretValue(value) then return nil end
  return value
end

local function publicBool(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, value = pcall(fn, ...)
  if not ok or type(value) ~= "boolean" or isSecretValue(value) then return nil end
  return value
end

------------------------------------------------------------------ Layer-Hop / Layer-Net
-- Forever exposes no documented GetAllLayers()/SwitchToLayer() API.  The
-- client does, however, expose a layer-like zone UID in nearby creature and
-- vehicle GUIDs.  This is intentionally treated as experimental: values are
-- read only outside combat/instances and are never used for secure actions.
local LAYER_STALE = 180
local LAYER_SEND_GAP = 12
local layerLastSent = 0

local function layerUnitGUID(unit)
  if type(unit) ~= "string" or type(UnitGUID) ~= "function" then return nil end
  local ok, guid = pcall(UnitGUID, unit)
  if not ok or type(guid) ~= "string" or isSecretValue(guid) then return nil end
  return guid
end

local function layerIDFromGUID(guid)
  if type(guid) ~= "string" or isSecretValue(guid) then return nil end
  local kind, _, _, _, zoneUID = strsplit("-", guid)
  if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
  local id = tonumber(zoneUID)
  if not id or id <= 0 then return nil end
  return id
end

local function layerMapID()
  if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
  local ok, map = pcall(C_Map.GetBestMapForUnit, "player")
  if ok and type(map) == "number" and not isSecretValue(map) then return map end
end

local function layerZoneText()
  local ok, zone = pcall(GetZoneText)
  if ok and type(zone) == "string" and not isSecretValue(zone) and zone ~= "" then return zone end
  return "Zone unbekannt"
end

local function layerInInstance()
  if type(IsInInstance) ~= "function" then return false end
  local ok, inside = pcall(IsInInstance)
  return ok and inside == true
end

local function layerCandidateUnits()
  local units = { "target", "mouseover" }
  if C_NamePlate and C_NamePlate.GetNamePlates then
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if ok and type(plates) == "table" then
      for _, plate in ipairs(plates) do
        local okUnit, unit = pcall(function()
          local frame = plate and plate.UnitFrame
          return frame and frame.unit
        end)
        if not okUnit then unit = nil end
        if type(unit) == "string" and not isSecretValue(unit) then units[#units + 1] = unit end
      end
    end
  end
  return units
end

local function layerDetectID()
  local counts = {}
  for _, unit in ipairs(layerCandidateUnits()) do
    local id = layerIDFromGUID(layerUnitGUID(unit))
    if id then counts[id] = (counts[id] or 0) + 1 end
  end
  local best, score = nil, 0
  for id, n in pairs(counts) do
    if n > score then best, score = id, n end
  end
  return best, score
end

local function layerRememberID(map, id)
  if not (DB and map and id) then return end
  DB.layerIds = DB.layerIds or {}
  local key = tostring(map)
  DB.layerIds[key] = DB.layerIds[key] or {}
  for _, known in ipairs(DB.layerIds[key]) do if known == id then return end end
  DB.layerIds[key][#DB.layerIds[key] + 1] = id
end

local function layerLabel(map, id)
  if not (map and id) then return "Layer unbekannt" end
  local ids, seen = {}, {}
  local function add(value)
    value = tonumber(value)
    if value and not seen[value] then seen[value] = true; ids[#ids + 1] = value end
  end
  if DB and DB.layerIds and DB.layerIds[tostring(map)] then
    for _, value in ipairs(DB.layerIds[tostring(map)]) do add(value) end
  end
  add(id)
  for _, peer in pairs(layerPeers) do if peer.map == map then add(peer.layer) end end
  table.sort(ids)
  for i, value in ipairs(ids) do if value == id then return "Layer " .. i end end
  return "Layer ?"
end

local function layerStateMessage()
  if not (layerState.map and layerState.id) then return nil end
  local host = DB and DB.set and DB.set.layerHost and 1 or 0
  local zone = tostring(layerState.zone or ""):gsub("[:|]", " ")
  return string.format("LY:STATE:%d:%d:%d:%s", layerState.map, layerState.id, host, zone)
end

local function sendLayerAddon(msg, channel, target)
  if type(msg) ~= "string" or msg == "" then return false end
  local fn = C_ChatInfo and C_ChatInfo.SendAddonMessage or SendAddonMessage
  if type(fn) ~= "function" then return false end
  local ok = pcall(fn, PREFIX, msg, channel, target)
  return ok
end

local function broadcastLayer(msg)
  if IsInGuild and IsInGuild() then sendLayerAddon(msg, "GUILD") end
  if IsInGroup and IsInGroup() then
    if IsInRaid and IsInRaid() then sendLayerAddon(msg, "RAID") else sendLayerAddon(msg, "PARTY") end
    if layerInInstance() then sendLayerAddon(msg, "INSTANCE_CHAT") end
  end
end

local function broadcastLayerState(force)
  local msg = layerStateMessage()
  if not msg then return end
  local now = GetTime()
  if not force and now - layerLastSent < LAYER_SEND_GAP then return end
  layerLastSent = now
  broadcastLayer(msg)
  for _, peer in pairs(layerPeers) do
    if peer.full and layerPeerFresh(peer) then sendLayerAddon(msg, "WHISPER", peer.full) end
  end
end

local function rememberLayerPeer(name, sender, map, id, host, zone)
  if not name or name == myName then return end
  local p = layerPeers[name] or {}
  p.t = GetTime(); p.full = sender or p.full
  p.map = tonumber(map) or p.map
  p.layer = tonumber(id) or p.layer
  if host ~= nil then p.host = tonumber(host) == 1 end
  p.zone = zone and zone ~= "" and zone or p.zone
  layerPeers[name] = p
  if p.map and p.layer then layerRememberID(p.map, p.layer) end
  if DB then
    DB.layerPeers = DB.layerPeers or {}
    DB.layerPeers[name] = { t = time(), full = p.full, map = p.map, layer = p.layer, host = p.host, zone = p.zone }
  end
end

layerPeerFresh = function(peer)
  return peer and peer.t and GetTime() - peer.t < LAYER_STALE
end

layerPeerText = function(peer)
  if not peer then return "Layer unbekannt" end
  local label = layerLabel(peer.map, peer.layer)
  if peer.layer then label = label .. " (ID " .. tostring(peer.layer) .. ")" end
  if layerState.map and peer.map and peer.map ~= layerState.map then return label .. " • andere Zone" end
  if layerState.id and peer.layer == layerState.id then return label .. " • gleiche Ebene" end
  if layerState.id and peer.layer then return label .. " • andere Ebene" end
  return label
end

layerSummaryText = function()
  if layerState.status == "instance" then
    return "|cffaaaaaaLayer-Scan pausiert: Instanz, Schlachtfeld oder Raid.|r"
  end
  if not layerState.id then
    return "|cffffcc44Layer: unbekannt|r  |cffaaaaaaNPC/Fahrzeug anvisieren oder Namensplaketten aktivieren.|r"
  end
  local label = layerLabel(layerState.map, layerState.id)
  local changed = layerState.changedAt > 0 and " • Wechsel " .. date("%H:%M:%S", layerState.changedAt) or ""
  return "|cffffd100" .. label .. "|r  |cffaaaaaa(ID " .. tostring(layerState.id) .. ")  " ..
    (layerState.zone or "Zone unbekannt") .. changed .. "|r"
end

layerScan = function(silent)
  if not DB then return end
  if layerInInstance() then
    layerState.status = "instance"
    layerState.id = nil
    if not silent and refreshList then refreshList() end
    return
  end
  if InCombatLockdown and InCombatLockdown() then return end
  local map = layerMapID()
  local id = layerDetectID()
  if not (map and id) then return end
  local changed = layerState.map ~= map or layerState.id ~= id
  layerState.map, layerState.id, layerState.zone = map, id, layerZoneText()
  layerState.t, layerState.status, layerState.source = GetTime(), "detected", "npc-guid"
  if changed then layerState.changedAt = time() end
  layerRememberID(map, id)
  DB.layerCurrent = { map = map, id = id, zone = layerState.zone, seen = time() }
  if changed then broadcastLayerState(true) else broadcastLayerState(false) end
  if changed and not silent and refreshList then refreshList() end
end

requestLayerHop = function(name, peer)
  peer = peer or layerPeers[name]
  if not name then return end
  if peer and layerState.map and peer.map == layerState.map and layerState.id and peer.layer == layerState.id then
    out(name .. " ist bereits auf deiner aktuellen Ebene.")
    return
  end
  local map = peer and peer.map or layerState.map or 0
  local id = peer and peer.layer or 0
  local msg = "LY:ASK:" .. tostring(name) .. ":" .. tostring(map) .. ":" .. tostring(id)
  broadcastLayer(msg)
  local full = peer and peer.full or fullName(name)
  if full then sendLayerAddon(msg, "WHISPER", full) end
  out("Layer-Hop-Anfrage an " .. name .. " gesendet. Bitte Gruppeneinladung annehmen und Gruppe für den Wechsel behalten.")
end

layerHopAny = function()
  local candidate
  for name, peer in pairs(layerPeers) do
    if layerPeerFresh(peer) and (not layerState.map or not peer.map or peer.map == layerState.map) and
      (not layerState.id or not peer.layer or peer.layer ~= layerState.id) then
      if peer.host then candidate = { name = name, peer = peer }; break end
      candidate = candidate or { name = name, peer = peer }
    end
  end
  if candidate then requestLayerHop(candidate.name, candidate.peer)
  else out("Kein anderer bestätigter Layer bekannt. Erst Layer aktualisieren oder einen Gildenkollegen /fg layer ausführen lassen.") end
end

layerPing = function()
  layerScan(true)
  broadcastLayer("LY:HELLO")
  broadcastLayerState(true)
end

local function buildPvPWarn()
  local f = CreateFrame("Frame", "ForeverGuildPvP", UIParent)
  f:SetSize(340, 70)
  f:SetPoint("TOP", 0, -140)
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:Hide()
  local bg = f:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); setColor(bg, 0.25, 0, 0, 0.9)
  local function edge(p1, p2, w, h)
    local t = f:CreateTexture(nil, "BORDER")
    setColor(t, 1, 0, 0, 1)
    t:SetPoint(p1); t:SetPoint(p2)
    if w then t:SetWidth(w) end
    if h then t:SetHeight(h) end
  end
  edge("TOPLEFT", "TOPRIGHT", nil, 3); edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 3)
  edge("TOPLEFT", "BOTTOMLEFT", 3, nil); edge("TOPRIGHT", "BOTTOMRIGHT", 3, nil)
  f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  f.text:SetPoint("CENTER")
  f.t = 0
  f:SetScript("OnUpdate", function(self, el)
    self.t = self.t + el
    if self.t > 4 then self:Hide(); return end
    local x = 0
    if self.t < 0.6 then x = math.sin(self.t * 70) * 7 * (1 - self.t / 0.6) end -- Rumble
    self:ClearAllPoints(); self:SetPoint("TOP", x, -140)
  end)
  pvpFrame = f
end

------------------------------------------------------------------ Tooltip-Erweiterung
local function tipUnit(tt)
  if not tt.GetUnit then return end
  local okUnit, _, rawUnit = pcall(tt.GetUnit, tt)
  local unit = okUnit and publicUnitToken(rawUnit) or nil
  if not unit then return end
  local isPlayer = publicBool(UnitIsPlayer, unit)
  if isPlayer ~= true then return end
  local name = publicString(UnitName, unit)
  if not name then return end
  local okGuild, gname, rank = pcall(GetGuildInfo, unit)
  if not okGuild or isSecretValue(gname) or isSecretValue(rank) then return end
  local playerGuild = publicString(GetGuildInfo, "player")
  if gname and gname == playerGuild and rank then
    tt:AddLine("Gildenrang: " .. rank, 0.4, 0.8, 1)
  end
  local isAFK = publicBool(UnitIsAFK, unit)
  local isDND = publicBool(UnitIsDND, unit)
  local status = isAFK == true and "AFK" or (isDND == true and "DND" or "Online")
  tt:AddLine("Status: " .. status, 0.7, 0.7, 0.7)
  if members[name] then tt:AddLine(GUILDNAME .. "-Addon", 1, 0.48, 0.1) end
  local p = profText(name)
  if p then tt:AddLine("Berufe: " .. p, 0.8, 0.8, 0.8, true) end
  local h = DB.creators[name]
  if h then tt:AddLine("Content Creator: " .. h, 1, 0.5, 1) end
  tt:Show()
end

local function hookTooltip()
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt)
      if tt == GameTooltip then tipUnit(tt) end
    end)
  else
    GameTooltip:HookScript("OnTooltipSetUnit", tipUnit)
  end
end

local f = CreateFrame("Frame")
for _, e in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE",
  "TRADE_SKILL_DATA_SOURCE_CHANGED", "TRADE_SKILL_NAME_UPDATE" }) do
  pcall(f.RegisterEvent, f, e)
end
f:SetScript("OnEvent", function(_, event, ...) if handlers[event] then handlers[event](...) end end)
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "CHAT_MSG_ADDON", "PLAYER_LEVEL_UP", "PLAYER_DEAD",
  "GUILD_ROSTER_UPDATE", "CHAT_MSG_LOOT", "SKILL_LINES_CHANGED", "CHAT_MSG_GUILD", "PLAYER_TARGET_CHANGED",
  "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA",
  "ZONE_CHANGED", "WORLD_STATE_TIMER_START", "CHAT_MSG_SYSTEM", "UNIT_HEALTH", "GROUP_ROSTER_UPDATE" }) do f:RegisterEvent(e) end
function handlers.ADDON_LOADED(name)
  if name ~= "ForeverGuild" then return end
  ForeverGuildDB = ForeverGuildDB or {}
  DB = ForeverGuildDB
  DB.interval = DB.interval or 10
  if DB.dots == nil then DB.dots = true end
  DB.buffs = DB.buffs or {}
  DB.loot = DB.loot or {}
  DB.attend = DB.attend or {}
  DB.deaths = DB.deaths or {}
  DB.set = DB.set or {}
  local D = { dots = DB.dots ~= false, mini = true, icons = false, showName = false, showLevel = false,
    showRank = false, showHealth = false, iconSize = 13, miniSize = 10, filter = "off", minL = 1, maxL = 100,
    below = 5, above = 5, hpAlert = 0, deathChat = DB.deathChat ~= false, milestones = true,
    profMile = true, rareLoot = true, autoLog = false, labelSize = 0, miniLabel = true, hideGroup = true,
    layerHost = false }
  for k, v in pairs(D) do if DB.set[k] == nil then DB.set[k] = v end end
  DB.profs = DB.profs or {}
  DB.recipes = DB.recipes or {}
  for k, v in pairs(DB.profs) do profs[k] = v end
  DB.creators = DB.creators or {}
  DB.layerIds = DB.layerIds or {}
  DB.layerPeers = DB.layerPeers or {}
  for name, saved in pairs(DB.layerPeers) do
    if type(saved) == "table" and saved.map and saved.layer and saved.t and time() - saved.t < 1800 then
      layerPeers[name] = { t = GetTime(), full = saved.full, map = saved.map, layer = saved.layer,
        host = saved.host and true or false, zone = saved.zone }
    end
  end
  if DB.pvp == nil then DB.pvp = true end
  if DB.pvpSound == nil then DB.pvpSound = false end
  if DB.deathChat == nil then DB.deathChat = true end
  DB.mmAngle = DB.mmAngle or 200
end

function handlers.PLAYER_LOGIN()
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
  elseif RegisterAddonMessagePrefix then RegisterAddonMessagePrefix(PREFIX) end
  rebuildGroup()
  DB.logApplied = DB.set.autoLog and true or false
  if DB.set.autoLog and LoggingChat then pcall(LoggingChat, true) end
  buildList(); buildBuffFrame(); hookMap(); buildDeathLog(); buildMinimap(); buildPvPWarn(); hookTooltip()
  local acc, mapAcc, miniAcc, rosAcc, layerAcc = 0, 0, 0, 50, 0
  f:SetScript("OnUpdate", function(_, el)
    acc = acc + el; mapAcc = mapAcc + el; miniAcc = miniAcc + el; rosAcc = rosAcc + el; layerAcc = layerAcc + el
    if acc >= DB.interval then acc = 0; broadcastPos() end
    if mapAcc >= 1 then mapAcc = 0; hookMap(); updatePins() end
    if miniAcc >= 0.2 then miniAcc = 0; updateMini() end
    if rosAcc >= 60 then rosAcc = 0; requestRoster() end
    if layerAcc >= 2 then layerAcc = 0; layerScan(true) end
  end)
  C_Timer.After(6, function() send("H"); broadcastPos(); broadcastProfs(); layerPing() end)
  out("Addon geladen. /ku oder /fg öffnet die Liste, /ku hilfe zeigt alle Befehle.")
end

local function checkProfMilestones()
  if not (DB and C_SkillInfo and C_SkillInfo.GetSkillLineInfo) then return end
  DB.profRank = DB.profRank or {}
  for i = 1, getSkillLineCount() do
    local name, isHeader, rank = getSkillLine(i)
    if name and not isHeader and PROFS[name] and rank then
      local old = DB.profRank[name]
      if old and DB.set.profMile and IsInGuild() and rank >= 75 and math.floor(rank / 75) > math.floor(old / 75) then
        sendChat(string.format("[KU] %s hat %s %d erreicht", myName, name, math.floor(rank / 75) * 75), "GUILD")
      end
      DB.profRank[name] = rank
    end
  end
end

local function fmtPattern(fmt)
  if not fmt then return nil end
  local p = (fmt:gsub("([%(%)%.%[%]%+%-%*%?%^%$])", "%%%1"))
  p = (p:gsub("%%s", "(.+)"))
  return "^" .. p .. "$"
end

local RARE_COLORS = { a335ee = true, ff8000 = true, e6cc80 = true } -- episch, legendaer, artefakt
local function checkRareLoot(msg)
  if not (DB.set.rareLoot and IsInGuild()) then return end
  for _, pat in ipairs({ fmtPattern(LOOT_ITEM_SELF), fmtPattern(LOOT_ITEM_PUSHED_SELF) }) do
    local link = pat and msg:match(pat)
    if link then
      local col = link:match("|cff(%x%x%x%x%x%x)|H")
      if col and RARE_COLORS[col:lower()] then
        sendChat(string.format("[KU] %s hat %s erbeutet", myName, link), "GUILD")
      end
      return
    end
  end
end

function handlers.SKILL_LINES_CHANGED()
  checkProfMilestones()
  if DB and not FG_PROF_T then
    FG_PROF_T = true
    C_Timer.After(5, function() FG_PROF_T = nil; broadcastProfs() end)
  end
end

function handlers.GROUP_ROSTER_UPDATE()
  rebuildGroup()
  layerScan(false)
  if mode == "layers" then layerPing() end
end

function handlers.PLAYER_ENTERING_WORLD()
  C_Timer.After(1, function() layerScan(false); if mode == "layers" then layerPing() end end)
end

function handlers.ZONE_CHANGED_NEW_AREA()
  layerState.id, layerState.map, layerState.status = nil, nil, "unknown"
  C_Timer.After(1, function() layerScan(false); if mode == "layers" then layerPing() end end)
end

function handlers.ZONE_CHANGED()
  layerScan(false)
end

function handlers.PLAYER_TARGET_CHANGED()
  layerScan(false)
  if not DB or not DB.pvp then return end
  local targetExists = publicBool(UnitExists, "target")
  local sameUnit = publicBool(UnitIsUnit, "target", "player")
  local targetPVP = publicBool(UnitIsPVP, "target")
  local canAttack = publicBool(UnitCanAttack, "player", "target")
  if targetExists ~= true or sameUnit == true then return end
  -- A nil result means the client deliberately hid the value.  Skipping the
  -- warning is safer than tainting the secure target/camera path.
  if targetPVP == true and canAttack == true then
    local key = publicString(UnitGUID, "target") or publicString(UnitName, "target") or "target"
    local now = GetTime()
    if now - (pvpSeen[key] or 0) >= 10 then
      pvpSeen[key] = now
      pvpFrame.text:SetText("|cffff3333PVP!|r " .. (publicString(UnitName, "target") or "?"))
      pvpFrame.t = 0
      pvpFrame:Show()
      if DB.pvpSound then pcall(PlaySound, 8959) end
    end
  end
end

function handlers.UPDATE_MOUSEOVER_UNIT()
  layerScan(false)
end

function handlers.NAME_PLATE_UNIT_ADDED()
  layerScan(true)
end

function handlers.WORLD_STATE_TIMER_START()
  if DB then DB.layerRefreshAt = time() end
  if mode == "layers" then refreshList() end
end

function handlers.CHAT_MSG_SYSTEM(msg)
  if type(msg) == "string" and msg:lower():find("refresh world", 1, true) then
    if DB then DB.layerRefreshAt = time() end
    if mode == "layers" then refreshList() end
  end
end

function handlers.GUILD_ROSTER_UPDATE()
  if GetNumGuildMembers then
    for i = 1, GetNumGuildMembers() do
      local n, rank = GetGuildRosterInfo(i)
      if n then rankCache[short(n)] = rank; fullCache[short(n)] = n end
    end
  end
  refreshList()
end

local lastHpSend = 0
function handlers.UNIT_HEALTH(unit)
  if unit ~= "player" or not DB then return end
  local hp = safeHealthPercent("player")
  if hp and hp < 60 and GetTime() - lastHpSend > 3 then
    lastHpSend = GetTime()
    broadcastPos()
  end
end
function handlers.TRADE_SKILL_SHOW() scanLater(scanTrade) end
function handlers.TRADE_SKILL_LIST_UPDATE() scanLater(scanTrade) end
function handlers.TRADE_SKILL_DATA_SOURCE_CHANGED() scanLater(scanTrade) end
function handlers.TRADE_SKILL_NAME_UPDATE() scanLater(scanTrade) end
function handlers.CHAT_MSG_ADDON(prefix, msg, _, sender)
  if prefix ~= PREFIX then return end
  local name = short(sender)
  local kind, rest = msg:match("^(%a+):?(.*)$")
  if kind == "P" then
    local m, x, y, file, lvl, hp = rest:match("^(%d+):([%d%.]+):([%d%.]+):(%a*):(%d+):?(%d*)$")
    if m then
      local hpn = tonumber(hp)
      members[name] = { map = tonumber(m), x = tonumber(x), y = tonumber(y), file = file, level = tonumber(lvl),
        hp = hpn, t = GetTime(), full = sender }
      if name ~= myName then hpAlert(name, hpn) end
    end
  elseif kind == "G" then
    local m, x, y = rest:match("^(%d+):([%d%.]+):([%d%.]+)$")
    if m then
      pings[#pings + 1] = { map = tonumber(m), x = tonumber(x), y = tonumber(y), t = GetTime() }
      out(name .. " hat einen Ping auf der Karte gesetzt.")
      pcall(PlaySound, 8959)
      updatePins()
    end
  elseif kind == "L" then
    if name ~= myName then out(name .. " hat Level " .. rest .. " erreicht!") end
  elseif kind == "D" then
    if name ~= myName then
      local lvl, zone = rest:match("^(%d*):(.*)$")
      recordDeath(name, zone or rest, tonumber(lvl))
    end
  elseif kind == "R" then
    profs[name] = rest
    DB.profs[name] = rest
    refreshList()
  elseif kind == "C" then
    local prof, i, _, body = rest:match("^([^:]+):(%d+):(%d+)(.*)$")
    if prof then
      DB.recipes[name] = DB.recipes[name] or {}
      if tonumber(i) == 1 or not DB.recipes[name][prof] then DB.recipes[name][prof] = {} end
      local t = DB.recipes[name][prof]
      for n in body:gmatch(";([^;]+)") do t[#t + 1] = n end
      refreshList()
    end
  elseif kind == "LY" then
    if rest == "HELLO" then
      if name ~= myName then
        rememberLayerPeer(name, sender)
        sendLayerAddon("LY:HERE", "WHISPER", sender)
        broadcastLayerState(true)
      end
      refreshList()
    elseif rest == "HERE" then
      if name ~= myName then rememberLayerPeer(name, sender) end
      refreshList()
    else
      local map, id, host, zone = rest:match("^STATE:(%d+):(%d+):([01]):?(.*)$")
      if map and id then
        rememberLayerPeer(name, sender, tonumber(map), tonumber(id), host, zone)
        refreshList()
      else
        local target, wantMap, wantID = rest:match("^ASK:([^:]+):?(%d*):?(%d*)$")
        if target == myName and name ~= myName then
          local wantedMap, wantedID = tonumber(wantMap), tonumber(wantID)
          local onRequestedLayer = (not wantedMap or wantedMap == 0 or layerState.map == wantedMap) and
            (not wantedID or wantedID == 0 or layerState.id == wantedID)
          if not onRequestedLayer then
            out(name .. " fragt deinen Layer an, aber deine aktuelle Ebene passt nicht zum Ziel.")
          elseif DB.set.layerHost then
            invitePlayer(sender or fullName(name))
            out("Layer-Hop: " .. name .. " wurde automatisch eingeladen.")
          elseif StaticPopupDialogs and StaticPopup_Show then
            out("|cffffcc44Layer-Hop-Anfrage von " .. name .. ".|r Bitte Einladung bestätigen.")
            StaticPopupDialogs["FG_LAYER_INVITE"] = StaticPopupDialogs["FG_LAYER_INVITE"] or {
              text = "%s moechte zu deinem Layer wechseln. In Gruppe einladen?", button1 = "Einladen", button2 = "Ablehnen",
              OnAccept = function(_, data) if data then invitePlayer(data) end end,
              timeout = 30, whileDead = true, hideOnEscape = true, preferredIndex = 3,
            }
            StaticPopup_Show("FG_LAYER_INVITE", name, nil, sender or fullName(name))
          end
        end
      end
    end
  elseif kind == "H" then
    if name ~= myName then broadcastPos(); broadcastProfs() end
  end
end

function handlers.PLAYER_LEVEL_UP(lvl)
  send("L:" .. tostring(lvl))
  lvl = tonumber(lvl)
  if DB.set.milestones and lvl and lvl % 5 == 0 and IsInGuild() then
    sendChat(string.format("[KU] %s hat Level %d erreicht (%s)", myName, lvl, UnitClass("player") or ""), "GUILD")
  end
end
function handlers.PLAYER_DEAD()
  local zone, lvl = GetZoneText() or "?", UnitLevel("player")
  local className = UnitClass("player") or ""
  recordDeath(myName, zone, lvl, true)
  send("D:" .. lvl .. ":" .. zone)
  if DB.set.deathChat and IsInGuild() then
    local msg = string.format("[KU] %s ist gestorben in %s (Lvl %d %s)", myName, zone, lvl, className)
    sendChat(msg, "GUILD")
  end
end

-- Zweitsystem: Gildenchat auswerten (fuer Mitglieder ohne Addon-Nachricht)
function handlers.CHAT_MSG_GUILD(msg, sender)
  local name = short(sender)
  if name == myName then return end
  local zone, lvl = msg:match("^%[KU%] .- ist gestorben in (.-) %(Lvl (%d+)")
  if zone then recordDeath(name, zone, tonumber(lvl)) end
end

function handlers.CHAT_MSG_LOOT(msg)
  if not DB then return end
  checkRareLoot(msg)
  table.insert(DB.loot, date("%d.%m. %H:%M") .. " " .. msg)
  while #DB.loot > 200 do table.remove(DB.loot, 1) end
end


------------------------------------------------------------------ Slash
local function runCheck()
  out("ForeverGuild v" .. VERSION .. " | Forever-API 16001")
  out("C_SkillInfo: " .. ((C_SkillInfo and C_SkillInfo.GetSkillLineInfo) and "OK" or "fehlt"))
  out("C_TradeSkillUI: " .. ((C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs) and "OK" or "fehlt"))
  local logging = chatLogState()
  if logging == true then
    out("Chatlog: AN (WoWChatLog.txt wird vom Client geschrieben)")
  elseif logging == false then
    out("Chatlog: AUS - /chatlog einschalten oder /fg opt nutzen")
  else
    out("Chatlog: Status unbekannt")
  end
  if DB then
    local previous = DB.__fgProbe
    DB.__fgProbe = true
    out("SavedVariables-Probe: " .. (previous and "vorheriger Wert geladen" or "frische Probe; nach /reload erneut prüfen"))
    out("Layer: " .. (layerSummaryText and layerSummaryText() or "unbekannt"))
    out("Layer-Host: " .. (DB.set.layerHost and "an" or "aus") .. " | Scan: NPC-/Fahrzeug-GUIDs")
  else
    out("SavedVariables: DB ist noch nicht geladen")
  end
end

local function slash(input)
  local cmd, arg = (input or ""):match("^(%S*)%s*(.-)$")
  cmd = cmd:lower()
  if cmd == "" or cmd == "liste" then
    if listFrame:IsShown() then listFrame:Hide() else listFrame:Show() end
  elseif cmd == "ping" then
    local m, x, y = getPos()
    if m then sendPing(m, x, y) else out("Position gerade nicht verfügbar.") end
  elseif cmd == "punkte" then
    DB.set.dots = not DB.set.dots; out("Kartenpunkte: " .. (DB.set.dots and "an" or "aus")); updatePins()
  elseif cmd == "intervall" then
    local n = tonumber(arg)
    if n and n >= 2 and n <= 60 then DB.interval = n; out("Update-Intervall: " .. n .. " Sek.")
    else out("Bitte eine Zahl von 2 bis 60 angeben.") end
  elseif cmd == "beruf" then
    local found = false
    for n, s in pairs(profs) do
      if arg ~= "" and s:lower():find(arg:lower(), 1, true) then
        out(n .. ": " .. s:gsub("=", " "):gsub(";", ", ")); found = true
      end
    end
    if not found then out("Niemand mit '" .. arg .. "' bekannt.") end
  elseif cmd == "anw" then
    if arg == "liste" then
      for _, e in ipairs({ unpack(DB.attend, math.max(1, #DB.attend - 4)) }) do out(e.date .. ": " .. e.names) end
    else
      local names = {}
      for i = 1, GetNumGroupMembers() do
        local n = GetRaidRosterInfo(i)
        if n then names[#names + 1] = short(n) end
      end
      table.insert(DB.attend, { date = date("%d.%m.%Y %H:%M"), names = table.concat(names, ", ") })
      out("Anwesenheit gespeichert (" .. #names .. " Spieler). '/fg anw liste' zeigt die letzten 5.")
    end
  elseif cmd == "loot" then
    for i = math.max(1, #DB.loot - 14), #DB.loot do out(DB.loot[i]) end
  elseif cmd == "opt" or cmd == "optionen" or cmd == "einstellungen" then
    openSettings()
  elseif cmd == "berufe" then
    openProfs()
  elseif cmd == "layer" or cmd == "layers" then
    local sub = (arg or ""):lower()
    if sub == "scan" or sub == "refresh" then
      layerPing(); if listFrame:IsShown() then refreshList() end
      out("Layer-Daten aktualisiert.")
    elseif sub == "hop" or sub == "any" then
      layerHopAny()
    elseif sub == "host" then
      DB.set.layerHost = not DB.set.layerHost
      out("Layer-Host: " .. (DB.set.layerHost and "an" or "aus"))
    else
      if not listFrame:IsShown() then listFrame:Show() end
      setMode("layers")
    end
  elseif cmd == "finder" then
    if not listFrame:IsShown() then listFrame:Show() end
    setMode("finder")
  elseif cmd == "sync" then
    syncMyRecipes()
  elseif cmd == "check" or cmd == "status" then
    runCheck()
  elseif cmd == "test" then
    if not IsInGuild() then
      out("Du bist in keiner Gilde. Der Test braucht den Gildenchat. Ohne Gilde: Beispieldatei der Bridge nutzen.")
    else
      local cls, lvl = UnitClass("player") or "?", UnitLevel("player")
      local zone = GetZoneText() or "?"
      local lines = {
        string.format("[KU] %s ist gestorben in %s (Lvl %d %s) durch Testwolf", myName, zone, lvl, cls),
        string.format("[KU] %s hat Level 20 erreicht (%s)", myName, cls),
        string.format("[KU] %s hat Alchemie 150 erreicht", myName),
        string.format("[KU] %s hat |cffa335ee|Hitem:19019::::::::|h[Donnerzorn, Klinge der Sturmbringer]|h|r erbeutet", myName),
      }
      local logging = chatLogState()
      if logging == false then
        out("|cffff4444Achtung:|r Der Chatlog ist AUS. Ohne ihn sieht die Bridge nichts. Mit /chatlog einschalten.")
      elseif logging == nil then
        out("|cffffcc44Hinweis:|r Der Chatlog-Status ist auf diesem Client unbekannt.")
      end
      out("Sende " .. #lines .. " Testmeldungen in den Gildenchat ...")
      for i, l in ipairs(lines) do
        C_Timer.After((i - 1) * 1.5, function() sendChat(l, "GUILD") end)
      end
    end
  elseif cmd == "tod" then
    toggleDeaths()
  elseif cmd == "todchat" then
    DB.set.deathChat = not DB.set.deathChat; out("Todesmeldung im Gildenchat: " .. (DB.set.deathChat and "an" or "aus"))
  elseif cmd == "pvp" then
    DB.pvp = not DB.pvp; out("PvP-Warnung: " .. (DB.pvp and "an" or "aus"))
  elseif cmd == "pvpton" then
    DB.pvpSound = not DB.pvpSound; out("PvP-Warnton: " .. (DB.pvpSound and "an" or "aus"))
  elseif cmd == "creator" then
    local nm, h = arg:match("^(%S+)%s*(.-)$")
    if nm and h ~= "" then DB.creators[nm] = h; out("Creator gespeichert: " .. nm .. " = " .. h)
    elseif nm then DB.creators[nm] = nil; out("Creator entfernt: " .. nm)
    else out("/fg creator <Name> <Handle>  (ohne Handle = entfernen)") end
  elseif cmd == "buff" then
    local sub, nm = arg:match("^(%S+)%s*(.-)$")
    if sub == "add" and nm ~= "" then DB.buffs[nm] = true; out("Buff hinzugefügt: " .. nm)
    elseif sub == "del" and nm ~= "" then DB.buffs[nm] = nil; out("Buff entfernt: " .. nm)
    else out("/fg buff add <exakter Buffname>  |  /fg buff del <Buffname>") end
  else
    out("/fg - Liste | /fg ping | /fg punkte | /fg intervall <2-60> | /fg beruf <name>")
    out("/fg anw [liste] | /fg loot | /fg buff add/del <name> | Strg+Klick auf Karte = Ping")
    out("/fg layer | /fg layer scan | /fg layer hop | /fg layer host | /fg berufe | /fg sync | /fg check | /fg opt")
    out("/ku test (Beispielmeldungen für die Discord-Bridge) | /fg tod | /fg todchat | /fg pvp | /fg pvpton | /fg creator <Name> <Handle>")
  end
end
SLASH_FOREVERGUILD1 = "/fg"
SLASH_FOREVERGUILD2 = "/foreverguild"
SLASH_FOREVERGUILD3 = "/ku"
SLASH_FOREVERGUILD4 = "/kritisch"
SlashCmdList["FOREVERGUILD"] = slash


