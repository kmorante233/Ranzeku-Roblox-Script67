-- WindUI: aim assistance, player visuals, and movement controls.
-- Client-side; intended for your own experience / authorized testing.
-- Right-click: aim | RightShift: toggle menu
-- Use "Unload" to disconnect everything and restore movement.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
assert(LocalPlayer, "Run this on the client.")

-- For a Studio-compatible WindUI installation, replace this loader
-- with your local ModuleScript require.
local WindUI = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"
))()

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
local connections = {}
local records = {}
local movement = nil

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

local playerGui = LocalPlayer:WaitForChild("PlayerGui")

local visualFolder = create("Folder", {
    Name = "WindUI_PlayerVisuals",
}, playerGui)

local highlightFolder = create("Folder", {
    Name = "WindUI_LocalHighlights",
}, workspace)

local overlay = create("ScreenGui", {
    Name = "WindUI_AimOverlay",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    ScreenInsets = Enum.ScreenInsets.None,
    DisplayOrder = 10,
}, visualFolder)

local circle = create("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Size = UDim2.fromOffset(S.FOV * 2, S.FOV * 2),
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

local function sameTeam(player)
    -- Neutral players are not automatically teammates.
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

local function visibleFromCamera(camera, character, head)
    local excluded = { camera }
    if LocalPlayer.Character then
        table.insert(excluded, LocalPlayer.Character)
    end

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = excluded
    params.IgnoreWater = true

    local origin = camera.CFrame.Position
    local result = workspace:Raycast(
        origin,
        head.Position - origin,
        params
    )

    return result == nil or result.Instance:IsDescendantOf(character)
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

    local center = camera.ViewportSize / 2
    local distance = (
        Vector2.new(projected.X, projected.Y) - center
    ).Magnitude

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
    }, visualFolder)

    local label = create("TextLabel", {
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
                "%s (@%s)", player.DisplayName, player.Name
            ))
        end

        if S.Distance then
            local root = LocalPlayer.Character
                and LocalPlayer.Character:FindFirstChild(
                    "HumanoidRootPart"
                )

            local origin = root and root.Position
                or camera.CFrame.Position

            table.insert(lines, string.format(
                "%.0f studs", (head.Position - origin).Magnitude
            ))
        end

        record.Label.Text = table.concat(lines, "\n")
        record.HealthBackground.Visible = S.Healthbar

        local fraction = humanoid.MaxHealth > 0
            and math.clamp(
                humanoid.Health / humanoid.MaxHealth, 0, 1
            ) or 0

        record.HealthFill.Size = UDim2.fromScale(fraction, 1)
        record.HealthFill.BackgroundColor3 =
            Color3.fromHSV(fraction / 3, 0.8, 0.95)
    end
end

connect(Players.PlayerRemoving, removeVisual)

-- Movement -------------------------------------------------------------------

local function restoreMovement()
    if not movement then
        return
    end

    local h = movement.Humanoid

    if h.Parent then
        if movement.SpeedApplied then
            h.WalkSpeed = movement.WalkSpeed
        end

        if movement.JumpApplied then
            h.JumpPower = movement.JumpPower
            h.JumpHeight = movement.JumpHeight
            h.UseJumpPower = movement.UseJumpPower
        end
    end

    movement = nil
end

local function updateMovement()
    local character = LocalPlayer.Character
    local humanoid = character
        and character:FindFirstChildOfClass("Humanoid")

    if not humanoid or humanoid.Health <= 0 then
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
        -- Follow normal game changes while the override is off.
        movement.WalkSpeed = humanoid.WalkSpeed
    end

    if S.Jump > 0 then
        humanoid.UseJumpPower = true
        humanoid.JumpPower =
            movement.JumpPower * (1 + S.Jump / 100)
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

-- WindUI menu ----------------------------------------------------------------

local Window = WindUI:CreateWindow({
    Title = "Player Toolkit",
    Icon = "settings",
    Size = UDim2.fromOffset(600, 500),
    Theme = "Dark",
    ToggleKey = Enum.KeyCode.RightShift,
})

local AimTab = Window:Tab({ Title = "Aim", Icon = "crosshair" })
local VisualTab = Window:Tab({ Title = "Visuals", Icon = "eye" })
local MovementTab = Window:Tab({ Title = "Movement", Icon = "footprints" })
local SettingsTab = Window:Tab({ Title = "Settings", Icon = "settings" })

local function toggle(tab, title, key)
    tab:Toggle({
        Title = title,
        Value = S[key],
        Callback = function(value)
            S[key] = value
            target = nil
        end,
    })
end

local function slider(tab, title, key, minimum, maximum)
    tab:Slider({
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

toggle(AimTab, "Enable aim assistance — hold right-click", "Aim")
slider(AimTab, "Aim strength: 0% normal / 100% instant", "Strength", 0, 100)
slider(AimTab, "FOV radius (pixels)", "FOV", 10, 600)
toggle(AimTab, "Show FOV circle", "ShowFOV")
toggle(AimTab, "Team check", "TeamCheck")
toggle(AimTab, "Wall check", "WallCheck")
toggle(AimTab, "Dead check", "DeadCheck")

toggle(VisualTab, "Enable player highlights / visuals", "Visuals")
toggle(VisualTab, "Show names", "Names")
toggle(VisualTab, "Show distance", "Distance")
toggle(VisualTab, "Show health bars", "Healthbar")
toggle(VisualTab, "Hide teammates", "VisualTeamCheck")
toggle(VisualTab, "Show through walls", "ThroughWalls")

slider(MovementTab, "WalkSpeed boost: 0% normal / 100% double", "Speed", 0, 100)
slider(MovementTab, "JumpPower boost: 0% normal / 100% double", "Jump", 0, 100)

-- Runtime and cleanup --------------------------------------------------------

local renderName =
    "WindUI_PlayerToolkit_" .. HttpService:GenerateGUID(false)

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

    restoreMovement()
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

-- If WindUI itself is destroyed, also remove toolkit effects.
if WindUI.ScreenGui then
    connect(WindUI.ScreenGui.Destroying, cleanup)
end

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

        local center = camera.ViewportSize / 2
        circle.Position = UDim2.fromOffset(center.X, center.Y)
        circle.Size = UDim2.fromOffset(S.FOV * 2, S.FOV * 2)
        circle.Visible = S.Aim and S.ShowFOV

        local localHumanoid = LocalPlayer.Character
            and LocalPlayer.Character:FindFirstChildOfClass(
                "Humanoid"
            )

        local aiming = S.Aim
            and S.Strength > 0
            and localHumanoid ~= nil
            and localHumanoid.Health > 0
            and UIS:GetFocusedTextBox() == nil
            and UIS:IsMouseButtonPressed(
                Enum.UserInputType.MouseButton2
            )

        if aiming then
            local head = target and aimCandidate(target, camera)

            if not head then
                target, head = findTarget(camera)
            end

            if head then
                local offset = head.Position - camera.CFrame.Position

                if offset.Magnitude > 0.001 then
                    local desired = CFrame.lookAt(
                        camera.CFrame.Position,
                        head.Position
                    )

                    if S.Strength >= 100 then
                        camera.CFrame = desired
                    else
                        -- Frame-rate-independent interpolation.
                        local strength = S.Strength / 100
                        local rate = 2 + 28 * strength * strength
                        local alpha = 1 - math.exp(-rate * dt)

                        camera.CFrame =
                            camera.CFrame:Lerp(desired, alpha)
                    end
                end
            end
        else
            target = nil
        end

        circleStroke.Color = target
            and Color3.fromRGB(100, 255, 150)
            or Color3.fromRGB(220, 225, 255)

        -- Update labels, bars, and movement at 10 Hz.
        updateTimer += dt

        if updateTimer >= 0.1 then
            updateTimer = 0
            updateVisuals(camera)
            updateMovement()
        end
    end
)
