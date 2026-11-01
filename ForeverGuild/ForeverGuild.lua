-- ForeverGuild v1.4 - Gilden-Addon fuer WoW Forever
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
local lastHit = {}
local playerGUID
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
  if C_Map and C_Map.GetBestMapForUnit then
    local m = C_Map.GetBestMapForUnit("player")
    if not m then return end
    local p = C_Map.GetPlayerMapPosition(m, "player")
    if not p then return end
    local x, y = p:GetXY()
    if not x or (x == 0 and y == 0) then return end
    return m, x, y
  elseif GetPlayerMapPosition then
    if not (WorldMapFrame and WorldMapFrame:IsShown()) and SetMapToCurrentZone then SetMapToCurrentZone() end
    local x, y = GetPlayerMapPosition("player")
    if not x or (x == 0 and y == 0) then return end
    return GetCurrentMapAreaID(), x, y
  end
end

local function broadcastPos()
  local m, x, y = getPos()
  if not m then return end
  local _, file = UnitClass("player")
  local lvl = UnitLevel("player")
  local hpmax = UnitHealthMax("player")
  local hp = (hpmax and hpmax > 0) and math.floor(UnitHealth("player") / hpmax * 100 + 0.5) or 100
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

local function broadcastProfs()
  if not GetNumSkillLines then return end
  local list = {}
  for i = 1, GetNumSkillLines() do
    local name, isHeader, _, rank = GetSkillLineInfo(i)
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
  if GetCurrentMapAreaID then return GetCurrentMapAreaID() end
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
local roster, onlineInfo, view, mode = {}, {}, {}, "who"

local function buildRoster()
  wipe(roster); wipe(onlineInfo)
  if not IsInGuild() then return end
  for i = 1, GetNumGuildMembers() do
    local name, _, _, level, class, zone, _, _, online, _, file = GetGuildRosterInfo(i)
    if name and online then
      local n = short(name)
      roster[#roster + 1] = { name = n, level = level, zone = zone or "?", file = file }
      onlineInfo[n] = { file = file }
    end
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

local function buildView()
  wipe(view)
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

  local q = ((listFrame and listFrame.search and listFrame.search:GetText()) or ""):lower()
  -- Berufe gruppieren
  local groups = {}
  for n, s in pairs(profs) do
    for prof, rank in s:gmatch("([^=;]+)=(%d+)") do
      groups[prof] = groups[prof] or {}
      table.insert(groups[prof], { n = n, r = tonumber(rank) })
    end
  end
  local pnames = {}
  for p in pairs(groups) do
    if q == "" or p:lower():find(q, 1, true) then pnames[#pnames + 1] = p end
  end
  table.sort(pnames)
  for _, p in ipairs(pnames) do
    local g = groups[p]
    table.sort(g, function(a, b) if a.r ~= b.r then return a.r > b.r end return a.n < b.n end)
    view[#view + 1] = { text = "|cffffd100" .. p .. " (" .. #g .. ")|r" }
    for _, e in ipairs(g) do
      local rc = DB.recipes[e.n] and DB.recipes[e.n][p]
      view[#view + 1] = { name = e.n, text = "   " .. nameStr(e.n) .. "  " .. e.r ..
        (rc and ("  |cff888888" .. #rc .. " Rezepte|r") or "") }
    end
  end

  -- Rezept-Suche: wer kann was craften
  if q ~= "" then
    local hits = {}
    for n, byProf in pairs(DB.recipes) do
      for prof, list in pairs(byProf) do
        for _, rec in ipairs(list) do
          if rec:lower():find(q, 1, true) then
            local key = rec .. " (" .. prof .. ")"
            hits[key] = hits[key] or {}
            table.insert(hits[key], n)
          end
        end
      end
    end
    local keys = {}
    for k in pairs(hits) do keys[#keys + 1] = k end
    table.sort(keys)
    for idx, k in ipairs(keys) do
      if idx > 200 then break end
      table.sort(hits[k])
      local parts = {}
      for _, n in ipairs(hits[k]) do parts[#parts + 1] = nameStr(n) end
      view[#view + 1] = { name = hits[k][1], text = "|cffffd100" .. k .. "|r: " .. table.concat(parts, ", ") }
    end
  end
  if #view == 0 then
    view[1] = { text = "|cff888888Nichts gefunden. Rezepte erscheinen erst, wenn der Crafter sein Berufefenster geöffnet hat.|r" }
  end
end

local function refreshList()
  if not listFrame or not listFrame:IsShown() then return end
  buildRoster()
  buildView()
  if mode == "who" then listFrame.title:SetText(BRAND .. " - online: " .. #roster)
  else listFrame.title:SetText(BRAND .. " - Berufe & Rezepte") end
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
    listFrame.search:SetShown(m == "profs")
    listFrame.searchLabel:SetShown(m == "profs")
    listFrame.tabWho.text:SetTextColor(m == "who" and 1 or 0.6, m == "who" and 0.82 or 0.6, m == "who" and 0 or 0.6)
    listFrame.tabProf.text:SetTextColor(m == "profs" and 1 or 0.6, m == "profs" and 0.82 or 0.6, m == "profs" and 0 or 0.6)
    listFrame.tabWho.bg:SetVertexColor(m == "who" and 0.2 or THEME.panel[1], m == "who" and 0.12 or THEME.panel[2], m == "who" and 0.08 or THEME.panel[3], 1)
    listFrame.tabProf.bg:SetVertexColor(m == "profs" and 0.2 or THEME.panel[1], m == "profs" and 0.12 or THEME.panel[2], m == "profs" and 0.08 or THEME.panel[3], 1)
  end
  refreshList()
end

local function makeTab(parent, label, x, m)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(126, 30)
  b:SetPoint("TOPLEFT", x, -50)
  b.bg = themeTexture(b, "BACKGROUND", THEME.panel)
  b.bg:SetAllPoints()
  b.line = themeTexture(b, "ARTWORK", THEME.border)
  b.line:SetPoint("BOTTOMLEFT"); b.line:SetPoint("BOTTOMRIGHT"); b.line:SetHeight(2)
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  b.text:SetAllPoints(); b.text:SetText(label)
  b.text:SetTextColor(THEME.muted[1], THEME.muted[2], THEME.muted[3])
  b:SetScript("OnEnter", function(self) self.bg:SetVertexColor(0.18, 0.12, 0.16, 1) end)
  b:SetScript("OnLeave", function(self) self.bg:SetVertexColor(THEME.panel[1], THEME.panel[2], THEME.panel[3], 1) end)
  b:SetScript("OnClick", function() setMode(m) end)
  return b
end

local function buildList()
  local f = CreateFrame("Frame", "ForeverGuildList", UIParent)
  f:SetSize(570, ROWS * 20 + 138)
  f:SetPoint("CENTER", 300, 0)
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
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
  f.subtitle:SetText("Gildenkarte  •  ForeverGuild")
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
  f.tabProf = makeTab(f, "Berufe", 144, "profs")

  f.searchLabel = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.searchLabel:SetPoint("TOPLEFT", 18, -88)
  f.searchLabel:SetText("Suche (Beruf/Rezept):")
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

  for i = 1, ROWS do
    local r = CreateFrame("Button", nil, f)
    r:SetSize(540, 20)
    r:SetPoint("TOPLEFT", 16, -112 - (i - 1) * 20)
    r.bg = themeTexture(r, "BACKGROUND", THEME.panel)
    r.bg:SetAllPoints()
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.text:SetPoint("LEFT", 8, 0); r.text:SetWidth(524); r.text:SetJustifyH("LEFT")
    r.text:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3])
    r:SetScript("OnEnter", function(self) self.bg:SetVertexColor(0.18, 0.12, 0.16, 1) end)
    r:SetScript("OnLeave", function(self) self.bg:SetVertexColor(THEME.panel[1], THEME.panel[2], THEME.panel[3], 1) end)
    if r.text.SetWordWrap then r.text:SetWordWrap(false) end
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:SetScript("OnClick", function(self, btn)
      if not self.data or not self.data.name then return end
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
      if self.data.name then
        local p = profText(self.data.name)
        GameTooltip:AddLine(p or "Berufe unbekannt (kein Addon?)", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Links: Flüstern   Rechts: Einladen", 0.5, 0.5, 0.5)
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
  if not (GetNumTradeSkills and GetTradeSkillLine) then return end
  local prof = GetTradeSkillLine()
  if not prof or prof == "UNKNOWN" then return end
  local names = {}
  for i = 1, GetNumTradeSkills() do
    local n, t = GetTradeSkillInfo(i)
    if n and t ~= "header" and t ~= "subheader" then names[#names + 1] = (n:gsub(";", "")) end
  end
  if #names > 0 then storeAndSend(prof, names) end
end

local function scanCraft()
  if not (GetNumCrafts and GetCraftDisplaySkillLine) then return end
  local prof = GetCraftDisplaySkillLine()
  if not prof then return end
  local names = {}
  for i = 1, GetNumCrafts() do
    local n, _, t = GetCraftInfo(i)
    if n and t ~= "header" then names[#names + 1] = (n:gsub(";", "")) end
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
  if C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
    local d = C_UnitAuras.GetBuffDataByIndex("player", i)
    if d then return d.name, d.expirationTime end
    return
  end
  local a, _, c, _, _, f, g = UnitBuff("player", i)
  if not a then return end
  if type(c) == "string" then return a, g end
  return a, f
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
      if tracked[name] and exp and exp > 0 then
        local left = math.max(0, exp - now)
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
  autoLog = false, labelSize = 0, miniLabel = true, hideGroup = true }

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
local VERSION = "0.5"
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

function handlers.PLAYER_TARGET_CHANGED()
  if not DB or not DB.pvp then return end
  if not UnitExists("target") or UnitIsUnit("target", "player") then return end
  if UnitIsPVP("target") and UnitCanAttack("player", "target") then
    local key = UnitGUID("target") or UnitName("target")
    local now = GetTime()
    if now - (pvpSeen[key] or 0) >= 10 then
      pvpSeen[key] = now
      pvpFrame.text:SetText("|cffff3333PVP!|r " .. (UnitName("target") or "?"))
      pvpFrame.t = 0
      pvpFrame:Show()
      if DB.pvpSound then pcall(PlaySound, 8959) end
    end
  end
end

------------------------------------------------------------------ Tooltip-Erweiterung
local function tipUnit(tt)
  if not tt.GetUnit then return end
  local _, unit = tt:GetUnit()
  if not unit or not UnitIsPlayer(unit) then return end
  local name = UnitName(unit)
  local gname, rank = GetGuildInfo(unit)
  if gname and gname == GetGuildInfo("player") and rank then
    tt:AddLine("Gildenrang: " .. rank, 0.4, 0.8, 1)
  end
  local status = UnitIsAFK(unit) and "AFK" or (UnitIsDND(unit) and "DND" or "Online")
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
for _, e in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "CRAFT_SHOW", "CRAFT_UPDATE" }) do
  pcall(f.RegisterEvent, f, e)
end
f:SetScript("OnEvent", function(_, event, ...) if handlers[event] then handlers[event](...) end end)
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "CHAT_MSG_ADDON", "PLAYER_LEVEL_UP", "PLAYER_DEAD",
  "GUILD_ROSTER_UPDATE", "CHAT_MSG_LOOT", "SKILL_LINES_CHANGED", "CHAT_MSG_GUILD", "PLAYER_TARGET_CHANGED", "UNIT_HEALTH", "GROUP_ROSTER_UPDATE" }) do f:RegisterEvent(e) end
-- Kampflog nur auf Classic-Clients registrieren (in Retail/Midnight ist das fuer Addons verboten)
if WOW_PROJECT_ID and WOW_PROJECT_MAINLINE and WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE then
  pcall(f.RegisterEvent, f, "COMBAT_LOG_EVENT_UNFILTERED")
end

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
    profMile = true, rareLoot = true, autoLog = false, labelSize = 0, miniLabel = true, hideGroup = true }
  for k, v in pairs(D) do if DB.set[k] == nil then DB.set[k] = v end end
  DB.profs = DB.profs or {}
  DB.recipes = DB.recipes or {}
  for k, v in pairs(DB.profs) do profs[k] = v end
  DB.creators = DB.creators or {}
  if DB.pvp == nil then DB.pvp = true end
  if DB.pvpSound == nil then DB.pvpSound = false end
  if DB.deathChat == nil then DB.deathChat = true end
  DB.mmAngle = DB.mmAngle or 200
end

function handlers.PLAYER_LOGIN()
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
  elseif RegisterAddonMessagePrefix then RegisterAddonMessagePrefix(PREFIX) end
  playerGUID = UnitGUID("player")
  rebuildGroup()
  DB.logApplied = DB.set.autoLog and true or false
  if DB.set.autoLog and LoggingChat then pcall(LoggingChat, true) end
  buildList(); buildBuffFrame(); hookMap(); buildDeathLog(); buildMinimap(); buildPvPWarn(); hookTooltip()
  local acc, mapAcc, miniAcc, rosAcc = 0, 0, 0, 50
  f:SetScript("OnUpdate", function(_, el)
    acc = acc + el; mapAcc = mapAcc + el; miniAcc = miniAcc + el; rosAcc = rosAcc + el
    if acc >= DB.interval then acc = 0; broadcastPos() end
    if mapAcc >= 1 then mapAcc = 0; hookMap(); updatePins() end
    if miniAcc >= 0.2 then miniAcc = 0; updateMini() end
    if rosAcc >= 60 then rosAcc = 0; requestRoster() end
  end)
  C_Timer.After(6, function() send("H"); broadcastPos(); broadcastProfs() end)
  out("Addon geladen. /ku oder /fg öffnet die Liste, /ku hilfe zeigt alle Befehle.")
end

local function checkProfMilestones()
  if not (GetNumSkillLines and DB) then return end
  DB.profRank = DB.profRank or {}
  for i = 1, GetNumSkillLines() do
    local name, isHeader, _, rank = GetSkillLineInfo(i)
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

local ENV_NAMES = { Falling = "Sturz", Drowning = "Ertrinken", Fatigue = "Erschöpfung", Fire = "Feuer",
  Lava = "Lava", Slime = "Schleim" }
function handlers.COMBAT_LOG_EVENT_UNFILTERED()
  if not CombatLogGetCurrentEventInfo then return end
  local _, sub, _, _, srcName, _, _, destGUID, _, _, _, p12 = CombatLogGetCurrentEventInfo()
  if destGUID ~= playerGUID then return end
  if sub == "ENVIRONMENTAL_DAMAGE" then
    lastHit.src = ENV_NAMES[p12] or tostring(p12); lastHit.t = GetTime()
  elseif srcName and sub:find("_DAMAGE$") then
    lastHit.src = srcName; lastHit.t = GetTime()
  end
end

function handlers.SKILL_LINES_CHANGED()
  checkProfMilestones()
  if DB and not FG_PROF_T then
    FG_PROF_T = true
    C_Timer.After(5, function() FG_PROF_T = nil; broadcastProfs() end)
  end
end

function handlers.GROUP_ROSTER_UPDATE() rebuildGroup() end

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
  local mx = UnitHealthMax("player")
  if mx and mx > 0 and UnitHealth("player") / mx < 0.6 and GetTime() - lastHpSend > 3 then
    lastHpSend = GetTime()
    broadcastPos()
  end
end
function handlers.TRADE_SKILL_SHOW() scanLater(scanTrade) end
function handlers.TRADE_SKILL_UPDATE() scanLater(scanTrade) end
function handlers.CRAFT_SHOW() scanLater(scanCraft) end
function handlers.CRAFT_UPDATE() scanLater(scanCraft) end

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
  local killer = (lastHit.src and GetTime() - (lastHit.t or 0) < 15) and lastHit.src or nil
  recordDeath(myName, zone, lvl, true)
  send("D:" .. lvl .. ":" .. zone)
  if DB.set.deathChat and IsInGuild() then
    local msg = string.format("[KU] %s ist gestorben in %s (Lvl %d %s)", myName, zone, lvl, className)
    if killer then msg = msg .. " durch " .. killer end
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
  elseif cmd == "sync" then
    syncMyRecipes()
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
      if LoggingChat and not LoggingChat() then
        out("|cffff4444Achtung:|r Der Chatlog ist AUS. Ohne ihn sieht die Bridge nichts. Mit /chatlog einschalten.")
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
    out("/fg berufe (Reiter) | /fg sync (eigene Rezepte senden) | /fg opt (Einstellungen)")
    out("/ku test (Beispielmeldungen für die Discord-Bridge) | /fg tod | /fg todchat | /fg pvp | /fg pvpton | /fg creator <Name> <Handle>")
  end
end
SLASH_FOREVERGUILD1 = "/fg"
SLASH_FOREVERGUILD2 = "/foreverguild"
SLASH_FOREVERGUILD3 = "/ku"
SLASH_FOREVERGUILD4 = "/kritisch"
SlashCmdList["FOREVERGUILD"] = slash

