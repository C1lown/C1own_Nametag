-- c1lown executor
-- An in-game script editor + runner for your executor.
--   Editor  : multi-tab code editor with line numbers, Execute / Clear / Copy / Paste
--   Scripts : save, load, run and delete scripts in your workspace folder "c1lown_scripts"
--   Output  : console showing your script's prints, warnings, errors, plus compile/runtime errors
-- Needs an executor that provides loadstring. Your tabs auto-save to c1lown_executor.json.

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")
local LogService = game:GetService("LogService")

local lp = Players.LocalPlayer

-- shared registry so the other c1lown scripts (unloader) can see / unload this one
local SELF_NAME = "Executor"
local env = (getgenv and getgenv()) or _G
env.c1lownScripts = env.c1lownScripts or {}
do
    local old = env.c1lownScripts[SELF_NAME]
    if old then pcall(old.unload) end
end

local GUI_NAME = "c1lownExecutorGui"
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
local function connect(sig, fn)
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
local PANELC = Color3.fromRGB(14, 22, 17)
local STROKEC = Color3.fromRGB(64, 94, 74)
local GREEN = Color3.fromRGB(40, 205, 92)
local RED = Color3.fromRGB(235, 96, 96)
local YELLOW = Color3.fromRGB(240, 200, 90)
local BLUE = Color3.fromRGB(120, 170, 255)
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
local function trim(s) return ((s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

local function button(parent, text, props, accent)
    local b = mk("TextButton", {
        BackgroundColor3 = accent and GREEN or BTNC, BackgroundTransparency = accent and 0.05 or 0.2,
        Text = text, TextColor3 = accent and DARKTXT or TEXTC, Font = Enum.Font.GothamMedium, TextSize = 13,
        AutoButtonColor = true,
    }, parent)
    for k, v in pairs(props or {}) do b[k] = v end
    corner(b, 10)
    return b
end

-- tap twice to confirm
local function confirmButton(btn, text, action)
    local armed = false
    btn.MouseButton1Click:Connect(function()
        if not armed then
            armed = true
            btn.Text = "Sure?"
            btn.BackgroundColor3 = RED
            task.delay(3, function()
                if armed and btn.Parent then
                    armed = false
                    btn.Text = text
                    btn.BackgroundColor3 = BTNC
                end
            end)
        else
            armed = false
            action()
        end
    end)
end

local MENU_KEY = "Insert"
local statusLbl
local function status(msg)
    if statusLbl then statusLbl.Text = tostring(msg) end
end

-- ====================================================================
-- Saved state (tabs)
-- ====================================================================
local STATE_FILE = "c1lown_executor.json"
local FOLDER = "c1lown_scripts"

local buffers = { { name = "Script 1", text = "" } }
local active = 1
local captureGame = true

local function loadState()
    if not (isfile and readfile and isfile(STATE_FILE)) then return end
    local ok, data = pcall(function() return HttpService:JSONDecode(readfile(STATE_FILE)) end)
    if not ok or type(data) ~= "table" or type(data.buffers) ~= "table" then return end
    local list = {}
    for _, b in ipairs(data.buffers) do
        if type(b) == "table" and type(b.name) == "string" then
            list[#list + 1] = { name = b.name, text = type(b.text) == "string" and b.text or "" }
        end
    end
    if #list > 0 then
        buffers = list
        active = math.clamp(tonumber(data.active) or 1, 1, #list)
    end
    if type(data.captureGame) == "boolean" then captureGame = data.captureGame end
end
local function saveState()
    if not writefile then return end
    pcall(writefile, STATE_FILE, HttpService:JSONEncode({ buffers = buffers, active = active, captureGame = captureGame }))
end
local saveQueued = false
local function saveSoon()
    if saveQueued then return end
    saveQueued = true
    task.delay(1, function()
        saveQueued = false
        saveState()
    end)
end
loadState()

-- ====================================================================
-- Window
-- ====================================================================
local root = mk("Frame", {
    Name = "Root", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(400, 480),
    Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = BGC, BackgroundTransparency = 0.05, BorderSizePixel = 0,
}, gui)
corner(root, 18)
ustroke(root, STROKEC, 1.5, 0.2)

local header = mk("Frame", { Size = UDim2.new(1, 0, 0, 46), BackgroundTransparency = 1 }, root)
local titleLbl = label(header, "Executor", 15, Enum.Font.GothamBold, TEXTC)
titleLbl.Position, titleLbl.Size = UDim2.fromOffset(16, 6), UDim2.fromOffset(160, 20)
statusLbl = label(header, "Ready  -  " .. MENU_KEY .. " to hide", 11, Enum.Font.Gotham, SUBC)
statusLbl.Position, statusLbl.Size = UDim2.fromOffset(16, 26), UDim2.new(1, -110, 0, 16)
statusLbl.TextTruncate = Enum.TextTruncate.AtEnd

local minBtn = button(header, "-", {
    AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -50, 0.5, 0), Size = UDim2.fromOffset(30, 30), TextSize = 18,
})
corner(minBtn, 15)
local closeBtn = button(header, "X", {
    AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(30, 30), TextSize = 12,
})
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

local body = mk("Frame", { Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 1, -46), BackgroundTransparency = 1 }, root)
local minimized = false
minBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    body.Visible = not minimized
    root.Size = minimized and UDim2.fromOffset(400, 48) or UDim2.fromOffset(400, 480)
end)

local TABS = { "Editor", "Scripts", "Output" }
local pages, tabButtons = {}, {}
local tabBar = mk("Frame", { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 0, 30), BackgroundTransparency = 1 }, body)
for idx, name in ipairs(TABS) do
    local b = button(tabBar, name, {
        Position = UDim2.new((idx - 1) / #TABS, 2, 0, 0), Size = UDim2.new(1 / #TABS, -4, 1, 0),
        BackgroundTransparency = 1, TextColor3 = SUBC, TextSize = 12, AutoButtonColor = false,
    })
    corner(b, 12)
    tabButtons[name] = b
    pages[name] = mk("Frame", { Position = UDim2.fromOffset(10, 38), Size = UDim2.new(1, -20, 1, -46), BackgroundTransparency = 1, Visible = false }, body)
end

local function selectTab(name)
    for n, p in pairs(pages) do p.Visible = (n == name) end
    for n, b in pairs(tabButtons) do
        b.BackgroundTransparency = (n == name) and 0.1 or 1
        b.TextColor3 = (n == name) and TEXTC or SUBC
    end
end
for name, b in pairs(tabButtons) do
    b.MouseButton1Click:Connect(function() selectTab(name) end)
end

-- ====================================================================
-- Output console
-- ====================================================================
local outPage = pages["Output"]
local logScroll = mk("ScrollingFrame", {
    Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, 0, 1, -44), BackgroundColor3 = PANELC, BackgroundTransparency = 0.1,
    BorderSizePixel = 0, ScrollBarThickness = 4, ScrollBarImageColor3 = GREEN,
    AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(),
}, outPage)
corner(logScroll, 12)
mk("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, logScroll)
mk("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }, logScroll)

local logLabels, logOrder = {}, 0
local function addLog(text, color)
    logOrder += 1
    local l = mk("TextLabel", {
        LayoutOrder = logOrder, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
        Text = os.date("%H:%M:%S") .. "  " .. tostring(text), TextColor3 = color or TEXTC, Font = Enum.Font.Code, TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true,
    }, logScroll)
    logLabels[#logLabels + 1] = l
    if #logLabels > 300 then
        local old = table.remove(logLabels, 1)
        old:Destroy()
    end
    task.defer(function() logScroll.CanvasPosition = Vector2.new(0, 1e6) end)
end
local function logMine(text, color) addLog(text, color) end

local clearLogBtn = button(outPage, "Clear", {
    AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(0.5, -5, 0, 38),
})
clearLogBtn.MouseButton1Click:Connect(function()
    for _, l in ipairs(logLabels) do l:Destroy() end
    logLabels = {}
end)
local capBtn = button(outPage, "", {
    AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, 0), Size = UDim2.new(0.5, -5, 0, 38),
})
local function syncCap() capBtn.Text = "Game output: " .. (captureGame and "On" or "Off") end
capBtn.MouseButton1Click:Connect(function()
    captureGame = not captureGame
    syncCap()
    saveSoon()
end)
syncCap()

connect(LogService.MessageOut, function(msg, mtype)
    if not captureGame then return end
    local color = TEXTC
    if mtype == Enum.MessageType.MessageWarning then color = YELLOW
    elseif mtype == Enum.MessageType.MessageError then color = RED
    elseif mtype == Enum.MessageType.MessageInfo then color = BLUE end
    addLog(msg, color)
end)

-- ====================================================================
-- Running code
-- ====================================================================
local function runCode(code, name)
    name = name or "script"
    if not loadstring then
        logMine("This executor has no loadstring.", RED)
        status("No loadstring")
        return false
    end
    if trim(code) == "" then
        status("Nothing to run")
        return false
    end
    local okc, fn, err = pcall(loadstring, code, "=" .. name)
    if not okc then
        -- some executors reject the chunkname argument; retry plain
        okc, fn, err = pcall(loadstring, code)
    end
    if not okc or not fn then
        local msg = tostring(okc and err or fn)
        logMine("Compile error (" .. name .. "): " .. msg, RED)
        status("Compile error")
        return false
    end
    logMine("Running " .. name .. "...", SUBC)
    status("Running " .. name)
    task.spawn(function()
        local ok, e = xpcall(fn, function(m) return debug.traceback(tostring(m), 2) end)
        if ok then
            logMine("Finished " .. name, GREEN)
            status("Finished " .. name)
        else
            logMine("Runtime error (" .. name .. "): " .. tostring(e), RED)
            status("Runtime error")
        end
    end)
    return true
end

-- ====================================================================
-- Editor page
-- ====================================================================
local edPage = pages["Editor"]

local strip = mk("ScrollingFrame", {
    Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, BorderSizePixel = 0,
    ScrollBarThickness = 0, AutomaticCanvasSize = Enum.AutomaticSize.X, CanvasSize = UDim2.new(),
    ScrollingDirection = Enum.ScrollingDirection.X,
}, edPage)
mk("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, strip)

local codeScroll = mk("ScrollingFrame", {
    Position = UDim2.fromOffset(0, 36), Size = UDim2.new(1, 0, 1, -36 - 46), BackgroundColor3 = PANELC, BackgroundTransparency = 0.1,
    BorderSizePixel = 0, ScrollBarThickness = 4, ScrollBarImageColor3 = GREEN,
    AutomaticCanvasSize = Enum.AutomaticSize.XY, CanvasSize = UDim2.new(),
    ScrollingDirection = Enum.ScrollingDirection.XY,
}, edPage)
corner(codeScroll, 12)

local lineNums = mk("TextLabel", {
    Position = UDim2.fromOffset(4, 8), Size = UDim2.fromOffset(34, 0), AutomaticSize = Enum.AutomaticSize.Y,
    BackgroundTransparency = 1, Text = "1", TextColor3 = SUBC, Font = Enum.Font.Code, TextSize = 13,
    TextXAlignment = Enum.TextXAlignment.Right, TextYAlignment = Enum.TextYAlignment.Top,
}, codeScroll)
local codeBox = mk("TextBox", {
    Position = UDim2.fromOffset(46, 8), Size = UDim2.new(1, -54, 0, 0), AutomaticSize = Enum.AutomaticSize.XY,
    BackgroundTransparency = 1, Text = "", PlaceholderText = "-- paste or type your script here",
    PlaceholderColor3 = SUBC, TextColor3 = TEXTC, Font = Enum.Font.Code, TextSize = 13,
    TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
    MultiLine = true, ClearTextOnFocus = false, TextWrapped = false,
}, codeScroll)

local function refreshLines()
    local n = 1
    for _ in codeBox.Text:gmatch("\n") do n += 1 end
    n = math.min(n, 9999)
    local t = table.create(n)
    for i = 1, n do t[i] = i end
    lineNums.Text = table.concat(t, "\n")
end

local suppress = false
codeBox:GetPropertyChangedSignal("Text"):Connect(function()
    refreshLines()
    if suppress then return end
    buffers[active].text = codeBox.Text
    saveSoon()
end)

local rebuildStrip
local function setActive(i)
    active = math.clamp(i, 1, #buffers)
    suppress = true
    codeBox.Text = buffers[active].text
    suppress = false
    refreshLines()
    codeScroll.CanvasPosition = Vector2.new(0, 0)
    rebuildStrip()
    saveSoon()
end

function rebuildStrip()
    for _, c in ipairs(strip:GetChildren()) do
        if c:IsA("TextButton") then c:Destroy() end
    end
    for i, b in ipairs(buffers) do
        local on = (i == active)
        local tb = button(strip, b.name, {
            LayoutOrder = i, Size = UDim2.fromOffset(math.clamp(#b.name * 8 + 24, 60, 150), 28),
            BackgroundColor3 = on and GREEN or BTNC, BackgroundTransparency = on and 0.1 or 0.3,
            TextColor3 = on and DARKTXT or TEXTC, TextSize = 12, TextTruncate = Enum.TextTruncate.AtEnd,
        })
        tb.MouseButton1Click:Connect(function() setActive(i) end)
    end
    local plus = button(strip, "+", { LayoutOrder = 1000, Size = UDim2.fromOffset(32, 28), TextSize = 16 })
    plus.MouseButton1Click:Connect(function()
        buffers[#buffers + 1] = { name = "Script " .. (#buffers + 1), text = "" }
        setActive(#buffers)
    end)
    if #buffers > 1 then
        local close = button(strip, "x", { LayoutOrder = 1001, Size = UDim2.fromOffset(32, 28), TextSize = 13 })
        confirmButton(close, "x", function()
            table.remove(buffers, active)
            setActive(math.clamp(active, 1, #buffers))
        end)
    end
end

-- toolbar
local tb = mk("Frame", {
    AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1,
}, edPage)
local execBtn = button(tb, "Execute", { Position = UDim2.fromOffset(0, 0), Size = UDim2.new(0.34, -4, 1, 0) }, true)
local clearBtn = button(tb, "Clear", { Position = UDim2.new(0.34, 2, 0, 0), Size = UDim2.new(0.22, -4, 1, 0) })
local copyBtn = button(tb, "Copy", { Position = UDim2.new(0.56, 2, 0, 0), Size = UDim2.new(0.22, -4, 1, 0) })
local pasteBtn = button(tb, "Paste", { Position = UDim2.new(0.78, 2, 0, 0), Size = UDim2.new(0.22, -2, 1, 0) })

execBtn.MouseButton1Click:Connect(function()
    runCode(codeBox.Text, buffers[active].name)
end)
confirmButton(clearBtn, "Clear", function()
    codeBox.Text = ""
    status("Cleared")
end)
copyBtn.MouseButton1Click:Connect(function()
    if setclipboard then
        setclipboard(codeBox.Text)
        status("Copied " .. #codeBox.Text .. " characters")
    else
        status("No clipboard in this executor")
    end
end)
pasteBtn.MouseButton1Click:Connect(function()
    if getclipboard then
        local ok, text = pcall(getclipboard)
        if ok and type(text) == "string" then
            codeBox.Text = text
            status("Pasted " .. #text .. " characters")
            return
        end
    end
    status("No clipboard read here: paste with your device's paste (tap the editor)")
end)

-- ====================================================================
-- Scripts page (workspace folder)
-- ====================================================================
local scPage = pages["Scripts"]
local canFiles = (writefile and readfile and listfiles and isfolder and makefolder) and true or false
if canFiles then
    pcall(function()
        if not isfolder(FOLDER) then makefolder(FOLDER) end
    end)
end

local nameBox = mk("TextBox", {
    Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, -96, 0, 36), BackgroundColor3 = PANELC, BackgroundTransparency = 0.1,
    Text = "", PlaceholderText = "Save current tab as...", PlaceholderColor3 = SUBC, TextColor3 = TEXTC,
    ClearTextOnFocus = false, Font = Enum.Font.Gotham, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
}, scPage)
corner(nameBox, 10)
ustroke(nameBox, STROKEC, 1, 0.4)
mk("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, nameBox)
local saveBtn = button(scPage, "Save", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(86, 36) }, true)

local fileScroll = mk("ScrollingFrame", {
    Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 1, -44 - 86), BackgroundTransparency = 1, BorderSizePixel = 0,
    ScrollBarThickness = 3, ScrollBarImageColor3 = GREEN, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(),
}, scPage)
mk("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, fileScroll)
mk("UIPadding", { PaddingRight = UDim.new(0, 6) }, fileScroll)

local bottom = mk("Frame", {
    AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 80), BackgroundTransparency = 1,
}, scPage)
local refreshBtn = button(bottom, "Refresh list", { Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, 0, 0, 36) })
local unloadBtn = button(bottom, "Unload executor", { Position = UDim2.fromOffset(0, 42), Size = UDim2.new(1, 0, 0, 36) })

local function baseName(path) return tostring(path):match("([^/\\]+)$") or tostring(path) end

local refreshFiles
local function fileRow(path, order)
    local fname = baseName(path)
    local row = mk("Frame", { Size = UDim2.new(1, 0, 0, 46), BackgroundColor3 = ROWC, BackgroundTransparency = 0.35, LayoutOrder = order }, fileScroll)
    corner(row, 12)
    local l = label(row, fname, 13, Enum.Font.GothamMedium, TEXTC)
    l.Position, l.Size = UDim2.fromOffset(12, 0), UDim2.new(1, -196, 1, 0)
    l.TextTruncate = Enum.TextTruncate.AtEnd
    local function small(text, x)
        return button(row, text, {
            AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -x, 0.5, 0), Size = UDim2.fromOffset(56, 30), TextSize = 12,
        })
    end
    local del = small("Del", 6)
    local run = small("Run", 66)
    local load = small("Load", 126)
    load.MouseButton1Click:Connect(function()
        local ok, text = pcall(readfile, path)
        if not ok then status("Couldn't read " .. fname) return end
        buffers[#buffers + 1] = { name = (fname:gsub("%.%w+$", "")), text = text }
        setActive(#buffers)
        selectTab("Editor")
        status("Loaded " .. fname)
    end)
    run.MouseButton1Click:Connect(function()
        local ok, text = pcall(readfile, path)
        if not ok then status("Couldn't read " .. fname) return end
        runCode(text, fname)
    end)
    confirmButton(del, "Del", function()
        if delfile then
            pcall(delfile, path)
            status("Deleted " .. fname)
            refreshFiles()
        else
            status("This executor can't delete files")
        end
    end)
end

function refreshFiles()
    for _, c in ipairs(fileScroll:GetChildren()) do
        if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then c:Destroy() end
    end
    if not canFiles then
        label(fileScroll, "This executor has no file functions (writefile / listfiles), so saved scripts aren't available.", 12, Enum.Font.Gotham, SUBC).Size = UDim2.new(1, 0, 0, 40)
        return
    end
    local ok, list = pcall(listfiles, FOLDER)
    if not ok or type(list) ~= "table" or #list == 0 then
        local l = label(fileScroll, "No saved scripts yet. Name the current tab and press Save.", 12, Enum.Font.Gotham, SUBC)
        l.Size = UDim2.new(1, 0, 0, 30)
        l.TextWrapped = true
        return
    end
    table.sort(list, function(a, b) return baseName(a):lower() < baseName(b):lower() end)
    for i, path in ipairs(list) do fileRow(path, i) end
end

saveBtn.MouseButton1Click:Connect(function()
    if not canFiles then status("No file functions in this executor") return end
    local nm = trim(nameBox.Text):gsub("[^%w_%- ]", "")
    nm = trim(nm)
    if nm == "" then nm = buffers[active].name:gsub("[^%w_%- ]", "") end
    if nm == "" then nm = "script" end
    local ok = pcall(writefile, FOLDER .. "/" .. nm .. ".lua", codeBox.Text)
    if ok then
        buffers[active].name = nm
        rebuildStrip()
        saveSoon()
        status("Saved " .. nm .. ".lua")
        nameBox.Text = ""
        refreshFiles()
    else
        status("Couldn't save")
    end
end)
refreshBtn.MouseButton1Click:Connect(refreshFiles)

-- ====================================================================
-- Register + unload
-- ====================================================================
local myEntry
local function unloadSelf()
    saveState()
    for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    if env.c1lownScripts[SELF_NAME] == myEntry then env.c1lownScripts[SELF_NAME] = nil end
    gui:Destroy()
end
myEntry = { unload = unloadSelf }
env.c1lownScripts[SELF_NAME] = myEntry
unloadBtn.MouseButton1Click:Connect(unloadSelf)

connect(UIS.InputBegan, function(i, gp)
    if gp or i.UserInputType ~= Enum.UserInputType.Keyboard then return end
    if i.KeyCode.Name == MENU_KEY then gui.Enabled = not gui.Enabled end
end)

setActive(active)
refreshFiles()
selectTab("Editor")
if not loadstring then
    logMine("Warning: this executor has no loadstring, so Execute won't work.", YELLOW)
end
