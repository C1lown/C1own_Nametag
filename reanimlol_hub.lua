-- Author: c1lown
-- cookie hub: reanimlol GUI + commands panel

----------------------------------------------------------------------
-- Theme helpers (hue shift based; saved between runs)
----------------------------------------------------------------------
local Theme = {hue = 0.10} -- 0.10 turns the crimson base into cookie brown/orange
local THEMES = {
    {"Cookie", 0.10}, {"Crimson", 0}, {"Ember", 0.06}, {"Gold", 0.11}, {"Emerald", 0.37}, {"Teal", 0.50},
    {"Ocean", 0.60}, {"Indigo", 0.70}, {"Violet", 0.77}, {"Pink", 0.88},
}
do
    local g = getgenv and getgenv() or _G
    if type(g.CookieThemeHue) == "number" then
        Theme.hue = g.CookieThemeHue
    elseif type(readfile) == "function" and type(isfile) == "function" then
        pcall(function()
            if isfile("CookieHub_theme.txt") then Theme.hue = tonumber(readfile("CookieHub_theme.txt")) or 0.10 end
        end)
    end
end
local function shiftC(c, d)
    if d == 0 then return c end
    local h, s, v = c:ToHSV()
    if s < 0.02 then return c end
    return Color3.fromHSV((h + d) % 1, s, v)
end
local function hc(c) return shiftC(c, Theme.hue) end
local function recolor(root, d)
    if d % 1 == 0 then return end
    for _, o in ipairs(root:GetDescendants()) do
        if o:GetAttribute("nohue") then continue end
        if o:IsA("GuiObject") then o.BackgroundColor3 = shiftC(o.BackgroundColor3, d) end
        if o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox") then o.TextColor3 = shiftC(o.TextColor3, d) end
        if o:IsA("TextBox") then o.PlaceholderColor3 = shiftC(o.PlaceholderColor3, d) end
        if o:IsA("ImageLabel") or o:IsA("ImageButton") then o.ImageColor3 = shiftC(o.ImageColor3, d) end
        if o:IsA("ScrollingFrame") then o.ScrollBarImageColor3 = shiftC(o.ScrollBarImageColor3, d) end
        if o:IsA("UIStroke") then o.Color = shiftC(o.Color, d) end
        if o:IsA("UIGradient") then
            local kps = {}
            for i, k in ipairs(o.Color.Keypoints) do kps[i] = ColorSequenceKeypoint.new(k.Time, shiftC(k.Value, d)) end
            o.Color = ColorSequence.new(kps)
        end
        local b = o:GetAttribute("base")
        if typeof(b) == "Color3" then o:SetAttribute("base", shiftC(b, d)) end
    end
end

----------------------------------------------------------------------
-- Cookie art: drawn cookies (dough, baked rim, chocolate chips) placed on the GUI panels
----------------------------------------------------------------------
local Cookie = {layers = {}, floaters = {}, halos = {}, on = true, image = ""} -- image: "rbxassetid://<id>" to use a real picture
local function nh(o) o:SetAttribute("nohue", true); return o end -- theme hue shifts skip cookie parts
local function cnew(class, props, parent)
    local o = Instance.new(class)
    if o:IsA("GuiObject") then o.BorderSizePixel = 0 end
    for k, v in pairs(props) do o[k] = v end
    o.Parent = parent
    return nh(o)
end
local function cround(o, scale)
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(scale or .5, 0); c.Parent = o
    return o
end

-- d = diameter px, alpha = 0 opaque .. 1 invisible, glow = warm halo ring
function Cookie.make(parent, d, alpha, glow, rng)
    rng = rng or Random.new()
    local root = cnew("Frame", {Size = UDim2.fromOffset(d, d), BackgroundTransparency = 1}, parent)
    if glow then
        local halo = cround(cnew("Frame", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1}, root))
        for _, spec in ipairs({{4, .55}, {9, .78}, {16, .92}}) do
            local hs = cnew("UIStroke", {Color = Color3.fromRGB(255, 188, 84), Thickness = spec[1], Transparency = spec[2],
                ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, halo)
            Cookie.halos[#Cookie.halos + 1] = {hs, spec[2]}
        end
    end
    local cg = cnew("CanvasGroup", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, GroupTransparency = alpha or 0}, root)
    if Cookie.image ~= "" then
        cnew("ImageLabel", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = Cookie.image,
            ScaleType = Enum.ScaleType.Fit}, cg)
        return root
    end
    local function disc(scale, color, ox, oy)
        return cround(cnew("Frame", {AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5 + (ox or 0), .5 + (oy or 0)),
            Size = UDim2.fromScale(scale, scale), BackgroundColor3 = color}, cg))
    end
    disc(1, Color3.fromRGB(168, 108, 52))               -- over-baked rim
    disc(.9, Color3.fromRGB(207, 150, 82))              -- dough
    disc(.7, Color3.fromRGB(224, 172, 104), -.02, -.03) -- puffed centre
    disc(.34, Color3.fromRGB(236, 190, 124), -.08, -.1) -- highlight
    for _ = 1, 3 do -- tiny surface cracks
        local a, r = rng:NextNumber(0, math.pi * 2), rng:NextNumber(.12, .3)
        cnew("Frame", {AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5 + math.cos(a) * r, .5 + math.sin(a) * r),
            Size = UDim2.fromScale(.16, .02), Rotation = rng:NextInteger(0, 179), BackgroundColor3 = Color3.fromRGB(176, 118, 58),
            BackgroundTransparency = .35}, cg)
    end
    local chips = {}
    for _ = 1, rng:NextInteger(6, 9) do -- chocolate chips, kept from piling up
        for _try = 1, 8 do
            local a = rng:NextNumber(0, math.pi * 2)
            local r = math.sqrt(rng:NextNumber()) * .34
            local x, y = math.cos(a) * r, math.sin(a) * r
            local ok = true
            for _, c in ipairs(chips) do if (c[1] - x) ^ 2 + (c[2] - y) ^ 2 < .016 then ok = false; break end end
            if ok then
                chips[#chips + 1] = {x, y}
                local sz = rng:NextNumber(.12, .19)
                local chip = cround(cnew("Frame", {AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5 + x, .5 + y),
                    Size = UDim2.fromScale(sz, sz * rng:NextNumber(.7, .95)), Rotation = rng:NextInteger(0, 179),
                    BackgroundColor3 = Color3.fromRGB(70, 38, 20)}, cg), .38)
                cnew("Frame", {Position = UDim2.fromScale(.14, .12), Size = UDim2.fromScale(.38, .24),
                    BackgroundColor3 = Color3.fromRGB(112, 66, 36)}, chip)
                break
            end
        end
    end
    return root
end

-- A faint field of slowly drifting cookies inside a panel (clipped to its rounded corners).
-- w, h = the panel's size in pixels. Sits behind everything else in the panel.
function Cookie.layer(frame, radius, w, h, count, minD, maxD, alpha)
    local rng = Random.new()
    local cg = cnew("CanvasGroup", {Name = "CookieLayer", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
        GroupTransparency = alpha, ZIndex = 0, Active = false, Visible = Cookie.on}, frame)
    local gc = Instance.new("UICorner"); gc.CornerRadius = UDim.new(0, radius); gc.Parent = cg
    Cookie.layers[#Cookie.layers + 1] = cg
    for _ = 1, count do
        local d = rng:NextInteger(minD, maxD)
        local k = Cookie.make(cg, d, 0, false, rng)
        k.AnchorPoint = Vector2.new(.5, .5)
        k.Rotation = rng:NextInteger(0, 359)
        local f = {f = k, x = rng:NextNumber(0, w), y = rng:NextNumber(0, h), w = w, d = d,
            vx = rng:NextNumber(3, 9) * (rng:NextInteger(0, 1) == 0 and -1 or 1), spin = rng:NextNumber(-8, 8)}
        k.Position = UDim2.fromOffset(f.x, f.y)
        Cookie.floaters[#Cookie.floaters + 1] = f
    end
    if not Cookie.conn then
        Cookie.conn = game:GetService("RunService").Heartbeat:Connect(function(dt)
            local list, alive = Cookie.floaters, 0
            for i = #list, 1, -1 do
                local f = list[i]
                if not f.f.Parent then
                    table.remove(list, i)
                else
                    alive += 1
                    f.x += f.vx * dt
                    if f.x > f.w + f.d then f.x = -f.d elseif f.x < -f.d then f.x = f.w + f.d end
                    f.f.Position = UDim2.fromOffset(f.x, f.y)
                    f.f.Rotation = f.f.Rotation + f.spin * dt
                end
            end
            for i = #Cookie.halos, 1, -1 do
                local e = Cookie.halos[i]
                if e[1].Parent then e[1].Transparency = math.clamp(e[2] - 0.14 * (0.5 + 0.5 * math.sin(os.clock() * 2.2)), 0, 1)
                else table.remove(Cookie.halos, i) end
            end
            if alive == 0 and #Cookie.halos == 0 then Cookie.conn:Disconnect(); Cookie.conn = nil end
        end)
    end
    return cg
end
function Cookie.setVisible(v)
    for i = #Cookie.layers, 1, -1 do
        local l = Cookie.layers[i]
        if l.Parent then l.Visible = v else table.remove(Cookie.layers, i) end
    end
end

local function ReanimlolModule()
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
  clone.Name = "ReanimlolBody"
  -- one pass over the clone: drop tools and scripts, make it invisible, and check it has Motor6D joints
  local humanoid, motors = nil, false
  for _, c in ipairs(clone:GetChildren()) do
    if c:IsA("Tool") then c:Destroy()
    elseif not humanoid and c:IsA("Humanoid") then humanoid = c end
  end
  if not humanoid then clone:Destroy(); return "Cloned character has no humanoid." end
  for _, d in ipairs(clone:GetDescendants()) do
    if d:IsA("LuaSourceContainer") then d:Destroy()
    elseif d:IsA("BasePart") then d.Transparency = 1; d.CanCollide = false
    elseif d:IsA("Decal") or d:IsA("Texture") then d.Transparency = 1
    elseif d:IsA("BillboardGui") then d.Enabled = false
    elseif d:IsA("Motor6D") then motors = true end
  end
  humanoid.RequiresNeck = false
  humanoid.BreakJointsOnDeath = false
  humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
  local ff = clone:FindFirstChildWhichIsA("ForceField")
  if ff then ff:Destroy() end
  return clone, motors
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
    -- the remote lookup (which can wait on the server) and the controls module are cached after the first start
    local remote, argsOn, isLocal, argsOff
    local rc = S.ragCache
    if rc and rc.remote.Parent then
      remote, argsOn, isLocal, argsOff = rc.remote, rc.on, rc.isLocal, rc.off
    else
      remote, argsOn, isLocal = findRagdoll(true)
      assert(remote, "This game has no known ragdoll remote, so this core can't run here.")
      local _, off = findRagdoll(false)
      argsOff = off or argsOn
      S.ragCache = {remote = remote, on = argsOn, off = argsOff, isLocal = isLocal}
    end
    assert(rev == S.rev, "Start cancelled.")
    local controls = S.controlsCache
    if not controls then
      local scripts = player:FindFirstChild("PlayerScripts")
      local module = scripts and scripts:FindFirstChild("PlayerModule")
      if module and module:IsA("ModuleScript") then
        local loaded, value = pcall(function() return require(module):GetControls() end)
        if loaded and value and type(value.GetMoveVector) == "function" then controls = value; S.controlsCache = value end
      end
    end
    local copy, motors = cloneCharacter(character)
    assert(typeof(copy) == "Instance", tostring(copy))
    local copyHumanoid, copyRoot = copy:FindFirstChildOfClass("Humanoid"), copy:FindFirstChild("HumanoidRootPart")
    if not (copyHumanoid and copyRoot and motors) then copy:Destroy() end
    assert(copyHumanoid and copyRoot, "Cloned rig is incomplete.")
    assert(motors, "This rig needs Motor6D joints.")
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
      -- hide mode: the real ragdolled body is parked under the map while you keep controlling the clone above
      local off = Vector3.zero
      if s.hideReq then
        local d = math.min(s.hideReq, copyRoot.Position.Y - (Workspace.FallenPartsDestroyHeight + 30)) -- stay above the void kill height
        if d >= 10 then off = Vector3.new(0, -d, 0) end
      end
      for _, link in ipairs(s.links) do
        if link.part.Parent and link.base.Parent then
          link.part.CFrame = link.base.CFrame + off
          link.part.AssemblyLinearVelocity = Vector3.zero
          link.part.AssemblyAngularVelocity = Vector3.zero
        end
      end
    end
    s.follow = follow
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
 Realign = function()
   local s = S.session
   if not s or not s.follow then return false end
   for _, link in ipairs(s.links) do
     if link.part.Parent then
       link.part.AssemblyLinearVelocity = Vector3.zero
       link.part.AssemblyAngularVelocity = Vector3.zero
     end
   end
   pcall(s.follow)
   pcall(function() if s.humanoid.Health < s.humanoid.MaxHealth then s.humanoid.Health = s.humanoid.MaxHealth end end)
   return true
 end,
 SetHide = function(depth) local s = S.session; if not s then return false end s.hideReq = depth; return true end,
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
    speed = 1, loop = true, stopOnMove = false, walkSync = true, blend = 0.35, recordRate = 20,
    noclip = true, keyToggle = "RightControl", keyGui = "RightShift", keyStop = "X",
    keySpeedDown = "Minus", keySpeedUp = "Equals", keySpeedReset = "Zero",
    keyPause = "Y", keyRewind = "U", keyReverse = "I", keyDrive = "LeftAlt",
    speedBinds = {},
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
if settings.blend == 0.15 then settings.blend = 0.35 end -- old default -> new crossfade default
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
    if curve[1].time <= time then
        -- binary search for the last key at or before `time` (long recordings have hundreds of keys)
        local lo, hi = 1, n
        while lo < hi do
            local mid = (lo + hi + 1) // 2
            if curve[mid].time <= time then lo = mid else hi = mid - 1 end
        end
        a, b = curve[lo], curve[lo + 1]
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
    elseif a.style ~= "Linear" and styles[a.style] then -- Linear needs no engine call
        alpha = TweenService:GetValue(alpha, styles[a.style], directions[a.direction] or Enum.EasingDirection.InOut)
    end
    if alpha <= 0 then return a.value end
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
for k, v in pairs(C) do C[k] = shiftC(v, Theme.hue) end
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
Cookie.layer(panel, 14, PANEL_W, PANEL_H, 18, 40, 90, .82)
do
    local stroke = Instance.new("UIStroke")
    stroke.Color, stroke.Thickness, stroke.Transparency, stroke.ApplyStrokeMode = C.stroke, 1, .45, Enum.ApplyStrokeMode.Border
    stroke.Parent = panel
    local grad = Instance.new("UIGradient")
    grad.Rotation = 90
    grad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, hc(Color3.fromRGB(110, 14, 24))),
        ColorSequenceKeypoint.new(0.45, hc(Color3.fromRGB(58, 8, 14))),
        ColorSequenceKeypoint.new(1, hc(Color3.fromRGB(24, 3, 6))),
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
local title = label(dragBar, "cookie reanim", 18, 0, 200, BAR_H, {Font = Enum.Font.GothamBold, TextSize = 18,
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
    if not sticky and text ~= "cookie reanim" then
        task.delay(3, function() if t == statusToken and not destroyed then title.Text = "cookie reanim" end end)
    end
end

local turnOn, turnOff, playEntry, stopEmote
-- window buttons: minimize (collapses to the title bar) and close, round like Novoline's
local function barButton(rightOffset, glyph, cb)
    local b = T("TextButton", {Size = UDim2.fromOffset(28, 28), Position = UDim2.new(1, -rightOffset - 28, 0.5, -14), Text = glyph,
        TextSize = 15, TextTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = .82, ZIndex = 20}, panel)
    corner(b, 14)
    b.MouseEnter:Connect(function() tween(b, {BackgroundTransparency = .6}, TweenInfo.new(.15)) end)
    b.MouseLeave:Connect(function() tween(b, {BackgroundTransparency = .82}, TweenInfo.new(.2)) end)
    b.Activated:Connect(cb)
    return b
end
local closeBtn = barButton(14, "X", function() if shared.ReanimlolCleanup then shared.ReanimlolCleanup() end end)
local minimized = false
barButton(14 + 28 + 4, "-", function()
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
local engine = {motors = {}, stateAnims = {}, gen = {}, token = 0, fadeT = 1, snapshot = {}, baked = {}, fitted = {}, parts = {}, collide = {}, prev = nil}
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

-- Fit a clip to YOUR avatar: converts clips made for the other rig type (R6 <-> R15, part by part, with the
-- joint-axis difference handled) and scales any joint translation (root bob, stretch, reach) to your body height.
-- Recordings made on your own avatar (own = true) are left alone. Toggle with the hub command "fitclips".
local fitClip
do
    local TO_R6 = {Torso = "LowerTorso", Head = "Head", ["Left Arm"] = "LeftUpperArm", ["Right Arm"] = "RightUpperArm",
        ["Left Leg"] = "LeftUpperLeg", ["Right Leg"] = "RightUpperLeg"} -- R6 part <- R15 source part
    local TO_R15 = {LowerTorso = "Torso", Head = "Head", LeftUpperArm = "Left Arm", RightUpperArm = "Right Arm",
        LeftUpperLeg = "Left Leg", RightUpperLeg = "Right Leg"} -- R15 part <- R6 source part
    local R6_ARM_R = CFrame.new(0, 0, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0)
    local R6_ARM_L = CFrame.new(0, 0, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0)
    local R6_UP = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0)
    local R6_C0_ROT = {Torso = R6_UP, Head = R6_UP, ["Right Arm"] = R6_ARM_R, ["Left Arm"] = R6_ARM_L,
        ["Right Leg"] = R6_ARM_R, ["Left Leg"] = R6_ARM_L} -- default R6 joint C0 rotations (R15 joints have none)
    local function engineScale()
        local h, r = engine.hum, engine.root
        if not (h and r) then return 1 end
        local height = engine.rig == "R6" and 3 * (r.Size.Y / 2) or (h.HipHeight + r.Size.Y / 2)
        return math.clamp(height / 3, 0.25, 6) -- 3 studs = the default avatar
    end
    fitClip = function(clip)
        if not clip or clip.own or type(clip.curves) ~= "table" or shared.ReanimlolFit == false then return clip end
        local cached = engine.fitted[clip]
        if cached then return cached end
        local rig, scale = engine.rig, engineScale()
        local srcRig = clip.rig or rig
        local out = clip
        if srcRig ~= rig or math.abs(scale - 1) > 0.02 then
            out = {curves = {}, duration = clip.duration, looped = clip.looped, hold = clip.hold, rig = rig, own = true}
            local map = nil
            if srcRig ~= rig then map = (rig == "R6") and TO_R6 or TO_R15 end
            for partName, motor in pairs(engine.motors) do
                local srcName = map and map[partName] or partName
                local curve = clip.curves[srcName]
                if not curve and map and partName == "Torso" then curve = clip.curves.UpperTorso end
                if curve then
                    local rt = motor.C0.Rotation
                    local rs = (srcRig == "R6" and R6_C0_ROT[srcName]) or CFrame.identity
                    local nc = {}
                    for i, k in ipairs(curve) do
                        local pos, rot = k.value.Position, k.value.Rotation
                        local newRot, newPos
                        if srcRig == rig then
                            newRot, newPos = rot, pos * scale
                        else
                            newRot = rt:Inverse() * (rs * rot * rs:Inverse()) * rt
                            newPos = rt:Inverse():VectorToWorldSpace(rs:VectorToWorldSpace(pos)) * scale
                        end
                        nc[i] = {time = k.time, value = CFrame.new(newPos) * newRot, style = k.style, direction = k.direction}
                    end
                    out.curves[partName] = nc
                end
            end
        else
            out = clip
        end
        engine.fitted[clip] = out
        return out
    end
end
local function resolveRaw(entry)
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
local function resolveAnim(entry) return fitClip(resolveRaw(entry)) end

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
            local midFade = cur and engine.fadeT < settings.blend
            if cur and not midFade then
                -- crossfade: the old clip keeps playing underneath while the new one fades in
                engine.prev = {anim = cur.anim, t = cur.t, loop = cur.loop ~= false, rate = cur.rate or 1}
            else
                -- first start, or interrupted mid-fade: fade from the pose that is currently on screen
                engine.prev = nil
                for _, m in pairs(engine.motors) do engine.snapshot[m] = m.Transform end
            end
            engine.fadeT = 0
            cur = {src = src, anim = desired, t = 0}
            engine.current = cur
        end
        cur.loop, cur.rate = loop, rate
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
        local prev = engine.prev
        if alpha >= 1 then
            engine.prev = nil
            prev = nil
        elseif prev and not engine.paused then
            -- keep the outgoing clip moving during the fade
            prev.t += dt * settings.speed * prev.rate * engine.dir
            local pd = prev.anim.duration
            if prev.loop then prev.t = prev.t % pd else prev.t = math.clamp(prev.t, 0, pd) end
        end
        local ea = alpha * alpha * (3 - 2 * alpha) -- smoothstep
        for name, m in pairs(engine.motors) do
            local curve = desired.curves[name]
            local target = curve and sample(curve, t, dur, loop) or CFrame.identity
            if alpha < 1 then
                local from
                if prev then
                    local pc = prev.anim.curves[name]
                    from = pc and sample(pc, prev.t, prev.anim.duration, prev.loop) or CFrame.identity
                else
                    from = engine.snapshot[m] or target
                end
                target = from:Lerp(target, ea)
            end
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
    local override = shared.ReanimlolOverride
    if override then pcall(override, dt) end
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
    engine.fitted = {}
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
    engine.prev = nil
    rigLabel.Text = engine.rig
    for _, s in ipairs(STATES) do refreshState(s) end
    engine.conn = RunService.PreSimulation:Connect(engineStep)
end

local function engineStop()
    if engine.conn then engine.conn:Disconnect(); engine.conn = nil end
    if engine.partConn then engine.partConn:Disconnect(); engine.partConn = nil end
    engine.parts, engine.collide = {}, {}
    engine.copy, engine.hum, engine.root, engine.current, engine.emote = nil, nil, nil, nil, nil
    engine.prev = nil
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
        setStatus("cookie reanim")
        if after then after() end
    end)
end
turnOff = function()
    startRev += 1
    busy = false
    bodyReanim.Stop()
    mainSwitch.set(false)
    setStatus("cookie reanim")
end
bodyReanim.OnStopped(function()
    engineStop()
    if destroyed then return end
    rigLabel.Text = ""
    mainSwitch.set(false)
    setStatus("cookie reanim")
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
local function newClip() return {curves = {}, duration = 0, looped = true, rig = engine.rig, own = true} end

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
                            recorded = true, path = path,
                            clip = (function() local c = deserializeClip(tbl); c.own = true; return c end)()}
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
    BackgroundColor3 = hc(Color3.fromRGB(230, 40, 58)), BackgroundTransparency = .25}, tabBar)
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
label(tabG, "Fade", 4, 68, 50, 30)
local blendVal = label(tabG, string.format("%.2fs", settings.blend), 300, 68, 56, 30, {TextColor3 = C.dim, TextSize = 12})
slider(tabG, 60, 76, 232, 0, 1.5, settings.blend, function(v)
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
    label(tabP, "Speed binds", 4, 222, 200, 14, {TextSize = 11, TextColor3 = C.dim})
    local speedBox = box(tabP, "Speed", 0, 240, 70, 28)
    local pickBtn
    ui.speedPickText = function()
        if pickBtn then pickBtn.Text = ui.speedKey and keyLabel(ui.speedKey) or "Pick key" end
    end
    pickBtn = button(tabP, "Pick key", 76, 240, 168, 28, function()
        ui.bindingSpeed = true
        pickBtn.Text = "press key..."
    end)
    local speedChips = chipRow(tabP, 274)
    local function refreshSpeedChips()
        clearButtons(speedChips)
        local keys = {}
        for k in pairs(settings.speedBinds) do keys[#keys + 1] = k end
        table.sort(keys)
        for i, k in ipairs(keys) do
            local v = math.floor((tonumber(settings.speedBinds[k]) or 1) * 100 + 0.5) / 100
            chip(speedChips, keyLabel(k) .. " = " .. tostring(v) .. "x  ✕", false, i, function()
                settings.speedBinds[k] = nil
                saveSoon()
                refreshSpeedChips()
            end)
        end
    end
    button(tabP, "Add", 250, 240, 106, 28, function()
        local v = tonumber(speedBox.Text)
        if not v then setStatus("Type a speed first"); return end
        if not ui.speedKey then setStatus("Pick a key first"); return end
        v = math.clamp(math.floor(v * 20 + 0.5) / 20, 0.1, 3)
        settings.speedBinds[ui.speedKey] = v
        saveSoon()
        setStatus(keyLabel(ui.speedKey) .. " = " .. tostring(v) .. "x")
        speedBox.Text = ""
        ui.speedKey = nil
        ui.speedPickText()
        refreshSpeedChips()
    end)
    label(tabP, "Press a bound key to jump to that speed (0.1 - 3). Click a chip to remove it.",
        4, 304, 350, 12, {TextSize = 10, TextColor3 = C.dim})
    refreshSpeedChips()
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
local function isReservedKey(k)
    for _, name in ipairs({"keyToggle", "keyGui", "keyStop", "keySpeedDown", "keySpeedUp", "keySpeedReset",
        "keyPause", "keyRewind", "keyReverse", "keyDrive"}) do
        if settings[name] == k then return true end
    end
    for _, v in pairs(data.binds) do if v == k then return true end end
    return false
end
connect(UserInputService.InputBegan, function(input, processed)
    if destroyed then return end
    if ui.bindingSpeed then
        if input.UserInputType == Enum.UserInputType.Keyboard then
            ui.bindingSpeed = false
            local k = input.KeyCode.Name
            if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.Backspace then
                ui.speedKey = nil
            elseif isReservedKey(k) then
                ui.speedKey = nil
                setStatus(k .. " is already a hotkey")
            else
                ui.speedKey = k
            end
            ui.speedPickText()
        end
        return
    end
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
                or k == settings.keyPause or k == settings.keyRewind or k == settings.keyReverse or k == settings.keyDrive
                or settings.speedBinds[k] then
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
    elseif settings.speedBinds[k] then
        setSpeed(tonumber(settings.speedBinds[k]) or 1)
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
    shared.ReanimlolTheme = nil
    shared.ReanimlolTurnOn, shared.ReanimlolHide, shared.ReanimlolRefit, shared.ReanimlolRealign = nil, nil, nil, nil
    gui:Destroy()
end
shared.ReanimlolCleanup = cleanup

refreshChips()
rebuildList()
refreshStateRows()
updateRecUI()
shared.ReanimlolTurnOn = function(cb) turnOn(cb) end
shared.ReanimlolHide = function(depth) return bodyReanim.SetHide(depth) end
shared.ReanimlolRealign = function() return bodyReanim.Realign() end
shared.ReanimlolRefit = function()
    if not engine.copy then return end
    engine.fitted = {}
    for _, st in ipairs(STATES) do refreshState(st) end
end
shared.ReanimlolTheme = function(d)
    if destroyed then return end
    for k, v in pairs(C) do C[k] = shiftC(v, d) end
    recolor(gui, d)
end
return {Destroy = cleanup}
end

local function HubMain()
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local PathfindingService = game:GetService("PathfindingService")
local ContextActionService = game:GetService("ContextActionService")
local StarterGui = game:GetService("StarterGui")
local StatsService = game:GetService("Stats")
local Teams = game:GetService("Teams")
local lp = Players.LocalPlayer
local G = getgenv and getgenv() or _G
if type(G.C1lownHubCleanup) == "function" then pcall(G.C1lownHubCleanup) end

local destroyed = false
local conns, OFFS, LOOPS = {}, {}, {}
local function bind(sig, fn) local c = sig:Connect(fn); conns[#conns + 1] = c; return c end
local function off(fn) OFFS[#OFFS + 1] = fn end
local say = function() end

local function startLoop(key, interval, fn) LOOPS[key] = {fn = fn, interval = interval, t = 0} end
local function stopLoop(key) LOOPS[key] = nil end
bind(RunService.Heartbeat, function(dt)
    for _, l in pairs(LOOPS) do
        l.t = l.t + dt
        if l.t >= l.interval then l.t = 0; pcall(l.fn) end
    end
end)

local function hum() local c = lp.Character; return c and c:FindFirstChildOfClass("Humanoid") end
local function root() local c = lp.Character; return c and c:FindFirstChild("HumanoidRootPart") end
local function num(s, d) local n = tonumber(s); if n == nil then return d end; return n end
local function weak() return setmetatable({}, {__mode = "k"}) end
local function typing() return UIS:GetFocusedTextBox() ~= nil end
local function clip(text)
    if type(setclipboard) == "function" then setclipboard(tostring(text)); return true end
    if type(toclipboard) == "function" then toclipboard(tostring(text)); return true end
    return false
end
local function findPlayer(q)
    q = tostring(q or ""):lower()
    if q == "" then return nil end
    if q == "me" then return lp end
    local partial
    for _, p in ipairs(Players:GetPlayers()) do
        local n, d = p.Name:lower(), p.DisplayName:lower()
        if n == q or d == q then return p end
        if not partial and (n:sub(1, #q) == q or d:sub(1, #q) == q) then partial = p end
    end
    return partial
end
local function targetRoot(q)
    local p = findPlayer(q)
    local c = p and p.Character
    return p, c and c:FindFirstChild("HumanoidRootPart")
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local function mouseHit()
    local cam = workspace.CurrentCamera
    if not cam then return nil end
    local mp = UIS:GetMouseLocation()
    local r = cam:ViewportPointToRay(mp.X, mp.Y)
    rayParams.FilterDescendantsInstances = {lp.Character}
    local hit = workspace:Raycast(r.Origin, r.Direction * 1000, rayParams)
    return hit and hit.Position
end
-- shared by invis, ftp and tptool: while invisible, teleporting moves the hidden body sideways under the map
-- (same depth below the spot you pick) instead of popping it up into view
local invisState = {}
local function teleportTo(pos)
    local r = root()
    if not (r and pos) then return end
    local I = invisState
    if I.on and I.depth then
        local y = math.max(pos.Y - I.depth, workspace.FallenPartsDestroyHeight + 30)
        I.y, I.camY = y, pos.Y + 3
        r.CFrame = CFrame.new(pos.X, y, pos.Z) * (r.CFrame - r.CFrame.Position)
        r.AssemblyLinearVelocity = Vector3.new()
    else
        r.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
    end
end

----------------------------------------------------------------------
-- Command registry
----------------------------------------------------------------------
local CMDS, LIST = {}, {}
local function def(cat, name, desc, args, fn, aliases)
    local c = {name = name, cat = cat, desc = desc, args = args, fn = fn}
    CMDS[name] = c
    LIST[#LIST + 1] = c
    for _, a in ipairs(aliases or {}) do CMDS[a] = c end
    return c
end
local function pair(cat, onName, offName, descOn, descOff, args, onFn, offFn, onAliases, offAliases)
    def(cat, onName, descOn, args, onFn, onAliases)
    def(cat, offName, descOff, nil, offFn, offAliases)
    off(offFn)
end

local lastLine
local runLine
local SCRIPT_BUTTONS = {
    {
        name = "ANTIVC",
        desc = "Doesnt allow you to be VC banned",
        source = [[ loadstring(game:HttpGet("https://scriptblox.com/raw/Universal-Script-Anti-Vc-Ban-225666"))() ]],
            
    },
    {
        name = "example2",
        desc = "Runs a Lua function directly",
        args = "[text]",
        run = function(args)
            print("you typed:", table.concat(args, " "))
        end,
    },
    -- To load a script from a link you trust:
    -- {name = "loader", desc = "Loads my script", source = [[ loadstring(game:HttpGet("https://example.com/script.lua"))() ]]},
}
for _, b in ipairs(SCRIPT_BUTTONS) do
    def("Scripts", tostring(b.name):lower(), b.desc or "Custom script", b.args, function(args)
        if b.run then return b.run(args) end
        if type(loadstring) ~= "function" then say("Executor has no loadstring"); return end
        local fn, err = loadstring(b.source or "")
        if not fn then say("Script error: " .. tostring(err):sub(1, 60)); return end
        fn()
    end)
end

----------------------------------------------------------------------
-- Movement
----------------------------------------------------------------------
do
    local fly = {speed = 1}
    local function stopFly()
        if fly.conn then fly.conn:Disconnect(); fly.conn = nil end
        if fly.bv then fly.bv:Destroy(); fly.bv = nil end
        if fly.bg then fly.bg:Destroy(); fly.bg = nil end
        local h = hum()
        if fly.active and h then h.PlatformStand = false end
        fly.active = false
    end
    local function startFly(speed)
        stopFly()
        local r, h = root(), hum()
        if not (r and h) then say("Character not ready"); return end
        if speed then fly.speed = speed end
        fly.active = true
        local bv = Instance.new("BodyVelocity")
        bv.MaxForce = Vector3.new(1e9, 1e9, 1e9)
        bv.Velocity = Vector3.new()
        bv.Parent = r
        local bg = Instance.new("BodyGyro")
        bg.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
        bg.P = 1e4
        bg.CFrame = r.CFrame
        bg.Parent = r
        fly.bv, fly.bg = bv, bg
        h.PlatformStand = true
        fly.conn = RunService.RenderStepped:Connect(function()
            local cam = workspace.CurrentCamera
            if not (r.Parent and cam) then stopFly(); return end
            local d = Vector3.new()
            if not typing() then
                if UIS:IsKeyDown(Enum.KeyCode.W) then d = d + cam.CFrame.LookVector end
                if UIS:IsKeyDown(Enum.KeyCode.S) then d = d - cam.CFrame.LookVector end
                if UIS:IsKeyDown(Enum.KeyCode.D) then d = d + cam.CFrame.RightVector end
                if UIS:IsKeyDown(Enum.KeyCode.A) then d = d - cam.CFrame.RightVector end
                if UIS:IsKeyDown(Enum.KeyCode.Space) or UIS:IsKeyDown(Enum.KeyCode.E) then d = d + Vector3.new(0, 1, 0) end
                if UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.Q) then d = d - Vector3.new(0, 1, 0) end
            end
            bv.Velocity = d.Magnitude > 0 and d.Unit * (50 * fly.speed) or Vector3.new()
            bg.CFrame = cam.CFrame
        end)
    end
    pair("Movement", "fly", "unfly", "Start flying; optional speed", "Stop flying", "[speed]",
        function(a) startFly(num(a[1], nil)) end, stopFly)
    def("Movement", "togglefly", "Toggle fly on/off", nil, function(a)
        if fly.active then stopFly() else startFly(num(a[1], nil)) end
    end)
    def("Movement", "flyspeed", "Set fly speed (default 1)", "<n>", function(a) fly.speed = num(a[1], 1) end)

    local nc = {orig = {}}
    local function ncOff()
        if nc.conn then nc.conn:Disconnect(); nc.conn = nil end
        for p, v in pairs(nc.orig) do if p.Parent then p.CanCollide = v end end
        nc.orig = {}
    end
    local function ncOn()
        ncOff()
        nc.conn = RunService.Stepped:Connect(function()
            local c = lp.Character
            if not c then return end
            for _, p in ipairs(c:GetDescendants()) do
                if p:IsA("BasePart") and p.CanCollide then
                    if nc.orig[p] == nil then nc.orig[p] = true end
                    p.CanCollide = false
                end
            end
        end)
    end
    pair("Movement", "noclip", "unnoclip", "Walk through walls", "Restore collision", nil, ncOn, ncOff, nil, {"clip"})
    def("Movement", "togglenoclip", "Toggle noclip on/off", nil, function()
        if nc.conn then ncOff() else ncOn() end
    end)

    local ij = {}
    pair("Movement", "infjump", "uninfjump", "Jump again in mid-air", "Disable infinite jump", nil,
        function()
            if ij.conn then return end
            ij.conn = UIS.JumpRequest:Connect(function()
                local h = hum()
                if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
            end)
        end,
        function() if ij.conn then ij.conn:Disconnect(); ij.conn = nil end end)

    def("Movement", "speed", "Set walk speed", "<n>", function(a)
        local h = hum()
        if h then h.WalkSpeed = num(a[1], 16) end
    end, {"ws", "walkspeed"})
    def("Movement", "jump", "Set jump power", "<n>", function(a)
        local h = hum()
        if h then h.UseJumpPower = true; h.JumpPower = num(a[1], 50) end
    end, {"jp", "jumppower"})
    def("Movement", "loopws", "Loop walkspeed", "<n>", function(a)
        local n = num(a[1], 16)
        startLoop("ws", 0.1, function() local h = hum(); if h then h.WalkSpeed = n end end)
    end)
    def("Movement", "unloopws", "Stop looping walkspeed", nil, function() stopLoop("ws") end)
    off(function() stopLoop("ws") end)
    def("Movement", "loopjp", "Loop jump power", "<n>", function(a)
        local n = num(a[1], 50)
        startLoop("jp", 0.1, function() local h = hum(); if h then h.UseJumpPower = true; h.JumpPower = n end end)
    end)
    def("Movement", "unloopjp", "Stop looping jump power", nil, function() stopLoop("jp") end)
    off(function() stopLoop("jp") end)
    def("Movement", "hipheight", "Set humanoid hip height", "<n>", function(a)
        local h = hum()
        if h then h.HipHeight = num(a[1], 2) end
    end)

    local grav = {default = workspace.Gravity}
    def("Movement", "gravity", "Set workspace gravity", "<n>", function(a) workspace.Gravity = num(a[1], grav.default) end)
    def("Movement", "nogravity", "Remove gravity (float)", nil, function() workspace.Gravity = 0 end)
    def("Movement", "resetgravity", "Restore default gravity", nil, function() workspace.Gravity = grav.default end)
    off(function() workspace.Gravity = grav.default end)
    pair("Movement", "swim", "unswim", "Float in zero-gravity swim", "Stop swimming", nil,
        function()
            workspace.Gravity = 0
            local h = hum()
            if h then h:ChangeState(Enum.HumanoidStateType.Swimming) end
        end,
        function()
            workspace.Gravity = grav.default
            local h = hum()
            if h then h:ChangeState(Enum.HumanoidStateType.GettingUp) end
        end)

    local fl = {}
    local function floatOff()
        if fl.conn then fl.conn:Disconnect(); fl.conn = nil end
        if fl.part then fl.part:Destroy(); fl.part = nil end
    end
    local function floatOn()
        floatOff()
        local r = root()
        if not r then return end
        local p = Instance.new("Part")
        p.Name, p.Anchored, p.Size, p.Transparency = "C1Float", true, Vector3.new(7, 1, 7), 1
        p.Parent = workspace
        fl.part, fl.y = p, r.Position.Y - 3.5
        fl.conn = RunService.Heartbeat:Connect(function()
            local rr = root()
            if not rr then floatOff(); return end
            if not typing() then
                if UIS:IsKeyDown(Enum.KeyCode.E) then fl.y = fl.y + 0.4
                elseif UIS:IsKeyDown(Enum.KeyCode.Q) then fl.y = fl.y - 0.4 end
            end
            p.CFrame = CFrame.new(rr.Position.X, fl.y, rr.Position.Z)
        end)
    end
    pair("Movement", "float", "unfloat", "Spawn a platform beneath you (Q=down, E=up)", "Remove the float platform", nil, floatOn, floatOff)
    def("Movement", "togglefloat", "Toggle float on/off", nil, function()
        if fl.conn then floatOff() else floatOn() end
    end)

    local platforms = {}
    def("Movement", "platform", "Spawn a platform under you", nil, function()
        local r = root()
        if not r then return end
        local p = Instance.new("Part")
        p.Name, p.Anchored, p.Size = "C1Platform", true, Vector3.new(10, 1, 10)
        p.CFrame = CFrame.new(r.Position - Vector3.new(0, 3.5, 0))
        p.Parent = workspace
        platforms[#platforms + 1] = p
    end)
    def("Movement", "unplatform", "Remove spawned platforms", nil, function()
        for _, p in ipairs(platforms) do p:Destroy() end
        platforms = {}
    end)
    off(function() for _, p in ipairs(platforms) do p:Destroy() end; platforms = {} end)

    local function spinOff()
        local r = root()
        if r then
            local s = r:FindFirstChild("C1Spin")
            if s then s:Destroy() end
        end
    end
    pair("Movement", "spin", "unspin", "Spin your character", "Stop spinning", "[speed]",
        function(a)
            local r = root()
            if not r then return end
            spinOff()
            local b = Instance.new("BodyAngularVelocity")
            b.Name = "C1Spin"
            b.MaxTorque = Vector3.new(0, 1e9, 0)
            b.AngularVelocity = Vector3.new(0, num(a[1], 20), 0)
            b.Parent = r
        end, spinOff)

    local function setAnchor(state)
        local c = lp.Character
        if not c then return end
        for _, p in ipairs(c:GetDescendants()) do
            if p:IsA("BasePart") then p.Anchored = state end
        end
    end
    pair("Movement", "freeze", "unfreeze", "Anchor all your character parts (client)", "Unanchor your character", nil,
        function() setAnchor(true) end, function() setAnchor(false) end)

    local pathState = {run = 0}
    local function pathStop() pathState.run = pathState.run + 1 end
    pair("Movement", "pathfind", "unpathfind", "Pathfind to x y z", "Stop current pathfinding route", "<x> <y> <z>",
        function(a)
            local h, r = hum(), root()
            if not (h and r) then return end
            local goal = Vector3.new(num(a[1], r.Position.X), num(a[2], r.Position.Y), num(a[3], r.Position.Z))
            pathStop()
            local id = pathState.run
            local path = PathfindingService:CreatePath()
            local ok = pcall(function() path:ComputeAsync(r.Position, goal) end)
            if not ok or path.Status ~= Enum.PathStatus.Success then say("No path found"); return end
            for _, wp in ipairs(path:GetWaypoints()) do
                if pathState.run ~= id then return end
                if wp.Action == Enum.PathWaypointAction.Jump then h.Jump = true end
                h:MoveTo(wp.Position)
                h.MoveToFinished:Wait()
            end
        end, pathStop)

    -- following / orbiting players
    local follow = {}
    local function followOff() if follow.conn then follow.conn:Disconnect(); follow.conn = nil end end
    pair("Movement", "follow", "unfollow", "Walk toward player and keep following", "Stop following player", "<player>",
        function(a)
            followOff()
            local p = findPlayer(a[1])
            if not p then say("Player not found"); return end
            local t = 0
            follow.conn = RunService.Heartbeat:Connect(function(dt)
                t = t + dt
                if t < 0.2 then return end
                t = 0
                local c = p.Character
                local pr = c and c:FindFirstChild("HumanoidRootPart")
                local h = hum()
                if pr and h then h:MoveTo(pr.Position) end
            end)
        end, followOff, {"walkto"}, {"unwalkto"})

    local orbit = {}
    local function orbitOff() if orbit.conn then orbit.conn:Disconnect(); orbit.conn = nil end end
    pair("Movement", "orbit", "unorbit", "Orbit around player", "Stop orbiting", "<player> [speed] [radius]",
        function(a)
            orbitOff()
            local p = findPlayer(a[1])
            if not p then say("Player not found"); return end
            local speed, radius, angle = num(a[2], 2), num(a[3], 8), 0
            orbit.conn = RunService.Heartbeat:Connect(function(dt)
                local c = p.Character
                local pr = c and c:FindFirstChild("HumanoidRootPart")
                local r = root()
                if not (pr and r) then return end
                angle = angle + dt * speed
                local pos = pr.Position + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
                r.CFrame = CFrame.new(pos, pr.Position)
            end)
        end, orbitOff)
end

----------------------------------------------------------------------
-- Character
----------------------------------------------------------------------
do
    def("Character", "reset", "Kill your character", nil, function()
        local h = hum()
        if h then h.Health = 0 end
    end, {"respawn", "die"})
    def("Character", "sit", "Make your character sit", nil, function()
        local h = hum()
        if h then h.Sit = true end
    end)
    pair("Character", "disablesit", "enablesit", "Prevent your character from sitting", "Re-enable sitting", nil,
        function()
            local h = hum()
            if h then h:SetStateEnabled(Enum.HumanoidStateType.Seated, false); h.Sit = false end
        end,
        function()
            local h = hum()
            if h then h:SetStateEnabled(Enum.HumanoidStateType.Seated, true) end
        end, {"antisit"}, {"unantisit"})

    local animOff = weak()
    pair("Character", "disableanims", "enableanims", "Disable character animations", "Enable character animations", nil,
        function()
            local c = lp.Character
            local a = c and c:FindFirstChild("Animate")
            if a then a.Disabled = true end
            local h = hum()
            local an = h and h:FindFirstChildOfClass("Animator")
            if an then for _, t in ipairs(an:GetPlayingAnimationTracks()) do t:Stop() end end
        end,
        function()
            local c = lp.Character
            local a = c and c:FindFirstChild("Animate")
            if a then a.Disabled = false end
        end)

    local playing
    def("Character", "anim", "Play animation by ID", "<id>", function(a)
        local h = hum()
        local an = h and (h:FindFirstChildOfClass("Animator") or h)
        if not an then return end
        if playing then playing:Stop(); playing = nil end
        local id = tostring(a[1] or "")
        if id == "" then say("Give an animation ID"); return end
        if tonumber(id) then id = "rbxassetid://" .. id end
        local anim = Instance.new("Animation")
        anim.AnimationId = id
        local ok, track = pcall(function() return an:LoadAnimation(anim) end)
        if not ok or not track then say("Couldn't load animation"); return end
        track.Looped = true
        track:Play()
        playing = track
    end)
    def("Character", "stopanim", "Stop looping animation", nil, function()
        if playing then playing:Stop(); playing = nil end
    end)
    off(function() if playing then playing:Stop(); playing = nil end end)

    local hatStore = {}
    def("Character", "nohats", "Remove your accessories", nil, function()
        local c = lp.Character
        if not c then return end
        for _, d in ipairs(c:GetChildren()) do
            if d:IsA("Accessory") then hatStore[#hatStore + 1] = d; d.Parent = nil end
        end
    end)
    def("Character", "hats", "Restore removed accessories", nil, function()
        local c = lp.Character
        if not c then return end
        for _, d in ipairs(hatStore) do d.Parent = c end
        hatStore = {}
    end)
    def("Character", "naked", "Remove all clothing", nil, function()
        local c = lp.Character
        if not c then return end
        for _, d in ipairs(c:GetChildren()) do
            if d:IsA("Shirt") or d:IsA("Pants") or d:IsA("ShirtGraphic") then d:Destroy() end
        end
    end)

    local hidden = weak()
    def("Character", "hide", "Make a player invisible (client-side)", "[player]", function(a)
        local p = a[1] and findPlayer(a[1]) or lp
        local c = p and p.Character
        if not c then say("Player not found"); return end
        for _, d in ipairs(c:GetDescendants()) do
            if (d:IsA("BasePart") or d:IsA("Decal")) and hidden[d] == nil then
                hidden[d] = d.Transparency
                d.Transparency = 1
            end
        end
    end)
    def("Character", "unhide", "Restore player visibility", "[player]", function(a)
        local p = a[1] and findPlayer(a[1]) or lp
        local c = p and p.Character
        if not c then return end
        for _, d in ipairs(c:GetDescendants()) do
            if hidden[d] ~= nil then d.Transparency = hidden[d]; hidden[d] = nil end
        end
    end)

    local light
    pair("Character", "light", "unlight", "Attach a light to yourself", "Remove your attached light", nil,
        function()
            local r = root()
            if not r then return end
            if light then light:Destroy() end
            light = Instance.new("PointLight")
            light.Brightness, light.Range = 3, 40
            light.Parent = r
        end,
        function() if light then light:Destroy(); light = nil end end)

    def("Character", "shiftlock", "Enable shift-lock (if game has it off)", nil, function()
        pcall(function() lp.DevEnableMouseLock = true end)
    end)
    def("Character", "switchteam", "Switch your team (client-side)", "<team>", function(a)
        local want = tostring(a[1] or ""):lower()
        for _, t in ipairs(Teams:GetTeams()) do
            if t.Name:lower():sub(1, #want) == want then lp.Team = t; return end
        end
        say("Team not found")
    end)
end

----------------------------------------------------------------------
-- Teleport
----------------------------------------------------------------------
do
    def("Teleport", "goto", "Teleport to player", "<player>", function(a)
        local p, pr = targetRoot(a[1])
        local r = root()
        if not (pr and r) then say("Player not found"); return end
        r.CFrame = pr.CFrame * CFrame.new(0, 0, 3)
    end, {"to", "tp"})

    local ftp = {}
    pair("Teleport", "ftp", "unftp", "Teleport to mouse (F key)", "Disable FTP", nil,
        function()
            if ftp.conn then return end
            ftp.conn = UIS.InputBegan:Connect(function(i, processed)
                if processed or typing() then return end
                if i.KeyCode == Enum.KeyCode.F then
                    teleportTo(mouseHit())
                end
            end)
        end,
        function() if ftp.conn then ftp.conn:Disconnect(); ftp.conn = nil end end)

    local tool
    pair("Teleport", "tptool", "untptool", "Equip click-to-teleport tool", "Remove the teleport tool", nil,
        function()
            if tool then tool:Destroy() end
            tool = Instance.new("Tool")
            tool.Name, tool.RequiresHandle, tool.CanBeDropped = "Teleport Tool", false, false
            tool.Activated:Connect(function() teleportTo(mouseHit()) end)
            tool.Parent = lp:FindFirstChildOfClass("Backpack")
        end,
        function() if tool then tool:Destroy(); tool = nil end end)

    local waypoints = {}
    def("Teleport", "setwaypoint", "Save current position as a named waypoint", "<name>", function(a)
        local r = root()
        if not (r and a[1]) then say("Need a name"); return end
        waypoints[a[1]:lower()] = r.CFrame
        say("Saved waypoint " .. a[1])
    end, {"swp"})
    def("Teleport", "gotowaypoint", "Teleport to a saved waypoint", "<name>", function(a)
        local cf, r = waypoints[tostring(a[1] or ""):lower()], root()
        if cf and r then r.CFrame = cf else say("Waypoint not found") end
    end, {"gwp"})
    def("Teleport", "deletewaypoint", "Delete a named waypoint", "<name>", function(a)
        waypoints[tostring(a[1] or ""):lower()] = nil
    end)
    def("Teleport", "clearwaypoints", "Delete all saved waypoints", nil, function() waypoints = {} end)
    def("Teleport", "waypoints", "List all saved waypoints", nil, function()
        local names = {}
        for n in pairs(waypoints) do names[#names + 1] = n end
        table.sort(names)
        say(#names > 0 and table.concat(names, ", ") or "No waypoints")
    end)
    local wpTool
    def("Teleport", "waypointtool", "Equip a tool, click anywhere to place a waypoint", "<name>", function(a)
        local name = tostring(a[1] or "wp"):lower()
        if wpTool then wpTool:Destroy() end
        wpTool = Instance.new("Tool")
        wpTool.Name, wpTool.RequiresHandle = "Waypoint Tool", false
        wpTool.Activated:Connect(function()
            local pos = mouseHit()
            if pos then waypoints[name] = CFrame.new(pos + Vector3.new(0, 3, 0)); say("Placed waypoint " .. name) end
        end)
        wpTool.Parent = lp:FindFirstChildOfClass("Backpack")
    end)
    off(function() if wpTool then wpTool:Destroy(); wpTool = nil end end)

    def("Teleport", "position", "Show your current position", nil, function()
        local r = root()
        if r then local p = r.Position; say(string.format("%.1f, %.1f, %.1f", p.X, p.Y, p.Z)) end
    end, {"pos"})
    def("Teleport", "copycoords", "Copy current xyz and cframe", nil, function()
        local r = root()
        if r then
            local p = r.Position
            say(clip(string.format("%.2f, %.2f, %.2f", p.X, p.Y, p.Z)) and "Copied" or "No clipboard")
        end
    end)
end

----------------------------------------------------------------------
-- Camera
----------------------------------------------------------------------
do
    local fc = {speed = 1, yaw = 0, pitch = 0}
    local function fcOff()
        if fc.conn then fc.conn:Disconnect(); fc.conn = nil end
        if fc.input then fc.input:Disconnect(); fc.input = nil end
        if fc.active then
            ContextActionService:UnbindAction("C1Freecam")
            UIS.MouseBehavior = Enum.MouseBehavior.Default
            local cam = workspace.CurrentCamera
            cam.CameraType = Enum.CameraType.Custom
            local h = hum()
            if h then cam.CameraSubject = h end
        end
        fc.active = false
    end
    local function fcOn()
        fcOff()
        local cam = workspace.CurrentCamera
        if not cam then return end
        fc.active = true
        fc.pos = cam.CFrame.Position
        local x, y = cam.CFrame:ToOrientation()
        fc.pitch, fc.yaw = x, y
        cam.CameraType = Enum.CameraType.Scriptable
        ContextActionService:BindActionAtPriority("C1Freecam", function() return Enum.ContextActionResult.Sink end,
            false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S,
            Enum.KeyCode.D, Enum.KeyCode.Q, Enum.KeyCode.E, Enum.KeyCode.Space, Enum.KeyCode.LeftShift)
        fc.input = UIS.InputChanged:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseMovement and UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
                fc.yaw = fc.yaw - i.Delta.X * 0.003
                fc.pitch = math.clamp(fc.pitch - i.Delta.Y * 0.003, -1.5, 1.5)
            end
        end)
        fc.conn = RunService.RenderStepped:Connect(function(dt)
            local c = workspace.CurrentCamera
            c.CameraType = Enum.CameraType.Scriptable
            local rot = CFrame.fromOrientation(fc.pitch, fc.yaw, 0)
            local d = Vector3.new()
            if not typing() then
                if UIS:IsKeyDown(Enum.KeyCode.W) then d = d + rot.LookVector end
                if UIS:IsKeyDown(Enum.KeyCode.S) then d = d - rot.LookVector end
                if UIS:IsKeyDown(Enum.KeyCode.D) then d = d + rot.RightVector end
                if UIS:IsKeyDown(Enum.KeyCode.A) then d = d - rot.RightVector end
                if UIS:IsKeyDown(Enum.KeyCode.E) or UIS:IsKeyDown(Enum.KeyCode.Space) then d = d + Vector3.new(0, 1, 0) end
                if UIS:IsKeyDown(Enum.KeyCode.Q) then d = d - Vector3.new(0, 1, 0) end
            end
            local boost = UIS:IsKeyDown(Enum.KeyCode.LeftShift) and 3 or 1
            if d.Magnitude > 0 then fc.pos = fc.pos + d.Unit * 30 * fc.speed * boost * dt end
            if UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
                UIS.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
            else
                UIS.MouseBehavior = Enum.MouseBehavior.Default
            end
            c.CFrame = CFrame.new(fc.pos) * rot
        end)
    end
    pair("Camera", "freecam", "unfreecam", "Enter free camera (hold right mouse to look)", "Exit free camera", nil, fcOn, fcOff)
    def("Camera", "fcspeed", "Set freecam nav speed", "<n>", function(a) fc.speed = num(a[1], 1) end, {"freecamspeed"})
    def("Camera", "fcgoto", "Move freecam to player", "<player>", function(a)
        local _, pr = targetRoot(a[1])
        if not pr then say("Player not found"); return end
        if not fc.active then fcOn() end
        fc.pos = pr.Position + Vector3.new(0, 3, 8)
    end)

    pair("Camera", "spectate", "unspectate", "Spectate player camera", "Stop spectating", "<player>",
        function(a)
            local p = findPlayer(a[1])
            local c = p and p.Character
            local h = c and c:FindFirstChildOfClass("Humanoid")
            if not h then say("Player not found"); return end
            workspace.CurrentCamera.CameraSubject = h
        end,
        function()
            local h = hum()
            if h then workspace.CurrentCamera.CameraSubject = h end
        end, {"view"}, {"unview"})

    pair("Camera", "unlockcam", "ununlockcam", "Bypass forced first person and zoom limits", "Stop unlock camera", nil,
        function()
            lp.CameraMode = Enum.CameraMode.Classic
            lp.CameraMinZoomDistance = 0
            lp.CameraMaxZoomDistance = 100000
        end,
        function()
            lp.CameraMinZoomDistance = 0.5
            lp.CameraMaxZoomDistance = 128
        end)
    def("Camera", "maxzoom", "Set max camera zoom distance", "<n>", function(a)
        lp.CameraMaxZoomDistance = num(a[1], 128)
    end)
    def("Camera", "fov", "Set field of view", "<n>", function(a)
        workspace.CurrentCamera.FieldOfView = num(a[1], 70)
    end)
    pair("Camera", "viewpart", "unviewpart", "Focus camera on a named part/model", "Reset camera to your character", "<name>",
        function(a)
            local want = tostring(a[1] or ""):lower()
            for _, d in ipairs(workspace:GetDescendants()) do
                if (d:IsA("BasePart") or d:IsA("Model")) and d.Name:lower() == want then
                    workspace.CurrentCamera.CameraSubject = d
                    return
                end
            end
            say("Part not found")
        end,
        function()
            local h = hum()
            if h then workspace.CurrentCamera.CameraSubject = h end
        end)
    pair("Camera", "inviscam", "uninviscam", "See through walls (InvisiCam mode)", "Restore camera from InvisiCam", nil,
        function() lp.DevCameraOcclusionMode = Enum.DevCameraOcclusionMode.Invisicam end,
        function() lp.DevCameraOcclusionMode = Enum.DevCameraOcclusionMode.Zoom end)

    local xray = weak()
    pair("Camera", "xray", "unxray", "Enable X-ray (see through walls)", "Disable X-ray", nil,
        function()
            for _, d in ipairs(workspace:GetDescendants()) do
                if d:IsA("BasePart") and not d:IsDescendantOf(lp.Character or workspace) and xray[d] == nil then
                    local isPlayer = false
                    for _, p in ipairs(Players:GetPlayers()) do
                        if p.Character and d:IsDescendantOf(p.Character) then isPlayer = true; break end
                    end
                    if not isPlayer then
                        xray[d] = d.Transparency
                        d.Transparency = math.max(d.Transparency, 0.65)
                    end
                end
            end
        end,
        function()
            for d, t in pairs(xray) do
                if d.Parent then d.Transparency = t end
                xray[d] = nil
            end
        end)
end

----------------------------------------------------------------------
-- Visual / Lighting
----------------------------------------------------------------------
do
    local fb
    pair("Visual", "fullbright", "nofullbright", "Maximize all light ranges", "Restore original lighting", nil,
        function()
            if not fb then
                fb = {Brightness = Lighting.Brightness, ClockTime = Lighting.ClockTime, FogEnd = Lighting.FogEnd,
                    GlobalShadows = Lighting.GlobalShadows, Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient}
            end
            Lighting.Brightness, Lighting.ClockTime, Lighting.FogEnd = 2, 14, 100000
            Lighting.GlobalShadows = false
            Lighting.Ambient = Color3.fromRGB(178, 178, 178)
            Lighting.OutdoorAmbient = Color3.fromRGB(178, 178, 178)
        end,
        function()
            if fb then for k, v in pairs(fb) do Lighting[k] = v end; fb = nil end
        end)

    local lightsOff = weak()
    pair("Visual", "nolights", "lights", "Remove all in-world lights", "Restore removed lights", nil,
        function()
            for _, d in ipairs(workspace:GetDescendants()) do
                if d:IsA("Light") and lightsOff[d] == nil then lightsOff[d] = d.Enabled; d.Enabled = false end
            end
        end,
        function()
            for d, v in pairs(lightsOff) do
                if d.Parent then d.Enabled = v end
                lightsOff[d] = nil
            end
        end)

    local fxOff = weak()
    local function killEffects()
        for _, root0 in ipairs({Lighting, workspace.CurrentCamera}) do
            if root0 then
                for _, d in ipairs(root0:GetChildren()) do
                    if d:IsA("PostEffect") then
                        if fxOff[d] == nil then fxOff[d] = d.Enabled end
                        d.Enabled = false
                    end
                end
            end
        end
    end
    local function restoreEffects()
        for d, v in pairs(fxOff) do
            if d.Parent then d.Enabled = v end
            fxOff[d] = nil
        end
    end
    def("Visual", "noeffect", "Disable all post-processing effects", nil, killEffects)
    def("Visual", "loopnoeffect", "Keep post-processing effects disabled", nil, function() startLoop("fx", 0.5, killEffects) end)
    def("Visual", "unloopnoeffect", "Stop loop disabling effects", nil, function() stopLoop("fx"); restoreEffects() end)
    off(function() stopLoop("fx"); restoreEffects() end)

    local fog = weak()
    local fogOrig
    local function killFog()
        if not fogOrig then fogOrig = {FogEnd = Lighting.FogEnd, FogStart = Lighting.FogStart} end
        Lighting.FogEnd, Lighting.FogStart = 1e9, 1e9
        for _, d in ipairs(Lighting:GetChildren()) do
            if d:IsA("Atmosphere") then
                if fog[d] == nil then fog[d] = d.Density end
                d.Density = 0
            end
        end
    end
    local function restoreFog()
        if fogOrig then Lighting.FogEnd, Lighting.FogStart = fogOrig.FogEnd, fogOrig.FogStart; fogOrig = nil end
        for d, v in pairs(fog) do
            if d.Parent then d.Density = v end
            fog[d] = nil
        end
    end
    def("Visual", "nofog", "Remove all fog from the game", nil, killFog)
    def("Visual", "loopnofog", "Keep fog removed", nil, function() startLoop("fog", 0.5, killFog) end)
    def("Visual", "unloopnofog", "Restore fog", nil, function() stopLoop("fog"); restoreFog() end)
    off(function() stopLoop("fog"); restoreFog() end)

    local expOrig, briOrig = Lighting.ExposureCompensation, Lighting.Brightness
    def("Visual", "gamma", "Set lighting exposure/gamma", "<n>", function(a) Lighting.ExposureCompensation = num(a[1], 0) end)
    def("Visual", "loopgamma", "Lock lighting exposure value", "<n>", function(a)
        local n = num(a[1], 0)
        startLoop("gamma", 0.1, function() Lighting.ExposureCompensation = n end)
    end)
    def("Visual", "unloopgamma", "Unlock looped gamma", nil, function() stopLoop("gamma") end)
    off(function() stopLoop("gamma"); Lighting.ExposureCompensation = expOrig end)
    def("Visual", "brightness", "Set lighting brightness", "<n>", function(a) Lighting.Brightness = num(a[1], 2) end)
    def("Visual", "loopbrightness", "Lock lighting brightness", "<n>", function(a)
        local n = num(a[1], 2)
        startLoop("bright", 0.1, function() Lighting.Brightness = n end)
    end)
    def("Visual", "unloopbrightness", "Unlock looped brightness", nil, function() stopLoop("bright") end)
    off(function() stopLoop("bright"); Lighting.Brightness = briOrig end)

    local shadowOrig = Lighting.GlobalShadows
    def("Visual", "globalshadows", "Enable global shadows", nil, function() Lighting.GlobalShadows = true end)
    def("Visual", "unglobalshadows", "Disable global shadows", nil, function() Lighting.GlobalShadows = false end)
    off(function() Lighting.GlobalShadows = shadowOrig end)

    local oldSkies, mySky = {}, nil
    local function skyOff()
        if mySky then mySky:Destroy(); mySky = nil end
        for _, s in ipairs(oldSkies) do s.Parent = Lighting end
        oldSkies = {}
    end
    pair("Visual", "skybox", "unskybox", "Replace the skybox with an image ID or link", "Restore the original skybox", "<id>",
        function(a)
            local id = tostring(a[1] or "")
            if id == "" then say("Give an image ID or link"); return end
            if tonumber(id) then id = "rbxassetid://" .. id end
            for _, s in ipairs(Lighting:GetChildren()) do
                if s:IsA("Sky") then oldSkies[#oldSkies + 1] = s; s.Parent = nil end
            end
            if mySky then mySky:Destroy() end
            mySky = Instance.new("Sky")
            for _, face in ipairs({"SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp"}) do
                mySky[face] = id
            end
            mySky.Parent = Lighting
        end, skyOff)

    local clockOrig = Lighting.ClockTime
    def("Visual", "time", "Set lighting time (hours)", "<0-24>", function(a) Lighting.ClockTime = num(a[1], 14) end)
    def("Visual", "day", "Set time to day", nil, function() Lighting.ClockTime = 14 end)
    def("Visual", "night", "Set time to night", nil, function() Lighting.ClockTime = 0 end)
    off(function() Lighting.ClockTime = clockOrig end)

    local mats = weak()
    pair("Visual", "plastic", "unplastic", "Set all parts to Plastic (FPS boost)", "Restore original materials", nil,
        function()
            for _, d in ipairs(workspace:GetDescendants()) do
                if d:IsA("BasePart") and mats[d] == nil then mats[d] = d.Material; d.Material = Enum.Material.Plastic end
            end
        end,
        function()
            for d, m in pairs(mats) do
                if d.Parent then d.Material = m end
                mats[d] = nil
            end
        end)

    local tex = weak()
    pair("Visual", "untexturebp", "texturebp", "Remove all textures/decals from workspace parts", "Restore removed textures", nil,
        function()
            for _, d in ipairs(workspace:GetDescendants()) do
                if (d:IsA("Decal") or d:IsA("Texture")) and tex[d] == nil then tex[d] = d.Transparency; d.Transparency = 1 end
            end
        end,
        function()
            for d, t in pairs(tex) do
                if d.Parent then d.Transparency = t end
                tex[d] = nil
            end
        end)

    def("Visual", "removebaseplate", "Remove all baseplates (client)", nil, function()
        for _, d in ipairs(workspace:GetDescendants()) do
            if d:IsA("BasePart") and d.Name:lower() == "baseplate" then d:Destroy() end
        end
    end)
end

----------------------------------------------------------------------
-- Tools / proximity prompts
----------------------------------------------------------------------
do
    local function backpack() return lp:FindFirstChildOfClass("Backpack") end
    def("Tools", "droptools", "Drop all tools from your backpack", nil, function()
        local c, b = lp.Character, backpack()
        local h = hum()
        if h then h:UnequipTools() end
        if b then for _, t in ipairs(b:GetChildren()) do if t:IsA("Tool") then t.Parent = workspace end end end
    end)
    def("Tools", "equiptools", "Equip every tool from backpack", nil, function()
        local c, b = lp.Character, backpack()
        if c and b then for _, t in ipairs(b:GetChildren()) do if t:IsA("Tool") then t.Parent = c end end end
    end)
    def("Tools", "unequiptools", "Unequip all held tools", nil, function()
        local h = hum()
        if h then h:UnequipTools() end
    end)
    def("Tools", "grabtools", "Grab dropped tools from workspace", nil, function()
        local b = backpack()
        if not b then return end
        for _, t in ipairs(workspace:GetChildren()) do if t:IsA("Tool") then t.Parent = b end end
    end)
    local grab
    pair("Tools", "autograbtools", "unautograbtools", "Auto-grab tools dropped into workspace", "Stop auto-grabbing tools", nil,
        function()
            if grab then return end
            grab = workspace.ChildAdded:Connect(function(t)
                local b = backpack()
                if t:IsA("Tool") and b then task.wait(0.1); t.Parent = b end
            end)
        end,
        function() if grab then grab:Disconnect(); grab = nil end end)

    local bt
    def("Tools", "btools", "Give a client-side delete tool (does not replicate)", nil, function()
        if bt then bt:Destroy() end
        bt = Instance.new("Tool")
        bt.Name, bt.RequiresHandle = "Delete (client)", false
        bt.Activated:Connect(function()
            local m = lp:GetMouse()
            if m.Target and not m.Target:IsDescendantOf(lp.Character) then m.Target:Destroy() end
        end)
        bt.Parent = backpack()
    end)
    off(function() if bt then bt:Destroy(); bt = nil end end)

    local function eachPrompt(fn)
        for _, d in ipairs(workspace:GetDescendants()) do if d:IsA("ProximityPrompt") then fn(d) end end
    end
    def("Tools", "fireproximityprompts", "Fire all proximity prompts", nil, function()
        if type(fireproximityprompt) ~= "function" then say("Executor lacks fireproximityprompt"); return end
        eachPrompt(function(p) pcall(fireproximityprompt, p) end)
    end)
    def("Tools", "fireproximitypromptsfind", "Fire proximity prompts matching name", "<name>", function(a)
        if type(fireproximityprompt) ~= "function" then say("Executor lacks fireproximityprompt"); return end
        local want = tostring(a[1] or ""):lower()
        eachPrompt(function(p)
            if p.Name:lower():find(want, 1, true) or p.ObjectText:lower():find(want, 1, true) then pcall(fireproximityprompt, p) end
        end)
    end)
    local plimit = weak()
    def("Tools", "noproximitypromptlimits", "Set all ProximityPrompt MaxActivationDistance to huge", nil, function()
        eachPrompt(function(p)
            if plimit[p] == nil then plimit[p] = p.MaxActivationDistance end
            p.MaxActivationDistance = 1e5
            p.RequiresLineOfSight = false
        end)
    end)
    off(function() for p, v in pairs(plimit) do if p.Parent then p.MaxActivationDistance = v end; plimit[p] = nil end end)
    local inst, instConn = weak(), nil
    local function makeInstant(p)
        if inst[p] == nil then inst[p] = p.HoldDuration end
        p.HoldDuration = 0
    end
    pair("Tools", "instantproximityprompts", "uninstantproximityprompts", "Fire proximity prompts the moment you hold them",
        "Disable instant proximity prompts", nil,
        function()
            eachPrompt(makeInstant)
            if not instConn then
                instConn = workspace.DescendantAdded:Connect(function(d) if d:IsA("ProximityPrompt") then makeInstant(d) end end)
            end
        end,
        function()
            if instConn then instConn:Disconnect(); instConn = nil end
            for p, v in pairs(inst) do if p.Parent then p.HoldDuration = v end; inst[p] = nil end
        end)
    pair("Tools", "disableproximityprompts", "enableproximityprompts", "Disable all ProximityPrompts", "Enable all ProximityPrompts", nil,
        function() eachPrompt(function(p) p.Enabled = false end) end,
        function() eachPrompt(function(p) p.Enabled = true end) end)
    def("Tools", "fireclickdetectors", "Fire all ClickDetectors in workspace", nil, function()
        if type(fireclickdetector) ~= "function" then say("Executor lacks fireclickdetector"); return end
        for _, d in ipairs(workspace:GetDescendants()) do
            if d:IsA("ClickDetector") then pcall(fireclickdetector, d) end
        end
    end)
end

----------------------------------------------------------------------
-- Server / Utility
----------------------------------------------------------------------
do
    local function httpGet(url)
        local ok, res = pcall(function() return game:HttpGet(url) end)
        if ok and type(res) == "string" then return res end
        local req = (syn and syn.request) or http_request or request
        if req then
            local ok2, r = pcall(req, {Url = url, Method = "GET"})
            if ok2 and r and r.Body then return r.Body end
        end
    end
    local function hop(mode)
        say("Finding a server...")
        local body = httpGet("https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder="
            .. (mode == "fewest" and "Asc" or "Desc") .. "&limit=100")
        local ok, data = pcall(function() return HttpService:JSONDecode(body or "") end)
        if not (ok and type(data) == "table" and type(data.data) == "table") then say("Couldn't fetch servers"); return end
        local pool = {}
        for _, s in ipairs(data.data) do
            if s.id ~= game.JobId and s.playing < s.maxPlayers then pool[#pool + 1] = s end
        end
        if #pool == 0 then say("No other servers found"); return end
        local pick
        if mode == "random" then pick = pool[math.random(#pool)]
        elseif mode == "most" then table.sort(pool, function(a, b) return a.playing > b.playing end); pick = pool[1]
        else table.sort(pool, function(a, b) return a.playing < b.playing end); pick = pool[1] end
        TeleportService:TeleportToPlaceInstance(game.PlaceId, pick.id, lp)
    end
    def("Server", "rejoin", "Rejoin this server", nil, function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, lp)
    end, {"rj"})
    def("Server", "serverhop", "Hop to a random server", nil, function() hop("random") end, {"hop"})
    def("Server", "shmost", "Serverhop to server with MOST players", nil, function() hop("most") end)
    def("Server", "shlowest", "Serverhop to server with FEWEST players", nil, function() hop("fewest") end)
    def("Server", "join", "Join server by Job ID", "<jobid>", function(a)
        if not a[1] then say("Give a Job ID"); return end
        TeleportService:TeleportToPlaceInstance(game.PlaceId, a[1], lp)
    end)
    def("Server", "jobid", "Copy a join link for your current server", nil, function()
        local link = "roblox://experiences/start?placeId=" .. game.PlaceId .. "&gameInstanceId=" .. game.JobId
        say(clip(link) and "Copied join link" or "No clipboard")
    end)
    def("Server", "serverinfo", "Show server info", nil, function()
        say(#Players:GetPlayers() .. "/" .. Players.MaxPlayers .. " players, place " .. game.PlaceId)
    end)
    local afk
    pair("Server", "antiafk", "unantiafk", "Prevent AFK kick", "Disable anti-AFK", nil,
        function()
            if afk then return end
            afk = lp.Idled:Connect(function()
                local vu = game:GetService("VirtualUser")
                vu:CaptureController()
                vu:ClickButton2(Vector2.new())
            end)
        end,
        function() if afk then afk:Disconnect(); afk = nil end end)

    def("Utility", "ping", "Show your current ping", nil, function()
        local ok, v = pcall(function() return StatsService.Network.ServerStatsItem["Data Ping"]:GetValueString() end)
        say(ok and v or "Ping unavailable")
    end)
    def("Utility", "fps", "Show current framerate", nil, function()
        local n = 0
        local c = RunService.RenderStepped:Connect(function() n = n + 1 end)
        task.wait(1)
        c:Disconnect()
        say(n .. " fps")
    end)
    def("Utility", "copyuser", "Copy player username", "<player>", function(a)
        local p = findPlayer(a[1]) or lp
        say(clip(p.Name) and ("Copied " .. p.Name) or "No clipboard")
    end)
    def("Utility", "inspect", "Inspect player avatar", "<player>", function(a)
        local p = findPlayer(a[1])
        if not p then say("Player not found"); return end
        pcall(function() game:GetService("GuiService"):InspectPlayerFromUserId(p.UserId) end)
    end)
    def("Utility", "console", "Open dev console", nil, function()
        pcall(function() StarterGui:SetCore("DevConsoleVisible", true) end)
    end)
    def("Utility", "volume", "Set master volume (0-10)", "<0-10>", function(a)
        pcall(function() UserSettings():GetService("UserGameSettings").MasterVolume = math.clamp(num(a[1], 5), 0, 10) / 10 end)
    end)
    def("Utility", "r", "Repeat last command", nil, function()
        if lastLine then runLine(lastLine, true) else say("Nothing to repeat") end
    end)
    def("Utility", "clearsettings", "Disable active toggles and restore default settings", nil, function()
        for _, f in ipairs(OFFS) do pcall(f) end
        say("Cleared active toggles")
    end)
    def("Utility", "cmds", "Show how many commands exist", nil, function() say(#LIST .. " commands") end, {"commands"})
end

----------------------------------------------------------------------
-- Command runner
----------------------------------------------------------------------
runLine = function(line, isRepeat)
    line = tostring(line or ""):match("^%s*(.-)%s*$")
    if line:sub(1, 1) == ";" then line = line:sub(2) end
    if line == "" then return end
    local parts = {}
    for w in line:gmatch("%S+") do parts[#parts + 1] = w end
    local name = table.remove(parts, 1):lower()
    local c = CMDS[name]
    if not c then say("Unknown command: " .. name); return end
    if c.name ~= "r" and not isRepeat then lastLine = line end
    task.spawn(function()
        local ok, err = pcall(c.fn, parts, line)
        if not ok then say(name .. ": " .. tostring(err):sub(1, 60)) end
    end)
end

----------------------------------------------------------------------
-- GUI: hub bar + commands panel
----------------------------------------------------------------------
local C = {
    text = Color3.fromRGB(255, 245, 245), dim = Color3.fromRGB(208, 142, 150), accent = Color3.fromRGB(255, 56, 74),
    accent2 = Color3.fromRGB(255, 112, 124), field = Color3.fromRGB(58, 14, 20), card = Color3.fromRGB(74, 18, 28),
    stroke = Color3.fromRGB(255, 80, 96), div = Color3.fromRGB(130, 40, 52), list = Color3.fromRGB(38, 8, 12),
    cat = {
        Movement = Color3.fromRGB(255, 96, 108), Character = Color3.fromRGB(255, 156, 96), Teleport = Color3.fromRGB(255, 205, 96),
        Camera = Color3.fromRGB(186, 136, 255), Visual = Color3.fromRGB(112, 204, 255), Tools = Color3.fromRGB(124, 232, 164),
        Server = Color3.fromRGB(96, 164, 255), Utility = Color3.fromRGB(224, 224, 236),
        Scripts = Color3.fromRGB(255, 130, 210),
    },
}
for k, v in pairs(C) do if typeof(v) == "Color3" then C[k] = shiftC(v, Theme.hue) end end
for k, v in pairs(C.cat) do C.cat[k] = shiftC(v, Theme.hue) end
local function tween(o, props, info)
    local t = TweenService:Create(o, info or TweenInfo.new(.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), props)
    t:Play()
    return t
end
local function mk(class, props, parent)
    local o = Instance.new(class)
    if o:IsA("GuiObject") then o.BorderSizePixel = 0 end
    if class == "TextLabel" or class == "TextButton" or class == "TextBox" then
        o.Font = (class == "TextLabel") and Enum.Font.GothamMedium or Enum.Font.GothamBold
        o.TextSize = 13
        o.TextColor3 = C.text
        if class == "TextLabel" then o.BackgroundTransparency = 1 else o.BackgroundColor3 = C.field end
        if class == "TextButton" then o.AutoButtonColor = false end
        if class == "TextBox" then o.ClearTextOnFocus = false; o.PlaceholderColor3 = C.dim end
    end
    for k, v in pairs(props) do o[k] = v end
    o.Parent = parent
    return o
end
local function corner(o, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = o end

-- glass body: diagonal crimson gradient + an animated, slowly rotating glowing rim
local strokeGrads = {}
local glowStrokes = {} -- {stroke, baseTransparency}: soft warm halo that pulses
local function glass(frame, radius)
    corner(frame, radius or 16)
    do -- cookies drifting inside the panel
        local w, h = frame.Size.X.Offset, frame.Size.Y.Offset
        if h < 80 then
            Cookie.layer(frame, radius or 16, w, h, 7, 24, 36, .55)
        else
            Cookie.layer(frame, radius or 16, w, h, math.clamp(math.floor(w * h / 11000), 8, 22), 40, 92, .8)
        end
    end
    local g = Instance.new("UIGradient")
    g.Rotation = 115
    g.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, hc(Color3.fromRGB(104, 14, 28))),
        ColorSequenceKeypoint.new(0.5, hc(Color3.fromRGB(52, 8, 16))),
        ColorSequenceKeypoint.new(1, hc(Color3.fromRGB(20, 3, 8))),
    })
    g.Parent = frame
    local st = Instance.new("UIStroke")
    st.Color, st.Thickness, st.Transparency, st.ApplyStrokeMode = Color3.new(1, 1, 1), 1.6, .15, Enum.ApplyStrokeMode.Border
    local sg = Instance.new("UIGradient")
    sg.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, C.accent2),
        ColorSequenceKeypoint.new(0.35, hc(Color3.fromRGB(110, 18, 30))),
        ColorSequenceKeypoint.new(0.65, hc(Color3.fromRGB(110, 18, 30))),
        ColorSequenceKeypoint.new(1, C.accent2),
    })
    sg.Parent = st
    st.Parent = frame
    strokeGrads[#strokeGrads + 1] = sg
    for _, spec in ipairs({{5, .72}, {11, .86}, {19, .94}}) do -- layered strokes fake a blurred cookie-gold glow
        local gs = Instance.new("UIStroke")
        gs.Color, gs.Thickness, gs.Transparency, gs.ApplyStrokeMode = C.accent2, spec[1], spec[2], Enum.ApplyStrokeMode.Border
        gs.Parent = frame
        glowStrokes[#glowStrokes + 1] = {gs, spec[2]}
    end
end
bind(RunService.RenderStepped, function(dt)
    for _, g in ipairs(strokeGrads) do
        if g.Parent then g.Rotation = (g.Rotation + dt * 45) % 360 end
    end
    local pulse = 0.5 + 0.5 * math.sin(os.clock() * 2.2)
    for _, e in ipairs(glowStrokes) do
        if e[1].Parent then e[1].Transparency = math.clamp(e[2] - 0.1 * pulse + 0.05, 0, 1) end
    end
end)
local function accentLine(parent, x, y, w)
    local l = mk("Frame", {Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, 2), BackgroundColor3 = Color3.new(1, 1, 1)}, parent)
    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new(C.accent, C.accent2)
    g.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1)})
    g.Parent = l
    return l
end
local function press(b)
    local s = Instance.new("UIScale")
    s.Parent = b
    b.MouseButton1Down:Connect(function() tween(s, {Scale = .94}, TweenInfo.new(.08)) end)
    b.MouseButton1Up:Connect(function() tween(s, {Scale = 1}, TweenInfo.new(.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)) end)
    b.MouseLeave:Connect(function() tween(s, {Scale = 1}, TweenInfo.new(.15)) end)
end
local function fieldBox(parent, placeholder, x, y, w, h)
    local b = mk("TextBox", {PlaceholderText = placeholder, Text = "", Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h),
        TextXAlignment = Enum.TextXAlignment.Left, Font = Enum.Font.GothamSemibold, TextSize = 13,
        BackgroundColor3 = C.card, BackgroundTransparency = .4}, parent)
    corner(b, h / 2)
    mk("UIPadding", {PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 12)}, b)
    local st = Instance.new("UIStroke")
    st.Color, st.Thickness, st.Transparency, st.ApplyStrokeMode = C.div, 1.2, .35, Enum.ApplyStrokeMode.Border
    st.Parent = b
    b.Focused:Connect(function() tween(st, {Color = C.accent, Transparency = 0}, TweenInfo.new(.15)) end)
    b.FocusLost:Connect(function() tween(st, {Color = C.div, Transparency = .35}, TweenInfo.new(.2)) end)
    return b
end
local function draggable(handle, target)
    local dragging, ds, sp = false
    handle.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging, ds, sp = true, i.Position, target.Position
        end
    end)
    bind(UIS.InputChanged, function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - ds
            target.Position = UDim2.new(sp.X.Scale, sp.X.Offset + d.X, sp.Y.Scale, sp.Y.Offset + d.Y)
        end
    end)
    bind(UIS.InputEnded, function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)
end

local gui = Instance.new("ScreenGui")
gui.Name, gui.ResetOnSpawn, gui.ZIndexBehavior = "CookieHub", false, Enum.ZIndexBehavior.Sibling
gui.Parent = lp:WaitForChild("PlayerGui")

gui.DisplayOrder = 10
def("Visual", "cookies", "Show/hide the cookies on the GUI (on/off, no arg toggles)", "[on|off]", function(a)
    local v = tostring(a[1] or ""):lower()
    if v == "on" then Cookie.on = true elseif v == "off" then Cookie.on = false else Cookie.on = not Cookie.on end
    Cookie.setVisible(Cookie.on)
    say("GUI cookies " .. (Cookie.on and "on" or "off"))
end, {"cookiebg"})
def("Visual", "cookieglow", "Turn the warm cookie glow on/off", "[on|off]", function(a)
    local v = tostring(a[1] or ""):lower()
    local cur = glowStrokes[1] and glowStrokes[1][1].Enabled
    local want
    if v == "on" then want = true elseif v == "off" then want = false else want = not cur end
    for _, e in ipairs(glowStrokes) do e[1].Enabled = want end
    for _, e in ipairs(Cookie.halos) do e[1].Enabled = want end
    say("Cookie glow " .. (want and "on" or "off"))
end)
off(function() Cookie.setVisible(true); Cookie.on = true end)

-- toast notifications (replace the plain status text)
local toastF = mk("Frame", {Size = UDim2.fromOffset(360, 40), AnchorPoint = Vector2.new(.5, 1), Position = UDim2.new(.5, 0, 1, -20),
    BackgroundColor3 = hc(Color3.fromRGB(34, 6, 12)), BackgroundTransparency = 1, Visible = false, ZIndex = 50}, gui)
corner(toastF, 20)
local toastStroke = Instance.new("UIStroke")
toastStroke.Color, toastStroke.Thickness, toastStroke.ApplyStrokeMode = C.accent, 1.4, Enum.ApplyStrokeMode.Border
toastStroke.Parent = toastF
local toastDot = mk("Frame", {Size = UDim2.fromOffset(8, 8), Position = UDim2.fromOffset(16, 16), BackgroundColor3 = C.accent, ZIndex = 51}, toastF)
corner(toastDot, 4)
local toastL = mk("TextLabel", {Text = "", TextSize = 13, Font = Enum.Font.GothamSemibold, Position = UDim2.fromOffset(34, 0),
    Size = UDim2.new(1, -48, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 51}, toastF)

-- hub bar
local BAR_W, BAR_H = 500, 54
local bar = mk("Frame", {Size = UDim2.fromOffset(BAR_W, BAR_H), Position = UDim2.new(0.5, -BAR_W / 2, 0, 14),
    BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = .16, Active = true}, gui)
glass(bar, 27)
local barScale = Instance.new("UIScale")
barScale.Scale = .8
barScale.Parent = bar
tween(barScale, {Scale = 1}, TweenInfo.new(.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
draggable(bar, bar)
local logo = mk("Frame", {Size = UDim2.fromOffset(36, 36), Position = UDim2.fromOffset(9, 9), BackgroundColor3 = Color3.new(1, 1, 1)}, bar)
corner(logo, 18)
do
    local lg = Instance.new("UIGradient")
    lg.Rotation = 45
    lg.Color = ColorSequence.new(C.accent2, hc(Color3.fromRGB(190, 20, 44)))
    lg.Parent = logo
end
logo.BackgroundTransparency = 1
Cookie.make(logo, 36, 0, true, Random.new(7))
mk("TextLabel", {Text = "cookie", Font = Enum.Font.GothamBold, TextSize = 15, Position = UDim2.fromOffset(54, 8),
    Size = UDim2.fromOffset(60, 18), TextXAlignment = Enum.TextXAlignment.Left}, bar)
mk("TextLabel", {Text = "hub", Font = Enum.Font.GothamMedium, TextSize = 11, TextColor3 = C.dim, Position = UDim2.fromOffset(54, 26),
    Size = UDim2.fromOffset(60, 14), TextXAlignment = Enum.TextXAlignment.Left}, bar)

local function barBtn(text, x, w)
    local b = mk("TextButton", {Text = text, TextSize = 12, Position = UDim2.fromOffset(x, 12), Size = UDim2.fromOffset(w, 30),
        BackgroundColor3 = C.card, BackgroundTransparency = .2}, bar)
    corner(b, 15)
    local st = Instance.new("UIStroke")
    st.Color, st.Thickness, st.Transparency, st.ApplyStrokeMode = C.div, 1, .4, Enum.ApplyStrokeMode.Border
    st.Parent = b
    b.MouseEnter:Connect(function() tween(st, {Color = C.accent, Transparency = 0}, TweenInfo.new(.12)) end)
    b.MouseLeave:Connect(function() tween(st, {Color = C.div, Transparency = .4}, TweenInfo.new(.18)) end)
    press(b)
    return b
end
local reanimBtn = barBtn("Reanim", 122, 74)
local cmdBtn = barBtn("Commands", 200, 92)
local playersBtn = barBtn("Players", 296, 78)
local closeBtn = barBtn("X", 456, 34)
closeBtn.BackgroundColor3 = C.accent
closeBtn.BackgroundTransparency = 0

-- theme button + commands (hue-shifts every GUI color, saved between runs)
local themeBtn = barBtn("Theme", 378, 70)
local function applyTheme(hue)
    hue = hue % 1
    local d = (hue - Theme.hue) % 1
    Theme.hue = hue
    G.CookieThemeHue = hue
    pcall(function() if writefile then writefile("CookieHub_theme.txt", tostring(hue)) end end)
    if d < 1e-4 then return end
    for k, v in pairs(C) do if typeof(v) == "Color3" then C[k] = shiftC(v, d) end end
    for k, v in pairs(C.cat) do C.cat[k] = shiftC(v, d) end
    recolor(gui, d)
    if type(G.ReanimlolTheme) == "function" then pcall(G.ReanimlolTheme, d) end
end
themeBtn.Activated:Connect(function()
    local idx = 0
    for i, t in ipairs(THEMES) do if math.abs(t[2] - Theme.hue) < 0.001 then idx = i end end
    local nxt = THEMES[idx % #THEMES + 1]
    applyTheme(nxt[2])
    say("Theme: " .. nxt[1])
end)
def("Utility", "theme", "Set GUI theme by name (no name lists them)", "[name]", function(a)
    local want = tostring(a[1] or ""):lower()
    for _, t in ipairs(THEMES) do
        if t[1]:lower() == want then applyTheme(t[2]); say("Theme: " .. t[1]); return end
    end
    local names = {}
    for _, t in ipairs(THEMES) do names[#names + 1] = t[1] end
    say(table.concat(names, ", "))
end)
def("Utility", "themehue", "Custom theme: hue shift 0-360 (0 = crimson)", "<0-360>", function(a)
    applyTheme(num(a[1], 0) / 360)
end)

-- commands panel
local PW, PH = 460, 520
local panel = mk("Frame", {Size = UDim2.fromOffset(PW, PH), Position = UDim2.new(0.5, -PW / 2, 0.5, -PH / 2 + 40),
    BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = .16, Active = true, Visible = false}, gui)
glass(panel, 20)
local pScale = Instance.new("UIScale")
pScale.Parent = panel
local head = mk("Frame", {Size = UDim2.new(1, 0, 0, 52), BackgroundTransparency = 1}, panel)
draggable(head, panel)
mk("TextLabel", {Text = "Commands", Font = Enum.Font.GothamBold, TextSize = 20, Position = UDim2.fromOffset(20, 0),
    Size = UDim2.fromOffset(160, 52), TextXAlignment = Enum.TextXAlignment.Left}, head)
local countPill = mk("Frame", {Size = UDim2.fromOffset(104, 24), Position = UDim2.new(1, -124, 0, 14), BackgroundColor3 = C.accent,
    BackgroundTransparency = .75}, head)
corner(countPill, 12)
local countLbl = mk("TextLabel", {Text = #LIST .. " commands", TextSize = 11, Font = Enum.Font.GothamBold, Size = UDim2.fromScale(1, 1)}, countPill)
accentLine(panel, 20, 52, PW - 40)

local search = fieldBox(panel, "Search commands...", 20, 64, PW - 40, 34)
local chipRow = mk("ScrollingFrame", {Position = UDim2.fromOffset(20, 106), Size = UDim2.fromOffset(PW - 40, 28),
    BackgroundTransparency = 1, ScrollBarThickness = 0, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.X,
    ScrollingDirection = Enum.ScrollingDirection.X}, panel)
mk("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, chipRow)

local listFrame = mk("ScrollingFrame", {Position = UDim2.fromOffset(20, 142), Size = UDim2.fromOffset(PW - 40, 296),
    BackgroundTransparency = 1, ScrollBarThickness = 3, ScrollBarImageColor3 = C.accent, CanvasSize = UDim2.new(),
    AutomaticCanvasSize = Enum.AutomaticSize.Y}, panel)
mk("UIListLayout", {Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder}, listFrame)
mk("UIPadding", {PaddingRight = UDim.new(0, 8)}, listFrame)

accentLine(panel, 20, 446, PW - 40)
local runBox = fieldBox(panel, "Type a command and press Enter   ( ; focuses this bar )", 20, 458, PW - 40 - 84, 36)
runBox:FindFirstChildOfClass("UIPadding").PaddingLeft = UDim.new(0, 30)
mk("TextLabel", {Text = ">", Font = Enum.Font.GothamBlack, TextSize = 16, TextColor3 = C.accent, Position = UDim2.fromOffset(12, 0),
    Size = UDim2.fromOffset(16, 36)}, runBox)
local runBtn = mk("TextButton", {Text = "Run", TextSize = 13, Position = UDim2.fromOffset(PW - 20 - 76, 458),
    Size = UDim2.fromOffset(76, 36), BackgroundColor3 = Color3.new(1, 1, 1)}, panel)
corner(runBtn, 18)
do
    local rg = Instance.new("UIGradient")
    rg.Rotation = 20
    rg.Color = ColorSequence.new(C.accent2, hc(Color3.fromRGB(200, 24, 48)))
    rg.Parent = runBtn
end
press(runBtn)
local status = mk("TextLabel", {Text = "Click a command to run it. Ones with arguments fill the bar for you.",
    TextSize = 11, TextColor3 = C.dim, Position = UDim2.fromOffset(20, 498), Size = UDim2.fromOffset(PW - 40, 16),
    TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd}, panel)

local toastTok = 0
say = function(text)
    if destroyed then return end
    text = tostring(text)
    status.Text = text
    toastTok = toastTok + 1
    local t = toastTok
    toastL.Text = text
    toastF.Visible = true
    toastF.Position = UDim2.new(.5, 0, 1, -10)
    toastF.BackgroundTransparency = 1
    toastL.TextTransparency = 1
    tween(toastF, {Position = UDim2.new(.5, 0, 1, -34), BackgroundTransparency = .08}, TweenInfo.new(.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
    tween(toastL, {TextTransparency = 0}, TweenInfo.new(.25))
    task.delay(2.8, function()
        if t ~= toastTok or destroyed then return end
        tween(toastF, {BackgroundTransparency = 1, Position = UDim2.new(.5, 0, 1, -18)}, TweenInfo.new(.3))
        tween(toastL, {TextTransparency = 1}, TweenInfo.new(.3))
        task.delay(.32, function() if t == toastTok and not destroyed then toastF.Visible = false end end)
    end)
end

local catOrder = {"All", "Scripts", "Movement", "Character", "Teleport", "Camera", "Visual", "Tools", "Server", "Utility"}
local curCat = "All"
local rebuild, buildChips

local function runFromBar()
    local t = runBox.Text
    runBox.Text = ""
    runLine(t)
end

rebuild = function()
    for _, c in ipairs(listFrame:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end
    local q = search.Text:lower()
    local sorted = {}
    for _, c in ipairs(LIST) do sorted[#sorted + 1] = c end
    table.sort(sorted, function(a, b) return a.name < b.name end)
    local order = 0
    for _, c in ipairs(sorted) do
        if (curCat == "All" or c.cat == curCat) and (q == "" or c.name:find(q, 1, true) or c.desc:lower():find(q, 1, true)) then
            order = order + 1
            local col = C.cat[c.cat] or C.accent
            local row = mk("TextButton", {Text = "", Size = UDim2.new(1, 0, 0, 44), LayoutOrder = order,
                BackgroundColor3 = col, BackgroundTransparency = .93}, listFrame)
            corner(row, 10)
            local barL = mk("Frame", {Size = UDim2.fromOffset(3, 22), Position = UDim2.fromOffset(8, 11), BackgroundColor3 = col}, row)
            corner(barL, 2)
            mk("TextLabel", {Text = c.name, Position = UDim2.fromOffset(20, 5), Size = UDim2.new(1, -130, 0, 18),
                TextXAlignment = Enum.TextXAlignment.Left, TextSize = 14, Font = Enum.Font.GothamBold,
                TextTruncate = Enum.TextTruncate.AtEnd}, row)
            if c.args then
                mk("TextLabel", {Text = c.args, Position = UDim2.new(1, -118, 0, 5), Size = UDim2.fromOffset(110, 18),
                    TextXAlignment = Enum.TextXAlignment.Right, TextSize = 11, TextColor3 = col, TextTransparency = .15,
                    TextTruncate = Enum.TextTruncate.AtEnd}, row)
            end
            mk("TextLabel", {Text = c.desc, Position = UDim2.fromOffset(20, 24), Size = UDim2.new(1, -110, 0, 15),
                TextXAlignment = Enum.TextXAlignment.Left, TextSize = 11, TextColor3 = C.dim,
                TextTruncate = Enum.TextTruncate.AtEnd}, row)
            mk("TextLabel", {Text = c.cat, Position = UDim2.new(1, -90, 0, 24), Size = UDim2.fromOffset(82, 15),
                TextXAlignment = Enum.TextXAlignment.Right, TextSize = 10, TextColor3 = col, TextTransparency = .25}, row)
            row.MouseEnter:Connect(function()
                tween(row, {BackgroundTransparency = .8}, TweenInfo.new(.12))
                tween(barL, {Size = UDim2.fromOffset(4, 30), Position = UDim2.fromOffset(8, 7)}, TweenInfo.new(.15))
            end)
            row.MouseLeave:Connect(function()
                tween(row, {BackgroundTransparency = .93}, TweenInfo.new(.18))
                tween(barL, {Size = UDim2.fromOffset(3, 22), Position = UDim2.fromOffset(8, 11)}, TweenInfo.new(.2))
            end)
            row.Activated:Connect(function()
                if c.args then
                    runBox.Text = c.name .. " "
                    runBox:CaptureFocus()
                else
                    runLine(c.name)
                end
            end)
        end
    end
end

buildChips = function()
    for _, c in ipairs(chipRow:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
    for i, name in ipairs(catOrder) do
        local on = (curCat == name)
        local b = mk("TextButton", {Text = name, TextSize = 12, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 26),
            LayoutOrder = i, BackgroundColor3 = on and C.accent or C.card, BackgroundTransparency = on and 0 or .35,
            TextColor3 = on and Color3.new(1, 1, 1) or C.dim}, chipRow)
        mk("UIPadding", {PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12)}, b)
        corner(b, 13)
        press(b)
        b.Activated:Connect(function() curCat = name; buildChips(); rebuild() end)
    end
end

bind(search:GetPropertyChangedSignal("Text"), rebuild)
runBox.FocusLost:Connect(function(enter) if enter then runFromBar() end end)
runBtn.Activated:Connect(runFromBar)
buildChips()
rebuild()

----------------------------------------------------------------------
-- Extra commands (esp, radar, shaders, novelty movement, rewind, ...)
----------------------------------------------------------------------
do
    -- ESP
    local esp = {objs = {}}
    local function espClear(p)
        for _, o in ipairs(esp.objs[p] or {}) do pcall(function() o:Destroy() end) end
        esp.objs[p] = nil
    end
    local function espAdd(p)
        if p == lp then return end
        espClear(p)
        local c = p.Character
        local head = c and c:FindFirstChild("Head")
        if not head then return end
        local h = Instance.new("Highlight")
        h.FillColor, h.FillTransparency, h.OutlineColor = C.accent, .6, Color3.new(1, 1, 1)
        h.Adornee, h.Parent = c, c
        local b = Instance.new("BillboardGui")
        b.Size, b.StudsOffset, b.AlwaysOnTop, b.Adornee, b.Parent = UDim2.fromOffset(120, 20), Vector3.new(0, 2.5, 0), true, head, c
        local t = Instance.new("TextLabel")
        t.Size, t.BackgroundTransparency, t.Text, t.TextColor3 = UDim2.fromScale(1, 1), 1, p.DisplayName, Color3.new(1, 1, 1)
        t.Font, t.TextSize, t.TextStrokeTransparency = Enum.Font.GothamBold, 13, 0.4
        t.Parent = b
        esp.objs[p] = {h, b}
    end
    local function espOff()
        for p in pairs(esp.objs) do espClear(p) end
        for _, c in ipairs(esp.conns or {}) do c:Disconnect() end
        esp.conns = {}
    end
    pair("Visual", "esp", "unesp", "Highlight and label other players", "Disable ESP", nil,
        function()
            espOff()
            for _, p in ipairs(Players:GetPlayers()) do
                espAdd(p)
                esp.conns[#esp.conns + 1] = p.CharacterAdded:Connect(function() task.wait(0.5); espAdd(p) end)
            end
            esp.conns[#esp.conns + 1] = Players.PlayerAdded:Connect(function(p)
                esp.conns[#esp.conns + 1] = p.CharacterAdded:Connect(function() task.wait(0.5); espAdd(p) end)
            end)
        end, espOff)

    -- Radar
    local radar
    local function radarOff()
        stopLoop("radar")
        if radar then radar:Destroy(); radar = nil end
    end
    pair("Visual", "radar", "unradar", "Open radar panel", "Disable radar", nil,
        function()
            radarOff()
            radar = mk("Frame", {Size = UDim2.fromOffset(170, 170), Position = UDim2.new(1, -190, 1, -190),
                BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = .45}, gui)
            corner(radar, 85)
            local st = Instance.new("UIStroke"); st.Color, st.Thickness = C.stroke, 1.5; st.Parent = radar
            mk("Frame", {Size = UDim2.fromOffset(6, 6), Position = UDim2.new(.5, -3, .5, -3), BackgroundColor3 = Color3.new(1, 1, 1)}, radar)
            local dots = {}
            startLoop("radar", 0.05, function()
                local r, cam = root(), workspace.CurrentCamera
                if not (r and cam and radar) then return end
                local yaw = math.atan2(-cam.CFrame.LookVector.X, -cam.CFrame.LookVector.Z)
                for p, d in pairs(dots) do if not p.Parent then d:Destroy(); dots[p] = nil end end
                for _, p in ipairs(Players:GetPlayers()) do
                    if p ~= lp then
                        local pr = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
                        local d = dots[p]
                        if not d then
                            d = mk("Frame", {Size = UDim2.fromOffset(6, 6), BackgroundColor3 = C.accent}, radar)
                            corner(d, 3)
                            dots[p] = d
                        end
                        if pr then
                            local rel = CFrame.Angles(0, -yaw, 0):VectorToWorldSpace(pr.Position - r.Position)
                            local x, y = rel.X / 200 * 85, rel.Z / 200 * 85
                            local m = math.sqrt(x * x + y * y)
                            if m > 80 then x, y = x / m * 80, y / m * 80 end
                            d.Position = UDim2.new(.5, x - 3, .5, y - 3)
                            d.Visible = true
                        else
                            d.Visible = false
                        end
                    end
                end
            end)
        end, radarOff)

    -- Shaders
    local shade = {}
    local function shadersOff() for _, o in ipairs(shade) do o:Destroy() end; shade = {} end
    pair("Visual", "shaders", "unshaders", "Add bloom, color grading and sun rays", "Disable shaders", nil,
        function()
            shadersOff()
            local cc = Instance.new("ColorCorrectionEffect"); cc.Saturation, cc.Contrast = .25, .1
            local bl = Instance.new("BloomEffect"); bl.Intensity, bl.Size, bl.Threshold = .6, 30, .9
            local sr = Instance.new("SunRaysEffect"); sr.Intensity, sr.Spread = .15, .8
            for _, o in ipairs({cc, bl, sr}) do o.Parent = Lighting; shade[#shade + 1] = o end
        end, shadersOff)

    -- Baseplates (optimized + custom image)
    local function httpGet(url)
        local ok, res = pcall(function() return game:HttpGet(url) end)
        if ok and type(res) == "string" then return res end
        local req = (syn and syn.request) or http_request or request
        if req then
            local ok2, r = pcall(req, {Url = url, Method = "GET"})
            if ok2 and r and r.Body then return r.Body end
        end
    end
    local imgCache = {}
    local function resolveImage(src)
        src = tostring(src or "")
        if tonumber(src) then return "rbxassetid://" .. src end
        if src:match("^rbxassetid://") or src:match("^rbxasset://") or src:match("^rbxthumb://") then return src end
        local id = src:match("roblox%.com/asset/?%?id=(%d+)")
        if id then return "rbxassetid://" .. id end
        if not src:match("^https?://") then say("Give a link, image ID or rbxassetid"); return nil end
        if imgCache[src] then return imgCache[src] end
        local gca = getcustomasset or getsynasset
        if not (gca and type(writefile) == "function") then say("Executor can't load web images (needs getcustomasset)"); return nil end
        local body = httpGet(src)
        if type(body) ~= "string" or #body < 32 then say("Couldn't download that link"); return nil end
        local ext = ".png"
        if body:sub(1, 2) == "\255\216" then ext = ".jpg"
        elseif body:sub(1, 4) ~= "\137PNG" then say("Link must be a direct .png or .jpg"); return nil end
        local h = 5381
        for i = 1, #src do h = (h * 33 + src:byte(i)) % 4294967296 end
        pcall(function() if type(isfolder) == "function" and not isfolder("CookieHub") then makefolder("CookieHub") end end)
        local path = "CookieHub/img_" .. h .. ext
        if not pcall(writefile, path, body) then say("Couldn't save image"); return nil end
        local okA, asset = pcall(gca, path)
        if not okA or not asset then say("Couldn't load image"); return nil end
        imgCache[src] = asset
        return asset
    end

    local bp = {fixed = {}, inf = nil, img = nil, tile = 16, color = nil}
    local function effTile(size) return math.max(bp.tile, size / 128) end -- caps tiles per side (lag guard)
    local function styleOne(p)
        for _, o in ipairs(p:GetChildren()) do
            if o:IsA("Texture") or o:IsA("Decal") then o:Destroy() end
        end
        if not bp.img then return end
        if bp.tile <= 0 then -- stretch one copy across the whole plate
            local d = Instance.new("Decal")
            d.Face, d.Texture = Enum.NormalId.Top, bp.img
            d.Parent = p
        else
            local t = Instance.new("Texture")
            local tile = effTile(p.Size.X)
            t.Face, t.Texture, t.StudsPerTileU, t.StudsPerTileV = Enum.NormalId.Top, bp.img, tile, tile
            t.Parent = p
        end
    end
    local function styleAll()
        for _, p in ipairs(bp.fixed) do if p.Parent then styleOne(p) end end
        if bp.inf and bp.inf.Parent then styleOne(bp.inf) end
    end
    local function newPart(size, cf)
        local p = Instance.new("Part")
        p.Name, p.Anchored, p.Size, p.Material = "C1Baseplate", true, Vector3.new(size, 2, size), Enum.Material.SmoothPlastic
        p.Color = bp.color or hc(Color3.fromRGB(70, 20, 26))
        p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
        p.CastShadow, p.CanTouch, p.Locked = false, false, true
        p.CFrame = cf
        styleOne(p)
        p.Parent = workspace
        return p
    end
    local function floorY(r, h) return r.Position.Y - (h.HipHeight + r.Size.Y / 2) - 1 end

    local function bpOff()
        for _, p in ipairs(bp.fixed) do p:Destroy() end
        bp.fixed = {}
    end
    pair("Visual", "baseplate", "unbaseplate", "Spawn a baseplate under you", "Remove spawned baseplates", "[size]",
        function(a)
            local r, h = root(), hum()
            if not (r and h) then say("Character not ready"); return end
            local size = math.clamp(num(a[1], 1024), 16, 20000)
            bp.fixed[#bp.fixed + 1] = newPart(size, CFrame.new(r.Position.X, floorY(r, h), r.Position.Z))
        end, bpOff)

    local function ibpOff() stopLoop("ibp"); if bp.inf then bp.inf:Destroy(); bp.inf = nil end end
    pair("Visual", "infbaseplate", "uninfbaseplate", "Spawn a baseplate that follows you", "Remove the baseplate", "[size]",
        function(a)
            ibpOff()
            local r, h = root(), hum()
            if not (r and h) then say("Character not ready"); return end
            local size = math.clamp(num(a[1], 1024), 64, 4096)
            bp.inf = newPart(size, CFrame.new(r.Position.X, floorY(r, h), r.Position.Z))
            startLoop("ibp", 0.25, function()
                local rr, part = root(), bp.inf
                if not (rr and part and part.Parent) then return end
                local c, p = part.Position, rr.Position
                local dx, dz = p.X - c.X, p.Z - c.Z
                if dx * dx + dz * dz < (size * 0.2) ^ 2 then return end -- only move when you've drifted
                local step = bp.tile > 0 and effTile(size) or 16 -- snap to tile grid so the image doesn't swim
                part.CFrame = CFrame.new(math.floor(p.X / step + 0.5) * step, c.Y, math.floor(p.Z / step + 0.5) * step)
            end)
        end, ibpOff)

    def("Visual", "bpimage", "Put an image on your baseplates (direct png/jpg link, or image ID)", "<link|id> [studsPerTile]", function(a)
        if not a[1] then say("Give an image link or ID"); return end
        say("Loading image...")
        local img = resolveImage(a[1])
        if not img then return end
        bp.img = img
        if a[2] then bp.tile = math.max(num(a[2], 16), 0) end
        styleAll()
        say("Baseplate image applied")
    end, {"baseplateimage"})
    def("Visual", "bptile", "Image size in studs per tile (0 = stretch one copy)", "<n>", function(a)
        bp.tile = math.max(num(a[1], 16), 0)
        styleAll()
    end)
    def("Visual", "bpcolor", "Baseplate color", "<r> <g> <b>", function(a)
        bp.color = Color3.fromRGB(num(a[1], 70), num(a[2], 20), num(a[3], 26))
        for _, p in ipairs(bp.fixed) do if p.Parent then p.Color = bp.color end end
        if bp.inf and bp.inf.Parent then bp.inf.Color = bp.color end
    end)
    def("Visual", "bpclear", "Remove the baseplate image", nil, function() bp.img = nil; styleAll() end)
    off(function() bp.img = nil end)

    -- No jump cooldown
    local njc
    pair("Movement", "nojumpcooldown", "unnojumpcooldown", "Remove jump cooldown in games", "Disable nojumpcooldown", nil,
        function()
            if njc then return end
            njc = UIS.JumpRequest:Connect(function()
                local h = hum()
                if h and h.FloorMaterial ~= Enum.Material.Air then h:ChangeState(Enum.HumanoidStateType.Jumping) end
            end)
        end, function() if njc then njc:Disconnect(); njc = nil end end)

    -- Sit walk
    local sw
    local function swOff() if sw then sw:Stop(); sw = nil end end
    pair("Movement", "sitwalk", "unsitwalk", "Walk with sit animation", "Restore walk animation", nil,
        function()
            swOff()
            local h = hum()
            local an = h and h:FindFirstChildOfClass("Animator")
            if not an then return end
            local a = Instance.new("Animation"); a.AnimationId = "rbxassetid://2506281703"
            local ok, tr = pcall(function() return an:LoadAnimation(a) end)
            if ok and tr then tr.Looped, tr.Priority = true, Enum.AnimationPriority.Action; tr:Play(); sw = tr end
        end, swOff)

    -- Spasm
    local sp = {}
    local function spOff() if sp.conn then sp.conn:Disconnect(); sp.conn = nil end end
    pair("Character", "spasm", "unspasm", "Twitch your body randomly", "Stop spasm", nil,
        function()
            spOff()
            sp.conn = RunService.RenderStepped:Connect(function()
                local c = lp.Character
                if not c then return end
                for _, m in ipairs(c:GetDescendants()) do
                    if m:IsA("Motor6D") and m.Name ~= "RootJoint" and m.Name ~= "Root" then
                        m.Transform = CFrame.Angles(math.rad(math.random(-40, 40)), math.rad(math.random(-40, 40)), math.rad(math.random(-40, 40)))
                    end
                end
            end)
        end, spOff)

    -- Backflip
    def("Movement", "flip", "Do a backflip", nil, function()
        local r, h = root(), hum()
        if not (r and h) then return end
        h:ChangeState(Enum.HumanoidStateType.Jumping)
        local start = r.CFrame
        local t0 = os.clock()
        while os.clock() - t0 < 0.6 and r.Parent do
            local a = (os.clock() - t0) / 0.6 * math.pi * 2
            r.CFrame = CFrame.new(r.Position) * CFrame.fromOrientation(0, select(2, start:ToOrientation()), 0) * CFrame.Angles(-a, 0, 0)
            RunService.Heartbeat:Wait()
        end
        r.CFrame = CFrame.new(r.Position) * CFrame.fromOrientation(0, select(2, start:ToOrientation()), 0)
    end, {"sexyflip", "backflip"})

    -- Helicopter
    def("Movement", "helicopter", "Fly while spinning like a helicopter", "[speed]", function(a)
        runLine("fly"); runLine("spin " .. tostring(num(a[1], 40)))
    end)
    def("Movement", "unhelicopter", "Stop helicopter fly", nil, function() runLine("unfly"); runLine("unspin") end)

    -- Fake out
    def("Movement", "fakeout", "Briefly void yourself then snap back", nil, function()
        local r = root()
        if not r then return end
        local cf = r.CFrame
        r.CFrame = CFrame.new(cf.X, -480, cf.Z)
        task.wait(0.15)
        r.CFrame = cf
        r.AssemblyLinearVelocity = Vector3.new()
    end)

    -- Rewind (hold Z)
    local rw = {hist = {}}
    local function rwOff()
        if rw.conn then rw.conn:Disconnect(); rw.conn = nil end
        rw.hist = {}
    end
    pair("Movement", "rewind", "unrewind", "Hold Z to rewind your position", "Disable rewind", nil,
        function()
            rwOff()
            rw.conn = RunService.Heartbeat:Connect(function()
                local r = root()
                if not r then return end
                if UIS:IsKeyDown(Enum.KeyCode.Z) and not typing() then
                    local cf = table.remove(rw.hist)
                    if cf then r.CFrame = cf; r.AssemblyLinearVelocity = Vector3.new() end
                else
                    rw.hist[#rw.hist + 1] = r.CFrame
                    if #rw.hist > 900 then table.remove(rw.hist, 1) end
                end
            end)
        end, rwOff)

    -- Invis: park yourself under the map. Others can't see you, but you stay alive and can still chat.
    local inv = invisState
    local function invOff(silent)
        stopLoop("invis")
        if inv.part then inv.part:Destroy(); inv.part = nil end
        local cam = workspace.CurrentCamera
        if inv.cam then
            if cam and cam.CameraSubject == inv.cam then
                local hh = hum()
                if hh then cam.CameraSubject = hh end
            end
            inv.cam:Destroy(); inv.cam = nil
        end
        local r = root()
        if inv.on and not silent and r and inv.back and inv.char == lp.Character then
            r.CFrame = inv.back
            r.AssemblyLinearVelocity = Vector3.new()
        end
        inv.on, inv.back, inv.char, inv.y, inv.depth = false, nil, nil, nil, nil
    end
    pair("Movement", "invis", "uninvis", "Hide under the map (you can still chat)", "Come back up to where you were", "[depth]",
        function(a)
            invOff(true)
            local r, h = root(), hum()
            if not (r and h) then say("Character not ready"); return end
            local pos = r.Position
            local depth = math.clamp(num(a[1], 60), 10, 5000)
            local y = pos.Y - depth
            local void = workspace.FallenPartsDestroyHeight
            if y < void + 30 then y = void + 30 end -- stay clear of the height where the game deletes you
            if y > pos.Y - 15 then say("The map is too low to hide under"); return end
            inv.on, inv.back, inv.char, inv.y, inv.depth = true, r.CFrame, lp.Character, y, depth
            local p = Instance.new("Part")
            p.Name, p.Anchored, p.Size, p.Transparency = "C1InvisPad", true, Vector3.new(40, 2, 40), 1
            p.CanTouch, p.CanQuery, p.CastShadow = false, false, false
            p.Parent = workspace
            inv.part = p
            -- camera anchor: an invisible part at your old height that follows you sideways, so the camera
            -- stays above the ground instead of following you underneath it
            local cp = Instance.new("Part")
            cp.Name, cp.Anchored, cp.Size, cp.Transparency = "C1InvisCam", true, Vector3.new(1, 1, 1), 1
            cp.CanCollide, cp.CanTouch, cp.CanQuery, cp.CastShadow = false, false, false, false
            cp.CFrame = CFrame.new(pos)
            cp.Parent = workspace
            inv.cam, inv.camY = cp, pos.Y
            local function stand(rr, hh)
                return CFrame.new(rr.Position.X, inv.y - (hh.HipHeight + rr.Size.Y / 2) - 1, rr.Position.Z)
            end
            r.CFrame = CFrame.new(pos.X, y, pos.Z) * (r.CFrame - r.CFrame.Position)
            r.AssemblyLinearVelocity = Vector3.new()
            p.CFrame = stand(r, h)
            do
                local cam = workspace.CurrentCamera
                if cam then cam.CameraSubject = cp end
            end
            startLoop("invis", 0, function()
                local rr, hh = root(), hum()
                if not (rr and hh and p.Parent) or inv.char ~= lp.Character or hh.Health <= 0 then
                    invOff(true) -- died / respawned: nothing to return to
                    return
                end
                if rr.Position.Y < inv.y - 12 then -- slipped off the pad
                    rr.CFrame = CFrame.new(rr.Position.X, inv.y, rr.Position.Z)
                    rr.AssemblyLinearVelocity = Vector3.new()
                end
                p.CFrame = stand(rr, hh)
                local cam = workspace.CurrentCamera
                if inv.cam and inv.cam.Parent then
                    inv.cam.CFrame = CFrame.new(rr.Position.X, inv.camY, rr.Position.Z)
                    if cam and cam.CameraSubject ~= inv.cam then cam.CameraSubject = inv.cam end
                end
            end)
            say("Invisible under the map: " .. tostring(math.floor(pos.Y - y)) .. " studs down. uninvis to return")
        end, function() invOff(false) end, {"hideunder", "vanish"}, {"uninvisible", "unvanish"})

    -- Ragdoll hide: your real (ragdolled, replicated) body goes under the map; you keep walking around as the
    -- invisible clone above. Others can't see you but your chat still works.
    pair("Movement", "ragdollhide", "unragdollhide", "Put your ragdoll under the map while you keep moving above (starts reanim)",
        "Bring your ragdoll back up", "[depth]",
        function(a)
            local depth = math.clamp(num(a[1], 60), 10, 5000)
            if type(G.ReanimlolCleanup) ~= "function" then
                local ok, err = pcall(ReanimlolModule)
                if not ok then warn("cookie hub: reanim failed: " .. tostring(err)); say("Reanim failed to load"); return end
            end
            if type(G.ReanimlolTurnOn) ~= "function" then say("Reanim not ready"); return end
            G.ReanimlolTurnOn(function()
                if G.ReanimlolHide and G.ReanimlolHide(depth) then
                    say("Ragdoll hidden " .. tostring(depth) .. " studs down. unragdollhide to bring it back")
                else
                    say("Reanim isn't running")
                end
            end)
        end,
        function()
            if type(G.ReanimlolHide) == "function" then pcall(G.ReanimlolHide, nil) end
        end, {"hideragdoll", "rghide"}, {"unhideragdoll", "unrghide"})

    def("Character", "fitclips", "Fit emotes and imported animations to your avatar's rig and size (on/off, no arg toggles)", "[on|off]", function(a)
        local v = tostring(a[1] or ""):lower()
        local cur = G.ReanimlolFit ~= false
        if v == "on" then cur = true elseif v == "off" then cur = false else cur = not cur end
        G.ReanimlolFit = cur
        if type(G.ReanimlolRefit) == "function" then pcall(G.ReanimlolRefit) end
        say("Fit clips to my avatar: " .. (cur and "on" or "off"))
    end, {"fitanims"})

    -- Friends
    def("Utility", "friend", "Send friend request", "<player>", function(a)
        local p = findPlayer(a[1])
        if p then pcall(function() StarterGui:SetCore("PromptSendFriendRequest", p) end) else say("Player not found") end
    end)
    def("Utility", "unfriend", "Revoke friendship", "<player>", function(a)
        local p = findPlayer(a[1])
        if p then pcall(function() StarterGui:SetCore("PromptUnfriend", p) end) else say("Player not found") end
    end)
end
do
    ------------------------------------------------------------------
    -- Player actions: headsit, behind, animcopy (+ Players panel)
    ------------------------------------------------------------------
    local hs = {}
    local function hsOff()
        if hs.conn then hs.conn:Disconnect(); hs.conn = nil end
        local h = hum()
        if hs.on and h then h.Sit = false end
        hs.on = false
    end
    pair("Teleport", "headsit", "unheadsit", "Sit on a player's head", "Get off the player's head", "<player>",
        function(a)
            hsOff()
            local p = findPlayer(a[1])
            if not p or p == lp then say("Player not found"); return end
            hs.on = true
            hs.conn = RunService.Heartbeat:Connect(function()
                local c = p.Character
                local head = c and c:FindFirstChild("Head")
                local r, h = root(), hum()
                if not (head and r and h) then return end
                h.Sit = true
                r.CFrame = head.CFrame * CFrame.new(0, head.Size.Y / 2 + 1.6, 0)
                r.AssemblyLinearVelocity = Vector3.new()
            end)
        end, hsOff)

    def("Teleport", "behind", "Teleport behind a player", "<player>", function(a)
        local _, pr = targetRoot(a[1])
        local r = root()
        if not (pr and r) then say("Player not found"); return end
        r.CFrame = pr.CFrame * CFrame.new(0, 0, 3)
    end)
    local ac = {tracks = {}, cache = {char = nil, list = {}}, badT = 0, stretch = true, jc = {}}
    local SKIP_ID = "507768375" -- same default animation Novoline's copyemote skips
    local function acMotors()
        local mc = lp.Character
        if ac.cache.char ~= mc then
            ac.cache.char, ac.cache.list = mc, {}
            if mc then
                for _, m in ipairs(mc:GetDescendants()) do
                    if m:IsA("Motor6D") and m.Part0 and m.Part1 then ac.cache.list[#ac.cache.list + 1] = m end
                end
            end
        end
        return ac.cache.list
    end
    -- Pose copy, fitted to YOUR avatar. Only joint rotations are copied (so limbs never stretch or detach on a
    -- different body size), the root joint's translation is scaled by body height, and R6 <-> R15 targets are
    -- mapped part by part (R6 arm = R15 upper arm, torso = upper/lower torso, ...). Joints with no counterpart relax.
    local R15_TO_R6 = {UpperTorso = "Torso", LowerTorso = "Torso", LeftUpperArm = "Left Arm", RightUpperArm = "Right Arm",
        LeftUpperLeg = "Left Leg", RightUpperLeg = "Right Leg"}
    local R6_TO_R15 = {["Left Arm"] = "LeftUpperArm", ["Right Arm"] = "RightUpperArm", ["Left Leg"] = "LeftUpperLeg",
        ["Right Leg"] = "RightUpperLeg"}
    local function bodyHeight(model)
        local h = model and model:FindFirstChildOfClass("Humanoid")
        local r = model and model:FindFirstChild("HumanoidRootPart")
        if not (h and r) then return 5 end
        if h.RigType == Enum.HumanoidRigType.R6 then return 3 * (r.Size.Y / 2) + 0.01 end -- legs 2 + half torso 1, scaled by root
        return math.max(h.HipHeight + r.Size.Y / 2, 0.5)
    end
    -- the target's part that matches one of my parts; `other` is the part on the far side of the joint
    local function matchPart(tc, name, other)
        local direct = tc:FindFirstChild(name)
        if direct and direct:IsA("BasePart") then return direct end
        local alias
        if name == "Torso" then -- my R6 torso <- their R15 upper/lower torso
            local low = other == "HumanoidRootPart" or (other and other:find("Leg", 1, true) ~= nil)
            alias = low and "LowerTorso" or "UpperTorso"
        else
            alias = R15_TO_R6[name] or R6_TO_R15[name]
        end
        local p = alias and tc:FindFirstChild(alias)
        return p and p:IsA("BasePart") and p or nil
    end
    -- the target's real joint data (C0, C1) for the joint between t0 (parent) and t1 (child).
    -- Uses their Motor6D if it exists; a reanimating target has none, so fall back to the rig attachments.
    local function targetJoint(tc, motor, t0, t1)
        for _, m in ipairs(tc:GetDescendants()) do
            if m:IsA("Motor6D") and m.Part0 == t0 and m.Part1 == t1 then return m.C0, m.C1 end
        end
        local an = motor.Name .. "RigAttachment"
        local a0, a1 = t0:FindFirstChild(an), t1:FindFirstChild(an)
        if a0 and a1 and a0:IsA("Attachment") and a1:IsA("Attachment") then return a0.CFrame, a1.CFrame end
    end
    local function applyPose(dt, full)
        local tc = ac.target and ac.target.Character
        local mc = lp.Character
        if not (tc and mc) then return 0 end
        if ac.jc.char ~= tc then ac.jc = {char = tc, map = weak()} end
        local k = full and 1 or (1 - math.exp(-(dt or 1 / 60) * 35))
        local scale = bodyHeight(mc) / bodyHeight(tc)
        local mh0, th0 = mc:FindFirstChildOfClass("Humanoid"), tc:FindFirstChildOfClass("Humanoid")
        local sameRig = mh0 and th0 and mh0.RigType == th0.RigType
        local n = 0
        for _, m in ipairs(acMotors()) do
            local p0, p1 = m.Part0, m.Part1
            if p0 and p1 and m.Parent then
                local t0, t1 = matchPart(tc, p0.Name, p1.Name), matchPart(tc, p1.Name, p0.Name)
                local want = CFrame.identity
                if t0 and t1 and t0 ~= t1 then
                    local isRoot = p0.Name == "HumanoidRootPart"
                    local tC0, tC1
                    if sameRig then
                        local cached = ac.jc.map[m]
                        if cached == nil then
                            local a, b = targetJoint(tc, m, t0, t1)
                            cached = a and {a, b} or false
                            ac.jc.map[m] = cached
                        end
                        if cached then tC0, tC1 = cached[1], cached[2] end
                    end
                    if tC0 then
                        -- exact transform of THEIR joint, so it can't be skewed by body proportions
                        local tr = (t0.CFrame * tC0):Inverse() * (t1.CFrame * tC1)
                        want = tr.Rotation
                        local pos = tr.Position
                        if isRoot or (ac.stretch and pos.Magnitude > 0.15) then
                            pos = pos * scale
                            if pos.Magnitude > 150 then pos = pos.Unit * 150 end
                            want = CFrame.new(pos) * want
                        end
                    else
                        -- different rig types: map part by part, rotation only (plus root crouch/lift)
                        local rel = (t0.CFrame * m.C0.Rotation):Inverse() * (t1.CFrame * m.C1.Rotation)
                        want = rel.Rotation
                        if isRoot then
                            local pos = ((t0.CFrame * m.C0):Inverse() * t1.CFrame * m.C1).Position * scale
                            if pos.Magnitude > 150 then pos = pos.Unit * 150 end
                            want = CFrame.new(pos) * want
                        end
                    end
                end
                m.Transform = k >= 1 and want or m.Transform:Lerp(want, k)
                n += 1
            end
        end
        return n
    end
    local function stopCopies()
        for t, tr in pairs(ac.tracks) do
            if tr then pcall(function() tr:Stop(0.1); tr:Destroy() end) end
            ac.tracks[t] = nil
        end
    end
    local function acOff()
        for _, key in ipairs({"conn", "render"}) do
            if ac[key] then ac[key]:Disconnect(); ac[key] = nil end
        end
        if ac.hook and G.ReanimlolOverride == ac.hook then G.ReanimlolOverride = nil end
        ac.hook, ac.target, ac.motor, ac.force, ac.reanim, ac.tReanim = nil, nil, false, false, false, nil
        stopCopies()
        ac.badT = 0
        if ac.usedMotor then
            for _, m in ipairs(ac.cache.list) do
                if m.Parent then pcall(function() m.Transform = CFrame.identity end) end
            end
        end
        ac.usedMotor = false
        ac.cache = {char = nil, list = {}}
        local c = lp.Character
        local an = c and c:FindFirstChild("Animate")
        if an and ac.hadAnimate then an.Disabled = false end
        ac.hadAnimate, ac.char = false, nil
        ac.jc = {}
        if type(G.ReanimlolRealign) == "function" then pcall(G.ReanimlolRealign) end -- snap ragdoll back onto the clone
    end
    -- Works like Novoline's copyemote: every animation the target is playing is loaded on your own animator,
    -- started at the same time position and speed, and stopped when the target's track stops. It keeps watching,
    -- so animations the target starts later are copied too.
    pair("Character", "animcopy", "unanimcopy", "Copy a player's playing animations (Novoline-style sync)", "Stop copying animations", "<player> [motor]",
        function(a)
            acOff()
            local p = findPlayer(a[1])
            if not p or p == lp then say("Player not found"); return end
            ac.target = p
            ac.force = tostring(a[2] or ""):lower() == "motor"
            ac.badT = 0
            -- while reanimated the engine resets joints every step, so pose-copy is applied at the end of each step
            ac.hook = function(dt) if ac.motor then applyPose(dt, true) end end
            G.ReanimlolOverride = ac.hook
            ac.render = RunService.RenderStepped:Connect(function(dt)
                if ac.motor and not ac.reanim then applyPose(dt, false) end
            end)
            ac.conn = RunService.Heartbeat:Connect(function(dt)
                local tp = ac.target
                if not tp or not tp.Parent then acOff(); say("Copy target left"); return end
                local mc = lp.Character
                if not mc then return end
                if ac.char ~= mc then stopCopies(); ac.char, ac.badT = mc, 0 end
                local an0 = mc:FindFirstChild("Animate")
                if an0 and an0:IsA("LocalScript") and not an0.Disabled then an0.Disabled = true; ac.hadAnimate = true end

                local tc = tp.Character
                local th = tc and tc:FindFirstChildOfClass("Humanoid")
                local tan = th and th:FindFirstChildOfClass("Animator")
                local tracks = tan and tan:GetPlayingAnimationTracks() or {}
                local reanimBody = mc.Name == "ReanimlolBody"
                ac.reanim = reanimBody
                local mh = hum()
                local man = mh and (mh:FindFirstChildOfClass("Animator") or mh)

                -- the target's copyable tracks
                local wanted, nWanted = {}, 0
                for _, t in ipairs(tracks) do
                    local anim = t.Animation
                    local id = anim and anim.AnimationId or ""
                    if anim and id ~= "" and not id:find(SKIP_ID, 1, true) then
                        wanted[t] = anim
                        nWanted += 1
                    end
                end

                local playing, loaded = 0, 0
                for _, tr in pairs(ac.tracks) do
                    if tr then loaded += 1; if tr.IsPlaying then playing += 1 end end
                end
                if nWanted > 0 and loaded > 0 and playing == 0 then ac.badT += dt else ac.badT = 0 end
                local fallback = ac.badT > 0.6

                -- a reanimating target has no working joints (their body is ragdolled and snapped onto an invisible
                -- clone), so their emotes only exist as part positions, never as animation tracks
                local tReanim = false
                if tc then
                    local joints = 0
                    for _, d in ipairs(tc:GetDescendants()) do
                        if d:IsA("Motor6D") and d.Part0 and d.Part1 and d.Part1.Parent == tc then joints += 1 end
                        if d:IsA("BallSocketConstraint") then tReanim = true end
                    end
                    if joints < 3 then tReanim = true end
                    if tc.Name == "ReanimlolBody" then tReanim = true end
                end
                if tReanim ~= ac.tReanim then
                    ac.tReanim = tReanim
                    say(tReanim and "Target is reanimating: copying pose" or "Copying animation tracks")
                end

                local rigMismatch = th and mh and th.RigType ~= mh.RigType
                ac.motor = ac.force or tReanim or rigMismatch or reanimBody or nWanted == 0 or not man or fallback
                if ac.motor then
                    ac.usedMotor = true
                    if not fallback then stopCopies() end
                    if man and man:IsA("Animator") then
                        for _, tr in ipairs(man:GetPlayingAnimationTracks()) do
                            local mine = false
                            for _, m in pairs(ac.tracks) do if m == tr then mine = true; break end end
                            if not mine then tr:Stop(0) end
                        end
                    end
                    applyPose(dt, true)
                    return
                end

                -- clear my own other animations (default idle etc.)
                if man:IsA("Animator") then
                    for _, tr in ipairs(man:GetPlayingAnimationTracks()) do
                        local mine = false
                        for _, m in pairs(ac.tracks) do if m == tr then mine = true; break end end
                        if not mine then tr:Stop(0) end
                    end
                end
                -- start a copy of every new target track, keep timing in sync, drop copies whose source stopped
                for t, anim in pairs(wanted) do
                    local mine = ac.tracks[t]
                    if mine == nil then
                        local ok, tr = pcall(function() return man:LoadAnimation(anim) end)
                        if ok and tr then
                            ac.tracks[t] = tr
                            tr:Play(0.1, 1, t.Speed)
                            tr.TimePosition = t.TimePosition
                        else
                            ac.tracks[t] = false
                        end
                    elseif mine then
                        if not mine.IsPlaying then mine:Play(0.1, 1, t.Speed) end
                        local diff, len = math.abs(mine.TimePosition - t.TimePosition), mine.Length
                        if len > 0 then diff = math.min(diff, len - diff) end
                        if diff > 0.3 then mine.TimePosition = t.TimePosition end
                        mine:AdjustSpeed(t.Speed)
                    end
                end
                for t, tr in pairs(ac.tracks) do
                    if not wanted[t] then
                        if tr then pcall(function() tr:Stop(0.1); tr:Destroy() end) end
                        ac.tracks[t] = nil
                    end
                end
            end)
        end, acOff)
    def("Character", "copystretch", "Copy stretched limbs in anim copy (on/off, no arg toggles)", "[on|off]", function(a)
        local v = tostring(a[1] or ""):lower()
        if v == "on" then ac.stretch = true elseif v == "off" then ac.stretch = false else ac.stretch = not ac.stretch end
        say("Copy stretch " .. (ac.stretch and "on" or "off"))
    end, {"stretch"})
    def("Character", "kfcopy", "Copy a player's pose even if they use keyframes", "<player>", function(a)
        runLine("animcopy " .. tostring(a[1] or "") .. " motor")
    end, {"motorcopy"})
    def("Character", "unkfcopy", "Stop keyframe pose copy", nil, function() runLine("unanimcopy") end, {"unmotorcopy"})
    def("Character", "realign", "Snap your ragdoll back onto your reanim body and clear stuck joints", nil, function()
        if type(G.ReanimlolRealign) == "function" and G.ReanimlolRealign() then
            say("Ragdoll realigned")
        else
            say("Reanim isn't running")
        end
    end, {"fixragdoll", "ragdollfix"})

    ------------------------------------------------------------------
    -- Players panel
    ------------------------------------------------------------------
    local PW2, PH2 = 460, 450
    local pp = mk("Frame", {Size = UDim2.fromOffset(PW2, PH2), Position = UDim2.new(0.5, 250, 0.5, -PH2 / 2 + 40),
        BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = .16, Active = true, Visible = false}, gui)
    glass(pp, 20)
    local ppScale = Instance.new("UIScale")
    ppScale.Parent = pp
    local ph = mk("Frame", {Size = UDim2.new(1, 0, 0, 52), BackgroundTransparency = 1}, pp)
    draggable(ph, pp)
    mk("TextLabel", {Text = "Players", Font = Enum.Font.GothamBold, TextSize = 20, Position = UDim2.fromOffset(20, 0),
        Size = UDim2.fromOffset(160, 52), TextXAlignment = Enum.TextXAlignment.Left}, ph)
    accentLine(pp, 20, 52, PW2 - 40)
    local psearch = fieldBox(pp, "Search players...", 20, 64, PW2 - 40, 34)
    local plist = mk("ScrollingFrame", {Position = UDim2.fromOffset(20, 106), Size = UDim2.fromOffset(PW2 - 40, 134),
        BackgroundTransparency = 1, ScrollBarThickness = 3, ScrollBarImageColor3 = C.accent, CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y}, pp)
    mk("UIListLayout", {Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder}, plist)
    mk("UIPadding", {PaddingRight = UDim.new(0, 8)}, plist)

    local thumbs = {}
    local function loadThumb(img, uid)
        if thumbs[uid] then img.Image = thumbs[uid]; return end
        task.spawn(function()
            local ok, url = pcall(function()
                return Players:GetUserThumbnailAsync(uid, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
            end)
            if ok and url then
                thumbs[uid] = url
                if img.Parent then img.Image = url end
            end
        end)
    end

    -- selected player card
    local selCard = mk("Frame", {Position = UDim2.fromOffset(20, 250), Size = UDim2.fromOffset(PW2 - 40, 58),
        BackgroundColor3 = C.card, BackgroundTransparency = .3}, pp)
    corner(selCard, 14)
    local selStroke = Instance.new("UIStroke")
    selStroke.Color, selStroke.Thickness, selStroke.Transparency, selStroke.ApplyStrokeMode = C.div, 1.2, .3, Enum.ApplyStrokeMode.Border
    selStroke.Parent = selCard
    local selAv = mk("ImageLabel", {Size = UDim2.fromOffset(40, 40), Position = UDim2.fromOffset(9, 9), BackgroundColor3 = C.field, Image = ""}, selCard)
    corner(selAv, 20)
    local selName = mk("TextLabel", {Text = "No player selected", Font = Enum.Font.GothamBold, TextSize = 14,
        Position = UDim2.fromOffset(60, 9), Size = UDim2.new(1, -70, 0, 20), TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd}, selCard)
    local selSub = mk("TextLabel", {Text = "Pick someone from the list above", TextSize = 11, TextColor3 = C.dim,
        Position = UDim2.fromOffset(60, 30), Size = UDim2.new(1, -70, 0, 16), TextXAlignment = Enum.TextXAlignment.Left}, selCard)

    local baseSay = say
    local pStatus = mk("TextLabel", {Text = "", TextSize = 11, TextColor3 = C.dim, Position = UDim2.fromOffset(20, 424),
        Size = UDim2.fromOffset(PW2 - 40, 16), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd}, pp)
    say = function(t) baseSay(t); pStatus.Text = tostring(t) end

    local sel
    local flags, btns = {}, {}
    local refreshPlayers
    local function setFlag(k, v)
        flags[k] = v
        if btns[k] then
            tween(btns[k], {BackgroundColor3 = v and C.accent or C.card, BackgroundTransparency = v and 0 or .2}, TweenInfo.new(.2))
        end
    end
    local function select(p)
        sel = p
        selName.Text = p.DisplayName
        selSub.Text = "@" .. p.Name
        loadThumb(selAv, p.UserId)
        tween(selStroke, {Color = C.accent, Transparency = 0}, TweenInfo.new(.2))
        refreshPlayers()
    end
    refreshPlayers = function()
        for _, c in ipairs(plist:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end
        local q = psearch.Text:lower()
        local order = 0
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= lp and (q == "" or p.Name:lower():find(q, 1, true) or p.DisplayName:lower():find(q, 1, true)) then
                order = order + 1
                local on = (sel == p)
                local row = mk("TextButton", {Text = "", Size = UDim2.new(1, 0, 0, 38), LayoutOrder = order,
                    BackgroundColor3 = C.accent, BackgroundTransparency = on and .6 or .93}, plist)
                corner(row, 10)
                local av = mk("ImageLabel", {Size = UDim2.fromOffset(28, 28), Position = UDim2.fromOffset(8, 5),
                    BackgroundColor3 = C.field, Image = ""}, row)
                corner(av, 14)
                loadThumb(av, p.UserId)
                mk("TextLabel", {Text = p.DisplayName, Font = Enum.Font.GothamBold, TextSize = 13, Position = UDim2.fromOffset(44, 3),
                    Size = UDim2.new(1, -54, 0, 17), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd}, row)
                mk("TextLabel", {Text = "@" .. p.Name, TextSize = 10, TextColor3 = C.dim, Position = UDim2.fromOffset(44, 20),
                    Size = UDim2.new(1, -54, 0, 14), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd}, row)
                row.MouseEnter:Connect(function() if sel ~= p then tween(row, {BackgroundTransparency = .8}, TweenInfo.new(.12)) end end)
                row.MouseLeave:Connect(function() if sel ~= p then tween(row, {BackgroundTransparency = .93}, TweenInfo.new(.18)) end end)
                row.Activated:Connect(function() select(p) end)
            end
        end
    end
    bind(psearch:GetPropertyChangedSignal("Text"), function() refreshPlayers() end)
    bind(Players.PlayerAdded, function() refreshPlayers() end)
    bind(Players.PlayerRemoving, function(p)
        if sel == p then
            sel = nil
            selName.Text, selSub.Text, selAv.Image = "No player selected", "Pick someone from the list above", ""
            tween(selStroke, {Color = C.div, Transparency = .3}, TweenInfo.new(.2))
        end
        task.defer(refreshPlayers)
    end)

    local function need()
        if not sel or not sel.Parent then say("Select a player first"); return nil end
        return sel
    end
    local function act(key)
        local p = need()
        if not p then return end
        local n = p.Name
        if key == "tp" then runLine("goto " .. n)
        elseif key == "behind" then runLine("behind " .. n)
        elseif key == "sit" then
            if flags.sit then runLine("unheadsit"); setFlag("sit", false) else runLine("headsit " .. n); setFlag("sit", true) end
        elseif key == "copy" then
            if flags.copy then runLine("unanimcopy"); setFlag("copy", false) else runLine("animcopy " .. n); setFlag("copy", true) end
        elseif key == "spec" then
            if flags.spec then runLine("unspectate"); setFlag("spec", false) else runLine("spectate " .. n); setFlag("spec", true) end
        elseif key == "hide" then
            if flags.hide then runLine("unhide " .. n); setFlag("hide", false) else runLine("hide " .. n); setFlag("hide", true) end
        end
    end
    accentLine(pp, 20, 318, PW2 - 40)
    local grid = {{"tp", "Teleport"}, {"sit", "Sit"}, {"copy", "Anim Copy"}, {"behind", "Behind"}, {"spec", "Spectate"}, {"hide", "Hide"}}
    for i, g in ipairs(grid) do
        local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
        local b = mk("TextButton", {Text = g[2], TextSize = 13, Position = UDim2.fromOffset(20 + col * 142, 332 + row * 46),
            Size = UDim2.fromOffset(134, 38), BackgroundColor3 = C.card, BackgroundTransparency = .2}, pp)
        corner(b, 12)
        local st = Instance.new("UIStroke")
        st.Color, st.Thickness, st.Transparency, st.ApplyStrokeMode = C.div, 1, .4, Enum.ApplyStrokeMode.Border
        st.Parent = b
        b.MouseEnter:Connect(function() tween(st, {Color = C.accent, Transparency = 0}, TweenInfo.new(.12)) end)
        b.MouseLeave:Connect(function() tween(st, {Color = C.div, Transparency = .4}, TweenInfo.new(.18)) end)
        press(b)
        b.Activated:Connect(function() act(g[1]) end)
        btns[g[1]] = b
    end
    off(function() for k in pairs(flags) do setFlag(k, false) end end)
    refreshPlayers()

    local function setPP(show)
        if show then
            pp.Visible = true
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
        if not ok then warn("cookie hub: reanim failed: " .. tostring(err)); say("Reanim failed to load") end
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
