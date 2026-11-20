--[[
    K1RSTEN TOOLKIT
    Creator: 00B_qruel (@k1rsten)
    UI library: WindUI by Footagesus

    Use in your own experience / authorized testing.

    AIM
      Toggle ON = automatic head assistance.
      0% = no assistance; 100% = instant.
      FOV, team, wall, and dead checks.

    MOVEMENT
      0% = captured normal movement.
      100% = configured maximum.
      Original movement restored when disabled/unloaded.

    STUDIO INSTALLATION
      ReplicatedStorage
        WindUI
          Init

    Unload older versions before using this replacement.
]]

-- =====================================================================
-- 01 | SERVICES AND CONFIGURATION
-- =====================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
assert(LocalPlayer, "Run this script on the client.")

local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local CONFIG = {
    Title = "K1RSTEN Toolkit",
    Creator = "00B_qruel (@k1rsten)",

    -- Editable movement limits.
    MaxWalkSpeed = 320,
    MaxJumpPower = 200,

    VisualInterval = 0.10,
    MovementInterval = 0.10,
}

local Settings = {
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

-- Addresses intentionally retained as supplied.
local SOCIALS = {
    { "TikTok", "https://tiktok.com/ranzeku233" },
    { "Instagram", "https://instagram.com/azters.gg" },
    { "Discord", "https://discord.com/ranzekugg" },
    { "Roblox", "https://roblox.com/O0B_qruel" },
    { "Email", "morantek77@gmail.com" },
    { "Telegram", "https://t.me/@konexeon" },
    { "Facebook", "https://facebook.com/aeaelc" },
    {
        "Bluesky",
        "https://bsky.app/profile/ranzekugg.bsky.social",
    },
    { "Tellonym", "https://tellonym.me/0Obqruel/hnest" },
    { "All links", "https://guns.lol/k1rsten_" },
}

-- =====================================================================
-- 02 | REMOVE AN EARLIER INSTANCE OF THIS VERSION
-- =====================================================================

local SESSION_NAME = "K1RSTEN_Toolkit_Session"

local previous = PlayerGui:FindFirstChild(SESSION_NAME)

if previous then
    local unload = previous:FindFirstChild("Unload")

    if unload and unload:IsA("BindableEvent") then
        unload:Fire()
    end

    if previous.Parent then
        previous:Destroy()
    end
end

-- =====================================================================
-- 03 | LOAD WINDUI
-- =====================================================================

local WindUI

if RunService:IsStudio() then
    WindUI = require(
        ReplicatedStorage:WaitForChild("WindUI")
            :WaitForChild("Init")
    )
else
    local ok, result = pcall(function()
        return loadstring(game:HttpGet(
            "https://raw.githubusercontent.com/"
                .. "Footagesus/WindUI/main/dist/main.lua"
        ))()
    end)

    assert(
        ok and result,
        "WindUI could not load. Studio requires a locally installed "
            .. "WindUI module. Loader error: " .. tostring(result)
    )

    WindUI = result
end

-- =====================================================================
-- 04 | STATE AND HELPERS
-- =====================================================================

local alive = true
local target
local movement
local Window

local connections = {}
local records = {}

local renderName =
    "K1RSTEN_" .. HttpService:GenerateGUID(false)

local function create(className, properties, parent)
    local object = Instance.new(className)

    for property, value in pairs(properties) do
        object[property] = value
    end

    object.Parent = parent
    return object
end

local function connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(connections, connection)
    return connection
end

local function notify(title, content)
    if not alive then
        return
    end

    WindUI:Notify({
        Title = title,
        Content = content,
        Duration = 5,
    })
end

local session = create("Folder", {
    Name = SESSION_NAME,
}, PlayerGui)

local unloadEvent = create("BindableEvent", {
    Name = "Unload",
}, session)

local highlightFolder = create("Folder", {
    Name = "K1RSTEN_LocalHighlights",
}, workspace)

local function sameTeam(player)
    return not LocalPlayer.Neutral
        and not player.Neutral
        and LocalPlayer.Team ~= nil
        and LocalPlayer.Team == player.Team
end

local function getParts(player)
    local character = player.Character

    if not character then
        return nil
    end

    local humanoid =
        character:FindFirstChildOfClass("Humanoid")
    local head = character:FindFirstChild("Head")

    if not humanoid or not head or not head:IsA("BasePart") then
        return nil
    end

    return character, humanoid, head
end

-- =====================================================================
-- 05 | CENTERED FOV OVERLAY
-- =====================================================================

local overlay = create("ScreenGui", {
    Name = "K1RSTEN_Overlay",
    ResetOnSpawn = false,
    DisplayOrder = 10,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, PlayerGui)

-- Keep the drawing origin aligned with viewport projection.
overlay.IgnoreGuiInset = true
overlay.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
overlay.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
overlay.ClipToDeviceSafeArea = false

local circle = create("Frame", {
    Name = "FOV",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(
        Settings.FOV * 2,
        Settings.FOV * 2
    ),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Active = false,
    Visible = false,
}, overlay)

create("UICorner", {
    CornerRadius = UDim.new(1, 0),
}, circle)

local circleStroke = create("UIStroke", {
    Thickness = 1.5,
    Transparency = 0.15,
    Color = Color3.fromRGB(190, 175, 255),
}, circle)

local function getAimCenter(camera)
    return camera.ViewportSize * 0.5
end

-- =====================================================================
-- 06 | CONTACT TEXT / CLIPBOARD FALLBACK
-- =====================================================================

local contactPanel = create("Frame", {
    Name = "ContactPanel",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.new(0.88, 0, 0, 188),
    BackgroundColor3 = Color3.fromRGB(24, 24, 32),
    BorderSizePixel = 0,
    Visible = false,
    Active = true,
    ZIndex = 50,
}, overlay)

create("UISizeConstraint", {
    MaxSize = Vector2.new(460, 188),
}, contactPanel)

create("UICorner", {
    CornerRadius = UDim.new(0, 12),
}, contactPanel)

local contactTitle = create("TextLabel", {
    Position = UDim2.fromOffset(16, 12),
    Size = UDim2.new(1, -66, 0, 26),
    BackgroundTransparency = 1,
    Font = Enum.Font.GothamBold,
    TextSize = 17,
    TextColor3 = Color3.new(1, 1, 1),
    TextXAlignment = Enum.TextXAlignment.Left,
    Text = "Contact",
    ZIndex = 51,
}, contactPanel)

create("TextLabel", {
    Position = UDim2.fromOffset(16, 46),
    Size = UDim2.new(1, -32, 0, 34),
    BackgroundTransparency = 1,
    Font = Enum.Font.Gotham,
    TextSize = 13,
    TextColor3 = Color3.fromRGB(195, 195, 210),
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    Text = "Select the address below to copy it manually.",
    ZIndex = 51,
}, contactPanel)

local contactText = create("TextBox", {
    Position = UDim2.fromOffset(16, 92),
    Size = UDim2.new(1, -32, 0, 70),
    BackgroundColor3 = Color3.fromRGB(36, 36, 48),
    BorderSizePixel = 0,
    Font = Enum.Font.Gotham,
    TextSize = 14,
    TextColor3 = Color3.new(1, 1, 1),
    ClearTextOnFocus = false,
    MultiLine = true,
    TextWrapped = true,
    Text = "",
    ZIndex = 51,
}, contactPanel)

create("UICorner", {
    CornerRadius = UDim.new(0, 8),
}, contactText)

local contactClose = create("TextButton", {
    Position = UDim2.new(1, -46, 0, 10),
    Size = UDim2.fromOffset(34, 30),
    BackgroundTransparency = 1,
    Font = Enum.Font.GothamBold,
    TextSize = 20,
    TextColor3 = Color3.new(1, 1, 1),
    Text = "×",
    ZIndex = 51,
}, contactPanel)

connect(contactClose.Activated, function()
    contactText:ReleaseFocus()
    contactPanel.Visible = false
end)

local function showContact(title, text)
    -- Clipboard is optional, never required.
    if type(setclipboard) == "function" then
        local copied = pcall(setclipboard, text)

        if copied then
            notify(title, "Copied to clipboard.")
            return
        end
    end

    contactTitle.Text = title
    contactText.Text = text
    contactPanel.Visible = true
end

-- =====================================================================
-- 07 | AUTOMATIC HEAD AIM ASSISTANCE
-- =====================================================================

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function hasLineOfSight(camera, character, head)
    local excluded = { camera, highlightFolder }

    if LocalPlayer.Character then
        table.insert(excluded, LocalPlayer.Character)
    end

    rayParams.FilterDescendantsInstances = excluded

    local origin = camera.CFrame.Position
    local direction = head.Position - origin

    if direction.Magnitude < 0.001 then
        return true
    end

    local hit = workspace:Raycast(origin, direction, rayParams)

    return hit == nil
        or hit.Instance:IsDescendantOf(character)
end

local function getCandidate(player, camera)
    if player == LocalPlayer or player.Parent ~= Players then
        return nil
    end

    if Settings.TeamCheck and sameTeam(player) then
        return nil
    end

    local character, humanoid, head = getParts(player)

    if not character then
        return nil
    end

    if Settings.DeadCheck and humanoid.Health <= 0 then
        return nil
    end

    local point, onScreen =
        camera:WorldToViewportPoint(head.Position)

    if not onScreen or point.Z <= 0 then
        return nil
    end

    local distance = (
        Vector2.new(point.X, point.Y) - getAimCenter(camera)
    ).Magnitude

    if distance > Settings.FOV then
        return nil
    end

    if Settings.WallCheck
        and not hasLineOfSight(camera, character, head) then
        return nil
    end

    return head, distance
end

local function findTarget(camera)
    local bestPlayer
    local bestHead
    local bestDistance = math.huge

    for _, player in ipairs(Players:GetPlayers()) do
        local head, distance = getCandidate(player, camera)

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

    if not Settings.Aim
        or Settings.Strength <= 0
        or not humanoid
        or humanoid.Health <= 0
        or UIS:GetFocusedTextBox() ~= nil
        or contactPanel.Visible then
        target = nil
        return
    end

    local head

    if target then
        head = getCandidate(target, camera)
    end

    if not head then
        target, head = findTarget(camera)
    end

    if not head then
        return
    end

    local position = camera.CFrame.Position

    if (head.Position - position).Magnitude < 0.001 then
        return
    end

    local desired = CFrame.lookAt(position, head.Position)

    if Settings.Strength >= 100 then
        camera.CFrame = desired
    else
        local strength = Settings.Strength / 100
        local rate = 30 * strength * strength
        local alpha = 1 - math.exp(-rate * dt)

        camera.CFrame = camera.CFrame:Lerp(desired, alpha)
    end
end

-- =====================================================================
-- 08 | PLAYER HIGHLIGHTS, NAMES, DISTANCE, HEALTH
-- =====================================================================

local function removeVisual(player)
    local record = records[player]

    if not record then
        return
    end

    record.Highlight:Destroy()
    record.Billboard:Destroy()
    records[player] = nil
end

local function makeVisual(player, character, head)
    removeVisual(player)

    local highlight = create("Highlight", {
        Name = "PlayerHighlight",
        Adornee = character,
        FillTransparency = 0.70,
        OutlineTransparency = 0,
        Enabled = false,
    }, highlightFolder)

    local billboard = create("BillboardGui", {
        Name = "K1RSTEN_PlayerInfo",
        Adornee = head,
        Size = UDim2.fromOffset(220, 64),
        StudsOffsetWorldSpace = Vector3.new(0, 2.7, 0),
        MaxDistance = 10000,
        ResetOnSpawn = false,
        AlwaysOnTop = false,
        Enabled = false,
    }, PlayerGui)

    local label = create("TextLabel", {
        Size = UDim2.new(1, 0, 0, 38),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamMedium,
        TextSize = 13,
        TextColor3 = Color3.new(1, 1, 1),
        TextStrokeTransparency = 0.25,
        Text = "",
        RichText = false,
    }, billboard)

    local healthBackground = create("Frame", {
        Position = UDim2.new(0.15, 0, 0, 44),
        Size = UDim2.new(0.7, 0, 0, 7),
        BackgroundColor3 = Color3.fromRGB(30, 30, 36),
        BorderSizePixel = 0,
        ClipsDescendants = true,
    }, billboard)

    create("UICorner", {
        CornerRadius = UDim.new(1, 0),
    }, healthBackground)

    local healthFill = create("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.fromRGB(80, 230, 110),
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

    local origin = root and root.Position
        or camera.CFrame.Position

    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then
            continue
        end

        local character, humanoid, head = getParts(player)
        local record = records[player]

        if not character then
            removeVisual(player)
            continue
        end

        local show = Settings.Visuals
            and humanoid.Health > 0
            and not (
                Settings.VisualTeamCheck and sameTeam(player)
            )

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
            or Color3.fromRGB(170, 145, 255)

        record.Highlight.FillColor = color
        record.Highlight.OutlineColor = color
        record.Highlight.DepthMode = Settings.ThroughWalls
            and Enum.HighlightDepthMode.AlwaysOnTop
            or Enum.HighlightDepthMode.Occluded
        record.Highlight.Enabled = true

        record.Billboard.AlwaysOnTop = Settings.ThroughWalls
        record.Billboard.Enabled =
            Settings.Names or Settings.Distance or Settings.Healthbar

        local lines = {}

        if Settings.Names then
            table.insert(lines, string.format(
                "%s (@%s)", player.DisplayName, player.Name
            ))
        end

        if Settings.Distance then
            table.insert(lines, string.format(
                "%.0f studs", (head.Position - origin).Magnitude
            ))
        end

        record.Label.Text = table.concat(lines, "\n")
        record.HealthBackground.Visible = Settings.Healthbar

        local fraction = humanoid.MaxHealth > 0
            and math.clamp(
                humanoid.Health / humanoid.MaxHealth, 0, 1
            ) or 0

        record.HealthFill.Size =
            UDim2.fromScale(fraction, 1)

        record.HealthFill.BackgroundColor3 =
            Color3.fromHSV(fraction / 3, 0.8, 0.95)
    end
end

-- =====================================================================
-- 09 | STRONGER MOVEMENT / RESTORATION
-- =====================================================================

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

    -- WalkSpeed: 0% normal -> 100% configured maximum.
    if Settings.Speed > 0 then
        local maximum = math.max(
            movement.WalkSpeed, CONFIG.MaxWalkSpeed
        )

        humanoid.WalkSpeed = movement.WalkSpeed
            + (maximum - movement.WalkSpeed)
                * (Settings.Speed / 100)

        movement.SpeedApplied = true
    elseif movement.SpeedApplied then
        humanoid.WalkSpeed = movement.WalkSpeed
        movement.SpeedApplied = false
    else
        -- Track normal changes while our override is inactive.
        movement.WalkSpeed = humanoid.WalkSpeed
    end

    -- Jump: convert the original height to equivalent velocity
    -- when the experience normally uses JumpHeight.
    if Settings.Jump > 0 then
        local basePower

        if movement.UseJumpPower then
            basePower = movement.JumpPower
        else
            basePower = math.sqrt(
                2 * math.max(workspace.Gravity, 0)
                    * math.max(movement.JumpHeight, 0)
            )
        end

        local maximum = math.max(
            basePower, CONFIG.MaxJumpPower
        )

        humanoid.UseJumpPower = true
        humanoid.JumpPower = basePower
            + (maximum - basePower) * (Settings.Jump / 100)

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

-- =====================================================================
-- 10 | CLEANUP
-- =====================================================================

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

    -- Avoid mutating the records table during enumeration.
    local playersToRemove = {}

    for player in pairs(records) do
        table.insert(playersToRemove, player)
    end

    for _, player in ipairs(playersToRemove) do
        removeVisual(player)
    end

    overlay:Destroy()
    highlightFolder:Destroy()
    session:Destroy()
end

local function unload()
    if not alive then
        return
    end

    cleanup()

    if Window then
        Window:Destroy()
    end
end

connect(unloadEvent.Event, unload)
connect(overlay.Destroying, cleanup)

connect(Players.PlayerRemoving, function(player)
    if target == player then
        target = nil
    end

    removeVisual(player)
end)

connect(LocalPlayer.CharacterRemoving, function()
    target = nil
    restoreMovement()
end)

-- =====================================================================
-- 11 | WINDUI WINDOW
-- =====================================================================

Window = WindUI:CreateWindow({
    Title = CONFIG.Title,
    Icon = "settings",
    Size = UDim2.fromOffset(580, 480),
    Theme = "Dark",

    OpenButton = {
        Title = "K1RSTEN",
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

local AboutTab = Window:Tab({
    Title = "About",
    Icon = "info",
})

local SettingsTab = Window:Tab({
    Title = "Settings",
    Icon = "settings",
})

local function section(tab, title)
    return tab:Section({ Title = title })
end

local function addToggle(tab, title, key, resetTarget)
    return tab:Toggle({
        Title = title,
        Value = Settings[key],

        Callback = function(value)
            Settings[key] = value == true

            if resetTarget then
                target = nil
            end
        end,
    })
end

local function addSlider(tab, title, key, minimum, maximum)
    return tab:Slider({
        Title = title,
        Step = 1,

        Value = {
            Min = minimum,
            Max = maximum,
            Default = Settings[key],
        },

        Callback = function(value)
            local number = tonumber(value)

            if number then
                Settings[key] = math.clamp(
                    number, minimum, maximum
                )
            end
        end,
    })
end

-- =====================================================================
-- 12 | AIM MENU
-- =====================================================================

section(AimTab, "Automatic head assistance")

addToggle(
    AimTab,
    "Enable aim — automatic / mobile",
    "Aim",
    true
)

addSlider(
    AimTab,
    "Strength: 0% normal / 100% instant",
    "Strength",
    0,
    100
)

section(AimTab, "Field of view")

addSlider(
    AimTab,
    "FOV radius — pixels",
    "FOV",
    10,
    600
)

addToggle(AimTab, "Show FOV circle", "ShowFOV", false)

section(AimTab, "Target checks")

addToggle(AimTab, "Team check", "TeamCheck", true)
addToggle(AimTab, "Wall check", "WallCheck", true)
addToggle(AimTab, "Dead check", "DeadCheck", true)

-- =====================================================================
-- 13 | VISUALS MENU
-- =====================================================================

section(VisualTab, "Player visuals")

addToggle(
    VisualTab,
    "Enable highlights and information",
    "Visuals",
    false
)

addToggle(VisualTab, "Names", "Names", false)
addToggle(VisualTab, "Distance", "Distance", false)
addToggle(VisualTab, "Health bars", "Healthbar", false)

section(VisualTab, "Visibility")

addToggle(
    VisualTab,
    "Hide teammates",
    "VisualTeamCheck",
    false
)

addToggle(
    VisualTab,
    "Show through walls",
    "ThroughWalls",
    false
)

-- =====================================================================
-- 14 | MOVEMENT MENU
-- =====================================================================

section(MovementTab, "Walk speed")

local speedSlider = addSlider(
    MovementTab,
    "Speed: 0% normal / 100% up to "
        .. CONFIG.MaxWalkSpeed,
    "Speed",
    0,
    100
)

section(MovementTab, "Jump power")

local jumpSlider = addSlider(
    MovementTab,
    "Jump: 0% normal / 100% up to "
        .. CONFIG.MaxJumpPower,
    "Jump",
    0,
    100
)

MovementTab:Button({
    Title = "Restore normal movement",
    Desc = "Resets both movement sliders to 0%.",

    Callback = function()
        Settings.Speed = 0
        Settings.Jump = 0

        -- Keep the visible sliders synchronized where supported.
        if speedSlider and type(speedSlider.Set) == "function" then
            pcall(function()
                speedSlider:Set(0)
            end)
        end

        if jumpSlider and type(jumpSlider.Set) == "function" then
            pcall(function()
                jumpSlider:Set(0)
            end)
        end

        restoreMovement()
        notify("Movement", "Normal movement restored.")
    end,
})

-- =====================================================================
-- 15 | ABOUT THE CREATOR AND SOCIALS
-- =====================================================================

section(AboutTab, "About the creator")

AboutTab:Button({
    Title = CONFIG.Creator,
    Desc = "Creator credit — tap to copy or select.",

    Callback = function()
        showContact("Creator", CONFIG.Creator)
    end,
})

section(AboutTab, "Social media and contact")

for _, social in ipairs(SOCIALS) do
    local name = social[1]
    local address = social[2]

    AboutTab:Button({
        Title = name,
        Desc = address,

        Callback = function()
            showContact(name, address)
        end,
    })
end

AboutTab:Button({
    Title = "Copy all creator contacts",
    Desc = "Copies all contacts or displays selectable text.",

    Callback = function()
        local lines = { CONFIG.Creator, "" }

        for _, social in ipairs(SOCIALS) do
            table.insert(
                lines,
                social[1] .. ": " .. social[2]
            )
        end

        showContact("All creator contacts", table.concat(lines, "\n"))
    end,
})

section(AboutTab, "Library credit")

AboutTab:Button({
    Title = "WindUI — Footagesus",
    Desc = "UI library credit and repository.",

    Callback = function()
        showContact(
            "WindUI",
            "https://github.com/Footagesus/WindUI"
        )
    end,
})

-- =====================================================================
-- 16 | SETTINGS MENU
-- =====================================================================

section(SettingsTab, "Session")

SettingsTab:Button({
    Title = "Release current target",
    Desc = "The next eligible target is selected automatically.",

    Callback = function()
        target = nil
    end,
})

SettingsTab:Button({
    Title = "Unload toolkit",
    Desc = "Restores movement and removes toolkit effects.",

    Callback = unload,
})

if typeof(WindUI.ScreenGui) == "Instance" then
    connect(WindUI.ScreenGui.Destroying, cleanup)
end

-- =====================================================================
-- 17 | RUNTIME
-- =====================================================================

local visualTimer = 0
local movementTimer = 0

RunService:BindToRenderStep(
    renderName,
    Enum.RenderPriority.Camera.Value + 1,
    function(dt)
        if not alive then
            return
        end

        local camera = workspace.CurrentCamera

        if camera then
            -- Exact same center used by target selection.
            local center = getAimCenter(camera)

            circle.Position =
                UDim2.fromOffset(center.X, center.Y)

            circle.Size = UDim2.fromOffset(
                Settings.FOV * 2,
                Settings.FOV * 2
            )

            circle.Visible =
                Settings.Aim and Settings.ShowFOV

            updateAim(camera, dt)

            circleStroke.Color = target
                and Color3.fromRGB(100, 255, 150)
                or Color3.fromRGB(190, 175, 255)

            visualTimer += dt

            if visualTimer >= CONFIG.VisualInterval then
                visualTimer = 0
                updateVisuals(camera)
            end
        else
            target = nil
            circle.Visible = false
        end

        movementTimer += dt

        if movementTimer >= CONFIG.MovementInterval then
            movementTimer = 0
            updateMovement()
        end
    end
)

notify(
    CONFIG.Title,
    "By " .. CONFIG.Creator
        .. "\nOpen Aim to enable automatic assistance."
)
