-- c1lown unloader
-- A menu that lists what is running on your client and lets you shut it down:
--   c1lown   : every c1lown script (nametag, reanimation, ...) with its own unload button
--   GUIs     : ScreenGuis other scripts created (gethui / CoreGui / PlayerGui), connections cut + destroyed
--   Game     : running LocalScripts, toggle Disabled or destroy them
--   Links    : connections made by executor scripts on common signals (Heartbeat, input, players)
-- Risky actions need a second tap to confirm. This only affects your own client.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

local lp = Players.LocalPlayer

-- shared registry (same one the other c1lown scripts use)
local SELF_NAME = "Unloader"
local env = (getgenv and getgenv()) or _G
env.c1lownScripts = env.c1lownScripts or {}
do
    local old = env.c1lownScripts[SELF_NAME]
    if old then pcall(old.unload) end -- re-running replaces the old copy cleanly
end

local GUI_NAME = "c1lownUnloaderGui"
pcall(function()
    local old = (gethui and gethui() or CoreGui):FindFirstChild(GUI_NAME)
    if old then old:Destroy() end
end)

local gui = Instance.new("ScreenGui")
gui.Name = GUI_NAME
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
local okp = pcall(function() gui.Parent = (gethui and gethui()) or CoreGui end)
if not okp or not gui.Parent then gui.Parent = lp:WaitForChild("PlayerGui") end

local connections = {}
local ownFns = setmetatable({}, { __mode = "k" }) -- our own callbacks, never touched by the Links tab
local function connect(sig, fn)
    ownFns[fn] = true
    local c = sig:Connect(fn)
    table.insert(connections, c)
    return c
end

-- ====================================================================
-- Theme / helpers
-- ====================================================================
local BGC = Color3.fromRGB(19, 30, 23)
local ROWC = Color3.fromRGB(44, 62, 49)
local BTNC = Color3.fromRGB(62, 82, 67)
local PANELC = Color3.fromRGB(26, 40, 31)
local STROKEC = Color3.fromRGB(64, 94, 74)
local GREEN = Color3.fromRGB(40, 205, 92)
local RED = Color3.fromRGB(214, 74, 74)
local DARKTXT = Color3.fromRGB(10, 30, 16)
local TEXTC = Color3.fromRGB(245, 248, 246)
local SUBC = Color3.fromRGB(165, 182, 171)
local WHITE = Color3.new(1, 1, 1)

local function mk(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props) do o[k] = v end
    o.Parent = parent
    return o
end
local function corner(o, r) return mk("UICorner", { CornerRadius = UDim.new(0, r or 8) }, o) end
local function ustroke(o, color, th, tr)
    return mk("UIStroke", {
        Color = color or STROKEC, Thickness = th or 1, Transparency = tr or 0.3,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, o)
end
local function label(parent, text, size, font, color, xalign)
    return mk("TextLabel", {
        BackgroundTransparency = 1, Text = text, TextSize = size or 13, Font = font or Enum.Font.Gotham,
        TextColor3 = color or TEXTC, TextXAlignment = xalign or Enum.TextXAlignment.Left,
    }, parent)
end
local function isPress(i)
    return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch
end
local function isMove(i)
    return i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch
end

local statusLbl
local function status(msg)
    if statusLbl then statusLbl.Text = tostring(msg) end
end

-- ====================================================================
-- Window
-- ====================================================================
local MENU_KEY = "RightShift"

local root = mk("Frame", {
    Name = "Root", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(360, 470),
    Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = BGC, BackgroundTransparency = 0.06, BorderSizePixel = 0,
}, gui)
corner(root, 18)
ustroke(root, STROKEC, 1.5, 0.2)

local header = mk("Frame", { Size = UDim2.new(1, 0, 0, 50), BackgroundTransparency = 1 }, root)
local title = label(header, "Script Unloader", 15, Enum.Font.GothamBold, TEXTC)
title.Position, title.Size = UDim2.fromOffset(16, 8), UDim2.fromOffset(200, 20)
local sub = label(header, MENU_KEY .. " to hide", 11, Enum.Font.Gotham, SUBC)
sub.Position, sub.Size = UDim2.fromOffset(16, 28), UDim2.fromOffset(200, 16)
local closeBtn = mk("TextButton", {
    AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(30, 30),
    BackgroundColor3 = BTNC, BackgroundTransparency = 0.2, Text = "X", TextColor3 = TEXTC,
    Font = Enum.Font.GothamBold, TextSize = 12, AutoButtonColor = true,
}, header)
corner(closeBtn, 15)
closeBtn.MouseButton1Click:Connect(function() gui.Enabled = false end)

do
    local dragging, dragStart, startPos
    header.InputBegan:Connect(function(i)
        if isPress(i) then dragging, dragStart, startPos = true, i.Position, root.Position end
    end)
    connect(UIS.InputChanged, function(i)
        if dragging and isMove(i) then
            local d = i.Position - dragStart
            root.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    connect(UIS.InputEnded, function(i)
        if isPress(i) then dragging = false end
    end)
end

local statusBar = mk("Frame", {
    AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 10, 1, -8), Size = UDim2.new(1, -20, 0, 26),
    BackgroundColor3 = PANELC, BackgroundTransparency = 0.25,
}, root)
corner(statusBar, 10)
statusLbl = label(statusBar, "Ready", 11, Enum.Font.Gotham, SUBC)
statusLbl.Position, statusLbl.Size = UDim2.fromOffset(10, 0), UDim2.new(1, -20, 1, 0)
statusLbl.TextTruncate = Enum.TextTruncate.AtEnd

local TABS = { "c1lown", "GUIs", "Game", "Links", "View" }
local currentTab = "c1lown"
local tabButtons = {}
local tabBar = mk("Frame", { Position = UDim2.fromOffset(10, 50), Size = UDim2.new(1, -20, 0, 32), BackgroundTransparency = 1 }, root)
for idx, name in ipairs(TABS) do
    local b = mk("TextButton", {
        Position = UDim2.new((idx - 1) / #TABS, 1, 0, 0), Size = UDim2.new(1 / #TABS, -2, 1, 0),
        BackgroundColor3 = BTNC, BackgroundTransparency = 1, Text = name, TextColor3 = SUBC,
        Font = Enum.Font.GothamMedium, TextSize = 12, AutoButtonColor = false,
    }, tabBar)
    corner(b, 12)
    tabButtons[name] = b
end

local scroll = mk("ScrollingFrame", {
    Position = UDim2.fromOffset(12, 90), Size = UDim2.new(1, -24, 1, -90 - 42), BackgroundTransparency = 1,
    BorderSizePixel = 0, ScrollBarThickness = 3, ScrollBarImageColor3 = GREEN,
    AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(),
}, root)
mk("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
mk("UIPadding", { PaddingRight = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }, scroll)

local function clearList()
    for _, c in ipairs(scroll:GetChildren()) do
        if not (c:IsA("UIListLayout") or c:IsA("UIPadding")) then c:Destroy() end
    end
end

local order = 0
local function nextOrder() order += 1 return order end

local function infoLabel(text, height)
    local l = label(scroll, text, 12, Enum.Font.Gotham, SUBC)
    l.Size = UDim2.new(1, 0, 0, height or 34)
    l.TextWrapped = true
    l.TextYAlignment = Enum.TextYAlignment.Top
    l.LayoutOrder = nextOrder()
    return l
end

-- button that needs a second tap when `confirm` is true
local function wireButton(btn, text, confirm, action)
    local armed = false
    btn.MouseButton1Click:Connect(function()
        if confirm and not armed then
            armed = true
            btn.Text = "Sure?"
            btn.BackgroundColor3 = RED
            btn.TextColor3 = WHITE
            task.delay(3, function()
                if armed and btn.Parent then
                    armed = false
                    btn.Text = text
                    btn.BackgroundColor3 = BTNC
                    btn.TextColor3 = TEXTC
                end
            end)
        else
            armed = false
            action()
        end
    end)
end

local function bigButton(text, confirm, action, accent)
    local b = mk("TextButton", {
        Size = UDim2.new(1, 0, 0, 38), BackgroundColor3 = accent and GREEN or BTNC, BackgroundTransparency = accent and 0.1 or 0.2,
        Text = text, TextColor3 = accent and DARKTXT or TEXTC, Font = Enum.Font.GothamMedium, TextSize = 13,
        AutoButtonColor = true, LayoutOrder = nextOrder(),
    }, scroll)
    corner(b, 12)
    wireButton(b, text, confirm, action)
    return b
end

-- row with a title, a small subtitle and up to two buttons on the right
local function makeRow(titleText, subText, buttons)
    local row = mk("Frame", {
        Size = UDim2.new(1, 0, 0, 52), BackgroundColor3 = ROWC, BackgroundTransparency = 0.35,
        BorderSizePixel = 0, LayoutOrder = nextOrder(),
    }, scroll)
    corner(row, 12)
    local bw = (#buttons >= 3) and 58 or 72
    local step = bw + 8
    local rightPad = 12 + step * #buttons
    local t = label(row, titleText, 13, Enum.Font.GothamMedium, TEXTC)
    t.Position, t.Size = UDim2.fromOffset(14, 7), UDim2.new(1, -rightPad - 14, 0, 18)
    t.TextTruncate = Enum.TextTruncate.AtEnd
    local s = label(row, subText or "", 11, Enum.Font.Gotham, SUBC)
    s.Position, s.Size = UDim2.fromOffset(14, 27), UDim2.new(1, -rightPad - 14, 0, 16)
    s.TextTruncate = Enum.TextTruncate.AtEnd
    for idx, bd in ipairs(buttons) do
        local b = mk("TextButton", {
            AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8 - step * (idx - 1), 0.5, 0),
            Size = UDim2.fromOffset(bw, 30), BackgroundColor3 = BTNC, BackgroundTransparency = 0.2,
            Text = bd.text, TextColor3 = TEXTC, Font = Enum.Font.GothamMedium, TextSize = 12, AutoButtonColor = true,
        }, row)
        corner(b, 10)
        wireButton(b, bd.text, bd.confirm, bd.action)
    end
    return row
end

-- ====================================================================
-- Raw viewer: shows the raw contents of whatever you pick
--   scripts     -> decompiled source (executor decompile) / bytecode info
--   GUIs        -> every instance with its main properties
--   registry    -> the entry, its unload function, and its GUI
--   connections -> function info, constants, upvalues
-- ====================================================================
local GUI_OF = { Nametag = "c1lownNametagGui", Reanimation = "c1lownReanimGui", Unloader = GUI_NAME }

local function pathOf(inst)
    local ok, p = pcall(function() return inst:GetFullName() end)
    return ok and p or tostring(inst)
end
local function short(v, n)
    local t = tostring(v):gsub("[%c]", " ")
    n = n or 80
    if #t > n then t = t:sub(1, n - 3) .. "..." end
    return t
end

local PROPS = { "Text", "Image", "Visible", "Size", "Position", "AnchorPoint", "BackgroundColor3",
    "BackgroundTransparency", "TextColor3", "Enabled", "ZIndex" }

local function dumpGui(g)
    local lines, count = {}, 0
    local function visit(inst, depth)
        count += 1
        if count > 2500 then return end
        local parts = {}
        for _, pn in ipairs(PROPS) do
            local ok, v = pcall(function() return inst[pn] end)
            if ok and v ~= nil then parts[#parts + 1] = pn .. "=" .. short(v) end
        end
        lines[#lines + 1] = string.rep("  ", depth) .. inst.ClassName .. ' "' .. inst.Name .. '"'
            .. (#parts > 0 and ("  { " .. table.concat(parts, ", ") .. " }") or "")
        for _, c in ipairs(inst:GetChildren()) do visit(c, depth + 1) end
    end
    visit(g, 0)
    if count > 2500 then lines[#lines + 1] = "... truncated at 2500 instances" end
    return table.concat(lines, "\n")
end

local function describeFunction(fn)
    if type(fn) ~= "function" then return "(not a function)" end
    local L = { "Function: " .. tostring(fn) }
    if iscclosure then
        local ok, r = pcall(iscclosure, fn)
        if ok then L[#L + 1] = "C closure: " .. tostring(r) end
    end
    if islclosure then
        local ok, r = pcall(islclosure, fn)
        if ok then L[#L + 1] = "Lua closure: " .. tostring(r) end
    end
    if debug and debug.info then
        local ok, src, line, name = pcall(debug.info, fn, "sln")
        if ok then
            L[#L + 1] = ("debug.info: source=%s  line=%s  name=%s"):format(tostring(src), tostring(line), tostring(name))
        end
        local ok2, np, va = pcall(debug.info, fn, "a")
        if ok2 then L[#L + 1] = "params: " .. tostring(np) .. (va and " (vararg)" or "") end
    end
    local okE, fenv = pcall(getfenv, fn)
    if okE and type(fenv) == "table" then
        local okS, sc = pcall(function() return fenv.script end)
        if okS then
            L[#L + 1] = "env.script: " .. ((typeof(sc) == "Instance") and pathOf(sc) or tostring(sc))
        end
    end
    if debug and debug.getinfo then
        local ok, t = pcall(debug.getinfo, fn)
        if ok and type(t) == "table" then
            local keys = {}
            for k, v in pairs(t) do
                if type(v) ~= "function" and type(v) ~= "table" then keys[#keys + 1] = tostring(k) end
            end
            table.sort(keys)
            L[#L + 1] = "debug.getinfo:"
            for _, k in ipairs(keys) do L[#L + 1] = "  " .. k .. " = " .. short(t[k], 120) end
        end
    end
    local function listing(titleText, fnName)
        local f = debug and debug[fnName]
        if not f then return end
        local ok, t = pcall(f, fn)
        if ok and type(t) == "table" then
            L[#L + 1] = ""
            L[#L + 1] = titleText
            local n = 0
            for i, v in pairs(t) do
                n += 1
                if n > 150 then L[#L + 1] = "  ... more omitted" break end
                L[#L + 1] = ("  [%s] %s: %s"):format(tostring(i), typeof(v), short(v, 100))
            end
            if n == 0 then L[#L + 1] = "  (none)" end
        end
    end
    listing("Constants:", "getconstants")
    listing("Upvalues:", "getupvalues")
    if debug and debug.getprotos then
        local ok, t = pcall(debug.getprotos, fn)
        if ok and type(t) == "table" then L[#L + 1] = ""  L[#L + 1] = "Inner functions: " .. #t end
    end
    return table.concat(L, "\n")
end

local function briefFn(fn)
    if debug and debug.info then
        local ok, src, line = pcall(debug.info, fn, "sl")
        if ok and src then return short(tostring(src) .. ":" .. tostring(line), 60) end
    end
    return short(fn, 60)
end

local function describeConnection(sigName, conn)
    local L = { "Signal: " .. sigName }
    pcall(function() L[#L + 1] = "Enabled: " .. tostring(conn.Enabled) end)
    pcall(function() L[#L + 1] = "ForeignState: " .. tostring(conn.ForeignState) end)
    L[#L + 1] = "Made by: executor script (not a game script)"
    L[#L + 1] = ""
    L[#L + 1] = describeFunction(conn.Function)
    return table.concat(L, "\n")
end

local function describeScript(sc)
    local L = { "-- " .. sc.ClassName .. ' "' .. sc.Name .. '"', "-- Path: " .. pathOf(sc) }
    pcall(function() L[#L + 1] = "-- Disabled: " .. tostring(sc.Disabled) end)
    if getscriptbytecode then
        local ok, bc = pcall(getscriptbytecode, sc)
        if ok and type(bc) == "string" then L[#L + 1] = "-- Bytecode: " .. #bc .. " bytes" end
    end
    L[#L + 1] = ""
    local src
    if decompile then
        local ok, res = pcall(decompile, sc)
        if ok and type(res) == "string" and res ~= "" then
            src = res
        else
            L[#L + 1] = "-- decompile failed: " .. tostring(res)
        end
    end
    if not src then
        local ok, res = pcall(function() return sc.Source end)
        if ok and type(res) == "string" and res ~= "" then src = res end
    end
    L[#L + 1] = src or "-- no source available (this executor has no decompile, and Source is empty on the client)"
    return table.concat(L, "\n")
end

local function describeRegistry(name, info)
    local L = { "Registry entry: " .. name, "" }
    local keys = {}
    for k in pairs(info) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local v = info[k]
        if type(v) == "function" then
            L[#L + 1] = k .. " ->"
            L[#L + 1] = describeFunction(v)
        else
            L[#L + 1] = k .. " = " .. short(v, 120)
        end
        L[#L + 1] = ""
    end
    local guiName = GUI_OF[name]
    if guiName then
        local g
        for _, c in ipairs({ gethui and gethui() or nil, CoreGui, lp:FindFirstChild("PlayerGui") }) do
            local ok, f = pcall(function() return c and c:FindFirstChild(guiName) end)
            if ok and f then g = f break end
        end
        if g then
            L[#L + 1] = "GUI tree (" .. guiName .. "):"
            L[#L + 1] = dumpGui(g)
        end
    end
    return table.concat(L, "\n")
end

-- viewer window ------------------------------------------------------------
local viewer = mk("Frame", {
    Position = UDim2.fromOffset(12, 54), Size = UDim2.new(1, -24, 1, -54 - 42), BackgroundTransparency = 1, Visible = false,
}, root)
local vBack = mk("TextButton", {
    Size = UDim2.fromOffset(64, 30), BackgroundColor3 = BTNC, BackgroundTransparency = 0.2, Text = "‹ Back",
    TextColor3 = TEXTC, Font = Enum.Font.GothamMedium, TextSize = 12, AutoButtonColor = true,
}, viewer)
corner(vBack, 10)
local vTitle = label(viewer, "", 13, Enum.Font.GothamBold, TEXTC)
vTitle.Position, vTitle.Size = UDim2.fromOffset(72, 0), UDim2.new(1, -72 - 136, 0, 30)
vTitle.TextTruncate = Enum.TextTruncate.AtEnd
local vCopy = mk("TextButton", {
    AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -66, 0, 0), Size = UDim2.fromOffset(60, 30),
    BackgroundColor3 = BTNC, BackgroundTransparency = 0.2, Text = "Copy", TextColor3 = TEXTC,
    Font = Enum.Font.GothamMedium, TextSize = 12, AutoButtonColor = true,
}, viewer)
corner(vCopy, 10)
local vSave = mk("TextButton", {
    AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(60, 30),
    BackgroundColor3 = BTNC, BackgroundTransparency = 0.2, Text = "Save", TextColor3 = TEXTC,
    Font = Enum.Font.GothamMedium, TextSize = 12, AutoButtonColor = true,
}, viewer)
corner(vSave, 10)
local vScroll = mk("ScrollingFrame", {
    Position = UDim2.fromOffset(0, 38), Size = UDim2.new(1, 0, 1, -38), BackgroundColor3 = PANELC, BackgroundTransparency = 0.25,
    BorderSizePixel = 0, ScrollBarThickness = 3, ScrollBarImageColor3 = GREEN,
    AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(),
}, viewer)
corner(vScroll, 12)
mk("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, vScroll)
mk("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) }, vScroll)

local rawText, rawTitle = "", "raw"
local MAX_LINES = 3000
local function setViewerText(text)
    rawText = text
    for _, c in ipairs(vScroll:GetChildren()) do
        if not (c:IsA("UIListLayout") or c:IsA("UIPadding")) then c:Destroy() end
    end
    local lines = {}
    for line in (text:gsub("\r", "") .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
    local shown = math.min(#lines, MAX_LINES)
    local i, chunk = 1, 0
    while i <= shown do
        local j = math.min(i + 99, shown)
        chunk += 1
        mk("TextBox", {
            LayoutOrder = chunk, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1, Text = table.concat(lines, "\n", i, j), TextColor3 = TEXTC,
            Font = Enum.Font.Code, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, MultiLine = true,
            TextEditable = false, ClearTextOnFocus = false,
        }, vScroll)
        i = j + 1
    end
    if #lines > shown then
        mk("TextLabel", {
            LayoutOrder = chunk + 1, Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1,
            Text = ("... %d more lines hidden, Copy or Save has the full text"):format(#lines - shown),
            TextColor3 = SUBC, Font = Enum.Font.Gotham, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left,
        }, vScroll)
    end
    vScroll.CanvasPosition = Vector2.new(0, 0)
end

local viewToken = 0
local function closeViewer()
    viewToken += 1
    viewer.Visible = false
    scroll.Visible = true
    tabBar.Visible = true
end
vBack.MouseButton1Click:Connect(closeViewer)
vCopy.MouseButton1Click:Connect(function()
    if setclipboard then
        setclipboard(rawText)
        status("Copied " .. #rawText .. " characters")
    else
        status("No clipboard here, use Save")
    end
end)
vSave.MouseButton1Click:Connect(function()
    local fname = "c1lown_raw_" .. rawTitle:gsub("[^%w_%-]", "_") .. ".txt"
    if writefile and pcall(writefile, fname, rawText) then
        status("Saved " .. fname)
    else
        status("Couldn't save (executor has no writefile)")
    end
end)

local function showRaw(titleText, producer)
    viewToken += 1
    local token = viewToken
    rawTitle = titleText
    scroll.Visible = false
    tabBar.Visible = false
    viewer.Visible = true
    vTitle.Text = titleText
    setViewerText("Loading...")
    task.spawn(function()
        local ok, res = pcall(producer)
        if token ~= viewToken or not viewer.Visible then return end
        setViewerText(ok and tostring(res) or ("Error: " .. tostring(res)))
    end)
end

-- ====================================================================
-- c1lown tab: the shared registry
-- ====================================================================
local rebuild

local function buildC1lown()
    infoLabel("Scripts from this suite that are currently loaded. Each one cleans up after itself when unloaded.", 34)
    local names = {}
    for name in pairs(env.c1lownScripts) do names[#names + 1] = name end
    table.sort(names)
    if #names == 0 then
        infoLabel("Nothing registered.", 20)
    end
    for _, name in ipairs(names) do
        local info = env.c1lownScripts[name]
        local isSelf = (name == SELF_NAME)
        makeRow(name, isSelf and "this menu" or "loaded", {
            { text = "Unload", confirm = false, action = function()
                status("Unloading " .. name)
                pcall(info.unload)
                if not isSelf then rebuild(true) end
            end },
            { text = "View", action = function()
                showRaw(name, function() return describeRegistry(name, info) end)
            end },
        })
    end
    if #names > 1 then
        bigButton("Unload all others", true, function()
            for _, name in ipairs(names) do
                if name ~= SELF_NAME and env.c1lownScripts[name] then pcall(env.c1lownScripts[name].unload) end
            end
            status("Unloaded all other c1lown scripts")
            rebuild(true)
        end)
    end
    bigButton("Refresh", false, function() rebuild(true) end)
end

-- ====================================================================
-- GUIs tab
-- ====================================================================
local PROTECTED = {
    RobloxGui = true, ThemeProvider = true, TopBarApp = true, PlayerList = true, Chat = true, BubbleChat = true,
    DevConsoleMaster = true, PurchasePromptApp = true, RobloxPromptGui = true, RobloxNetworkPauseNotification = true,
    RobloxLoadingGui = true, ScreenshotHud = true, VoiceChat = true, TouchGui = true, ControlGui = true,
    InGameMenu = true, ExperienceChat = true, EmotesMenu = true, BackpackGui = true, Freecam = true,
}
local KNOWN = { c1lownNametagGui = "Nametag", c1lownReanimGui = "Reanimation" }
local GUI_SIGNALS = {
    "MouseButton1Click", "MouseButton1Down", "MouseButton1Up", "MouseButton2Click", "Activated", "InputBegan",
    "InputEnded", "InputChanged", "MouseEnter", "MouseLeave", "MouseMoved", "FocusLost", "Focused",
}

local function cutGuiConnections(g)
    if not getconnections then return 0 end
    local n = 0
    for _, d in ipairs(g:GetDescendants()) do
        for _, sn in ipairs(GUI_SIGNALS) do
            local okSig, sig = pcall(function() return d[sn] end)
            if okSig and typeof(sig) == "RBXScriptSignal" then
                local okc, list = pcall(getconnections, sig)
                if okc and type(list) == "table" then
                    for _, c in ipairs(list) do
                        if pcall(function() c:Disconnect() end) then n += 1 end
                    end
                end
            end
        end
    end
    return n
end

local function unloadGui(g, reg)
    local key = KNOWN[g.Name]
    if key and env.c1lownScripts[key] then
        pcall(env.c1lownScripts[key].unload)
        status("Unloaded " .. key)
        return
    end
    local n = cutGuiConnections(g)
    pcall(function() g:Destroy() end)
    status(("Removed %s (%d connections cut)"):format(g.Name, n))
end

local function guiContainers()
    local list, seen = {}, {}
    local function add(c, tag)
        if c and not seen[c] then
            seen[c] = true
            list[#list + 1] = { c, tag }
        end
    end
    if gethui then pcall(function() add(gethui(), "hidden ui") end) end
    pcall(function() add(CoreGui, "CoreGui") end)
    local pg = lp:FindFirstChild("PlayerGui")
    if pg then add(pg, "PlayerGui") end
    return list
end

local function buildGuis()
    infoLabel("ScreenGuis created by scripts. Unload cuts the button/input connections inside the GUI, then destroys it. Roblox's own menus are hidden from this list.", 52)
    local n = 0
    for _, pair in ipairs(guiContainers()) do
        local container, tag = pair[1], pair[2]
        local okc, kids = pcall(function() return container:GetChildren() end)
        if okc then
            for _, g in ipairs(kids) do
                if g:IsA("ScreenGui") and g ~= gui and not PROTECTED[g.Name] then
                    n += 1
                    makeRow(g.Name, tag .. (KNOWN[g.Name] and "  -  c1lown" or ""), {
                        { text = "Unload", confirm = true, action = function()
                            unloadGui(g)
                            rebuild(true)
                        end },
                        { text = "View", action = function()
                            showRaw(g.Name, function()
                                return ("ScreenGui \"%s\"  (%s)\n\n%s"):format(g.Name, tag, dumpGui(g))
                            end)
                        end },
                    })
                end
            end
        end
    end
    if n == 0 then infoLabel("No script GUIs found.", 20) end
    bigButton("Refresh", false, function() rebuild(true) end)
end

-- ====================================================================
-- Game tab: running LocalScripts
-- ====================================================================
local function shortPath(inst)
    local ok, p = pcall(function() return inst:GetFullName() end)
    return ok and p or inst.Name
end

local function listLocalScripts()
    local out, seen = {}, {}
    local function add(s)
        if typeof(s) == "Instance" and s:IsA("LocalScript") and not seen[s] then
            seen[s] = true
            out[#out + 1] = s
        end
    end
    if getrunningscripts then
        local ok, list = pcall(getrunningscripts)
        if ok and type(list) == "table" then
            for _, s in ipairs(list) do add(s) end
        end
    end
    if #out == 0 then
        local roots = { lp.Character, lp:FindFirstChild("PlayerGui"), lp:FindFirstChild("PlayerScripts"),
            game:GetService("ReplicatedFirst") }
        for _, r in ipairs(roots) do
            if r then
                for _, d in ipairs(r:GetDescendants()) do add(d) end
            end
        end
    end
    table.sort(out, function(a, b) return a.Name:lower() < b.Name:lower() end)
    return out
end

local function buildGame()
    infoLabel("LocalScripts running in this game. Disabling or destroying game scripts can break controls, UI or the game itself, so use it carefully. Re-enable restores a disabled script.", 64)
    local list = listLocalScripts()
    if #list == 0 then infoLabel("No LocalScripts found.", 20) end
    for idx, s in ipairs(list) do
        if idx > 80 then
            infoLabel("...and " .. (#list - 80) .. " more (list capped at 80).", 20)
            break
        end
        local disabled = false
        pcall(function() disabled = s.Disabled end)
        makeRow(s.Name .. (disabled and "  (disabled)" or ""), shortPath(s), {
            { text = disabled and "Enable" or "Disable", confirm = not disabled, action = function()
                pcall(function() s.Disabled = not disabled end)
                status((disabled and "Enabled " or "Disabled ") .. s.Name)
                rebuild(true)
            end },
            { text = "Destroy", confirm = true, action = function()
                pcall(function() s:Destroy() end)
                status("Destroyed " .. s.Name)
                rebuild(true)
            end },
            { text = "View", action = function()
                showRaw(s.Name, function() return describeScript(s) end)
            end },
        })
    end
    bigButton("Refresh", false, function() rebuild(true) end)
end

-- ====================================================================
-- Links tab: executor connections on common signals
-- ====================================================================
local function signalList()
    local sigs = {
        { "Heartbeat", RunService.Heartbeat },
        { "RenderStepped", RunService.RenderStepped },
        { "Stepped", RunService.Stepped },
        { "InputBegan", UIS.InputBegan },
        { "InputEnded", UIS.InputEnded },
        { "InputChanged", UIS.InputChanged },
        { "PlayerAdded", Players.PlayerAdded },
        { "PlayerRemoving", Players.PlayerRemoving },
        { "CharacterAdded", lp.CharacterAdded },
    }
    return sigs
end

-- a connection counts as "executor-made" if its function is a Lua closure that
-- does not belong to a script inside the game
local function isForeign(conn)
    local fn = conn.Function
    if type(fn) ~= "function" then return false end
    if ownFns[fn] then return false end
    if iscclosure and iscclosure(fn) then return false end
    local ok, fenv = pcall(getfenv, fn)
    if ok and type(fenv) == "table" then
        local okS, sc = pcall(function() return fenv.script end)
        if okS and typeof(sc) == "Instance" and sc:IsDescendantOf(game) then return false end
    end
    return true
end

local function scanLinks()
    local found, total = {}, 0
    if not getconnections then return found, total, false end
    for _, pair in ipairs(signalList()) do
        local okc, list = pcall(getconnections, pair[2])
        if okc and type(list) == "table" then
            for _, c in ipairs(list) do
                local okf, foreign = pcall(isForeign, c)
                if okf and foreign then
                    found[#found + 1] = { name = pair[1], conn = c }
                    total += 1
                end
            end
        end
    end
    return found, total, true
end

local function buildLinks()
    infoLabel("Connections on common signals that were made by executor scripts (not game scripts and not this menu). Cutting them stops loops and listeners that other scripts left running. Best effort: it can also cut other scripts you still want.", 78)
    if not getconnections then
        infoLabel("Your executor doesn't support getconnections, so this tab can't work here.", 34)
        return
    end
    local found, total = scanLinks()
    if total == 0 then
        infoLabel("No executor connections found.", 20)
    else
        for idx, f in ipairs(found) do
            if idx > 60 then
                infoLabel("...and " .. (#found - 60) .. " more (list capped at 60).", 20)
                break
            end
            local fn = f.conn.Function
            makeRow(f.name .. "  #" .. idx, briefFn(fn), {
                { text = "Cut", confirm = true, action = function()
                    pcall(function() f.conn:Disconnect() end)
                    status("Cut one " .. f.name .. " connection")
                    rebuild(true)
                end },
                { text = "View", action = function()
                    showRaw(f.name .. " connection", function() return describeConnection(f.name, f.conn) end)
                end },
            })
        end
        bigButton(("Disconnect all %d executor connection(s)"):format(total), true, function()
            local cut = 0
            for _, f in ipairs(found) do
                if pcall(function() f.conn:Disconnect() end) then cut += 1 end
            end
            status("Disconnected " .. cut .. " connection(s)")
            rebuild(true)
        end)
    end
    bigButton("Rescan", false, function() rebuild(true) end)
end

-- ====================================================================
-- View tab: everything in one list, each with a View button
-- ====================================================================
local viewFilter = ""

local function buildView()
    infoLabel("Tap View on anything to see its raw contents: script source, GUI trees, c1lown entries, connection details.", 34)
    local box = mk("TextBox", {
        Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = PANELC, BackgroundTransparency = 0.25, Text = viewFilter,
        PlaceholderText = "Filter by name", PlaceholderColor3 = SUBC, TextColor3 = TEXTC, ClearTextOnFocus = false,
        Font = Enum.Font.Gotham, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = nextOrder(),
    }, scroll)
    corner(box, 10)
    ustroke(box, STROKEC, 1, 0.4)
    mk("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, box)

    local rows = {}
    local function addRow(name, subText, producer)
        local row = makeRow(name, subText, {
            { text = "View", action = function() showRaw(name, producer) end },
        })
        rows[#rows + 1] = { row = row, key = (name .. " " .. subText):lower() }
    end
    local function section(text)
        local l = label(scroll, string.upper(text), 11, Enum.Font.GothamBold, SUBC)
        l.Size = UDim2.new(1, 0, 0, 18)
        l.LayoutOrder = nextOrder()
    end

    -- c1lown scripts
    section("c1lown scripts")
    local names = {}
    for name in pairs(env.c1lownScripts) do names[#names + 1] = name end
    table.sort(names)
    if #names == 0 then infoLabel("None registered.", 18) end
    for _, name in ipairs(names) do
        local info = env.c1lownScripts[name]
        addRow(name, name == SELF_NAME and "this menu" or "c1lown script", function()
            return describeRegistry(name, info)
        end)
    end

    -- GUIs
    section("GUIs")
    local guiCount = 0
    for _, pair in ipairs(guiContainers()) do
        local container, tag = pair[1], pair[2]
        local okc, kids = pcall(function() return container:GetChildren() end)
        if okc then
            for _, g in ipairs(kids) do
                if g:IsA("ScreenGui") and g ~= gui and not PROTECTED[g.Name] then
                    guiCount += 1
                    addRow(g.Name, tag, function()
                        return ("ScreenGui \"%s\"  (%s)\n\n%s"):format(g.Name, tag, dumpGui(g))
                    end)
                end
            end
        end
    end
    if guiCount == 0 then infoLabel("No script GUIs found.", 18) end

    -- game scripts
    section("Game scripts")
    local list = listLocalScripts()
    if #list == 0 then infoLabel("No LocalScripts found.", 18) end
    for idx, sc in ipairs(list) do
        if idx > 80 then
            infoLabel("...and " .. (#list - 80) .. " more (list capped at 80).", 18)
            break
        end
        addRow(sc.Name, shortPath(sc), function() return describeScript(sc) end)
    end

    -- executor connections
    section("Executor connections")
    if not getconnections then
        infoLabel("Not available (executor has no getconnections).", 18)
    else
        local found, total = scanLinks()
        if total == 0 then infoLabel("None found.", 18) end
        for idx, f in ipairs(found) do
            if idx > 60 then
                infoLabel("...and " .. (#found - 60) .. " more (list capped at 60).", 18)
                break
            end
            addRow(f.name .. "  #" .. idx, briefFn(f.conn.Function), function()
                return describeConnection(f.name, f.conn)
            end)
        end
    end

    local function applyFilter()
        local q = viewFilter:lower()
        for _, r in ipairs(rows) do
            r.row.Visible = (q == "") or (r.key:find(q, 1, true) ~= nil)
        end
    end
    box:GetPropertyChangedSignal("Text"):Connect(function()
        viewFilter = box.Text
        applyFilter()
    end)
    applyFilter()
    bigButton("Refresh", false, function() rebuild(true) end)
end

-- ====================================================================
-- Tab plumbing
-- ====================================================================
function rebuild(keep)
    local pos = scroll.CanvasPosition
    clearList()
    order = 0
    if currentTab == "c1lown" then buildC1lown()
    elseif currentTab == "GUIs" then buildGuis()
    elseif currentTab == "Game" then buildGame()
    elseif currentTab == "Links" then buildLinks()
    elseif currentTab == "View" then buildView() end
    if keep then
        task.defer(function() scroll.CanvasPosition = pos end)
    end
end

local function selectTab(name)
    currentTab = name
    for n, b in pairs(tabButtons) do
        b.BackgroundTransparency = (n == name) and 0.1 or 1
        b.TextColor3 = (n == name) and TEXTC or SUBC
    end
    rebuild()
end
for name, b in pairs(tabButtons) do
    b.MouseButton1Click:Connect(function() selectTab(name) end)
end

-- ====================================================================
-- Register + unload self
-- ====================================================================
local myEntry
local function unloadSelf()
    for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    if env.c1lownScripts[SELF_NAME] == myEntry then env.c1lownScripts[SELF_NAME] = nil end
    gui:Destroy()
end
myEntry = { unload = unloadSelf }
env.c1lownScripts[SELF_NAME] = myEntry

connect(UIS.InputBegan, function(i, gp)
    if gp or i.UserInputType ~= Enum.UserInputType.Keyboard then return end
    if i.KeyCode.Name == MENU_KEY then gui.Enabled = not gui.Enabled end
end)

selectTab("c1lown")
