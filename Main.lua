--[[
    TARGETING & VISUALS — SMART V2

    Full replacement. Unload the previous version first.
    Use only in an experience you own or have permission to test.

    PRESERVED
      - V1 activation, targeting, filters, visuals, and appearance.
      - Full-screen-centered FOV circles.
      - No bottom-left target/log panel.
      - Menu selection navigation disabled.

    ADDED
      - Independent Smart Aim V2.
      - Event-driven character scan cache.
      - Custom rig / renamed part fallbacks.
      - Manual character scanner with complete paginated hierarchy.
      - Per-player manual component selection.
      - Visual-only hitbox dimensions and outlines.
      - Shared team allowlist and team colors.
      - Draggable mobile V2 control.
      - Validated settings and optional persistent storage.

    IMPORTANT
      - Hitboxes are VISUAL ONLY.
      - No real character sizes, collisions, or weapon hits are changed.
      - V2 takes camera priority while V2 is active.
      - V1 runs when V2 is not active.
      - Custom models need a Humanoid OR numeric Health/MaxHealth
        attributes on their Character Model for live targeting.
      - Arbitrary custom rig semantics cannot be inferred perfectly.
        Use AimRole / AimTargetable attributes or manual selection.

    OPTIONAL CUSTOM RIG ATTRIBUTES
      On BasePart:
        AimTargetable = false     -- exclude component
        AimTargetable = true      -- explicitly identify candidate
        AimRole = "Head"          -- Head / Torso / Root

      On a custom Character Model without a Humanoid:
        Health = 100
        MaxHealth = 100

    Uses the same loader environment as the previous working version.
]]

--==============================================================
-- 01. SERVICES / SESSION
--==============================================================

local Players = game:GetService("Players")
local Teams = game:GetService("Teams")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
assert(LocalPlayer, "Run this on the client.")

local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local Environment = _G

if type(getgenv) == "function" then
    local ok, result = pcall(getgenv)

    if ok and type(result) == "table" then
        Environment = result
    end
end

local SessionKey = "__TargetingSmartV2_" .. tostring(game.PlaceId)
local PreviousSession = Environment[SessionKey]

if type(PreviousSession) == "table"
    and type(PreviousSession.Cleanup) == "function" then

    pcall(PreviousSession.Cleanup)
end

local Session = Environment[SessionKey]

if type(Session) ~= "table" then
    Session = {}
    Environment[SessionKey] = Session
end

Session.Cleanup = nil

-- Same WindUI loader as the previous working script.
local WindUI = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"
))()

--==============================================================
-- 02. CONFIGURATION
--==============================================================

local Config = {
    Version = 2,

    V1 = {
        AimEnabled = false,
        ActivationMode = "Hold",
        ActivationKey = "MouseButton2",
        Strength = 50,
        TargetPart = "Head",
        Priority = "Crosshair",
        StickyTarget = true,

        AimTeamCheck = true,
        WallCheck = true,
        ForceFieldCheck = true,
        MaxDistance = 1500,
        MinimumHealth = 0,
        SpecificTeams = false,

        FOV = 180,
        ShowFOV = true,
        FOVColor = "#DCE1FF",
        FOVThickness = 1.5,

        Highlights = false,
        Names = false,
        HealthBars = false,
        Boxes = false,
        Distances = false,
        HealthNumbers = false,
        VisualTeamCheck = true,
        VisualSpecificTeams = false,
        ThroughWalls = false,

        TeamColors = false,
        VisualColor = "#6E96FF",
        HighlightOpacity = 35,
        TextSize = 13,
        Crosshair = false,
        VisualRefreshRate = 30,
    },

    V2 = {
        Enabled = false,
        KeybindEnabled = true,
        Key = "E",
        ActivationMode = "Hold",
        FloatingToggle = true,

        ShowFOV = true,
        FOV = 180,
        FOVColor = "#66E3FF",
        FOVThickness = 1.5,

        -- 0 = instant; 100 = soft, slower tracking.
        Smoothness = 50,
        TargetPart = "Auto",
        Priority = "Crosshair",
        StickyTarget = true,
        MissingPartFallback = true,

        MaxDistance = 1500,
        MinimumHealth = 0,
        TeamCheck = true,
        WallCheck = true,
        ForceFieldCheck = true,
        SpecificTeams = false,

        Deadzone = 0,
        AcquisitionRate = 20,

        FloatingX = 0.90,
        FloatingY = 0.65,

        -- UserId string -> relative component key.
        ManualTargets = {},
    },

    Hitbox = {
        Enabled = false,
        TargetPart = "Root",

        X = 4,
        Y = 6,
        Z = 3,

        Transparency = 70,
        Fill = true,
        Outlines = true,
        OutlineThickness = 0.04,
        OutlineTransparency = 0,

        TeamCheck = true,
        SpecificTeams = false,
        TeamColors = true,
        ThroughWalls = false,
        Color = "#66E3FF",

        MaxDistance = 1500,
        MaxVisible = 32,
    },

    Shared = {
        -- Tokens: "Team: TeamName" or "Neutral / unassigned".
        SelectedTeams = {},

        -- Team token -> hex color override.
        TeamColors = {},
    },
}

local Limits = {
    ["V1.Strength"] = { 0, 100 },
    ["V1.MaxDistance"] = { 50, 5000 },
    ["V1.MinimumHealth"] = { 0, 500 },
    ["V1.FOV"] = { 20, 800 },
    ["V1.FOVThickness"] = { 1, 5 },
    ["V1.HighlightOpacity"] = { 0, 100 },
    ["V1.TextSize"] = { 10, 22 },
    ["V1.VisualRefreshRate"] = { 10, 60 },

    ["V2.FOV"] = { 20, 800 },
    ["V2.FOVThickness"] = { 1, 5 },
    ["V2.Smoothness"] = { 0, 100 },
    ["V2.MaxDistance"] = { 50, 5000 },
    ["V2.MinimumHealth"] = { 0, 500 },
    ["V2.Deadzone"] = { 0, 20 },
    ["V2.AcquisitionRate"] = { 5, 60 },
    ["V2.FloatingX"] = { 0, 1 },
    ["V2.FloatingY"] = { 0, 1 },

    ["Hitbox.X"] = { 0.2, 30 },
    ["Hitbox.Y"] = { 0.2, 30 },
    ["Hitbox.Z"] = { 0.2, 30 },
    ["Hitbox.Transparency"] = { 0, 100 },
    ["Hitbox.OutlineThickness"] = { 0.01, 0.3 },
    ["Hitbox.OutlineTransparency"] = { 0, 100 },
    ["Hitbox.MaxDistance"] = { 50, 5000 },
    ["Hitbox.MaxVisible"] = { 1, 100 },
}

local Choices = {
    ["V1.ActivationMode"] = { "Hold", "Toggle", "Always" },
    ["V1.ActivationKey"] = {
        "MouseButton2", "MouseButton1", "Q", "E", "LeftAlt",
    },
    ["V1.TargetPart"] = { "Head", "Torso", "Root" },
    ["V1.Priority"] = { "Crosshair", "Distance", "Lowest health" },

    ["V2.ActivationMode"] = { "Hold", "Toggle", "Always" },
    ["V2.TargetPart"] = {
        "Auto", "Head", "Torso", "Root", "Closest visible", "Manual",
    },
    ["V2.Priority"] = { "Crosshair", "Distance", "Lowest health" },

    ["Hitbox.TargetPart"] = {
        "Auto", "Head", "Torso", "Root", "Manual",
    },
}

local function finite(number)
    return type(number) == "number"
        and number == number
        and number ~= math.huge
        and number ~= -math.huge
end

local function validHex(value)
    return type(value) == "string"
        and value:match("^#%x%x%x%x%x%x$") ~= nil
end

local function color(value)
    return Color3.fromHex(value:gsub("#", ""))
end

local function cleanStringArray(value)
    local result = {}
    local seen = {}

    if type(value) ~= "table" then
        return result
    end

    for _, entry in ipairs(value) do
        if type(entry) == "string"
            and #entry <= 300
            and not seen[entry] then

            seen[entry] = true
            table.insert(result, entry)
        end
    end

    return result
end

local function mergeConfiguration(saved)
    if type(saved) ~= "table" then
        return
    end

    for _, group in ipairs({ "V1", "V2", "Hitbox" }) do
        local incoming = saved[group]

        if type(incoming) == "table" then
            for key, default in pairs(Config[group]) do
                local value = incoming[key]
                local path = group .. "." .. key

                if type(default) == "boolean" then
                    if type(value) == "boolean" then
                        Config[group][key] = value
                    end

                elseif type(default) == "number" then
                    if finite(value) then
                        local limit = Limits[path]

                        Config[group][key] = limit
                            and math.clamp(value, limit[1], limit[2])
                            or value
                    end

                elseif type(default) == "string" then
                    if Choices[path] then
                        if table.find(Choices[path], value) then
                            Config[group][key] = value
                        end

                    elseif key:find("Color") then
                        if validHex(value) then
                            Config[group][key] = value
                        end

                    elseif path == "V2.Key" then
                        if type(value) == "string"
                            and Enum.KeyCode[value]
                            and value ~= "Unknown"
                            and value ~= "Escape"
                            and value ~= "RightShift" then

                            Config.V2.Key = value
                        end
                    end
                end
            end
        end
    end

    if type(saved.Shared) == "table" then
        Config.Shared.SelectedTeams =
            cleanStringArray(saved.Shared.SelectedTeams)

        if type(saved.Shared.TeamColors) == "table" then
            for token, hex in pairs(saved.Shared.TeamColors) do
                if type(token) == "string"
                    and #token <= 300
                    and validHex(hex) then

                    Config.Shared.TeamColors[token] = hex
                end
            end
        end
    end

    if type(saved.V2) == "table"
        and type(saved.V2.ManualTargets) == "table" then

        for userId, key in pairs(saved.V2.ManualTargets) do
            if type(userId) == "string"
                and userId:match("^%d+$")
                and type(key) == "string"
                and #key <= 4096 then

                Config.V2.ManualTargets[userId] = key
            end
        end
    end
end

--==============================================================
-- 03. STORAGE
--==============================================================

local SaveFile = string.format(
    "TargetingSmartV2_%s_%s.json",
    tostring(game.PlaceId),
    tostring(LocalPlayer.UserId)
)

local CanReadFile = type(readfile) == "function"
local CanWriteFile = type(writefile) == "function"

local StorageStatus = CanWriteFile
    and "File storage available"
    or "Session-only storage: file APIs unavailable"

local StorageWarning = ""

do
    local json

    if CanReadFile then
        local ok, result = pcall(readfile, SaveFile)

        if ok and type(result) == "string" then
            json = result
        end
    end

    if not json and type(Session.JSON) == "string" then
        json = Session.JSON
    end

    if json then
        local ok, decoded = pcall(function()
            return HttpService:JSONDecode(json)
        end)

        if ok and type(decoded) == "table" then
            mergeConfiguration(decoded)
        else
            StorageWarning = "Invalid saved configuration ignored."
        end
    end
end

local function saveConfiguration()
    local ok, json = pcall(function()
        return HttpService:JSONEncode(Config)
    end)

    if not ok then
        StorageStatus = "Save failed: configuration encoding error"
        return
    end

    Session.JSON = json

    if CanWriteFile then
        local written = pcall(writefile, SaveFile, json)

        StorageStatus = written
            and "Saved to " .. SaveFile
            or "File write failed; settings retained in this session"
    else
        StorageStatus = "Saved in this session only"
    end
end

--==============================================================
-- 04. RUNTIME / CONNECTION OWNERSHIP
--==============================================================

local State = {
    Running = true,
    Focused = true,

    Held1 = false,
    Toggle1 = false,
    Held2 = false,
    Toggle2 = false,
    TouchArmed2 = false,

    Binding = false,
    BindingExpires = 0,

    Target1 = nil,
    Target2 = nil,
    NextAcquire2 = 0,

    VisualElapsed = math.huge,
    StatusElapsed = 0,
    SaveDue = nil,
    Revision = 0,

    ScreenSize = Vector2.zero,
    ProjectionOffset = Vector2.zero,
    LastViewport = Vector2.zero,

    SelectedPlayer = LocalPlayer,
    ScannerPage = 1,
    ScannerRefresh = true,

    ScanWorkers = 0,
    ScanCount = 0,

    VisibleHitboxes = 0,
    ActiveSystem = "Idle",
}

local Connections = {}
local Records = {}
local Visuals = {}
local Hitboxes = {}
local UI = {}

local RenderName =
    "SmartTargetingV2_" .. HttpService:GenerateGUID(false)

local function connect(signal, callback, bucket)
    local connection = signal:Connect(callback)
    table.insert(bucket or Connections, connection)
    return connection
end

local function disconnectAll(bucket)
    for _, connection in ipairs(bucket) do
        connection:Disconnect()
    end

    table.clear(bucket)
end

local function resetActivation()
    State.Held1 = false
    State.Toggle1 = false
    State.Held2 = false
    State.Toggle2 = false
    State.TouchArmed2 = false

    State.Target1 = nil
    State.Target2 = nil
    State.NextAcquire2 = 0
end

local function changed()
    State.Revision += 1
    State.Target1 = nil
    State.Target2 = nil
    State.NextAcquire2 = 0
    State.VisualElapsed = math.huge
    State.ScannerRefresh = true
    State.SaveDue = os.clock() + 0.8
end

local function setConfig(group, key, value)
    if Config[group][key] == value then
        return
    end

    Config[group][key] = value

    if key == "ActivationMode"
        or key == "ActivationKey"
        or key == "Key"
        or key == "KeybindEnabled" then

        resetActivation()

    elseif group == "V1" and key == "AimEnabled" then
        State.Held1 = false
        State.Toggle1 = false

    elseif group == "V2" and key == "Enabled" then
        State.Held2 = false
        State.Toggle2 = false
        State.TouchArmed2 = false
    end

    changed()
end

--==============================================================
-- 05. INSTANCE HELPERS / OVERLAY
--==============================================================

local function make(className, properties, parent)
    local object = Instance.new(className)

    for key, value in pairs(properties) do
        object[key] = value
    end

    object.Parent = parent
    return object
end

local Overlay = make("ScreenGui", {
    Name = "SmartTargetingOverlayV2",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    ScreenInsets = Enum.ScreenInsets.None,
    ClipToDeviceSafeArea = false,
    DisplayOrder = 20,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, PlayerGui)

local Canvas = make("Frame", {
    Name = "Canvas",
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Active = false,
    Selectable = false,
}, Overlay)

local Artifacts = make("Folder", {
    Name = "SmartTargetingClientVisuals",
}, workspace)

local function createCircle(name)
    local frame = make("Frame", {
        Name = name,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Selectable = false,
        Active = false,
        Visible = false,
    }, Canvas)

    make("UICorner", {
        CornerRadius = UDim.new(1, 0),
    }, frame)

    local stroke = make("UIStroke", {
        Thickness = 1.5,
        Transparency = 0.15,
    }, frame)

    return {
        Frame = frame,
        Stroke = stroke,
    }
end

local Circle1 = createCircle("FOV_V1")
local Circle2 = createCircle("FOV_V2")

local Crosshair = make("Frame", {
    Name = "Crosshair",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(0, 0),
    BackgroundTransparency = 1,
    Selectable = false,
    Active = false,
    Visible = false,
}, Canvas)

for _, geometry in ipairs({
    { -8, -1, 5, 2 },
    { 3, -1, 5, 2 },
    { -1, -8, 2, 5 },
    { -1, 3, 2, 5 },
}) do
    make("Frame", {
        Position = UDim2.fromOffset(geometry[1], geometry[2]),
        Size = UDim2.fromOffset(geometry[3], geometry[4]),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        Selectable = false,
        Active = false,
    }, Crosshair)
end

local Floating = make("TextButton", {
    Name = "FloatingV2",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(
        Config.V2.FloatingX,
        Config.V2.FloatingY
    ),
    Size = UDim2.fromOffset(112, 46),
    BackgroundColor3 = Color3.fromRGB(30, 35, 48),
    TextColor3 = Color3.new(1, 1, 1),
    Font = Enum.Font.GothamBold,
    TextSize = 14,
    Text = "V2 OFF",
    AutoButtonColor = false,
    Selectable = false,
    Active = true,
    ZIndex = 30,
    Visible = Config.V2.FloatingToggle,
}, Canvas)

make("UICorner", {
    CornerRadius = UDim.new(0, 14),
}, Floating)

make("UIStroke", {
    Color = Color3.fromRGB(102, 227, 255),
    Thickness = 1.2,
    Transparency = 0.15,
}, Floating)

-- No bottom-left status panel is created.

--==============================================================
-- 06. SCREEN COORDINATES / VISIBILITY
--==============================================================

local RayParameters = RaycastParams.new()
RayParameters.FilterType = Enum.RaycastFilterType.Exclude
RayParameters.IgnoreWater = true

local function updateScreenGeometry(camera)
    local size = Canvas.AbsoluteSize
    local viewport = camera.ViewportSize

    if size ~= State.ScreenSize
        or viewport ~= State.LastViewport then

        State.ScreenSize = size
        State.LastViewport = viewport

        local deviceArea = GuiService:GetInsetArea(
            Enum.ScreenInsets.DeviceSafeInsets
        )

        local fullArea = GuiService:GetInsetArea(
            Enum.ScreenInsets.None
        )

        State.ProjectionOffset = deviceArea.Min - fullArea.Min
    end

    local ignore = { Artifacts, camera }

    if LocalPlayer.Character then
        table.insert(ignore, LocalPlayer.Character)
    end

    RayParameters.FilterDescendantsInstances = ignore
end

local function overlayCenter()
    return State.ScreenSize * 0.5
end

local function project(camera, position)
    local projected = camera:WorldToViewportPoint(position)
    local offset = State.ProjectionOffset

    local point = Vector3.new(
        projected.X + offset.X,
        projected.Y + offset.Y,
        projected.Z
    )

    local size = State.ScreenSize

    return point, point.Z > 0
        and point.X >= 0
        and point.Y >= 0
        and point.X <= size.X
        and point.Y <= size.Y
end

local function visible(camera, character, position)
    local origin = camera.CFrame.Position
    local direction = position - origin

    if direction.Magnitude < 0.001 then
        return true
    end

    local result = workspace:Raycast(
        origin,
        direction,
        RayParameters
    )

    return result == nil
        or result.Instance:IsDescendantOf(character)
end

--==============================================================
-- 07. SHARED TEAM CONFIGURATION
--==============================================================

local NeutralToken = "Neutral / unassigned"

local function teamToken(player)
    if player.Neutral or player.Team == nil then
        return NeutralToken
    end

    return "Team: " .. player.Team.Name
end

local function sameTeam(player)
    return not LocalPlayer.Neutral
        and not player.Neutral
        and LocalPlayer.Team ~= nil
        and LocalPlayer.Team == player.Team
end

local function teamAllowed(player, checkTeammates, useAllowlist)
    if checkTeammates and sameTeam(player) then
        return false
    end

    if useAllowlist then
        return table.find(
            Config.Shared.SelectedTeams,
            teamToken(player)
        ) ~= nil
    end

    return true
end

local function playerColor(player, defaultHex, useTeams)
    if not useTeams then
        return color(defaultHex)
    end

    local override = Config.Shared.TeamColors[teamToken(player)]

    if override then
        return color(override)
    end

    if player.Team and not player.Neutral then
        return player.TeamColor.Color
    end

    return color(defaultHex)
end

local function teamOptions()
    local result = { NeutralToken }
    local seen = { [NeutralToken] = true }

    for _, team in ipairs(Teams:GetTeams()) do
        local token = "Team: " .. team.Name

        if not seen[token] then
            seen[token] = true
            table.insert(result, token)
        end
    end

    table.sort(result)

    return result
end

--==============================================================
-- 08. SMART SCANNER — CACHE / INVALIDATION
--==============================================================

local Scanner = {}

local function isCurrent(record, character, generation)
    return State.Running
        and Records[record.Player] == record
        and record.Character == character
        and record.Generation == generation
        and character ~= nil
        and character.Parent ~= nil
end

function Scanner.Mark(record)
    if not State.Running or not record.Character then
        return
    end

    record.Revision += 1
    record.Dirty = true
    record.Due = os.clock() + 0.15

    if not record.Busy then
        record.Status = "Queued"
    end

    if State.SelectedPlayer == record.Player then
        State.ScannerRefresh = true
    end
end

local function excludedPart(part, character)
    if part:GetAttribute("AimTargetable") == false then
        return true, "AimTargetable=false"
    end

    local ancestor = part.Parent

    while ancestor and ancestor ~= character do
        if ancestor:IsA("Accessory") then
            return true, "Accessory component"
        end

        if ancestor:IsA("Tool") then
            return true, "Tool component"
        end

        ancestor = ancestor.Parent
    end

    return false, nil
end

local function namedRole(part)
    local attribute = part:GetAttribute("AimRole")

    if attribute == "Head"
        or attribute == "Torso"
        or attribute == "Root" then

        return attribute
    end

    local name = part.Name:lower():gsub("[^%w]", "")

    if name:find("head", 1, true)
        or name:find("skull", 1, true) then
        return "Head"
    end

    if name:find("torso", 1, true)
        or name:find("chest", 1, true)
        or name == "body" then
        return "Torso"
    end

    if name == "humanoidrootpart"
        or name == "root"
        or name == "rootpart"
        or name == "pelvis" then
        return "Root"
    end

    return "Body"
end

local function observeObject(record, object)
    if record.Observed[object] then
        return
    end

    local bucket = {}
    record.Observed[object] = bucket

    connect(object:GetPropertyChangedSignal("Name"), function()
        Scanner.Mark(record)
    end, bucket)

    if object:IsA("BasePart") or object:IsA("Model") then
        connect(object.AttributeChanged, function(attribute)
            if attribute == "AimRole"
                or attribute == "AimTargetable" then

                Scanner.Mark(record)
            end
        end, bucket)
    end

    if object:IsA("Motor6D") or object:IsA("Weld") then
        connect(object:GetPropertyChangedSignal("Part0"), function()
            Scanner.Mark(record)
        end, bucket)

        connect(object:GetPropertyChangedSignal("Part1"), function()
            Scanner.Mark(record)
        end, bucket)
    end

    if object:IsA("Humanoid") then
        connect(object:GetPropertyChangedSignal("RootPart"), function()
            Scanner.Mark(record)
        end, bucket)
    end
end

local function forgetObject(record, object)
    local bucket = record.Observed[object]

    if bucket then
        disconnectAll(bucket)
        record.Observed[object] = nil
    end
end

function Scanner.Bind(record, character)
    disconnectAll(record.CharacterConnections)

    for object, bucket in pairs(record.Observed) do
        disconnectAll(bucket)
        record.Observed[object] = nil
    end

    record.Generation += 1
    record.Revision += 1
    record.Character = character
    record.Scan = nil
    record.Progress = 0
    record.Dirty = character ~= nil
    record.Due = os.clock()
    record.Status = character and "Queued" or "Waiting for character"

    if State.Target1 and State.Target1.Player == record.Player then
        State.Target1 = nil
    end

    if State.Target2 and State.Target2.Player == record.Player then
        State.Target2 = nil
    end

    if not character then
        State.ScannerRefresh = true
        return
    end

    connect(character.DescendantAdded, function(object)
        observeObject(record, object)
        Scanner.Mark(record)
    end, record.CharacterConnections)

    connect(character.DescendantRemoving, function(object)
        forgetObject(record, object)
        Scanner.Mark(record)
    end, record.CharacterConnections)

    connect(character:GetPropertyChangedSignal("PrimaryPart"), function()
        Scanner.Mark(record)
    end, record.CharacterConnections)

    observeObject(record, character)

    for _, object in ipairs(character:GetDescendants()) do
        observeObject(record, object)
    end

    State.ScannerRefresh = true
end

-- Relative keys include class and same-name sibling index.
-- This distinguishes duplicate component names in different branches.
local function pathBuilder(character)
    local paths = { [character] = "" }
    local siblingKeys = {}

    local function siblingKey(object)
        local parent = object.Parent

        if not parent then
            return object.Name .. " [" .. object.ClassName .. "]"
        end

        if not siblingKeys[parent] then
            local mapping = {}
            local counts = {}

            for _, child in ipairs(parent:GetChildren()) do
                local identity = child.Name .. "\0" .. child.ClassName
                counts[identity] = (counts[identity] or 0) + 1

                mapping[child] = string.format(
                    "%s [%s]#%d",
                    child.Name,
                    child.ClassName,
                    counts[identity]
                )
            end

            siblingKeys[parent] = mapping
        end

        return siblingKeys[parent][object]
            or object.Name .. " [" .. object.ClassName .. "]"
    end

    local function getPath(object)
        if paths[object] then
            return paths[object]
        end

        local parent = object.Parent

        if not parent or not object:IsDescendantOf(character) then
            return nil
        end

        local parentPath = getPath(parent)

        if parentPath == nil then
            return nil
        end

        local key = siblingKey(object)

        paths[object] = parentPath == ""
            and key
            or parentPath .. "/" .. key

        return paths[object]
    end

    return getPath
end

function Scanner.Start(record)
    if record.Busy
        or not record.Character
        or not record.Character.Parent then
        return
    end

    local character = record.Character
    local generation = record.Generation
    local revision = record.Revision

    record.Busy = true
    record.Dirty = false
    record.Progress = 0
    record.Status = "Scanning"
    State.ScanWorkers += 1

    task.spawn(function()
        local started = os.clock()

        local ok, failure = pcall(function()
            local descendants = character:GetDescendants()
            local getPath = pathBuilder(character)

            local scan = {
                Character = character,
                Humanoid = nil,
                Parts = {},
                ByKey = {},
                ByInstance = {},
                Roles = {
                    Head = {},
                    Torso = {},
                    Root = {},
                    Body = {},
                },
                Entries = {},
                Motors = {},
                ForceFields = {},
                Excluded = 0,
                Root = nil,
                Head = nil,
                Rig = "Custom component hierarchy",
                Duration = 0,
            }

            for index, object in ipairs(descendants) do
                if not isCurrent(record, character, generation) then
                    return
                end

                if record.Revision ~= revision then
                    return
                end

                local key = getPath(object)

                if key then
                    local entry = {
                        Key = key,
                        Class = object.ClassName,
                        Targetable = false,
                        Reason = "",
                    }

                    if object:IsA("Humanoid") then
                        scan.Humanoid = scan.Humanoid or object

                    elseif object:IsA("Motor6D") then
                        table.insert(scan.Motors, object)

                    elseif object:IsA("ForceField") then
                        table.insert(scan.ForceFields, object)
                    end

                    if object:IsA("BasePart") then
                        local excluded, reason =
                            excludedPart(object, character)

                        if excluded then
                            scan.Excluded += 1
                            entry.Reason = reason
                        else
                            local item = {
                                Part = object,
                                Key = key,
                                Role = namedRole(object),
                            }

                            entry.Targetable = true
                            entry.Reason = item.Role

                            table.insert(scan.Parts, item)
                            scan.ByKey[key] = item
                            scan.ByInstance[object] = item
                        end

                    elseif object:IsA("Bone") then
                        entry.Reason = "Informational; select its BasePart"
                    end

                    table.insert(scan.Entries, entry)
                end

                record.Progress = math.floor(
                    index / math.max(#descendants, 1) * 100
                )

                -- Spread large model scans across frames.
                if index % 64 == 0 then
                    task.wait()
                end
            end

            if not isCurrent(record, character, generation)
                or record.Revision ~= revision then
                return
            end

            local humanoid = scan.Humanoid
            local root = humanoid and humanoid.RootPart
                or character.PrimaryPart

            if root and not scan.ByInstance[root] then
                root = nil
            end

            if not root then
                for _, item in ipairs(scan.Parts) do
                    if item.Role == "Root" then
                        root = item.Part
                        break
                    end
                end
            end

            if not root then
                local largestVolume = -1

                for _, item in ipairs(scan.Parts) do
                    local size = item.Part.Size
                    local volume = size.X * size.Y * size.Z

                    if volume > largestVolume then
                        largestVolume = volume
                        root = item.Part
                    end
                end
            end

            scan.Root = root

            -- Neck joints identify a head even when it was renamed.
            for _, motor in ipairs(scan.Motors) do
                if motor.Parent then
                    local name = motor.Name:lower()

                    if name:find("neck", 1, true) then
                        local item = scan.ByInstance[motor.Part1]

                        if item and item.Role == "Body" then
                            item.Role = "Head"
                        end
                    end
                end
            end

            -- Explicit AimRole attributes take precedence over heuristics.
            for _, item in ipairs(scan.Parts) do
                local role = item.Part:GetAttribute("AimRole")

                if role == "Head"
                    or role == "Torso"
                    or role == "Root" then

                    item.Role = role
                end

                table.insert(scan.Roles[item.Role], item)
            end

            if #scan.Roles.Head > 0 then
                scan.Head = scan.Roles.Head[1].Part
            else
                -- Geometric fallback for otherwise unnamed custom rigs.
                local highest = -math.huge

                for _, item in ipairs(scan.Parts) do
                    local position = item.Part.Position

                    local height = root
                        and root.CFrame:PointToObjectSpace(position).Y
                        or position.Y

                    if height > highest then
                        highest = height
                        scan.Head = item.Part
                    end
                end
            end

            if character:FindFirstChild("UpperTorso")
                and character:FindFirstChild("LowerTorso") then

                scan.Rig = "R15-style named rig"

            elseif character:FindFirstChild("Torso")
                and character:FindFirstChild("Head") then

                scan.Rig = "R6-style named rig"

            elseif humanoid then
                scan.Rig = "Custom / renamed Humanoid rig ("
                    .. humanoid.RigType.Name .. ")"
            end

            for _, entry in ipairs(scan.Entries) do
                local item = scan.ByKey[entry.Key]

                if item then
                    entry.Reason = item.Role
                end
            end

            table.sort(scan.Parts, function(a, b)
                return a.Key < b.Key
            end)

            table.sort(scan.Entries, function(a, b)
                return a.Key < b.Key
            end)

            scan.Duration = os.clock() - started

            record.Scan = scan
            record.Progress = 100
            record.Status = #scan.Parts > 0
                and "Ready"
                or "No supported BasePart candidates"

            record.Completed = os.clock()
            State.ScanCount += 1
            State.ScannerRefresh = true
            State.VisualElapsed = math.huge
        end)

        record.Busy = false
        State.ScanWorkers = math.max(State.ScanWorkers - 1, 0)

        if not State.Running or Records[record.Player] ~= record then
            return
        end

        if not ok then
            record.Status = "Scan error"
            record.Error = tostring(failure)
            record.Dirty = false

        elseif record.Generation ~= generation
            or record.Revision ~= revision then

            record.Dirty = record.Character ~= nil
            record.Due = os.clock() + 0.15
            record.Status = record.Character
                and "Queued after model change"
                or "Waiting for character"

        else
            record.Error = nil
        end
    end)
end

--==============================================================
-- 09. LIVE CHARACTER DATA / COMPONENT RESOLUTION
--==============================================================

local function validPart(part, character)
    return part ~= nil
        and part:IsA("BasePart")
        and part.Parent ~= nil
        and part:IsDescendantOf(character)
        and part:GetAttribute("AimTargetable") ~= false
end

local function liveData(record)
    local scan = record and record.Scan
    local character = record and record.Character

    if not scan
        or not character
        or not character.Parent
        or record.Player.Character ~= character then
        return nil
    end

    local humanoid = scan.Humanoid
    local health
    local maxHealth

    if humanoid and humanoid:IsDescendantOf(character) then
        health = humanoid.Health
        maxHealth = humanoid.MaxHealth
    else
        humanoid = nil
        health = character:GetAttribute("Health")
        maxHealth = character:GetAttribute("MaxHealth")
    end

    if not finite(health)
        or not finite(maxHealth)
        or health <= 0
        or maxHealth <= 0 then
        return nil
    end

    local root = scan.Root

    if not validPart(root, character) then
        return nil
    end

    local head = scan.Head

    if not validPart(head, character) then
        head = root
    end

    return {
        Character = character,
        Humanoid = humanoid,
        Health = health,
        MaxHealth = maxHealth,
        Root = root,
        Head = head,
        Scan = scan,
    }
end

local function hasForceField(scan)
    for _, field in ipairs(scan.ForceFields) do
        if field.Parent and field:IsDescendantOf(scan.Character) then
            return true
        end
    end

    return false
end

local function componentList(record, mode, allowFallback)
    local scan = record and record.Scan

    if not scan then
        return {}
    end

    local result = {}
    local seen = {}

    local function append(part)
        if validPart(part, scan.Character) and not seen[part] then
            seen[part] = true
            table.insert(result, part)
        end
    end

    local function appendRole(role)
        for _, item in ipairs(scan.Roles[role] or {}) do
            append(item.Part)
        end
    end

    local function appendAuto()
        appendRole("Head")
        append(scan.Head)
        appendRole("Torso")
        append(scan.Root)

        for _, item in ipairs(scan.Parts) do
            append(item.Part)
        end
    end

    if mode == "Manual" then
        local key = Config.V2.ManualTargets[
            tostring(record.Player.UserId)
        ]

        local item = key and scan.ByKey[key]

        if item then
            append(item.Part)
        end

        -- No per-player choice means automatic selection.
        if not key or (#result == 0 and allowFallback) then
            appendAuto()
        end

    elseif mode == "Auto" or mode == "Closest visible" then
        appendAuto()

    elseif mode == "Root" then
        append(scan.Root)
        appendRole("Root")

        if #result == 0 and allowFallback then
            appendAuto()
        end

    else
        appendRole(mode)

        if #result == 0 and allowFallback then
            appendAuto()
        end
    end

    return result
end

-- Exact V1 naming rules remain separate from Smart Scan V2.
local function v1Character(player)
    local character = player.Character

    if not character or not character.Parent then
        return nil
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local head = character:FindFirstChild("Head")
    local root = character:FindFirstChild("HumanoidRootPart")

    if not humanoid or humanoid.Health <= 0 then
        return nil
    end

    if not head or not head:IsA("BasePart") then
        return nil
    end

    if not root or not root:IsA("BasePart") then
        root = head
    end

    return character, humanoid, head, root
end

local function v1Part(character)
    local mode = Config.V1.TargetPart
    local part

    if mode == "Torso" then
        part = character:FindFirstChild("UpperTorso")
            or character:FindFirstChild("Torso")

    elseif mode == "Root" then
        part = character:FindFirstChild("HumanoidRootPart")
    else
        part = character:FindFirstChild("Head")
    end

    return part and part:IsA("BasePart") and part or nil
end

--==============================================================
-- 10. AIM V1
--==============================================================

local function evaluateV1(player, camera, origin)
    local settings = Config.V1

    if player == LocalPlayer
        or not teamAllowed(
            player,
            settings.AimTeamCheck,
            settings.SpecificTeams
        ) then
        return nil
    end

    local character, humanoid = v1Character(player)

    if not character
        or humanoid.Health < settings.MinimumHealth then
        return nil
    end

    if settings.ForceFieldCheck
        and character:FindFirstChildOfClass("ForceField") then
        return nil
    end

    local part = v1Part(character)

    if not part then
        return nil
    end

    local distance = (part.Position - camera.CFrame.Position).Magnitude

    if distance > settings.MaxDistance then
        return nil
    end

    local point, onScreen = project(camera, part.Position)

    if not onScreen then
        return nil
    end

    local screenDistance = (
        Vector2.new(point.X, point.Y) - origin
    ).Magnitude

    if screenDistance > settings.FOV then
        return nil
    end

    if settings.WallCheck
        and not visible(camera, character, part.Position) then
        return nil
    end

    local score = screenDistance

    if settings.Priority == "Distance" then
        score = distance
    elseif settings.Priority == "Lowest health" then
        score = humanoid.Health
    end

    return {
        Player = player,
        Part = part,
        Character = character,
        Score = score,
        ScreenDistance = screenDistance,
    }
end

local function chooseV1(camera, origin)
    if Config.V1.StickyTarget and State.Target1 then
        local current = evaluateV1(
            State.Target1.Player,
            camera,
            origin
        )

        if current then
            State.Target1 = current
            return current
        end
    end

    local best

    for _, player in ipairs(Players:GetPlayers()) do
        local candidate = evaluateV1(player, camera, origin)

        if candidate and (not best or candidate.Score < best.Score) then
            best = candidate
        end
    end

    State.Target1 = best
    return best
end

--==============================================================
-- 11. AIM V2
--==============================================================

local function evaluateV2(player, camera, origin)
    local settings = Config.V2
    local record = Records[player]

    if player == LocalPlayer
        or not teamAllowed(
            player,
            settings.TeamCheck,
            settings.SpecificTeams
        ) then
        return nil
    end

    local data = liveData(record)

    if not data or data.Health < settings.MinimumHealth then
        return nil
    end

    if settings.ForceFieldCheck and hasForceField(data.Scan) then
        return nil
    end

    local rootDistance = (
        data.Root.Position - camera.CFrame.Position
    ).Magnitude

    if rootDistance > settings.MaxDistance then
        return nil
    end

    local parts = componentList(
        record,
        settings.TargetPart,
        settings.MissingPartFallback
    )

    local candidates = {}

    for index, part in ipairs(parts) do
        local point, onScreen = project(camera, part.Position)

        if onScreen then
            local screenDistance = (
                Vector2.new(point.X, point.Y) - origin
            ).Magnitude

            local distance = (
                part.Position - camera.CFrame.Position
            ).Magnitude

            if screenDistance <= settings.FOV
                and distance <= settings.MaxDistance then

                table.insert(candidates, {
                    Part = part,
                    ScreenDistance = screenDistance,
                    Distance = distance,
                    Order = index,
                })
            end
        end
    end

    if settings.TargetPart == "Closest visible" then
        table.sort(candidates, function(a, b)
            return a.ScreenDistance < b.ScreenDistance
        end)
    end

    for _, candidate in ipairs(candidates) do
        if not settings.WallCheck
            or visible(camera, data.Character, candidate.Part.Position) then

            local score = candidate.ScreenDistance

            if settings.Priority == "Distance" then
                score = candidate.Distance
            elseif settings.Priority == "Lowest health" then
                score = data.Health
            end

            return {
                Player = player,
                Part = candidate.Part,
                Character = data.Character,
                Score = score,
                ScreenDistance = candidate.ScreenDistance,
            }
        end
    end

    return nil
end

local function chooseV2(camera, origin)
    local settings = Config.V2
    local now = os.clock()
    local current

    if State.Target2 then
        current = evaluateV2(State.Target2.Player, camera, origin)
    end

    if current and settings.StickyTarget then
        State.Target2 = current
        return current
    end

    if now < State.NextAcquire2 then
        State.Target2 = current
        return current
    end

    State.NextAcquire2 = now + 1 / settings.AcquisitionRate

    local best

    for _, player in ipairs(Players:GetPlayers()) do
        local candidate = evaluateV2(player, camera, origin)

        if candidate and (not best or candidate.Score < best.Score) then
            best = candidate
        end
    end

    State.Target2 = best
    return best
end

local function turnCamera(camera, part, alpha)
    if not part or not part.Parent then
        return
    end

    local position = camera.CFrame.Position

    if (part.Position - position).Magnitude <= 0.001 then
        return
    end

    camera.CFrame = camera.CFrame:Lerp(
        CFrame.lookAt(position, part.Position),
        math.clamp(alpha, 0, 1)
    )
end

--==============================================================
-- 12. ESP — CREATION
--==============================================================

local function textLabel(parent, name)
    return make("TextLabel", {
        Name = name,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Font = Enum.Font.GothamSemibold,
        TextSize = Config.V1.TextSize,
        TextColor3 = Color3.new(1, 1, 1),
        TextStrokeTransparency = 0.25,
        TextTruncate = Enum.TextTruncate.AtEnd,
        RichText = false,
        Selectable = false,
        Active = false,
        Visible = false,
    }, parent)
end

local function createVisual(player)
    if player == LocalPlayer or Visuals[player] then
        return
    end

    local gui = make("Frame", {
        Name = "Player_" .. tostring(player.UserId),
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Selectable = false,
        Active = false,
        Visible = false,
    }, Canvas)

    local highlight = make("Highlight", {
        Name = "Highlight_" .. tostring(player.UserId),
        Enabled = false,
        FillTransparency = 0.65,
        OutlineTransparency = 0.1,
    }, Artifacts)

    local name = textLabel(gui, "Name")
    name.AnchorPoint = Vector2.new(0.5, 1)
    name.Size = UDim2.fromOffset(280, 26)

    local details = textLabel(gui, "Details")
    details.AnchorPoint = Vector2.new(0.5, 0)
    details.Size = UDim2.fromOffset(300, 26)

    local box = make("Frame", {
        Name = "Box",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Selectable = false,
        Active = false,
        Visible = false,
    }, gui)

    local stroke = make("UIStroke", {
        Thickness = 1,
    }, box)

    local health = make("Frame", {
        Name = "HealthBar",
        BackgroundColor3 = Color3.fromRGB(20, 20, 24),
        BorderSizePixel = 0,
        Selectable = false,
        Active = false,
        Visible = false,
    }, gui)

    make("UIStroke", {
        Color = Color3.new(0, 0, 0),
        Thickness = 1,
    }, health)

    local fill = make("Frame", {
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.fromScale(0, 1),
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.fromRGB(70, 220, 100),
        BorderSizePixel = 0,
        Selectable = false,
        Active = false,
    }, health)

    Visuals[player] = {
        Gui = gui,
        Highlight = highlight,
        Name = name,
        Details = details,
        Box = box,
        BoxStroke = stroke,
        Health = health,
        Fill = fill,
    }
end

local function hideVisual(visual)
    visual.Gui.Visible = false
    visual.Highlight.Enabled = false
end

local function removeVisual(player)
    local visual = Visuals[player]

    if visual then
        visual.Highlight:Destroy()
        visual.Gui:Destroy()
        Visuals[player] = nil
    end
end

local function screenBounds(camera, character)
    local boxCFrame, boxSize = character:GetBoundingBox()
    local half = boxSize * 0.5

    local left = math.huge
    local top = math.huge
    local right = -math.huge
    local bottom = -math.huge

    for x = -1, 1, 2 do
        for y = -1, 1, 2 do
            for z = -1, 1, 2 do
                local position = boxCFrame:PointToWorldSpace(
                    Vector3.new(
                        half.X * x,
                        half.Y * y,
                        half.Z * z
                    )
                )

                local point = project(camera, position)

                if point.Z <= 0.1 then
                    return nil
                end

                left = math.min(left, point.X)
                right = math.max(right, point.X)
                top = math.min(top, point.Y)
                bottom = math.max(bottom, point.Y)
            end
        end
    end

    local size = State.ScreenSize

    if right < 0
        or bottom < 0
        or left > size.X
        or top > size.Y then
        return nil
    end

    return left, top, right, bottom
end

--==============================================================
-- 13. ESP — UPDATES
--==============================================================

local function updateVisual(player, visual, camera)
    hideVisual(visual)

    local settings = Config.V1

    if not (
        settings.Highlights
        or settings.Names
        or settings.HealthBars
        or settings.Boxes
        or settings.Distances
        or settings.HealthNumbers
    ) then
        return
    end

    if not teamAllowed(
        player,
        settings.VisualTeamCheck,
        settings.VisualSpecificTeams
    ) then
        return
    end

    -- Standard rigs retain V1 behavior.
    -- Custom rigs can use the scanner's live-data fallback.
    local character, humanoid, head, root = v1Character(player)
    local health
    local maxHealth

    if character then
        health = humanoid.Health
        maxHealth = humanoid.MaxHealth
    else
        local data = liveData(Records[player])

        if not data then
            return
        end

        character = data.Character
        head = data.Head
        root = data.Root
        health = data.Health
        maxHealth = data.MaxHealth
    end

    if not settings.ThroughWalls
        and not visible(camera, character, head.Position) then
        return
    end

    local tint = playerColor(
        player,
        settings.VisualColor,
        settings.TeamColors
    )

    visual.Highlight.Adornee = character
    visual.Highlight.FillColor = tint
    visual.Highlight.OutlineColor = tint
    visual.Highlight.FillTransparency =
        1 - settings.HighlightOpacity / 100

    visual.Highlight.DepthMode = settings.ThroughWalls
        and Enum.HighlightDepthMode.AlwaysOnTop
        or Enum.HighlightDepthMode.Occluded

    visual.Highlight.Enabled = settings.Highlights

    visual.Name.Visible = false
    visual.Details.Visible = false
    visual.Box.Visible = false
    visual.Health.Visible = false

    if settings.Names then
        local position = head.Position
            + Vector3.new(0, head.Size.Y * 0.5 + 0.35, 0)

        local point, onScreen = project(camera, position)

        if onScreen then
            visual.Name.Text = string.format(
                "%s (@%s)",
                player.DisplayName,
                player.Name
            )

            visual.Name.TextSize = settings.TextSize
            visual.Name.TextColor3 = tint
            visual.Name.Position = UDim2.fromOffset(point.X, point.Y)
            visual.Name.Visible = true
        end
    end

    local needsBounds = settings.HealthBars
        or settings.Boxes
        or settings.Distances
        or settings.HealthNumbers

    if not needsBounds then
        visual.Gui.Visible = visual.Name.Visible
        return
    end

    local left, top, right, bottom = screenBounds(camera, character)

    if not left then
        visual.Gui.Visible = visual.Name.Visible
        return
    end

    visual.Gui.Visible = true

    if settings.Boxes then
        visual.Box.Position = UDim2.fromOffset(left, top)
        visual.Box.Size = UDim2.fromOffset(
            math.max(right - left, 1),
            math.max(bottom - top, 1)
        )

        visual.BoxStroke.Color = tint
        visual.Box.Visible = true
    end

    if settings.HealthBars then
        local fraction = math.clamp(
            health / math.max(maxHealth, 1),
            0,
            1
        )

        visual.Health.Position = UDim2.fromOffset(right + 5, top)
        visual.Health.Size = UDim2.fromOffset(
            4,
            math.max(bottom - top, 8)
        )

        visual.Fill.Size = UDim2.fromScale(1, fraction)
        visual.Fill.BackgroundColor3 =
            Color3.fromHSV(fraction / 3, 0.85, 1)

        visual.Health.Visible = true
    end

    local details = {}

    if settings.Distances then
        local distance = (
            root.Position - camera.CFrame.Position
        ).Magnitude

        table.insert(details, string.format(
            "%d studs",
            math.floor(distance + 0.5)
        ))
    end

    if settings.HealthNumbers then
        table.insert(details, string.format(
            "%d/%d HP",
            math.ceil(health),
            math.ceil(maxHealth)
        ))
    end

    if #details > 0 then
        visual.Details.Text = table.concat(details, "  |  ")
        visual.Details.TextSize = settings.TextSize
        visual.Details.TextColor3 = tint
        visual.Details.Position = UDim2.fromOffset(
            (left + right) * 0.5,
            bottom + 3
        )

        visual.Details.Visible = true
    end
end

--==============================================================
-- 14. VISUAL-ONLY HITBOX MODULE
--==============================================================

local HitboxModule = {}

local function newAdornment(parent)
    return make("BoxHandleAdornment", {
        Adornee = nil,
        Size = Vector3.new(1, 1, 1),
        CFrame = CFrame.identity,
        Color3 = Color3.fromRGB(102, 227, 255),
        Transparency = 0.7,
        AlwaysOnTop = false,
        ZIndex = 1,
        Visible = false,
    }, parent)
end

function HitboxModule.Create(player)
    if Hitboxes[player] then
        return Hitboxes[player]
    end

    local folder = make("Folder", {
        Name = "Hitbox_" .. tostring(player.UserId),
    }, Artifacts)

    local visual = {
        Folder = folder,
        Fill = newAdornment(folder),
        Edges = {},
        Revision = -1,
        Part = nil,
    }

    for index = 1, 12 do
        visual.Edges[index] = newAdornment(folder)
    end

    Hitboxes[player] = visual
    return visual
end

function HitboxModule.Hide(visual)
    visual.Fill.Visible = false
    visual.Fill.Adornee = nil

    for _, edge in ipairs(visual.Edges) do
        edge.Visible = false
        edge.Adornee = nil
    end

    visual.Part = nil
end

function HitboxModule.Remove(player)
    local visual = Hitboxes[player]

    if visual then
        visual.Folder:Destroy()
        Hitboxes[player] = nil
    end
end

local function edgeGeometry(x, y, z, thickness)
    local result = {}

    for _, sy in ipairs({ -1, 1 }) do
        for _, sz in ipairs({ -1, 1 }) do
            table.insert(result, {
                Size = Vector3.new(x, thickness, thickness),
                Offset = Vector3.new(0, sy * y / 2, sz * z / 2),
            })
        end
    end

    for _, sx in ipairs({ -1, 1 }) do
        for _, sz in ipairs({ -1, 1 }) do
            table.insert(result, {
                Size = Vector3.new(thickness, y, thickness),
                Offset = Vector3.new(sx * x / 2, 0, sz * z / 2),
            })
        end
    end

    for _, sx in ipairs({ -1, 1 }) do
        for _, sy in ipairs({ -1, 1 }) do
            table.insert(result, {
                Size = Vector3.new(thickness, thickness, z),
                Offset = Vector3.new(sx * x / 2, sy * y / 2, 0),
            })
        end
    end

    return result
end

function HitboxModule.Show(player, part)
    local settings = Config.Hitbox
    local visual = HitboxModule.Create(player)

    local tint = playerColor(
        player,
        settings.Color,
        settings.TeamColors
    )

    if visual.Revision ~= State.Revision then
        visual.Revision = State.Revision

        visual.Fill.Size = Vector3.new(
            settings.X,
            settings.Y,
            settings.Z
        )

        local geometry = edgeGeometry(
            settings.X,
            settings.Y,
            settings.Z,
            settings.OutlineThickness
        )

        for index, edge in ipairs(visual.Edges) do
            edge.Size = geometry[index].Size
            edge.CFrame = CFrame.new(geometry[index].Offset)
        end
    end

    visual.Part = part
    visual.Fill.Adornee = part
    visual.Fill.Color3 = tint
    visual.Fill.Transparency = settings.Transparency / 100
    visual.Fill.AlwaysOnTop = settings.ThroughWalls
    visual.Fill.Visible = settings.Fill

    for _, edge in ipairs(visual.Edges) do
        edge.Adornee = part
        edge.Color3 = tint
        edge.Transparency = settings.OutlineTransparency / 100
        edge.AlwaysOnTop = settings.ThroughWalls
        edge.Visible = settings.Outlines
    end
end

function HitboxModule.Update(camera)
    local settings = Config.Hitbox
    local candidates = {}
    local shown = {}

    State.VisibleHitboxes = 0

    if settings.Enabled then
        for player, record in pairs(Records) do
            if player ~= LocalPlayer
                and teamAllowed(
                    player,
                    settings.TeamCheck,
                    settings.SpecificTeams
                ) then

                local data = liveData(record)

                if data then
                    local distance = (
                        data.Root.Position - camera.CFrame.Position
                    ).Magnitude

                    if distance <= settings.MaxDistance then
                        local parts = componentList(
                            record,
                            settings.TargetPart,
                            true
                        )

                        if parts[1] then
                            table.insert(candidates, {
                                Player = player,
                                Part = parts[1],
                                Distance = distance,
                            })
                        end
                    end
                end
            end
        end

        table.sort(candidates, function(a, b)
            return a.Distance < b.Distance
        end)

        local count = math.min(
            #candidates,
            math.floor(settings.MaxVisible)
        )

        for index = 1, count do
            local candidate = candidates[index]
            shown[candidate.Player] = true

            HitboxModule.Show(candidate.Player, candidate.Part)
            State.VisibleHitboxes += 1
        end
    end

    for player, visual in pairs(Hitboxes) do
        if not shown[player] then
            HitboxModule.Hide(visual)
        end
    end
end

--==============================================================
-- 15. WINDUI WINDOW / CONTROL HELPERS
--==============================================================

local initialViewport = workspace.CurrentCamera
    and workspace.CurrentCamera.ViewportSize
    or Vector2.new(1000, 700)

local Window = WindUI:CreateWindow({
    Title = "Targeting & Visuals — Smart V2",
    Icon = "scan",
    Folder = "TargetingSmartV2",
    Size = UDim2.fromOffset(
        math.clamp(initialViewport.X - 36, 340, 680),
        math.clamp(initialViewport.Y - 60, 300, 560)
    ),
    MinSize = Vector2.new(320, 280),
    SideBarWidth = 165,
    AutoScale = true,
    Resizable = true,
    NewElements = true,
    Theme = "Dark",
    ToggleKey = Enum.KeyCode.RightShift,
})

local Tabs = {}

for _, item in ipairs({
    { "V1", "Aim V1", "crosshair" },
    { "V2", "Smart Aim V2", "scan" },
    { "Scanner", "Character Scanner", "search" },
    { "Hitbox", "Hitbox Visuals", "box" },
    { "Teams", "Shared Teams", "users" },
    { "Visuals", "Player Visuals", "eye" },
    { "Appearance", "Appearance", "palette" },
    { "System", "System", "settings" },
}) do
    Tabs[item[1]] = Window:Tab({
        Title = item[2],
        Icon = item[3],
    })
end

local function section(tab, title)
    return tab:Section({ Title = title })
end

local function paragraph(tab, title, description)
    return tab:Paragraph({
        Title = title,
        Desc = description,
    })
end

local function escapeText(value)
    return tostring(value)
        :gsub("&", "&amp;")
        :gsub("<", "&lt;")
        :gsub(">", "&gt;")
end

local function setParagraph(control, text)
    local frame = control and control.ParagraphFrame

    if frame then
        frame:SetDesc(escapeText(text))
    end
end

local function toggle(tab, title, group, key)
    return tab:Toggle({
        Title = title,
        Value = Config[group][key],

        Callback = function(value)
            if State.Running then
                setConfig(group, key, value)
            end
        end,
    })
end

local function slider(tab, title, group, key, step)
    local limit = Limits[group .. "." .. key]

    return tab:Slider({
        Title = title,
        Step = step or 1,

        Value = {
            Min = limit[1],
            Max = limit[2],
            Default = Config[group][key],
        },

        Callback = function(value)
            local number = tonumber(value)

            if State.Running and finite(number) then
                setConfig(
                    group,
                    key,
                    math.clamp(number, limit[1], limit[2])
                )
            end
        end,
    })
end

local function dropdown(tab, title, group, key)
    return tab:Dropdown({
        Title = title,
        Values = Choices[group .. "." .. key],
        Value = Config[group][key],
        Multi = false,
        AllowNone = false,

        Callback = function(value)
            if State.Running
                and table.find(Choices[group .. "." .. key], value) then

                setConfig(group, key, value)
            end
        end,
    })
end

local function colorpicker(tab, title, group, key)
    return tab:Colorpicker({
        Title = title,
        Default = color(Config[group][key]),

        Callback = function(value)
            if State.Running and typeof(value) == "Color3" then
                setConfig(group, key, "#" .. value:ToHex())
            end
        end,
    })
end

--==============================================================
-- 16. AIM V1 MENU — PRESERVED CONTROLS
--==============================================================

section(Tabs.V1, "Activation")

toggle(Tabs.V1, "Enable aim assistance V1", "V1", "AimEnabled")
dropdown(Tabs.V1, "Activation mode V1", "V1", "ActivationMode")
dropdown(Tabs.V1, "Activation key V1", "V1", "ActivationKey")

section(Tabs.V1, "Tracking")

slider(
    Tabs.V1,
    "Strength — 0% normal / 100% instant",
    "V1",
    "Strength"
)

dropdown(Tabs.V1, "Target body part V1", "V1", "TargetPart")
dropdown(Tabs.V1, "Target priority V1", "V1", "Priority")
toggle(Tabs.V1, "Keep current target V1", "V1", "StickyTarget")

section(Tabs.V1, "Target eligibility")

toggle(Tabs.V1, "Team check V1", "V1", "AimTeamCheck")
toggle(Tabs.V1, "Wall check V1", "V1", "WallCheck")
toggle(Tabs.V1, "Ignore ForceField targets V1", "V1", "ForceFieldCheck")
toggle(Tabs.V1, "Use shared team selection V1", "V1", "SpecificTeams")

slider(Tabs.V1, "Maximum distance V1 — studs", "V1", "MaxDistance")
slider(Tabs.V1, "Minimum target health V1", "V1", "MinimumHealth")

section(Tabs.V1, "Centered FOV")

toggle(Tabs.V1, "Show FOV circle V1", "V1", "ShowFOV")
slider(Tabs.V1, "FOV radius V1 — pixels", "V1", "FOV")

--==============================================================
-- 17. AIM V2 MENU
--==============================================================

paragraph(
    Tabs.V2,
    "Smart Aim V2",
    "V2 has camera priority while active. "
        .. "V1 remains available when V2 is inactive. "
        .. "Auto tries recognized head, torso, root, then other candidates."
)

section(Tabs.V2, "Activation")

UI.V2Enabled = toggle(
    Tabs.V2,
    "Enable Smart Aim V2",
    "V2",
    "Enabled"
)

toggle(Tabs.V2, "Enable activation key V2", "V2", "KeybindEnabled")
dropdown(Tabs.V2, "Activation mode V2", "V2", "ActivationMode")
toggle(Tabs.V2, "Show movable floating toggle", "V2", "FloatingToggle")

UI.KeyStatus = paragraph(Tabs.V2, "V2 keybind", "Preparing...")

Tabs.V2:Button({
    Title = "Assign activation key V2",
    Icon = "keyboard",

    Callback = function()
        if not State.Running then
            return
        end

        resetActivation()
        State.Binding = true
        State.BindingExpires = os.clock() + 8

        setParagraph(
            UI.KeyStatus,
            "Press a keyboard key. Escape cancels. RightShift is reserved."
        )
    end,
})

section(Tabs.V2, "Targeting")

dropdown(Tabs.V2, "Preferred component V2", "V2", "TargetPart")
dropdown(Tabs.V2, "Player priority V2", "V2", "Priority")

toggle(Tabs.V2, "Keep current valid target V2", "V2", "StickyTarget")

toggle(
    Tabs.V2,
    "Fallback when preferred component is missing",
    "V2",
    "MissingPartFallback"
)

slider(
    Tabs.V2,
    "Smoothness V2 — 0 instant / 100 soft",
    "V2",
    "Smoothness"
)

slider(Tabs.V2, "Center deadzone V2 — pixels", "V2", "Deadzone")
slider(Tabs.V2, "Maximum distance V2 — studs", "V2", "MaxDistance")
slider(Tabs.V2, "Minimum target health V2", "V2", "MinimumHealth")

section(Tabs.V2, "Eligibility")

toggle(Tabs.V2, "Team check V2", "V2", "TeamCheck")
toggle(Tabs.V2, "Wall check V2", "V2", "WallCheck")
toggle(Tabs.V2, "Ignore ForceField targets V2", "V2", "ForceFieldCheck")
toggle(Tabs.V2, "Enable specific-team aim V2", "V2", "SpecificTeams")

section(Tabs.V2, "Centered FOV V2")

toggle(Tabs.V2, "Show FOV circle V2", "V2", "ShowFOV")
slider(Tabs.V2, "FOV radius V2 — pixels", "V2", "FOV")
colorpicker(Tabs.V2, "FOV color V2", "V2", "FOVColor")
slider(Tabs.V2, "FOV thickness V2", "V2", "FOVThickness", 0.5)

--==============================================================
-- 18. MANUAL SCANNER MENU
--==============================================================

local PlayerOptions = {}
local PlayerOptionMap = {}
local ScannerUpdating = false
local ManualOptionsSignature = ""

local function playerLabel(player)
    return string.format(
        "%s (@%s) [%d]",
        player.DisplayName,
        player.Name,
        player.UserId
    )
end

local function refreshPlayerOptions()
    table.clear(PlayerOptions)
    table.clear(PlayerOptionMap)

    for _, player in ipairs(Players:GetPlayers()) do
        local label = playerLabel(player)
        table.insert(PlayerOptions, label)
        PlayerOptionMap[label] = player
    end

    table.sort(PlayerOptions)

    if UI.ScannerPlayer then
        ScannerUpdating = true

        UI.ScannerPlayer:Refresh(PlayerOptions)

        if State.SelectedPlayer
            and State.SelectedPlayer.Parent == Players then

            UI.ScannerPlayer:Select(playerLabel(State.SelectedPlayer))
        end

        ScannerUpdating = false
    end
end

refreshPlayerOptions()

paragraph(
    Tabs.Scanner,
    "Manual character scanner",
    "Scans the selected player's entire Character hierarchy. "
        .. "BaseParts are selectable; bones and other components are "
        .. "listed for inspection. Accessories and Tools are excluded. "
        .. "Manual selections apply per player when Manual mode is chosen."
)

UI.ScannerPlayer = Tabs.Scanner:Dropdown({
    Title = "Character to inspect",
    Values = PlayerOptions,
    Value = playerLabel(LocalPlayer),
    Multi = false,
    AllowNone = false,

    Callback = function(value)
        if ScannerUpdating then
            return
        end

        local player = PlayerOptionMap[value]

        if player then
            State.SelectedPlayer = player
            State.ScannerPage = 1
            State.ScannerRefresh = true
            ManualOptionsSignature = ""
        end
    end,
})

UI.ScannerStatus = paragraph(Tabs.Scanner, "Scan status", "Waiting...")
UI.ScannerDetails = paragraph(Tabs.Scanner, "Character diagnostics", "Waiting...")

UI.ManualComponent = Tabs.Scanner:Dropdown({
    Title = "Manual targetable component",
    Values = { "Automatic" },
    Value = "Automatic",
    Multi = false,
    AllowNone = false,
    SearchBarEnabled = true,

    Callback = function(value)
        if ScannerUpdating or not State.SelectedPlayer then
            return
        end

        local record = Records[State.SelectedPlayer]
        local key = tostring(State.SelectedPlayer.UserId)

        if value == "Automatic" then
            Config.V2.ManualTargets[key] = nil

        elseif record
            and record.Scan
            and record.Scan.ByKey[value] then

            Config.V2.ManualTargets[key] = value
        else
            return
        end

        changed()
    end,
})

Tabs.Scanner:Button({
    Title = "Rescan selected character",
    Icon = "refresh-cw",

    Callback = function()
        local record = Records[State.SelectedPlayer]

        if record then
            Scanner.Mark(record)
            record.Due = 0
            record.Error = nil
            State.ScannerPage = 1
            State.ScannerRefresh = true
        end
    end,
})

Tabs.Scanner:Button({
    Title = "Rescan all player characters",
    Icon = "scan",

    Callback = function()
        for _, record in pairs(Records) do
            Scanner.Mark(record)
            record.Due = 0
            record.Error = nil
        end

        State.ScannerRefresh = true
    end,
})

section(Tabs.Scanner, "Complete component hierarchy")

UI.Hierarchy = paragraph(
    Tabs.Scanner,
    "Hierarchy",
    "All scanned components appear here in pages."
)

Tabs.Scanner:Button({
    Title = "Previous hierarchy page",
    Icon = "chevron-left",

    Callback = function()
        State.ScannerPage = math.max(State.ScannerPage - 1, 1)
        State.ScannerRefresh = true
    end,
})

Tabs.Scanner:Button({
    Title = "Next hierarchy page",
    Icon = "chevron-right",

    Callback = function()
        local record = Records[State.SelectedPlayer]
        local count = record and record.Scan
            and #record.Scan.Entries
            or 0

        local pages = math.max(math.ceil(count / 20), 1)

        State.ScannerPage = math.min(State.ScannerPage + 1, pages)
        State.ScannerRefresh = true
    end,
})

local function updateScannerDisplay()
    local player = State.SelectedPlayer
    local record = player and Records[player]

    if not record then
        setParagraph(UI.ScannerStatus, "No available character selected.")
        setParagraph(UI.ScannerDetails, "Select a current player.")
        setParagraph(UI.Hierarchy, "No scan available.")
        return
    end

    setParagraph(UI.ScannerStatus, string.format(
        "%s\nProgress: %d%%\nCharacter: %s%s",
        record.Status,
        record.Progress,
        record.Character and record.Character.Name or "Not spawned",
        record.Error and ("\nError: " .. record.Error) or ""
    ))

    local scan = record.Scan

    if not scan then
        setParagraph(UI.ScannerDetails, "Waiting for a completed scan.")
        setParagraph(UI.Hierarchy, "No completed hierarchy yet.")

        if ManualOptionsSignature ~= "empty:" .. tostring(player.UserId) then
            ScannerUpdating = true
            UI.ManualComponent:Refresh({ "Automatic" })
            UI.ManualComponent:Select("Automatic")
            ScannerUpdating = false

            ManualOptionsSignature = "empty:" .. tostring(player.UserId)
        end

        return
    end

    local data = liveData(record)
    local manualKey = Config.V2.ManualTargets[tostring(player.UserId)]
    local manualExists = manualKey and scan.ByKey[manualKey] ~= nil

    local controller

    if scan.Humanoid then
        controller = "Humanoid"
    elseif finite(scan.Character:GetAttribute("Health"))
        and finite(scan.Character:GetAttribute("MaxHealth")) then

        controller = "Model Health / MaxHealth attributes"
    else
        controller = "No supported live-health controller"
    end

    setParagraph(UI.ScannerDetails, string.format(
        "Structure: %s\n"
            .. "Controller: %s\n"
            .. "Components: %d | Targetable candidates: %d | Excluded: %d\n"
            .. "Last scan: %.1f ms\n"
            .. "Live targeting: %s\n"
            .. "Manual selection: %s\n"
            .. "Recognition uses names, joints, attributes, and geometric fallback.",
        scan.Rig,
        controller,
        #scan.Entries,
        #scan.Parts,
        scan.Excluded,
        scan.Duration * 1000,
        data and "Supported and alive" or "Unavailable / dead / incomplete",
        manualKey
            and (manualExists and manualKey or "Saved component is currently missing")
            or "Automatic"
    ))

    local signature = tostring(player.UserId)
        .. ":" .. tostring(record.Completed)
        .. ":" .. tostring(manualKey)

    if signature ~= ManualOptionsSignature then
        local options = { "Automatic" }

        for _, item in ipairs(scan.Parts) do
            table.insert(options, item.Key)
        end

        ScannerUpdating = true
        UI.ManualComponent:Refresh(options)
        UI.ManualComponent:Select(
            manualExists and manualKey or "Automatic"
        )
        ScannerUpdating = false

        ManualOptionsSignature = signature
    end

    local pageSize = 20
    local pages = math.max(math.ceil(#scan.Entries / pageSize), 1)

    State.ScannerPage = math.clamp(State.ScannerPage, 1, pages)

    local lines = {
        string.format(
            "%s [Model]\nPage %d / %d — %d total components",
            scan.Character.Name,
            State.ScannerPage,
            pages,
            #scan.Entries
        ),
    }

    local first = (State.ScannerPage - 1) * pageSize + 1
    local last = math.min(first + pageSize - 1, #scan.Entries)

    for index = first, last do
        local entry = scan.Entries[index]

        local suffix = entry.Targetable
            and ("TARGETABLE: " .. entry.Reason)
            or entry.Reason

        table.insert(lines, entry.Key
            .. (suffix ~= "" and (" — " .. suffix) or ""))
    end

    if #scan.Entries == 0 then
        table.insert(lines, "The character has no descendants.")
    end

    setParagraph(UI.Hierarchy, table.concat(lines, "\n"))
end

--==============================================================
-- 19. HITBOX MENU
--==============================================================

paragraph(
    Tabs.Hitbox,
    "Visual-only hitbox configuration",
    "These boxes visualize configured dimensions around a component. "
        .. "They do not enlarge real body parts or alter hit registration. "
        .. "Dimensions are in studs; transparency 100% hides that layer."
)

section(Tabs.Hitbox, "Main controls")

toggle(Tabs.Hitbox, "Enable hitbox visualization", "Hitbox", "Enabled")
dropdown(Tabs.Hitbox, "Hitbox anchor component", "Hitbox", "TargetPart")

slider(Tabs.Hitbox, "Width X — studs", "Hitbox", "X", 0.1)
slider(Tabs.Hitbox, "Height Y — studs", "Hitbox", "Y", 0.1)
slider(Tabs.Hitbox, "Depth Z — studs", "Hitbox", "Z", 0.1)

UI.HitboxDimensions = paragraph(
    Tabs.Hitbox,
    "Current dimensions",
    "Preparing..."
)

section(Tabs.Hitbox, "Appearance")

toggle(Tabs.Hitbox, "Show hitbox fill", "Hitbox", "Fill")
slider(Tabs.Hitbox, "Fill transparency — percent", "Hitbox", "Transparency")

toggle(Tabs.Hitbox, "Show hitbox outlines", "Hitbox", "Outlines")

slider(
    Tabs.Hitbox,
    "Outline thickness — studs",
    "Hitbox",
    "OutlineThickness",
    0.01
)

slider(
    Tabs.Hitbox,
    "Outline transparency — percent",
    "Hitbox",
    "OutlineTransparency"
)

colorpicker(Tabs.Hitbox, "Default hitbox color", "Hitbox", "Color")
toggle(Tabs.Hitbox, "Use shared team colors", "Hitbox", "TeamColors")
toggle(Tabs.Hitbox, "Show hitboxes through walls", "Hitbox", "ThroughWalls")

section(Tabs.Hitbox, "Filtering and performance")

toggle(Tabs.Hitbox, "Exclude teammates", "Hitbox", "TeamCheck")
toggle(Tabs.Hitbox, "Enable specific-team hitboxes", "Hitbox", "SpecificTeams")

slider(
    Tabs.Hitbox,
    "Maximum visualization distance — studs",
    "Hitbox",
    "MaxDistance"
)

slider(
    Tabs.Hitbox,
    "Maximum visible hitboxes — nearest first",
    "Hitbox",
    "MaxVisible"
)

--==============================================================
-- 20. SHARED TEAM MENU
--==============================================================

paragraph(
    Tabs.Teams,
    "One team selection, shared across modules",
    "Select teams once here. Each module has its own "
        .. "'specific-team' switch. An enabled switch with an empty "
        .. "selection allows nobody. Team checks still exclude teammates "
        .. "even when their team is selected. Team names identify saved selections."
)

local TeamUpdating = false
local EditedTeam = NeutralToken

UI.TeamSelection = Tabs.Teams:Dropdown({
    Title = "Allowed teams — shared selection",
    Values = teamOptions(),
    Value = Config.Shared.SelectedTeams,
    Multi = true,
    AllowNone = true,

    Callback = function(value)
        if TeamUpdating then
            return
        end

        Config.Shared.SelectedTeams = cleanStringArray(value)
        changed()
    end,
})

UI.TeamSummary = paragraph(Tabs.Teams, "Shared team status", "Preparing...")

section(Tabs.Teams, "Shared team color overrides")

UI.EditedTeam = Tabs.Teams:Dropdown({
    Title = "Team to customize",
    Values = teamOptions(),
    Value = EditedTeam,
    Multi = false,
    AllowNone = false,

    Callback = function(value)
        if type(value) == "string" then
            EditedTeam = value
            State.ScannerRefresh = true
        end
    end,
})

Tabs.Teams:Colorpicker({
    Title = "Apply color to the selected team",
    Default = Color3.fromRGB(102, 227, 255),

    Callback = function(value)
        if State.Running and typeof(value) == "Color3" then
            Config.Shared.TeamColors[EditedTeam] = "#" .. value:ToHex()
            changed()
        end
    end,
})

Tabs.Teams:Button({
    Title = "Clear selected team's color override",
    Icon = "rotate-ccw",

    Callback = function()
        Config.Shared.TeamColors[EditedTeam] = nil
        changed()
    end,
})

Tabs.Teams:Button({
    Title = "Select all current teams",
    Icon = "check-check",

    Callback = function()
        Config.Shared.SelectedTeams = teamOptions()

        TeamUpdating = true
        UI.TeamSelection:Select(Config.Shared.SelectedTeams)
        TeamUpdating = false

        changed()
    end,
})

Tabs.Teams:Button({
    Title = "Clear shared team selection",
    Icon = "x",

    Callback = function()
        Config.Shared.SelectedTeams = {}

        TeamUpdating = true
        UI.TeamSelection:Select({})
        TeamUpdating = false

        changed()
    end,
})

local function refreshTeams()
    if not State.Running then
        return
    end

    local options = teamOptions()

    TeamUpdating = true
    UI.TeamSelection:Refresh(options)
    UI.TeamSelection:Select(Config.Shared.SelectedTeams)

    UI.EditedTeam:Refresh(options)

    if not table.find(options, EditedTeam) then
        EditedTeam = NeutralToken
    end

    UI.EditedTeam:Select(EditedTeam)
    TeamUpdating = false

    changed()
end

--==============================================================
-- 21. ESP / APPEARANCE / SYSTEM MENUS
--==============================================================

section(Tabs.Visuals, "Player overlays")

toggle(Tabs.Visuals, "Player highlights", "V1", "Highlights")
toggle(Tabs.Visuals, "Names above players", "V1", "Names")
toggle(Tabs.Visuals, "Health bars — right side", "V1", "HealthBars")
toggle(Tabs.Visuals, "Bounding boxes", "V1", "Boxes")
toggle(Tabs.Visuals, "Distance labels — studs", "V1", "Distances")
toggle(Tabs.Visuals, "Numeric health", "V1", "HealthNumbers")

section(Tabs.Visuals, "Visibility and teams")

toggle(Tabs.Visuals, "Visual team check", "V1", "VisualTeamCheck")

toggle(
    Tabs.Visuals,
    "Use shared team selection for ESP",
    "V1",
    "VisualSpecificTeams"
)

toggle(Tabs.Visuals, "Show visuals through walls", "V1", "ThroughWalls")

section(Tabs.Appearance, "V1 FOV")

colorpicker(Tabs.Appearance, "FOV color V1", "V1", "FOVColor")

slider(
    Tabs.Appearance,
    "FOV outline thickness V1",
    "V1",
    "FOVThickness",
    0.5
)

section(Tabs.Appearance, "Player visuals")

toggle(Tabs.Appearance, "Use shared player team colors", "V1", "TeamColors")

colorpicker(
    Tabs.Appearance,
    "Default player visual color",
    "V1",
    "VisualColor"
)

slider(
    Tabs.Appearance,
    "Highlight fill opacity — percent",
    "V1",
    "HighlightOpacity"
)

slider(Tabs.Appearance, "Label text size", "V1", "TextSize")

section(Tabs.Appearance, "HUD")

toggle(Tabs.Appearance, "Center crosshair", "V1", "Crosshair")

paragraph(
    Tabs.Appearance,
    "Clean HUD",
    "No bottom-left target panel. "
        .. "Scanner and runtime diagnostics remain inside the menu."
)

section(Tabs.System, "Performance")

slider(
    Tabs.System,
    "Player visual updates per second",
    "V1",
    "VisualRefreshRate"
)

slider(
    Tabs.System,
    "V2 target acquisition updates per second",
    "V2",
    "AcquisitionRate"
)

paragraph(
    Tabs.System,
    "Scan scheduling",
    "Scans are cached and invalidated by model changes. "
        .. "At most two scans run concurrently. "
        .. "Large scans yield every 64 components. "
        .. "Camera tracking remains frame-updated."
)

UI.RuntimeStatus = paragraph(Tabs.System, "Runtime status", "Preparing...")
UI.StorageStatus = paragraph(Tabs.System, "Configuration storage", StorageStatus)

Tabs.System:Button({
    Title = "Save configuration now",
    Icon = "save",

    Callback = function()
        saveConfiguration()
        State.SaveDue = nil
        setParagraph(UI.StorageStatus, StorageStatus)
    end,
})

Tabs.System:Button({
    Title = "Release targets / stop activation",
    Icon = "unlink",

    Callback = function()
        resetActivation()
    end,
})

--==============================================================
-- 22. MENU SELECTION NAVIGATION GUARD
--==============================================================

local MenuRoots = {}
local NavigationConnections = {}

for _, key in ipairs({
    "ScreenGui",
    "DropdownGui",
    "TooltipGui",
    "NotificationGui",
}) do
    local root = WindUI[key]

    if typeof(root) == "Instance" then
        table.insert(MenuRoots, root)
    end
end

local function belongsToMenu(object)
    if not object then
        return false
    end

    for _, root in ipairs(MenuRoots) do
        if object == root or object:IsDescendantOf(root) then
            return true
        end
    end

    return false
end

local function clearMenuSelection()
    if belongsToMenu(GuiService.SelectedObject) then
        GuiService.SelectedObject = nil
    end
end

local function guardNavigation(object)
    if not object:IsA("GuiObject")
        or NavigationConnections[object] then
        return
    end

    object.Selectable = false

    local bucket = {}
    NavigationConnections[object] = bucket

    connect(object:GetPropertyChangedSignal("Selectable"), function()
        if State.Running and object.Selectable then
            object.Selectable = false
        end
    end, bucket)

    connect(object.Destroying, function()
        local connections = NavigationConnections[object]

        if connections then
            NavigationConnections[object] = nil
            disconnectAll(connections)
        end
    end, bucket)
end

for _, root in ipairs(MenuRoots) do
    connect(root.DescendantAdded, guardNavigation)

    for _, object in ipairs(root:GetDescendants()) do
        guardNavigation(object)
    end
end

connect(
    GuiService:GetPropertyChangedSignal("SelectedObject"),
    clearMenuSelection
)

clearMenuSelection()

--==============================================================
-- 23. PLAYER LIFECYCLE
--==============================================================

local function addPlayer(player)
    if Records[player] or not State.Running then
        return
    end

    local record = {
        Player = player,
        Character = nil,
        Scan = nil,

        PlayerConnections = {},
        CharacterConnections = {},
        Observed = {},

        Generation = 0,
        Revision = 0,
        Due = 0,
        Dirty = false,
        Busy = false,
        Progress = 0,
        Status = "Waiting for character",
        Error = nil,
        Completed = nil,
    }

    Records[player] = record

    connect(player.CharacterAdded, function(character)
        Scanner.Bind(record, character)
    end, record.PlayerConnections)

    connect(player.CharacterRemoving, function(character)
        if record.Character == character then
            Scanner.Bind(record, nil)
        end

        if player == LocalPlayer then
            resetActivation()
        end
    end, record.PlayerConnections)

    connect(player:GetPropertyChangedSignal("Team"), function()
        State.VisualElapsed = math.huge
        State.Target1 = nil
        State.Target2 = nil
    end, record.PlayerConnections)

    connect(player:GetPropertyChangedSignal("Neutral"), function()
        State.VisualElapsed = math.huge
        State.Target1 = nil
        State.Target2 = nil
    end, record.PlayerConnections)

    Scanner.Bind(record, player.Character)
    createVisual(player)

    refreshPlayerOptions()
end

local function removePlayer(player)
    local record = Records[player]

    if record then
        Records[player] = nil

        record.Generation += 1
        record.Character = nil

        disconnectAll(record.PlayerConnections)
        disconnectAll(record.CharacterConnections)

        for object, bucket in pairs(record.Observed) do
            disconnectAll(bucket)
            record.Observed[object] = nil
        end
    end

    removeVisual(player)
    HitboxModule.Remove(player)

    if State.Target1 and State.Target1.Player == player then
        State.Target1 = nil
    end

    if State.Target2 and State.Target2.Player == player then
        State.Target2 = nil
    end

    if State.SelectedPlayer == player then
        State.SelectedPlayer = LocalPlayer
        State.ScannerPage = 1
        State.ScannerRefresh = true
        ManualOptionsSignature = ""
    end

    refreshPlayerOptions()
end

connect(Players.PlayerAdded, addPlayer)
connect(Players.PlayerRemoving, removePlayer)

for _, player in ipairs(Players:GetPlayers()) do
    addPlayer(player)
end

local TeamConnections = {}

local function watchTeam(team)
    if TeamConnections[team] then
        return
    end

    local bucket = {}
    TeamConnections[team] = bucket

    connect(team:GetPropertyChangedSignal("Name"), refreshTeams, bucket)

    connect(team:GetPropertyChangedSignal("TeamColor"), function()
        State.VisualElapsed = math.huge
    end, bucket)
end

for _, team in ipairs(Teams:GetTeams()) do
    watchTeam(team)
end

connect(Teams.ChildAdded, function(child)
    if child:IsA("Team") then
        watchTeam(child)
        refreshTeams()
    end
end)

connect(Teams.ChildRemoved, function(child)
    local bucket = TeamConnections[child]

    if bucket then
        disconnectAll(bucket)
        TeamConnections[child] = nil
        refreshTeams()
    end
end)

--==============================================================
-- 24. INPUT / CUSTOM KEY CAPTURE
--==============================================================

local function matchesV1(input)
    local key = Config.V1.ActivationKey

    if key == "MouseButton1" or key == "MouseButton2" then
        return input.UserInputType == Enum.UserInputType[key]
    end

    return input.KeyCode == Enum.KeyCode[key]
end

local function matchesV2(input)
    return input.UserInputType == Enum.UserInputType.Keyboard
        and input.KeyCode.Name == Config.V2.Key
end

connect(UserInputService.InputBegan, function(input, processed)
    if not State.Running then
        return
    end

    if State.Binding then
        if input.UserInputType ~= Enum.UserInputType.Keyboard then
            return
        end

        local key = input.KeyCode.Name

        if key == "Escape" then
            State.Binding = false
            return
        end

        if key == "Unknown" or key == "RightShift" then
            return
        end

        State.Binding = false
        setConfig("V2", "Key", key)
        return
    end

    if processed
        or not State.Focused
        or UserInputService:GetFocusedTextBox()
        or GuiService.MenuIsOpen then
        return
    end

    if Config.V1.AimEnabled and matchesV1(input) then
        State.Held1 = true

        if Config.V1.ActivationMode == "Toggle" then
            State.Toggle1 = not State.Toggle1
            State.Target1 = nil
        end
    end

    if Config.V2.Enabled
        and Config.V2.KeybindEnabled
        and matchesV2(input) then

        State.Held2 = true

        if Config.V2.ActivationMode == "Toggle" then
            State.Toggle2 = not State.Toggle2
            State.Target2 = nil
        end
    end
end)

connect(UserInputService.InputEnded, function(input)
    if matchesV1(input) then
        State.Held1 = false

        if Config.V1.ActivationMode == "Hold" then
            State.Target1 = nil
        end
    end

    if matchesV2(input) then
        State.Held2 = false

        if Config.V2.ActivationMode == "Hold" then
            State.Target2 = nil
        end
    end
end)

connect(UserInputService.WindowFocusReleased, function()
    State.Focused = false
    State.Binding = false
    resetActivation()
end)

connect(UserInputService.WindowFocused, function()
    State.Focused = true
end)

connect(UserInputService.TextBoxFocused, function()
    State.Binding = false
    resetActivation()
end)

connect(GuiService.MenuOpened, function()
    State.Binding = false
    resetActivation()
end)

--==============================================================
-- 25. DRAGGABLE FLOATING CONTROL
--==============================================================

local Drag = {
    Input = nil,
    Start = nil,
    StartPosition = nil,
    Moved = false,
    IgnoreActivationUntil = 0,
}

local function clampFloatingPosition(position)
    local size = Canvas.AbsoluteSize

    if size.X <= 0 or size.Y <= 0 then
        return Vector2.new(0.5, 0.5)
    end

    local half = Floating.AbsoluteSize * 0.5

    local x = math.clamp(
        position.X,
        half.X + 6,
        math.max(half.X + 6, size.X - half.X - 6)
    )

    local y = math.clamp(
        position.Y,
        half.Y + 6,
        math.max(half.Y + 6, size.Y - half.Y - 6)
    )

    return Vector2.new(x / size.X, y / size.Y)
end

connect(Floating.InputBegan, function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1
        and input.UserInputType ~= Enum.UserInputType.Touch then
        return
    end

    Drag.Input = input
    Drag.Start = Vector2.new(input.Position.X, input.Position.Y)
    Drag.StartPosition =
        Floating.AbsolutePosition + Floating.AbsoluteSize * 0.5

    Drag.Moved = false
end)

connect(UserInputService.InputChanged, function(input)
    if not Drag.Input then
        return
    end

    local isTouch = Drag.Input.UserInputType
        == Enum.UserInputType.Touch

    if isTouch and input ~= Drag.Input then
        return
    end

    if not isTouch
        and input.UserInputType ~= Enum.UserInputType.MouseMovement then
        return
    end

    local position = Vector2.new(input.Position.X, input.Position.Y)
    local delta = position - Drag.Start

    if delta.Magnitude > 7 then
        Drag.Moved = true
    end

    if Drag.Moved then
        local normalized = clampFloatingPosition(
            Drag.StartPosition + delta
        )

        Floating.Position = UDim2.fromScale(
            normalized.X,
            normalized.Y
        )
    end
end)

connect(UserInputService.InputEnded, function(input)
    if not Drag.Input then
        return
    end

    local touch = Drag.Input.UserInputType == Enum.UserInputType.Touch

    local ended = touch and input == Drag.Input
        or not touch
            and input.UserInputType == Enum.UserInputType.MouseButton1

    if not ended then
        return
    end

    if Drag.Moved then
        Drag.IgnoreActivationUntil = os.clock() + 0.2

        local position =
            Floating.AbsolutePosition + Floating.AbsoluteSize * 0.5

        local normalized = clampFloatingPosition(position)

        Config.V2.FloatingX = normalized.X
        Config.V2.FloatingY = normalized.Y
        changed()
    end

    Drag.Input = nil
end)

connect(Floating.Activated, function()
    if not State.Running
        or Drag.Moved
        or os.clock() < Drag.IgnoreActivationUntil then
        return
    end

    local enabled = not Config.V2.Enabled
    setConfig("V2", "Enabled", enabled)

    -- Floating activation can arm V2 without a physical keyboard.
    State.TouchArmed2 = enabled
    UI.V2Enabled:Set(enabled, false, true)
end)

local LastFloatingEnabled
local FloatingTween

local function updateFloating()
    Floating.Visible = Config.V2.FloatingToggle
    Floating.Text = Config.V2.Enabled and "V2 ON" or "V2 OFF"

    if LastFloatingEnabled ~= Config.V2.Enabled then
        LastFloatingEnabled = Config.V2.Enabled

        if FloatingTween then
            FloatingTween:Cancel()
        end

        FloatingTween = TweenService:Create(
            Floating,
            TweenInfo.new(0.16),
            {
                BackgroundColor3 = Config.V2.Enabled
                    and Color3.fromRGB(20, 105, 125)
                    or Color3.fromRGB(30, 35, 48),
            }
        )

        FloatingTween:Play()
    end

    if not Drag.Input and State.ScreenSize.X > 0 then
        local intended = Vector2.new(
            Config.V2.FloatingX * State.ScreenSize.X,
            Config.V2.FloatingY * State.ScreenSize.Y
        )

        local normalized = clampFloatingPosition(intended)

        Floating.Position = UDim2.fromScale(
            normalized.X,
            normalized.Y
        )
    end
end

--==============================================================
-- 26. DIAGNOSTICS — MENU ONLY
--==============================================================

local function updateDiagnostics()
    local ready = 0
    local queued = 0
    local errors = 0
    local total = 0

    for _, record in pairs(Records) do
        total += 1

        if record.Scan then
            ready += 1
        end

        if record.Dirty then
            queued += 1
        end

        if record.Error then
            errors += 1
        end
    end

    local target = State.Target2 or State.Target1
    local targetText = target and target.Player.DisplayName or "None"

    setParagraph(UI.RuntimeStatus, string.format(
        "Camera controller: %s\n"
            .. "Current target: %s\n"
            .. "Cached characters: %d / %d\n"
            .. "Queued scans: %d | Active workers: %d | Scan errors: %d\n"
            .. "Completed scans: %d | Visible hitboxes: %d",
        State.ActiveSystem,
        targetText,
        ready,
        total,
        queued,
        State.ScanWorkers,
        errors,
        State.ScanCount,
        State.VisibleHitboxes
    ))

    setParagraph(
        UI.StorageStatus,
        StorageStatus
            .. (StorageWarning ~= "" and ("\n" .. StorageWarning) or "")
    )

    if not State.Binding then
        setParagraph(UI.KeyStatus, string.format(
            "Key: %s | Mode: %s\n"
                .. "Key requirement: %s\n"
                .. "Floating button can enable and arm V2 for touch.",
            Config.V2.Key,
            Config.V2.ActivationMode,
            Config.V2.KeybindEnabled and "Enabled" or "Disabled — always active"
        ))
    end

    setParagraph(UI.HitboxDimensions, string.format(
        "X %.1f × Y %.1f × Z %.1f studs\n"
            .. "Fill transparency: %.0f%% | Outline transparency: %.0f%%",
        Config.Hitbox.X,
        Config.Hitbox.Y,
        Config.Hitbox.Z,
        Config.Hitbox.Transparency,
        Config.Hitbox.OutlineTransparency
    ))

    setParagraph(UI.TeamSummary, string.format(
        "Selected teams: %d\n%s\n"
            .. "Color-edit target: %s\n"
            .. "V1: %s | V2: %s | ESP: %s | Hitboxes: %s",
        #Config.Shared.SelectedTeams,
        #Config.Shared.SelectedTeams > 0
            and table.concat(Config.Shared.SelectedTeams, ", ")
            or "None selected",
        EditedTeam,
        Config.V1.SpecificTeams and "Allowlist ON" or "Allowlist OFF",
        Config.V2.SpecificTeams and "Allowlist ON" or "Allowlist OFF",
        Config.V1.VisualSpecificTeams and "Allowlist ON" or "Allowlist OFF",
        Config.Hitbox.SpecificTeams and "Allowlist ON" or "Allowlist OFF"
    ))

    updateScannerDisplay()
    State.ScannerRefresh = false
end

--==============================================================
-- 27. CLEANUP
--==============================================================

local function cleanup()
    if not State.Running then
        return
    end

    saveConfiguration()

    State.Running = false
    State.Binding = false
    resetActivation()

    RunService:UnbindFromRenderStep(RenderName)
    clearMenuSelection()

    disconnectAll(Connections)

    for _, record in pairs(Records) do
        record.Generation += 1
        record.Character = nil

        disconnectAll(record.PlayerConnections)
        disconnectAll(record.CharacterConnections)

        for object, bucket in pairs(record.Observed) do
            disconnectAll(bucket)
            record.Observed[object] = nil
        end
    end

    for object, bucket in pairs(NavigationConnections) do
        disconnectAll(bucket)
        NavigationConnections[object] = nil
    end

    for team, bucket in pairs(TeamConnections) do
        disconnectAll(bucket)
        TeamConnections[team] = nil
    end

    if FloatingTween then
        FloatingTween:Cancel()
        FloatingTween = nil
    end

    Overlay:Destroy()
    Artifacts:Destroy()

    table.clear(Records)
    table.clear(Visuals)
    table.clear(Hitboxes)
    table.clear(MenuRoots)

    Session.Cleanup = nil
end

Window:OnDestroy(cleanup)

Tabs.System:Button({
    Title = "Unload — remove menu and all visuals",
    Icon = "trash-2",

    Callback = function()
        cleanup()
        Window:Destroy()
    end,
})

Session.Cleanup = function()
    cleanup()

    if not Window.Destroyed then
        Window:Destroy()
    end
end

--==============================================================
-- 28. BACKGROUND SCHEDULER
--==============================================================

connect(RunService.Heartbeat, function(deltaTime)
    if not State.Running then
        return
    end

    local now = os.clock()

    if State.Binding and now >= State.BindingExpires then
        State.Binding = false
    end

    if State.SaveDue and now >= State.SaveDue then
        State.SaveDue = nil
        saveConfiguration()
    end

    -- Prioritize the manually selected character.
    local selected = Records[State.SelectedPlayer]

    if selected
        and selected.Dirty
        and not selected.Busy
        and selected.Due <= now
        and State.ScanWorkers < 2 then

        Scanner.Start(selected)
    end

    for _, record in pairs(Records) do
        if State.ScanWorkers >= 2 then
            break
        end

        if record.Dirty
            and not record.Busy
            and record.Due <= now then

            Scanner.Start(record)
        end
    end

    State.StatusElapsed += deltaTime

    if State.StatusElapsed >= 0.25 then
        State.StatusElapsed = 0
        updateDiagnostics()
    end
end)

--==============================================================
-- 29. RENDER LOOP
--==============================================================

local function activation(mode, held, toggled)
    return mode == "Always"
        or mode == "Hold" and held
        or mode == "Toggle" and toggled
end

local function hideEverything()
    Circle1.Frame.Visible = false
    Circle2.Frame.Visible = false
    Crosshair.Visible = false

    for _, visual in pairs(Visuals) do
        hideVisual(visual)
    end

    for _, visual in pairs(Hitboxes) do
        HitboxModule.Hide(visual)
    end

    State.VisibleHitboxes = 0
end

local function updateCircle(circle, settings, visibleValue)
    circle.Frame.Size = UDim2.fromOffset(
        settings.FOV * 2,
        settings.FOV * 2
    )

    circle.Frame.Visible = visibleValue
    circle.Stroke.Color = color(settings.FOVColor)
    circle.Stroke.Thickness = settings.FOVThickness
end

RunService:BindToRenderStep(
    RenderName,
    Enum.RenderPriority.Camera.Value + 1,

    function(deltaTime)
        if not State.Running then
            return
        end

        local camera = workspace.CurrentCamera

        if not camera then
            State.Target1 = nil
            State.Target2 = nil
            State.ActiveSystem = "No camera"

            hideEverything()
            return
        end

        updateScreenGeometry(camera)
        updateFloating()

        if State.ScreenSize.X <= 0 or State.ScreenSize.Y <= 0 then
            hideEverything()
            return
        end

        local origin = overlayCenter()

        -- Both rings use screen-relative centering.
        -- Their positions are never overwritten with viewport offsets.
        updateCircle(
            Circle1,
            Config.V1,
            Config.V1.ShowFOV
        )

        -- V2 ring only appears while the V2 module is enabled.
        updateCircle(
            Circle2,
            Config.V2,
            Config.V2.Enabled and Config.V2.ShowFOV
        )

        Crosshair.Visible = Config.V1.Crosshair

        local ownCharacter, ownHumanoid = v1Character(LocalPlayer)
        local ownSmartData = liveData(Records[LocalPlayer])

        local alive = ownCharacter ~= nil
            and ownHumanoid ~= nil
            or ownSmartData ~= nil

        local inputAllowed = State.Focused
            and alive
            and not State.Binding
            and not GuiService.MenuIsOpen
            and UserInputService:GetFocusedTextBox() == nil

        local active2 = Config.V2.Enabled
            and (
                State.TouchArmed2
                or not Config.V2.KeybindEnabled
                or activation(
                    Config.V2.ActivationMode,
                    State.Held2,
                    State.Toggle2
                )
            )

        local active1 = Config.V1.AimEnabled
            and Config.V1.Strength > 0
            and activation(
                Config.V1.ActivationMode,
                State.Held1,
                State.Toggle1
            )

        if inputAllowed and active2 then
            -- One camera writer: V2 owns it while active.
            State.ActiveSystem = "Smart Aim V2"
            State.Target1 = nil

            local target = chooseV2(camera, origin)

            if target
                and target.ScreenDistance > Config.V2.Deadzone then

                local smoothness = Config.V2.Smoothness
                local alpha

                if smoothness <= 0 then
                    alpha = 1
                else
                    local normalized = smoothness / 100
                    local response = 2 + (1 - normalized) ^ 2 * 58

                    alpha = 1 - math.exp(-response * deltaTime)
                end

                turnCamera(camera, target.Part, alpha)
            end

        elseif inputAllowed and active1 then
            State.ActiveSystem = "Aim V1"
            State.Target2 = nil
            State.NextAcquire2 = 0

            local target = chooseV1(camera, origin)

            if target then
                local strength = Config.V1.Strength / 100

                local alpha = strength >= 1
                    and 1
                    or 1 - (1 - strength) ^ (deltaTime * 60)

                turnCamera(camera, target.Part, alpha)
            end

        else
            State.Target1 = nil
            State.Target2 = nil
            State.NextAcquire2 = 0
            State.ActiveSystem = inputAllowed and "Idle" or "Paused"
        end

        State.VisualElapsed += deltaTime

        if State.VisualElapsed >= 1 / Config.V1.VisualRefreshRate then
            State.VisualElapsed = 0

            -- Refresh with the final camera orientation for this frame.
            for player, visual in pairs(Visuals) do
                updateVisual(player, visual, camera)
            end

            HitboxModule.Update(camera)
        end
    end
)

updateDiagnostics()
updateFloating()
