ANTI VC PATCH FOR THE C1LOWN HUB  (4 edits inside HubMain)
Adds the commands  antivc / unantivc / muteallvc / unmuteallvc / mutevc / unmutevc / mutemic / unmutemic  and an "Anti VC" button on the hub bar.

=====================================================================
EDIT 1: add state variables
Find:
    local lastLine
    local runLine
Replace with:
    local lastLine
    local runLine
    local antiVcOn, antiBtnUpdate = false, function() end

=====================================================================
EDIT 2: add the feature
Find this header (it appears once, just above "runLine = function(line, isRepeat)"):
    ----------------------------------------------------------------------
    -- Command runner
Paste the following block ABOVE it:

----------------------------------------------------------------------
-- Anti VC: silence voice chat for you (client-side only). Mute method taken from Novoline's mute commands.
----------------------------------------------------------------------
do
    local av = {muted = weak(), wires = weak(), conn = nil, join = nil}
    local function pauseVoice(p, paused)
        pcall(function() game:GetService("VoiceChatInternal"):SubscribePause(p.UserId, paused) end)
    end
    local function handle(d)
        pcall(function()
            if d:IsA("AudioDeviceInput") then
                if d.Player ~= lp and av.muted[d] == nil then av.muted[d] = d.Muted; d.Muted = true end
            elseif d:IsA("Wire") then
                local t = d.TargetInstance
                if t and t:IsA("AudioEmitter") and av.wires[d] == nil then av.wires[d] = d.Enabled; d.Enabled = false end
            end
        end)
    end
    local function avOff()
        if av.conn then av.conn:Disconnect(); av.conn = nil end
        if av.join then av.join:Disconnect(); av.join = nil end
        for _, p in ipairs(Players:GetPlayers()) do if p ~= lp then pauseVoice(p, false) end end
        for d, v in pairs(av.muted) do if d.Parent then pcall(function() d.Muted = v end) end; av.muted[d] = nil end
        for w, v in pairs(av.wires) do if w.Parent then pcall(function() w.Enabled = v end) end; av.wires[w] = nil end
        antiVcOn = false
        antiBtnUpdate()
    end
    pair("Utility", "antivc", "unantivc", "Mute every other player's voice chat (client-side)", "Restore voice chat", nil,
        function()
            if av.conn then return end
            antiVcOn = true
            for _, p in ipairs(Players:GetPlayers()) do if p ~= lp then pauseVoice(p, true) end end
            av.join = Players.PlayerAdded:Connect(function(p) pauseVoice(p, true) end)
            for _, d in ipairs(game:GetDescendants()) do handle(d) end
            av.conn = game.DescendantAdded:Connect(handle)
            antiBtnUpdate()
            say("Anti VC on")
        end, avOff)

    -- Novoline-style per-player and mute-all commands
    def("Utility", "muteallvc", "Mute all voice chat", nil, function()
        for _, p in ipairs(Players:GetPlayers()) do if p ~= lp then pauseVoice(p, true) end end
    end, {"mavc"})
    def("Utility", "unmuteallvc", "Unmute all voice chat", nil, function()
        for _, p in ipairs(Players:GetPlayers()) do pauseVoice(p, false) end
    end, {"umavc"})
    def("Utility", "mutevc", "Mute one player's voice chat", "<player>", function(a)
        local p = findPlayer(a[1])
        if not p or p == lp then say("Player not found"); return end
        pauseVoice(p, true); say("Muted " .. p.Name)
    end, {"mvc"})
    def("Utility", "unmutevc", "Unmute one player's voice chat", "<player>", function(a)
        local p = findPlayer(a[1])
        if not p then say("Player not found"); return end
        pauseVoice(p, false); say("Unmuted " .. p.Name)
    end, {"umvc"})

    local mic = weak()
    local function micOff()
        for d, v in pairs(mic) do if d.Parent then pcall(function() d.Muted = v end) end; mic[d] = nil end
    end
    pair("Utility", "mutemic", "unmutemic", "Mute your own microphone", "Unmute your own microphone", nil,
        function()
            for _, d in ipairs(game:GetDescendants()) do
                if d:IsA("AudioDeviceInput") and d.Player == lp and mic[d] == nil then mic[d] = d.Muted; d.Muted = true end
            end
        end, micOff)
end

=====================================================================
EDIT 3: widen the bar (so the new button fits)
Find:
    local BAR_W, BAR_H = 500, 54
Replace with:
    local BAR_W, BAR_H = 584, 54

=====================================================================
EDIT 4: add the button
Find:
    local closeBtn = barBtn("X", 456, 34)
Replace with:
    local antiBtn = barBtn("Anti VC", 452, 80)
    antiBtnUpdate = function()
        tween(antiBtn, {BackgroundColor3 = antiVcOn and C.accent or C.card, BackgroundTransparency = antiVcOn and 0 or .2}, TweenInfo.new(.2))
    end
    antiBtn.Activated:Connect(function() runLine(antiVcOn and "unantivc" or "antivc") end)
    local closeBtn = barBtn("X", 540, 34)
