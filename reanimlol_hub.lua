-- reanimlol hub: red skin, Play / Live / Tricks / Prefs tabs + a command bar (press ; or chat ;command)
-- Clone-and-follow reanimation: an invisible-to-others clone is what you control and animate, and your real
-- body is snapped onto it every frame. Simulation radius is boosted so other players see the real parts move.
-- Everything is keyframes (no animation assets). Saved data goes to the "Reanimlol" folder when writefile exists.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")
local player = Players.LocalPlayer
assert(player, "Run on the client")

local env = getgenv and getgenv() or _G
if type(env.ReanimHubCleanup) == "function" then pcall(env.ReanimHubCleanup) end

local destroyed = false
local conns = {}
local function connect(sig, fn) local c = sig:Connect(fn); conns[#conns + 1] = c; return c end

----------------------------------------------------------------------
-- Persistence
----------------------------------------------------------------------
local ROOT = "Reanimlol"
local hasFS = type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function"
    and type(makefolder) == "function" and type(isfolder) == "function"
local function ensureFolder(p) if hasFS then pcall(function() if not isfolder(p) then makefolder(p) end end) end end
local settings = {
    speed = 1, loop = true, walkSync = true, blend = 0.15, noclip = true, boost = true,
    keyToggle = "RightControl", keyGui = "RightShift", keyCmd = "Semicolon", keyAim = "LeftAlt", keyStop = "X",
}
local DATA_FILE = ROOT .. "/hub.json"
if hasFS then
    pcall(function()
        if isfile(DATA_FILE) then
            local d = HttpService:JSONDecode(readfile(DATA_FILE))
            for k, v in pairs(d) do if type(settings[k]) == type(v) then settings[k] = v end end
        end
    end)
end
local function save()
    if not hasFS then return end
    pcall(function() ensureFolder(ROOT); writefile(DATA_FILE, HttpService:JSONEncode(settings)) end)
end
local saveTok = 0
local function saveSoon() saveTok += 1; local t = saveTok; task.delay(1, function() if t == saveTok then save() end end) end

----------------------------------------------------------------------
-- Core reanimation (clone + follow)
----------------------------------------------------------------------
local function boostSim()
    if not settings.boost then return end
    pcall(function()
        if sethiddenproperty then
            sethiddenproperty(player, "SimulationRadius", 1e9)
            pcall(sethiddenproperty, player, "MaximumSimulationRadius", 1e9)
        elseif setsimulationradius then setsimulationradius(1e9, 1e9) end
    end)
end

local core = (function()
    local S = {session = nil, starting = false, rev = 0, onStop = nil}

    local function setProp(s, obj, prop, value)
        s.saved[#s.saved + 1] = {obj, prop, obj[prop]}
        obj[prop] = value
    end

    local function stop()
        S.rev += 1
        S.starting = false
        local s = S.session
        S.session = nil
        if not s then return end
        for k, c in pairs(s.conns) do s.conns[k] = nil; pcall(function() c:Disconnect() end) end
        local cf = s.copyRoot.Parent and s.copyRoot.CFrame or nil
        if cf and s.root.Parent then
            s.root.CFrame = cf
            s.root.AssemblyLinearVelocity = Vector3.zero
        end
        for i = #s.saved, 1, -1 do
            local o, p, v = table.unpack(s.saved[i])
            pcall(function() o[p] = v end)
        end
        pcall(function() Workspace.CurrentCamera.CameraSubject = s.humanoid end)
        pcall(function() s.copy:Destroy() end)
        pcall(function() s.humanoid:ChangeState(Enum.HumanoidStateType.GettingUp) end)
        if S.onStop then pcall(S.onStop) end
    end

    local function start()
        if S.session then return end
        if S.starting then return "Already starting" end
        S.rev += 1
        local rev = S.rev
        S.starting = true
        local ok, err = pcall(function()
            local char = player.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local root = char and char:FindFirstChild("HumanoidRootPart")
            assert(hum and root and hum.Health > 0, "Character not ready")
            assert(not root.Anchored, "Character is anchored")
            boostSim()
            local controls
            local scripts = player:FindFirstChild("PlayerScripts")
            local module = scripts and scripts:FindFirstChild("PlayerModule")
            if module and module:IsA("ModuleScript") then
                local good, v = pcall(function() return require(module):GetControls() end)
                if good and v and type(v.GetMoveVector) == "function" then controls = v end
            end
            -- clone (temporarily archivable)
            local changed = {}
            local good, copy = pcall(function()
                local list = char:GetDescendants()
                table.insert(list, char)
                for _, o in ipairs(list) do if not o.Archivable then changed[#changed + 1] = o; o.Archivable = true end end
                return char:Clone()
            end)
            for _, o in ipairs(changed) do pcall(function() o.Archivable = false end) end
            assert(good and copy, "Clone failed")
            for _, d in ipairs(copy:GetDescendants()) do
                if d:IsA("LuaSourceContainer") or d:IsA("Tool") or d:IsA("ForceField") then d:Destroy() end
            end
            copy.Name = "ReanimHubBody"
            local cHum = copy:FindFirstChildOfClass("Humanoid")
            local cRoot = copy:FindFirstChild("HumanoidRootPart")
            assert(cHum and cRoot, "Rig incomplete")
            local hasMotor = false
            for _, d in ipairs(copy:GetDescendants()) do if d:IsA("Motor6D") then hasMotor = true; break end end
            assert(hasMotor, "Rig needs Motor6D joints")
            cHum.RequiresNeck, cHum.BreakJointsOnDeath = false, false
            cHum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
            copy.Parent = Workspace
            copy:PivotTo(char:GetPivot())
            cRoot.AssemblyLinearVelocity = root.AssemblyLinearVelocity
            cHum:ChangeState(Enum.HumanoidStateType.GettingUp)

            local s = {character = char, humanoid = hum, root = root, copy = copy, cHum = cHum, cRoot = cRoot,
                saved = {}, conns = {}, links = {}, controls = controls, focused = true}
            S.session = s
            -- real body: loose joints, invisible, not colliding
            for _, d in ipairs(char:GetDescendants()) do
                if not d:FindFirstAncestorOfClass("Tool") then
                    if d:IsA("JointInstance") or d:IsA("WeldConstraint") then setProp(s, d, "Enabled", false)
                    elseif d:IsA("BasePart") then
                        setProp(s, d, "CanCollide", false)
                        setProp(s, d, "Transparency", 1)
                        if d ~= root then setProp(s, d, "Massless", true) end
                    elseif d:IsA("Decal") then setProp(s, d, "Transparency", 1) end
                end
            end
            setProp(s, hum, "PlatformStand", true)
            setProp(s, hum, "RequiresNeck", false)
            setProp(s, hum, "BreakJointsOnDeath", false)
            local animate = char:FindFirstChild("Animate")
            if animate and animate:IsA("LocalScript") then setProp(s, animate, "Disabled", true) end
            local animator = hum:FindFirstChildOfClass("Animator")
            if animator then for _, t in ipairs(animator:GetPlayingAnimationTracks()) do t:Stop(0) end end
            for _, part in ipairs(char:GetChildren()) do
                local base = copy:FindFirstChild(part.Name)
                if part:IsA("BasePart") and base and base:IsA("BasePart") then s.links[#s.links + 1] = {part = part, base = base} end
            end
            setProp(s, Workspace.CurrentCamera, "CameraSubject", hum)
            Workspace.CurrentCamera.CameraSubject = cHum

            local function valid()
                return S.session == s and player.Character == char and char.Parent and copy.Parent
                    and hum.Parent == char and cHum.Parent == copy and root.Parent == char and cRoot.Parent == copy
            end
            local function follow()
                local v = cRoot.AssemblyLinearVelocity
                for _, l in ipairs(s.links) do
                    if l.part.Parent and l.base.Parent then
                        l.part.CFrame = l.base.CFrame
                        l.part.AssemblyLinearVelocity = v
                        l.part.AssemblyAngularVelocity = Vector3.zero
                    end
                end
            end
            local function listen(name, sig, fn)
                s.conns[name] = sig:Connect(function(...)
                    if S.session ~= s then return end
                    local good2, problem = pcall(fn, ...)
                    if not good2 then stop(); warn("reanim hub: " .. tostring(problem)) end
                end)
            end
            listen("died", hum.Died, stop)
            listen("cdied", cHum.Died, stop)
            listen("removing", player.CharacterRemoving, function(m) if m == char then stop() end end)
            listen("focus", UserInputService.WindowFocused, function() s.focused = true end)
            listen("blur", UserInputService.WindowFocusReleased, function() s.focused = false; cHum:Move(Vector3.zero) end)
            listen("jump", UserInputService.JumpRequest, function()
                if s.focused and not UserInputService:GetFocusedTextBox() then cHum.Jump = true end
            end)
            listen("camera", Workspace:GetPropertyChangedSignal("CurrentCamera"), function()
                Workspace.CurrentCamera.CameraSubject = cHum
            end)
            listen("step", RunService.PreSimulation, function()
                if not valid() then stop(); return end
                boostSim()
                hum.PlatformStand = true
                for _, l in ipairs(s.links) do if l.part.CanCollide then l.part.CanCollide = false end end
                local move, rel = Vector3.zero, false
                if s.focused and not UserInputService:GetFocusedTextBox() then
                    if s.controls then
                        local g, v = pcall(function() return s.controls:GetMoveVector() end)
                        if g and typeof(v) == "Vector3" then move, rel = v, true else s.controls = nil end
                    end
                    if not s.controls then move = cHum.MoveDirection end
                end
                if move.Magnitude ~= move.Magnitude or move.Magnitude == math.huge then move = Vector3.zero end
                if move.Magnitude > 1 then move = move.Unit end
                cHum:Move(move, rel)
                follow()
            end)
            if RunService.PostSimulation then
                listen("post", RunService.PostSimulation, function() if valid() then follow() end end)
            end
            listen("beat", RunService.Heartbeat, function()
                if not valid() then stop(); return end
                boostSim(); follow()
            end)
        end)
        if rev ~= S.rev then return "Cancelled" end
        S.starting = false
        if not ok then stop(); return (tostring(err):gsub("^.-:%d+: ", "")) end
    end

    return {Start = start, Stop = stop,
        Get = function() local s = S.session; return s and s.copy.Parent and s.copy or nil end,
        OnStop = function(fn) S.onStop = fn end}
end)()

----------------------------------------------------------------------
-- Keyframes: sampling, baking, library
----------------------------------------------------------------------
local styles = {Linear = Enum.EasingStyle.Linear, Sine = Enum.EasingStyle.Sine, Quad = Enum.EasingStyle.Quad,
    Cubic = Enum.EasingStyle.Cubic, Back = Enum.EasingStyle.Back, Bounce = Enum.EasingStyle.Bounce}
local dirs = {In = Enum.EasingDirection.In, Out = Enum.EasingDirection.Out, InOut = Enum.EasingDirection.InOut}

local function sample(curve, t, dur, looped)
    local n = #curve
    if n == 1 then return curve[1].value end
    local a, b
    for i = n, 1, -1 do if curve[i].time <= t then a = curve[i]; b = curve[i + 1]; break end end
    local at, bt
    if not a then
        if not looped then return curve[1].value end
        a, b = curve[n], curve[1]; at, bt = a.time - dur, b.time
    elseif not b then
        if not looped then return a.value end
        b = curve[1]; at, bt = a.time, b.time + dur
    else at, bt = a.time, b.time end
    local alpha = bt > at and math.clamp((t - at) / (bt - at), 0, 1) or 1
    alpha = TweenService:GetValue(alpha, styles[a.style] or Enum.EasingStyle.Linear, dirs[a.direction] or Enum.EasingDirection.InOut)
    return a.value:Lerp(b.value, alpha)
end

-- pose joints -> part names. rotations are degrees (x,y,z) + optional offset (dx,dy,dz) relative to rest
local PARTS = {
    R15 = {Hips = "LowerTorso", Torso = "UpperTorso", Head = "Head", LArm = "LeftUpperArm", RArm = "RightUpperArm",
        LForearm = "LeftLowerArm", RForearm = "RightLowerArm", LLeg = "LeftUpperLeg", RLeg = "RightUpperLeg",
        LShin = "LeftLowerLeg", RShin = "RightLowerLeg"},
    R6 = {Hips = "Torso", Torso = "Torso", Head = "Head", LArm = "Left Arm", RArm = "Right Arm",
        LLeg = "Left Leg", RLeg = "Right Leg"},
}
local function bake(def, rig, motors)
    local used, last = {}, 0
    for _, k in ipairs(def.keys) do last = math.max(last, k.t); for j in pairs(k.pose) do used[j] = true end end
    local curves, map = {}, PARTS[rig] or PARTS.R15
    for _, k in ipairs(def.keys) do
        local acc = {}
        for j in pairs(used) do
            local v = k.pose[j] or {}
            local part = map[j]
            local m = part and motors[part]
            if m then
                local rc = m.C0.Rotation
                local d = CFrame.Angles(math.rad(v[1] or 0), math.rad(v[2] or 0), math.rad(v[3] or 0))
                local t = rc:Inverse() * d * rc
                if (v[4] or 0) ~= 0 or (v[5] or 0) ~= 0 or (v[6] or 0) ~= 0 then
                    t = CFrame.new(rc:VectorToObjectSpace(Vector3.new(v[4] or 0, v[5] or 0, v[6] or 0))) * t
                end
                acc[part] = acc[part] and acc[part] * t or t
            end
        end
        for part, cf in pairs(acc) do
            curves[part] = curves[part] or {}
            table.insert(curves[part], {time = k.t, value = cf, style = k.style or "Sine", direction = k.dir or "InOut"})
        end
    end
    return {curves = curves, duration = math.max(def.duration or last, last, 0.05), looped = def.loop ~= false,
        hold = def.hold == true, rig = rig}
end

local function K(t, pose, style, dir) return {t = t, pose = pose, style = style, dir = dir} end
local function cycle(dur, n, fn)
    local keys = {}
    for i = 0, n do keys[#keys + 1] = {t = dur * i / n, pose = fn(i / n * 2 * math.pi), style = "Linear", dir = "InOut"} end
    return {duration = dur, loop = true, keys = keys}
end

local LIB = {}
local function add(cat, name, def) LIB[#LIB + 1] = {key = "b:" .. cat .. "/" .. name, name = name, cat = cat, sub = cat, def = def} end
local WH = {0, 0, -6}
add("Emotes", "Wave", {duration = 2, loop = false, keys = {
    K(0, {RArm = {0, 0, 4}}), K(0.35, {RArm = {0, 0, 112}, RForearm = {0, 0, 66}, Head = WH}),
    K(0.6, {RArm = {0, 0, 122}, RForearm = {0, 0, 100}, Head = WH}), K(0.85, {RArm = {0, 0, 102}, RForearm = {0, 0, 36}, Head = WH}),
    K(1.1, {RArm = {0, 0, 122}, RForearm = {0, 0, 100}, Head = WH}), K(1.35, {RArm = {0, 0, 102}, RForearm = {0, 0, 36}, Head = WH}),
    K(2, {RArm = {0, 0, 4}})}})
add("Emotes", "Bow", {duration = 2.4, loop = false, keys = {K(0, {}),
    K(0.7, {Torso = {-50, 0, 0}, Head = {-12, 0, 0}}, "Quad", "Out"), K(1.5, {Torso = {-50, 0, 0}, Head = {-12, 0, 0}}), K(2.4, {})}})
add("Emotes", "Point", {duration = 1.8, loop = false, keys = {K(0, {}),
    K(0.3, {RArm = {88, 0, 4}, Torso = {0, -10, 0}, Head = {0, -10, 0}}, "Quad", "Out"),
    K(1.4, {RArm = {88, 0, 4}, Torso = {0, -10, 0}, Head = {0, -10, 0}}), K(1.8, {})}})
add("Emotes", "Cheer", {duration = 0.6, loop = true, keys = {
    K(0, {RArm = {0, 0, 150}, LArm = {0, 0, -150}}),
    K(0.3, {RArm = {0, 0, 172}, LArm = {0, 0, -172}, Head = {14, 0, 0}, Hips = {0, 0, 0, 0, 0.22, 0}}),
    K(0.6, {RArm = {0, 0, 150}, LArm = {0, 0, -150}})}})
add("Emotes", "Clap", {duration = 0.5, loop = true, keys = {
    K(0, {RArm = {50, 0, -42}, LArm = {50, 0, 42}, RForearm = {40, 0, -25}, LForearm = {40, 0, 25}}),
    K(0.25, {RArm = {50, 0, -20}, LArm = {50, 0, 20}, RForearm = {40, 0, -8}, LForearm = {40, 0, 8}}),
    K(0.5, {RArm = {50, 0, -42}, LArm = {50, 0, 42}, RForearm = {40, 0, -25}, LForearm = {40, 0, 25}})}})
add("Poses", "T-Pose", {duration = 0.6, loop = false, hold = true, keys = {K(0, {}),
    K(0.25, {RArm = {0, 0, 90}, LArm = {0, 0, -90}}, "Quad", "Out"), K(0.6, {RArm = {0, 0, 90}, LArm = {0, 0, -90}})}})
add("Poses", "Zombie", {duration = 0.6, loop = false, hold = true, keys = {K(0, {}),
    K(0.3, {RArm = {88, 0, 3}, LArm = {88, 0, -3}, Head = {0, 0, 8}, Torso = {-8, 0, 0}}, "Quad", "Out"),
    K(0.6, {RArm = {88, 0, 3}, LArm = {88, 0, -3}, Head = {0, 0, 8}, Torso = {-8, 0, 0}})}})
add("Dances", "Bounce", cycle(0.8, 8, function(a)
    local s = math.sin(a)
    return {Hips = {0, 0, s * 4, 0, 0.12 * s * s, 0}, RArm = {s * 30, 0, 20}, LArm = {-s * 30, 0, -20},
        RForearm = {50, 0, 0}, LForearm = {50, 0, 0}}
end))
add("Dances", "Disco", cycle(1.2, 12, function(a)
    local s = math.sin(a)
    return {RArm = {0, 0, 30 + 120 * (0.5 + 0.5 * s)}, LArm = {0, 0, -(30 + 120 * (0.5 - 0.5 * s))},
        Hips = {0, 0, s * 8}, Torso = {0, 0, -s * 6}, Head = {0, 0, s * 5}}
end))
add("Dances", "Spin", {duration = 1.2, loop = true, keys = {
    K(0, {Hips = {0, 0, 0}, RArm = {0, 0, 70}, LArm = {0, 0, -70}}, "Linear"),
    K(0.3, {Hips = {0, 90, 0}, RArm = {0, 0, 70}, LArm = {0, 0, -70}}, "Linear"),
    K(0.6, {Hips = {0, 180, 0}, RArm = {0, 0, 70}, LArm = {0, 0, -70}}, "Linear"),
    K(0.9, {Hips = {0, 270, 0}, RArm = {0, 0, 70}, LArm = {0, 0, -70}}, "Linear"),
    K(1.2, {Hips = {0, 360, 0}, RArm = {0, 0, 70}, LArm = {0, 0, -70}}, "Linear")}})

local function gait(dur, swing, knee, arm)
    return cycle(dur, 12, function(a)
        local c = math.cos(a)
        return {RLeg = {swing * math.sin(a), 0, 0}, LLeg = {-swing * math.sin(a), 0, 0},
            RShin = {-knee * math.max(0, c), 0, 0}, LShin = {-knee * math.max(0, -c), 0, 0},
            RArm = {-arm * math.sin(a), 0, 0}, LArm = {arm * math.sin(a), 0, 0}}
    end)
end
local STATE_DEFS = {walk = gait(0.8, 35, 40, 30), run = gait(0.5, 55, 70, 55),
    jump = {duration = 0.4, loop = true, keys = {K(0, {RArm = {0, 0, 140}, LArm = {0, 0, -140}}), K(0.4, {RArm = {0, 0, 140}, LArm = {0, 0, -140}})}},
    fall = {duration = 0.4, loop = true, keys = {K(0, {RArm = {0, 0, 100}, LArm = {0, 0, -100}}), K(0.4, {RArm = {0, 0, 100}, LArm = {0, 0, -100}})}}}

-- imported keyframes (Lua export text parsed as plain text, never executed, or pose JSON)
local fileClips = {}
local function parseLua(text)
    local out, heads = {}, {}
    for pos, name in text:gmatch('()%["([^"]+)"%]%s*=%s*{%s*{%s*Time') do heads[#heads + 1] = {pos = pos, name = name} end
    if #heads == 0 then heads[1] = {pos = 1, name = "Imported"} end
    for i, h in ipairs(heads) do
        local body = text:sub(h.pos, heads[i + 1] and heads[i + 1].pos - 1 or #text)
        local times = {}
        for pos, t in body:gmatch("()Time%s*=%s*([%-%d%.eE]+)") do if tonumber(t) then times[#times + 1] = {pos = pos, t = tonumber(t)} end end
        local curves, dur = {}, 0
        for j, f in ipairs(times) do
            local seg = body:sub(f.pos, times[j + 1] and times[j + 1].pos - 1 or #body)
            for part, nums in seg:gmatch('%["([^"]+)"%]%s*=%s*CFrame%.new%(([^%)]*)%)') do
                local c = {}
                for n in nums:gmatch("[^,%s]+") do c[#c + 1] = tonumber(n) end
                if #c == 12 then
                    curves[part] = curves[part] or {}
                    table.insert(curves[part], {time = f.t, value = CFrame.new(table.unpack(c)), style = "Linear", direction = "InOut"})
                end
            end
            dur = math.max(dur, f.t)
        end
        if dur > 0 and next(curves) then
            local rig = (curves.UpperTorso or curves.LowerTorso) and "R15" or (curves.Torso and "R6") or nil
            out[#out + 1] = {name = h.name, clip = {curves = curves, duration = dur, looped = true, rig = rig}}
        end
    end
    return out
end
local function loadFiles()
    table.clear(fileClips)
    if not (hasFS and type(listfiles) == "function") then return 0 end
    ensureFolder(ROOT); ensureFolder(ROOT .. "/keyframes")
    local n = 0
    local function scan(folder, depth)
        local ok, paths = pcall(listfiles, folder)
        if not ok then return end
        for _, p in ipairs(paths) do
            p = tostring(p):gsub("\\", "/")
            local isDir = false
            pcall(function() isDir = isfolder(p) end)
            if isDir then if depth < 3 then scan(p, depth + 1) end
            else
                local ext = (p:match("%.(%w+)$") or ""):lower()
                if ext == "txt" or ext == "lua" or ext == "json" then
                    local base = p:match("([^/]+)%.%w+$") or "Imported"
                    local okR, raw = pcall(readfile, p)
                    if okR and type(raw) == "string" and raw:find("CFrame.new", 1, true) and raw:find("Time%s*=") then
                        for _, item in ipairs(parseLua(raw)) do
                            local name = item.name == "Imported" and base or item.name
                            fileClips[#fileClips + 1] = {key = "f:" .. name, name = name, cat = "Imported", sub = "Imported", clip = item.clip}
                            n += 1
                        end
                    end
                end
            end
        end
    end
    scan(ROOT .. "/keyframes", 0)
    return n
end
loadFiles()
local function entries()
    local out = {}
    for _, e in ipairs(LIB) do out[#out + 1] = e end
    for _, e in ipairs(fileClips) do out[#out + 1] = e end
    return out
end
local function findEntry(q)
    q = (q or ""):lower()
    if q == "" then return nil end
    local starts, contains
    for _, e in ipairs(entries()) do
        local n = e.name:lower()
        if n == q then return e end
        if not starts and n:sub(1, #q) == q then starts = e end
        if not contains and n:find(q, 1, true) then contains = e end
    end
    return starts or contains
end

----------------------------------------------------------------------
-- Theme + GUI helpers
----------------------------------------------------------------------
local C = {bg = Color3.fromRGB(30, 6, 9), field = Color3.fromRGB(66, 18, 24), card = Color3.fromRGB(78, 20, 27),
    text = Color3.fromRGB(255, 244, 244), dim = Color3.fromRGB(218, 150, 156), accent = Color3.fromRGB(255, 48, 64),
    off = Color3.fromRGB(104, 34, 40), stroke = Color3.fromRGB(220, 56, 68), green = Color3.fromRGB(80, 210, 100)}
local function tween(o, p, info) local t = TweenService:Create(o, info or TweenInfo.new(.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), p); t:Play(); return t end
local function T(class, props, parent)
    local o = Instance.new(class)
    if o:IsA("GuiObject") then o.BorderSizePixel = 0 end
    if class == "TextLabel" or class == "TextButton" or class == "TextBox" then
        o.Font = Enum.Font.GothamBold; o.TextSize = 13; o.TextColor3 = C.text
        if class == "TextLabel" then o.BackgroundTransparency = 1; o.Font = Enum.Font.GothamMedium else o.BackgroundColor3 = C.field end
        if class == "TextButton" then o.AutoButtonColor = false end
        if class == "TextBox" then o.ClearTextOnFocus = false; o.PlaceholderColor3 = C.dim end
    end
    for k, v in pairs(props) do o[k] = v end
    o.Parent = parent
    return o
end
local function corner(o, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = o end
local function hover(b)
    b.MouseEnter:Connect(function() tween(b, {BackgroundTransparency = math.max(b.BackgroundTransparency - .15, 0)}, TweenInfo.new(.1)) end)
    b.MouseLeave:Connect(function() tween(b, {BackgroundTransparency = b:GetAttribute("rest") or 0}, TweenInfo.new(.15)) end)
end
local function button(parent, text, x, y, w, h, cb)
    local b = T("TextButton", {Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), Text = text, TextSize = 12}, parent)
    b:SetAttribute("rest", 0)
    corner(b, 10); hover(b)
    if cb then b.Activated:Connect(cb) end
    return b
end
local function label(parent, text, x, y, w, h, extra)
    local p = {Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), Text = text, TextXAlignment = Enum.TextXAlignment.Left}
    for k, v in pairs(extra or {}) do p[k] = v end
    return T("TextLabel", p, parent)
end
local function box(parent, ph, x, y, w, h)
    local b = T("TextBox", {Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), Text = "", PlaceholderText = ph,
        TextXAlignment = Enum.TextXAlignment.Left, BackgroundColor3 = C.card, BackgroundTransparency = .24}, parent)
    corner(b, 10)
    T("UIPadding", {PaddingLeft = UDim.new(0, 12)}, b)
    return b
end
local function switch(parent, x, y, initial, cb)
    local b = T("TextButton", {Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(46, 24), Text = "", BackgroundColor3 = C.off}, parent)
    corner(b, 12)
    local knob = T("Frame", {Size = UDim2.fromOffset(18, 18), Position = UDim2.fromOffset(3, 3), BackgroundColor3 = C.text}, b)
    corner(knob, 9)
    local api = {value = initial}
    function api.set(v)
        api.value = v
        tween(b, {BackgroundColor3 = v and C.accent or C.off})
        tween(knob, {Position = UDim2.fromOffset(v and 25 or 3, 3)}, TweenInfo.new(.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
    end
    b.Activated:Connect(function() api.set(not api.value); if cb then cb(api.value) end end)
    api.set(initial)
    return api
end
local function slider(parent, x, y, w, min, max, value, cb)
    local bar = T("Frame", {Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, 14), BackgroundTransparency = 1}, parent)
    local track = T("Frame", {AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(0, 0, .5, 0), Size = UDim2.new(1, 0, 0, 6), BackgroundColor3 = C.off}, bar)
    corner(track, 3)
    local fill = T("Frame", {Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.accent}, track)
    corner(fill, 3)
    local knob = T("Frame", {AnchorPoint = Vector2.new(.5, .5), Size = UDim2.fromOffset(14, 14), Position = UDim2.new(0, 0, .5, 0), BackgroundColor3 = C.text, ZIndex = 2}, bar)
    corner(knob, 7)
    local api, dragging = {}, false
    function api.set(v, fire)
        v = math.clamp(v, min, max)
        local p = (v - min) / (max - min)
        fill.Size = UDim2.fromScale(p, 1); knob.Position = UDim2.new(p, 0, .5, 0)
        api.value = v
        if fire and cb then cb(v) end
    end
    local function fromX(px) api.set(min + (max - min) * math.clamp((px - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1), true) end
    bar.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = true; fromX(i.Position.X) end
    end)
    connect(UserInputService.InputChanged, function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then fromX(i.Position.X) end
    end)
    connect(UserInputService.InputEnded, function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)
    api.set(value, false)
    return api
end
local function selected(b, on)
    b.BackgroundColor3 = on and C.accent or C.field
    b.TextColor3 = on and Color3.new(1, 1, 1) or C.dim
end

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
local engine = {motors = {}, anims = {}, baked = {}, paused = false, dir = 1, fadeT = 1, snapshot = {}, parts = {}}
local live = {on = false, aim = false, group = "rarm", mirror = false, pole = false, pose = {}, cur = {}}
local tricks = {head = {on = false, yaw = 0, pitch = 0}, torso = {on = false, strength = 1, yaw = 0, pitch = 0}, fly = {on = false, speed = 40}}
local turnOn, turnOff, setStatus, playEntry, refreshPlay, flyStop
local mainState = {value = false}

----------------------------------------------------------------------
-- Window
----------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name, gui.ResetOnSpawn, gui.ZIndexBehavior = "ReanimHub", false, Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")
local W, H = 380, 478
local panel = T("Frame", {Size = UDim2.fromOffset(W, H), Position = UDim2.new(0.5, -W / 2, 0.5, -H / 2),
    BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = .12, Active = true}, gui)
corner(panel, 14)
do
    local st = Instance.new("UIStroke"); st.Color, st.Thickness, st.Transparency, st.ApplyStrokeMode = C.stroke, 1, .45, Enum.ApplyStrokeMode.Border; st.Parent = panel
    local g = Instance.new("UIGradient"); g.Rotation = 90
    g.Color = ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.fromRGB(110, 14, 24)), ColorSequenceKeypoint.new(.45, Color3.fromRGB(58, 8, 14)), ColorSequenceKeypoint.new(1, Color3.fromRGB(24, 3, 6))})
    g.Parent = panel
end
local scale = Instance.new("UIScale"); scale.Scale = .9; scale.Parent = panel
tween(scale, {Scale = 1}, TweenInfo.new(.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
local bar = T("Frame", {Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1}, panel)
local title = label(bar, "reanimlol hub", 18, 0, 220, 44, {Font = Enum.Font.GothamBold, TextSize = 18, TextTruncate = Enum.TextTruncate.AtEnd})
do
    local dragging, ds, sp
    bar.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging, ds, sp = true, i.Position, panel.Position end
    end)
    connect(UserInputService.InputChanged, function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - ds
            panel.Position = UDim2.new(sp.X.Scale, sp.X.Offset + d.X, sp.Y.Scale, sp.Y.Offset + d.Y)
        end
    end)
    connect(UserInputService.InputEnded, function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)
end
local stTok = 0
setStatus = function(text, sticky)
    stTok += 1
    local t = stTok
    title.Text = text
    if not sticky and text ~= "reanimlol hub" then
        task.delay(3, function() if t == stTok and not destroyed then title.Text = "reanimlol hub" end end)
    end
end
local function barBtn(off, glyph, cb)
    local b = T("TextButton", {Size = UDim2.fromOffset(28, 28), Position = UDim2.new(1, -off - 28, .5, -14), Text = glyph,
        BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = .82, ZIndex = 20}, panel)
    corner(b, 14)
    b.MouseEnter:Connect(function() tween(b, {BackgroundTransparency = .6}, TweenInfo.new(.15)) end)
    b.MouseLeave:Connect(function() tween(b, {BackgroundTransparency = .82}, TweenInfo.new(.2)) end)
    b.Activated:Connect(cb)
end
barBtn(14, "X", function() if env.ReanimHubCleanup then env.ReanimHubCleanup() end end)
local minimized = false
barBtn(46, "-", function()
    minimized = not minimized
    panel.ClipsDescendants = true
    tween(panel, {Size = UDim2.fromOffset(W, minimized and 44 or H)}, TweenInfo.new(.35, Enum.EasingStyle.Quint))
    if not minimized then task.delay(.4, function() if not destroyed and not minimized then panel.ClipsDescendants = false end end) end
end)

local dot = T("Frame", {Position = UDim2.fromOffset(28, 67), Size = UDim2.fromOffset(6, 6), BackgroundColor3 = C.off}, panel)
corner(dot, 3)
local statusLbl = label(panel, "Status: Idle", 44, 54, 190, 32, {Font = Enum.Font.GothamSemibold, TextColor3 = C.dim})
local mainBtn = T("TextButton", {Position = UDim2.fromOffset(W - 18 - 120, 54), Size = UDim2.fromOffset(120, 32), Text = "Reanimate",
    BackgroundColor3 = C.card, BackgroundTransparency = .5}, panel)
corner(mainBtn, 10)
function mainState.set(v)
    mainState.value = v
    mainBtn.Text = v and "Stop Reanim" or "Reanimate"
    statusLbl.Text = v and "Status: Active" or "Status: Idle"
    tween(dot, {BackgroundColor3 = v and C.green or C.off})
end
mainBtn.Activated:Connect(function() if mainState.value then turnOff() else turnOn() end end)

-- tabs
local tabNames = {"Play", "Live", "Tricks", "Prefs"}
local tabBar = T("Frame", {Position = UDim2.fromOffset(18, 96), Size = UDim2.fromOffset(W - 36, 34), BackgroundTransparency = 1}, panel)
local CELL = 1 / #tabNames
local pill = T("Frame", {Position = UDim2.new(0, 3, 0, 3), Size = UDim2.new(CELL, -6, 1, -6), BackgroundColor3 = Color3.fromRGB(230, 40, 58), BackgroundTransparency = .25}, tabBar)
corner(pill, 8)
local tabFrames, tabBtns, tabIdx, current = {}, {}, {}, "Play"
local function showTab(name)
    if name == current then return end
    current = name
    tween(pill, {Position = UDim2.new(CELL * (tabIdx[name] - 1), 3, 0, 3)}, TweenInfo.new(.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
    for n, f in pairs(tabFrames) do
        f.Visible = (n == name)
        tabBtns[n].TextColor3 = (n == name) and C.text or C.dim
    end
end
for i, n in ipairs(tabNames) do
    tabIdx[n] = i
    tabFrames[n] = T("Frame", {Position = UDim2.fromOffset(18, 138), Size = UDim2.fromOffset(W - 36, 300), BackgroundTransparency = 1, Visible = (i == 1)}, panel)
    tabBtns[n] = T("TextButton", {Position = UDim2.new(CELL * (i - 1), 0, 0, 0), Size = UDim2.new(CELL, 0, 1, 0), BackgroundTransparency = 1,
        Text = n, TextSize = 12, TextColor3 = (i == 1) and C.text or C.dim, ZIndex = 3}, tabBar)
    tabBtns[n].Activated:Connect(function() showTab(n) end)
end
local TW = W - 36 -- tab content width

local function rowLabel(parent, text, y) label(parent, text, 4, y, TW - 70, 26) end
local function toggleRow(parent, text, y, initial, cb)
    rowLabel(parent, text, y)
    return switch(parent, TW - 50, y + 1, initial, cb)
end
local function sliderRow(parent, text, y, min, max, value, fmt, cb)
    label(parent, text, 4, y, 70, 22, {TextColor3 = C.dim, TextSize = 12})
    local val = label(parent, string.format(fmt, value), TW - 56, y, 56, 22, {TextColor3 = C.dim, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right})
    return slider(parent, 76, y + 4, TW - 140, min, max, value, function(v) val.Text = string.format(fmt, v); cb(v) end)
end

-- footer speed
label(panel, "Speed", 18, 448, 46, 22, {TextColor3 = C.dim, TextSize = 12})
local speedVal = label(panel, string.format("%.2fx", settings.speed), W - 76, 448, 58, 22, {TextColor3 = C.dim, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right})
local speedSlider
local function setSpeed(v)
    v = math.clamp(math.floor(v * 20 + 0.5) / 20, 0.1, 3)
    settings.speed = v
    if speedSlider then speedSlider.set(v, false) end
    speedVal.Text = string.format("%.2fx", v)
    saveSoon()
end
speedSlider = slider(panel, 70, 452, W - 160, 0.1, 3, settings.speed, function(v) setSpeed(v) end)

----------------------------------------------------------------------
-- Engine
----------------------------------------------------------------------
local function resolve(entry)
    if entry.clip then return entry.clip end
    if not entry.def or not engine.rig then return nil end
    local b = engine.baked[entry.def]
    if not b then b = bake(entry.def, engine.rig, engine.motors); engine.baked[entry.def] = b end
    return b
end
local function usable(anim)
    if not anim or (anim.rig and anim.rig ~= engine.rig) then return false end
    for n in pairs(engine.motors) do if anim.curves[n] then return true end end
    return false
end
local function stateName(hum, speed)
    local st = hum:GetState()
    if st == Enum.HumanoidStateType.Jumping then return "jump"
    elseif st == Enum.HumanoidStateType.Freefall then return "fall" end
    if speed < 0.75 then return "idle" end
    return speed > 20 and "run" or "walk"
end
local EMPTY = {curves = {}, duration = 1, looped = true}

local liveStep, tricksStep
local function engineStep(dt)
    local copy = engine.copy
    if not copy or not copy.Parent then return end
    if settings.noclip then for _, p in ipairs(engine.parts) do if p.Parent and p.CanCollide then p.CanCollide = false end end end
    local hum, root = engine.hum, engine.root
    local v = root.AssemblyLinearVelocity
    local speed = Vector3.new(v.X, 0, v.Z).Magnitude
    local st = stateName(hum, speed)
    local e = engine.emote
    local desired, src, loop, rate = nil, nil, true, 1
    if e then desired, src, loop = e.anim, e, e.loop
    else
        desired = engine.anims[st] or engine.anims.idle or EMPTY
        src = desired
        loop = desired.looped ~= false
        if settings.walkSync and (st == "walk" or st == "run") then rate = math.clamp(speed / 16, .5, 2) end
    end
    local cur = engine.current
    if not cur or cur.src ~= src then
        for _, m in pairs(engine.motors) do engine.snapshot[m] = m.Transform end
        engine.fadeT = 0
        cur = {src = src, anim = desired, t = 0}
        engine.current = cur
    end
    local dur = desired.duration
    if not engine.paused then cur.t += dt * settings.speed * rate * engine.dir end
    local t = cur.t
    if loop then t = t % dur; cur.t = t
    elseif t >= dur then
        t = dur; cur.t = dur
        if e and not desired.hold and engine.dir > 0 and not engine.paused then engine.emote = nil end
    elseif t <= 0 then
        t = 0; cur.t = 0
        if e and engine.dir < 0 and not engine.paused then engine.emote = nil end
    end
    engine.fadeT += dt
    local alpha = settings.blend > 0 and math.min(engine.fadeT / settings.blend, 1) or 1
    for name, m in pairs(engine.motors) do
        local curve = desired.curves[name]
        local target = curve and sample(curve, t, dur, loop) or CFrame.identity
        if alpha < 1 then target = (engine.snapshot[m] or target):Lerp(target, alpha) end
        m.Transform = target
    end
    for _, fn in ipairs({tricksStep, liveStep}) do
        local ok, err = pcall(fn, dt)
        if not ok and not engine.warned then engine.warned = true; warn("reanim hub: " .. tostring(err)) end
    end
end

local function engineStart()
    local copy = core.Get()
    if not copy then return end
    engine.copy = copy
    engine.hum = copy:FindFirstChildOfClass("Humanoid")
    engine.root = copy:FindFirstChild("HumanoidRootPart")
    engine.rig = engine.hum.RigType == Enum.HumanoidRigType.R6 and "R6" or "R15"
    engine.motors, engine.baked, engine.anims, engine.parts = {}, {}, {}, {}
    for _, m in ipairs(copy:GetDescendants()) do
        if m:IsA("Motor6D") and m.Part1 then engine.motors[m.Part1.Name] = m end
        if m:IsA("BasePart") then engine.parts[#engine.parts + 1] = m end
    end
    for s, def in pairs(STATE_DEFS) do
        local a = resolve({def = def})
        if usable(a) then engine.anims[s] = a end
    end
    engine.current, engine.emote, engine.snapshot, engine.fadeT = nil, nil, {}, 1
    engine.conn = RunService.PreSimulation:Connect(engineStep)
end
local function engineStop()
    if engine.conn then engine.conn:Disconnect(); engine.conn = nil end
    if flyStop then flyStop() end
    engine.copy, engine.hum, engine.root, engine.current, engine.emote = nil, nil, nil, nil, nil
    engine.motors, engine.anims, engine.parts = {}, {}, {}
    engine.paused, engine.dir = false, 1
    live.on, live.aim, live.pole, live.pose, live.cur = false, false, false, {}, {}
    if refreshPlay then refreshPlay() end
end

local busy, startRev = false, 0
turnOn = function(after)
    if core.Get() then if after then after() end return end
    if busy then return end
    busy = true
    startRev += 1
    local rev = startRev
    mainState.set(true)
    setStatus("Starting...", true)
    task.spawn(function()
        local msg = core.Start()
        busy = false
        if destroyed or rev ~= startRev then return end
        if msg or not core.Get() then
            core.Stop(); mainState.set(false)
            setStatus(msg and tostring(msg):sub(1, 38) or "Can't start")
            return
        end
        engineStart()
        setStatus("reanimlol hub")
        if after then after() end
    end)
end
turnOff = function()
    startRev += 1; busy = false
    core.Stop(); mainState.set(false); setStatus("reanimlol hub")
end
core.OnStop(function()
    engineStop()
    if destroyed then return end
    mainState.set(false); setStatus("reanimlol hub")
end)

playEntry = function(entry)
    turnOn(function()
        local anim = resolve(entry)
        if not usable(anim) then setStatus("Doesn't fit this rig"); return end
        engine.emote = {anim = anim, loop = settings.loop and not anim.hold, name = entry.name, key = entry.key}
        engine.paused, engine.dir = false, 1
        engine.lastEntry = entry
        if refreshPlay then refreshPlay() end
        setStatus(entry.name)
    end)
end
local function stopEmote() engine.emote = nil end

----------------------------------------------------------------------
-- Play tab
----------------------------------------------------------------------
do
    local tab = tabFrames.Play
    local search = box(tab, "Search animations...", 0, 0, TW, 28)
    local list = T("ScrollingFrame", {Position = UDim2.fromOffset(0, 34), Size = UDim2.fromOffset(TW, 168), BackgroundTransparency = 1,
        ScrollBarThickness = 2, ScrollBarImageColor3 = C.accent, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y}, tab)
    T("UIListLayout", {Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder}, list)
    T("UIPadding", {PaddingLeft = UDim.new(0, 2), PaddingRight = UDim.new(0, 4), PaddingTop = UDim.new(0, 2)}, list)
    local rows = {}
    local function rebuild()
        for _, c in ipairs(list:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end
        rows = {}
        local q = search.Text:lower()
        local n = 0
        for _, e in ipairs(entries()) do
            if q == "" or (e.name .. " " .. e.cat):lower():find(q, 1, true) then
                n += 1
                local row = T("TextButton", {Size = UDim2.new(1, -4, 0, 28), Text = "", LayoutOrder = n, BackgroundColor3 = C.accent, BackgroundTransparency = 1}, list)
                row:SetAttribute("rest", 1)
                corner(row, 8)
                label(row, e.name, 10, 0, 180, 28, {TextSize = 12, TextTruncate = Enum.TextTruncate.AtEnd})
                label(row, e.cat, TW - 110, 0, 90, 28, {TextSize = 10, TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Right})
                row.MouseEnter:Connect(function() tween(row, {BackgroundTransparency = .7}, TweenInfo.new(.12)) end)
                row.MouseLeave:Connect(function() tween(row, {BackgroundTransparency = engine.emote and engine.emote.key == e.key and .8 or 1}, TweenInfo.new(.15)) end)
                row.Activated:Connect(function()
                    if engine.emote and engine.emote.key == e.key then stopEmote(); setStatus("Stopped " .. e.name) else playEntry(e) end
                end)
                rows[e.key] = row
            end
        end
    end
    connect(search:GetPropertyChangedSignal("Text"), rebuild)
    rebuild()
    env.ReanimHubRebuild = rebuild

    local btnW = (TW - 18) / 4
    local function step() end
    button(tab, "Restart", 0, 210, btnW, 28, function()
        if engine.emote and engine.current then engine.current.t = engine.dir < 0 and engine.current.anim.duration or 0
        elseif engine.lastEntry then playEntry(engine.lastEntry) end
        engine.paused = false; refreshPlay()
    end)
    local pauseBtn = button(tab, "Pause", btnW + 6, 210, btnW, 28, function()
        if not engine.current then return end
        engine.paused = not engine.paused; refreshPlay()
    end)
    local revBtn = button(tab, "Reverse", (btnW + 6) * 2, 210, btnW, 28, function() engine.dir = -engine.dir; refreshPlay() end)
    button(tab, "Stop", (btnW + 6) * 3, 210, btnW, 28, function() stopEmote() end)
    refreshPlay = function()
        if destroyed then return end
        pauseBtn.Text = engine.paused and "Play" or "Pause"
        selected(pauseBtn, engine.paused)
        selected(revBtn, engine.dir < 0)
    end
    refreshPlay()
    toggleRow(tab, "Loop emotes", 246, settings.loop, function(v)
        settings.loop = v
        if engine.emote then engine.emote.loop = v and not engine.emote.anim.hold end
        saveSoon()
    end)
    label(tab, "Click an animation to play it, click again to stop. Drop keyframe files in Reanimlol/keyframes/ and run the reload command.",
        4, 274, TW - 8, 26, {TextSize = 9, TextColor3 = C.dim, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top})
end

----------------------------------------------------------------------
-- Live tab: aim limbs at the mouse
----------------------------------------------------------------------
local ctl = {}
do
    local tab = tabFrames.Live
    local GROUPS = {{"larm", "L Arm"}, {"rarm", "R Arm"}, {"lleg", "L Leg"}, {"rleg", "R Leg"}}
    local PARTSET = {
        R15 = {larm = "LeftUpperArm", rarm = "RightUpperArm", lleg = "LeftUpperLeg", rleg = "RightUpperLeg"},
        R6 = {larm = "Left Arm", rarm = "Right Arm", lleg = "Left Leg", rleg = "Right Leg"},
    }
    local LOWER = {
        R15 = {larm = "LeftLowerArm", rarm = "RightLowerArm", lleg = "LeftLowerLeg", rleg = "RightLowerLeg"},
        R6 = {},
    }
    local OPP = {larm = "rarm", rarm = "larm", lleg = "rleg", rleg = "lleg"}
    local mouseRay = RaycastParams.new()
    mouseRay.FilterType, mouseRay.IgnoreWater = Enum.RaycastFilterType.Exclude, true
    local function hitPoint()
        local cam = Workspace.CurrentCamera
        if not cam then return nil end
        local mp = UserInputService:GetMouseLocation()
        local ray = cam:ViewportPointToRay(mp.X, mp.Y)
        local ignore = {}
        if engine.copy then ignore[#ignore + 1] = engine.copy end
        if player.Character then ignore[#ignore + 1] = player.Character end
        mouseRay.FilterDescendantsInstances = ignore
        local hit = Workspace:Raycast(ray.Origin, ray.Direction * 400, mouseRay)
        return hit and hit.Position or ray.Origin + ray.Direction * 60
    end
    env.ReanimHubHit = hitPoint

    -- rotation (in the joint's frame) that points a limb hanging along -Y at a world position
    local function aim(part, target)
        local m = engine.motors[part]
        if not (m and m.Parent and m.Part0 and m.Part0.Parent) then return nil end
        local J = m.Part0.CFrame * m.C0
        local dW = target - J.Position
        if dW.Magnitude < 0.1 then return nil end
        local dl = J:VectorToObjectSpace(dW.Unit)
        local Rc = m.C1.Rotation:Inverse()
        local from = Rc:VectorToWorldSpace(Vector3.new(0, -1, 0))
        local dot = math.clamp(from:Dot(dl), -1, 1)
        local axis = from:Cross(dl)
        if axis.Magnitude < 1e-4 then
            if dot > 0 then return CFrame.identity end
            axis = Rc:VectorToWorldSpace(Vector3.new(1, 0, 0))
        end
        return CFrame.fromAxisAngle(axis.Unit, math.acos(dot))
    end
    local function groupParts(g)
        local set = PARTSET[engine.rig or "R15"] or PARTSET.R15
        local low = LOWER[engine.rig or "R15"] or {}
        return set[g], low[g]
    end
    local function setGroup(g, target)
        local up, low = groupParts(g)
        if not up then return end
        local cf = aim(up, target)
        if cf then live.pose[up] = cf end
        if low then live.pose[low] = CFrame.identity end
    end

    liveStep = function(dt)
        if not live.on then return end
        local cam = Workspace.CurrentCamera
        if live.pole and cam then
            for _, g in ipairs({"larm", "rarm"}) do
                local up, low = groupParts(g)
                local m = up and engine.motors[up]
                if m and m.Part0 then
                    local J = m.Part0.CFrame * m.C0
                    setGroup(g, J.Position + cam.CFrame.LookVector * 50)
                end
            end
        elseif live.aim then
            local target = hitPoint()
            if target then
                setGroup(live.group, target)
                if live.mirror then setGroup(OPP[live.group], target) end
            end
        end
        local k = 1 - math.exp(-dt * 14)
        for part, target in pairs(live.pose) do
            local m = engine.motors[part]
            if m and m.Parent then
                local c = (live.cur[part] or CFrame.identity):Lerp(target, k)
                live.cur[part] = c
                m.Transform = c
            end
        end
    end

    local liveSwitch, poleSwitch, hint
    local groupBtns = {}
    local function refresh()
        if destroyed then return end
        if not live.on then live.pole = false end
        liveSwitch.set(live.on); poleSwitch.set(live.pole)
        for id, b in pairs(groupBtns) do selected(b, id == live.group) end
        hint.Text = "Hold " .. settings.keyAim .. " to aim the selected limb at your mouse"
    end
    ctl.setLive = function(v)
        if v then
            local function on() live.on = true; setStatus("Live control on"); refresh() end
            if engine.copy then on() else turnOn(on) end
        else
            live.on, live.aim, live.pole, live.pose, live.cur = false, false, false, {}, {}
            setStatus("Live control off")
        end
        refresh()
    end
    ctl.setPole = function(v)
        if v and not live.on then ctl.setLive(true) end
        live.pole = v and true or false
        if not v then live.pose, live.cur = {}, {} end
        refresh()
    end
    ctl.setAim = function(v)
        v = v and live.on or false
        if live.aim == v then return end
        live.aim = v
        if not v then live.pose, live.cur = {}, {} end
    end
    ctl.setGroup = function(g) live.group = g; refresh() end
    ctl.refresh = refresh
    label(tab, "Live limb control", 4, 0, 220, 26)
    liveSwitch = switch(tab, TW - 50, 1, false, function(v) ctl.setLive(v) end)
    local gw = (TW - 18) / 4
    for i, g in ipairs(GROUPS) do
        groupBtns[g[1]] = button(tab, g[2], (i - 1) * (gw + 6), 34, gw, 28, function() live.group = g[1]; refresh() end)
    end
    hint = label(tab, "", 4, 68, TW - 8, 20, {TextSize = 10, TextColor3 = C.dim})
    toggleRow(tab, "Mirror to opposite limb", 94, false, function(v) live.mirror = v end)
    poleSwitch = toggleRow(tab, "Pole arms (along camera)", 126, false, function(v) ctl.setPole(v) end)
    button(tab, "Reset limbs", 0, 164, TW, 28, function() live.pose, live.cur, live.pole = {}, {}, false; refresh() end)
    label(tab, "Limbs smooth toward your mouse while the aim key is held. Releasing the key lets them relax back into the animation.",
        4, 200, TW - 8, 40, {TextSize = 10, TextColor3 = C.dim, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top})
    refresh()
end

----------------------------------------------------------------------
-- Tricks tab: head / torso tracking and fly
----------------------------------------------------------------------
do
    local tab = tabFrames.Tricks
    local function turnToward(cur, goal, rate, dt)
        local diff = ((goal - cur + math.pi) % (2 * math.pi)) - math.pi
        return cur + diff * (1 - math.exp(-rate * dt))
    end
    local function ease(cur, goal, rate, dt) return cur + (goal - cur) * (1 - math.exp(-rate * dt)) end
    local function angles(m, dir, maxYaw, minP, maxP)
        local d = m.Part0.CFrame:VectorToObjectSpace(dir)
        local yaw = math.atan2(-d.X, -d.Z)
        if math.abs(yaw) > math.rad(115) then return 0, 0 end
        return math.clamp(yaw, -maxYaw, maxYaw), math.clamp(math.asin(math.clamp(d.Y, -1, 1)), minP, maxP)
    end
    local function rotate(m, yaw, pitch)
        if math.abs(yaw) + math.abs(pitch) < 0.002 then return end
        local R = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
        local c0 = m.C0.Rotation
        m.Transform = (c0:Inverse() * R * c0) * m.Transform
    end

    local flySwitch
    flyStop = function()
        local F = tricks.fly
        if F.on then
            F.on = false
            if F.hum and F.hum.Parent then pcall(function() F.hum.PlatformStand = F.platform == true end) end
            if F.root and F.root.Parent then pcall(function() F.root.AssemblyLinearVelocity = Vector3.zero end) end
        end
        F.root, F.hum = nil, nil
        tricks.head.yaw, tricks.head.pitch, tricks.torso.yaw, tricks.torso.pitch = 0, 0, 0, 0
        if flySwitch then flySwitch.set(false) end
    end
    local function flyDrive(F, dt)
        local cam = Workspace.CurrentCamera
        if not cam then return end
        local look, right = cam.CFrame.LookVector, cam.CFrame.RightVector
        local fl = Vector3.new(look.X, 0, look.Z)
        fl = fl.Magnitude > 1e-3 and fl.Unit or Vector3.new(0, 0, -1)
        local typing = UserInputService:GetFocusedTextBox() ~= nil
        local x, z, up = 0, 0, 0
        if not typing then
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then x += 1 end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then x -= 1 end
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then z += 1 end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then z -= 1 end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) or UserInputService:IsKeyDown(Enum.KeyCode.E) then up += 1 end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.Q) then up -= 1 end
        end
        local dir = look * z + right * x + Vector3.yAxis * up
        if dir.Magnitude > 1 then dir = dir.Unit end
        F.vel = F.vel:Lerp(dir * F.speed, 1 - math.exp(-6 * dt))
        F.yaw = turnToward(F.yaw, math.atan2(-fl.X, -fl.Z), 8, dt)
        F.cf = CFrame.new(F.cf.Position + F.vel * dt) * CFrame.Angles(0, F.yaw, 0)
        F.root.CFrame = F.cf
        F.root.AssemblyLinearVelocity = Vector3.zero
        F.root.AssemblyAngularVelocity = Vector3.zero
    end
    tricksStep = function(dt)
        local cam = Workspace.CurrentCamera
        local H, m = tricks.head, engine.motors.Head
        if m and m.Part0 and not live.pose.Head then
            local gy, gp = 0, 0
            if H.on and cam then gy, gp = angles(m, cam.CFrame.LookVector, math.rad(75), math.rad(-50), math.rad(60)) end
            H.yaw, H.pitch = turnToward(H.yaw, gy, 12, dt), ease(H.pitch, gp, 12, dt)
            rotate(m, H.yaw, H.pitch)
        end
        local B = tricks.torso
        local tm = engine.motors[engine.rig == "R6" and "Torso" or "UpperTorso"]
        if tm and tm.Part0 then
            local gy, gp = 0, 0
            if B.on and cam then
                local yaw, pitch = angles(tm, cam.CFrame.LookVector, math.rad(60), math.rad(-80), math.rad(80))
                gy, gp = yaw * B.strength, math.clamp(pitch * .4, math.rad(-22), math.rad(22)) * B.strength
            end
            B.yaw, B.pitch = turnToward(B.yaw, gy, 8, dt), ease(B.pitch, gp, 8, dt)
            rotate(tm, B.yaw, B.pitch)
        end
        local F = tricks.fly
        if F.on then
            if F.root and F.root.Parent and F.hum and F.hum.Parent then flyDrive(F, dt) else flyStop() end
        end
    end
    ctl.setFly = function(v)
        local F = tricks.fly
        if not v then flyStop(); return end
        local function go()
            if not (engine.copy and engine.root and engine.hum) then flySwitch.set(false); return end
            F.root, F.hum = engine.root, engine.hum
            F.platform = F.hum.PlatformStand
            F.cf = F.root.CFrame
            F.vel = Vector3.zero
            local _, ry = F.cf:ToOrientation()
            F.yaw = ry
            F.hum.PlatformStand = true
            F.on = true
            flySwitch.set(true)
            setStatus("Flying: WASD, Space up, Ctrl down")
        end
        if engine.copy then go() else turnOn(go) end
    end
    toggleRow(tab, "Head follows camera", 0, false, function(v) tricks.head.on = v end)
    toggleRow(tab, "Torso follows camera", 34, false, function(v) tricks.torso.on = v end)
    sliderRow(tab, "Strength", 66, 0.25, 2, tricks.torso.strength, "%.2f", function(v) tricks.torso.strength = v end)
    flySwitch = toggleRow(tab, "Fly", 104, false, function(v) ctl.setFly(v) end)
    sliderRow(tab, "Fly speed", 136, 10, 200, tricks.fly.speed, "%.0f", function(v) tricks.fly.speed = math.floor(v + 0.5) end)
    label(tab, "Fly: WASD along the camera, Space / E up, Ctrl / Q down. Turn it off to drop back down. Head and torso tracking stack on top of the playing animation.",
        4, 172, TW - 8, 54, {TextSize = 10, TextColor3 = C.dim, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top})
end

----------------------------------------------------------------------
-- Prefs tab
----------------------------------------------------------------------
local bindBtns, binding = {}, nil
do
    local tab = tabFrames.Prefs
    toggleRow(tab, "Noclip while reanimated", 0, settings.noclip, function(v) settings.noclip = v; saveSoon() end)
    toggleRow(tab, "Sync walk speed to movement", 32, settings.walkSync, function(v) settings.walkSync = v; saveSoon() end)
    toggleRow(tab, "Boost replication", 64, settings.boost, function(v) settings.boost = v; saveSoon() end)
    sliderRow(tab, "Blend", 96, 0, 0.5, settings.blend, "%.2fs", function(v) settings.blend = math.floor(v * 100 + 0.5) / 100; saveSoon() end)
    local function bindRow(text, key, y)
        label(tab, text, 4, y, 200, 28)
        bindBtns[key] = button(tab, settings[key], TW - 124, y, 124, 28, function()
            binding = key
            bindBtns[key].Text = "press key..."
        end)
    end
    bindRow("Toggle reanim key", "keyToggle", 130)
    bindRow("Hide / show GUI key", "keyGui", 162)
    bindRow("Command bar key", "keyCmd", 194)
    bindRow("Aim key (Live)", "keyAim", 226)
    label(tab, "Esc cancels a rebind. Hotkeys are ignored while typing.", 4, 260, TW - 8, 14, {TextSize = 10, TextColor3 = C.dim})
end

----------------------------------------------------------------------
-- Command bar
----------------------------------------------------------------------
local cmds = {}
do
    local function def(names, fn) for n in names:gmatch("%S+") do cmds[n] = fn end end
    local function bool(a, cur)
        if a == nil then return not cur end
        a = a:lower()
        if a == "on" or a == "true" or a == "1" then return true end
        if a == "off" or a == "false" or a == "0" then return false end
    end
    def("reanim on", function() turnOn(); return "Reanimating..." end)
    def("unreanim off", function() turnOff(); return "Reanim off" end)
    def("toggle", function() if core.Get() then turnOff(); return "Reanim off" end turnOn(); return "Reanimating..." end)
    def("close exit", function() if env.ReanimHubCleanup then env.ReanimHubCleanup() end end)
    def("play", function(a, rest)
        local e = findEntry(rest)
        if not e then return "No animation matches '" .. rest .. "'" end
        playEntry(e); return "Playing " .. e.name
    end)
    def("stop", function() stopEmote(); return "Stopped" end)
    def("random", function()
        local all = entries()
        local e = all[math.random(#all)]
        playEntry(e); return "Playing " .. e.name
    end)
    def("list", function(a, rest)
        local names, q = {}, rest:lower()
        for _, e in ipairs(entries()) do if q == "" or (e.name .. " " .. e.cat):lower():find(q, 1, true) then names[#names + 1] = e.name end end
        return #names == 0 and "Nothing found" or (#names .. " animations: " .. table.concat(names, ", "))
    end)
    def("pause", function() engine.paused = true; refreshPlay(); return "Paused" end)
    def("resume", function() engine.paused = false; refreshPlay(); return "Resumed" end)
    def("reverse", function() engine.dir = -engine.dir; refreshPlay(); return engine.dir < 0 and "Reverse" or "Forward" end)
    def("speed", function(a)
        local n = tonumber(a[1]); if not n then return "Usage: speed <0.1-3>" end
        setSpeed(n); return string.format("Speed %.2fx", settings.speed)
    end)
    def("noclip", function(a)
        local v = bool(a[1], settings.noclip); if v == nil then return "Usage: noclip [on/off]" end
        settings.noclip = v; saveSoon(); return "Noclip " .. (v and "on" or "off")
    end)
    def("boost", function(a)
        local v = bool(a[1], settings.boost); if v == nil then return "Usage: boost [on/off]" end
        settings.boost = v; saveSoon(); return "Replication boost " .. (v and "on" or "off")
    end)
    def("live", function(a)
        local v = bool(a[1], live.on); if v == nil then return "Usage: live [on/off]" end
        ctl.setLive(v); return "Live " .. (v and "on" or "off")
    end)
    def("limb", function(a)
        local g = (a[1] or ""):lower()
        if g ~= "larm" and g ~= "rarm" and g ~= "lleg" and g ~= "rleg" then return "Usage: limb <larm|rarm|lleg|rleg>" end
        ctl.setGroup(g); return "Selected " .. g
    end)
    def("aim", function(a)
        if not live.on then return "Turn live on first" end
        local v = bool(a[1], live.aim); if v == nil then return "Usage: aim [on/off]" end
        ctl.setAim(v); return "Aim " .. (v and "on" or "off")
    end)
    def("pole", function(a)
        local v = bool(a[1], live.pole); if v == nil then return "Usage: pole [on/off]" end
        ctl.setPole(v); return "Pole " .. (v and "on" or "off")
    end)
    def("head", function(a)
        local v = bool(a[1], tricks.head.on); if v == nil then return "Usage: head [on/off]" end
        tricks.head.on = v; return "Head tracking " .. (v and "on" or "off")
    end)
    def("torso", function(a)
        local v = bool(a[1], tricks.torso.on); if v == nil then return "Usage: torso [on/off]" end
        tricks.torso.on = v; return "Torso tracking " .. (v and "on" or "off")
    end)
    def("fly", function(a)
        local v = bool(a[1], tricks.fly.on); if v == nil then return "Usage: fly [on/off]" end
        ctl.setFly(v); return v and "Flying" or "Fly off"
    end)
    def("flyspeed", function(a)
        local n = tonumber(a[1]); if not n then return "Usage: flyspeed <10-200>" end
        tricks.fly.speed = math.floor(math.clamp(n, 10, 200) + 0.5); return "Fly speed " .. tricks.fly.speed
    end)
    def("reload", function()
        local n = loadFiles()
        if env.ReanimHubRebuild then env.ReanimHubRebuild() end
        return "Loaded " .. n .. " imported clips"
    end)
    def("gui", function() panel.Visible = not panel.Visible; return panel.Visible and "GUI shown" or "GUI hidden" end)
    def("tab", function(a)
        local want = (a[1] or ""):lower()
        for _, n in ipairs(tabNames) do if n:lower() == want then panel.Visible = true; showTab(n); return "Tab " .. n end end
        return "Tabs: " .. table.concat(tabNames, ", ")
    end)
    def("status", function()
        return table.concat({
            "Reanim: " .. (core.Get() and ("on (" .. tostring(engine.rig) .. ")") or "off"),
            "Playing: " .. (engine.emote and engine.emote.name or "none") .. (engine.paused and " (paused)" or ""),
            string.format("Speed %.2fx  Noclip %s  Boost %s", settings.speed, tostring(settings.noclip), tostring(settings.boost)),
            "Live " .. tostring(live.on) .. "  Fly " .. tostring(tricks.fly.on),
        }, "\n")
    end)
    def("help", function()
        return "reanim | unreanim | toggle | status | close\nplay <name> | stop | random | list [filter]\npause | resume | reverse | speed <0.1-3>\nnoclip | boost | reload\nlive | limb <larm|rarm|lleg|rleg> | aim | pole\nhead | torso | fly | flyspeed <n>\ngui | tab <name>"
    end)
end

local barFrame = T("Frame", {AnchorPoint = Vector2.new(.5, 1), Position = UDim2.new(.5, 0, 1, -24), Size = UDim2.fromOffset(460, 36),
    BackgroundColor3 = C.bg, BackgroundTransparency = .08, Visible = false, ZIndex = 30}, gui)
corner(barFrame, 12)
local input = box(barFrame, "command   (type help)", 4, 4, 452, 28)
input.ZIndex = 31
local outFrame = T("ScrollingFrame", {AnchorPoint = Vector2.new(.5, 1), Position = UDim2.new(.5, 0, 1, -66), Size = UDim2.fromOffset(460, 150),
    BackgroundColor3 = C.bg, BackgroundTransparency = .08, Visible = false, ScrollBarThickness = 3, CanvasSize = UDim2.new(),
    AutomaticCanvasSize = Enum.AutomaticSize.Y, ZIndex = 30}, gui)
corner(outFrame, 12)
T("UIPadding", {PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8)}, outFrame)
local outLabel = T("TextLabel", {Size = UDim2.new(1, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Text = "", TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextSize = 12, ZIndex = 31}, outFrame)
local function say(text)
    outLabel.Text = text
    outFrame.Visible = true
    setStatus((text:match("[^\n]+") or text):sub(1, 38))
end
local function run(line)
    line = (line or ""):gsub("^%s+", "")
    if line:sub(1, 1) == ";" then line = line:sub(2) end
    local name, rest = line:match("^(%S+)%s*(.-)%s*$")
    if not name then return end
    local fn = cmds[name:lower()]
    if not fn then say("Unknown command '" .. name .. "'. Type help."); return end
    local args = {}
    for w in rest:gmatch("%S+") do args[#args + 1] = w end
    local ok, res = pcall(fn, args, rest)
    if destroyed then return end
    if not ok then say("Error: " .. tostring(res)) elseif res then say(tostring(res)) end
end
local function openBar() barFrame.Visible = true; input:CaptureFocus(); task.defer(function() input.Text = "" end) end
local function closeBar() barFrame.Visible = false; outFrame.Visible = false; input.Text = ""; input:ReleaseFocus() end
connect(input.FocusLost, function(enter)
    if destroyed then return end
    if enter then
        local text = input.Text
        input.Text = ""
        if text:match("%S") then run(text) end
        task.defer(function() if barFrame.Visible and not destroyed then input:CaptureFocus() end end)
    else closeBar() end
end)
connect(player.Chatted, function(msg) if not destroyed and msg:sub(1, 1) == ";" then run(msg) end end)

----------------------------------------------------------------------
-- Hotkeys + lifecycle
----------------------------------------------------------------------
connect(UserInputService.InputBegan, function(i, processed)
    if destroyed then return end
    if binding then
        if i.UserInputType == Enum.UserInputType.Keyboard then
            if i.KeyCode ~= Enum.KeyCode.Escape then settings[binding] = i.KeyCode.Name; saveSoon() end
            bindBtns[binding].Text = settings[binding]
            binding = nil
            ctl.refresh()
        end
        return
    end
    if processed or UserInputService:GetFocusedTextBox() or i.UserInputType ~= Enum.UserInputType.Keyboard then return end
    local k = i.KeyCode.Name
    if k == settings.keyToggle then if core.Get() then turnOff() else turnOn() end
    elseif k == settings.keyGui then panel.Visible = not panel.Visible
    elseif k == settings.keyCmd then if barFrame.Visible then closeBar() else openBar() end
    elseif k == settings.keyAim then ctl.setAim(true)
    elseif k == settings.keyStop then stopEmote() end
end)
connect(UserInputService.InputEnded, function(i)
    if i.UserInputType == Enum.UserInputType.Keyboard and i.KeyCode.Name == settings.keyAim then ctl.setAim(false) end
end)

local function cleanup()
    if destroyed then return end
    destroyed = true
    save()
    engineStop()
    core.Stop()
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    if env.ReanimHubCleanup == cleanup then env.ReanimHubCleanup = nil end
    gui:Destroy()
end
env.ReanimHubCleanup = cleanup

return {Destroy = cleanup}
