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

local TABS = { "c1lown", "GUIs", "Game", "Links" }
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
    local rightPad = 12 + 80 * #buttons
    local t = label(row, titleText, 13, Enum.Font.GothamMedium, TEXTC)
    t.Position, t.Size = UDim2.fromOffset(14, 7), UDim2.new(1, -rightPad - 14, 0, 18)
    t.TextTruncate = Enum.TextTruncate.AtEnd
    local s = label(row, subText or "", 11, Enum.Font.Gotham, SUBC)
    s.Position, s.Size = UDim2.fromOffset(14, 27), UDim2.new(1, -rightPad - 14, 0, 16)
    s.TextTruncate = Enum.TextTruncate.AtEnd
    for idx, bd in ipairs(buttons) do
        local b = mk("TextButton", {
            AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8 - 80 * (idx - 1), 0.5, 0),
            Size = UDim2.fromOffset(72, 30), BackgroundColor3 = BTNC, BackgroundTransparency = 0.2,
            Text = bd.text, TextColor3 = TEXTC, Font = Enum.Font.GothamMedium, TextSize = 12, AutoButtonColor = true,
        }, row)
        corner(b, 10)
        wireButton(b, bd.text, bd.confirm, bd.action)
    end
    return row
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
    local counts, names = {}, {}
    for _, f in ipairs(found) do
        if not counts[f.name] then counts[f.name] = 0 names[#names + 1] = f.name end
        counts[f.name] += 1
    end
    table.sort(names)
    if total == 0 then
        infoLabel("No executor connections found.", 20)
    else
        for _, n in ipairs(names) do
            makeRow(n, counts[n] .. " executor connection(s)", {})
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
-- Tab plumbing
-- ====================================================================
function rebuild(keep)
    local pos = scroll.CanvasPosition
    clearList()
    order = 0
    if currentTab == "c1lown" then buildC1lown()
    elseif currentTab == "GUIs" then buildGuis()
    elseif currentTab == "Game" then buildGame()
    elseif currentTab == "Links" then buildLinks() end
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
