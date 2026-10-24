-- Anti VC (standalone): a small draggable button that silences everyone's voice chat for you.
-- Click the button to toggle. It only changes things on YOUR client:
--   * every other player is paused with VoiceChatInternal:SubscribePause (the same call Novoline's mute commands use)
--   * every other player's AudioDeviceInput is muted
--   * every Wire feeding an AudioEmitter is disabled
-- It also catches players who join (or voices that load) after you turn it on. Turning it off restores everything.
-- Works with Roblox's Audio API voice chat. Games that play voice through their own custom system are not affected.

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local lp = Players.LocalPlayer
local G = getgenv and getgenv() or _G
if type(G.AntiVCCleanup) == "function" then pcall(G.AntiVCCleanup) end

local muted, wires = setmetatable({}, {__mode = "k"}), setmetatable({}, {__mode = "k"})
local on, conn, joinConn = false, nil, nil

-- Novoline's mute method: VoiceChatInternal:SubscribePause(userId, paused) stops you receiving that player's voice
local function pauseVoice(plr, paused)
    pcall(function() game:GetService("VoiceChatInternal"):SubscribePause(plr.UserId, paused) end)
end

local function handle(d)
    pcall(function()
        if d:IsA("AudioDeviceInput") then
            if d.Player ~= lp and muted[d] == nil then muted[d] = d.Muted; d.Muted = true end
        elseif d:IsA("Wire") then
            local t = d.TargetInstance
            if t and t:IsA("AudioEmitter") and wires[d] == nil then wires[d] = d.Enabled; d.Enabled = false end
        end
    end)
end
local function enable()
    if on then return end
    on = true
    for _, d in ipairs(game:GetDescendants()) do handle(d) end
    conn = game.DescendantAdded:Connect(handle)
    for _, p in ipairs(Players:GetPlayers()) do if p ~= lp then pauseVoice(p, true) end end
    joinConn = Players.PlayerAdded:Connect(function(p) pauseVoice(p, true) end)
end
local function disable()
    on = false
    if conn then conn:Disconnect(); conn = nil end
    if joinConn then joinConn:Disconnect(); joinConn = nil end
    for _, p in ipairs(Players:GetPlayers()) do if p ~= lp then pauseVoice(p, false) end end
    for d, v in pairs(muted) do if d.Parent then pcall(function() d.Muted = v end) end; muted[d] = nil end
    for w, v in pairs(wires) do if w.Parent then pcall(function() w.Enabled = v end) end; wires[w] = nil end
end

-- button
local gui = Instance.new("ScreenGui")
gui.Name, gui.ResetOnSpawn = "AntiVC", false
gui.Parent = lp:WaitForChild("PlayerGui")
local btn = Instance.new("TextButton")
btn.Size, btn.Position = UDim2.fromOffset(110, 34), UDim2.new(1, -130, 0, 80)
btn.BackgroundColor3, btn.BorderSizePixel = Color3.fromRGB(74, 18, 28), 0
btn.Font, btn.TextSize, btn.TextColor3, btn.AutoButtonColor = Enum.Font.GothamBold, 13, Color3.fromRGB(255, 245, 245), false
btn.Text = "Anti VC: off"
btn.Parent = gui
Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 17)
local function paint()
    btn.Text = on and "Anti VC: on" or "Anti VC: off"
    TweenService:Create(btn, TweenInfo.new(.2), {BackgroundColor3 = on and Color3.fromRGB(255, 56, 74) or Color3.fromRGB(74, 18, 28)}):Play()
end
local dragging, moved, ds, sp
btn.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        dragging, moved, ds, sp = true, false, i.Position, btn.Position
    end
end)
local c1 = UIS.InputChanged:Connect(function(i)
    if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
        local d = i.Position - ds
        if d.Magnitude > 4 then moved = true end
        btn.Position = UDim2.new(sp.X.Scale, sp.X.Offset + d.X, sp.Y.Scale, sp.Y.Offset + d.Y)
    end
end)
local c2 = UIS.InputEnded:Connect(function(i)
    if dragging and (i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch) then
        dragging = false
        if not moved then
            if on then disable() else enable() end
            paint()
        end
    end
end)

G.AntiVCCleanup = function()
    disable()
    c1:Disconnect(); c2:Disconnect()
    gui:Destroy()
    G.AntiVCCleanup = nil
end
