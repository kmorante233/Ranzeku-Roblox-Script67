--[[
    WindUI Player Toolkit

    Aim:
      Toggle ON = automatic head assistance.
      No right-click, keyboard key, or touch hold required.
      0% strength = no assistance.
      100% strength = instant lock.

    Movement:
      0% = original movement.
      100% = double original WalkSpeed / JumpPower.

    Intended for your own experience / authorized testing.
    Unload the previous version before running this replacement.
]]

-- Services -------------------------------------------------------------------

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
assert(LocalPlayer, "This script must run on the client.")

local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- WindUI ---------------------------------------------------------------------

local WindUI

if RunService:IsStudio() then
    -- Studio installation:
    -- ReplicatedStorage
    --   WindUI
    --     Init
    WindUI = require(
        ReplicatedStorage:WaitForChild("WindUI"):WaitForChild("Init")
    )
else
    WindUI = loadstring(game:HttpGet(
        "https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"
    ))()
end

-- Settings -------------------------------------------------------------------

local S = {
    Aim = false,
    Strength = 35,
    FOV = 150,
    ShowFOV = true,
    TeamCheck = true,
    WallCheck = true,
    DeadCheck = true,

    Visuals = false,
    Names = true,
    Distance = true,
    Healthbar = true,
    VisualTeamCheck = false,
    ThroughWalls = false,

    Speed = 0,
    Jump = 0,
}

local alive = true
local target = nil
local movement = nil

local connections = {}
local records = {}

local renderName =
    "WindUI_PlayerToolkit_" .. HttpService:GenerateGUID(false)

local function connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(connections, connection)
    return connection
end

local function create(className, properties, parent)
    local object = Instance.new(className)

    for key, value in pairs(properties) do
        object[key] = value
    end

    object.Parent = parent
    return object
end

-- FOV overlay ----------------------------------------------------------------
-- Parent directly to PlayerGui.
-- Set inset properties explicitly in a predictable order.

local overlay = create("ScreenGui", {
    Name = "WindUI_AimOverlay",
    ResetOnSpawn = false,
    DisplayOrder = 10,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, PlayerGui)

overlay.IgnoreGuiInset = true
overlay.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
overlay.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None

local circle = create("Frame", {
    Name = "FOVCircle",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(S.FOV * 2, S.FOV * 2),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Active = false,
    Visible = false,
}, overlay)

create("UICorner", {
    CornerRadius = UDim.new(1, 0),
}, circle)

local circleStroke = create("UIStroke", {
    Color = Color3.fromRGB(220, 225, 255),
    Thickness = 1.5,
    Transparency = 0.2,
}, circle)

-- Visual containers ----------------------------------------------------------

local visualFolder = create("Folder", {
    Name = "WindUI_PlayerVisuals",
}, PlayerGui)

local highlightFolder = create("Folder", {
    Name = "WindUI_LocalHighlights",
}, workspace)

-- Character helpers ----------------------------------------------------------

local function sameTeam(player)
    return not LocalPlayer.Neutral
        and not player.Neutral
        and LocalPlayer.Team ~= nil
        and LocalPlayer.Team == player.Team
end

local function getCharacterParts(player)
    local character = player.Character

    if not character then
        return nil
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local head = character:FindFirstChild("Head")

    if not humanoid or not head or not head:IsA("BasePart") then
        return nil
    end

    return character, humanoid, head
end

-- Aim assistance -------------------------------------------------------------

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
raycastParams.IgnoreWater = true

local function visibleFromCamera(camera, character, head)
    local excluded = { camera, highlightFolder }

    if LocalPlayer.Character then
        table.insert(excluded, LocalPlayer.Character)
    end

    raycastParams.FilterDescendantsInstances = excluded

    local origin = camera.CFrame.Position
    local direction = head.Position - origin

    if direction.Magnitude <= 0.001 then
        return true
    end

    local result = workspace:Raycast(
        origin,
        direction,
        raycastParams
    )

    return result == nil
        or result.Instance:IsDescendantOf(character)
end

local function aimCandidate(player, camera)
    if player == LocalPlayer or player.Parent ~= Players then
        return nil
    end

    if S.TeamCheck and sameTeam(player) then
        return nil
    end

    local character, humanoid, head = getCharacterParts(player)

    if not character then
        return nil
    end

    if S.DeadCheck and humanoid.Health <= 0 then
        return nil
    end

    local projected, onScreen =
        camera:WorldToViewportPoint(head.Position)

    if not onScreen or projected.Z <= 0 then
        return nil
    end

    -- Same center and coordinate space as the FOV overlay.
    local center = camera.ViewportSize * 0.5
    local screenPosition = Vector2.new(projected.X, projected.Y)
    local distance = (screenPosition - center).Magnitude

    if distance > S.FOV then
        return nil
    end

    if S.WallCheck
        and not visibleFromCamera(camera, character, head) then
        return nil
    end

    return head, distance
end

local function findTarget(camera)
    local bestPlayer = nil
    local bestHead = nil
    local bestDistance = math.huge

    for _, player in ipairs(Players:GetPlayers()) do
        local head, distance = aimCandidate(player, camera)

        if head and distance < bestDistance then
            bestPlayer = player
            bestHead = head
            bestDistance = distance
        end
    end

    return bestPlayer, bestHead
end

local function updateAim(camera, dt)
    local character = LocalPlayer.Character
    local humanoid = character
        and character:FindFirstChildOfClass("Humanoid")

    -- Automatic activation: no input button checks.
    local aiming = S.Aim
        and S.Strength > 0
        and humanoid ~= nil
        and humanoid.Health > 0
        and UserInputService:GetFocusedTextBox() == nil

    if not aiming then
        target = nil
        return
    end

    local head

    -- Retain the current target while it passes all checks.
    if target then
        head = aimCandidate(target, camera)
    end

    if not head then
        target, head = findTarget(camera)
    end

    if not head then
        return
    end

    local position = camera.CFrame.Position
    local direction = head.Position - position

    if direction.Magnitude <= 0.001 then
        return
    end

    local desired = CFrame.lookAt(position, head.Position)

    if S.Strength >= 100 then
        camera.CFrame = desired
    else
        -- Smooth, frame-rate-independent assistance.
        -- Approaches zero continuously as strength approaches zero.
        local strength = S.Strength / 100
        local rate = 30 * strength * strength
        local alpha = 1 - math.exp(-rate * dt)

        camera.CFrame = camera.CFrame:Lerp(desired, alpha)
    end
end

-- Player visuals -------------------------------------------------------------

local function removeVisual(player)
    local record = records[player]

    if record then
        record.Highlight:Destroy()
        record.Billboard:Destroy()
        records[player] = nil
    end
end

local function makeVisual(player, character, head)
    removeVisual(player)

    local highlight = create("Highlight", {
        Name = "PlayerHighlight",
        Adornee = character,
        FillTransparency = 0.7,
        OutlineTransparency = 0,
        Enabled = false,
    }, highlightFolder)

    local billboard = create("BillboardGui", {
        Name = "PlayerInfo",
        Adornee = head,
        Size = UDim2.fromOffset(210, 58),
        StudsOffsetWorldSpace = Vector3.new(0, 2.5, 0),
        MaxDistance = 10000,
        AlwaysOnTop = false,
        Enabled = false,
        ResetOnSpawn = false,
    }, PlayerGui)

    local label = create("TextLabel", {
        Name = "Info",
        Size = UDim2.new(1, 0, 0, 38),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamMedium,
        TextSize = 13,
        TextColor3 = Color3.new(1, 1, 1),
        TextStrokeTransparency = 0.3,
        Text = "",
        RichText = false,
    }, billboard)

    local healthBackground = create("Frame", {
        Name = "HealthBackground",
        Position = UDim2.new(0.15, 0, 0, 43),
        Size = UDim2.new(0.7, 0, 0, 6),
        BackgroundColor3 = Color3.fromRGB(30, 30, 35),
        BorderSizePixel = 0,
        ClipsDescendants = true,
    }, billboard)

    create("UICorner", {
        CornerRadius = UDim.new(1, 0),
    }, healthBackground)

    local healthFill = create("Frame", {
        Name = "HealthFill",
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.fromRGB(70, 220, 100),
        BorderSizePixel = 0,
    }, healthBackground)

    create("UICorner", {
        CornerRadius = UDim.new(1, 0),
    }, healthFill)

    local record = {
        Character = character,
        Head = head,
        Highlight = highlight,
        Billboard = billboard,
        Label = label,
        HealthBackground = healthBackground,
        HealthFill = healthFill,
    }

    records[player] = record
    return record
end

local function updateVisuals(camera)
    local localCharacter = LocalPlayer.Character
    local root = localCharacter
        and localCharacter:FindFirstChild("HumanoidRootPart")

    local origin = root and root.Position or camera.CFrame.Position

    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then
            continue
        end

        local character, humanoid, head = getCharacterParts(player)
        local record = records[player]

        if not character then
            removeVisual(player)
            continue
        end

        local show = S.Visuals
            and humanoid.Health > 0
            and not (S.VisualTeamCheck and sameTeam(player))

        if not show then
            if record then
                record.Highlight.Enabled = false
                record.Billboard.Enabled = false
            end

            continue
        end

        if not record
            or record.Character ~= character
            or record.Head ~= head then
            record = makeVisual(player, character, head)
        end

        local color = player.Team and player.TeamColor.Color
            or Color3.fromRGB(120, 170, 255)

        record.Highlight.FillColor = color
        record.Highlight.OutlineColor = color

        record.Highlight.DepthMode = S.ThroughWalls
            and Enum.HighlightDepthMode.AlwaysOnTop
            or Enum.HighlightDepthMode.Occluded

        record.Highlight.Enabled = true

        record.Billboard.AlwaysOnTop = S.ThroughWalls
        record.Billboard.Enabled =
            S.Names or S.Distance or S.Healthbar

        local lines = {}

        if S.Names then
            table.insert(lines, string.format(
                "%s (@%s)",
                player.DisplayName,
                player.Name
            ))
        end

        if S.Distance then
            table.insert(lines, string.format(
                "%.0f studs",
                (head.Position - origin).Magnitude
            ))
        end

        record.Label.Text = table.concat(lines, "\n")
        record.HealthBackground.Visible = S.Healthbar

        local fraction = 0

        if humanoid.MaxHealth > 0 then
            fraction = math.clamp(
                humanoid.Health / humanoid.MaxHealth,
                0,
                1
            )
        end

        record.HealthFill.Size = UDim2.fromScale(fraction, 1)
        record.HealthFill.BackgroundColor3 =
            Color3.fromHSV(fraction / 3, 0.8, 0.95)
    end
end

connect(Players.PlayerRemoving, function(player)
    if target == player then
        target = nil
    end

    removeVisual(player)
end)

-- Movement -------------------------------------------------------------------

local function restoreMovement()
    if not movement then
        return
    end

    local humanoid = movement.Humanoid

    if humanoid.Parent then
        if movement.SpeedApplied then
            humanoid.WalkSpeed = movement.WalkSpeed
        end

        if movement.JumpApplied then
            humanoid.JumpPower = movement.JumpPower
            humanoid.JumpHeight = movement.JumpHeight
            humanoid.UseJumpPower = movement.UseJumpPower
        end
    end

    movement = nil
end

local function updateMovement()
    local character = LocalPlayer.Character
    local humanoid = character
        and character:FindFirstChildOfClass("Humanoid")

    if not humanoid or humanoid.Health <= 0 then
        restoreMovement()
        return
    end

    if not movement or movement.Humanoid ~= humanoid then
        restoreMovement()

        movement = {
            Humanoid = humanoid,
            WalkSpeed = humanoid.WalkSpeed,
            JumpPower = humanoid.JumpPower,
            JumpHeight = humanoid.JumpHeight,
            UseJumpPower = humanoid.UseJumpPower,
            SpeedApplied = false,
            JumpApplied = false,
        }
    end

    if S.Speed > 0 then
        humanoid.WalkSpeed =
            movement.WalkSpeed * (1 + S.Speed / 100)

        movement.SpeedApplied = true
    elseif movement.SpeedApplied then
        humanoid.WalkSpeed = movement.WalkSpeed
        movement.SpeedApplied = false
    else
        movement.WalkSpeed = humanoid.WalkSpeed
    end

    if S.Jump > 0 then
        local multiplier = 1 + S.Jump / 100

        -- Preserve the experience's original jump mode.
        if movement.UseJumpPower then
            humanoid.JumpPower =
                movement.JumpPower * multiplier
        else
            -- Equivalent height increase for a jump-power multiplier.
            humanoid.JumpHeight =
                movement.JumpHeight * multiplier * multiplier
        end

        movement.JumpApplied = true
    elseif movement.JumpApplied then
        humanoid.JumpPower = movement.JumpPower
        humanoid.JumpHeight = movement.JumpHeight
        humanoid.UseJumpPower = movement.UseJumpPower

        movement.JumpApplied = false
    else
        movement.JumpPower = humanoid.JumpPower
        movement.JumpHeight = humanoid.JumpHeight
        movement.UseJumpPower = humanoid.UseJumpPower
    end
end

connect(LocalPlayer.CharacterRemoving, function()
    target = nil
    restoreMovement()
end)

-- WindUI menu ----------------------------------------------------------------

local Window = WindUI:CreateWindow({
    Title = "Player Toolkit",
    Icon = "settings",
    Size = UDim2.fromOffset(560, 460),
    Theme = "Dark",

    -- Touch-accessible reopen button: no keyboard required.
    OpenButton = {
        Title = "Open Toolkit",
        Enabled = true,
        Draggable = true,
        OnlyMobile = false,
        CornerRadius = UDim.new(1, 0),
    },
})

local AimTab = Window:Tab({
    Title = "Aim",
    Icon = "crosshair",
})

local VisualTab = Window:Tab({
    Title = "Visuals",
    Icon = "eye",
})

local MovementTab = Window:Tab({
    Title = "Movement",
    Icon = "footprints",
})

local SettingsTab = Window:Tab({
    Title = "Settings",
    Icon = "settings",
})

local function toggle(tab, title, key, resetTarget)
    return tab:Toggle({
        Title = title,
        Value = S[key],

        Callback = function(value)
            S[key] = value

            if resetTarget then
                target = nil
            end
        end,
    })
end

local function slider(tab, title, key, minimum, maximum)
    return tab:Slider({
        Title = title,
        Step = 1,

        Value = {
            Min = minimum,
            Max = maximum,
            Default = S[key],
        },

        Callback = function(value)
            local number = tonumber(value)

            if number then
                S[key] = math.clamp(number, minimum, maximum)
            end
        end,
    })
end

toggle(
    AimTab,
    "Enable aim assistance - automatic",
    "Aim",
    true
)

slider(
    AimTab,
    "Aim strength: 0% normal / 100% instant",
    "Strength",
    0,
    100
)

slider(
    AimTab,
    "FOV circle radius",
    "FOV",
    10,
    600
)

toggle(AimTab, "Show FOV circle", "ShowFOV", false)
toggle(AimTab, "Team check", "TeamCheck", true)
toggle(AimTab, "Wall check", "WallCheck", true)
toggle(AimTab, "Dead check", "DeadCheck", true)

toggle(
    VisualTab,
    "Enable player highlights / visuals",
    "Visuals",
    false
)

toggle(VisualTab, "Show names", "Names", false)
toggle(VisualTab, "Show distance", "Distance", false)
toggle(VisualTab, "Show health bars", "Healthbar", false)

toggle(
    VisualTab,
    "Hide teammates",
    "VisualTeamCheck",
    false
)

toggle(
    VisualTab,
    "Show through walls",
    "ThroughWalls",
    false
)

slider(
    MovementTab,
    "WalkSpeed: 0% normal / 100% double",
    "Speed",
    0,
    100
)

slider(
    MovementTab,
    "Jump boost: 0% normal / 100% double power",
    "Jump",
    0,
    100
)

-- Cleanup --------------------------------------------------------------------

local function cleanup()
    if not alive then
        return
    end

    alive = false
    target = nil

    RunService:UnbindFromRenderStep(renderName)

    for _, connection in ipairs(connections) do
        connection:Disconnect()
    end

    table.clear(connections)

    restoreMovement()

    for player in pairs(records) do
        removeVisual(player)
    end

    overlay:Destroy()
    visualFolder:Destroy()
    highlightFolder:Destroy()
end

SettingsTab:Button({
    Title = "Unload and restore movement",

    Callback = function()
        cleanup()
        Window:Destroy()
    end,
})

if typeof(WindUI.ScreenGui) == "Instance" then
    connect(WindUI.ScreenGui.Destroying, cleanup)
end

connect(overlay.Destroying, cleanup)

-- Runtime --------------------------------------------------------------------

local updateTimer = 0

RunService:BindToRenderStep(
    renderName,
    Enum.RenderPriority.Camera.Value + 1,
    function(dt)
        if not alive then
            return
        end

        local camera = workspace.CurrentCamera

        if not camera then
            return
        end

        -- Explicitly use the exact same center as aimCandidate().
        -- DeviceSafeInsets keeps the overlay origin aligned with
        -- WorldToViewportPoint(), including on notched phones.
        local center = camera.ViewportSize * 0.5

        circle.Position = UDim2.fromOffset(center.X, center.Y)
        circle.Size = UDim2.fromOffset(S.FOV * 2, S.FOV * 2)
        circle.Visible = S.Aim and S.ShowFOV

        updateAim(camera, dt)

        circleStroke.Color = target
            and Color3.fromRGB(100, 255, 150)
            or Color3.fromRGB(220, 225, 255)

        updateTimer += dt

        if updateTimer >= 0.1 then
            updateTimer = 0

            updateVisuals(camera)
            updateMovement()
        end
    end
)
