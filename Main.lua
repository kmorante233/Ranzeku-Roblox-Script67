--[[
    TARGETING & VISUALS — LITE
    By 00B_qruel

    Use only in an experience you own or have permission to test.
    Unload older versions before running.

    KEPT
      - Smart Aim V2
      - Automatic, event-driven rig detection
      - Centered FOV circle
      - Independent through-wall player highlights
      - Player names and health bars
      - Basic team checks
      - Draggable mobile control
      - Visual-only hitbox: one toggle and one size slider
      - Optional settings storage
      - Cleanup / unload

    REMOVED
      - Aim V1
      - Manual character scanner and hierarchy pages
      - Per-player manual component selection
      - Shared team allowlists and custom team colors
      - Bounding boxes, distance labels, numeric health labels
      - Extra appearance / performance / diagnostic menus

    IMPORTANT
      - Hitboxes are visual-only.
      - Real character sizes, collisions, and hits are not modified.
      - Highlight visibility is independent of the aim wall check.
      - Unstreamed characters cannot be drawn by this client.

    Optional custom-rig attributes:
      BasePart:
        AimTargetable = false / true
        AimRole = "Head" / "Torso" / "Root"

      Character Model without a Humanoid:
        Health = 100
        MaxHealth = 100
]]

--==============================================================
-- 01. SERVICES / PREVIOUS SESSION
--==============================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local GuiService = game:GetService("GuiService")

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

-- Matches the previous script's session key for automatic cleanup.
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

-- Same loader environment as the previous script.
local loaderOK, WindUI = pcall(function()
    local source = game:HttpGet(
        "https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"
    )

    local chunk = loadstring(source)
    assert(chunk, "The interface library could not be compiled.")

    return chunk()
end)

assert(
    loaderOK and WindUI,
    "Unable to load the interface library: " .. tostring(WindUI)
)

--==============================================================
-- 02. CONFIGURATION
--==============================================================

local Config = {
    Version = 3,

    Aim = {
        Enabled = false,
        KeybindEnabled = true,
        Key = "E",
        ActivationMode = "Hold",

        TargetPart = "Auto",
        Priority = "Crosshair",
        StickyTarget = true,

        Smoothness = 50,
        FOV = 180,
        ShowFOV = true,
        MaxDistance = 1500,

        TeamCheck = true,
        WallCheck = true,
        ForceFieldCheck = true,

        FloatingToggle = true,
        FloatingX = 0.90,
        FloatingY = 0.65,
    },

    Visuals = {
        Highlights = true,
        Names = false,
        HealthBars = false,

        TeamCheck = true,

        -- Applies ONLY to names and health bars.
        -- Highlights always use AlwaysOnTop.
        OtherVisualsThroughWalls = false,
    },

    Hitbox = {
        Enabled = false,
        Size = 4,
    },
}

local Limits = {
    ["Aim.Smoothness"] = { 0, 100 },
    ["Aim.FOV"] = { 20, 800 },
    ["Aim.MaxDistance"] = { 50, 5000 },
    ["Aim.FloatingX"] = { 0, 1 },
    ["Aim.FloatingY"] = { 0, 1 },

    ["Hitbox.Size"] = { 0.2, 30 },
}

local Choices = {
    ["Aim.Key"] = {
        "E",
        "Q",
        "F",
        "LeftAlt",
        "MouseButton2",
    },

    ["Aim.ActivationMode"] = {
        "Hold",
        "Toggle",
        "Always",
    },

    ["Aim.TargetPart"] = {
        "Auto",
        "Head",
        "Torso",
        "Root",
    },

    ["Aim.Priority"] = {
        "Crosshair",
        "Distance",
        "Lowest health",
    },
}

-- Internal constants, not extra menu controls.
local STYLE = {
    PlayerColor = Color3.fromRGB(110, 150, 255),
    FOVColor = Color3.fromRGB(102, 227, 255),
    HitboxColor = Color3.fromRGB(102, 227, 255),

    HighlightFillTransparency = 0.65,
    HighlightOutlineTransparency = 0.10,

    TextSize = 13,
    VisualRefreshRate = 30,
    AcquisitionRate = 20,

    HitboxTransparency = 0.70,
    HitboxMaxDistance = 1500,
    HitboxMaxVisible = 32,
}

local function finite(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

--==============================================================
-- 03. OPTIONAL SETTINGS STORAGE
--==============================================================

-- Separate from the old configuration so removed settings cannot
-- restore the old highlight visibility behavior.
local SaveFile = string.format(
    "TargetingLite_%s_%s.json",
    tostring(game.PlaceId),
    tostring(LocalPlayer.UserId)
)

local CanReadFile = type(readfile) == "function"
local CanWriteFile = type(writefile) == "function"

local function mergeConfiguration(saved)
    if type(saved) ~= "table" then
        return
    end

    for _, group in ipairs({ "Aim", "Visuals", "Hitbox" }) do
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
                    local limit = Limits[path]

                    if finite(value) and limit then
                        Config[group][key] = math.clamp(
                            value,
                            limit[1],
                            limit[2]
                        )
                    end

                elseif type(default) == "string" then
                    local options = Choices[path]

                    if options and table.find(options, value) then
                        Config[group][key] = value
                    end
                end
            end
        end
    end
end

do
    local json

    if CanReadFile then
        local ok, result = pcall(readfile, SaveFile)

        if ok and type(result) == "string" then
            json = result
        end
    end

    if not json and type(Session.LiteJSON) == "string" then
        json = Session.LiteJSON
    end

    if json then
        local ok, decoded = pcall(function()
            return HttpService:JSONDecode(json)
        end)

        if ok then
            mergeConfiguration(decoded)
        end
    end
end

local function saveConfiguration()
    local ok, json = pcall(function()
        return HttpService:JSONEncode(Config)
    end)

    if not ok then
        return false, "Could not encode settings."
    end

    Session.LiteJSON = json

    if CanWriteFile then
        local written = pcall(writefile, SaveFile, json)

        if written then
            return true, "Settings saved."
        end

        return false, "File save failed; settings remain in this session."
    end

    return true, "Settings saved for this session."
end

--==============================================================
-- 04. RUNTIME / CONNECTION OWNERSHIP
--==============================================================

local State = {
    Running = true,
    Focused = true,

    Held = false,
    Toggled = false,
    TouchArmed = false,

    Target = nil,
    NextAcquire = 0,

    ScreenSize = Vector2.zero,
    LastViewport = Vector2.zero,
    ProjectionOffset = Vector2.zero,

    VisualElapsed = math.huge,
    SaveDue = nil,

    ScanWorkers = 0,
}

local Records = {}
local Connections = {}
local NavigationConnections = {}
local MenuRoots = {}

local RenderName = "TargetingLite_" .. HttpService:GenerateGUID(false)

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
    State.Held = false
    State.Toggled = false
    State.TouchArmed = false

    State.Target = nil
    State.NextAcquire = 0
end

local function changed()
    State.Target = nil
    State.NextAcquire = 0
    State.VisualElapsed = math.huge
    State.SaveDue = os.clock() + 0.8
end

local function setConfig(group, key, value)
    if Config[group][key] == value then
        return
    end

    Config[group][key] = value

    if group == "Aim" and (
        key == "Enabled"
        or key == "Key"
        or key == "ActivationMode"
        or key == "KeybindEnabled"
    ) then
        resetActivation()
    end

    changed()
end

local function make(className, properties, parent)
    local object = Instance.new(className)

    for key, value in pairs(properties) do
        object[key] = value
    end

    object.Parent = parent
    return object
end

--==============================================================
-- 05. WINDOW
--==============================================================

local initialViewport = workspace.CurrentCamera
    and workspace.CurrentCamera.ViewportSize
    or Vector2.new(1000, 700)

local Window = WindUI:CreateWindow({
    Title = "Targeting & Visuals — By 00B_qruel",
    Author = "By 00B_qruel",
    Icon = "scan",
    Folder = "TargetingLite",

    Size = UDim2.fromOffset(
        math.clamp(initialViewport.X - 36, 340, 620),
        math.clamp(initialViewport.Y - 60, 300, 520)
    ),

    MinSize = Vector2.new(320, 280),
    SideBarWidth = 150,

    AutoScale = true,
    Resizable = true,
    NewElements = true,
    Theme = "Dark",

    ToggleKey = Enum.KeyCode.RightShift,
})

local Tabs = {
    Aim = Window:Tab({
        Title = "Smart Aim V2",
        Icon = "crosshair",
    }),

    Visuals = Window:Tab({
        Title = "Player Visuals",
        Icon = "eye",
    }),

    Hitbox = Window:Tab({
        Title = "Hitbox",
        Icon = "box",
    }),

    System = Window:Tab({
        Title = "System",
        Icon = "settings",
    }),
}

local SyncingControls = false
local AimToggle

local function section(tab, title)
    return tab:Section({
        Title = title,
    })
end

local function paragraph(tab, title, description)
    return tab:Paragraph({
        Title = title,
        Desc = description,
    })
end

local function toggle(tab, title, group, key)
    return tab:Toggle({
        Title = title,
        Value = Config[group][key],

        Callback = function(value)
            if State.Running and not SyncingControls then
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

            if State.Running
                and not SyncingControls
                and finite(number) then
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
    local values = Choices[group .. "." .. key]

    return tab:Dropdown({
        Title = title,
        Values = values,
        Value = Config[group][key],

        Multi = false,
        AllowNone = false,

        Callback = function(value)
            if State.Running
                and not SyncingControls
                and table.find(values, value) then
                setConfig(group, key, value)
            end
        end,
    })
end

-- Aim menu.
section(Tabs.Aim, "Activation")

AimToggle = toggle(
    Tabs.Aim,
    "Enable Smart Aim V2",
    "Aim",
    "Enabled"
)

toggle(
    Tabs.Aim,
    "Require activation key",
    "Aim",
    "KeybindEnabled"
)

dropdown(Tabs.Aim, "Activation key", "Aim", "Key")
dropdown(Tabs.Aim, "Activation mode", "Aim", "ActivationMode")

toggle(
    Tabs.Aim,
    "Show movable aim button",
    "Aim",
    "FloatingToggle"
)

section(Tabs.Aim, "Targeting")

dropdown(Tabs.Aim, "Preferred component", "Aim", "TargetPart")
dropdown(Tabs.Aim, "Target priority", "Aim", "Priority")

toggle(
    Tabs.Aim,
    "Keep current valid target",
    "Aim",
    "StickyTarget"
)

slider(
    Tabs.Aim,
    "Smoothness — 0 instant / 100 soft",
    "Aim",
    "Smoothness"
)

slider(
    Tabs.Aim,
    "Maximum distance — studs",
    "Aim",
    "MaxDistance"
)

section(Tabs.Aim, "Checks")

toggle(Tabs.Aim, "Ignore teammates", "Aim", "TeamCheck")
toggle(Tabs.Aim, "Aim wall check", "Aim", "WallCheck")

toggle(
    Tabs.Aim,
    "Ignore ForceField targets",
    "Aim",
    "ForceFieldCheck"
)

section(Tabs.Aim, "Field of view")

toggle(Tabs.Aim, "Show centered FOV circle", "Aim", "ShowFOV")
slider(Tabs.Aim, "FOV radius — pixels", "Aim", "FOV")

-- Visual menu.
section(Tabs.Visuals, "Player overlays")

toggle(
    Tabs.Visuals,
    "Player highlights — through walls",
    "Visuals",
    "Highlights"
)

toggle(
    Tabs.Visuals,
    "Names above players",
    "Visuals",
    "Names"
)

toggle(
    Tabs.Visuals,
    "Health bars",
    "Visuals",
    "HealthBars"
)

section(Tabs.Visuals, "Visibility")

toggle(
    Tabs.Visuals,
    "Ignore teammates",
    "Visuals",
    "TeamCheck"
)

toggle(
    Tabs.Visuals,
    "Names and health bars through walls",
    "Visuals",
    "OtherVisualsThroughWalls"
)

paragraph(
    Tabs.Visuals,
    "Independent highlights",
    "Highlights always display through walls when enabled. "
        .. "The aim wall check and the names / health-bar wall setting "
        .. "do not disable highlights. "
        .. "Turn off Ignore teammates to include your own team."
)

-- Exactly one hitbox toggle and one size slider.
toggle(
    Tabs.Hitbox,
    "Enable visual hitbox",
    "Hitbox",
    "Enabled"
)

slider(
    Tabs.Hitbox,
    "Hitbox size — studs",
    "Hitbox",
    "Size",
    0.1
)

-- System menu.
paragraph(Tabs.System, "Owner", "By 00B_qruel")

paragraph(
    Tabs.System,
    "Controls",
    "RightShift opens or closes the menu. "
        .. "The movable aim button can arm aiming without a keyboard. "
        .. "Hitboxes are visual-only."
)

Tabs.System:Button({
    Title = "Save settings",
    Icon = "save",

    Callback = function()
        local _, message = saveConfiguration()
        State.SaveDue = nil

        pcall(function()
            WindUI:Notify({
                Title = "Settings",
                Content = message,
                Duration = 3,
                Icon = "save",
            })
        end)
    end,
})

Tabs.System:Button({
    Title = "Release current target",
    Icon = "unlink",

    Callback = function()
        resetActivation()
    end,
})

--==============================================================
-- 06. OVERLAY / FOV / MOBILE BUTTON
--==============================================================

local Overlay = make("ScreenGui", {
    Name = "TargetingLiteOverlay",
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
    Name = "TargetingLiteClientVisuals",
}, workspace)

local FOVCircle = make("Frame", {
    Name = "FOV",

    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),

    BackgroundTransparency = 1,
    BorderSizePixel = 0,

    Active = false,
    Selectable = false,
    Visible = false,
}, Canvas)

make("UICorner", {
    CornerRadius = UDim.new(1, 0),
}, FOVCircle)

make("UIStroke", {
    Color = STYLE.FOVColor,
    Thickness = 1.5,
    Transparency = 0.15,
}, FOVCircle)

local Floating = make("TextButton", {
    Name = "FloatingAim",

    AnchorPoint = Vector2.new(0.5, 0.5),

    Position = UDim2.fromScale(
        Config.Aim.FloatingX,
        Config.Aim.FloatingY
    ),

    Size = UDim2.fromOffset(126, 46),

    BackgroundColor3 = Color3.fromRGB(30, 35, 48),
    TextColor3 = Color3.new(1, 1, 1),

    Font = Enum.Font.GothamBold,
    TextSize = 14,
    Text = "AIM OFF",

    AutoButtonColor = false,
    Selectable = false,
    Active = true,
    ZIndex = 30,

    Visible = Config.Aim.FloatingToggle,
}, Canvas)

make("UICorner", {
    CornerRadius = UDim.new(0, 14),
}, Floating)

make("UIStroke", {
    Color = STYLE.FOVColor,
    Thickness = 1.2,
    Transparency = 0.15,
}, Floating)

--==============================================================
-- 07. PROJECTION / TEAMS / WALL CHECK
--==============================================================

local RayParameters = RaycastParams.new()
RayParameters.FilterType = Enum.RaycastFilterType.Exclude
RayParameters.IgnoreWater = true

local function sameTeam(player)
    return not LocalPlayer.Neutral
        and not player.Neutral
        and LocalPlayer.Team ~= nil
        and LocalPlayer.Team == player.Team
end

local function teamAllowed(player, checkTeams)
    return player ~= LocalPlayer
        and (not checkTeams or not sameTeam(player))
end

local function updateScreenGeometry(camera)
    local size = Canvas.AbsoluteSize
    local viewport = camera.ViewportSize

    if size ~= State.ScreenSize or viewport ~= State.LastViewport then
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

local function project(camera, position)
    local projected = camera:WorldToViewportPoint(position)
    local offset = State.ProjectionOffset

    local point = Vector3.new(
        projected.X + offset.X,
        projected.Y + offset.Y,
        projected.Z
    )

    local size = State.ScreenSize

    local onScreen = point.Z > 0
        and point.X >= 0
        and point.Y >= 0
        and point.X <= size.X
        and point.Y <= size.Y

    return point, onScreen
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
-- 08. AUTOMATIC RIG DETECTION
-- No scanner menus, hierarchy pages, or manual selections.
--==============================================================

local Scanner = {}

local function validPart(part, character)
    return part ~= nil
        and part:IsA("BasePart")
        and part.Parent ~= nil
        and part:IsDescendantOf(character)
        and part:GetAttribute("AimTargetable") ~= false
end

local function excludedPart(part, character)
    if part:GetAttribute("AimTargetable") == false then
        return true
    end

    local ancestor = part.Parent

    while ancestor and ancestor ~= character do
        if ancestor:IsA("Accessory") or ancestor:IsA("Tool") then
            return true
        end

        ancestor = ancestor.Parent
    end

    return false
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

function Scanner.Mark(record)
    if not State.Running or not record.Character then
        return
    end

    record.Revision += 1
    record.Dirty = true
    record.Due = os.clock() + 0.15
end

local function forgetObject(record, object)
    local bucket = record.Observed[object]

    if bucket then
        disconnectAll(bucket)
        record.Observed[object] = nil
    end
end

local function observeObject(record, object)
    if record.Observed[object] then
        return
    end

    -- Only observe objects relevant to automatic rig recognition.
    if not (
        object:IsA("BasePart")
        or object:IsA("Humanoid")
        or object:IsA("Motor6D")
        or object == record.Character
    ) then
        return
    end

    local bucket = {}
    record.Observed[object] = bucket

    connect(object:GetPropertyChangedSignal("Name"), function()
        Scanner.Mark(record)
    end, bucket)

    if object:IsA("BasePart") then
        connect(object.AttributeChanged, function(attribute)
            if attribute == "AimRole"
                or attribute == "AimTargetable" then
                Scanner.Mark(record)
            end
        end, bucket)
    end

    if object:IsA("Motor6D") then
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

    record.Dirty = character ~= nil
    record.Due = os.clock()

    if State.Target and State.Target.Player == record.Player then
        State.Target = nil
        State.NextAcquire = 0
    end

    State.VisualElapsed = math.huge

    if not character then
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
end

local function buildScan(record, character, generation, revision)
    local function current()
        return State.Running
            and Records[record.Player] == record
            and record.Character == character
            and record.Generation == generation
            and record.Revision == revision
            and character.Parent ~= nil
    end

    local scan = {
        Character = character,
        Humanoid = nil,

        Parts = {},
        ByInstance = {},

        Roles = {
            Head = {},
            Torso = {},
            Root = {},
            Body = {},
        },

        ForceFields = {},
        Root = nil,
        Head = nil,
    }

    local motors = {}

    for index, object in ipairs(character:GetDescendants()) do
        if not current() then
            return nil
        end

        if object:IsA("Humanoid") then
            scan.Humanoid = scan.Humanoid or object

        elseif object:IsA("ForceField") then
            table.insert(scan.ForceFields, object)

        elseif object:IsA("Motor6D") then
            table.insert(motors, object)

        elseif object:IsA("BasePart")
            and not excludedPart(object, character) then
            local item = {
                Part = object,
                Role = namedRole(object),
            }

            table.insert(scan.Parts, item)
            scan.ByInstance[object] = item
        end

        if index % 64 == 0 then
            task.wait()
        end
    end

    if not current() then
        return nil
    end

    local root = scan.Humanoid and scan.Humanoid.RootPart
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

    -- Custom / renamed rigs: use the largest eligible part as fallback.
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

    -- Neck joints can identify renamed heads.
    for _, motor in ipairs(motors) do
        if motor.Parent and motor.Name:lower():find("neck", 1, true) then
            local item = scan.ByInstance[motor.Part1]

            if item and item.Role == "Body" then
                item.Role = "Head"
            end
        end
    end

    for _, item in ipairs(scan.Parts) do
        local explicitRole = item.Part:GetAttribute("AimRole")

        if explicitRole == "Head"
            or explicitRole == "Torso"
            or explicitRole == "Root" then
            item.Role = explicitRole
        end

        table.insert(scan.Roles[item.Role], item)
    end

    if #scan.Roles.Head > 0 then
        scan.Head = scan.Roles.Head[1].Part
    else
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

    return current() and scan or nil
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
    State.ScanWorkers += 1

    task.spawn(function()
        local ok, scan = pcall(
            buildScan,
            record,
            character,
            generation,
            revision
        )

        record.Busy = false
        State.ScanWorkers = math.max(State.ScanWorkers - 1, 0)

        if not State.Running or Records[record.Player] ~= record then
            return
        end

        local unchanged = record.Character == character
            and record.Generation == generation
            and record.Revision == revision

        if ok and scan and unchanged then
            record.Scan = scan
            State.VisualElapsed = math.huge

        elseif not unchanged then
            record.Dirty = record.Character ~= nil
            record.Due = os.clock() + 0.15

        elseif not ok then
            -- A later character change will request another scan.
            warn("Automatic rig scan failed: " .. tostring(scan))
        end
    end)
end

local function liveData(record)
    local character = record and record.Character
    local scan = record and record.Scan

    if not character
        or not character.Parent
        or not scan
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
        health = character:GetAttribute("Health")
        maxHealth = character:GetAttribute("MaxHealth")
    end

    if not finite(health)
        or not finite(maxHealth)
        or health <= 0
        or maxHealth <= 0
        or not validPart(scan.Root, character) then
        return nil
    end

    return {
        Character = character,
        Scan = scan,

        Root = scan.Root,
        Head = validPart(scan.Head, character)
            and scan.Head
            or scan.Root,

        Health = health,
        MaxHealth = maxHealth,
    }
end

local function componentList(data, mode)
    local scan = data.Scan
    local result = {}
    local seen = {}

    local function append(part)
        if validPart(part, data.Character) and not seen[part] then
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
        append(data.Head)
        appendRole("Torso")
        append(data.Root)

        for _, item in ipairs(scan.Parts) do
            append(item.Part)
        end
    end

    if mode == "Auto" then
        appendAuto()

    elseif mode == "Root" then
        append(data.Root)
        appendRole("Root")

    else
        appendRole(mode)
    end

    -- Automatic fallback replaces the removed manual controls.
    if #result == 0 then
        appendAuto()
    end

    return result
end

--==============================================================
-- 09. SMART AIM V2
--==============================================================

local function hasForceField(data)
    for _, field in ipairs(data.Scan.ForceFields) do
        if field.Parent and field:IsDescendantOf(data.Character) then
            return true
        end
    end

    return false
end

local function evaluateTarget(player, camera, origin)
    local settings = Config.Aim

    if not teamAllowed(player, settings.TeamCheck) then
        return nil
    end

    local data = liveData(Records[player])

    if not data then
        return nil
    end

    if settings.ForceFieldCheck and hasForceField(data) then
        return nil
    end

    local rootDistance = (
        data.Root.Position - camera.CFrame.Position
    ).Magnitude

    if rootDistance > settings.MaxDistance then
        return nil
    end

    for _, part in ipairs(componentList(data, settings.TargetPart)) do
        local point, onScreen = project(camera, part.Position)

        if onScreen then
            local screenDistance = (
                Vector2.new(point.X, point.Y) - origin
            ).Magnitude

            local distance = (
                part.Position - camera.CFrame.Position
            ).Magnitude

            if screenDistance <= settings.FOV
                and distance <= settings.MaxDistance
                and (
                    not settings.WallCheck
                    or visible(camera, data.Character, part.Position)
                ) then

                local score = screenDistance

                if settings.Priority == "Distance" then
                    score = distance

                elseif settings.Priority == "Lowest health" then
                    score = data.Health
                end

                return {
                    Player = player,
                    Part = part,
                    Character = data.Character,

                    Score = score,
                    ScreenDistance = screenDistance,
                }
            end
        end
    end

    return nil
end

local function chooseTarget(camera, origin)
    local now = os.clock()
    local current

    if State.Target then
        current = evaluateTarget(
            State.Target.Player,
            camera,
            origin
        )
    end

    if current and Config.Aim.StickyTarget then
        State.Target = current
        return current
    end

    if now < State.NextAcquire then
        State.Target = current
        return current
    end

    State.NextAcquire = now + 1 / STYLE.AcquisitionRate

    local best

    for player in pairs(Records) do
        local candidate = evaluateTarget(player, camera, origin)

        if candidate and (
            not best
            or candidate.Score < best.Score
        ) then
            best = candidate
        end
    end

    State.Target = best
    return best
end

local function aimRequested()
    local settings = Config.Aim

    if not settings.Enabled then
        return false
    end

    if State.TouchArmed or not settings.KeybindEnabled then
        return true
    end

    return settings.ActivationMode == "Always"
        or settings.ActivationMode == "Hold" and State.Held
        or settings.ActivationMode == "Toggle" and State.Toggled
end

local function turnCamera(camera, part, deltaTime)
    if not part or not part.Parent then
        return
    end

    local position = camera.CFrame.Position

    if (part.Position - position).Magnitude <= 0.001 then
        return
    end

    local smoothness = Config.Aim.Smoothness
    local alpha = 1

    if smoothness > 0 then
        local normalized = smoothness / 100
        local response = 2 + (1 - normalized) ^ 2 * 58

        alpha = 1 - math.exp(-response * deltaTime)
    end

    camera.CFrame = camera.CFrame:Lerp(
        CFrame.lookAt(position, part.Position),
        math.clamp(alpha, 0, 1)
    )
end

--==============================================================
-- 10. PLAYER VISUALS
--==============================================================

local function createVisual(record)
    if record.Player == LocalPlayer or record.Visual then
        return
    end

    local gui = make("Frame", {
        Name = "Player_" .. tostring(record.Player.UserId),
        Size = UDim2.fromScale(1, 1),

        BackgroundTransparency = 1,
        BorderSizePixel = 0,

        Active = false,
        Selectable = false,
        Visible = false,
    }, Canvas)

    local nameLabel = make("TextLabel", {
        Name = "Name",

        AnchorPoint = Vector2.new(0.5, 1),
        Size = UDim2.fromOffset(280, 26),

        BackgroundTransparency = 1,
        BorderSizePixel = 0,

        Font = Enum.Font.GothamSemibold,
        TextSize = STYLE.TextSize,
        TextColor3 = STYLE.PlayerColor,
        TextStrokeTransparency = 0.25,

        TextTruncate = Enum.TextTruncate.AtEnd,
        RichText = false,

        Active = false,
        Selectable = false,
        Visible = false,
    }, gui)

    local health = make("Frame", {
        Name = "HealthBar",

        BackgroundColor3 = Color3.fromRGB(20, 20, 24),
        BorderSizePixel = 0,

        Active = false,
        Selectable = false,
        Visible = false,
    }, gui)

    make("UIStroke", {
        Color = Color3.new(0, 0, 0),
        Thickness = 1,
    }, health)

    local fill = make("Frame", {
        Name = "Fill",

        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.fromScale(0, 1),
        Size = UDim2.fromScale(1, 1),

        BackgroundColor3 = Color3.fromRGB(70, 220, 100),
        BorderSizePixel = 0,

        Active = false,
        Selectable = false,
    }, health)

    local highlight = make("Highlight", {
        Name = "Highlight_" .. tostring(record.Player.UserId),

        Adornee = nil,
        Enabled = false,

        DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,

        FillColor = STYLE.PlayerColor,
        OutlineColor = STYLE.PlayerColor,

        FillTransparency = STYLE.HighlightFillTransparency,
        OutlineTransparency = STYLE.HighlightOutlineTransparency,
    }, Artifacts)

    record.Visual = {
        Gui = gui,
        Name = nameLabel,
        Health = health,
        Fill = fill,
        Highlight = highlight,
    }
end

local function hideVisual(record)
    local visual = record.Visual

    if not visual then
        return
    end

    visual.Gui.Visible = false
    visual.Highlight.Enabled = false
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

local function updateVisual(record, camera)
    local visual = record.Visual

    if not visual then
        return
    end

    local settings = Config.Visuals

    visual.Gui.Visible = false
    visual.Name.Visible = false
    visual.Health.Visible = false

    if not teamAllowed(record.Player, settings.TeamCheck) then
        visual.Highlight.Enabled = false
        visual.Highlight.Adornee = nil
        return
    end

    local data = liveData(record)

    if not data then
        visual.Highlight.Enabled = false
        visual.Highlight.Adornee = nil
        return
    end

    --==========================================================
    -- HIGHLIGHT FIX
    --
    -- Update highlights BEFORE any line-of-sight check.
    -- AlwaysOnTop is independent of all aim and label settings.
    --==========================================================

    local highlight = visual.Highlight

    highlight.Adornee = data.Character
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop

    highlight.FillColor = STYLE.PlayerColor
    highlight.OutlineColor = STYLE.PlayerColor

    highlight.FillTransparency = STYLE.HighlightFillTransparency
    highlight.OutlineTransparency = STYLE.HighlightOutlineTransparency

    highlight.Enabled = settings.Highlights

    -- Everything below applies only to names and health bars.
    if not settings.Names and not settings.HealthBars then
        return
    end

    if not settings.OtherVisualsThroughWalls
        and not visible(camera, data.Character, data.Head.Position) then
        return
    end

    if settings.Names then
        local position = data.Head.Position
            + Vector3.new(
                0,
                data.Head.Size.Y * 0.5 + 0.35,
                0
            )

        local point, onScreen = project(camera, position)

        if onScreen then
            visual.Name.Text = string.format(
                "%s (@%s)",
                record.Player.DisplayName,
                record.Player.Name
            )

            visual.Name.Position = UDim2.fromOffset(
                point.X,
                point.Y
            )

            visual.Name.Visible = true
        end
    end

    if settings.HealthBars then
        local left, top, right, bottom = screenBounds(
            camera,
            data.Character
        )

        if left then
            local fraction = math.clamp(
                data.Health / data.MaxHealth,
                0,
                1
            )

            visual.Health.Position = UDim2.fromOffset(
                right + 5,
                top
            )

            visual.Health.Size = UDim2.fromOffset(
                4,
                math.max(bottom - top, 8)
            )

            visual.Fill.Size = UDim2.fromScale(1, fraction)

            visual.Fill.BackgroundColor3 = Color3.fromHSV(
                fraction / 3,
                0.85,
                1
            )

            visual.Health.Visible = true
        end
    end

    visual.Gui.Visible = visual.Name.Visible or visual.Health.Visible
end

--==============================================================
-- 11. VISUAL-ONLY HITBOX
--==============================================================

local function hideHitbox(record)
    if record.Hitbox then
        record.Hitbox.Visible = false
        record.Hitbox.Adornee = nil
    end
end

local function showHitbox(record, part)
    if not record.Hitbox then
        record.Hitbox = make("BoxHandleAdornment", {
            Name = "Hitbox_" .. tostring(record.Player.UserId),

            Adornee = nil,
            Size = Vector3.new(1, 1, 1),
            CFrame = CFrame.identity,

            Color3 = STYLE.HitboxColor,
            Transparency = STYLE.HitboxTransparency,

            AlwaysOnTop = false,
            ZIndex = 1,
            Visible = false,
        }, Artifacts)
    end

    local size = Config.Hitbox.Size
    local adornment = record.Hitbox

    adornment.Adornee = part
    adornment.Size = Vector3.new(size, size, size)
    adornment.Visible = true
end

local function updateHitboxes(camera)
    local candidates = {}
    local shown = {}

    if Config.Hitbox.Enabled then
        for player, record in pairs(Records) do
            if teamAllowed(player, Config.Visuals.TeamCheck) then
                local data = liveData(record)

                if data then
                    local distance = (
                        data.Root.Position - camera.CFrame.Position
                    ).Magnitude

                    if distance <= STYLE.HitboxMaxDistance then
                        table.insert(candidates, {
                            Record = record,
                            Part = data.Root,
                            Distance = distance,
                        })
                    end
                end
            end
        end

        table.sort(candidates, function(a, b)
            return a.Distance < b.Distance
        end)

        local count = math.min(
            #candidates,
            STYLE.HitboxMaxVisible
        )

        for index = 1, count do
            local candidate = candidates[index]

            shown[candidate.Record] = true
            showHitbox(candidate.Record, candidate.Part)
        end
    end

    for _, record in pairs(Records) do
        if not shown[record] then
            hideHitbox(record)
        end
    end
end

--==============================================================
-- 12. PLAYER LIFECYCLE
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

        Dirty = false,
        Busy = false,
        Due = 0,

        Visual = nil,
        Hitbox = nil,
    }

    Records[player] = record
    createVisual(record)

    connect(player.CharacterAdded, function(character)
        Scanner.Bind(record, character)
    end, record.PlayerConnections)

    connect(player.CharacterRemoving, function(character)
        if record.Character == character then
            Scanner.Bind(record, nil)
        end

        hideVisual(record)
        hideHitbox(record)

        if player == LocalPlayer then
            resetActivation()
        end
    end, record.PlayerConnections)

    local function teamChanged()
        State.Target = nil
        State.NextAcquire = 0
        State.VisualElapsed = math.huge
    end

    connect(
        player:GetPropertyChangedSignal("Team"),
        teamChanged,
        record.PlayerConnections
    )

    connect(
        player:GetPropertyChangedSignal("Neutral"),
        teamChanged,
        record.PlayerConnections
    )

    Scanner.Bind(record, player.Character)
end

local function removePlayer(player)
    local record = Records[player]

    if not record then
        return
    end

    Records[player] = nil

    record.Generation += 1
    record.Character = nil

    disconnectAll(record.PlayerConnections)
    disconnectAll(record.CharacterConnections)

    for object, bucket in pairs(record.Observed) do
        disconnectAll(bucket)
        record.Observed[object] = nil
    end

    if record.Visual then
        record.Visual.Highlight:Destroy()
        record.Visual.Gui:Destroy()
    end

    if record.Hitbox then
        record.Hitbox:Destroy()
    end

    if State.Target and State.Target.Player == player then
        State.Target = nil
        State.NextAcquire = 0
    end
end

connect(Players.PlayerAdded, addPlayer)
connect(Players.PlayerRemoving, removePlayer)

for _, player in ipairs(Players:GetPlayers()) do
    addPlayer(player)
end

--==============================================================
-- 13. INPUT
--==============================================================

local function matchesAimKey(input)
    local key = Config.Aim.Key

    if key == "MouseButton2" then
        return input.UserInputType == Enum.UserInputType.MouseButton2
    end

    return input.UserInputType == Enum.UserInputType.Keyboard
        and input.KeyCode.Name == key
end

connect(UserInputService.InputBegan, function(input, processed)
    if not State.Running
        or processed
        or not State.Focused
        or GuiService.MenuIsOpen
        or UserInputService:GetFocusedTextBox() then
        return
    end

    if Config.Aim.Enabled
        and Config.Aim.KeybindEnabled
        and matchesAimKey(input) then
        State.Held = true

        if Config.Aim.ActivationMode == "Toggle" then
            State.Toggled = not State.Toggled
            State.Target = nil
            State.NextAcquire = 0
        end
    end
end)

connect(UserInputService.InputEnded, function(input)
    if matchesAimKey(input) then
        State.Held = false

        if Config.Aim.ActivationMode == "Hold" then
            State.Target = nil
            State.NextAcquire = 0
        end
    end
end)

connect(UserInputService.WindowFocusReleased, function()
    State.Focused = false
    resetActivation()
end)

connect(UserInputService.WindowFocused, function()
    State.Focused = true
end)

connect(UserInputService.TextBoxFocused, function()
    resetActivation()
end)

connect(GuiService.MenuOpened, function()
    resetActivation()
end)

--==============================================================
-- 14. DRAGGABLE MOBILE CONTROL
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

    Drag.StartPosition = Floating.AbsolutePosition
        + Floating.AbsoluteSize * 0.5

    Drag.Moved = false
end)

connect(UserInputService.InputChanged, function(input)
    if not Drag.Input then
        return
    end

    local touch = Drag.Input.UserInputType == Enum.UserInputType.Touch

    if touch and input ~= Drag.Input then
        return
    end

    if not touch
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

        local position = Floating.AbsolutePosition
            + Floating.AbsoluteSize * 0.5

        local normalized = clampFloatingPosition(position)

        Config.Aim.FloatingX = normalized.X
        Config.Aim.FloatingY = normalized.Y

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

    -- If the menu enabled aim but the button is not armed yet,
    -- the first tap arms it; the next tap switches it off.
    local enabled = not (
        Config.Aim.Enabled and State.TouchArmed
    )

    setConfig("Aim", "Enabled", enabled)
    State.TouchArmed = enabled

    SyncingControls = true
    AimToggle:Set(enabled)
    SyncingControls = false
end)

local function updateFloating()
    Floating.Visible = Config.Aim.FloatingToggle

    local active = aimRequested()

    if not Config.Aim.Enabled then
        Floating.Text = "AIM OFF"
    elseif active then
        Floating.Text = "AIM ON"
    else
        Floating.Text = "AIM READY"
    end

    Floating.BackgroundColor3 = active
        and Color3.fromRGB(20, 105, 125)
        or Color3.fromRGB(30, 35, 48)

    if not Drag.Input and State.ScreenSize.X > 0 then
        local intended = Vector2.new(
            Config.Aim.FloatingX * State.ScreenSize.X,
            Config.Aim.FloatingY * State.ScreenSize.Y
        )

        local normalized = clampFloatingPosition(intended)

        Floating.Position = UDim2.fromScale(
            normalized.X,
            normalized.Y
        )
    end
end

--==============================================================
-- 15. DISABLE MENU SELECTION NAVIGATION
--==============================================================

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
-- 16. CLEANUP
--==============================================================

local WindowDestroyed = false

local function cleanup()
    if not State.Running then
        return
    end

    saveConfiguration()

    State.Running = false
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

    Overlay:Destroy()
    Artifacts:Destroy()

    table.clear(Records)
    table.clear(MenuRoots)

    Session.Cleanup = nil
end

local function unload()
    cleanup()

    if not WindowDestroyed then
        Window:Destroy()
    end
end

Window:OnDestroy(function()
    WindowDestroyed = true
    cleanup()
end)

Tabs.System:Button({
    Title = "Unload — remove menu and all visuals",
    Icon = "trash-2",
    Callback = unload,
})

Session.Cleanup = unload

--==============================================================
-- 17. BACKGROUND SCAN / SAVE SCHEDULER
--==============================================================

connect(RunService.Heartbeat, function()
    if not State.Running then
        return
    end

    local now = os.clock()

    if State.SaveDue and now >= State.SaveDue then
        State.SaveDue = nil
        saveConfiguration()
    end

    -- Prioritize the local rig so aiming can establish alive state.
    local ownRecord = Records[LocalPlayer]

    if ownRecord
        and ownRecord.Dirty
        and not ownRecord.Busy
        and ownRecord.Due <= now
        and State.ScanWorkers < 2 then
        Scanner.Start(ownRecord)
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
end)

--==============================================================
-- 18. RENDER LOOP
--==============================================================

local function hideEverything()
    FOVCircle.Visible = false

    for _, record in pairs(Records) do
        hideVisual(record)
        hideHitbox(record)
    end
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
            State.Target = nil
            State.NextAcquire = 0

            hideEverything()

            -- Force a visual refresh as soon as a camera returns.
            State.VisualElapsed = math.huge
            return
        end

        updateScreenGeometry(camera)
        updateFloating()

        if State.ScreenSize.X <= 0 or State.ScreenSize.Y <= 0 then
            hideEverything()
            State.VisualElapsed = math.huge
            return
        end

        FOVCircle.Size = UDim2.fromOffset(
            Config.Aim.FOV * 2,
            Config.Aim.FOV * 2
        )

        FOVCircle.Visible = Config.Aim.Enabled
            and Config.Aim.ShowFOV

        local ownData = liveData(Records[LocalPlayer])

        local inputAllowed = State.Focused
            and ownData ~= nil
            and not GuiService.MenuIsOpen
            and UserInputService:GetFocusedTextBox() == nil

        if inputAllowed and aimRequested() then
            local target = chooseTarget(
                camera,
                State.ScreenSize * 0.5
            )

            if target then
                turnCamera(camera, target.Part, deltaTime)
            end
        else
            State.Target = nil
            State.NextAcquire = 0
        end

        -- Visuals do not depend on aim being enabled or active.
        State.VisualElapsed += deltaTime

        if State.VisualElapsed >= 1 / STYLE.VisualRefreshRate then
            State.VisualElapsed = 0

            for _, record in pairs(Records) do
                updateVisual(record, camera)
            end

            updateHitboxes(camera)
        end
    end
)

updateFloating()
