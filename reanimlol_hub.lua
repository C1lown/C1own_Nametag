            ppScale.Scale = .9
            pp.BackgroundTransparency = 1
            tween(ppScale, {Scale = 1}, TweenInfo.new(.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
            tween(pp, {BackgroundTransparency = .16}, TweenInfo.new(.25))
            refreshPlayers()
        else
            tween(ppScale, {Scale = .9}, TweenInfo.new(.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In))
            task.delay(.15, function() if not destroyed then pp.Visible = false end end)
        end
        tween(playersBtn, {BackgroundColor3 = show and C.accent or C.card, BackgroundTransparency = show and 0 or .2}, TweenInfo.new(.2))
    end
    playersBtn.Activated:Connect(function() setPP(not pp.Visible) end)
end
rebuild()
countLbl.Text = #LIST .. " commands"

-- open / close the panels
local function setPanel(show)
    if show then
        panel.Visible = true
        pScale.Scale = .92
        panel.BackgroundTransparency = 1
        tween(pScale, {Scale = 1}, TweenInfo.new(.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
        tween(panel, {BackgroundTransparency = .16}, TweenInfo.new(.25))
    else
        tween(pScale, {Scale = .92}, TweenInfo.new(.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In))
        task.delay(.15, function() if not destroyed then panel.Visible = false end end)
    end
    tween(cmdBtn, {BackgroundColor3 = show and C.accent or C.card, BackgroundTransparency = show and 0 or .2}, TweenInfo.new(.2))
end
cmdBtn.Activated:Connect(function() setPanel(not panel.Visible) end)

local function reanimOpen() return type(G.ReanimlolCleanup) == "function" end
reanimBtn.Activated:Connect(function()
    if reanimOpen() then
        pcall(G.ReanimlolCleanup)
    else
        local ok, err = pcall(ReanimlolModule)
        if not ok then warn("c1lown hub: reanim failed: " .. tostring(err)); say("Reanim failed to load") end
    end
end)
startLoop("ui", 0.4, function()
    local on = reanimOpen()
    tween(reanimBtn, {BackgroundColor3 = on and C.accent or C.card, BackgroundTransparency = on and 0 or .2}, TweenInfo.new(.2))
end)

-- ";" jumps to the command bar
bind(UIS.InputBegan, function(i, processed)
    if destroyed or processed or typing() then return end
    if i.KeyCode == Enum.KeyCode.Semicolon then
        if not panel.Visible then setPanel(true) end
        task.delay(0.03, function() runBox:CaptureFocus(); task.defer(function() runBox.Text = "" end) end)
    end
end)

local function cleanup()
    if destroyed then return end
    destroyed = true
    for _, f in ipairs(OFFS) do pcall(f) end
    for k in pairs(LOOPS) do LOOPS[k] = nil end
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    if type(G.ReanimlolCleanup) == "function" then pcall(G.ReanimlolCleanup) end
    if G.C1lownHubCleanup == cleanup then G.C1lownHubCleanup = nil end
    gui:Destroy()
end
closeBtn.Activated:Connect(cleanup)
G.C1lownHubCleanup = cleanup

return {Destroy = cleanup}
end

return HubMain()
