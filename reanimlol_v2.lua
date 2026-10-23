-- Author: c1lown
-- reanimlol v10.3 (Novoline skin + Novoline-style Play / Live / Tricks tabs). The reanimation core is untouched.
-- reanimlol v10.1: v7 GUI + ragdoll-remote reanimation core (the game's own ragdoll remote breaks your joints on the server)
-- Body reanimation core is the one from your message__14_ file (unchanged). The GUI, keyframe
-- library, recorder and importer are from v4/v5. Saved data goes to the "Reanimlol" folder when your
-- executor supports writefile.

warn("=== reanimlol V10.4 by c1lown (Play / Live / Tricks) loaded ===")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer
assert(player, "Run reanimlol on the client")

local shared = getgenv and getgenv() or _G
if type(shared.ReanimlolCleanup) == "function" then pcall(shared.ReanimlolCleanup) end

----------------------------------------------------------------------
-- CORE: body reanimation
----------------------------------------------------------------------
local bodyReanim = (function()
-- Ragdoll-remote reanimation. The game's own ragdoll remote makes the SERVER swap your joints for loose
-- ragdoll constraints, which is what lets your client drive (and replicate) every limb. An invisible clone
-- is what you control and animate; the real, ragdolled body is snapped onto the clone every frame.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local S = {session = nil, starting = false, rev = 0, callback = nil}

-- returns remote, args, isLocal for this game (nil when none is known/found)
local function findRagdoll(enable)
  local rep, placeId = ReplicatedStorage, game.PlaceId
  if placeId == 15546218972 or placeId == 6884319169 then -- Mic Up and a sibling place
    local r = rep:WaitForChild("event_rag", 4)
    if r then return r, {"Ball"}, false end
  elseif placeId == 5991163185 then
    local ok, r = pcall(function() return rep.Remotes.Physics.Ragdoll end)
    if ok and r then return r, {}, false end
  elseif placeId == 5683833663 then
    local r = rep:WaitForChild("LocalRagdollEvent", 4)
    if r then return r, {enable}, true end
  elseif placeId == 86382196724726 or game.GameId == 10581310106 then
    local remotes = rep:WaitForChild("Remotes", 4)
    local toggle = remotes and remotes:WaitForChild("RagdollToggle", 4)
    if toggle then return toggle, {enable and "Ball" or false}, false end
    return nil
  end
  local function at(path)
    local cur = rep
    for part in path:gmatch("[^/]+") do
      cur = cur and cur:FindFirstChild(part)
    end
    return cur
  end
  for _, path in ipairs({"Ragdoll", "RagdollEvent", "event_rag", "Rag", "Ragdolled", "Remotes/Ragdoll",
      "Events/Ragdoll", "Remotes/Physics/Ragdoll", "RemoteEvents/Ragdoll", "RemoteEvents/RagdollEvent"}) do
    local r = at(path)
    if r then
      if r:IsA("BindableEvent") then return r, {enable}, true end
      if r:IsA("RemoteEvent") or r:IsA("RemoteFunction") then return r, {}, false end
    end
  end
  return nil
end

local function fire(remote, args, isLocal)
  if isLocal then remote:Fire(unpack(args))
  elseif remote:IsA("RemoteEvent") then remote:FireServer(unpack(args))
  else task.spawn(function() remote:InvokeServer(unpack(args)) end) end
end

local function cloneCharacter(model)
  local changed = {}
  local ok, clone = pcall(function()
    local objects = model:GetDescendants()
    table.insert(objects, model)
    for _, object in ipairs(objects) do
      if not object.Archivable then table.insert(changed, object); object.Archivable = true end
    end
    return model:Clone()
  end)
  for _, object in ipairs(changed) do pcall(function() object.Archivable = false end) end
  if not ok or not clone then return "Character clone failed." end
  for _, d in ipairs(clone:GetDescendants()) do
    if d:IsA("LuaSourceContainer") then d:Destroy() end
  end
  clone.Name = "ReanimlolBody"
  local humanoid = clone:FindFirstChildOfClass("Humanoid")
  if not humanoid then clone:Destroy(); return "Cloned character has no humanoid." end
  humanoid.RequiresNeck = false
  humanoid.BreakJointsOnDeath = false
  humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
  local ff = clone:FindFirstChildWhichIsA("ForceField")
  if ff then ff:Destroy() end
  return clone
end

local function setInvisible(model)
  for _, d in ipairs(model:GetDescendants()) do
    if d:IsA("BasePart") then d.Transparency = 1; d.CanCollide = false
    elseif d:IsA("Decal") or d:IsA("Texture") then d.Transparency = 1
    elseif d:IsA("BillboardGui") then d.Enabled = false end
  end
end

local stopReanimation
stopReanimation = function()
  S.rev += 1
  S.starting = false
  local s = S.session
  S.session = nil
  if not s then return end
  for key, c in pairs(s.conns) do s.conns[key] = nil; pcall(function() c:Disconnect() end) end
  local lastCF = s.copyRoot and s.copyRoot.Parent and s.copyRoot.CFrame or nil
  local gui = player:FindFirstChildWhichIsA("PlayerGui")
  local flipped = {}
  if gui then
    for _, g in ipairs(gui:GetChildren()) do
      if g:IsA("ScreenGui") and g.ResetOnSpawn then g.ResetOnSpawn = false; flipped[g] = true end
    end
  end
  if s.character.Parent then
    pcall(function() player.Character = s.character end)
    pcall(function() Workspace.CurrentCamera.CameraSubject = s.humanoid end)
  end
  pcall(function() s.humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, true) end)
  pcall(fire, s.remote, s.argsOff, s.isLocal) -- ragdoll off: server puts the joints back
  pcall(function() s.copy:Destroy() end)
  if lastCF then
    local root = s.root
    task.spawn(function()
      local t0 = os.clock()
      while os.clock() - t0 < 0.5 and root.Parent do
        task.wait()
        root.CFrame = lastCF
        root.AssemblyLinearVelocity = Vector3.zero
      end
    end)
  end
  task.delay(0.6, function()
    for g in pairs(flipped) do if g.Parent then g.ResetOnSpawn = true end end
  end)
  if S.callback then pcall(S.callback) end
end

local function startReanimation()
  if S.session then return end
  if S.starting then return "Reanim is starting." end
  S.rev += 1
  local rev = S.rev
  S.starting = true
  local ok, err = pcall(function()
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    assert(humanoid and root and humanoid.Health > 0, "Character not ready.")
    assert(not root.Anchored, "Character is anchored.")
    local remote, argsOn, isLocal = findRagdoll(true)
    assert(remote, "This game has no known ragdoll remote, so this core can't run here.")
    local _, argsOff = findRagdoll(false)
    argsOff = argsOff or argsOn
    assert(rev == S.rev, "Start cancelled.")
    local controls
    local scripts = player:FindFirstChild("PlayerScripts")
    local module = scripts and scripts:FindFirstChild("PlayerModule")
    if module and module:IsA("ModuleScript") then
      local loaded, value = pcall(function() return require(module):GetControls() end)
      if loaded and value and type(value.GetMoveVector) == "function" then controls = value end
    end
    local copy = cloneCharacter(character)
    assert(typeof(copy) == "Instance", tostring(copy))
    local copyHumanoid, copyRoot = copy:FindFirstChildOfClass("Humanoid"), copy:FindFirstChild("HumanoidRootPart")
    assert(copyHumanoid and copyRoot, "Cloned rig is incomplete.")
    local motors = false
    for _, d in ipairs(copy:GetDescendants()) do if d:IsA("Motor6D") then motors = true; break end end
    assert(motors, "This rig needs Motor6D joints.")
    for _, d in ipairs(copy:GetDescendants()) do
      if d:IsA("Tool") then d:Destroy() end
    end
    setInvisible(copy)
    copy.Parent = Workspace
    copyHumanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
    local s = {
      character = character, humanoid = humanoid, root = root, copy = copy, copyHumanoid = copyHumanoid,
      copyRoot = copyRoot, remote = remote, args = argsOn, argsOff = argsOff, isLocal = isLocal,
      conns = {}, links = {}, controls = controls, focused = true,
    }
    S.session = s
    for _, part in ipairs(character:GetChildren()) do
      local base = copy:FindFirstChild(part.Name)
      if part:IsA("BasePart") and base and base:IsA("BasePart") then
        s.links[#s.links + 1] = {part = part, base = base}
      end
    end
    -- swap control to the clone (keeping the game's GUIs from resetting)
    local gui = player:FindFirstChildWhichIsA("PlayerGui")
    local flipped = {}
    if gui then
      for _, g in ipairs(gui:GetChildren()) do
        if g:IsA("ScreenGui") and g.ResetOnSpawn then g.ResetOnSpawn = false; flipped[g] = true end
      end
    end
    player.Character = copy
    Workspace.CurrentCamera.CameraSubject = copyHumanoid
    task.delay(0.6, function() for g in pairs(flipped) do if g.Parent then g.ResetOnSpawn = true end end end)
    pcall(function() humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false) end)
    humanoid.Health = humanoid.MaxHealth
    pcall(function() copyHumanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false) end)
    fire(remote, argsOn, isLocal) -- server ragdolls the real body: joints become loose
    local function valid()
      return S.session == s and character.Parent and copy.Parent and humanoid.Parent == character
        and copyHumanoid.Parent == copy and copyRoot.Parent == copy and root.Parent == character
    end
    local function follow()
      for _, link in ipairs(s.links) do
        if link.part.Parent and link.base.Parent then
          link.part.CFrame = link.base.CFrame
          link.part.AssemblyLinearVelocity = Vector3.zero
          link.part.AssemblyAngularVelocity = Vector3.zero
        end
      end
    end
    local function listen(name, signal, callback)
      s.conns[name] = signal:Connect(function(...)
        if S.session ~= s then return end
        local good, problem = pcall(callback, ...)
        if not good then stopReanimation(); warn("Reanimlol reanim: " .. tostring(problem)) end
      end)
    end
    listen("died", humanoid.Died, stopReanimation)
    listen("clone_died", copyHumanoid.Died, stopReanimation)
    listen("clone_removed", copy.AncestryChanged, function() if not copy:IsDescendantOf(game) then stopReanimation() end end)
    listen("real_removed", character.AncestryChanged, function() if not character:IsDescendantOf(game) then stopReanimation() end end)
    listen("focus", UserInputService.WindowFocused, function() s.focused = true end)
    listen("blur", UserInputService.WindowFocusReleased, function() s.focused = false; copyHumanoid:Move(Vector3.zero) end)
    listen("jump", UserInputService.JumpRequest, function()
      if s.focused and not UserInputService:GetFocusedTextBox() then copyHumanoid.Jump = true end
    end)
    listen("camera", Workspace:GetPropertyChangedSignal("CurrentCamera"), function()
      Workspace.CurrentCamera.CameraSubject = copyHumanoid
    end)
    listen("step", game:GetService("RunService").PreSimulation, function()
      if not valid() then stopReanimation(); return end
      if humanoid.Health < humanoid.MaxHealth then humanoid.Health = humanoid.MaxHealth end
      if copyHumanoid.Health < copyHumanoid.MaxHealth then copyHumanoid.Health = copyHumanoid.MaxHealth end
      local move, relative = Vector3.zero, false
      if s.focused and not UserInputService:GetFocusedTextBox() then
        if s.controls then
          local got, value = pcall(function() return s.controls:GetMoveVector() end)
          if got and typeof(value) == "Vector3" then move, relative = value, true else s.controls = nil end
        end
        if not s.controls then move = copyHumanoid.MoveDirection end
      end
      if move.Magnitude ~= move.Magnitude or move.Magnitude == math.huge then move = Vector3.zero end
      if move.Magnitude > 1 then move = move.Unit end
      copyHumanoid:Move(move, relative)
      follow()
    end)
    listen("beat", game:GetService("RunService").Heartbeat, function()
      if not valid() then stopReanimation(); return end
      follow()
    end)
  end)
  if rev ~= S.rev then return "Start cancelled." end
  S.starting = false
  if not ok then
    stopReanimation()
    return (tostring(err):gsub("^.-:%d+: ", ""))
  end
end

return {
 Start = startReanimation, Stop = stopReanimation,
 Get = function() local s = S.session; return s and s.copy.Parent and s.copy or nil end,
 OnStopped = function(callback) S.callback = callback end,
}
end)()

----------------------------------------------------------------------
-- Shared state, persistence
----------------------------------------------------------------------
local destroyed = false
local connections = {}
local function connect(signal, fn)
    local c = signal:Connect(fn)
    connections[#connections + 1] = c
    return c
end

local ROOT = "Reanimlol"
local DATA_FILE = ROOT .. "/data.json"
local hasFS = type(writefile) == "function" and type(readfile) == "function"
    and type(isfile) == "function" and type(makefolder) == "function" and type(isfolder) == "function"
local function ensureFolder(path)
    if hasFS then pcall(function() if not isfolder(path) then makefolder(path) end end) end
end

local settings = {
    speed = 1, loop = true, stopOnMove = false, walkSync = true, blend = 0.15, recordRate = 20,
    noclip = true, keyToggle = "RightControl", keyGui = "RightShift", keyStop = "X",
    keySpeedDown = "Minus", keySpeedUp = "Equals", keySpeedReset = "Zero",
    keyPause = "Y", keyRewind = "U", keyReverse = "I", keyDrive = "LeftAlt",
}
local data = {favorites = {}, custom = {}, states = {}, binds = {}, settings = settings}

do -- load
    if hasFS then
        local ok, raw = pcall(function() if isfile(DATA_FILE) then return readfile(DATA_FILE) end end)
        if ok and raw then
            local ok2, decoded = pcall(function() return HttpService:JSONDecode(raw) end)
            if ok2 and type(decoded) == "table" then
                for _, k in ipairs({"favorites", "custom", "states", "binds"}) do
                    if type(decoded[k]) == "table" then data[k] = decoded[k] end
                end
                if type(decoded.settings) == "table" then
                    for k, v in pairs(decoded.settings) do
                        if type(settings[k]) == type(v) then settings[k] = v end
                    end
                end
            end
        end
    end
end
settings.stopOnMove = false

local function saveData()
    if not hasFS then return end
    pcall(function()
        ensureFolder(ROOT)
        writefile(DATA_FILE, HttpService:JSONEncode(data))
    end)
end
local saveToken = 0
local function saveSoon()
    saveToken += 1
    local t = saveToken
    task.delay(1, function() if t == saveToken then saveData() end end)
end

----------------------------------------------------------------------
-- Library data: everything is built from keyframes (no animation assets, IDs or downloads)
----------------------------------------------------------------------
local STATES = {"idle", "walk", "run", "jump", "fall", "climb", "swim"}
local function cap(s) return s:sub(1, 1):upper() .. s:sub(2) end

-- Keyframe sampling ----------------------------------------------------
local styles = {Linear = Enum.EasingStyle.Linear, Sine = Enum.EasingStyle.Sine, Quad = Enum.EasingStyle.Quad,
    Cubic = Enum.EasingStyle.Cubic, CubicV2 = Enum.EasingStyle.Cubic, Quart = Enum.EasingStyle.Quart,
    Quint = Enum.EasingStyle.Quint, Back = Enum.EasingStyle.Back, Elastic = Enum.EasingStyle.Elastic,
    Bounce = Enum.EasingStyle.Bounce}
local directions = {In = Enum.EasingDirection.In, Out = Enum.EasingDirection.Out, InOut = Enum.EasingDirection.InOut}

local function sample(curve, time, duration, looped)
    local n = #curve
    if n == 1 then return curve[1].value end
    local a, b
    for i = n, 1, -1 do
        if curve[i].time <= time then a = curve[i]; b = curve[i + 1]; break end
    end
    local at, bt
    if not a then
        if not looped then return curve[1].value end
        a, b = curve[n], curve[1]
        at, bt = a.time - duration, b.time
    elseif not b then
        if not looped then return a.value end
        b = curve[1]
        at, bt = a.time, b.time + duration
    else at, bt = a.time, b.time end
    local alpha = bt > at and math.clamp((time - at) / (bt - at), 0, 1) or 1
    if a.style == "Constant" then alpha = 0
    else alpha = TweenService:GetValue(alpha, styles[a.style] or Enum.EasingStyle.Linear,
        directions[a.direction] or Enum.EasingDirection.InOut) end
    return a.value:Lerp(b.value, alpha)
end

-- Pose keyframes -------------------------------------------------------
-- A clip is {duration, loop, hold, keys = {{t, pose, style, dir}}}. A pose maps joint names to
-- {x, y, z} rotation in degrees (+ optional dx, dy, dz in studs). Rotations are relative to the rest
-- pose, in the parent part's axes (x = right, y = up, z = back). That makes one clip work on R6 and R15:
-- each joint is turned into a Motor6D Transform using that rig's own C0 when the clip is baked.
local JOINTS = {Hips = true, Torso = true, Head = true, LArm = true, RArm = true, LForearm = true,
    RForearm = true, LLeg = true, RLeg = true, LShin = true, RShin = true}
local PARTS = {
    R15 = {Hips = "LowerTorso", Torso = "UpperTorso", Head = "Head", LArm = "LeftUpperArm", RArm = "RightUpperArm",
        LForearm = "LeftLowerArm", RForearm = "RightLowerArm", LLeg = "LeftUpperLeg", RLeg = "RightUpperLeg",
        LShin = "LeftLowerLeg", RShin = "RightLowerLeg"},
    R6 = {Hips = "Torso", Torso = "Torso", Head = "Head", LArm = "Left Arm", RArm = "Right Arm",
        LLeg = "Left Leg", RLeg = "Right Leg"}, -- R6 has no waist, elbows or knees
}
local ZERO = {0, 0, 0, 0, 0, 0}

local function poseTransforms(pose, rig, motors)
    local out, map = {}, PARTS[rig] or PARTS.R15
    for joint, v in pairs(pose) do
        local part = map[joint]
        local motor = part and motors[part]
        if motor then
            local rc = motor.C0.Rotation
            local delta = CFrame.Angles(math.rad(v[1] or 0), math.rad(v[2] or 0), math.rad(v[3] or 0))
            local t = rc:Inverse() * delta * rc
            if (v[4] or 0) ~= 0 or (v[5] or 0) ~= 0 or (v[6] or 0) ~= 0 then
                t = CFrame.new(rc:VectorToObjectSpace(Vector3.new(v[4] or 0, v[5] or 0, v[6] or 0))) * t
            end
            out[part] = out[part] and (out[part] * t) or t
        end
    end
    return out
end

local function bakeClip(def, rig, motors)
    local used, last = {}, 0
    for _, k in ipairs(def.keys) do
        last = math.max(last, k.t)
        for joint in pairs(k.pose) do used[joint] = true end
    end
    local curves = {}
    for _, k in ipairs(def.keys) do
        local full = {}
        for joint in pairs(used) do full[joint] = k.pose[joint] or ZERO end
        for part, cf in pairs(poseTransforms(full, rig, motors)) do
            local curve = curves[part]
            if not curve then curve = {}; curves[part] = curve end
            curve[#curve + 1] = {time = k.t, value = cf, style = k.style or "Sine", direction = k.dir or "InOut"}
        end
    end
    return {curves = curves, duration = math.max(def.duration or last, last, 0.05), looped = def.loop ~= false,
        hold = def.hold == true, rig = rig}
end

local function parseDef(t)
    if type(t) ~= "table" or type(t.keys) ~= "table" or #t.keys < 1 then return nil, "Need a keys list" end
    local keys = {}
    for _, k in ipairs(t.keys) do
        if type(k) ~= "table" or type(k.t) ~= "number" or type(k.pose) ~= "table" then
            return nil, "Each key needs t and pose"
        end
        local pose = {}
        for joint, v in pairs(k.pose) do
            if not JOINTS[joint] then return nil, "Unknown joint " .. tostring(joint) end
            if type(v) ~= "table" then return nil, "Bad pose for " .. joint end
            local arr = {}
            for i = 1, 6 do arr[i] = tonumber(v[i]) or 0 end
            pose[joint] = arr
        end
        keys[#keys + 1] = {t = math.max(k.t, 0), pose = pose,
            style = (styles[k.style] or k.style == "Constant") and k.style or "Sine",
            dir = directions[k.dir] and k.dir or "InOut"}
    end
    table.sort(keys, function(a, b) return a.t < b.t end)
    local merged = {}
    for _, k in ipairs(keys) do
        if #merged > 0 and merged[#merged].t == k.t then merged[#merged] = k else merged[#merged + 1] = k end
    end
    local duration = tonumber(t.duration) or merged[#merged].t
    duration = math.max(duration, merged[#merged].t)
    if duration <= 0 then return nil, "Clip needs a duration" end
    return {duration = duration, loop = t.loop ~= false, hold = t.hold == true, keys = merged}
end

-- Parses raw keyframe tables exported as Lua text, e.g.
--   return { ["name"] = { { Time = 0.0, Data = { ["Head"] = CFrame.new(...12 numbers...), ... } }, ... } }
-- Read as plain text (nothing is executed). Each CFrame is the Motor6D Transform of that part.
local function parseLuaClips(text)
    local out, heads = {}, {}
    for pos, name in text:gmatch('()%["([^"]+)"%]%s*=%s*{%s*{%s*Time') do heads[#heads + 1] = {pos = pos, name = name} end
    if #heads == 0 then heads[1] = {pos = 1, name = "Imported"} end
    for i, head in ipairs(heads) do
        local body = text:sub(head.pos, heads[i + 1] and heads[i + 1].pos - 1 or #text)
        local times = {}
        for pos, t in body:gmatch("()Time%s*=%s*([%-%d%.eE]+)") do
            if tonumber(t) then times[#times + 1] = {pos = pos, t = tonumber(t)} end
        end
        local curves, duration = {}, 0
        for j, frame in ipairs(times) do
            local seg = body:sub(frame.pos, times[j + 1] and times[j + 1].pos - 1 or #body)
            for part, nums in seg:gmatch('%["([^"]+)"%]%s*=%s*CFrame%.new%(([^%)]*)%)') do
                local c = {}
                for n in nums:gmatch("[^,%s]+") do c[#c + 1] = tonumber(n) end
                if #c == 12 then
                    local curve = curves[part]
                    if not curve then curve = {}; curves[part] = curve end
                    curve[#curve + 1] = {time = frame.t, value = CFrame.new(table.unpack(c)), style = "Linear", direction = "InOut"}
                end
            end
            duration = math.max(duration, frame.t)
        end
        if duration > 0 and next(curves) then
            local rig = (curves.UpperTorso or curves.LowerTorso) and "R15" or (curves.Torso and "R6") or nil
            out[#out + 1] = {name = head.name, clip = {curves = curves, duration = duration, looped = true, rig = rig}}
        end
    end
    return out
end

-- True when the text looks like a Lua keyframe export (Time = ... CFrame.new(...)) rather than JSON
local function looksLikeLuaKeyframes(text)
    return text:find("CFrame.new", 1, true) ~= nil and text:find("Time%s*=") ~= nil
end

-- Authoring helpers ----------------------------------------------------
local function K(t, pose, style, dir) return {t = t, pose = pose, style = style, dir = dir} end
-- Samples fn(angle 0..2pi) n times across one loop
local function cycle(duration, n, fn)
    local keys = {}
    for i = 0, n do
        keys[#keys + 1] = {t = duration * i / n, pose = fn(i / n * 2 * math.pi), style = "Linear", dir = "InOut"}
    end
    return {duration = duration, loop = true, keys = keys}
end

local LIB = {}
local function add(cat, sub, name, def)
    LIB[#LIB + 1] = {key = "b:" .. cat .. "/" .. sub .. "/" .. name, name = name, cat = cat, sub = sub, def = def}
    return LIB[#LIB].key
end

-- Emotes ---------------------------------------------------------------
local WAVE_HEAD = {0, 0, -6}
add("Emotes", "Greetings", "Wave", {duration = 2, loop = false, keys = {
    K(0,    {RArm = {0, 0, 4}}),
    K(0.35, {RArm = {0, 0, 112}, RForearm = {0, 0, 66}, Head = WAVE_HEAD}),
    K(0.6,  {RArm = {0, 0, 122}, RForearm = {0, 0, 100}, Head = WAVE_HEAD}),
    K(0.85, {RArm = {0, 0, 102}, RForearm = {0, 0, 36}, Head = WAVE_HEAD}),
    K(1.1,  {RArm = {0, 0, 122}, RForearm = {0, 0, 100}, Head = WAVE_HEAD}),
    K(1.35, {RArm = {0, 0, 102}, RForearm = {0, 0, 36}, Head = WAVE_HEAD}),
    K(1.6,  {RArm = {0, 0, 114}, RForearm = {0, 0, 66}, Head = WAVE_HEAD}),
    K(2,    {RArm = {0, 0, 4}}),
}})
add("Emotes", "Greetings", "Bow", {duration = 2.4, loop = false, keys = {
    K(0, {}),
    K(0.7, {Torso = {-50, 0, 0}, Head = {-12, 0, 0}, RArm = {-8, 0, 4}, LArm = {-8, 0, -4}}, "Quad", "Out"),
    K(1.5, {Torso = {-50, 0, 0}, Head = {-12, 0, 0}, RArm = {-8, 0, 4}, LArm = {-8, 0, -4}}),
    K(2.4, {}),
}})
add("Emotes", "Greetings", "Point", {duration = 1.8, loop = false, keys = {
    K(0, {}),
    K(0.3, {RArm = {88, 0, 4}, Torso = {0, -10, 0}, Head = {0, -10, 0}}, "Quad", "Out"),
    K(1.4, {RArm = {88, 0, 4}, Torso = {0, -10, 0}, Head = {0, -10, 0}}),
    K(1.8, {}),
}})
add("Emotes", "Reactions", "Cheer", {duration = 0.6, loop = true, keys = {
    K(0,   {RArm = {0, 0, 150}, LArm = {0, 0, -150}, Head = {6, 0, 0}}),
    K(0.3, {RArm = {0, 0, 172}, LArm = {0, 0, -172}, Head = {14, 0, 0}, Hips = {0, 0, 0, 0, 0.22, 0}, RLeg = {-10, 0, 0}, LLeg = {-10, 0, 0}}),
    K(0.6, {RArm = {0, 0, 150}, LArm = {0, 0, -150}, Head = {6, 0, 0}}),
}})
add("Emotes", "Reactions", "Laugh", {duration = 0.5, loop = true, keys = {
    K(0,    {Torso = {-8, 0, 0}, Head = {20, 0, 0}, RArm = {25, 0, 10}, LArm = {25, 0, -10}, RForearm = {70, 0, 0}, LForearm = {70, 0, 0}}),
    K(0.25, {Torso = {-18, 0, 0}, Head = {28, 0, 0}, RArm = {25, 0, 10}, LArm = {25, 0, -10}, RForearm = {70, 0, 0}, LForearm = {70, 0, 0}}),
    K(0.5,  {Torso = {-8, 0, 0}, Head = {20, 0, 0}, RArm = {25, 0, 10}, LArm = {25, 0, -10}, RForearm = {70, 0, 0}, LForearm = {70, 0, 0}}),
}})
add("Emotes", "Reactions", "Shrug", {duration = 1.6, loop = false, keys = {
    K(0, {}),
    K(0.3, {RArm = {20, 0, 22}, LArm = {20, 0, -22}, RForearm = {0, 0, 55}, LForearm = {0, 0, -55}, Head = {0, 0, 8}}, "Quad", "Out"),
    K(1.2, {RArm = {20, 0, 22}, LArm = {20, 0, -22}, RForearm = {0, 0, 55}, LForearm = {0, 0, -55}, Head = {0, 0, 8}}),
    K(1.6, {}),
}})
add("Emotes", "Reactions", "Clap", {duration = 0.5, loop = true, keys = {
    K(0,    {RArm = {50, 0, -42}, LArm = {50, 0, 42}, RForearm = {40, 0, -25}, LForearm = {40, 0, 25}}),
    K(0.25, {RArm = {50, 0, -20}, LArm = {50, 0, 20}, RForearm = {40, 0, -8}, LForearm = {40, 0, 8}}),
    K(0.5,  {RArm = {50, 0, -42}, LArm = {50, 0, 42}, RForearm = {40, 0, -25}, LForearm = {40, 0, 25}}),
}})
add("Emotes", "Poses", "T-Pose", {duration = 0.6, loop = false, hold = true, keys = {
    K(0, {}), K(0.25, {RArm = {0, 0, 90}, LArm = {0, 0, -90}}, "Quad", "Out"), K(0.6, {RArm = {0, 0, 90}, LArm = {0, 0, -90}}),
}})
add("Emotes", "Poses", "Arms Up", {duration = 0.6, loop = false, hold = true, keys = {
    K(0, {}), K(0.3, {RArm = {0, 0, 170}, LArm = {0, 0, -170}, Head = {8, 0, 0}}, "Quad", "Out"),
    K(0.6, {RArm = {0, 0, 170}, LArm = {0, 0, -170}, Head = {8, 0, 0}}),
}})
add("Emotes", "Poses", "Zombie Arms", {duration = 0.6, loop = false, hold = true, keys = {
    K(0, {}), K(0.3, {RArm = {88, 0, 3}, LArm = {88, 0, -3}, Head = {0, 0, 8}, Torso = {-8, 0, 0}}, "Quad", "Out"),
    K(0.6, {RArm = {88, 0, 3}, LArm = {88, 0, -3}, Head = {0, 0, 8}, Torso = {-8, 0, 0}}),
}})

-- Dances ---------------------------------------------------------------
add("Dances", "Classic", "Bounce", cycle(0.8, 8, function(a)
    local s = math.sin(a)
    return {Hips = {0, 0, s * 4, 0, 0.12 * s * s, 0}, RArm = {s * 30, 0, 20}, LArm = {-s * 30, 0, -20},
        RForearm = {50, 0, 0}, LForearm = {50, 0, 0}, RShin = {-10 * (1 - math.cos(2 * a)), 0, 0},
        LShin = {-10 * (1 - math.cos(2 * a)), 0, 0}}
end))
add("Dances", "Classic", "Disco", cycle(1.2, 12, function(a)
    local s = math.sin(a)
    return {RArm = {0, 0, 30 + 120 * (0.5 + 0.5 * s)}, LArm = {0, 0, -(30 + 120 * (0.5 - 0.5 * s))},
        Hips = {0, 0, s * 8}, Torso = {0, 0, -s * 6}, Head = {0, 0, s * 5},
        RLeg = {0, 0, 8}, LLeg = {0, 0, -8}, RShin = {-10 * (0.5 + 0.5 * math.cos(2 * a)), 0, 0},
        LShin = {-10 * (0.5 - 0.5 * math.cos(2 * a)), 0, 0}}
end))
add("Dances", "Classic", "Sway", cycle(2.4, 8, function(a)
    local s = math.sin(a)
    return {Hips = {0, 0, s * 6, s * 0.12, 0, 0}, Torso = {0, 0, -s * 8}, Head = {0, 0, s * 6},
        RArm = {0, 0, 35 + s * 15}, LArm = {0, 0, -(35 - s * 15)}, RForearm = {30, 0, 0}, LForearm = {30, 0, 0}}
end))
add("Dances", "Classic", "Spin", {duration = 1.2, loop = true, keys = {
    K(0,   {Hips = {0, 0, 0}, RArm = {0, 0, 70}, LArm = {0, 0, -70}}, "Linear"),
    K(0.3, {Hips = {0, 90, 0}, RArm = {0, 0, 70}, LArm = {0, 0, -70}}, "Linear"),
    K(0.6, {Hips = {0, 180, 0}, RArm = {0, 0, 70}, LArm = {0, 0, -70}}, "Linear"),
    K(0.9, {Hips = {0, 270, 0}, RArm = {0, 0, 70}, LArm = {0, 0, -70}}, "Linear"),
    K(1.2, {Hips = {0, 360, 0}, RArm = {0, 0, 70}, LArm = {0, 0, -70}}, "Linear"),
}})

-- Fallback movement animations, used only for a state you haven't assigned a clip to (the cloned body has
-- no Animate script, so without these it slides around stiff). Assigning a clip overrides them.
local function gait(duration, swing, knee, arm)
    return cycle(duration, 12, function(a)
        local c = math.cos(a)
        return {RLeg = {swing * math.sin(a), 0, 0}, LLeg = {-swing * math.sin(a), 0, 0},
            RShin = {-knee * math.max(0, c), 0, 0}, LShin = {-knee * math.max(0, -c), 0, 0},
            RArm = {-arm * math.sin(a), 0, 0}, LArm = {arm * math.sin(a), 0, 0},
            Hips = {0, 0, 0, 0, 0.06 * math.abs(math.sin(a)), 0}}
    end)
end
local DEFAULT_STATES = {
    walk = {def = gait(0.8, 35, 40, 30)},
    run = {def = gait(0.5, 55, 70, 55)},
    jump = {def = {duration = 0.4, loop = true, keys = {
        K(0, {RArm = {0, 0, 140}, LArm = {0, 0, -140}, RLeg = {-10, 0, 0}, LLeg = {10, 0, 0}}),
        K(0.4, {RArm = {0, 0, 140}, LArm = {0, 0, -140}, RLeg = {-10, 0, 0}, LLeg = {10, 0, 0}})}}},
    fall = {def = {duration = 0.4, loop = true, keys = {
        K(0, {RArm = {0, 0, 100}, LArm = {0, 0, -100}, RLeg = {8, 0, 6}, LLeg = {-8, 0, -6}}),
        K(0.4, {RArm = {0, 0, 100}, LArm = {0, 0, -100}, RLeg = {8, 0, 6}, LLeg = {-8, 0, -6}})}}},
}

-- Entries --------------------------------------------------------------
local recorded = {} -- recorded entries {key,name,cat,sub,recorded=true,clip=,path=}
local fileClips = {} -- keyframe files from Reanimlol/keyframes

-- drop leftovers from older versions (animation IDs)
for s, v in pairs(data.states) do
    if type(v) ~= "table" or not (v.lib or v.rec) or (v.lib and tostring(v.lib):sub(1, 11) == "b:Movement/") then data.states[s] = nil end
end
for i = #data.custom, 1, -1 do
    if type(data.custom[i]) ~= "table" or not (data.custom[i].def or data.custom[i].clipData) then table.remove(data.custom, i) end
end

local deserializeClip -- assigned in the recording helpers below
local clipCache = setmetatable({}, {__mode = "k"})
local function customToEntry(c)
    local e = {key = "c:" .. c.cat .. "/" .. c.sub .. "/" .. c.name, name = c.name, cat = c.cat, sub = c.sub,
        custom = true, src = c, def = c.def}
    if c.clipData then
        local clip = clipCache[c]
        if not clip then clip = deserializeClip(c.clipData); clipCache[c] = clip end
        e.clip = clip
    end
    return e
end
local function getEntries()
    local out = {}
    for _, e in ipairs(LIB) do out[#out + 1] = e end
    for _, c in ipairs(data.custom) do out[#out + 1] = customToEntry(c) end
    for _, e in ipairs(fileClips) do out[#out + 1] = e end
    for _, e in ipairs(recorded) do out[#out + 1] = e end
    return out
end
local function findEntry(key)
    for _, e in ipairs(getEntries()) do if e.key == key then return e end end
end
local function playerRig()
    local ch = player.Character
    local h = ch and ch:FindFirstChildOfClass("Humanoid")
    return (h and h.RigType == Enum.HumanoidRigType.R6) and "R6" or "R15"
end

----------------------------------------------------------------------
-- GUI skeleton (needed by engine for status text)
----------------------------------------------------------------------
local C = {
    bg = Color3.fromRGB(30, 6, 9), field = Color3.fromRGB(66, 18, 24), sel = Color3.fromRGB(128, 28, 38),
    text = Color3.fromRGB(255, 244, 244), dim = Color3.fromRGB(218, 150, 156),
    accent = Color3.fromRGB(255, 48, 64), off = Color3.fromRGB(104, 34, 40), list = Color3.fromRGB(38, 8, 12),
    stroke = Color3.fromRGB(220, 56, 68), div = Color3.fromRGB(120, 38, 46), card = Color3.fromRGB(78, 20, 27),
    green = Color3.fromRGB(80, 210, 100), gold = Color3.fromRGB(255, 200, 40), ink = Color3.fromRGB(255, 255, 255),
    danger = Color3.fromRGB(255, 130, 120),
}
local EASE = TweenInfo.new(.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local function tween(o, props, info)
    local t = TweenService:Create(o, info or EASE, props)
    t:Play()
    return t
end
-- setBase: changes a button's resting colour (hover effects return to this colour)
local function setBase(o, color)
    o:SetAttribute("base", color)
    tween(o, {BackgroundColor3 = color})
end
local function hoverable(o)
    o:SetAttribute("base", o.BackgroundColor3)
    o.MouseEnter:Connect(function()
        tween(o, {BackgroundColor3 = o:GetAttribute("base"):Lerp(Color3.new(1, 1, 1), .1)}, TweenInfo.new(.1))
    end)
    o.MouseLeave:Connect(function() tween(o, {BackgroundColor3 = o:GetAttribute("base")}, TweenInfo.new(.15)) end)
    o.MouseButton1Down:Connect(function()
        tween(o, {BackgroundColor3 = o:GetAttribute("base"):Lerp(Color3.new(0, 0, 0), .2)}, TweenInfo.new(.06))
    end)
    o.MouseButton1Up:Connect(function()
        tween(o, {BackgroundColor3 = o:GetAttribute("base"):Lerp(Color3.new(1, 1, 1), .1)}, TweenInfo.new(.1))
    end)
end
local function T(class, props, parent)
    local o = Instance.new(class)
    if o:IsA("GuiObject") then o.BorderSizePixel = 0 end
    if class == "TextLabel" or class == "TextButton" or class == "TextBox" then
        o.Font = (class == "TextLabel") and Enum.Font.GothamMedium or Enum.Font.GothamBold; o.TextSize = 13; o.TextColor3 = C.text
        if class == "TextLabel" then o.BackgroundTransparency = 1 else o.BackgroundColor3 = C.field end
        if class == "TextButton" then o.AutoButtonColor = false end
        if class == "TextBox" then o.ClearTextOnFocus = false; o.PlaceholderColor3 = Color3.fromRGB(118, 118, 124) end
    end
    for k, v in pairs(props) do o[k] = v end
    o.Parent = parent
    return o
end
local function corner(o, r)
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = o
end
local function button(parent, text, x, y, w, h, cb)
    local b = T("TextButton", {Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), Text = text, TextSize = 12}, parent)
    corner(b, 10)
    hoverable(b)
    if cb then b.Activated:Connect(cb) end
    return b
end
local function label(parent, text, x, y, w, h, extra)
    local props = {Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), Text = text,
        TextXAlignment = Enum.TextXAlignment.Left}
    for k, v in pairs(extra or {}) do props[k] = v end
    return T("TextLabel", props, parent)
end
local function box(parent, placeholder, x, y, w, h)
    local b = T("TextBox", {Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), Text = "",
        PlaceholderText = placeholder, TextXAlignment = Enum.TextXAlignment.Left}, parent)
    corner(b, 10)
    T("UIPadding", {PaddingLeft = UDim.new(0, 12)}, b)
    b.Font = Enum.Font.GothamSemibold
    b.BackgroundColor3, b.BackgroundTransparency = C.card, .24
    b.PlaceholderColor3 = C.dim
    local st = Instance.new("UIStroke")
    st.Color, st.Thickness, st.Transparency, st.ApplyStrokeMode = C.div, 1, .5, Enum.ApplyStrokeMode.Border
    st.Parent = b
    b.Focused:Connect(function() tween(st, {Color = C.dim, Transparency = .2}, TweenInfo.new(.15)) end)
    b.FocusLost:Connect(function() tween(st, {Color = C.div, Transparency = .5}, TweenInfo.new(.2)) end)
    return b
end
local function switch(parent, pos, initial, onChange)
    local b = T("TextButton", {Position = UDim2.new(pos.X.Scale, pos.X.Offset - 6, pos.Y.Scale, pos.Y.Offset - 1),
        Size = UDim2.fromOffset(52, 26), Text = "", BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = .86}, parent)
    corner(b, 13)
    local fill = T("Frame", {Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.accent, BackgroundTransparency = 1}, b)
    corner(fill, 13)
    local knob = T("Frame", {AnchorPoint = Vector2.new(.5, .5), Size = UDim2.fromOffset(32, 22), Position = UDim2.new(0, 18, .5, 0),
        BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 2}, b)
    corner(knob, 11)
    local api = {value = initial}
    function api.set(v)
        api.value = v
        tween(fill, {BackgroundTransparency = v and .05 or 1}, TweenInfo.new(.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
        tween(knob, {Position = UDim2.new(0, v and 34 or 18, .5, 0)}, TweenInfo.new(.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out))
    end
    b.Activated:Connect(function()
        api.set(not api.value)
        if onChange then onChange(api.value) end
    end)
    api.set(initial)
    return api
end
local function slider(parent, x, y, w, min, max, value, onChange)
    local bar = T("Frame", {Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, 14), BackgroundTransparency = 1}, parent)
    local track = T("Frame", {AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(0, 0, .5, 0), Size = UDim2.new(1, 0, 0, 6),
        BackgroundColor3 = C.off}, bar)
    corner(track, 3)
    local fill = T("Frame", {Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.accent}, track)
    corner(fill, 3)
    local knob = T("Frame", {AnchorPoint = Vector2.new(.5, .5), Size = UDim2.fromOffset(14, 14), Position = UDim2.new(0, 0, .5, 0),
        BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 2}, bar)
    corner(knob, 7)
    local api, dragging = {}, false
    function api.set(v, fire)
        v = math.clamp(v, min, max)
        local p = (v - min) / (max - min)
        fill.Size = UDim2.fromScale(p, 1)
        knob.Position = UDim2.new(p, 0, .5, 0)
        api.value = v
        if fire then onChange(v) end
    end
    local function fromX(px)
        api.set(min + (max - min) * math.clamp((px - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1), true)
    end
    bar.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true; fromX(i.Position.X)
        end
    end)
    connect(UserInputService.InputChanged, function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            fromX(i.Position.X)
        end
    end)
    connect(UserInputService.InputEnded, function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)
    api.set(value, false)
    return api
end

local gui = Instance.new("ScreenGui")
gui.Name, gui.ResetOnSpawn = "Reanimlol", false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")
local PANEL_W, PANEL_H, BAR_H = 392, 534, 44
local PANEL_ALPHA = 0.22
local panel = T("Frame", {Size = UDim2.fromOffset(PANEL_W, PANEL_H), Position = UDim2.new(0.5, -PANEL_W / 2, 0.5, -PANEL_H / 2),
    BackgroundColor3 = Color3.new(1, 1, 1), Active = true}, gui)
corner(panel, 14)
do
    local stroke = Instance.new("UIStroke")
    stroke.Color, stroke.Thickness, stroke.Transparency, stroke.ApplyStrokeMode = C.stroke, 1, .45, Enum.ApplyStrokeMode.Border
    stroke.Parent = panel
    local grad = Instance.new("UIGradient")
    grad.Rotation = 90
    grad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(110, 14, 24)),
        ColorSequenceKeypoint.new(0.45, Color3.fromRGB(58, 8, 14)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(24, 3, 6)),
    })
    grad.Parent = panel
    pcall(function()
        local glow = Instance.new("UIShadow")
        glow.Name, glow.Color, glow.BlurRadius, glow.Offset, glow.Transparency = "DarkGlow", Color3.new(0, 0, 0), UDim.new(0, 26), UDim2.fromOffset(0, 10), .45
        glow.Parent = panel
    end)
end
local panelScale = Instance.new("UIScale")
panelScale.Scale = .9
panelScale.Parent = panel
panel.BackgroundTransparency = 1
tween(panelScale, {Scale = 1}, TweenInfo.new(.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
tween(panel, {BackgroundTransparency = PANEL_ALPHA}, TweenInfo.new(.3))
local dragBar = T("Frame", {Size = UDim2.new(1, 0, 0, BAR_H), BackgroundTransparency = 1}, panel)
local title = label(dragBar, "reanimlol", 18, 0, 200, BAR_H, {Font = Enum.Font.GothamBold, TextSize = 18,
    TextTruncate = Enum.TextTruncate.AtEnd})
local rigLabel = label(dragBar, "", 226, 0, 52, BAR_H, {TextColor3 = C.dim, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right})
do
    local dragging, dragStart, startPos = false
    dragBar.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging, dragStart, startPos = true, i.Position, panel.Position
        end
    end)
    connect(UserInputService.InputChanged, function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - dragStart
            panel.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    connect(UserInputService.InputEnded, function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)
end

local statusToken = 0
local function setStatus(text, sticky)
    statusToken += 1
    local t = statusToken
    title.Text = text
    if not sticky and text ~= "reanimlol" then
        task.delay(3, function() if t == statusToken and not destroyed then title.Text = "reanimlol" end end)
    end
end

local turnOn, turnOff, playEntry, stopEmote
-- window buttons: minimize (collapses to the title bar) and close, round like Novoline's
local function barButton(rightOffset, glyph, cb)
    local b = T("TextButton", {Size = UDim2.fromOffset(28, 28), Position = UDim2.new(1, -rightOffset - 28, 0.5, -14), Text = glyph,
        TextSize = 15, TextTransparency = .35, BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, ZIndex = 5}, panel)
    corner(b, 14)
    b.MouseEnter:Connect(function() tween(b, {BackgroundTransparency = .9, TextTransparency = 0}, TweenInfo.new(.15)) end)
    b.MouseLeave:Connect(function() tween(b, {BackgroundTransparency = 1, TextTransparency = .35}, TweenInfo.new(.2)) end)
    b.Activated:Connect(cb)
    return b
end
local closeBtn = barButton(14, "✕", function() if shared.ReanimlolCleanup then shared.ReanimlolCleanup() end end)
local minimized = false
barButton(14 + 28 + 4, "–", function()
    minimized = not minimized
    panel.ClipsDescendants = true
    tween(panel, {Size = UDim2.fromOffset(PANEL_W, minimized and BAR_H or PANEL_H)}, TweenInfo.new(.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out))
    if not minimized then task.delay(.4, function() if not destroyed and not minimized then panel.ClipsDescendants = false end end) end
end)

-- status chip + Reanimate button (replaces the old on/off switch; same set() API)
local statusDot = T("Frame", {Position = UDim2.fromOffset(28, 54 + 13), Size = UDim2.fromOffset(6, 6), BackgroundColor3 = C.div}, panel)
corner(statusDot, 3)
local statusLbl = label(panel, "Status: Idle", 44, 54, 190, 32, {Font = Enum.Font.GothamSemibold, TextColor3 = C.dim})
local reanimBtn = T("TextButton", {Position = UDim2.fromOffset(PANEL_W - 18 - 120, 54), Size = UDim2.fromOffset(120, 32), Text = "Reanimate",
    Font = Enum.Font.GothamBold, BackgroundColor3 = C.card, BackgroundTransparency = .6}, panel)
corner(reanimBtn, 10)
reanimBtn.MouseEnter:Connect(function() tween(reanimBtn, {BackgroundTransparency = .45}, TweenInfo.new(.22, Enum.EasingStyle.Quint)) end)
reanimBtn.MouseLeave:Connect(function() tween(reanimBtn, {BackgroundTransparency = .6}, TweenInfo.new(.22, Enum.EasingStyle.Quint)) end)
local mainSwitch = {value = false}
function mainSwitch.set(v)
    mainSwitch.value = v
    reanimBtn.Text = v and "Stop Reanim" or "Reanimate"
    statusLbl.Text = v and "Status: Active" or "Status: Idle"
    tween(statusDot, {BackgroundColor3 = v and C.green or C.div}, TweenInfo.new(.2))
end
reanimBtn.Activated:Connect(function()
    if mainSwitch.value then turnOff() else turnOn() end
end)

----------------------------------------------------------------------
-- Engine: state animations, emotes, blending, recording
----------------------------------------------------------------------
local engine = {motors = {}, stateAnims = {}, gen = {}, token = 0, fadeT = 1, snapshot = {}, baked = {}, parts = {}, collide = {}}
local rec = {on = false, clip = nil, t = 0, acc = 0, frames = 0}
local updateRecUI
-- transport state (Play tab), live limb control (Live tab) and tricks (Tricks tab); logic is filled in further down
engine.paused, engine.dir = false, 1
local live = {on = false, drive = false, group = "rarm", seg = 1, sens = 1, keep = false, mirror = false, pole = false,
    pose = {}, cur = {}, ext = {}, sign = {}}
local tricks = {head = {on = false, mode = "camera", free = false, yaw = 0, pitch = 0},
    torso = {on = false, strength = 1, free = false, yaw = 0, pitch = 0},
    fly = {on = false, speed = 40}}
local liveStep, tricksStep, liveRefresh, playRefresh, tricksStop

local NO_STATE = {name = "None"}
local EMPTY_CLIP = {curves = {}, duration = 1, looped = true} -- rest pose when no clip is assigned
local function stateEntry(s) return data.states[s] or NO_STATE end

local function usable(anim)
    if not anim then return false end
    if anim.rig and anim.rig ~= engine.rig then return false end
    for n in pairs(engine.motors) do if anim.curves[n] then return true end end
    return false
end

local function resolveAnim(entry)
    if not entry then return nil end
    if entry.clip then return entry.clip end
    if entry.rec then
        for _, r in ipairs(recorded) do if r.name == entry.rec then return r.clip end end
        return nil
    end
    if entry.lib then entry = findEntry(entry.lib) end
    if not entry then return nil end
    if entry.clip then return entry.clip end
    local def = entry.def
    if not def or not engine.rig then return nil end
    local baked = engine.baked[def]
    if not baked then
        baked = bakeClip(def, engine.rig, engine.motors)
        engine.baked[def] = baked
    end
    return baked
end

local function refreshState(s)
    if not engine.copy then return end
    engine.gen[s] = (engine.gen[s] or 0) + 1
    local gen, copy = engine.gen[s], engine.copy
    task.spawn(function()
        local anim = resolveAnim(data.states[s] or DEFAULT_STATES[s])
        if not usable(anim) then
            if data.states[s] and not destroyed then setStatus(cap(s) .. " anim doesn't fit this rig") end
            anim = nil
        end
        if destroyed or engine.copy ~= copy or engine.gen[s] ~= gen then return end
        engine.stateAnims[s] = anim
    end)
end

local function currentState(hum, speed)
    local st = hum:GetState()
    if st == Enum.HumanoidStateType.Jumping then return "jump"
    elseif st == Enum.HumanoidStateType.Freefall then return "fall"
    elseif st == Enum.HumanoidStateType.Climbing then return "climb"
    elseif st == Enum.HumanoidStateType.Swimming then return "swim" end
    if speed < 0.75 then return "idle" end
    return speed > 20 and "run" or "walk"
end

local function recordSample(time)
    local clip = rec.clip
    for name, motor in pairs(engine.motors) do
        local curve = clip.curves[name]
        if not curve then curve = {}; clip.curves[name] = curve end
        curve[#curve + 1] = {time = time, value = motor.Transform, style = "Linear", direction = "InOut"}
    end
    clip.duration = math.max(clip.duration, time)
    rec.frames += 1
end

local function engineStep(dt)
    local copy = engine.copy
    if not copy or not copy.Parent then return end
    local hum, root = engine.hum, engine.root
    if settings.noclip then -- noclip: the controlled body passes through walls and parts
        for _, part in ipairs(engine.parts) do
            if part.Parent and part.CanCollide then part.CanCollide = false end
        end
    end
    local e = engine.emote
    if e then
        e.age += dt
        if settings.stopOnMove and e.age > 0.3 and hum.MoveDirection.Magnitude > 0.1 then
            engine.emote = nil; e = nil
        end
    end
    local v = root.AssemblyLinearVelocity
    local speed = Vector3.new(v.X, 0, v.Z).Magnitude
    local stateName = currentState(hum, speed)
    local desired, src, loop, rate = nil, nil, true, 1
    if e then
        desired, src, loop = e.anim, e, e.loop
    else
        desired = engine.stateAnims[stateName] or engine.stateAnims.idle or EMPTY_CLIP
        src = desired
        if desired then loop = desired.looped ~= false end
        if settings.walkSync and (stateName == "walk" or stateName == "run") then
            rate = math.clamp(speed / 16, 0.5, 2)
        end
    end
    if desired then
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
        if loop then
            t = t % dur
            cur.t = t
        elseif t >= dur then
            t = dur
            cur.t = dur
            if e and not desired.hold and engine.dir > 0 and not engine.paused then engine.emote = nil end
        elseif t <= 0 then
            t = 0
            cur.t = 0
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
    end
    if tricksStep then
        local ok, err = pcall(tricksStep, dt)
        if not ok and not engine.warnedTricks then engine.warnedTricks = true; warn("reanimlol tricks: " .. tostring(err)) end
    end
    if liveStep then
        local ok, err = pcall(liveStep, dt)
        if not ok and not engine.warnedLive then engine.warnedLive = true; warn("reanimlol live: " .. tostring(err)) end
    end
    if rec.on then
        rec.t += dt
        rec.acc += dt
        local interval = 1 / settings.recordRate
        if rec.acc >= interval then
            rec.acc -= interval
            recordSample(rec.t)
            updateRecUI()
        end
    end
end

local function engineStart()
    local copy = bodyReanim.Get()
    if not copy then return end
    engine.copy = copy
    engine.hum = copy:FindFirstChildOfClass("Humanoid")
    engine.root = copy:FindFirstChild("HumanoidRootPart")
    engine.rig = engine.hum.RigType == Enum.HumanoidRigType.R6 and "R6" or "R15"
    engine.motors = {}
    engine.baked = {}
    for _, m in ipairs(copy:GetDescendants()) do
        if m:IsA("Motor6D") and m.Part1 then engine.motors[m.Part1.Name] = m end
    end
    engine.parts, engine.collide = {}, {}
    local function track(object)
        if object:IsA("BasePart") and engine.collide[object] == nil then
            engine.collide[object] = object.CanCollide -- remembered so turning noclip off restores it
            engine.parts[#engine.parts + 1] = object
        end
    end
    for _, object in ipairs(copy:GetDescendants()) do track(object) end
    engine.partConn = copy.DescendantAdded:Connect(track)
    engine.current, engine.emote, engine.stateAnims, engine.gen, engine.snapshot, engine.fadeT = nil, nil, {}, {}, {}, 1
    rigLabel.Text = engine.rig
    for _, s in ipairs(STATES) do refreshState(s) end
    engine.conn = RunService.PreSimulation:Connect(engineStep)
end

local function engineStop()
    if engine.conn then engine.conn:Disconnect(); engine.conn = nil end
    if engine.partConn then engine.partConn:Disconnect(); engine.partConn = nil end
    engine.parts, engine.collide = {}, {}
    engine.copy, engine.hum, engine.root, engine.current, engine.emote = nil, nil, nil, nil, nil
    engine.motors, engine.stateAnims = {}, {}
    engine.token += 1
    rec.on = false
    if tricksStop then tricksStop() end
    live.on, live.drive, live.pose, live.cur, live.ext = false, false, {}, {}, {}
    engine.paused, engine.dir = false, 1
    if liveRefresh then liveRefresh() end
    if playRefresh then playRefresh() end
    if updateRecUI and not destroyed then updateRecUI() end
end

local startRev, busy = 0, false
turnOn = function(after)
    if bodyReanim.Get() then if after then after() end return end
    if busy then return end
    busy = true
    startRev += 1
    local rev = startRev
    mainSwitch.set(true)
    setStatus("Starting...", true)
    task.spawn(function()
        local message = bodyReanim.Start()
        busy = false
        if destroyed or rev ~= startRev then return end
        if message or not bodyReanim.Get() then
            bodyReanim.Stop()
            mainSwitch.set(false)
            setStatus(message and tostring(message):sub(1, 38) or "Can't start reanim")
            if message then warn("reanimlol: " .. tostring(message)) end
            return
        end
        engineStart()
        setStatus("reanimlol")
        if after then after() end
    end)
end
turnOff = function()
    startRev += 1
    busy = false
    bodyReanim.Stop()
    mainSwitch.set(false)
    setStatus("reanimlol")
end
bodyReanim.OnStopped(function()
    engineStop()
    if destroyed then return end
    rigLabel.Text = ""
    mainSwitch.set(false)
    setStatus("reanimlol")
end)

stopEmote = function()
    engine.token += 1
    engine.emote = nil
end

local function startEmote(anim, name, key)
    if anim.rig and anim.rig ~= engine.rig then
        setStatus(anim.rig .. " animation on " .. engine.rig .. " rig"); return false
    end
    local matched = 0
    for n in pairs(engine.motors) do if anim.curves[n] then matched += 1 end end
    if matched == 0 then setStatus("Animation doesn't match rig"); return false end
    engine.emote = {anim = anim, loop = settings.loop and not anim.hold, age = 0, name = name, key = key}
    engine.paused, engine.dir = false, 1
    if playRefresh then playRefresh() end
    setStatus(name)
    return true
end

playEntry = function(entry)
    turnOn(function()
        local anim = resolveAnim(entry)
        if not anim then setStatus("Can't play " .. entry.name); return end
        startEmote(anim, entry.name, entry.key)
    end)
end

-- Recording helpers ----------------------------------------------------
local function newClip() return {curves = {}, duration = 0, looped = true, rig = engine.rig} end

local function serializeClip(clip, name)
    local out = {name = name, rig = clip.rig, duration = clip.duration, curves = {}}
    for part, curve in pairs(clip.curves) do
        local arr = {}
        for i, k in ipairs(curve) do arr[i] = {t = k.time, c = {k.value:GetComponents()}, s = k.style, d = k.direction} end
        out.curves[part] = arr
    end
    return out
end
deserializeClip = function(tbl)
    local clip = {curves = {}, duration = tbl.duration or 0, looped = true, rig = tbl.rig}
    for part, arr in pairs(tbl.curves or {}) do
        local curve = {}
        for i, k in ipairs(arr) do
            curve[i] = {time = k.t, value = CFrame.new(table.unpack(k.c)), style = k.s or "Linear", direction = k.d or "InOut"}
        end
        clip.curves[part] = curve
    end
    return clip
end

do -- load saved recordings
    if hasFS and type(listfiles) == "function" then
        pcall(function()
            ensureFolder(ROOT); ensureFolder(ROOT .. "/recordings")
            for _, path in ipairs(listfiles(ROOT .. "/recordings")) do
                if tostring(path):sub(-5) == ".json" then
                    local ok, tbl = pcall(function() return HttpService:JSONDecode(readfile(path)) end)
                    if ok and type(tbl) == "table" and type(tbl.curves) == "table" then
                        local name = tbl.name or tostring(path)
                        recorded[#recorded + 1] = {key = "r:" .. name, name = name, cat = "Recorded", sub = "Local",
                            recorded = true, clip = deserializeClip(tbl), path = path}
                    end
                end
            end
        end)
    end
end

-- Keyframe folder loader ------------------------------------------------
-- Scans Reanimlol/keyframes (and subfolders) for .txt / .lua / .json files. The parser is chosen by
-- file CONTENT, so a Lua export saved as .txt (or JSON saved as .lua) still loads. Subfolder names
-- become the sub-category. Safe to call again at any time to reload. Returns loaded, failed counts.
local loadKeyframeFiles
loadKeyframeFiles = function()
    local keyframeDir = ROOT .. "/keyframes"
    table.clear(fileClips)
    local loaded, failed = 0, 0
    if not (hasFS and type(listfiles) == "function") then return 0, 0 end
    ensureFolder(ROOT); ensureFolder(keyframeDir)

    local function scan(folder, subName, depth)
        local ok, paths = pcall(listfiles, folder)
        if not ok or type(paths) ~= "table" then return end
        for _, path in ipairs(paths) do
            path = (tostring(path):gsub("\\", "/"))
            local isDir = false
            pcall(function() isDir = isfolder(path) end)
            if isDir then
                if depth < 4 then scan(path, path:match("([^/]+)/?$") or subName, depth + 1) end
            else
                local ext = (path:match("%.(%w+)$") or ""):lower()
                if ext == "txt" or ext == "lua" or ext == "json" then
                    local base = path:match("([^/]+)%.%w+$") or "Imported"
                    local okR, raw = pcall(readfile, path)
                    local added = false
                    if okR and type(raw) == "string" then
                        raw = (raw:gsub("^\239\187\191", "")) -- strip UTF-8 BOM
                        if looksLikeLuaKeyframes(raw) then
                            for _, item in ipairs(parseLuaClips(raw)) do
                                local name = item.name == "Imported" and base or item.name
                                fileClips[#fileClips + 1] = {key = "f:" .. name, name = name, cat = "Imported",
                                    sub = subName, clip = item.clip}
                                added = true
                            end
                        else
                            local okJ, tbl = pcall(function() return HttpService:JSONDecode(raw) end)
                            local def = okJ and parseDef(tbl)
                            if def then
                                local name = tostring(tbl.name or base)
                                fileClips[#fileClips + 1] = {key = "f:" .. name, name = name,
                                    cat = tostring(tbl.cat or "Imported"), sub = tostring(tbl.sub or subName), def = def}
                                added = true
                            end
                        end
                    end
                    if added then loaded += 1 else failed += 1 end
                end
            end
        end
    end

    scan(keyframeDir, "Files", 0)
    return loaded, failed
end
loadKeyframeFiles()

----------------------------------------------------------------------
-- GUI: tabs
----------------------------------------------------------------------
local tabNames = {"Emotes", "States", "Play", "Live", "Tricks", "Import", "Record", "Settings"}
local tabFrames, tabButtons, tabOrder = {}, {}, {}
local TAB_X, TAB_Y = 18, 138
local TAB_BAR_Y, TAB_BAR_H, TAB_PAD = 96, 34, 3
local TAB_LABEL = {Settings = "Prefs"}
local CELL = 1 / #tabNames
local tabBar = T("Frame", {Position = UDim2.fromOffset(18, TAB_BAR_Y), Size = UDim2.fromOffset(PANEL_W - 36, TAB_BAR_H),
    BackgroundTransparency = 1}, panel)
local tabPill = T("Frame", {Position = UDim2.new(0, TAB_PAD, 0, TAB_PAD), Size = UDim2.new(CELL, -TAB_PAD * 2, 1, -TAB_PAD * 2),
    BackgroundColor3 = Color3.fromRGB(230, 40, 58), BackgroundTransparency = .25}, tabBar)
corner(tabPill, 8)
local currentTab, tabToken = "Emotes", 0
local function showTab(name)
    if name == currentTab and tabFrames[name].Visible then return end
    tabToken += 1
    local token = tabToken
    local old = currentTab
    local dir = (tabOrder[name] >= tabOrder[old]) and 1 or -1
    currentTab = name
    for n, b in pairs(tabButtons) do
        tween(b, {TextColor3 = n == name and C.text or C.dim})
    end
    local lo, span = math.min(tabOrder[old], tabOrder[name]), math.abs(tabOrder[name] - tabOrder[old])
    tween(tabPill, {Position = UDim2.new(CELL * (lo - 1), TAB_PAD, 0, TAB_PAD),
        Size = UDim2.new(CELL * (span + 1), -TAB_PAD * 2, 1, -TAB_PAD * 2)},
        TweenInfo.new(.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
    task.delay(.13, function()
        if token ~= tabToken or destroyed then return end
        tween(tabPill, {Position = UDim2.new(CELL * (tabOrder[name] - 1), TAB_PAD, 0, TAB_PAD),
            Size = UDim2.new(CELL, -TAB_PAD * 2, 1, -TAB_PAD * 2)},
            TweenInfo.new(.38, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
    end)
    for n, f in pairs(tabFrames) do
        if n == name then
            f.Visible = true
            f.Position = UDim2.fromOffset(TAB_X + 34 * dir, TAB_Y)
            f.GroupTransparency = 1
            tween(f, {Position = UDim2.fromOffset(TAB_X, TAB_Y), GroupTransparency = 0},
                TweenInfo.new(.42, Enum.EasingStyle.Quint, Enum.EasingDirection.Out))
            local idx = 0
            for _, child in ipairs(f:GetChildren()) do
                if child:IsA("GuiObject") then
                    local orig = child:GetAttribute("origPos")
                    if not orig then orig = child.Position; child:SetAttribute("origPos", orig) end
                    child.Position = orig + UDim2.fromOffset(0, 14)
                    local delay = math.min(idx * 0.022, 0.26)
                    idx += 1
                    task.delay(delay, function()
                        if destroyed or not child.Parent then return end
                        tween(child, {Position = orig}, TweenInfo.new(.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out))
                    end)
                end
            end
        elseif f.Visible then
            tween(f, {Position = UDim2.fromOffset(TAB_X - 26 * dir, TAB_Y), GroupTransparency = 1},
                TweenInfo.new(.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In))
            task.delay(.19, function()
                if token == tabToken and not destroyed then f.Visible = false end
            end)
        end
    end
end
for i, name in ipairs(tabNames) do
    tabOrder[name] = i
    tabFrames[name] = T("CanvasGroup", {Position = UDim2.fromOffset(TAB_X, TAB_Y), Size = UDim2.fromOffset(356, 318),
        BackgroundTransparency = 1, Visible = (i == 1)}, tabBar.Parent)
    local b = T("TextButton", {Position = UDim2.new(CELL * (i - 1), 0, 0, 0), Size = UDim2.new(CELL, 0, 1, 0), BackgroundTransparency = 1,
        Text = TAB_LABEL[name] or name, TextScaled = true, Font = Enum.Font.GothamBold, TextColor3 = (i == 1) and C.text or C.dim, ZIndex = 3}, tabBar)
    T("UITextSizeConstraint", {MaxTextSize = 12, MinTextSize = 7}, b)
    T("UIPadding", {PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4), PaddingTop = UDim.new(0, 9), PaddingBottom = UDim.new(0, 9)}, b)
    b.Activated:Connect(function() showTab(name) end)
    tabButtons[name] = b
end

local ui = {main = "All", sub = "All", selected = nil, rows = {}, bindBtn = {}}
local rebuildList, refreshChips, refreshStateRows

local function chipRow(parent, y)
    local row = T("ScrollingFrame", {Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 26),
        BackgroundTransparency = 1, ScrollBarThickness = 0, CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.X, ScrollingDirection = Enum.ScrollingDirection.X}, parent)
    T("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4),
        SortOrder = Enum.SortOrder.LayoutOrder}, row)
    return row
end
local function clearButtons(row)
    for _, c in ipairs(row:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
end
local function chip(row, text, active, order, cb)
    local b = T("TextButton", {AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 24), Text = text,
        TextSize = 12, LayoutOrder = order, BackgroundColor3 = C.field, TextColor3 = active and C.ink or C.dim}, row)
    T("UIPadding", {PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10)}, b)
    corner(b, 12)
    hoverable(b)
    if active then
        -- selected chip fades from the idle colour to the accent colour
        task.defer(function() if b.Parent then setBase(b, C.accent); tween(b, {TextColor3 = C.ink}) end end)
    end
    b.Activated:Connect(cb)
    return b
end

-- Emotes tab ---------------------------------------------------------
local tabE = tabFrames.Emotes
local search = box(tabE, "Search animations...", 0, 0, 356, 28)
local mainRow = chipRow(tabE, 32)
local subRow = chipRow(tabE, 60)
local list = T("ScrollingFrame", {Position = UDim2.fromOffset(0, 90), Size = UDim2.fromOffset(356, 176),
    BackgroundTransparency = 1, ScrollBarThickness = 2, ScrollBarImageColor3 = C.accent, ScrollBarImageTransparency = .6,
    CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y}, tabE)
T("UIListLayout", {Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder}, list)
T("UIPadding", {PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4)}, list)
label(tabE, "Select an animation, then pick a state to assign it to:", 2, 268, 350, 14, {TextSize = 10, TextColor3 = C.dim})

local KEYSHORT = {Zero = "0", One = "1", Two = "2", Three = "3", Four = "4", Five = "5", Six = "6",
    Seven = "7", Eight = "8", Nine = "9", LeftControl = "LCtrl", RightControl = "RCtrl", LeftShift = "LShift",
    RightShift = "RShift", LeftAlt = "LAlt", RightAlt = "RAlt", Backquote = "`", Minus = "-", Equals = "=",
    LeftBracket = "[", RightBracket = "]", Semicolon = ";", Quote = "'", Comma = ",", Period = ".", Slash = "/"}
local function keyLabel(name) return name and (KEYSHORT[name] or name) or "bind" end
local function rowTint(row, selected)
    row:SetAttribute("restT", selected and .8 or 1)
    tween(row, {BackgroundTransparency = selected and .8 or 1}, TweenInfo.new(.2))
end

local function inMain(e)
    if ui.main == "All" then return true end
    if ui.main == "★ Favorites" then return data.favorites[e.key] == true end
    return e.cat == ui.main
end

refreshChips = function()
    clearButtons(mainRow); clearButtons(subRow)
    local mains, seen = {"All", "★ Favorites", "Emotes", "Dances", "Custom", "Recorded"}, {}
    for _, m in ipairs(mains) do seen[m] = true end
    for _, e in ipairs(getEntries()) do
        if not seen[e.cat] then seen[e.cat] = true; mains[#mains + 1] = e.cat end
    end
    for i, m in ipairs(mains) do
        chip(mainRow, m, ui.main == m, i, function()
            ui.main, ui.sub = m, "All"
            refreshChips(); rebuildList(true)
        end)
    end
    if ui.main ~= "All" then
        local subs, seenS = {"All"}, {All = true}
        for _, e in ipairs(getEntries()) do
            if inMain(e) and not seenS[e.sub] then seenS[e.sub] = true; subs[#subs + 1] = e.sub end
        end
        for i, s in ipairs(subs) do
            chip(subRow, s, ui.sub == s, i, function() ui.sub = s; refreshChips(); rebuildList(true) end)
        end
    end
end

local function popIn(row, delay)
    local sc = Instance.new("UIScale")
    sc.Scale = .88
    sc.Parent = row
    row.BackgroundTransparency = 1
    local texts = {}
    for _, d in ipairs(row:GetDescendants()) do
        if d:IsA("TextLabel") or d:IsA("TextButton") then texts[d] = d.TextTransparency; d.TextTransparency = 1 end
    end
    task.delay(delay, function()
        if destroyed or not row.Parent then return end
        local info = TweenInfo.new(.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
        TweenService:Create(sc, info, {Scale = 1}):Play()
        TweenService:Create(row, info, {BackgroundTransparency = row:GetAttribute("restT") or 1}):Play()
        for d, tr in pairs(texts) do TweenService:Create(d, info, {TextTransparency = tr}):Play() end
    end)
end

rebuildList = function(animate)
    if animate then list.CanvasPosition = Vector2.zero end
    for _, c in ipairs(list:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end
    ui.rows, ui.ebtn = {}, {}
    local q = search.Text:lower()
    local order = 0
    for _, e in ipairs(getEntries()) do
        local show = inMain(e)
        if show and ui.sub ~= "All" then show = (e.sub == ui.sub) end
        if show and q ~= "" then show = e.name:lower():find(q, 1, true) ~= nil end
        if show then
            order += 1
            local isSel = ui.selected and ui.selected.key == e.key
            local row = T("TextButton", {Size = UDim2.new(1, -6, 0, 30), Text = "", LayoutOrder = order,
                BackgroundColor3 = C.accent, BackgroundTransparency = isSel and .8 or 1}, list)
            row:SetAttribute("restT", isSel and .8 or 1)
            corner(row, 8)
            row.MouseEnter:Connect(function() tween(row, {BackgroundTransparency = .7}, TweenInfo.new(.15)) end)
            row.MouseLeave:Connect(function() tween(row, {BackgroundTransparency = row:GetAttribute("restT") or 1}, TweenInfo.new(.2)) end)
            local hasX = e.custom or e.recorded
            label(row, e.name, 10, 0, 135, 30, {TextTruncate = Enum.TextTruncate.AtEnd, TextSize = 12})
            label(row, e.sub, 150, 0, 90, 30, {TextSize = 10, TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Right})
            -- keybind button: click, then press a key (Esc cancels, Backspace clears)
            local bindBtn = T("TextButton", {Position = UDim2.new(1, hasX and -106 or -78, 0, 3), Size = UDim2.fromOffset(44, 24),
                Text = keyLabel(data.binds[e.key]), TextSize = 10, TextTruncate = Enum.TextTruncate.AtEnd,
                BackgroundTransparency = 1, TextXAlignment = Enum.TextXAlignment.Right,
                TextColor3 = data.binds[e.key] and C.accent or C.dim}, row)
            ui.ebtn[e.key] = bindBtn
            bindBtn.Activated:Connect(function()
                if ui.bindingEmote == e.key then
                    ui.bindingEmote = nil
                    bindBtn.Text = keyLabel(data.binds[e.key])
                    return
                end
                if ui.bindingEmote and ui.ebtn[ui.bindingEmote] then
                    ui.ebtn[ui.bindingEmote].Text = keyLabel(data.binds[ui.bindingEmote])
                end
                ui.bindingEmote = e.key
                bindBtn.Text = "..."
                setStatus("Press a key for " .. e.name)
            end)
            local star = T("TextButton", {Position = UDim2.new(1, -30, 0, 3), Size = UDim2.fromOffset(24, 24),
                BackgroundTransparency = 1, TextSize = 18, TextColor3 = data.favorites[e.key] and C.gold or C.dim,
                Text = data.favorites[e.key] and "★" or "☆"}, row)
            star.Activated:Connect(function()
                if data.favorites[e.key] then data.favorites[e.key] = nil else data.favorites[e.key] = true end
                saveData()
                if ui.main == "★ Favorites" then refreshChips(); rebuildList()
                else
                    star.Text = data.favorites[e.key] and "★" or "☆"
                    star.TextColor3 = data.favorites[e.key] and C.gold or C.dim
                end
            end)
            if hasX then
                local del = T("TextButton", {Position = UDim2.new(1, -58, 0, 3), Size = UDim2.fromOffset(24, 24),
                    BackgroundTransparency = 1, Text = "✕", TextSize = 13, TextColor3 = C.dim}, row)
                del.Activated:Connect(function()
                    if e.custom then
                        for i, c in ipairs(data.custom) do if c == e.src then table.remove(data.custom, i); break end end
                        saveData()
                    else
                        for i, r in ipairs(recorded) do if r == e then table.remove(recorded, i); break end end
                        if e.path and type(delfile) == "function" then pcall(delfile, e.path) end
                    end
                    data.favorites[e.key] = nil
                    data.binds[e.key] = nil
                    if ui.selected and ui.selected.key == e.key then ui.selected = nil end
                    refreshChips(); rebuildList()
                end)
            end
            ui.rows[e.key] = row
            if animate and order <= 12 then popIn(row, (order - 1) * 0.03) end
            row.Activated:Connect(function()
                if ui.selected and ui.rows[ui.selected.key] then rowTint(ui.rows[ui.selected.key], false) end
                ui.selected = e
                rowTint(row, true)
                -- clicking the animation that's already playing stops it
                if engine.emote and engine.emote.key == e.key then
                    stopEmote()
                    setStatus("Stopped " .. e.name)
                    return
                end
                playEntry(e)
            end)
        end
    end
end
connect(search:GetPropertyChangedSignal("Text"), function() rebuildList() end)

local function assignState(s, e)
    if e.recorded then data.states[s] = {name = e.name, rec = e.name}
    else data.states[s] = {name = e.name, lib = e.key} end
    saveData()
    refreshStateRows()
    refreshState(s)
    setStatus(cap(s) .. " = " .. e.name)
end
local openStatePicker -- defined in the States section (shares the popup helpers)
local stateBtn = button(tabE, "Choose state to assign  ▼", 0, 284, 356, 28, function()
    openStatePicker(stateBtn)
end)

-- States tab ---------------------------------------------------------
local tabS = tabFrames.States
local stateBoxes = {}
-- Dropdown picker: lists every clip (built-in, imported, recorded) with a search box.
-- It lives inside the panel (not the clipped tab frame) and a big invisible catcher closes it on outside click.
local dropCatcher, dropFrame
local function closeDropdown()
    if dropCatcher then dropCatcher:Destroy(); dropCatcher = nil end
    if dropFrame then dropFrame:Destroy(); dropFrame = nil end
end
local function openDropdown(s, anchor)
    closeDropdown()
    local scale = math.max(panelScale.Scale, 0.01)
    local rel = (anchor.AbsolutePosition - panel.AbsolutePosition) / scale
    local w, h = 300, 200
    local x = math.clamp(rel.X, 6, PANEL_W - w - 6)
    local y = rel.Y + anchor.AbsoluteSize.Y / scale + 2
    if y + h > PANEL_H - 6 then y = rel.Y - h - 2 end

    dropCatcher = T("TextButton", {Size = UDim2.fromOffset(4000, 4000), Position = UDim2.fromOffset(-2000, -2000),
        BackgroundTransparency = 1, Text = "", ZIndex = 9}, panel)
    dropCatcher.Activated:Connect(closeDropdown)

    local frame = T("Frame", {Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h),
        BackgroundColor3 = C.bg, ZIndex = 10}, panel)
    dropFrame = frame
    corner(frame, 16)
    local stroke = Instance.new("UIStroke")
    stroke.Color, stroke.Thickness, stroke.ApplyStrokeMode = C.stroke, 1.5, Enum.ApplyStrokeMode.Border
    stroke.Parent = frame
    local searchBox = box(frame, "Search clips", 6, 6, w - 12, 26)
    local listFrame = T("ScrollingFrame", {Position = UDim2.fromOffset(6, 38), Size = UDim2.fromOffset(w - 12, h - 44),
        BackgroundColor3 = C.list, ScrollBarThickness = 4, CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y}, frame)
    corner(listFrame, 12)
    T("UIListLayout", {Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder}, listFrame)
    T("UIPadding", {PaddingLeft = UDim.new(0, 3), PaddingRight = UDim.new(0, 3), PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 3)}, listFrame)

    local function populate()
        for _, c in ipairs(listFrame:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end
        local q = searchBox.Text:lower()
        local order = 0
        local current = stateEntry(s)
        local function addRow(text, sub, active, cb)
            order += 1
            local row = T("TextButton", {Size = UDim2.new(1, -6, 0, 26), Text = "", LayoutOrder = order,
                BackgroundColor3 = active and C.sel or C.field}, listFrame)
            corner(row, 9)
            label(row, text, 8, 0, 180, 26, {TextTruncate = Enum.TextTruncate.AtEnd})
            label(row, sub, 190, 0, 84, 26, {TextSize = 10, TextColor3 = C.dim,
                TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd})
            hoverable(row)
            row.Activated:Connect(function() cb(); closeDropdown() end)
        end
        if q == "" then
            addRow("✕ None", "", data.states[s] == nil, function()
                data.states[s] = nil; saveData(); refreshStateRows(); refreshState(s)
                setStatus(cap(s) .. " cleared")
            end)
        end
        -- clips whose name contains the state (e.g. "Walk") are listed first
        local first, rest = {}, {}
        for _, e in ipairs(getEntries()) do
            local hay = (e.name .. " " .. e.sub .. " " .. e.cat):lower()
            if q == "" or hay:find(q, 1, true) then
                if e.name:lower():find(s, 1, true) then first[#first + 1] = e else rest[#rest + 1] = e end
            end
        end
        for _, group in ipairs({first, rest}) do
            for _, e in ipairs(group) do
                addRow(e.name, e.sub, current and current.name == e.name, function() assignState(s, e) end)
            end
        end
        if order == 0 then
            addRow("No clips found", "", false, function() end)
        end
    end
    searchBox:GetPropertyChangedSignal("Text"):Connect(populate)
    populate()
end

-- Emotes tab: pick which state (Idle, Walk, ...) the selected animation is assigned to
openStatePicker = function(anchor)
    if not ui.selected then setStatus("Select an entry first"); return end
    closeDropdown()
    local scale = math.max(panelScale.Scale, 0.01)
    local rel = (anchor.AbsolutePosition - panel.AbsolutePosition) / scale
    local w, h = anchor.AbsoluteSize.X / scale, #STATES * 29 + 9
    local x = math.clamp(rel.X, 6, math.max(6, PANEL_W - w - 6))
    local y = rel.Y - h - 2 -- opens upward; the button sits near the bottom of the panel
    if y < 6 then y = rel.Y + anchor.AbsoluteSize.Y / scale + 2 end

    dropCatcher = T("TextButton", {Size = UDim2.fromOffset(4000, 4000), Position = UDim2.fromOffset(-2000, -2000),
        BackgroundTransparency = 1, Text = "", ZIndex = 9}, panel)
    dropCatcher.Activated:Connect(closeDropdown)
    local frame = T("Frame", {Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h),
        BackgroundColor3 = C.bg, ZIndex = 10}, panel)
    dropFrame = frame
    corner(frame, 16)
    local stroke = Instance.new("UIStroke")
    stroke.Color, stroke.Thickness, stroke.ApplyStrokeMode = C.stroke, 1.5, Enum.ApplyStrokeMode.Border
    stroke.Parent = frame
    T("UIListLayout", {Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder}, frame)
    T("UIPadding", {PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4)}, frame)
    local picked = ui.selected
    for i, s in ipairs(STATES) do
        local row = T("TextButton", {Size = UDim2.new(1, 0, 0, 26), Text = "", LayoutOrder = i}, frame)
        corner(row, 9)
        label(row, cap(s), 10, 0, 100, 26)
        label(row, stateEntry(s).name, 110, 0, w - 130, 26, {TextSize = 10, TextColor3 = C.dim,
            TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd})
        hoverable(row)
        row.Activated:Connect(function()
            assignState(s, picked)
            closeDropdown()
        end)
    end
end

for i, s in ipairs(STATES) do
    local y = 4 + (i - 1) * 36
    label(tabS, cap(s), 4, y, 56, 30)
    local tb = button(tabS, "", 60, y, 226, 30, function() openDropdown(s, stateBoxes[s]) end)
    tb.TextXAlignment = Enum.TextXAlignment.Left
    tb.TextTruncate = Enum.TextTruncate.AtEnd
    T("UIPadding", {PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 26)}, tb)
    label(tb, "▼", 0, 0, 0, 30, {Size = UDim2.new(0, 20, 1, 0), Position = UDim2.new(1, -22, 0, 0),
        TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.dim, TextSize = 10})
    stateBoxes[s] = tb
    button(tabS, "Reset", 292, y, 64, 30, function()
        data.states[s] = nil; saveData(); refreshStateRows(); refreshState(s)
    end)
end
label(tabS, "No built-in state animations. Open a state's dropdown to choose any clip, or select an\nanimation on the Emotes tab and pick a state there.", 4, 262, 350, 28,
    {TextSize = 10, TextColor3 = C.dim, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top})
refreshStateRows = function()
    for _, s in ipairs(STATES) do stateBoxes[s].Text = stateEntry(s).name end
end

-- Import tab ----------------------------------------------------------
local tabA = tabFrames.Import
local nameBox = box(tabA, "Name (optional)", 0, 0, 356, 30)
local catBox = box(tabA, "Category", 0, 36, 172, 30)
local subBox = box(tabA, "Sub-category", 184, 36, 172, 30)
catBox.Text, subBox.Text = "Custom", "General"
local fileBox = box(tabA, "Workspace file (.txt / .lua / .json)", 0, 72, 244, 30)
local jsonBox = box(tabA, "...or paste keyframes here", 0, 108, 356, 92)
jsonBox.MultiLine, jsonBox.TextWrapped, jsonBox.TextYAlignment = true, true, Enum.TextYAlignment.Top
jsonBox.TextSize = 11
T("UIPadding", {PaddingTop = UDim.new(0, 8), PaddingRight = UDim.new(0, 8)}, jsonBox)

local function trim(str, d) str = str:match("^%s*(.-)%s*$"); return str ~= "" and str or d end

local function importText(text, fallbackName)
    local cat, sub = trim(catBox.Text, "Custom"), trim(subBox.Text, "General")
    local typed = trim(nameBox.Text, nil)
    local entries = {}
    if looksLikeLuaKeyframes(text) then
        local found = parseLuaClips(text)
        if #found == 0 then
            setStatus(("No keyframes found in %d chars (file cut off?)"):format(#text)); return
        end
        for _, item in ipairs(found) do
            local name = (#found == 1 and typed) or item.name
            if name == "Imported" then name = fallbackName or name end
            item.clip.rig = item.clip.rig or playerRig()
            entries[#entries + 1] = {name = name, cat = cat, sub = sub, clipData = serializeClip(item.clip, name)}
        end
    else
        local ok, decoded = pcall(function() return HttpService:JSONDecode(text) end)
        if not ok or type(decoded) ~= "table" then
            setStatus(("Not keyframes: got %d chars, no Time/CFrame or JSON found"):format(#text)); return
        end
        local def, err = parseDef(decoded)
        if not def then setStatus(err or "Bad keyframes"); return end
        entries[1] = {name = typed or tostring(decoded.name or fallbackName or ("Imported " .. (#data.custom + 1))),
            cat = cat, sub = sub, def = def}
    end
    for _, e in ipairs(entries) do table.insert(data.custom, e) end
    saveData()
    nameBox.Text, jsonBox.Text, fileBox.Text = "", "", ""
    ui.main, ui.sub = cat, "All"
    refreshChips(); rebuildList(true)
    setStatus("Added " .. (#entries == 1 and entries[1].name or (#entries .. " clips")))
    showTab("Emotes")
end

button(tabA, "Load file", 250, 72, 106, 30, function()
    if not hasFS then setStatus("No file access"); return end
    local path = trim(fileBox.Text, "")
    if path == "" then setStatus("Type a file name first"); return end
    -- try the name as typed, inside Reanimlol/keyframes and Reanimlol, and with .txt/.lua/.json added
    local candidates = {}
    for _, base in ipairs({path, ROOT .. "/keyframes/" .. path, ROOT .. "/" .. path}) do
        candidates[#candidates + 1] = base
        if not base:match("%.%w+$") then
            for _, ext in ipairs({".txt", ".lua", ".json"}) do candidates[#candidates + 1] = base .. ext end
        end
    end
    local text
    for _, candidate in ipairs(candidates) do
        local ok, raw = pcall(function() if isfile(candidate) then return readfile(candidate) end end)
        if ok and type(raw) == "string" then text = raw; break end
    end
    if not text then setStatus("File not found"); return end
    text = text:gsub("^\239\187\191", "") -- strip UTF-8 BOM
    importText(text, path:match("([^/\\]+)%.%w+$") or path)
end)
button(tabA, "Add pasted keyframes", 0, 206, 244, 30, function()
    if jsonBox.Text:match("^%s*$") then setStatus("Paste keyframes first"); return end
    importText(jsonBox.Text)
end)
button(tabA, "Reload folder", 250, 206, 106, 30, function()
    if not hasFS or type(listfiles) ~= "function" then setStatus("No file access"); return end
    local loaded, failed = loadKeyframeFiles()
    if ui.selected then ui.selected = findEntry(ui.selected.key) end
    refreshChips(); rebuildList(true)
    for _, s in ipairs(STATES) do refreshState(s) end -- re-resolve any state set to a file clip
    setStatus(("Reloaded %d file%s%s"):format(loaded, loaded == 1 and "" or "s",
        failed > 0 and (", " .. failed .. " failed") or ""))
end)
label(tabA, "Drop .txt / .lua / .json keyframe files into Reanimlol/keyframes/ (subfolders become sub-categories), then press Reload folder: no rejoin needed. Imported clips show under Emotes > Imported. Or type a file name and press Load file. Pasting is limited to ~100k characters.",
    2, 242, 352, 74, {TextSize = 10, TextColor3 = C.dim, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top})

-- Record tab ---------------------------------------------------------
local tabR = tabFrames.Record
local recInfo = label(tabR, "0.0s • 0 keyframes", 2, 0, 350, 24, {TextColor3 = C.dim})
local recBtn
updateRecUI = function()
    recBtn.Text = rec.on and "■ Stop" or "● Record"
    recBtn.TextColor3 = rec.on and C.danger or C.text
    local d = rec.clip and rec.clip.duration or 0
    recInfo.Text = string.format("%.1fs • %d keyframes", d, rec.clip and rec.frames or 0)
end
recBtn = button(tabR, "● Record", 0, 28, 84, 30, function()
    if rec.on then rec.on = false; updateRecUI(); return end
    if not engine.copy then setStatus("Turn reanim on first"); return end
    rec.clip, rec.t, rec.acc, rec.frames = newClip(), 0, math.huge, 0
    rec.on = true
    updateRecUI()
end)
button(tabR, "Snap pose", 90, 28, 84, 30, function()
    if not engine.copy then setStatus("Turn reanim on first"); return end
    if rec.on then return end
    if not rec.clip then rec.clip, rec.frames = newClip(), 0 end
    recordSample(rec.frames == 0 and 0 or rec.clip.duration + 0.3)
    updateRecUI()
end)
button(tabR, "Preview", 180, 28, 84, 30, function()
    if not rec.clip or rec.clip.duration <= 0 then setStatus("Record or snap 2+ poses"); return end
    rec.on = false; updateRecUI()
    turnOn(function() startEmote(rec.clip, "Preview") end)
end)
button(tabR, "Clear", 270, 28, 86, 30, function()
    rec.on, rec.clip, rec.frames = false, nil, 0
    updateRecUI()
end)
local recName = box(tabR, "Recording name", 0, 66, 244, 30)
button(tabR, "Save", 250, 66, 106, 30, function()
    local clip = rec.clip
    if not clip or clip.duration <= 0 then setStatus("Nothing recorded"); return end
    rec.on = false
    local name = recName.Text:match("^%s*(.-)%s*$")
    if name == "" then name = "Recording " .. (#recorded + 1) end
    clip.rig = clip.rig or engine.rig or playerRig()
    local entry = {key = "r:" .. name, name = name, cat = "Recorded", sub = "Local", recorded = true, clip = clip}
    for i, r in ipairs(recorded) do if r.name == name then table.remove(recorded, i); break end end
    recorded[#recorded + 1] = entry
    if hasFS then
        local path = ROOT .. "/recordings/" .. name:gsub("[^%w%-_ ]", "_") .. ".json"
        entry.path = path
        pcall(function()
            ensureFolder(ROOT); ensureFolder(ROOT .. "/recordings")
            writefile(path, HttpService:JSONEncode(serializeClip(clip, name)))
        end)
    end
    rec.clip, rec.frames = nil, 0
    recName.Text = ""
    updateRecUI(); refreshChips(); rebuildList()
    setStatus("Saved " .. name)
end)
label(tabR, "Rate", 2, 104, 40, 14, {TextColor3 = C.dim, TextSize = 12})
local rateVal = label(tabR, settings.recordRate .. " Hz", 300, 104, 56, 14, {TextColor3 = C.dim, TextSize = 12})
slider(tabR, 46, 104, 246, 5, 30, settings.recordRate, function(v)
    settings.recordRate = math.floor(v + 0.5)
    rateVal.Text = settings.recordRate .. " Hz"
    saveSoon()
end)
label(tabR, "● Record captures whatever the rig is doing (emote, state animation, speed and blend included) as keyframes. \"Snap pose\" adds a single keyframe 0.3s after the last one. Save adds it to Library > Recorded, writes Reanimlol/recordings/<name>.json.",
    2, 142, 352, 120, {TextSize = 11, TextColor3 = C.dim, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top})

-- Settings tab -------------------------------------------------------
local tabG = tabFrames.Settings
label(tabG, "Stop emote when moving", 4, 0, 280, 30)
switch(tabG, UDim2.fromOffset(306, 3), settings.stopOnMove, function(v) settings.stopOnMove = v; saveSoon() end)
label(tabG, "Sync walk speed to movement", 4, 34, 280, 30)
switch(tabG, UDim2.fromOffset(306, 37), settings.walkSync, function(v) settings.walkSync = v; saveSoon() end)
label(tabG, "Blend", 4, 68, 50, 30)
local blendVal = label(tabG, string.format("%.2fs", settings.blend), 300, 68, 56, 30, {TextColor3 = C.dim, TextSize = 12})
slider(tabG, 60, 76, 232, 0, 0.5, settings.blend, function(v)
    settings.blend = math.floor(v * 100 + 0.5) / 100
    blendVal.Text = string.format("%.2fs", settings.blend)
    saveSoon()
end)
local function bindRow(text, key, y)
    label(tabG, text, 4, y, 220, 30)
    local b = button(tabG, settings[key], 236, y, 120, 30, function()
        ui.binding = key
        ui.bindBtn[key].Text = "press key..."
    end)
    ui.bindBtn[key] = b
end
label(tabG, "Noclip while reanimated", 4, 102, 280, 30)
switch(tabG, UDim2.fromOffset(306, 105), settings.noclip, function(v)
    settings.noclip = v
    saveSoon()
    if not v then -- put collisions back the way they were
        for part, can in pairs(engine.collide) do if part.Parent then part.CanCollide = can end end
    end
end)
bindRow("Toggle reanim key", "keyToggle", 136)
bindRow("Hide / show GUI key", "keyGui", 170)
bindRow("Stop emote key", "keyStop", 204)
label(tabG, "Speed keys: slower / faster / reset  (Esc cancels a rebind)", 4, 238, 350, 14, {TextSize = 10, TextColor3 = C.dim})
for i, key in ipairs({"keySpeedDown", "keySpeedUp", "keySpeedReset"}) do
    local b = button(tabG, settings[key], (i - 1) * 122, 254, 112, 26, function()
        ui.binding = key
        ui.bindBtn[key].Text = "press key..."
    end)
    ui.bindBtn[key] = b
end
button(tabG, "Reset saved data", 0, 286, 356, 28, function()
    data.favorites, data.custom, data.states, data.binds = {}, {}, {}, {}
    saveData()
    ui.main, ui.sub, ui.selected = "All", "All", nil
    refreshChips(); rebuildList(); refreshStateRows()
    for _, s in ipairs(STATES) do refreshState(s) end
    setStatus("Data reset")
end)

----------------------------------------------------------------------
-- Play / Live / Tricks tabs (transport, live limb control and body tricks)
----------------------------------------------------------------------
local ctl = {}
local function toggleRow(parent, text, y, initial, cb)
    label(parent, text, 4, y, 290, 28)
    return switch(parent, UDim2.fromOffset(306, y + 2), initial, cb)
end
local function sliderRow(parent, text, y, min, max, value, fmt, cb)
    label(parent, text, 4, y, 60, 22, {TextColor3 = C.dim, TextSize = 12})
    local val = label(parent, string.format(fmt, value), 300, y, 56, 22, {TextColor3 = C.dim, TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Right})
    local sl = slider(parent, 64, y + 4, 228, min, max, value, function(v)
        val.Text = string.format(fmt, v)
        cb(v)
    end)
    sl.label = val
    return sl
end
local function bindButton(parent, text, key, y)
    label(parent, text, 4, y, 220, 28)
    local b = button(parent, settings[key], 236, y, 120, 28, function()
        ui.binding = key
        ui.bindBtn[key].Text = "press key..."
    end)
    ui.bindBtn[key] = b
end
local function setSelected(b, on)
    setBase(b, on and C.accent or C.field)
    tween(b, {TextColor3 = on and C.ink or C.dim})
end
local mouseRay = RaycastParams.new()
mouseRay.FilterType = Enum.RaycastFilterType.Exclude
mouseRay.IgnoreWater = true
-- world point under the mouse (ignores your own bodies); falls back to a point 60 studs along the ray
local function hitPoint()
    local cam = workspace.CurrentCamera
    if not cam then return nil end
    local mp = UserInputService:GetMouseLocation()
    local ray = cam:ViewportPointToRay(mp.X, mp.Y)
    local ignore = {}
    if engine.copy then ignore[#ignore + 1] = engine.copy end
    if player.Character then ignore[#ignore + 1] = player.Character end
    mouseRay.FilterDescendantsInstances = ignore
    local hit = workspace:Raycast(ray.Origin, ray.Direction * 400, mouseRay)
    return hit and hit.Position or ray.Origin + ray.Direction * 60
end

-- Play tab: transport controls ----------------------------------------
do
    local tabP = tabFrames.Play
    local playName = label(tabP, "Nothing playing", 2, 0, 230, 24, {Font = Enum.Font.GothamBold,
        TextTruncate = Enum.TextTruncate.AtEnd})
    local playTime = label(tabP, "0.00 / 0.00s", 232, 0, 124, 24, {TextColor3 = C.dim, TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Right})
    local lastScrub = 0
    local scrub = slider(tabP, 0, 32, 356, 0, 1, 0, function(v)
        local cur = engine.current
        if not cur then return end
        lastScrub = os.clock()
        engine.paused = true
        cur.t = v * cur.anim.duration
        playRefresh()
    end)
    local function step(delta)
        local cur = engine.current
        if not cur then return end
        engine.paused = true
        cur.t = math.clamp(cur.t + delta, 0, cur.anim.duration)
        lastScrub = 0
        playRefresh()
    end
    ctl.togglePause = function()
        if not engine.current then return end
        engine.paused = not engine.paused
        playRefresh()
    end
    ctl.restart = function()
        local cur = engine.current
        if engine.emote and cur then
            cur.t = engine.dir < 0 and cur.anim.duration or 0
        elseif ui.lastEntry then
            playEntry(ui.lastEntry) -- the emote already finished: play it again
        elseif cur then
            cur.t = 0
        end
        engine.paused = false
        playRefresh()
    end
    ctl.reverse = function()
        engine.dir = -engine.dir
        playRefresh()
    end
    local W, GAP = 66, 6.5
    button(tabP, "⏮ Restart", 0, 58, W, 28, ctl.restart)
    local pauseBtn = button(tabP, "⏸ Pause", (W + GAP), 58, W, 28, ctl.togglePause)
    local revBtn = button(tabP, "⇄ Reverse", (W + GAP) * 2, 58, W, 28, ctl.reverse)
    button(tabP, "◀ Step", (W + GAP) * 3, 58, W, 28, function() step(-0.05) end)
    button(tabP, "Step ▶", (W + GAP) * 4, 58, W, 28, function() step(0.05) end)
    for _, b in ipairs({pauseBtn, revBtn}) do b.TextSize = 11 end
    playRefresh = function()
        if destroyed then return end
        pauseBtn.Text = engine.paused and "▶ Play" or "⏸ Pause"
        setSelected(pauseBtn, engine.paused)
        tween(pauseBtn, {TextColor3 = engine.paused and C.ink or C.text})
        setSelected(revBtn, engine.dir < 0)
        tween(revBtn, {TextColor3 = engine.dir < 0 and C.ink or C.text})
    end
    playRefresh()
    label(tabP, "Keybinds  (Esc cancels a rebind)", 4, 100, 350, 16, {TextSize = 11, TextColor3 = C.dim})
    bindButton(tabP, "Pause / resume", "keyPause", 122)
    bindButton(tabP, "Restart", "keyRewind", 156)
    bindButton(tabP, "Reverse", "keyReverse", 190)
    label(tabP, "Works on emotes and state animations. Dragging the bar pauses and scrubs; the speed slider below still applies. Reverse plays the clip backwards.",
        4, 228, 350, 60, {TextSize = 10, TextColor3 = C.dim, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top})
    connect(RunService.RenderStepped, function()
        if destroyed or currentTab ~= "Play" then return end
        local cur = engine.current
        if cur and engine.copy then
            local dur = math.max(cur.anim.duration, 0.001)
            playName.Text = engine.emote and engine.emote.name or "State animation"
            playTime.Text = string.format("%.2f / %.2fs", math.clamp(cur.t, 0, dur), dur)
            if os.clock() - lastScrub > 0.25 then scrub.set(math.clamp(cur.t / dur, 0, 1), false) end
        else
            playName.Text, playTime.Text = "Nothing playing", "0.00 / 0.00s"
        end
    end)
    local origPlay = playEntry
    playEntry = function(entry)
        ui.lastEntry = entry
        return origPlay(entry)
    end
end

-- Live tab: aim limbs at the mouse --------------------------------------
do
    local tabL = tabFrames.Live
    local GROUPS = {{"larm", "L Arm"}, {"head", "Head"}, {"rarm", "R Arm"}, {"lleg", "L Leg"}, {"torso", "Torso"}, {"rleg", "R Leg"}}
    local PARTS = {
        R15 = {head = {{"Head", "Head"}}, torso = {{"UpperTorso", "Upper"}, {"LowerTorso", "Lower"}},
            larm = {{"LeftUpperArm", "Upper"}, {"LeftLowerArm", "Lower"}, {"LeftHand", "Hand"}},
            rarm = {{"RightUpperArm", "Upper"}, {"RightLowerArm", "Lower"}, {"RightHand", "Hand"}},
            lleg = {{"LeftUpperLeg", "Upper"}, {"LeftLowerLeg", "Lower"}, {"LeftFoot", "Foot"}},
            rleg = {{"RightUpperLeg", "Upper"}, {"RightLowerLeg", "Lower"}, {"RightFoot", "Foot"}}},
        R6 = {head = {{"Head", "Head"}}, torso = {{"Torso", "Torso"}}, larm = {{"Left Arm", "Arm"}},
            rarm = {{"Right Arm", "Arm"}}, lleg = {{"Left Leg", "Leg"}}, rleg = {{"Right Leg", "Leg"}}},
    }
    local LIM = {Head = {75, 45}, UpperTorso = {40, 30}, LowerTorso = {60, 25}, Torso = {60, 25}}
    local function segs(group)
        local set = PARTS[engine.rig or "R15"] or PARTS.R15
        return set[group or live.group] or set.rarm
    end
    local function selPart()
        local list = segs()
        local e = list[math.clamp(live.seg, 1, #list)]
        return e and e[1]
    end
    local function opposite(n)
        if n:sub(1, 4) == "Left" then return "Right" .. n:sub(5) end
        if n:sub(1, 5) == "Right" then return "Left" .. n:sub(6) end
    end
    local function flip(cf)
        local x, y, z = cf:ToOrientation()
        return CFrame.fromOrientation(x, -y, -z)
    end
    local function setPose(part, cf, ext)
        live.pose[part] = cf
        if ext then live.ext[part] = ext end
        if live.mirror then
            local o = opposite(part)
            if o and engine.motors[o] then
                live.pose[o] = flip(cf)
                if ext then live.ext[o] = ext end
            end
        end
    end
    local function joint(part)
        local m = engine.motors[part]
        if m and m.Parent and m.Part0 and m.Part0.Parent then
            return m.Part0.CFrame * m.C0, m.C1.Rotation:Inverse(), m
        end
    end
    -- rotation (in the joint's own frame) that points the limb at a world position
    local function aim(part, target)
        local J, Rc = joint(part)
        if not J then return nil end
        local dW = target - J.Position
        if dW.Magnitude < 0.1 then return nil end
        local dl = J:VectorToObjectSpace(dW.Unit)
        local lim = LIM[part]
        if lim then -- head / torso: yaw + pitch with limits
            local dp = Rc:VectorToObjectSpace(dl)
            local rx = math.asin(math.clamp(dp.Y, -1, 1))
            local ry = math.atan2(-dp.X, -dp.Z)
            local ym, pm = math.rad(lim[1]), math.rad(lim[2])
            rx = math.clamp(rx, -pm, pm)
            if math.abs(ry) > ym then
                ry = (live.sign[part] or (ry > 0 and 1 or -1)) * ym
            else
                live.sign[part] = ry >= 0 and 1 or -1
            end
            return Rc * CFrame.fromOrientation(rx, ry, 0) * Rc:Inverse()
        end
        local from = Rc:VectorToWorldSpace(Vector3.new(0, -1, 0)) -- limbs hang along -Y
        local dot = math.clamp(from:Dot(dl), -1, 1)
        local axis = from:Cross(dl)
        if axis.Magnitude < 1e-4 then
            if dot > 0 then return CFrame.identity end
            axis = Rc:VectorToWorldSpace(Vector3.new(1, 0, 0))
        end
        return CFrame.fromAxisAngle(axis.Unit, math.acos(dot))
    end

    liveStep = function(dt)
        if not live.on then return end
        local cam = workspace.CurrentCamera
        if live.pole and cam then
            -- "pole": both arms stretched straight out along the camera direction
            for _, g in ipairs({"larm", "rarm"}) do
                local list = segs(g)
                local part = list[1][1]
                local J = joint(part)
                if J then
                    local cf = aim(part, J.Position + cam.CFrame.LookVector * 50)
                    if cf then
                        live.pose[part] = cf
                        live.ext[part] = math.max(live.ext[part] or 0, 6)
                    end
                end
                for i = 2, #list do live.pose[list[i][1]] = CFrame.identity end
            end
        elseif live.drive then
            local part = selPart()
            local target = part and hitPoint()
            if target then
                local cf = aim(part, target)
                if cf then setPose(part, cf) end
            end
        end
        local k = 1 - math.exp(-dt * 14 * live.sens)
        for part, target in pairs(live.pose) do
            local m = engine.motors[part]
            if m and m.Parent then
                local cur = (live.cur[part] or CFrame.identity):Lerp(target, k)
                live.cur[part] = cur
                local out = cur
                local ext = live.ext[part] or 0
                if ext > 0 then -- reach / stretch: slide the limb out along its own axis
                    local axis = m.C1.Rotation:Inverse():VectorToWorldSpace(Vector3.new(0, -1, 0))
                    out = CFrame.new(cur:VectorToWorldSpace(axis) * ext) * cur
                end
                m.Transform = live.keep and (m.Transform * out) or out
            end
        end
    end

    -- UI
    label(tabL, "Live limb control", 4, 0, 250, 28)
    local liveSwitch
    local groupBtns = {}
    local segRow = T("Frame", {Position = UDim2.fromOffset(0, 100), Size = UDim2.fromOffset(356, 24), BackgroundTransparency = 1}, tabL)
    T("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, segRow)
    local segBtns = {}
    local reachSlider
    local function syncReach()
        local part = selPart()
        local v = part and live.ext[part] or 0
        reachSlider.set(v, false)
        reachSlider.label.Text = string.format("%.1f", v)
    end
    local function refreshGroups()
        for id, b in pairs(groupBtns) do setSelected(b, id == live.group) end
    end
    local function rebuildSegs()
        for _, b in ipairs(segBtns) do b:Destroy() end
        segBtns = {}
        for i, e in ipairs(segs()) do
            local b = T("TextButton", {Size = UDim2.fromOffset(84, 24), Text = e[2], TextSize = 12, LayoutOrder = i}, segRow)
            corner(b, 12)
            hoverable(b)
            setSelected(b, i == live.seg)
            b.Activated:Connect(function()
                live.seg = i
                rebuildSegs()
                syncReach()
            end)
            segBtns[#segBtns + 1] = b
        end
    end
    for i, g in ipairs(GROUPS) do
        groupBtns[g[1]] = button(tabL, g[2], ((i - 1) % 3) * 121, 34 + math.floor((i - 1) / 3) * 32, 114, 28, function()
            live.group, live.seg = g[1], 1
            refreshGroups(); rebuildSegs(); syncReach()
        end)
    end
    local hint = label(tabL, "", 2, 126, 230, 24, {TextSize = 10, TextColor3 = C.dim})
    local driveBtn = button(tabL, settings.keyDrive, 236, 126, 120, 24, function()
        ui.binding = "keyDrive"
        ui.bindBtn.keyDrive.Text = "press key..."
    end)
    driveBtn.TextSize = 11
    ui.bindBtn.keyDrive = driveBtn
    sliderRow(tabL, "Follow", 156, 0.2, 3, live.sens, "%.1fx", function(v) live.sens = math.floor(v * 10 + 0.5) / 10 end).set(live.sens, false)
    reachSlider = sliderRow(tabL, "Reach", 182, 0, 14, 0, "%.1f", function(v)
        local part = selPart()
        if not part then return end
        v = math.floor(v * 10 + 0.5) / 10
        if not live.pose[part] then setPose(part, CFrame.identity, v) end
        setPose(part, live.pose[part], v)
    end)
    toggleRow(tabL, "Mirror to opposite limb", 208, false, function(v) live.mirror = v end)
    toggleRow(tabL, "Keep animation underneath", 236, false, function(v) live.keep = v end)
    local poleSwitch = toggleRow(tabL, "Pole arms (stretch along camera)", 264, false, function(v) ctl.setPole(v) end)
    local function clearArms()
        for _, g in ipairs({"larm", "rarm"}) do
            for _, e in ipairs(segs(g)) do live.pose[e[1]] = CFrame.identity; live.ext[e[1]] = 0 end
        end
    end
    button(tabL, "Reset limb", 0, 292, 174, 24, function()
        local part = selPart()
        if not part then return end
        for _, n in ipairs({part, live.mirror and opposite(part) or part}) do
            live.pose[n], live.cur[n], live.ext[n] = nil, nil, nil
        end
        syncReach()
    end)
    button(tabL, "Reset all", 182, 292, 174, 24, function()
        live.pose, live.cur, live.ext, live.pole = {}, {}, {}, false
        liveRefresh()
        syncReach()
    end)

    ctl.setLive = function(v)
        if v then
            local function on()
                live.on = true
                setStatus("Live control on")
                liveRefresh()
            end
            if engine.copy then on() else turnOn(on) end
        else
            live.on, live.drive, live.pole = false, false, false
            live.pose, live.cur = {}, {}
            setStatus("Live control off")
        end
        liveRefresh()
    end
    ctl.setPole = function(v)
        if v and not live.on then ctl.setLive(true) end
        live.pole = v and true or false
        if not v then clearArms() end
        liveRefresh()
    end
    ctl.setDrive = function(on)
        on = on and live.on or false
        if live.drive == on then return end
        live.drive = on
        if on then -- segments below the selected one relax so the whole limb follows
            local list = segs()
            for i = live.seg + 1, #list do setPose(list[i][1], CFrame.identity) end
        end
    end
    liveRefresh = function()
        if destroyed then return end
        if not live.on then live.pole = false end
        liveSwitch.set(live.on)
        poleSwitch.set(live.pole)
        hint.Text = "Hold " .. keyLabel(settings.keyDrive) .. " to aim the selected limb at your mouse"
        refreshGroups(); rebuildSegs(); syncReach()
    end
    liveSwitch = switch(tabL, UDim2.fromOffset(306, 2), false, function(v) ctl.setLive(v) end)
    liveRefresh()
end

-- Tricks tab: head / torso tracking and flight ----------------------------
do
    local tabT = tabFrames.Tricks
    local function turnToward(cur, goal, rate, dt)
        local diff = ((goal - cur + math.pi) % (2 * math.pi)) - math.pi
        return cur + diff * (1 - math.exp(-rate * dt))
    end
    local function ease(cur, goal, rate, dt) return cur + (goal - cur) * (1 - math.exp(-rate * dt)) end
    local function aimAngles(m, dir, maxYaw, minPitch, maxPitch, free)
        local d = m.Part0.CFrame:VectorToObjectSpace(dir)
        local yaw = math.atan2(-d.X, -d.Z)
        if not free and math.abs(yaw) > math.rad(115) then return 0, 0 end
        local pitch = math.asin(math.clamp(d.Y, -1, 1))
        return math.clamp(yaw, -maxYaw, maxYaw), math.clamp(pitch, minPitch, maxPitch)
    end
    -- rotation given in the parent part's axes, applied about the joint
    local function rotateJoint(m, yaw, pitch)
        if math.abs(yaw) + math.abs(pitch) < 0.002 then return end
        local R = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
        local c0 = m.C0.Rotation
        m.Transform = (c0:Inverse() * R * c0) * m.Transform
    end

    local function flyDrive(F, dt)
        local cam = workspace.CurrentCamera
        if not cam then return end
        local look, right = cam.CFrame.LookVector, cam.CFrame.RightVector
        local flatLook = Vector3.new(look.X, 0, look.Z)
        flatLook = flatLook.Magnitude > 1e-3 and flatLook.Unit or Vector3.new(0, 0, -1)
        local flatRight = Vector3.new(right.X, 0, right.Z)
        flatRight = flatRight.Magnitude > 1e-3 and flatRight.Unit or Vector3.new(1, 0, 0)
        local typing = UserInputService:GetFocusedTextBox() ~= nil
        local md = F.hum.MoveDirection
        if md.Magnitude < 0.01 and not typing then
            local x, z = 0, 0
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then x += 1 end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then x -= 1 end
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then z += 1 end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then z -= 1 end
            md = flatRight * x + flatLook * z
        end
        local fwd, side = md:Dot(flatLook), md:Dot(flatRight)
        local up = 0
        if not typing then
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) or UserInputService:IsKeyDown(Enum.KeyCode.E) then up += 1 end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.Q) then up -= 1 end
        end
        local dir = look * fwd + right * side + Vector3.yAxis * up
        if dir.Magnitude > 1 then dir = dir.Unit end
        F.vel = F.vel:Lerp(dir * F.speed, 1 - math.exp(-6 * dt))
        if F.vel.Magnitude < 0.01 then F.vel = Vector3.zero end
        F.yaw = turnToward(F.yaw, math.atan2(-flatLook.X, -flatLook.Z), 8, dt)
        F.cf = CFrame.new(F.cf.Position + F.vel * dt) * CFrame.Angles(0, F.yaw, 0)
        F.root.CFrame = F.cf
        F.root.AssemblyLinearVelocity = Vector3.zero
        F.root.AssemblyAngularVelocity = Vector3.zero
    end

    tricksStep = function(dt)
        local cam = workspace.CurrentCamera
        -- head tracking
        local H, m = tricks.head, engine.motors.Head
        if m and m.Part0 and not live.pose.Head then
            local gy, gp = 0, 0
            if H.on and cam then
                local dir = cam.CFrame.LookVector
                if H.mode == "mouse" then
                    local target = hitPoint()
                    local from = m.Part1 and m.Part1.Position or m.Part0.Position
                    if target and (target - from).Magnitude > 0.1 then dir = (target - from).Unit end
                end
                if H.free then gy, gp = aimAngles(m, dir, math.pi, math.rad(-85), math.rad(85), true)
                else gy, gp = aimAngles(m, dir, math.rad(75), math.rad(-50), math.rad(60), false) end
            end
            H.yaw, H.pitch = turnToward(H.yaw, gy, 12, dt), ease(H.pitch, gp, 12, dt)
            rotateJoint(m, H.yaw, H.pitch)
        end
        -- torso tracking
        local B = tricks.torso
        local tm = engine.motors[engine.rig == "R6" and "Torso" or "UpperTorso"]
        if tm and tm.Part0 and not live.pose[tm.Part1.Name] then
            local gy, gp = 0, 0
            if B.on and cam then
                local k = B.strength
                if B.free then
                    gy, gp = aimAngles(tm, cam.CFrame.LookVector, math.pi, math.rad(-80), math.rad(80), true)
                else
                    local yaw, pitch = aimAngles(tm, cam.CFrame.LookVector, math.rad(60), math.rad(-80), math.rad(80), false)
                    gy, gp = yaw * k, math.clamp(pitch * 0.4, math.rad(-22), math.rad(22)) * k
                end
            end
            B.yaw, B.pitch = turnToward(B.yaw, gy, 8, dt), ease(B.pitch, gp, 8, dt)
            rotateJoint(tm, B.yaw, B.pitch)
        end
        -- flight
        local F = tricks.fly
        if F.on then
            if F.root and F.root.Parent and F.hum and F.hum.Parent then flyDrive(F, dt)
            else tricksStop() end
        end
    end

    local flySwitch
    tricksStop = function()
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
    ctl.setFly = function(v)
        local F = tricks.fly
        if not v then tricksStop(); return end
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
            setStatus("Flying: WASD, Space up, Ctrl down")
        end
        if engine.copy then go() else turnOn(go) end
    end

    toggleRow(tabT, "Head follows camera", 0, false, function(v) tricks.head.on = v end)
    label(tabT, "Head aims at", 4, 32, 120, 26, {TextColor3 = C.dim, TextSize = 12})
    local modeBtns = {}
    for i, mode in ipairs({"camera", "mouse"}) do
        modeBtns[mode] = button(tabT, mode == "camera" and "Camera" or "Mouse", 130 + (i - 1) * 114, 32, 108, 26, function()
            tricks.head.mode = mode
            for n, b in pairs(modeBtns) do setSelected(b, n == mode) end
        end)
        setSelected(modeBtns[mode], tricks.head.mode == mode)
    end
    toggleRow(tabT, "Free look (full turn)", 64, false, function(v) tricks.head.free = v end)
    toggleRow(tabT, "Torso follows camera", 106, false, function(v) tricks.torso.on = v end)
    sliderRow(tabT, "Strength", 138, 0.25, 2, tricks.torso.strength, "%.2f", function(v) tricks.torso.strength = v end).set(tricks.torso.strength, false)
    toggleRow(tabT, "Torso free look", 168, false, function(v) tricks.torso.free = v end)
    flySwitch = toggleRow(tabT, "Fly", 210, false, function(v) ctl.setFly(v) end)
    sliderRow(tabT, "Fly speed", 242, 10, 200, tricks.fly.speed, "%.0f", function(v) tricks.fly.speed = math.floor(v + 0.5) end).set(tricks.fly.speed, false)
    label(tabT, "Fly: WASD along the camera, Space / E up, Ctrl / Q down. Turn it off to drop back down. Head and torso tracking add on top of whatever animation is playing.",
        4, 270, 350, 44, {TextSize = 10, TextColor3 = C.dim, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top})
end

-- Footer (speed / stop / loop) ----------------------------------------
label(panel, "Speed", 18, 466, 46, 22, {TextColor3 = C.dim, TextSize = 12})
local speedVal = label(panel, string.format("%.2fx", settings.speed), 316, 466, 58, 22, {TextColor3 = C.dim, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right})
local speedSlider = slider(panel, 70, 470, 236, 0.1, 3, settings.speed, function(v)
    settings.speed = math.floor(v * 20 + 0.5) / 20
    speedVal.Text = string.format("%.2fx", settings.speed)
    saveSoon()
end)
local function setSpeed(v)
    v = math.clamp(math.floor(v * 20 + 0.5) / 20, 0.1, 3)
    settings.speed = v
    speedSlider.set(v, false)
    speedVal.Text = string.format("%.2fx", v)
    saveSoon()
    setStatus(string.format("Speed %.2fx", v))
end
button(panel, "■ Stop emote", 18, 496, 110, 28, function() stopEmote() end)
label(panel, "Loop", 146, 496, 36, 28, {TextColor3 = C.dim, TextSize = 12})
switch(panel, UDim2.fromOffset(190, 498), settings.loop, function(v)
    settings.loop = v
    if engine.emote then engine.emote.loop = v and not engine.emote.anim.hold end
    saveSoon()
end)

----------------------------------------------------------------------
-- Hotkeys + lifecycle
----------------------------------------------------------------------
connect(UserInputService.InputBegan, function(input, processed)
    if destroyed then return end
    if ui.bindingEmote then
        if input.UserInputType == Enum.UserInputType.Keyboard then
            local key, k = ui.bindingEmote, input.KeyCode.Name
            ui.bindingEmote = nil
            if input.KeyCode == Enum.KeyCode.Escape then
                -- cancelled
            elseif input.KeyCode == Enum.KeyCode.Backspace or input.KeyCode == Enum.KeyCode.Delete then
                data.binds[key] = nil
                setStatus("Bind cleared")
            elseif k == settings.keyToggle or k == settings.keyGui or k == settings.keyStop
                or k == settings.keySpeedDown or k == settings.keySpeedUp or k == settings.keySpeedReset
                or k == settings.keyPause or k == settings.keyRewind or k == settings.keyReverse or k == settings.keyDrive then
                setStatus(k .. " is already a hotkey")
            else
                for other, boundKey in pairs(data.binds) do if boundKey == k then data.binds[other] = nil end end
                data.binds[key] = k
                local entry = findEntry(key)
                setStatus(k .. " = " .. (entry and entry.name or "emote"))
            end
            saveData()
            for entryKey, b in pairs(ui.ebtn) do
                b.Text = keyLabel(data.binds[entryKey])
                b.TextColor3 = data.binds[entryKey] and C.accent or C.dim
            end
        end
        return
    end
    if ui.binding then
        if input.UserInputType == Enum.UserInputType.Keyboard then
            if input.KeyCode ~= Enum.KeyCode.Escape then settings[ui.binding] = input.KeyCode.Name; saveSoon() end
            ui.bindBtn[ui.binding].Text = settings[ui.binding]
            ui.binding = nil
            if liveRefresh then liveRefresh() end
        end
        return
    end
    if processed or UserInputService:GetFocusedTextBox() then return end
    if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
    local k = input.KeyCode.Name
    if k == settings.keyToggle then
        if bodyReanim.Get() then turnOff() else turnOn() end
    elseif k == settings.keyGui then
        if panel.Visible then
            tween(panelScale, {Scale = .9}, TweenInfo.new(.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In))
            task.delay(.15, function() if not destroyed then panel.Visible = false end end)
        else
            panel.Visible = true
            panelScale.Scale = .9
            tween(panelScale, {Scale = 1}, TweenInfo.new(.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
        end
    elseif k == settings.keyStop then
        stopEmote()
    elseif k == settings.keySpeedDown then
        setSpeed(settings.speed - 0.1)
    elseif k == settings.keySpeedUp then
        setSpeed(settings.speed + 0.1)
    elseif k == settings.keySpeedReset then
        setSpeed(1)
    elseif k == settings.keyPause then
        ctl.togglePause()
    elseif k == settings.keyRewind then
        ctl.restart()
    elseif k == settings.keyReverse then
        ctl.reverse()
    elseif k == settings.keyDrive then
        ctl.setDrive(true)
    else
        -- emote binds: press to play, press again to stop
        for entryKey, keyName in pairs(data.binds) do
            if keyName == k then
                local entry = findEntry(entryKey)
                if entry then
                    if engine.emote and engine.emote.key == entry.key then stopEmote() else playEntry(entry) end
                end
                break
            end
        end
    end
end)
connect(UserInputService.InputEnded, function(input)
    if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode.Name == settings.keyDrive then ctl.setDrive(false) end
end)
connect(UserInputService.JumpRequest, function()
    if settings.stopOnMove and engine.emote and engine.emote.age > 0.3 then engine.emote = nil end
end)
-- Keep the normal Roblox animations (Animate script, walk/idle/jump tracks) from playing on the real
-- character while reanimated. The rig is driven only by the emote/state engine.
connect(RunService.Heartbeat, function()
    if destroyed or not bodyReanim.Get() then return end
    local char = player.Character
    if not char then return end
    local animate = char:FindFirstChild("Animate")
    if animate and animate:IsA("LocalScript") and not animate.Disabled then animate.Disabled = true end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local animator = hum and hum:FindFirstChildOfClass("Animator")
    if animator then
        for _, track in ipairs(animator:GetPlayingAnimationTracks()) do track:Stop(0) end
    end
end)
-- (CharacterRemoving is ignored on purpose: this core swaps player.Character itself.)

local cleanup
cleanup = function()
    if destroyed then return end
    destroyed = true
    saveData()
    engineStop()
    bodyReanim.Stop()
    for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    if shared.ReanimlolCleanup == cleanup then shared.ReanimlolCleanup = nil end
    gui:Destroy()
end
shared.ReanimlolCleanup = cleanup

refreshChips()
rebuildList()
refreshStateRows()
updateRecUI()
return {Destroy = cleanup}
