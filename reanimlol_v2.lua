-- reanimlol v3 (restyled GUI, animated tab / category switching, default Roblox animations suppressed)
-- Body reanimation + emote library (categories / sub-categories / favorites / custom),
-- walk/idle/run/jump/fall/climb/swim state overrides, speed + blend controls,
-- R6/R15 detection, rebindable hotkeys and a keyframe recorder.
-- No downloaded code or game remotes. Enable the toggle (or press the hotkey) first.
-- Saved data (favorites, custom emotes, state picks, settings, recordings) is written to
-- the "Reanimlol" folder when your executor supports writefile/readfile.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Provider = game:GetService("KeyframeSequenceProvider")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
assert(player, "Run reanimlol on the client")

local shared = getgenv and getgenv() or _G
if type(shared.ReanimlolCleanup) == "function" then pcall(shared.ReanimlolCleanup) end

----------------------------------------------------------------------
-- CORE: body reanimation (unchanged logic from v1)
----------------------------------------------------------------------
local bodyReanim = (function()
local state = {
 services={players=game:GetService("Players"),workspace=game:GetService("Workspace"),
 run_service=game:GetService("RunService"),user_input_service=game:GetService("UserInputService")},
 flags={reanimated=false},rig={revision=0,starting=false},clones={},real_chars={},connections={},callbacks={},
 animation={joints={},original_motor_c0s={}},
}
local api={set_arm_poles=function() end,stop_animation=function() end}
local function cloneCharacter(arg2)
  if typeof(arg2) ~= "Instance" then
    return ("bad argument #1 to 'clone_char' (Instance expected, got %s)"):format(typeof(arg2))
  end
  local changed = {}
  local ok, clone = pcall(function()
    local objects = arg2:GetDescendants()
    table.insert(objects, arg2)
    for _, object in ipairs(objects) do
      if not object.Archivable then table.insert(changed, object); object.Archivable = true end
    end
    return arg2:Clone()
  end)
  for _, object in ipairs(changed) do pcall(function() object.Archivable = false end) end
  if not ok or not clone then return "Character clone failed." end
  for _, descendant in ipairs(clone:GetDescendants()) do
    if descendant:IsA("LuaSourceContainer") then descendant:Destroy() end
  end
  clone.Name = "ReanimlolBody"
  local humanoid = clone:FindFirstChildOfClass("Humanoid")
  if not humanoid then clone:Destroy(); return "Cloned character has no humanoid." end
  humanoid.RequiresNeck = false
  humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

  if clone:FindFirstChildWhichIsA("ForceField") then
    clone:FindFirstChildWhichIsA("ForceField"):Destroy()
  end

  return clone
end

local function bodyJoint(object, model)
  local a, b
  if object:IsA("JointInstance") or object:IsA("WeldConstraint") then
    a, b = object.Part0, object.Part1
  elseif object:IsA("Constraint") and not object:IsA("NoCollisionConstraint") then
    local ok, first, second = pcall(function() return object.Attachment0, object.Attachment1 end)
    if ok then
      a = first and first:FindFirstAncestorOfClass("BasePart")
      b = second and second:FindFirstAncestorOfClass("BasePart")
    end
  end
  return a and b and (a ~= b or object:IsA("Motor6D")) and a.Parent == model and b.Parent == model
end

local function remember(session, object, property)
  local properties = session.saved[object]
  if not properties then properties = {}; session.saved[object] = properties end
  if not properties[property] then properties[property] = {value = object[property]} end
end

local function own(session, className, parent, properties)
  local object = Instance.new(className)
  table.insert(session.owned, object)
  for property, value in pairs(properties) do object[property] = value end
  object.Parent = parent
  return object
end

local function sourceObject(session, object)
  if object:FindFirstAncestorOfClass("Tool") then return end
  if object:IsA("JointInstance") or object:IsA("WeldConstraint") or object:IsA("Constraint") then
    session.jointCandidates[object] = true
    if bodyJoint(object, session.character) then
      remember(session, object, "Enabled")
      if object:IsA("Motor6D") then
        for _, property in ipairs({"C0", "C1", "Transform"}) do remember(session, object, property) end
      end
      object.Enabled = false
    end
  elseif object:IsA("BasePart") then
    for _, property in ipairs({"CanCollide", "Massless", "CustomPhysicalProperties", "Transparency", "Size"}) do
      remember(session, object, property)
    end
    session.parts[object] = true
    object.CanCollide, object.Massless, object.Transparency = false, true, 1
    object.CustomPhysicalProperties = PhysicalProperties.new(0.001, 0, 0, 0, 0)
  elseif object:IsA("Decal") then
    remember(session, object, "Transparency")
    object.Transparency = 1
  end
end

local function setSessionCamera(session)
  local camera = state.services.workspace.CurrentCamera
  if camera and camera.CameraSubject ~= session.copyHumanoid then
    if not session.cameras[camera] then session.cameras[camera] = {value = camera.CameraSubject} end
    camera.CameraSubject = session.copyHumanoid
  end
end

local function syncMovement(session)
  for _, property in ipairs({"WalkSpeed", "JumpPower", "JumpHeight", "UseJumpPower", "HipHeight", "MaxSlopeAngle", "AutoJumpEnabled", "AutoRotate"}) do
    if session.copyHumanoid[property] ~= session.humanoid[property] then
      session.copyHumanoid[property] = session.humanoid[property]
    end
  end
end

local stopReanimation
stopReanimation = function()
  state.rig.revision += 1
  state.rig.starting = false
  local session = state.rig.session
  state.rig.session = nil
  local wasActive = state.flags.reanimated
  state.flags.reanimated = false
  local errors = {}
  local function release(callback)
    local ok, message = pcall(callback)
    if not ok then table.insert(errors, tostring(message)) end
  end
  for key, connection in pairs(state.connections) do
    state.connections[key] = nil
    release(function() connection:Disconnect() end)
  end
  release(function() api.set_arm_poles(false) end)
  release(function() api.stop_animation() end)
  if session then
    for _, object in ipairs(session.owned) do release(function() object:Destroy() end) end
    -- Rebuild the body before restoring joints, collisions, and RequiresNeck.
    if session.character.Parent and session.player.Character == session.character and session.humanoid.Health > 0 then
      release(function()
        local frame = session.copyRoot and session.copyRoot.Parent and session.copyRoot.CFrame or session.root.CFrame
        local frames = {[session.root] = frame}
        for _ = 1, 20 do
          local changed = false
          for joint, properties in pairs(session.saved) do
            if properties.C0 and joint.Parent and joint.Part0 and joint.Part1 and frames[joint.Part0] and not frames[joint.Part1] then
              frames[joint.Part1] = frames[joint.Part0] * properties.C0.value * properties.Transform.value * properties.C1.value:Inverse()
              changed = true
            end
          end
          if not changed then break end
        end
        for _, link in ipairs(session.links) do
          if link.part.Parent then
            link.part.CFrame = frames[link.part] or link.base.CFrame
            link.part.AssemblyLinearVelocity, link.part.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
          end
        end
      end)
    end
    for object, properties in pairs(session.saved) do
      if object ~= session.humanoid then
        for property, saved in pairs(properties) do release(function() object[property] = saved.value end) end
      end
    end
    local humanoidProperties = session.saved[session.humanoid] or {}
    for property, saved in pairs(humanoidProperties) do
      if property ~= "RequiresNeck" and property ~= "PlatformStand" then
        release(function() session.humanoid[property] = saved.value end)
      end
    end
    for _, property in ipairs({"RequiresNeck", "PlatformStand"}) do
      local saved = humanoidProperties[property]
      if saved then release(function() session.humanoid[property] = saved.value end) end
    end
    for camera, saved in pairs(session.cameras) do
      release(function()
        if camera.CameraSubject == session.copyHumanoid then camera.CameraSubject = saved.value end
      end)
    end
    if session.copy then release(function() session.copy:Destroy() end) end
    state.clones[session.player], state.real_chars[session.player] = nil, nil
    if wasActive and session.humanoid.Parent and session.humanoid.Health > 0 and not session.humanoid.PlatformStand then
      release(function() session.humanoid:ChangeState(Enum.HumanoidStateType.GettingUp) end)
    end
  end
  state.animation.body, state.animation.ac_joint_map = nil, nil
  table.clear(state.animation.joints)
  table.clear(state.animation.original_motor_c0s)
  if wasActive and state.callbacks.on_deactivate then release(state.callbacks.on_deactivate) end
  if #errors > 0 then return "Stopped with cleanup errors: " .. table.concat(errors, "; ") end
end

local function startReanimation()
  if state.flags.reanimated then return end
  if state.rig.starting then return "Reanim is starting." end
  state.rig.revision += 1
  state.rig.starting = true
  local revision = state.rig.revision
  local function current() return revision == state.rig.revision end
  local ok, message = pcall(function()
    local player = state.services.players.LocalPlayer
    assert(player, "Local player is unavailable.")
    local character, humanoid, root, pending
    local deadline = os.clock() + 5
    repeat
      assert(current(), "Start cancelled.")
      character = player.Character
      if pending and pending ~= character then error("Character changed; try again.", 0) end
      pending = character
      humanoid = character and character:FindFirstChildOfClass("Humanoid")
      root = character and character:FindFirstChild("HumanoidRootPart")
      if humanoid and root then break end
      assert(os.clock() < deadline, "Wait for your character to respawn.")
      task.wait(0.05)
    until false
    assert(humanoid.Health > 0 and not root.Anchored, "Character is dead or anchored.")
    local mainFollower = root:FindFirstChild("rn_ap")
    assert(not (mainFollower and mainFollower:IsA("AlignPosition") and mainFollower.Enabled), "Turn off Main reanim before enabling Reanimlol.")
    -- This is the player's installed local controls module, not an asset or URL.
    local scripts = player:FindFirstChild("PlayerScripts")
    local module = scripts and scripts:FindFirstChild("PlayerModule")
    local controls
    if module and module:IsA("ModuleScript") then
      local loaded, value = pcall(function() return require(module):GetControls() end)
      local valid = loaded and value and pcall(function() assert(type(value.GetMoveVector) == "function") end)
      if valid then controls = value end
    end
    assert(current(), "Start cancelled.")
    assert(player.Character == character and character.Parent and humanoid.Parent == character and root.Parent == character
      and humanoid.Health > 0 and not root.Anchored, "Character changed; try again.")
    local session = {
      player = player, character = character, humanoid = humanoid, root = root,
      saved = {}, owned = {}, links = {}, parts = {}, jointCandidates = {}, cameras = {},
      controls = controls, focused = true,
    }
    state.rig.session = session
    state.real_chars[player] = character
    local copy = cloneCharacter(character)
    assert(typeof(copy) == "Instance", tostring(copy))
    session.copy = copy
    state.clones[player] = copy
    local copyHumanoid, copyRoot = copy:FindFirstChildOfClass("Humanoid"), copy:FindFirstChild("HumanoidRootPart")
    assert(copyHumanoid and copyRoot, "Cloned character rig is incomplete.")
    session.copyHumanoid, session.copyRoot = copyHumanoid, copyRoot
    copyHumanoid.RequiresNeck, copyHumanoid.BreakJointsOnDeath = false, false
    copyHumanoid.PlatformStand, copyHumanoid.Sit = false, false
    pcall(function() copyHumanoid.EvaluateStateMachine = true end)
    local hasMotors = false
    for _, object in ipairs(copy:GetDescendants()) do if object:IsA("Motor6D") then hasMotors = true; break end end
    assert(hasMotors, "This rig needs Motor6D joints.")
    local forceClasses = {BodyForce = true, BodyVelocity = true, BodyGyro = true, VectorForce = true, LinearVelocity = true, AngularVelocity = true}
    for _, object in ipairs(copy:GetDescendants()) do
      if object:IsA("LuaSourceContainer") or object:IsA("Tool") or forceClasses[object.ClassName] then
        object:Destroy()
      elseif object:IsA("BillboardGui") then object.Enabled = false
      elseif object:IsA("BasePart") then object.LocalTransparencyModifier = 0
      elseif bodyJoint(object, copy) then
        object.Enabled = object:IsA("Motor6D") or not hasMotors and object:IsA("AnimationConstraint")
      end
    end
    syncMovement(session)
    copy.Parent = state.services.workspace
    copyRoot.AssemblyLinearVelocity, copyRoot.AssemblyAngularVelocity = root.AssemblyLinearVelocity, Vector3.zero
    copyHumanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
    for _, property in ipairs({"RequiresNeck", "BreakJointsOnDeath", "PlatformStand", "DisplayDistanceType"}) do remember(session, humanoid, property) end
    local evaluated = pcall(function() remember(session, humanoid, "EvaluateStateMachine") end)
    humanoid.RequiresNeck, humanoid.BreakJointsOnDeath, humanoid.PlatformStand = false, false, true
    humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
    if evaluated then humanoid.EvaluateStateMachine = false end
    local animate = character:FindFirstChild("Animate")
    if animate and animate:IsA("LocalScript") then remember(session, animate, "Disabled"); animate.Disabled = true end
    local animator = humanoid:FindFirstChildOfClass("Animator")
    if animator then for _, track in ipairs(animator:GetPlayingAnimationTracks()) do track:Stop(0) end end
    for _, object in ipairs(character:GetDescendants()) do sourceObject(session, object) end
    for _, part in ipairs(character:GetChildren()) do
      local base = copy:FindFirstChild(part.Name)
      if part:IsA("BasePart") and base and base:IsA("BasePart") then
        local a0 = own(session, "Attachment", part, {Name = "ReanimlolFollower0"})
        local a1 = own(session, "Attachment", base, {Name = "ReanimlolFollower1"})
        own(session, "AlignPosition", part, {
          Name = "ReanimlolPosition", Attachment0 = a0, Attachment1 = a1,
          RigidityEnabled = true, ReactionForceEnabled = false,
        })
        own(session, "AlignOrientation", part, {
          Name = "ReanimlolOrientation", Attachment0 = a0, Attachment1 = a1,
          RigidityEnabled = true, ReactionTorqueEnabled = false,
        })
        table.insert(session.links, {part = part, base = base})
      end
    end
    state.animation.body = copy
    table.clear(state.animation.joints)
    table.clear(state.animation.original_motor_c0s)
    for _, object in ipairs(copy:GetDescendants()) do
      if object:IsA("Motor6D") and object.Part1 then
        state.animation.joints[object.Part1.Name] = object
        state.animation.original_motor_c0s[object] = object.C0
      end
    end
    state.animation.ac_joint_map = nil
    state.flags.reanimated = true
    local function listen(name, signal, callback)
      state.connections[name] = signal:Connect(function(...)
        if not current() or state.rig.session ~= session then return end
        local handled, problem = pcall(callback, ...)
        if not handled and current() then
          stopReanimation()
          warn("Reanimlol reanim: " .. tostring(problem))
        end
      end)
    end
    local function validRig()
      return player.Character == character and character.Parent and copy.Parent
        and humanoid.Parent == character and root.Parent == character
        and copyHumanoid.Parent == copy and copyRoot.Parent == copy
        and character:FindFirstChild("HumanoidRootPart") == root and not root.Anchored
    end
    local function driveFollowers()
      for _, link in ipairs(session.links) do
        if link.part.Parent and link.base.Parent then
          link.part.Size = link.base.Size
          link.part.CFrame = link.base.CFrame
          link.part.AssemblyLinearVelocity = copyRoot.AssemblyLinearVelocity
          link.part.AssemblyAngularVelocity = Vector3.zero
        end
      end
    end
    listen("source_added", character.DescendantAdded, function(object) sourceObject(session, object) end)
    listen("source_removed", character.DescendantRemoving, function(object)
      if object == humanoid or object == root then stopReanimation(); return end
      for _, link in ipairs(session.links) do if object == link.part then stopReanimation(); return end end
    end)
    listen("died", humanoid.Died, stopReanimation)
    listen("clone_died", copyHumanoid.Died, stopReanimation)
    listen("character_removing", player.CharacterRemoving, function(model) if model == character then stopReanimation() end end)
    listen("character_added", player.CharacterAdded, function(model) if model ~= character then stopReanimation() end end)
    listen("camera", state.services.workspace:GetPropertyChangedSignal("CurrentCamera"), function() setSessionCamera(session) end)
    listen("focus", state.services.user_input_service.WindowFocused, function() session.focused = true end)
    listen("blur", state.services.user_input_service.WindowFocusReleased, function() session.focused = false; copyHumanoid:Move(Vector3.zero) end)
    listen("jump", state.services.user_input_service.JumpRequest, function()
      if session.focused and not state.services.user_input_service:GetFocusedTextBox() then copyHumanoid.Jump = true end
    end)
    listen("step", state.services.run_service.PreSimulation, function()
      if not validRig() or humanoid.Health <= 0 or copyHumanoid.Health <= 0 then stopReanimation(); return end
      humanoid.RequiresNeck, humanoid.BreakJointsOnDeath, humanoid.PlatformStand = false, false, true
      for joint in pairs(session.jointCandidates) do
        if joint:IsDescendantOf(character) then
          if bodyJoint(joint, character) then sourceObject(session, joint) end
        else
          local saved = session.saved[joint]
          if saved and saved.Enabled and joint.Parent then joint.Enabled = saved.Enabled.value end
          session.jointCandidates[joint] = nil
        end
      end
      for part in pairs(session.parts) do if part:IsDescendantOf(character) then part.CanCollide = false end end
      syncMovement(session)
      local move, relative = Vector3.zero, false
      if session.focused and not state.services.user_input_service:GetFocusedTextBox() then
        if session.controls then
          local got, value = pcall(function() return session.controls:GetMoveVector() end)
          if got and typeof(value) == "Vector3" then move, relative = value, true else session.controls = nil end
        end
        if not session.controls then move = humanoid.MoveDirection or Vector3.zero end
      end
      if move.Magnitude ~= move.Magnitude or move.Magnitude == math.huge then move = Vector3.zero end
      if move.Magnitude > 1 then move = move.Unit end
      copyHumanoid:Move(move, relative)
      driveFollowers()
    end)
    if state.services.run_service.PostSimulation then
      listen("post_step", state.services.run_service.PostSimulation, function()
        if not validRig() then stopReanimation(); return end
        driveFollowers()
      end)
    end
    setSessionCamera(session)
  end)
  if not current() then return "Start cancelled." end
  state.rig.starting = false
  if not ok then stopReanimation(); return tostring(message) end
end

return {
 Start=startReanimation, Stop=stopReanimation,
 Get=function() local s=state.rig.session; return state.flags.reanimated and s and s.copy end,
 OnStopped=function(callback) state.callbacks.on_deactivate=callback end,
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
    speed = 1, loop = true, stopOnMove = true, walkSync = true, blend = 0.15, recordRate = 20,
    keyToggle = "RightControl", keyGui = "RightShift", keyStop = "X",
}
local data = {favorites = {}, custom = {}, states = {}, settings = settings}

do -- load
    if hasFS then
        local ok, raw = pcall(function() if isfile(DATA_FILE) then return readfile(DATA_FILE) end end)
        if ok and raw then
            local ok2, decoded = pcall(function() return HttpService:JSONDecode(raw) end)
            if ok2 and type(decoded) == "table" then
                for _, k in ipairs({"favorites", "custom", "states"}) do
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
-- Library data
----------------------------------------------------------------------
local STATES = {"idle", "walk", "run", "jump", "fall", "climb", "swim"}
local function cap(s) return s:sub(1, 1):upper() .. s:sub(2) end
local function S(a, b, c, d, e, f, g)
    return {idle = a, walk = b, run = c, jump = d, fall = e, climb = f, swim = g}
end

-- IDs are Roblox's public animation assets. R15 packs come from memory of the standard
-- animation packs: if one fails to load, the status line says so and the default is used.
local PACKS = {
    {name = "Default", r15 = S(507766666, 507777826, 507767714, 507765000, 507767968, 507765644, 507784897),
     r6 = S(180435571, 180426354, 180426354, 125750702, 180436148, 180436334, nil)},
    {name = "Ninja", r15 = S(656117400, 656121766, 656118852, 656117878, 656115606, 656114359, 656119721)},
    {name = "Robot", r15 = S(616088211, 616095330, 616091570, 616090535, 616087089, 616086039, 616092998)},
    {name = "Zombie", r15 = S(616158929, 616168032, 616163682, 616161997, 616157476, 616156119, 616165109)},
    {name = "Levitation", r15 = S(616006778, 616013216, 616010382, 616008936, 616005863, 616003713, 616011509)},
    {name = "Cartoony", r15 = S(742637544, 742640026, 742638842, 742637942, 742637151, 742636889, 742639220)},
    {name = "Mage", r15 = S(707742142, 707897309, 707861613, 707853694, 707829716, 707826056, 707876443)},
    {name = "Stylish", r15 = S(616136790, 616146177, 616140816, 616139451, 616134815, 616133594, 616143378)},
    {name = "Superhero", r15 = S(616111295, 616122287, 616117076, 616115533, 616108001, 616104706, 616119360)},
    {name = "Toy", r15 = S(782841498, 782843345, 782842708, 782847020, 782846423, 782843869, 782844582)},
    {name = "Vampire", r15 = S(1083445855, 1083473930, 1083462077, 1083455352, 1083443587, 1083439238, 1083464683)},
    {name = "Werewolf", r15 = S(1083195517, 1083178339, 1083216690, 1083218792, 1083189019, 1083182000, 1083222527)},
}

local DEFAULTS = {}
for _, s in ipairs(STATES) do
    DEFAULTS[s] = {name = "Default " .. cap(s), r15 = PACKS[1].r15[s], r6 = PACKS[1].r6[s]}
end

local LIB = {}
local function add(cat, sub, name, r15, r6)
    LIB[#LIB + 1] = {key = "b:" .. cat .. "/" .. sub .. "/" .. name, name = name, cat = cat, sub = sub, r15 = r15, r6 = r6}
end
add("Emotes", "Greetings", "Wave", 507770239, 128777973)
add("Emotes", "Greetings", "Hello", 3576686446)
add("Emotes", "Greetings", "Salute", 3333474484)
add("Emotes", "Reactions", "Cheer", 507770677, 129423030)
add("Emotes", "Reactions", "Laugh", 507770818, 129423131)
add("Emotes", "Reactions", "Applaud", 5915779043)
add("Emotes", "Reactions", "Shrug", 3576968026)
add("Emotes", "Poses", "Point", 507770453, 128853357)
add("Emotes", "Poses", "Stadium", 3360686498)
add("Emotes", "Poses", "Tilt", 3360692915)
add("Dances", "Classic", "Dance", 507771019, 182435998)
add("Dances", "Classic", "Dance 2", 507776043, 182436842)
add("Dances", "Classic", "Dance 3", 507777268, 182436935)
for _, pack in ipairs(PACKS) do
    for _, s in ipairs(STATES) do
        add("Movement", pack.name, pack.name .. " " .. cap(s), pack.r15[s], pack.r6 and pack.r6[s] or nil)
    end
end

local recorded = {} -- recorded entries {key,name,cat,sub,recorded=true,clip=,path=}

local function customToEntry(c)
    local e = {key = "c:" .. c.cat .. "/" .. c.sub .. "/" .. c.name .. "/" .. tostring(c.id),
        name = c.name, cat = c.cat, sub = c.sub, custom = true, src = c}
    if c.rig == "R15" then e.r15 = c.id elseif c.rig == "R6" then e.r6 = c.id else e.any = c.id end
    return e
end
local function getEntries()
    local out = {}
    for _, e in ipairs(LIB) do out[#out + 1] = e end
    for _, c in ipairs(data.custom) do out[#out + 1] = customToEntry(c) end
    for _, e in ipairs(recorded) do out[#out + 1] = e end
    return out
end
local function entryId(e, rig)
    if not e then return nil end
    if rig == "R6" then return e.r6 or e.any end
    return e.r15 or e.any
end
local function playerRig()
    local ch = player.Character
    local h = ch and ch:FindFirstChildOfClass("Humanoid")
    return (h and h.RigType == Enum.HumanoidRigType.R6) and "R6" or "R15"
end

----------------------------------------------------------------------
-- Keyframe decoding / sampling / loading
----------------------------------------------------------------------
local function decode(sequence)
    local frames = sequence:GetKeyframes()
    table.sort(frames, function(a, b) return a.Time < b.Time end)
    local curves, duration = {}, 0
    for _, frame in ipairs(frames) do
        duration = math.max(duration, frame.Time)
        for _, pose in ipairs(frame:GetDescendants()) do
            if pose:IsA("Pose") then
                local curve = curves[pose.Name]
                if not curve then curve = {}; curves[pose.Name] = curve end
                local key = {time = frame.Time, value = CFrame.identity:Lerp(pose.CFrame, math.clamp(pose.Weight, 0, 1)),
                    style = pose.EasingStyle.Name, direction = pose.EasingDirection.Name}
                if #curve > 0 and curve[#curve].time == key.time then curve[#curve] = key
                else curve[#curve + 1] = key end
            end
        end
    end
    return curves, duration
end

local styles = {Linear = Enum.EasingStyle.Linear, Cubic = Enum.EasingStyle.Cubic,
    CubicV2 = Enum.EasingStyle.Cubic, Elastic = Enum.EasingStyle.Elastic, Bounce = Enum.EasingStyle.Bounce}
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

local function rigOf(curves)
    if curves.UpperTorso or curves.LowerTorso then return "R15" end
    if curves.Torso then return "R6" end
    return nil
end

local cache, pending = {}, {}
-- Yields. Returns anim or (nil, errorMessage).
local function loadAnim(id)
    id = tostring(id)
    if cache[id] then return cache[id] end
    if pending[id] then
        while pending[id] do task.wait() end
        if cache[id] then return cache[id] end
        return nil, "Can't load keyframes"
    end
    pending[id] = true
    local result = {}
    task.spawn(function()
        local ok, seq = pcall(function() return Provider:GetKeyframeSequenceAsync("rbxassetid://" .. id) end)
        result.ok, result.seq, result.done = ok, seq, true
        if result.abandoned and ok and typeof(seq) == "Instance" then seq:Destroy() end
    end)
    local deadline = os.clock() + 15
    while not result.done and os.clock() < deadline do task.wait() end
    if not result.done then
        result.abandoned = true
        pending[id] = nil
        return nil, "Keyframes timed out"
    end
    local anim, err
    if result.ok and typeof(result.seq) == "Instance" then
        local parsed, curves, duration = pcall(decode, result.seq)
        local looped = true
        pcall(function() looped = result.seq.Loop end)
        result.seq:Destroy()
        if parsed and duration > 0 then
            anim = {curves = curves, duration = duration, looped = looped, rig = rigOf(curves)}
        else err = "No keyframes in animation" end
    else err = "Can't load keyframes" end
    cache[id] = anim
    pending[id] = nil
    return anim, err
end

----------------------------------------------------------------------
-- GUI skeleton (needed by engine for status text)
----------------------------------------------------------------------
local C = {
    bg = Color3.fromRGB(17, 17, 24), field = Color3.fromRGB(30, 30, 41), sel = Color3.fromRGB(56, 50, 98),
    text = Color3.fromRGB(236, 236, 244), dim = Color3.fromRGB(143, 143, 164),
    accent = Color3.fromRGB(124, 92, 255), off = Color3.fromRGB(46, 46, 62), list = Color3.fromRGB(22, 22, 31),
    stroke = Color3.fromRGB(58, 56, 88),
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
        o.Font = Enum.Font.GothamMedium; o.TextSize = 13; o.TextColor3 = C.text
        if class == "TextLabel" then o.BackgroundTransparency = 1 else o.BackgroundColor3 = C.field end
        if class == "TextButton" then o.AutoButtonColor = false end
        if class == "TextBox" then o.ClearTextOnFocus = false; o.PlaceholderColor3 = Color3.fromRGB(135, 135, 135) end
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
    corner(b, 7)
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
    corner(b, 6)
    T("UIPadding", {PaddingLeft = UDim.new(0, 10)}, b)
    return b
end
local function switch(parent, pos, initial, onChange)
    local b = T("TextButton", {Position = pos, Size = UDim2.fromOffset(46, 24), Text = "", BackgroundColor3 = C.off}, parent)
    corner(b, 12)
    local knob = T("Frame", {Size = UDim2.fromOffset(18, 18), Position = UDim2.fromOffset(3, 3), BackgroundColor3 = C.text}, b)
    corner(knob, 9)
    local api = {value = initial}
    function api.set(v)
        api.value = v
        tween(b, {BackgroundColor3 = v and C.accent or C.off})
        TweenService:Create(knob, TweenInfo.new(.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Position = UDim2.fromOffset(v and 25 or 3, 3)}):Play()
    end
    b.Activated:Connect(function()
        api.set(not api.value)
        if onChange then onChange(api.value) end
    end)
    api.set(initial)
    return api
end
local function slider(parent, x, y, w, min, max, value, onChange)
    local bar = T("Frame", {Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, 14), BackgroundColor3 = C.field}, parent)
    corner(bar, 7)
    local fill = T("Frame", {Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.accent}, bar)
    corner(fill, 7)
    local api, dragging = {}, false
    function api.set(v, fire)
        v = math.clamp(v, min, max)
        fill.Size = UDim2.fromScale((v - min) / (max - min), 1)
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
local panel = T("Frame", {Size = UDim2.fromOffset(380, 470), Position = UDim2.new(0.5, -190, 0.5, -235),
    BackgroundColor3 = C.bg, Active = true}, gui)
corner(panel, 14)
do
    local stroke = Instance.new("UIStroke")
    stroke.Color, stroke.Thickness, stroke.Transparency, stroke.ApplyStrokeMode = C.stroke, 1.5, .2, Enum.ApplyStrokeMode.Border
    stroke.Parent = panel
    local grad = Instance.new("UIGradient")
    grad.Rotation = 90
    grad.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(196, 196, 214))
    grad.Parent = panel
end
local panelScale = Instance.new("UIScale")
panelScale.Scale = .9
panelScale.Parent = panel
panel.BackgroundTransparency = 1
tween(panelScale, {Scale = 1}, TweenInfo.new(.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
tween(panel, {BackgroundTransparency = 0}, TweenInfo.new(.3))
local dragBar = T("Frame", {Size = UDim2.new(1, 0, 0, 38), BackgroundTransparency = 1}, panel)
local title = label(dragBar, "reanimlol", 16, 0, 190, 38, {Font = Enum.Font.GothamMedium, TextSize = 16,
    TextTruncate = Enum.TextTruncate.AtEnd})
local rigLabel = label(dragBar, "", 212, 0, 40, 38, {TextColor3 = C.dim, TextSize = 12})
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
local mainSwitch = switch(panel, UDim2.fromOffset(262, 7), false, function(v)
    if v then turnOn() else turnOff() end
end)
local closeBtn = button(panel, "✕", 336, 7, 28, 24, function() if shared.ReanimlolCleanup then shared.ReanimlolCleanup() end end)

----------------------------------------------------------------------
-- Engine: state animations, emotes, blending, recording
----------------------------------------------------------------------
local engine = {motors = {}, stateAnims = {}, gen = {}, token = 0, fadeT = 1, snapshot = {}}
local rec = {on = false, clip = nil, t = 0, acc = 0, frames = 0}
local updateRecUI

local function stateEntry(s) return data.states[s] or DEFAULTS[s] end

local function usable(anim)
    if not anim then return false end
    if anim.rig and anim.rig ~= engine.rig then return false end
    for n in pairs(engine.motors) do if anim.curves[n] then return true end end
    return false
end

local function resolveAnim(entry)
    if not entry then return nil end
    if entry.rec then
        for _, r in ipairs(recorded) do if r.name == entry.rec then return r.clip end end
        return nil
    end
    local id = entryId(entry, engine.rig)
    if not id then return nil end
    return (loadAnim(id))
end

local function refreshState(s)
    if not engine.copy then return end
    engine.gen[s] = (engine.gen[s] or 0) + 1
    local gen, copy = engine.gen[s], engine.copy
    task.spawn(function()
        local anim = resolveAnim(stateEntry(s))
        if not usable(anim) then
            if data.states[s] and not destroyed then setStatus(cap(s) .. " anim failed, using default") end
            anim = resolveAnim(DEFAULTS[s])
            if not usable(anim) then anim = nil end
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
        desired = engine.stateAnims[stateName] or engine.stateAnims.idle
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
        cur.t += dt * settings.speed * rate
        local t = cur.t
        if loop then
            t = t % dur
        elseif t >= dur then
            t = dur
            if e then engine.emote = nil end
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
    for _, m in ipairs(copy:GetDescendants()) do
        if m:IsA("Motor6D") and m.Part1 then engine.motors[m.Part1.Name] = m end
    end
    engine.current, engine.emote, engine.stateAnims, engine.gen, engine.snapshot, engine.fadeT = nil, nil, {}, {}, {}, 1
    rigLabel.Text = engine.rig
    for _, s in ipairs(STATES) do refreshState(s) end
    engine.conn = RunService.PreSimulation:Connect(engineStep)
end

local function engineStop()
    if engine.conn then engine.conn:Disconnect(); engine.conn = nil end
    engine.copy, engine.hum, engine.root, engine.current, engine.emote = nil, nil, nil, nil, nil
    engine.motors, engine.stateAnims = {}, {}
    engine.token += 1
    rec.on = false
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

local function startEmote(anim, name)
    if anim.rig and anim.rig ~= engine.rig then
        setStatus(anim.rig .. " animation on " .. engine.rig .. " rig"); return false
    end
    local matched = 0
    for n in pairs(engine.motors) do if anim.curves[n] then matched += 1 end end
    if matched == 0 then setStatus("Animation doesn't match rig"); return false end
    engine.emote = {anim = anim, loop = settings.loop, age = 0, name = name}
    setStatus(name)
    return true
end

playEntry = function(entry)
    turnOn(function()
        if entry.clip then startEmote(entry.clip, entry.name); return end
        local id = entryId(entry, engine.rig)
        if not id then setStatus("No " .. tostring(engine.rig) .. " version"); return end
        engine.token += 1
        local token = engine.token
        setStatus("Loading...", true)
        task.spawn(function()
            local anim, err = loadAnim(id)
            if destroyed or token ~= engine.token or not engine.copy then return end
            if not anim then setStatus(err or "Can't load keyframes"); return end
            startEmote(anim, entry.name)
        end)
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
local function deserializeClip(tbl)
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

local function exportSequence(clip, name)
    if not engine.copy then return nil end
    local seq = Instance.new("KeyframeSequence")
    seq.Name, seq.Loop = name, true
    local times, seen = {}, {}
    for _, curve in pairs(clip.curves) do
        for _, k in ipairs(curve) do
            local key = string.format("%.4f", k.time)
            if not seen[key] then seen[key] = true; times[#times + 1] = k.time end
        end
    end
    table.sort(times)
    local motors = {}
    for _, m in ipairs(engine.copy:GetDescendants()) do
        if m:IsA("Motor6D") and m.Part0 and m.Part1 and clip.curves[m.Part1.Name] then motors[#motors + 1] = m end
    end
    for _, time in ipairs(times) do
        local kf = Instance.new("Keyframe")
        kf.Time = time
        local poses = {}
        local rootPose = Instance.new("Pose")
        rootPose.Name, rootPose.Weight, rootPose.Parent = "HumanoidRootPart", 0, kf
        poses.HumanoidRootPart = rootPose
        local remaining = {}
        for i, m in ipairs(motors) do remaining[i] = m end
        local progress = true
        while #remaining > 0 and progress do
            progress = false
            for i = #remaining, 1, -1 do
                local m = remaining[i]
                local parentPose = poses[m.Part0.Name]
                if parentPose then
                    local p = Instance.new("Pose")
                    p.Name = m.Part1.Name
                    p.CFrame = sample(clip.curves[m.Part1.Name], time, clip.duration, false)
                    p.Weight = 1
                    p.Parent = parentPose
                    poses[m.Part1.Name] = p
                    table.remove(remaining, i)
                    progress = true
                end
            end
        end
        kf.Parent = seq
    end
    seq.Parent = ReplicatedStorage
    return seq
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

----------------------------------------------------------------------
-- GUI: tabs
----------------------------------------------------------------------
local tabNames = {"Emotes", "States", "Add", "Record", "Settings"}
local tabFrames, tabButtons, tabOrder = {}, {}, {}
local TAB_X, TAB_Y = 12, 74
T("Frame", {Position = UDim2.fromOffset(12, 71), Size = UDim2.new(1, -24, 0, 1), BackgroundColor3 = C.stroke, BackgroundTransparency = .4}, panel)
local indicator = T("Frame", {Position = UDim2.fromOffset(12, 68), Size = UDim2.fromOffset(68, 3), BackgroundColor3 = C.accent}, panel)
corner(indicator, 2)
local currentTab, tabToken = "Emotes", 0
local function showTab(name)
    local first = (tabFrames[name].Visible == false and name == currentTab)
    tabToken += 1
    local token = tabToken
    local dir = (tabOrder[name] >= tabOrder[currentTab]) and 1 or -1
    local old = currentTab
    currentTab = name
    for n, b in pairs(tabButtons) do
        setBase(b, n == name and C.sel or C.field)
        tween(b, {TextColor3 = n == name and C.text or C.dim})
    end
    tween(indicator, {Position = UDim2.fromOffset(12 + (tabOrder[name] - 1) * 72, 68)}, TweenInfo.new(.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out))
    for n, f in pairs(tabFrames) do
        if n == name then
            f.Visible = true
            if old ~= name or first then
                f.Position = UDim2.fromOffset(TAB_X + 22 * dir, TAB_Y)
                f.GroupTransparency = 1
                tween(f, {Position = UDim2.fromOffset(TAB_X, TAB_Y), GroupTransparency = 0}, TweenInfo.new(.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out))
            end
        elseif f.Visible then
            tween(f, {Position = UDim2.fromOffset(TAB_X - 22 * dir, TAB_Y), GroupTransparency = 1}, TweenInfo.new(.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In))
            task.delay(.15, function()
                if token == tabToken and not destroyed then f.Visible = false end
            end)
        end
    end
end
for i, name in ipairs(tabNames) do
    tabOrder[name] = i
    tabFrames[name] = T("CanvasGroup", {Position = UDim2.fromOffset(TAB_X, TAB_Y), Size = UDim2.fromOffset(356, 318),
        BackgroundTransparency = 1, Visible = (i == 1)}, panel)
    tabButtons[name] = button(panel, name, 12 + (i - 1) * 72, 40, 68, 26, function() showTab(name) end)
    tabButtons[name].TextColor3 = (i == 1) and C.text or C.dim
    if i == 1 then setBase(tabButtons[name], C.sel) end
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
        TextSize = 12, LayoutOrder = order, BackgroundColor3 = C.field, TextColor3 = active and C.text or C.dim}, row)
    T("UIPadding", {PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10)}, b)
    corner(b, 12)
    hoverable(b)
    if active then
        -- selected chip fades from the idle colour to the accent colour
        task.defer(function() if b.Parent then setBase(b, C.accent); tween(b, {TextColor3 = C.text}) end end)
    end
    b.Activated:Connect(cb)
    return b
end

-- Emotes tab ---------------------------------------------------------
local tabE = tabFrames.Emotes
local search = box(tabE, "Search emotes", 0, 0, 356, 28)
local mainRow = chipRow(tabE, 32)
local subRow = chipRow(tabE, 60)
local list = T("ScrollingFrame", {Position = UDim2.fromOffset(0, 90), Size = UDim2.fromOffset(356, 176),
    BackgroundColor3 = C.list, ScrollBarThickness = 4, CanvasSize = UDim2.new(),
    AutomaticCanvasSize = Enum.AutomaticSize.Y}, tabE)
corner(list, 10)
T("UIListLayout", {Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder}, list)
T("UIPadding", {PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4)}, list)
label(tabE, "Set selected as state animation:", 2, 268, 300, 14, {TextSize = 10, TextColor3 = C.dim})

local function inMain(e)
    if ui.main == "All" then return true end
    if ui.main == "★ Favorites" then return data.favorites[e.key] == true end
    return e.cat == ui.main
end

refreshChips = function()
    clearButtons(mainRow); clearButtons(subRow)
    local mains, seen = {"All", "★ Favorites", "Emotes", "Dances", "Movement", "Custom", "Recorded"}, {}
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
        TweenService:Create(row, info, {BackgroundTransparency = 0}):Play()
        for d, tr in pairs(texts) do TweenService:Create(d, info, {TextTransparency = tr}):Play() end
    end)
end

rebuildList = function(animate)
    if animate then list.CanvasPosition = Vector2.zero end
    for _, c in ipairs(list:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end
    ui.rows = {}
    local q = search.Text:lower()
    local order = 0
    for _, e in ipairs(getEntries()) do
        local show = inMain(e)
        if show and ui.sub ~= "All" then show = (e.sub == ui.sub) end
        if show and q ~= "" then show = e.name:lower():find(q, 1, true) ~= nil end
        if show then
            order += 1
            local row = T("TextButton", {Size = UDim2.new(1, -6, 0, 30), Text = "", LayoutOrder = order,
                BackgroundColor3 = (ui.selected and ui.selected.key == e.key) and C.sel or C.field}, list)
            corner(row, 8)
            local hasX = e.custom or e.recorded
            label(row, e.name, 10, 0, 260 - (hasX and 28 or 0), 30, {TextTruncate = Enum.TextTruncate.AtEnd})
            label(row, e.sub, 150, 0, 90, 30, {TextSize = 10, TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Right})
            local star = T("TextButton", {Position = UDim2.new(1, -30, 0, 3), Size = UDim2.fromOffset(24, 24),
                BackgroundTransparency = 1, TextSize = 18,
                Text = data.favorites[e.key] and "★" or "☆"}, row)
            star.Activated:Connect(function()
                if data.favorites[e.key] then data.favorites[e.key] = nil else data.favorites[e.key] = true end
                saveData()
                if ui.main == "★ Favorites" then refreshChips(); rebuildList()
                else star.Text = data.favorites[e.key] and "★" or "☆" end
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
                    if ui.selected and ui.selected.key == e.key then ui.selected = nil end
                    refreshChips(); rebuildList()
                end)
            end
            ui.rows[e.key] = row
            hoverable(row)
            if animate and order <= 12 then popIn(row, (order - 1) * 0.03) end
            row.Activated:Connect(function()
                if ui.selected and ui.rows[ui.selected.key] then setBase(ui.rows[ui.selected.key], C.field) end
                ui.selected = e
                setBase(row, C.sel)
                playEntry(e)
            end)
        end
    end
end
connect(search:GetPropertyChangedSignal("Text"), function() rebuildList() end)

local function assignState(s, e)
    if e.recorded then data.states[s] = {name = e.name, rec = e.name}
    else data.states[s] = {name = e.name, r15 = e.r15, r6 = e.r6, any = e.any} end
    saveData()
    refreshStateRows()
    refreshState(s)
    setStatus(cap(s) .. " = " .. e.name)
end
for i, s in ipairs(STATES) do
    button(tabE, cap(s), (i - 1) * 51, 284, 48, 28, function()
        if not ui.selected then setStatus("Select an entry first"); return end
        assignState(s, ui.selected)
    end)
end

-- States tab ---------------------------------------------------------
local tabS = tabFrames.States
local packRow = chipRow(tabS, 0)
local stateBoxes = {}
local function applyPack(pack)
    local rig = engine.rig or playerRig()
    local ids = (rig == "R6") and pack.r6 or pack.r15
    if not ids then setStatus(pack.name .. " is R15 only"); return end
    for _, s in ipairs(STATES) do
        if pack.name == "Default" then data.states[s] = nil
        else data.states[s] = {name = pack.name .. " " .. cap(s), r15 = pack.r15[s], r6 = pack.r6 and pack.r6[s] or nil} end
    end
    saveData(); refreshStateRows()
    for _, s in ipairs(STATES) do refreshState(s) end
    setStatus(pack.name .. " pack")
end
for i, pack in ipairs(PACKS) do chip(packRow, pack.name, false, i, function() applyPack(pack) end) end
for i, s in ipairs(STATES) do
    local y = 32 + (i - 1) * 36
    label(tabS, cap(s), 4, y, 56, 30)
    local tb = box(tabS, "Animation ID", 60, y, 226, 30)
    stateBoxes[s] = tb
    button(tabS, "Reset", 292, y, 64, 30, function()
        data.states[s] = nil; saveData(); refreshStateRows(); refreshState(s)
    end)
    tb.FocusLost:Connect(function()
        local text = tb.Text:match("^%s*(.-)%s*$")
        if text == stateEntry(s).name then return end
        local id = text:match("%d+")
        if id and id:find("[1-9]") then
            data.states[s] = {name = "ID " .. id, any = tonumber(id)}
            saveData(); refreshState(s); setStatus(cap(s) .. " = " .. id)
        end
        refreshStateRows()
    end)
end
label(tabS, "Pick a pack, type an ID, or select a library entry and\nuse the buttons on the Emotes tab.", 4, 288, 350, 28,
    {TextSize = 10, TextColor3 = C.dim, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top})
refreshStateRows = function()
    for _, s in ipairs(STATES) do stateBoxes[s].Text = stateEntry(s).name end
end

-- Add tab ------------------------------------------------------------
local tabA = tabFrames.Add
local nameBox = box(tabA, "Name", 0, 0, 356, 30)
local idBox = box(tabA, "Animation / KeyframeSequence ID", 0, 36, 356, 30)
local catBox = box(tabA, "Category", 0, 72, 172, 30)
local subBox = box(tabA, "Sub-category", 184, 72, 172, 30)
catBox.Text, subBox.Text = "Custom", "General"
local rigChoices, rigIndex = {"Both", "R15", "R6"}, 1
local rigBtn
rigBtn = button(tabA, "Rig: Both", 0, 108, 172, 30, function()
    rigIndex = rigIndex % #rigChoices + 1
    rigBtn.Text = "Rig: " .. rigChoices[rigIndex]
end)
button(tabA, "Add to library", 184, 108, 172, 30, function()
    local id = idBox.Text:match("%d+")
    if not id or not id:find("[1-9]") then setStatus("Enter an animation ID"); return end
    local function trim(s, d) s = s:match("^%s*(.-)%s*$"); return s ~= "" and s or d end
    local entry = {name = trim(nameBox.Text, "Custom " .. id), id = tonumber(id),
        cat = trim(catBox.Text, "Custom"), sub = trim(subBox.Text, "General"), rig = rigChoices[rigIndex]}
    table.insert(data.custom, entry)
    saveData()
    nameBox.Text, idBox.Text = "", ""
    ui.main, ui.sub = entry.cat, "All"
    refreshChips(); rebuildList()
    setStatus("Added " .. entry.name)
    showTab("Emotes")
end)
label(tabA, "Paste any public KeyframeSequence / animation asset ID. Pick the rig it was made for (R6 and R15 animations are not interchangeable). Use \"Category\" and \"Sub-category\" to organise your own folders; they show up as chips on the Emotes tab.",
    2, 150, 352, 90, {TextSize = 11, TextColor3 = C.dim, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top})

-- Record tab ---------------------------------------------------------
local tabR = tabFrames.Record
local recInfo = label(tabR, "0.0s • 0 keyframes", 2, 0, 350, 24, {TextColor3 = C.dim})
local recBtn
updateRecUI = function()
    recBtn.Text = rec.on and "■ Stop" or "● Record"
    recBtn.TextColor3 = rec.on and Color3.fromRGB(255, 110, 110) or C.text
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
    local exported = pcall(exportSequence, clip, name)
    rec.clip, rec.frames = nil, 0
    recName.Text = ""
    updateRecUI(); refreshChips(); rebuildList()
    setStatus("Saved " .. name .. (exported and "" or " (no instance)"))
end)
label(tabR, "Rate", 2, 104, 40, 14, {TextColor3 = C.dim, TextSize = 12})
local rateVal = label(tabR, settings.recordRate .. " Hz", 300, 104, 56, 14, {TextColor3 = C.dim, TextSize = 12})
slider(tabR, 46, 104, 246, 5, 30, settings.recordRate, function(v)
    settings.recordRate = math.floor(v + 0.5)
    rateVal.Text = settings.recordRate .. " Hz"
    saveSoon()
end)
label(tabR, "● Record captures whatever the rig is doing (emote, state animation, speed and blend included) as keyframes. \"Snap pose\" adds a single keyframe 0.3s after the last one. Save adds it to Library > Recorded, writes Reanimlol/recordings/<name>.json, and creates a KeyframeSequence in ReplicatedStorage while reanim is on.",
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
bindRow("Toggle reanim key", "keyToggle", 102)
bindRow("Hide / show GUI key", "keyGui", 136)
bindRow("Stop emote key", "keyStop", 170)
button(tabG, "Reset saved data", 0, 214, 356, 30, function()
    data.favorites, data.custom, data.states = {}, {}, {}
    saveData()
    ui.main, ui.sub, ui.selected = "All", "All", nil
    refreshChips(); rebuildList(); refreshStateRows()
    for _, s in ipairs(STATES) do refreshState(s) end
    setStatus("Data reset")
end)
label(tabG, "Esc cancels a rebind. Hotkeys are ignored while typing in a text box.", 4, 252, 350, 30,
    {TextSize = 10, TextColor3 = C.dim, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top})

-- Footer (speed / stop / loop) ----------------------------------------
label(panel, "Speed", 14, 398, 46, 22, {TextColor3 = C.dim, TextSize = 12})
local speedVal = label(panel, string.format("%.2fx", settings.speed), 318, 398, 52, 22, {TextColor3 = C.dim, TextSize = 12})
slider(panel, 62, 402, 250, 0.1, 3, settings.speed, function(v)
    settings.speed = math.floor(v * 20 + 0.5) / 20
    speedVal.Text = string.format("%.2fx", settings.speed)
    saveSoon()
end)
button(panel, "■ Stop emote", 12, 430, 110, 28, function() stopEmote() end)
label(panel, "Loop", 138, 430, 36, 28, {TextColor3 = C.dim, TextSize = 12})
switch(panel, UDim2.fromOffset(176, 432), settings.loop, function(v)
    settings.loop = v
    if engine.emote then engine.emote.loop = v end
    saveSoon()
end)

----------------------------------------------------------------------
-- Hotkeys + lifecycle
----------------------------------------------------------------------
connect(UserInputService.InputBegan, function(input, processed)
    if destroyed then return end
    if ui.binding then
        if input.UserInputType == Enum.UserInputType.Keyboard then
            if input.KeyCode ~= Enum.KeyCode.Escape then settings[ui.binding] = input.KeyCode.Name; saveSoon() end
            ui.bindBtn[ui.binding].Text = settings[ui.binding]
            ui.binding = nil
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
    end
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
connect(player.CharacterRemoving, function()
    if bodyReanim.Get() then turnOff() end
end)

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
