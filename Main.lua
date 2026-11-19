# Roblox Advanced Player Control Menu

A self-contained, WindUI-inspired Roblox Studio implementation. No executors, loadstring, HTTP downloads, or external injection. The UI is custom Roblox UI, not the WindUI library. This package contains two scripts; install both in the locations below.

## Install

1. Create a **Script** named `AbilitiesServer` in **ServerScriptService**. Paste script 1.
2. Create a **LocalScript** named `AbilitiesClient` in **StarterPlayer > StarterPlayerScripts**. Paste script 2 (all sections of script 2 belong in the SAME LocalScript).
3. In Studio's Test tools, launch a server with two players. Ordinary Play Solo has no other player to target.
4. Press **RightShift** or the floating **Abilities** button to show/hide the menu. Drag the title bar. Tabs and lists scroll on touch devices.
5. Test **Strike** near another player. Server default: 15 damage, 0.45-second cooldown, maximum 14-stud root distance, team and line-of-sight validation. A ForceField prevents damage through Roblox's normal TakeDamage behavior.

All players receive these abilities as gameplay features. Change the server `allowed` function to integrate your own unlocks, stamina, rounds, or ability zones. Set `AllowFriendlyFire` deliberately. Visual/team filters in aim assist do not override server combat rules.

### Behavior

- Aim assist selects the closest eligible screen-space target inside the displayed FOV circle, retains it while eligible, and smoothly steers the camera. At 100% it snaps each rendered frame; at 0% camera steering is disabled. Target bones resolve for R6 and R15.
- Highlight visibility can be Always or Visible only; Show allies controls highlighting, while Aim team check controls targeting. Names, distances, and bars have individual toggles.
- Speed and jump sliders are direct WalkSpeed/JumpPower values 0–100, not percentages. Strength is a percentage. FOV is a pixel radius, clamped visually to the viewport.
- Flight: PC WASD, Space up, Ctrl down. Touch uses the existing Roblox movement joystick only; look up/down while pushing forward/back to climb/descend. Keyboard and gamepad MoveDirection also work. There are no extra touch ascent buttons.
- Noclip disables character collisions on the server and restores each saved original value on exit, death, respawn, or script shutdown. Leave flight on while passing through floors to avoid falling.
- The hitbox slider changes the player's **melee attack volume**, not opponent body-part sizes. The server performs an oriented overlap query on Strike, then validates distance, teams, health, and line of sight before applying damage once per character. Size changes apply to the next strike immediately. The local box is a visualization only.
- Teleport places you three studs behind the selected player at a server raycast floor position, rejecting blocked or unsupported destinations. Some unusual avatar sizes or custom collision systems may require tuning clearance checks.
- Fly physics are simulated with server-created constraints and server network ownership while flying. Normal walking still uses standard Roblox character replication. This is a gameplay package, not a general anti-cheat; add movement auditing for competitive experiences.
- Server requests are rate-limited, numeric values bounded, vectors checked, and flight input expires if updates stop. Combat uses server world state, not client hit reports. No lag compensation is included.

## Script 1 — ServerScriptService/AbilitiesServer

```lua
--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CONFIG = {
    Damage = 15,
    StrikeCooldown = 0.45,
    MaxHitDistance = 14,
    AllowFriendlyFire = false,
    TeleportCooldown = 1,
}

local previous = ReplicatedStorage:FindFirstChild("PlayerAbilities")
if previous then previous:Destroy() end
local folder = Instance.new("Folder")
folder.Name = "PlayerAbilities"
folder.Parent = ReplicatedStorage
local remote = Instance.new("RemoteEvent")
remote.Name = "Request"
remote.Parent = folder
local reply = Instance.new("RemoteEvent")
reply.Name = "Reply"
reply.Parent = folder

local states: {[Player]: any} = {}
local function allowed(player: Player, _ability: string): boolean
    return player.Parent == Players -- Integrate your game's ability unlock rules here.
end
local function finite(n: any): boolean
    return typeof(n) == "number" and n == n and math.abs(n) < math.huge
end
local function sameTeam(a: Player, b: Player): boolean
    return not a.Neutral and not b.Neutral and a.Team ~= nil and a.Team == b.Team
end
local function rig(player: Player): (Model?, Humanoid?, BasePart?)
    local c = player.Character
    if not c then return nil, nil, nil end
    local h = c:FindFirstChildOfClass("Humanoid")
    local r = c:FindFirstChild("HumanoidRootPart")
    if not h or h.Health <= 0 or not r or not r:IsA("BasePart") then
        return nil, nil, nil
    end
    return c, h, r
end
local function notify(p: Player, text: string)
    reply:FireClient(p, text)
end
local function clearFly(s: any)
    local f = s.flight
    if not f then return end
    f.velocity:Destroy()
    f.orientation:Destroy()
    f.attachment:Destroy()
    if f.humanoid.Parent then
        f.humanoid.AutoRotate = f.autoRotate
        f.humanoid.PlatformStand = f.platformStand
    end
    if f.root.Parent then
        pcall(function() f.root:SetNetworkOwnershipAuto() end)
    end
    s.flight = nil
    s.input = Vector3.zero
end
local function restoreCollisions(s: any)
    for part, original in pairs(s.collisions) do
        if part.Parent then part.CanCollide = original end
    end
    table.clear(s.collisions)
end
local function setFly(player: Player, s: any, enabled: boolean)
    clearFly(s)
    s.fly = false
    if enabled then
        local _, humanoid, root = rig(player)
        if not humanoid or not root then return end
        local a = Instance.new("Attachment")
        a.Name = "AbilityFlight"
        a.Parent = root
        local v = Instance.new("LinearVelocity")
        v.Attachment0 = a
        v.RelativeTo = Enum.ActuatorRelativeTo.World
        v.MaxForce = math.huge
        v.VectorVelocity = Vector3.zero
        v.Parent = root
        local o = Instance.new("AlignOrientation")
        o.Attachment0 = a
        o.Mode = Enum.OrientationAlignmentMode.OneAttachment
        o.MaxTorque = math.huge
        o.Responsiveness = 20
        local flat = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
        if flat.Magnitude < 0.01 then flat = Vector3.new(0, 0, -1) end
        o.CFrame = CFrame.lookAt(Vector3.zero, flat)
        o.Parent = root
        s.flight = {attachment = a, velocity = v, orientation = o, root = root,
            humanoid = humanoid, autoRotate = humanoid.AutoRotate,
            platformStand = humanoid.PlatformStand}
        humanoid.AutoRotate = false
        humanoid.PlatformStand = true
        pcall(function() root:SetNetworkOwner(nil) end)
        s.fly = true
        s.inputAt = os.clock()
    end
    if player.Character then player.Character:SetAttribute("AbilityFly", s.fly) end
end
local function clearCharacter(s: any)
    clearFly(s)
    restoreCollisions(s)
    s.fly = false
    s.noclip = false
    if s.death then s.death:Disconnect(); s.death = nil end
end
local function setup(player: Player)
    local s = {walk = 16, jump = 50, flySpeed = 50, hitbox = 4,
        fly = false, noclip = false, input = Vector3.zero, inputAt = 0,
        collisions = {}, tokens = 35, tokenAt = os.clock(),
        strikeAt = -math.huge, teleportAt = -math.huge}
    states[player] = s
    local function spawnCharacter(character: Model)
        clearCharacter(s)
        local h = character:WaitForChild("Humanoid", 10)
        if not h or not h:IsA("Humanoid") or player.Character ~= character then return end
        h.UseJumpPower = true
        h.WalkSpeed = s.walk
        h.JumpPower = s.jump
        character:SetAttribute("AbilityFly", false)
        character:SetAttribute("AbilityNoclip", false)
        s.death = h.Died:Connect(function() clearCharacter(s) end)
    end
    player.CharacterAdded:Connect(spawnCharacter)
    player.CharacterRemoving:Connect(function() clearCharacter(s) end)
    if player.Character then task.spawn(spawnCharacter, player.Character) end
end
Players.PlayerAdded:Connect(setup)
for _, player in Players:GetPlayers() do setup(player) end
Players.PlayerRemoving:Connect(function(player)
    local s = states[player]
    if s then clearCharacter(s) end
    states[player] = nil
end)

local function strike(player: Player, s: any)
    local now = os.clock()
    if now - s.strikeAt < CONFIG.StrikeCooldown then return end
    local character, _, root = rig(player)
    if not character or not root then return end
    s.strikeAt = now
    local size = s.hitbox
    local box = root.CFrame * CFrame.new(0, 0, -(2 + size / 2))
    local overlap = OverlapParams.new()
    overlap.FilterType = Enum.RaycastFilterType.Exclude
    overlap.FilterDescendantsInstances = {character}
    local ray = RaycastParams.new()
    ray.FilterType = Enum.RaycastFilterType.Exclude
    ray.FilterDescendantsInstances = {character}
    local seen: {[Model]: boolean} = {}
    local hits = 0
    for _, part in Workspace:GetPartBoundsInBox(box, Vector3.new(size, size, size), overlap) do
        local model = part:FindFirstAncestorOfClass("Model")
        -- Accessories may introduce another Model: walk up until a character is found.
        while model and not model:FindFirstChildOfClass("Humanoid") do
            model = model.Parent and model.Parent:FindFirstAncestorOfClass("Model")
        end
        if not model or seen[model] then continue end
        seen[model] = true
        local target = Players:GetPlayerFromCharacter(model)
        if not target or target == player then continue end
        if not CONFIG.AllowFriendlyFire and sameTeam(player, target) then continue end
        local _, h, r = rig(target)
        if not h or not r or (r.Position - root.Position).Magnitude > CONFIG.MaxHitDistance then continue end
        local obstruction = Workspace:Raycast(root.Position, r.Position - root.Position, ray)
        if obstruction and not obstruction.Instance:IsDescendantOf(model) then continue end
        h:TakeDamage(CONFIG.Damage)
        hits += 1
    end
    notify(player, if hits > 0 then "Strike: " .. hits .. " target(s)" else "Strike: no eligible target")
end
local function teleport(player: Player, s: any, userId: any)
    if not finite(userId) then return end
    if os.clock() - s.teleportAt < CONFIG.TeleportCooldown then return end
    s.teleportAt = os.clock()
    local target = Players:GetPlayerByUserId(userId)
    local character, h, root = rig(player)
    if not target or target == player or not character or not h or not root then return end
    local _, _, tr = rig(target)
    if not tr then return end
    local desired = (tr.CFrame * CFrame.new(0, 0, 3)).Position
    local ray = RaycastParams.new()
    ray.FilterType = Enum.RaycastFilterType.Exclude
    ray.FilterDescendantsInstances = {character, target.Character :: Model}
    local floor = Workspace:Raycast(desired + Vector3.new(0, 8, 0), Vector3.new(0, -40, 0), ray)
    if not floor or floor.Normal.Y < 0.5 then notify(player, "Teleport: no safe floor"); return end
    local position = floor.Position + Vector3.new(0, h.HipHeight + root.Size.Y / 2 + 0.15, 0)
    -- Approximate standing-character clearance; ignore the floor by lifting the box bottom.
    local overlap = OverlapParams.new()
    overlap.FilterType = Enum.RaycastFilterType.Exclude
    overlap.FilterDescendantsInstances = {character}
    local bounds = CFrame.new(floor.Position + Vector3.new(0, 3.1, 0))
    for _, part in Workspace:GetPartBoundsInBox(bounds, Vector3.new(2.8, 5.8, 2.8), overlap) do
        if part.CanCollide then notify(player, "Teleport: destination blocked"); return end
    end
    local look = Vector3.new(tr.Position.X, position.Y, tr.Position.Z)
    local targetRoot = CFrame.lookAt(position, look)
    local rootToPivot = root.CFrame:ToObjectSpace(character:GetPivot())
    character:PivotTo(targetRoot * rootToPivot)
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    notify(player, "Teleported to " .. target.DisplayName)
end

remote.OnServerEvent:Connect(function(player: Player, action: any, value: any)
    local s = states[player]
    if not s or typeof(action) ~= "string" then return end
    local now = os.clock()
    if action == "FlyInput" then
        if not s.fly or now - (s.lastInputPacket or 0) < 1 / 40 then return end
        s.lastInputPacket = now
        if typeof(value) ~= "Vector3" or not finite(value.X) or not finite(value.Y) or not finite(value.Z) then return end
        s.input = if value.Magnitude > 1 then value.Unit else value
        s.inputAt = now
        return
    end
    s.tokens = math.min(35, s.tokens + (now - s.tokenAt) * 25)
    s.tokenAt = now
    if s.tokens < 1 or not allowed(player, action) then return end
    s.tokens -= 1
    local _, h = rig(player)
    if action == "WalkSpeed" and finite(value) then
        s.walk = math.clamp(value, 0, 100)
        if h then h.WalkSpeed = s.walk end
    elseif action == "JumpPower" and finite(value) then
        s.jump = math.clamp(value, 0, 100)
        if h then h.UseJumpPower = true; h.JumpPower = s.jump end
    elseif action == "FlySpeed" and finite(value) then
        s.flySpeed = math.clamp(value, 0, 100)
    elseif action == "HitboxSize" and finite(value) then
        s.hitbox = math.clamp(value, 2, 12)
    elseif action == "Fly" and typeof(value) == "boolean" then
        setFly(player, s, value)
    elseif action == "Noclip" and typeof(value) == "boolean" then
        s.noclip = value and h ~= nil
        if not s.noclip then restoreCollisions(s) end
        if player.Character then player.Character:SetAttribute("AbilityNoclip", s.noclip) end
    elseif action == "Strike" then
        strike(player, s)
    elseif action == "Teleport" then
        teleport(player, s, value)
    end
end)
RunService.PreSimulation:Connect(function(dt)
    for player, s in pairs(states) do
        local character = player.Character
        if s.noclip and character then
            for _, part in character:GetDescendants() do
                if part:IsA("BasePart") then
                    if s.collisions[part] == nil then s.collisions[part] = part.CanCollide end
                    part.CanCollide = false
                end
            end
        end
        local f = s.flight
        if f then
            if not f.root.Parent or f.humanoid.Health <= 0 then clearFly(s); continue end
            local input = if os.clock() - s.inputAt <= 0.35 then s.input else Vector3.zero
            local targetVelocity = input * s.flySpeed
            f.velocity.VectorVelocity = f.velocity.VectorVelocity:Lerp(targetVelocity, 1 - math.exp(-16 * dt))
            local flat = Vector3.new(input.X, 0, input.Z)
            if flat.Magnitude > 0.05 then f.orientation.CFrame = CFrame.lookAt(Vector3.zero, flat.Unit) end
        end
    end
end)
game:BindToClose(function()
    for _, s in pairs(states) do clearCharacter(s) end
end)
```

## Script 2 — StarterPlayer/StarterPlayerScripts/AbilitiesClient

Paste ALL of the following client sections, in order, into one LocalScript.

```lua
--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")
local player = Players.LocalPlayer
local net = ReplicatedStorage:WaitForChild("PlayerAbilities")
local remote = net:WaitForChild("Request") :: RemoteEvent
local reply = net:WaitForChild("Reply") :: RemoteEvent
local settings: any = {
    aim = false, strength = 50, bone = "Head", team = true, wall = true, fov = 160,
    ring = true, highlight = false, names = true, distance = true, health = true,
    allies = true, visibility = "Always", fly = false, noclip = false,
    walk = 16, jump = 50, flySpeed = 50, hitbox = 4, visualize = false,
}
local C = {
    bg = Color3.fromRGB(17, 20, 29), panel = Color3.fromRGB(25, 29, 41),
    row = Color3.fromRGB(33, 38, 52), accent = Color3.fromRGB(94, 192, 169),
    text = Color3.fromRGB(235, 240, 248), muted = Color3.fromRGB(157, 170, 188),
}
local function new(class: string, props: any, parent: Instance?): any
    local object = Instance.new(class)
    for key, value in pairs(props) do (object :: any)[key] = value end
    object.Parent = parent
    return object
end
local function corner(object: Instance, radius: number?)
    new("UICorner", {CornerRadius = UDim.new(0, radius or 9)}, object)
end
local function text(parent: Instance, value: string, size: number?): TextLabel
    return new("TextLabel", {BackgroundTransparency = 1, Text = value,
        TextColor3 = C.text, TextSize = size or 14, Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, 0, 0, 24)}, parent)
end
local gui = new("ScreenGui", {Name = "PlayerAbilitiesUI", ResetOnSpawn = false,
    IgnoreGuiInset = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling}, player:WaitForChild("PlayerGui"))
local launcher = new("TextButton", {Size = UDim2.fromOffset(104, 38),
    Position = UDim2.new(1, -116, 0, 12), BackgroundColor3 = C.accent,
    Text = "Abilities", TextColor3 = C.bg, Font = Enum.Font.GothamBold, TextSize = 14}, gui)
corner(launcher)
local window = new("Frame", {Size = UDim2.fromOffset(470, 530),
    Position = UDim2.new(0.5, -235, 0.5, -265), BackgroundColor3 = C.bg,
    BorderSizePixel = 0, ClipsDescendants = true}, gui)
corner(window, 14)
new("UIStroke", {Color = Color3.fromRGB(61, 72, 90), Thickness = 1}, window)
local header = new("Frame", {Size = UDim2.new(1, 0, 0, 58), BackgroundTransparency = 1, Active = true}, window)
local title = text(header, "PLAYER  /  ABILITIES", 16)
title.Font = Enum.Font.GothamBold
title.Position = UDim2.fromOffset(18, 10)
title.Size = UDim2.new(1, -72, 0, 24)
local subtitle = text(header, "Gameplay controls • PC + mobile", 11)
subtitle.TextColor3 = C.muted
subtitle.Position = UDim2.fromOffset(18, 32)
subtitle.Size = UDim2.new(1, -72, 0, 18)
local close = new("TextButton", {Text = "×", TextSize = 25, Font = Enum.Font.Gotham,
    TextColor3 = C.muted, BackgroundTransparency = 1, Size = UDim2.fromOffset(42, 42),
    Position = UDim2.new(1, -47, 0, 7)}, header)
local tabs = new("ScrollingFrame", {Position = UDim2.fromOffset(12, 62),
    Size = UDim2.new(1, -24, 0, 39), BackgroundTransparency = 1, BorderSizePixel = 0,
    ScrollBarThickness = 0, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.X,
    ScrollingDirection = Enum.ScrollingDirection.X}, window)
new("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6)}, tabs)
local content = new("Frame", {Position = UDim2.fromOffset(12, 109),
    Size = UDim2.new(1, -24, 1, -148), BackgroundTransparency = 1}, window)
local status = text(window, "Ready", 11)
status.TextColor3 = C.muted
status.Position = UDim2.new(0, 18, 1, -31)
status.Size = UDim2.new(1, -36, 0, 23)
status.TextTruncate = Enum.TextTruncate.AtEnd
local function message(value: string) status.Text = value end
reply.OnClientEvent:Connect(message)
launcher.Activated:Connect(function() window.Visible = not window.Visible end)
close.Activated:Connect(function() window.Visible = false end)

local dragging: InputObject? = nil
local dragStart = Vector2.zero
local frameStart = Vector2.zero
local function clampWindow()
    local available = gui.AbsoluteSize
    local size = Vector2.new(math.min(470, math.max(240, available.X - 16)), math.min(530, math.max(180, available.Y - 16)))
    window.Size = UDim2.fromOffset(size.X, size.Y)
    local p = window.AbsolutePosition - gui.AbsolutePosition
    window.Position = UDim2.fromOffset(math.clamp(p.X, 0, math.max(0, available.X - size.X)), math.clamp(p.Y, 0, math.max(0, available.Y - size.Y)))
end
header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = input
        dragStart = Vector2.new(input.Position.X, input.Position.Y)
        frameStart = Vector2.new(window.Position.X.Offset, window.Position.Y.Offset)
    end
end)
UIS.InputChanged:Connect(function(input)
    if dragging and (input == dragging or input.UserInputType == Enum.UserInputType.MouseMovement) then
        local delta = Vector2.new(input.Position.X, input.Position.Y) - dragStart
        window.Position = UDim2.fromOffset(frameStart.X + delta.X, frameStart.Y + delta.Y)
        clampWindow()
    end
end)
UIS.InputEnded:Connect(function(input)
    if input == dragging then dragging = nil end
end)
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(clampWindow)
task.defer(clampWindow)

local pages: {[string]: ScrollingFrame} = {}
local tabButtons: {[string]: TextButton} = {}
local first = true
local function page(name: string): ScrollingFrame
    local p = new("ScrollingFrame", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
        BorderSizePixel = 0, ScrollBarThickness = 3, ScrollBarImageColor3 = C.accent,
        CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y, Visible = first}, content)
    new("UIListLayout", {Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder}, p)
    new("UIPadding", {PaddingRight = UDim.new(0, 7), PaddingBottom = UDim.new(0, 10)}, p)
    local b = new("TextButton", {Size = UDim2.fromOffset(if name == "Highlights" then 98 else 82, 35),
        BackgroundColor3 = if first then C.accent else C.panel,
        TextColor3 = if first then C.bg else C.text, Text = name,
        TextSize = 12, Font = Enum.Font.GothamMedium}, tabs)
    corner(b)
    pages[name] = p
    tabButtons[name] = b
    b.Activated:Connect(function()
        for key, child in pairs(pages) do
            child.Visible = key == name
            tabButtons[key].BackgroundColor3 = if key == name then C.accent else C.panel
            tabButtons[key].TextColor3 = if key == name then C.bg else C.text
        end
    end)
    first = false
    return p
end
local function row(parent: Instance, height: number): Frame
    local r = new("Frame", {Size = UDim2.new(1, 0, 0, height), BackgroundColor3 = C.panel,
        BorderSizePixel = 0}, parent)
    corner(r)
    return r
end
local function label(r: Frame, name: string)
    local l = text(r, name)
    l.Position = UDim2.fromOffset(12, 9)
    l.Size = UDim2.new(1, -104, 0, 25)
    l.TextTruncate = Enum.TextTruncate.AtEnd
end
local function toggle(parent: Instance, name: string, initial: boolean, callback: (boolean) -> ()): (boolean?) -> ()
    local r = row(parent, 44)
    label(r, name)
    local state = initial
    local b = new("TextButton", {Size = UDim2.fromOffset(66, 28), Position = UDim2.new(1, -78, 0, 8),
        TextSize = 12, Font = Enum.Font.GothamBold, Text = "", BorderSizePixel = 0}, r)
    corner(b, 14)
    local function paint()
        b.Text = if state then "ON" else "OFF"
        b.TextColor3 = if state then C.bg else C.muted
        TweenService:Create(b, TweenInfo.new(0.12), {BackgroundColor3 = if state then C.accent else C.row}):Play()
    end
    b.Activated:Connect(function() state = not state; paint(); callback(state) end)
    paint()
    return function(value: boolean?)
        state = value == true
        paint()
    end
end
-- Network-bound slider updates are throttled; release always submits the latest value.
local function slider(parent: Instance, name: string, minimum: number, maximum: number, initial: number, callback: (number) -> ())
    local r = row(parent, 72)
    label(r, name)
    local valueLabel = text(r, tostring(initial), 13)
    valueLabel.TextColor3 = C.accent
    valueLabel.TextXAlignment = Enum.TextXAlignment.Right
    valueLabel.Position = UDim2.new(1, -86, 0, 10)
    valueLabel.Size = UDim2.fromOffset(72, 22)
    local area = new("TextButton", {Text = "", AutoButtonColor = false, BackgroundTransparency = 1,
        Size = UDim2.new(1, -24, 0, 32), Position = UDim2.fromOffset(12, 35)}, r)
    local track = new("Frame", {BackgroundColor3 = C.row, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 5), Position = UDim2.new(0, 0, 0.5, -2)}, area)
    corner(track)
    local fill = new("Frame", {BackgroundColor3 = C.accent, BorderSizePixel = 0, Size = UDim2.new()}, track)
    corner(fill)
    local knob = new("Frame", {BackgroundColor3 = C.text, BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(15, 15)}, track)
    corner(knob, 10)
    local current = initial
    local active: InputObject? = nil
    local lastSend = -math.huge
    local function paint()
        local alpha = (current - minimum) / (maximum - minimum)
        fill.Size = UDim2.new(alpha, 0, 1, 0)
        knob.Position = UDim2.new(alpha, 0, 0.5, 0)
        valueLabel.Text = tostring(current)
    end
    local function update(x: number)
        local alpha = math.clamp((x - area.AbsolutePosition.X) / math.max(1, area.AbsoluteSize.X), 0, 1)
        current = math.round(minimum + alpha * (maximum - minimum))
        paint()
        if os.clock() - lastSend >= 0.1 then lastSend = os.clock(); callback(current) end
    end
    area.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            active = input
            update(input.Position.X)
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if active and (input == active or input.UserInputType == Enum.UserInputType.MouseMovement) then update(input.Position.X) end
    end)
    UIS.InputEnded:Connect(function(input)
        if input == active then active = nil; callback(current) end
    end)
    paint()
end
local function button(parent: Instance, name: string, callback: () -> ()): TextButton
    local b = new("TextButton", {Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = C.row,
        Text = name, TextColor3 = C.text, Font = Enum.Font.GothamMedium, TextSize = 14}, parent)
    corner(b)
    b.Activated:Connect(callback)
    return b
end
local function note(parent: Instance, value: string)
    local r = row(parent, 62)
    local l = text(r, value, 12)
    l.Position = UDim2.fromOffset(12, 6)
    l.Size = UDim2.new(1, -24, 1, -12)
    l.TextWrapped = true
    l.TextColor3 = C.muted
end
local function dropdown(parent: Instance, name: string, initial: string, callback: (string) -> ())
    local holder = new("Frame", {Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.Y}, parent)
    new("UIListLayout", {Padding = UDim.new(0, 4)}, holder)
    local top = button(holder, name .. ": " .. initial, function() end)
    local list = new("ScrollingFrame", {Visible = false, Size = UDim2.new(1, 0, 0, 140),
        BackgroundColor3 = C.panel, BorderSizePixel = 0, ScrollBarThickness = 3,
        AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new()}, holder)
    corner(list)
    new("UIListLayout", {Padding = UDim.new(0, 3)}, list)
    top.Activated:Connect(function() list.Visible = not list.Visible end)
    local function replace(options: {string})
        for _, child in list:GetChildren() do if child:IsA("TextButton") then child:Destroy() end end
        list.Size = UDim2.new(1, 0, 0, math.clamp(#options * 42, 42, 168))
        for _, option in options do
            local b = button(list, option, function()
                top.Text = name .. ": " .. option
                list.Visible = false
                callback(option)
            end)
            b.Size = UDim2.new(1, -4, 0, 39)
            b.TextTruncate = Enum.TextTruncate.AtEnd
        end
    end
    local function caption(value: string) top.Text = name .. ": " .. value end
    return replace, caption
end
```

Continue in the SAME AbilitiesClient LocalScript, immediately after the preceding code:

```lua
local aimPage = page("Aim")
toggle(aimPage, "Target lock", false, function(v) settings.aim = v end)
slider(aimPage, "Strength (%)", 0, 100, 50, function(v) settings.strength = v end)
local setBones = dropdown(aimPage, "Target", "Head", function(v) settings.bone = v end)
setBones({"Head", "Chest", "Knee", "Feet"})
toggle(aimPage, "Team check", true, function(v) settings.team = v end)
toggle(aimPage, "Line-of-sight check", true, function(v) settings.wall = v end)
slider(aimPage, "FOV radius (pixels)", 30, 500, 160, function(v) settings.fov = v end)
toggle(aimPage, "Show FOV circle", true, function(v) settings.ring = v end)
note(aimPage, "Targets must remain inside the FOV. 100% snaps instantly; 0% does not move your camera.")
local highPage = page("Highlights")
toggle(highPage, "Player highlights", false, function(v) settings.highlight = v end)
toggle(highPage, "Player names", true, function(v) settings.names = v end)
toggle(highPage, "Distance", true, function(v) settings.distance = v end)
toggle(highPage, "Health bars", true, function(v) settings.health = v end)
toggle(highPage, "Show allies", true, function(v) settings.allies = v end)
local setVisibility = dropdown(highPage, "Visibility", "Always", function(v) settings.visibility = v end)
setVisibility({"Always", "Visible only"})
local movePage = page("Movement")
slider(movePage, "WalkSpeed", 0, 100, 16, function(v) settings.walk = v; remote:FireServer("WalkSpeed", v) end)
slider(movePage, "JumpPower", 0, 100, 50, function(v) settings.jump = v; remote:FireServer("JumpPower", v) end)
local syncFly = toggle(movePage, "Fly", false, function(v)
    settings.fly = v
    remote:FireServer("Fly", v)
end)
slider(movePage, "Fly speed", 0, 100, 50, function(v) settings.flySpeed = v; remote:FireServer("FlySpeed", v) end)
local syncNoclip = toggle(movePage, "Noclip", false, function(v)
    settings.noclip = v
    remote:FireServer("Noclip", v)
end)
note(movePage, "PC: WASD, Space up, Ctrl down. Touch: joystick only; tilt the camera up/down to climb or descend.")
local hitPage = page("Hitbox")
slider(hitPage, "Melee hitbox size (studs)", 2, 12, 4, function(v)
    settings.hitbox = v
    remote:FireServer("HitboxSize", v)
end)
toggle(hitPage, "Visualize hitbox", false, function(v) settings.visualize = v end)
button(hitPage, "Strike  [F / touch attack button]", function() remote:FireServer("Strike") end)
note(hitPage, "One forward cubic attack volume. The server detects and damages eligible players when you strike.")
local tpPage = page("Teleport")
local selectedId: number? = nil
local playerOptions: {[string]: number} = {}
local setPlayers, setPlayerCaption = dropdown(tpPage, "Player", "Select a player", function(v)
    selectedId = playerOptions[v]
end)
local function refreshPlayers()
    local choices = {}
    table.clear(playerOptions)
    for _, other in Players:GetPlayers() do
        if other ~= player then
            local name = other.DisplayName .. " (@" .. other.Name .. ")"
            playerOptions[name] = other.UserId
            table.insert(choices, name)
        end
    end
    table.sort(choices)
    setPlayers(choices)
    if selectedId and not Players:GetPlayerByUserId(selectedId) then selectedId = nil end
    if not selectedId then setPlayerCaption("Select a player") end
end
Players.PlayerAdded:Connect(function() task.defer(refreshPlayers) end)
Players.PlayerRemoving:Connect(function(leaving)
    if selectedId == leaving.UserId then selectedId = nil end
    task.defer(refreshPlayers)
end)
refreshPlayers()
button(tpPage, "Teleport to selected player", function()
    if selectedId then remote:FireServer("Teleport", selectedId) else message("Select a player first") end
end)
note(tpPage, "Destination safety, target availability, and cooldown are checked on the server.")

-- A compact attack control stays available when the menu is closed.
local attack = new("TextButton", {AnchorPoint = Vector2.new(1, 1),
    Position = UDim2.new(1, -24, 1, -180), Size = UDim2.fromOffset(76, 54),
    BackgroundColor3 = C.accent, TextColor3 = C.bg, Text = "STRIKE",
    TextSize = 12, Font = Enum.Font.GothamBold}, gui)
corner(attack, 20)
attack.Activated:Connect(function() remote:FireServer("Strike") end)
UIS.InputBegan:Connect(function(input, processed)
    if processed or UIS:GetFocusedTextBox() then return end
    if input.KeyCode == Enum.KeyCode.RightShift then window.Visible = not window.Visible end
    if input.KeyCode == Enum.KeyCode.F then remote:FireServer("Strike") end
end)
UIS.WindowFocusReleased:Connect(function()
    if settings.fly then remote:FireServer("FlyInput", Vector3.zero) end
end)
local charConnections: {RBXScriptConnection} = {}
local function bindCharacter(character: Model)
    for _, connection in charConnections do connection:Disconnect() end
    table.clear(charConnections)
    settings.fly = character:GetAttribute("AbilityFly") == true
    settings.noclip = character:GetAttribute("AbilityNoclip") == true
    syncFly(settings.fly)
    syncNoclip(settings.noclip)
    table.insert(charConnections, character:GetAttributeChangedSignal("AbilityFly"):Connect(function()
        settings.fly = character:GetAttribute("AbilityFly") == true
        syncFly(settings.fly)
    end))
    table.insert(charConnections, character:GetAttributeChangedSignal("AbilityNoclip"):Connect(function()
        settings.noclip = character:GetAttribute("AbilityNoclip") == true
        syncNoclip(settings.noclip)
    end))
end
player.CharacterAdded:Connect(bindCharacter)
if player.Character then bindCharacter(player.Character) end

local visuals = new("Folder", {Name = "AbilityLocalVisuals"}, Workspace)
local hitbox = new("Part", {Name = "MeleeHitboxPreview", Anchored = true,
    CanCollide = false, CanTouch = false, CanQuery = false, CastShadow = false,
    Material = Enum.Material.ForceField, Color = C.accent, Transparency = 1,
    Size = Vector3.new(4, 4, 4)}, visuals)
local ring = new("Frame", {Name = "AimFOV", BackgroundTransparency = 1,
    AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(320, 320), Visible = false}, gui)
corner(ring, 10000)
local ringStroke = new("UIStroke", {Color = C.accent, Thickness = 1, Transparency = 0.3}, ring)
local centerDot = new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5),
    BackgroundColor3 = C.accent, Size = UDim2.fromOffset(4, 4), BorderSizePixel = 0,
    Visible = false}, gui)
corner(centerDot)
local tracks: {[Player]: any} = {}
local function destroyTrack(other: Player)
    local t = tracks[other]
    if t then t.highlight:Destroy(); t.billboard:Destroy(); tracks[other] = nil end
end
local function sameTeam(other: Player): boolean
    return not player.Neutral and not other.Neutral and player.Team ~= nil and player.Team == other.Team
end
local function getRig(other: Player): (Model?, Humanoid?, BasePart?)
    local c = other.Character
    if not c then return nil, nil, nil end
    local h = c:FindFirstChildOfClass("Humanoid")
    local root = c:FindFirstChild("HumanoidRootPart")
    if not h or h.Health <= 0 or not root or not root:IsA("BasePart") then return nil, nil, nil end
    return c, h, root
end
local function bone(character: Model): BasePart?
    local choices: {string}
    if settings.bone == "Chest" then
        choices = {"UpperTorso", "Torso", "HumanoidRootPart"}
    elseif settings.bone == "Knee" then
        choices = {"LeftLowerLeg", "RightLowerLeg", "Left Leg", "Right Leg"}
    elseif settings.bone == "Feet" then
        choices = {"LeftFoot", "RightFoot", "Left Leg", "Right Leg"}
    else choices = {"Head"} end
    for _, name in choices do
        local part = character:FindFirstChild(name)
        if part and part:IsA("BasePart") then return part end
    end
    return nil
end
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local function visible(camera: Camera, character: Model, position: Vector3): boolean
    local exclusions: {Instance} = {visuals}
    if player.Character then table.insert(exclusions, player.Character :: Model) end
    rayParams.FilterDescendantsInstances = exclusions
    local result = Workspace:Raycast(camera.CFrame.Position, position - camera.CFrame.Position, rayParams)
    return result == nil or result.Instance:IsDescendantOf(character)
end
local function makeTrack(other: Player, character: Model, root: BasePart)
    destroyTrack(other)
    local highlight = new("Highlight", {Adornee = character, Enabled = false,
        FillColor = C.accent, OutlineColor = C.accent, FillTransparency = 0.82,
        OutlineTransparency = 0.12}, visuals)
    local billboard = new("BillboardGui", {Adornee = root, Size = UDim2.fromOffset(180, 62),
        StudsOffset = Vector3.new(0, 3.6, 0), AlwaysOnTop = true,
        MaxDistance = 1500, Enabled = false}, gui)
    local name = text(billboard, "", 13)
    name.Font = Enum.Font.GothamBold
    name.TextXAlignment = Enum.TextXAlignment.Center
    name.TextStrokeTransparency = 0.35
    name.Size = UDim2.new(1, 0, 0, 20)
    local distance = text(billboard, "", 11)
    distance.TextXAlignment = Enum.TextXAlignment.Center
    distance.TextStrokeTransparency = 0.35
    distance.Position = UDim2.fromOffset(0, 21)
    distance.Size = UDim2.new(1, 0, 0, 18)
    local background = new("Frame", {Position = UDim2.new(0.15, 0, 0, 44),
        Size = UDim2.new(0.7, 0, 0, 5), BackgroundColor3 = C.bg, BorderSizePixel = 0}, billboard)
    corner(background)
    local fill = new("Frame", {Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.accent,
        BorderSizePixel = 0}, background)
    corner(fill)
    tracks[other] = {character = character, highlight = highlight, billboard = billboard,
        name = name, distance = distance, bar = background, fill = fill}
end
Players.PlayerRemoving:Connect(destroyTrack)
local function updateHighlights()
    local camera = Workspace.CurrentCamera
    if not camera then return end
    local _, _, localRoot = getRig(player)
    for _, other in Players:GetPlayers() do
        if other == player then continue end
        local character, humanoid, root = getRig(other)
        if not character or not humanoid or not root then destroyTrack(other); continue end
        if not tracks[other] and not settings.highlight then continue end
        if not tracks[other] or tracks[other].character ~= character then makeTrack(other, character, root) end
        local t = tracks[other]
        local eligible = settings.highlight and (settings.allies or not sameTeam(other))
        local _, onScreen = camera:WorldToViewportPoint(root.Position)
        local closeEnough = (camera.CFrame.Position - root.Position).Magnitude <= 1500
        eligible = eligible and onScreen and closeEnough
        if eligible and settings.visibility == "Visible only" then eligible = visible(camera, character, root.Position) end
        t.highlight.Enabled = eligible
        t.highlight.DepthMode = if settings.visibility == "Always" then Enum.HighlightDepthMode.AlwaysOnTop else Enum.HighlightDepthMode.Occluded
        t.billboard.Enabled = eligible
        if not eligible then continue end
        t.name.Visible = settings.names
        t.name.Text = other.DisplayName .. " (@" .. other.Name .. ")"
        t.distance.Visible = settings.distance
        t.distance.Text = if localRoot then tostring(math.round((localRoot.Position - root.Position).Magnitude)) .. " studs" else ""
        t.bar.Visible = settings.health
        local ratio = math.clamp(humanoid.Health / math.max(1, humanoid.MaxHealth), 0, 1)
        t.fill.Size = UDim2.fromScale(ratio, 1)
        t.fill.BackgroundColor3 = Color3.fromRGB(240, 85, 92):Lerp(C.accent, ratio)
    end
end

local currentTarget: Player? = nil
local targetPart: BasePart? = nil
local function fovRadius(camera: Camera): number
    return math.min(settings.fov, math.min(camera.ViewportSize.X, camera.ViewportSize.Y) / 2 - 8)
end
local function eligibleTarget(other: Player, camera: Camera): (BasePart?, number)
    if other == player or (settings.team and sameTeam(other)) then return nil, math.huge end
    local character, _, _ = getRig(other)
    if not character then return nil, math.huge end
    local part = bone(character)
    if not part then return nil, math.huge end
    local screen, onScreen = camera:WorldToViewportPoint(part.Position)
    if not onScreen then return nil, math.huge end
    local distance = (Vector2.new(screen.X, screen.Y) - camera.ViewportSize / 2).Magnitude
    if distance > fovRadius(camera) then return nil, math.huge end
    if settings.wall and not visible(camera, character, part.Position) then return nil, math.huge end
    return part, distance
end
local function chooseTarget()
    local camera = Workspace.CurrentCamera
    if not camera or not settings.aim or settings.strength == 0 then
        currentTarget = nil; targetPart = nil; return
    end
    if currentTarget then
        local part = eligibleTarget(currentTarget, camera)
        if part then targetPart = part; return end
    end
    currentTarget = nil
    targetPart = nil
    local best = math.huge
    for _, other in Players:GetPlayers() do
        local part, distance = eligibleTarget(other, camera)
        if part and distance < best then
            best = distance
            currentTarget = other
            targetPart = part
        end
    end
end
local function flyInput(camera: Camera, humanoid: Humanoid): Vector3
    if UIS:GetFocusedTextBox() or GuiService.MenuIsOpen then return Vector3.zero end
    local look = camera.CFrame.LookVector
    local flatLook = Vector3.new(look.X, 0, look.Z)
    if flatLook.Magnitude < 0.01 then
        flatLook = Vector3.new(-math.sin(math.atan2(-look.X, -look.Z)), 0, -math.cos(math.atan2(-look.X, -look.Z)))
    end
    flatLook = flatLook.Unit
    local right = Vector3.new(-flatLook.Z, 0, flatLook.X)
    -- MoveDirection comes from Roblox's standard touch joystick, keyboard, or gamepad.
    local move = humanoid.MoveDirection
    local forward = move:Dot(flatLook)
    local side = move:Dot(right)
    local result = look * forward + right * side
    if UIS.KeyboardEnabled then
        local x = (if UIS:IsKeyDown(Enum.KeyCode.D) then 1 else 0) - (if UIS:IsKeyDown(Enum.KeyCode.A) then 1 else 0)
        local z = (if UIS:IsKeyDown(Enum.KeyCode.W) then 1 else 0) - (if UIS:IsKeyDown(Enum.KeyCode.S) then 1 else 0)
        -- Keyboard movement stays horizontal; Space/Ctrl controls elevation.
        if x ~= 0 or z ~= 0 then result = right * x + flatLook * z end
        local up = if UIS:IsKeyDown(Enum.KeyCode.Space) then 1 else 0
        local down = if UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl) then 1 else 0
        result += Vector3.new(0, up - down, 0)
    end
    return if result.Magnitude > 1 then result.Unit else result
end
local highlightTimer = 0
local targetTimer = 0
local flightTimer = 0
RunService.Heartbeat:Connect(function(dt)
    highlightTimer += dt
    targetTimer += dt
    flightTimer += dt
    if highlightTimer >= 0.1 then highlightTimer = 0; updateHighlights() end
    if targetTimer >= 0.05 then targetTimer = 0; chooseTarget() end
    if flightTimer >= 0.05 then
        flightTimer = 0
        local _, humanoid = getRig(player)
        local camera = Workspace.CurrentCamera
        if settings.fly and humanoid and camera then remote:FireServer("FlyInput", flyInput(camera, humanoid)) end
    end
end)
RunService:BindToRenderStep("AbilitiesCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
    local camera = Workspace.CurrentCamera
    if not camera then return end
    local inset = GuiService:GetGuiInset()
    local center = camera.ViewportSize / 2 - inset
    ring.Position = UDim2.fromOffset(center.X, center.Y)
    centerDot.Position = UDim2.fromOffset(center.X, center.Y)
    local radius = math.max(1, fovRadius(camera))
    ring.Size = UDim2.fromOffset(radius * 2, radius * 2)
    ring.Visible = settings.aim and settings.ring
    centerDot.Visible = settings.aim
    ringStroke.Color = if targetPart then Color3.fromRGB(255, 207, 110) else C.accent
    local _, _, root = getRig(player)
    if settings.visualize and root then
        local size = settings.hitbox
        hitbox.Size = Vector3.new(size, size, size)
        hitbox.CFrame = root.CFrame * CFrame.new(0, 0, -(2 + size / 2))
        hitbox.Transparency = 0.65
    else hitbox.Transparency = 1 end
    if settings.aim and settings.strength > 0 and currentTarget then
        -- Recheck every rendered frame so loss of LOS/team/FOV releases immediately.
        local part = eligibleTarget(currentTarget, camera)
        if not part then currentTarget = nil; targetPart = nil; return end
        targetPart = part
        local delta = part.Position - camera.CFrame.Position
        if delta.Magnitude < 0.01 then return end
        local desired = CFrame.lookAt(camera.CFrame.Position, part.Position)
        local alpha = if settings.strength >= 100 then 1 else 1 - math.exp(-(settings.strength / 100) * 24 * dt)
        camera.CFrame = camera.CFrame:Lerp(desired, alpha)
    end
end)
script.Destroying:Connect(function()
    RunService:UnbindFromRenderStep("AbilitiesCamera")
    remote:FireServer("Fly", false)
    remote:FireServer("Noclip", false)
    visuals:Destroy()
    gui:Destroy()
end)
```

## Multiplayer verification checklist

This code has not been executed in Roblox Studio here. Verify these behaviors in your own place before publishing:

1. Launch two clients. Aim at an opponent, test all four bones in R6 and R15, and test 0%, 50%, and 100% strength. Move the opponent behind a wall, out of FOV, and onto your team.
2. Toggle highlight options separately. Check names, distance, and health after taking damage; check Visible only behind solid geometry. Test at the player count you intend to support. Selection runs at 20 Hz, overlays at 10 Hz, and only camera steering/preview transforms run per frame. Very large servers may require distance culling before raycasts.
3. Test walking/jumping at 0 and 100. Enable flight and check every keyboard direction, then touch joystick forward/back while tilting the camera. Change flight speed live. Disable flight in midair and confirm gravity and normal character control return.
4. Enable noclip through a wall. Disable it in open space and confirm collisions return. Die and respawn with flight and noclip active; confirm both are off and no constraints remain.
5. Stand in attack range, vary hitbox size, and Strike. Compare visualization to the server's attack box. Try through a wall and against an ally with friendly fire disabled; damage should be rejected. Roblox spatial overlap queries use part bounding boxes, so geometry edges can produce broadphase candidates, which are further filtered by the server.
6. Select a player, teleport, then disconnect the selected player. Confirm the list refreshes and selection resets. Test blocked destinations and floors at different heights.
7. Use Studio Device Emulator for phone/tablet landscape and portrait. Verify menu dragging, scrolling tabs, dropdowns, sliders, the Roblox movement joystick, and the Strike button. Adjust the Strike button's position if your experience has other touch controls there.
8. Check Output for Luau errors and use a published private server to evaluate flight latency. Server-owned flight is authoritative but can feel less responsive on high latency connections; smoothing mitigates it and does not remove network delay.

## Integration notes

The client should be installed only once. The server creates `ReplicatedStorage.PlayerAbilities`; do not create another script with the same remote names. Both scripts assume standard Humanoid characters and Roblox's default camera and movement controllers. Scripted cameras, custom controllers, ragdolls, collision-group systems, seated characters, vehicles, and custom damage services require integration. In your combat framework, replace `h:TakeDamage(CONFIG.Damage)` with your server damage service; preserve the target validation. Query detection honors `CanQuery`, so character body parts intended for combat must remain queryable. Decorative parts configured as raycast blockers also block line of sight.

Aim assist and highlighting are local presentation features; they do not grant a hit. Teleport and noclip intentionally allow powerful gameplay actions, so design level rules accordingly. The server accepts these abilities for every connected player by default because this package implements player-facing mechanics. Server clamps are the hard caps, regardless of a modified client's slider values.

WindUI inspiration reference: https://github.com/Footagesus/WindUI . No WindUI source is bundled or executed; this avoids executor-specific loaders and keeps installation entirely inside Roblox Studio.
