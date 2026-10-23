-- reanimlol v5: keyframe-only (Motor6Ds are unparented so other players see the animation)
-- Body reanimation driven purely by keyframes. No Roblox animation assets, IDs or AnimationTracks are
-- used: every clip is a list of timed poses (built in, recorded, or imported as JSON) that the engine
-- samples itself and writes to the rig's Motor6D.Transform values. Works on R6 and R15.
-- Enable the toggle (or press the hotkey) first. Saved data (favorites, imported clips, state picks,
-- settings, recordings) is written to the "Reanimlol" folder when your executor supports writefile.
--
-- Replication fixes in this build (so other players can see the animation):
--   * simulation radius is raised on start and every physics step (needs sethiddenproperty or setsimulationradius)
--   * the real HumanoidRootPart keeps normal density/mass (only the limbs are made massless), so the
--     assembly doesn't end up with ~zero mass
--   * network ownership of the real character's parts is checked every few seconds (isnetworkowner);
--     a warning in the console lists any parts you don't own
--
-- Import fixes from the previous build:
--   * keyframe files are detected by CONTENT (Lua tables with Time / CFrame.new vs JSON), not by extension
--   * .txt files are supported (a Lua export or JSON pose file saved as .txt loads fine)
--   * drop files in Reanimlol/keyframes/ (subfolders become sub-categories) and press "Reload folder"
--     on the Import tab to pick up new / edited / deleted files without rejoining
--   * "Load file" also tries .lua / .json / .txt when you type a name without an extension
--   * the invalid-data message now tells you how much text arrived (pasting very large files fails
--     because a text box can't hold them: use Load file instead)

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
local state = {
 services={players=game:GetService("Players"),workspace=game:GetService("Workspace"),
 run_service=game:GetService("RunService"),user_input_service=game:GetService("UserInputService")},
 flags={reanimated=false},rig={revision=0,starting=false},clones={},real_chars={},connections={},callbacks={},
 animation={joints={},original_motor_c0s={}},
}
local api={set_arm_poles=function() end,stop_animation=function() end}

-- Raises the simulation radius so the server keeps giving this client physics ownership of the real
-- body parts. Without it, parts drift out of range and other players see them frozen or stuck.
local function boostSimulation(lp)
  pcall(function()
    if type(sethiddenproperty) == "function" then
      sethiddenproperty(lp, "SimulationRadius", 1e9)
      sethiddenproperty(lp, "MaximumSimulationRadius", 1e9)
    elseif type(setsimulationradius) == "function" then
      setsimulationradius(1e9, 1e9)
    end
  end)
end

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
      -- Disabling is client-only; actually unparenting the Motor6D is what the server sees as a broken weld.
      if object:IsA("Motor6D") and not session.removedJoints[object] then
        session.removedJoints[object] = object.Parent
        object.Parent = nil
      end
    end
  elseif object:IsA("BasePart") then
    for _, property in ipairs({"CanCollide", "Massless", "CustomPhysicalProperties", "Transparency", "Size"}) do
      remember(session, object, property)
    end
    session.parts[object] = true
    object.CanCollide, object.Transparency = false, 1
    -- Limbs are made weightless, but the root keeps normal mass/density so the real assembly doesn't
    -- end up with almost no mass (the server may throttle or reject such an assembly).
    if object ~= session.root then
      object.Massless = true
      object.CustomPhysicalProperties = PhysicalProperties.new(0.001, 0, 0, 0, 0)
    end
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
    -- Put removed Motor6Ds back (disabled until their saved values are restored below).
    for joint, parent in pairs(session.removedJoints) do
      release(function()
        joint.Enabled = false
        joint.Parent = parent
      end)
    end
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
      saved = {}, owned = {}, links = {}, parts = {}, jointCandidates = {}, cameras = {}, removedJoints = {},
      controls = controls, focused = true, lastOwnerCheck = 0,
    }
    state.rig.session = session
    state.real_chars[player] = character
    boostSimulation(player)
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
    -- Every few seconds, warn about real body parts this client doesn't have network ownership of.
    -- Parts you don't own are not replicated, so other players can't see them move.
    local function checkOwnership()
      if type(isnetworkowner) ~= "function" then return end
      local now = os.clock()
      if now - session.lastOwnerCheck < 3 then return end
      session.lastOwnerCheck = now
      local missing = {}
      for _, link in ipairs(session.links) do
        if link.part.Parent then
          local okOwner, owned = pcall(isnetworkowner, link.part)
          if okOwner and not owned then missing[#missing + 1] = link.part.Name end
        end
      end
      if #missing > 0 then
        warn("reanimlol: not network owner of: " .. table.concat(missing, ", ") .. " (others can't see these parts move)")
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
      boostSimulation(player)
      checkOwnership()
      humanoid.RequiresNeck, humanoid.BreakJointsOnDeath, humanoid.PlatformStand = false, false, true
      for joint in pairs(session.jointCandidates) do
        if joint:IsDescendantOf(character) then
          if bodyJoint(joint, character) then sourceObject(session, joint) end
        else
          if not session.removedJoints[joint] then
            local saved = session.saved[joint]
            if saved and saved.Enabled and joint.Parent then joint.Enabled = saved.Enabled.value end
            session.jointCandidates[joint] = nil
          end
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
    noclip = true, keyToggle = "RightControl", keyGui = "RightShift", keyStop = "X",
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

-- No built-in state animations: states stay empty until you assign a clip

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
local engine = {motors = {}, stateAnims = {}, gen = {}, token = 0, fadeT = 1, snapshot = {}, baked = {}, parts = {}, collide = {}}
local rec = {on = false, clip = nil, t = 0, acc = 0, frames = 0}
local updateRecUI

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
        local anim = resolveAnim(data.states[s])
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
        cur.t += dt * settings.speed * rate
        local t = cur.t
        if loop then
            t = t % dur
        elseif t >= dur then
            t = dur
            if e and not desired.hold then engine.emote = nil end
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
local tabNames = {"Emotes", "States", "Import", "Record", "Settings"}
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
label(tabE, "Select an animation, then pick a state to assign it to:", 2, 268, 350, 14, {TextSize = 10, TextColor3 = C.dim})

local KEYSHORT = {Zero = "0", One = "1", Two = "2", Three = "3", Four = "4", Five = "5", Six = "6",
    Seven = "7", Eight = "8", Nine = "9", LeftControl = "LCtrl", RightControl = "RCtrl", LeftShift = "LShift",
    RightShift = "RShift", LeftAlt = "LAlt", RightAlt = "RAlt", Backquote = "`", Minus = "-", Equals = "=",
    LeftBracket = "[", RightBracket = "]", Semicolon = ";", Quote = "'", Comma = ",", Period = ".", Slash = "/"}
local function keyLabel(name) return name and (KEYSHORT[name] or name) or "⌨" end

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
        TweenService:Create(row, info, {BackgroundTransparency = 0}):Play()
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
            local row = T("TextButton", {Size = UDim2.new(1, -6, 0, 30), Text = "", LayoutOrder = order,
                BackgroundColor3 = (ui.selected and ui.selected.key == e.key) and C.sel or C.field}, list)
            corner(row, 8)
            local hasX = e.custom or e.recorded
            label(row, e.name, 10, 0, 135, 30, {TextTruncate = Enum.TextTruncate.AtEnd})
            label(row, e.sub, 150, 0, 90, 30, {TextSize = 10, TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Right})
            -- keybind button: click, then press a key (Esc cancels, Backspace clears)
            local bindBtn = T("TextButton", {Position = UDim2.new(1, hasX and -106 or -78, 0, 3), Size = UDim2.fromOffset(44, 24),
                Text = keyLabel(data.binds[e.key]), TextSize = 11, TextTruncate = Enum.TextTruncate.AtEnd,
                BackgroundColor3 = C.list, TextColor3 = data.binds[e.key] and C.text or C.dim}, row)
            corner(bindBtn, 6)
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
                    data.binds[e.key] = nil
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
    local x = math.clamp(rel.X, 6, 380 - w - 6)
    local y = rel.Y + anchor.AbsoluteSize.Y / scale + 2
    if y + h > 464 then y = rel.Y - h - 2 end

    dropCatcher = T("TextButton", {Size = UDim2.fromOffset(4000, 4000), Position = UDim2.fromOffset(-2000, -2000),
        BackgroundTransparency = 1, Text = "", ZIndex = 9}, panel)
    dropCatcher.Activated:Connect(closeDropdown)

    local frame = T("Frame", {Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h),
        BackgroundColor3 = C.bg, ZIndex = 10}, panel)
    dropFrame = frame
    corner(frame, 10)
    local stroke = Instance.new("UIStroke")
    stroke.Color, stroke.Thickness, stroke.ApplyStrokeMode = C.stroke, 1.5, Enum.ApplyStrokeMode.Border
    stroke.Parent = frame
    local searchBox = box(frame, "Search clips", 6, 6, w - 12, 26)
    local listFrame = T("ScrollingFrame", {Position = UDim2.fromOffset(6, 38), Size = UDim2.fromOffset(w - 12, h - 44),
        BackgroundColor3 = C.list, ScrollBarThickness = 4, CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y}, frame)
    corner(listFrame, 8)
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
            corner(row, 6)
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
    local x = math.clamp(rel.X, 6, math.max(6, 380 - w - 6))
    local y = rel.Y - h - 2 -- opens upward; the button sits near the bottom of the panel
    if y < 6 then y = rel.Y + anchor.AbsoluteSize.Y / scale + 2 end

    dropCatcher = T("TextButton", {Size = UDim2.fromOffset(4000, 4000), Position = UDim2.fromOffset(-2000, -2000),
        BackgroundTransparency = 1, Text = "", ZIndex = 9}, panel)
    dropCatcher.Activated:Connect(closeDropdown)
    local frame = T("Frame", {Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h),
        BackgroundColor3 = C.bg, ZIndex = 10}, panel)
    dropFrame = frame
    corner(frame, 10)
    local stroke = Instance.new("UIStroke")
    stroke.Color, stroke.Thickness, stroke.ApplyStrokeMode = C.stroke, 1.5, Enum.ApplyStrokeMode.Border
    stroke.Parent = frame
    T("UIListLayout", {Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder}, frame)
    T("UIPadding", {PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4)}, frame)
    local picked = ui.selected
    for i, s in ipairs(STATES) do
        local row = T("TextButton", {Size = UDim2.new(1, 0, 0, 26), Text = "", LayoutOrder = i}, frame)
        corner(row, 6)
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
button(tabG, "Reset saved data", 0, 246, 356, 30, function()
    data.favorites, data.custom, data.states, data.binds = {}, {}, {}, {}
    saveData()
    ui.main, ui.sub, ui.selected = "All", "All", nil
    refreshChips(); rebuildList(); refreshStateRows()
    for _, s in ipairs(STATES) do refreshState(s) end
    setStatus("Data reset")
end)
label(tabG, "Esc cancels a rebind. Hotkeys are ignored while typing in a text box. Emote binds: click the ⌨ button on an emote row, then press a key (Backspace clears).", 4, 284, 350, 30,
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
            elseif k == settings.keyToggle or k == settings.keyGui or k == settings.keyStop then
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
                b.TextColor3 = data.binds[entryKey] and C.text or C.dim
            end
        end
        return
    end
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
