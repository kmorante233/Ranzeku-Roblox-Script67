--[[
    TARGETING & VISUALS + HITBOX V2
    By 00B_qruel

    SINGLE-PASTE ROBLOX STUDIO INSTALLER

    Run in Studio's Command Bar while NOT playing.

    Installs:
      ReplicatedStorage/TargetingSuite/WindUI
      ServerScriptService/HitboxV2
      ServerScriptService/HitboxV2Start
      StarterPlayer/StarterPlayerScripts/TargetingSuiteClient

    Existing installations using those exact names are backed up.

    IMPORTANT:
      - This is a Studio installation, not an executor script.
      - No position offsets.
      - Hitbox queries and damage commits run on the server.
      - No remote accepts damage or a victim.
      - Existing weapons must use HitboxV2's server API.
      - Does not modify or guess your weapon's ammo/damage logic.
      - Not runtime-tested in your experience.
]]

local RunService = game:GetService("RunService")
assert(RunService:IsStudio(), "Run this in Roblox Studio.")
assert(not RunService:IsRunning(), "Stop the playtest before installing.")

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local starterScripts = StarterPlayer:WaitForChild("StarterPlayerScripts")

-- The only downloaded dependency is the same WindUI library.
-- The source is installed as a ModuleScript, not executed here.
local windSource
local existingPackage = ReplicatedStorage:FindFirstChild("TargetingSuite")
local existingWind = existingPackage
    and existingPackage:FindFirstChild("WindUI")

if existingWind and existingWind:IsA("ModuleScript") then
    windSource = existingWind.Source
else
    local previousHttp = HttpService.HttpEnabled

    local ok, result = pcall(function()
        HttpService.HttpEnabled = true

        return HttpService:GetAsync(
            "https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"
        )
    end)

    pcall(function()
        HttpService.HttpEnabled = previousHttp
    end)

    assert(
        ok and type(result) == "string" and #result > 1000,
        "WindUI download failed. No scripts were installed. "
            .. tostring(result)
    )

    windSource = result
end

local installerUserId = 0

pcall(function()
    installerUserId = game:GetService("StudioService"):GetUserId()
end)

local SERVER_SOURCE = [====[
-- ServerScriptService/HitboxV2
-- By 00B_qruel
--
-- Root-centered server-authoritative combat queries.
-- No offsets. No client damage remote.
--
-- API:
--   Start()
--   NewAttack(attacker, damage, range, lifetime?)
--   Raycast(ticket, origin, direction)
--   Sphere(ticket, center, radius)
--   CommitHit(ticket, hit, damageCallback?)
--
-- Weapon ownership/ammo/reload/fire-rate/muzzle validation
-- remain the responsibility of your weapon server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

assert(RunService:IsServer(), "HitboxV2 is server-only.")

local API = {}

local DEFAULT = {
    Enabled = false,

    X = 4,
    Y = 6,
    Z = 4,

    Transparency = 0.7,
    Visualization = true,

    R = 102,
    G = 227,
    B = 255,

    TeamCheck = true,
    SpecificTeams = false,
    SelectedTeams = {},
}

local LIMITS = {
    X = {0.5, 30},
    Y = {0.5, 30},
    Z = {0.5, 30},

    Transparency = {0, 1},

    R = {0, 255},
    G = {0, 255},
    B = {0, 255},
}

local UI_DEFAULTS = {
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
        FloatingX = 0.9,
        FloatingY = 0.65,
    },

    Visuals = {
        Highlights = true,
        Names = false,
        HealthBars = false,
        TeamCheck = true,
        OtherVisualsThroughWalls = false,
    },
}

local UI_LIMITS = {
    Smoothness = {0, 100},
    FOV = {20, 800},
    MaxDistance = {50, 5000},
    FloatingX = {0, 1},
    FloatingY = {0, 1},
}

local UI_CHOICES = {
    Key = {"E", "Q", "F", "LeftAlt", "MouseButton2"},
    ActivationMode = {"Hold", "Toggle", "Always"},
    TargetPart = {"Auto", "Head", "Torso", "Root"},
    Priority = {"Crosshair", "Distance", "Lowest health"},
}

local function copy(value)
    if type(value) ~= "table" then
        return value
    end

    local result = {}

    for key, item in pairs(value) do
        result[key] = copy(item)
    end

    return result
end

local function finite(value)
    return type(value) == "number"
        and value == value
        and math.abs(value) < math.huge
end

local function vector(value)
    return typeof(value) == "Vector3"
        and finite(value.X)
        and finite(value.Y)
        and finite(value.Z)
end

local function count(values)
    local n = 0

    for _ in pairs(values) do
        n += 1
    end

    return n
end

local function fresh()
    return {
        Global = copy(DEFAULT),
        Teams = {},
        Players = {},
    }
end

local Configuration = fresh()
local Revision = 0
local Started = false
local Changed

local Requests = {}
local StorageTimes = {}
local StorageBusy = {}
local Preferences = {}

local Tickets = {}
local Store

pcall(function()
    Store = DataStoreService:GetDataStore("TargetingSuite_HitboxV2_v2")
end)

local function admin(player)
    -- Studio test players can exercise the admin controls.
    if RunService:IsStudio() then
        return true
    end

    local installingUser = script:GetAttribute("InstallerUserId")

    return (
        finite(installingUser)
        and installingUser > 0
        and player.UserId == installingUser
    ) or (
        game.CreatorType == Enum.CreatorType.User
        and player.UserId == game.CreatorId
    )
end

local function validateField(field, value)
    assert(DEFAULT[field] ~= nil, "Unknown hitbox setting.")

    local limits = LIMITS[field]

    if limits then
        assert(finite(value), "Expected a finite number.")

        value = math.clamp(value, limits[1], limits[2])

        if field == "R" or field == "G" or field == "B" then
            value = math.round(value)
        end

        return value
    end

    if field == "SelectedTeams" then
        assert(type(value) == "table", "Expected team array.")
        assert(count(value) <= 64, "Too many teams.")

        local result = {}
        local seen = {}

        for index, name in pairs(value) do
            assert(
                type(index) == "number"
                    and index % 1 == 0
                    and index >= 1
                    and index <= 64,
                "Invalid team array."
            )

            assert(
                type(name) == "string"
                    and #name > 0
                    and #name <= 100,
                "Invalid team name."
            )

            if not seen[name] then
                seen[name] = true
                table.insert(result, name)
            end
        end

        table.sort(result)
        return result
    end

    assert(type(value) == type(DEFAULT[field]), "Wrong setting type.")
    return value
end

local function layer(config, scope, key, create)
    if scope == "Global" then
        return config.Global
    end

    assert(type(key) == "string", "Missing override key.")

    local bucket

    if scope == "Team" then
        assert(#key > 0 and #key <= 100, "Invalid team key.")
        bucket = config.Teams

    elseif scope == "Player" then
        local id = tonumber(key)

        assert(
            finite(id)
                and id % 1 == 0
                and math.abs(id) <= 9007199254740991,
            "Invalid player key."
        )

        key = tostring(id)
        bucket = config.Players
    else
        error("Invalid scope.")
    end

    if create and not bucket[key] then
        assert(count(bucket) < 128, "Override limit reached.")
        bucket[key] = {}
    end

    return bucket[key], bucket, key
end

local function validateProfile(profile)
    assert(type(profile) == "table", "Invalid profile.")

    local result = fresh()

    for _, definition in ipairs({
        {"Global", "Global"},
        {"Teams", "Team"},
        {"Players", "Player"},
    }) do
        local source = profile[definition[1]]

        if source ~= nil then
            assert(type(source) == "table", "Invalid profile section.")

            if definition[2] == "Global" then
                for field, value in pairs(source) do
                    result.Global[field] = validateField(field, value)
                end
            else
                assert(count(source) <= 128, "Too many overrides.")

                for key, fields in pairs(source) do
                    assert(type(fields) == "table", "Invalid override.")

                    local target = layer(
                        result,
                        definition[2],
                        key,
                        true
                    )

                    for field, value in pairs(fields) do
                        target[field] = validateField(field, value)
                    end
                end
            end
        end
    end

    return result
end

local function validatePreferences(input)
    assert(type(input) == "table", "Invalid preferences.")

    local result = copy(UI_DEFAULTS)

    for group, defaults in pairs(UI_DEFAULTS) do
        local incoming = input[group]

        if type(incoming) == "table" then
            for field, default in pairs(defaults) do
                local value = incoming[field]

                if value ~= nil then
                    if type(default) == "boolean" then
                        assert(type(value) == "boolean", "Expected boolean.")

                    elseif type(default) == "number" then
                        assert(finite(value), "Expected finite number.")
                        local bounds = UI_LIMITS[field]
                        value = math.clamp(value, bounds[1], bounds[2])

                    elseif type(default) == "string" then
                        assert(
                            table.find(UI_CHOICES[field], value),
                            "Invalid choice."
                        )
                    end

                    result[group][field] = value
                end
            end
        end
    end

    return result
end

local function resolve(player)
    local result = copy(Configuration.Global)

    local team = player.Team
        and Configuration.Teams[player.Team.Name]

    local personal = Configuration.Players[tostring(player.UserId)]

    if team then
        for field, value in pairs(team) do
            result[field] = value
        end
    end

    if personal then
        for field, value in pairs(personal) do
            result[field] = value
        end
    end

    return result
end

local function rig(player)
    if not player or player.Parent ~= Players then
        return nil
    end

    local character = player.Character

    if not character or not character:IsDescendantOf(workspace) then
        return nil
    end

    local humanoid = character:FindFirstChildWhichIsA("Humanoid", true)

    local root = humanoid and humanoid.RootPart
        or character:FindFirstChild("HumanoidRootPart", true)
        or character.PrimaryPart

    if not humanoid
        or humanoid.Health <= 0
        or not root
        or not root:IsA("BasePart")
        or not root:IsDescendantOf(character) then
        return nil
    end

    return character, humanoid, root
end

local function sameTeam(a, b)
    return not a.Neutral
        and not b.Neutral
        and a.Team ~= nil
        and a.Team == b.Team
end

local function eligible(attacker, target)
    if attacker == target then
        return nil
    end

    local character, humanoid, root = rig(target)

    if not character
        or character:FindFirstChildWhichIsA("ForceField", true) then
        return nil
    end

    local settings = resolve(target)

    if settings.TeamCheck and sameTeam(attacker, target) then
        return nil
    end

    if settings.SpecificTeams then
        local teamName = target.Team and target.Team.Name

        if not teamName
            or not table.find(settings.SelectedTeams, teamName) then
            return nil
        end
    end

    return character, humanoid, root, settings
end

local function rayParameters(character)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {character}
    params.IgnoreWater = true
    return params
end

local function clearLine(from, to, attackerCharacter, targetCharacter)
    local displacement = to - from

    if displacement.Magnitude < 0.001 then
        return true
    end

    local hit = workspace:Raycast(
        from,
        displacement,
        rayParameters(attackerCharacter)
    )

    return hit == nil
        or (
            targetCharacter ~= nil
            and hit.Instance:IsDescendantOf(targetCharacter)
        )
end

local function rayBox(origin, unit, length, frame, size)
    local p = frame:PointToObjectSpace(origin)
    local d = frame:VectorToObjectSpace(unit)
    local half = size * 0.5

    local entry = 0
    local exit = length

    for _, axis in ipairs({"X", "Y", "Z"}) do
        if math.abs(d[axis]) < 1e-8 then
            if p[axis] < -half[axis] or p[axis] > half[axis] then
                return nil
            end
        else
            local a = (-half[axis] - p[axis]) / d[axis]
            local b = (half[axis] - p[axis]) / d[axis]

            if a > b then
                a, b = b, a
            end

            entry = math.max(entry, a)
            exit = math.min(exit, b)

            if entry > exit then
                return nil
            end
        end
    end

    return entry
end

local function closestPoint(frame, size, position)
    local p = frame:PointToObjectSpace(position)
    local half = size * 0.5

    return frame:PointToWorldSpace(Vector3.new(
        math.clamp(p.X, -half.X, half.X),
        math.clamp(p.Y, -half.Y, half.Y),
        math.clamp(p.Z, -half.Z, half.Z)
    ))
end

local function playerFromPart(part)
    local object = part

    while object and object ~= workspace do
        if object:IsA("Model") then
            local player = Players:GetPlayerFromCharacter(object)

            if player then
                return player
            end
        end

        object = object.Parent
    end
end

local function activeTicket(ticket)
    local attack = Tickets[ticket]

    if not attack
        or os.clock() > attack.Expires
        or attack.Revision ~= Revision then
        return nil
    end

    local character, _, root = rig(attack.Attacker)

    if not character or character ~= attack.Character then
        return nil
    end

    return attack, root
end

local function resultFor(attack, player, position, expanded)
    local character, humanoid = eligible(attack.Attacker, player)

    if not character or attack.Registered[humanoid] then
        return nil
    end

    local hit = {
        Player = player,
        Character = character,
        Humanoid = humanoid,
        Position = position,
        Expanded = expanded,
    }

    attack.Results[hit] = {
        Player = player,
        Character = character,
        Humanoid = humanoid,
    }

    return hit
end

function API.NewAttack(attacker, damage, range, lifetime)
    assert(
        typeof(attacker) == "Instance" and attacker:IsA("Player"),
        "Expected attacker Player."
    )

    assert(
        finite(damage) and damage > 0 and damage <= 500,
        "Invalid server damage."
    )

    assert(
        finite(range) and range > 0 and range <= 5000,
        "Invalid server range."
    )

    lifetime = lifetime or 0.5

    assert(
        finite(lifetime) and lifetime > 0 and lifetime <= 2,
        "Invalid lifetime."
    )

    local character = rig(attacker)

    if not character then
        return nil
    end

    local ticket = {}

    Tickets[ticket] = {
        Attacker = attacker,
        Character = character,
        Damage = damage,
        Range = range,
        Expires = os.clock() + lifetime,
        Revision = Revision,

        Results = {},
        Registered = {},
    }

    return ticket
end

function API.Raycast(ticket, origin, direction)
    local attack, attackerRoot = activeTicket(ticket)

    if not attack
        or not vector(origin)
        or not vector(direction)
        or (origin - attackerRoot.Position).Magnitude > 12 then
        return nil
    end

    local magnitude = direction.Magnitude

    if magnitude < 0.001 then
        return nil
    end

    local unit = direction.Unit
    local length = math.min(magnitude, attack.Range)

    local worldHit = workspace:Raycast(
        origin,
        unit * length,
        rayParameters(attack.Character)
    )

    local nearest = worldHit and worldHit.Distance or length
    local chosen
    local position
    local expanded = false

    if worldHit then
        local player = playerFromPart(worldHit.Instance)

        if player and eligible(attack.Attacker, player) then
            chosen = player
            position = worldHit.Position
        end
    end

    for _, target in ipairs(Players:GetPlayers()) do
        local character, _, root, settings =
            eligible(attack.Attacker, target)

        if character and settings.Enabled then
            local size = Vector3.new(settings.X, settings.Y, settings.Z)

            if (root.Position - origin).Magnitude
                <= nearest + size.Magnitude * 0.5 then

                local distance = rayBox(
                    origin,
                    unit,
                    nearest,
                    root.CFrame,
                    size
                )

                if distance
                    and distance <= nearest
                    and clearLine(
                        origin,
                        root.Position,
                        attack.Character,
                        character
                    ) then

                    nearest = distance
                    chosen = target
                    position = origin + unit * distance
                    expanded = true
                end
            end
        end
    end

    if chosen then
        return resultFor(attack, chosen, position, expanded)
    end
end

function API.Sphere(ticket, center, radius)
    local attack, attackerRoot = activeTicket(ticket)

    if not attack
        or not vector(center)
        or not finite(radius)
        or radius <= 0
        or radius > math.min(20, attack.Range)
        or (center - attackerRoot.Position).Magnitude
            > math.min(12, attack.Range)
        or not clearLine(
            attackerRoot.Position,
            center,
            attack.Character,
            nil
        ) then
        return {}
    end

    local results = {}

    for _, target in ipairs(Players:GetPlayers()) do
        local character, humanoid, root, settings =
            eligible(attack.Attacker, target)

        if character and not attack.Registered[humanoid] then
            local contact

            if settings.Enabled then
                local point = closestPoint(
                    root.CFrame,
                    Vector3.new(settings.X, settings.Y, settings.Z),
                    center
                )

                if (point - center).Magnitude <= radius then
                    contact = point
                end
            else
                for _, part in ipairs(character:GetDescendants()) do
                    if part:IsA("BasePart")
                        and not part:FindFirstAncestorWhichIsA("Accessory")
                        and not part:FindFirstAncestorWhichIsA("Tool") then

                        local point = closestPoint(
                            part.CFrame,
                            part.Size,
                            center
                        )

                        if (point - center).Magnitude <= radius then
                            contact = point
                            break
                        end
                    end
                end
            end

            if contact
                and (contact - attackerRoot.Position).Magnitude <= attack.Range
                and clearLine(
                    center,
                    root.Position,
                    attack.Character,
                    character
                ) then

                local hit = resultFor(
                    attack,
                    target,
                    contact,
                    settings.Enabled
                )

                if hit then
                    table.insert(results, hit)
                end
            end
        end
    end

    return results
end

function API.CommitHit(ticket, hit, applyDamage)
    local attack = activeTicket(ticket)
    local recorded = attack and attack.Results[hit]

    if not recorded then
        return false
    end

    local character, humanoid = eligible(
        attack.Attacker,
        recorded.Player
    )

    if not character
        or character ~= recorded.Character
        or humanoid ~= recorded.Humanoid
        or attack.Registered[humanoid] then
        return false
    end

    attack.Registered[humanoid] = true

    local ok, message = pcall(function()
        if applyDamage ~= nil then
            assert(type(applyDamage) == "function", "Invalid damage callback.")

            applyDamage(
                humanoid,
                attack.Damage,
                attack.Attacker,
                recorded.Player
            )
        else
            humanoid:TakeDamage(attack.Damage)
        end
    end)

    if not ok then
        warn("HitboxV2 damage callback:", message)
    end

    return ok
end

local function snapshot(player, ok, message)
    return {
        Ok = ok,
        Message = message,
        CanEdit = admin(player),
        Revision = Revision,
        Config = copy(Configuration),
    }
end

local function publish()
    Revision += 1

    Changed:FireAllClients({
        Revision = Revision,
        Config = copy(Configuration),
    })
end

local function storageAction(player, callback)
    assert(Store, "DataStore is unavailable.")
    assert(not StorageBusy[player], "Storage request already running.")

    local now = os.clock()

    assert(
        now - (StorageTimes[player] or -math.huge) >= 10,
        "Wait 10 seconds between storage requests."
    )

    StorageTimes[player] = now
    StorageBusy[player] = true

    local ok, value = pcall(callback)

    StorageBusy[player] = nil
    assert(ok, tostring(value))

    return value
end

function API.Start()
    if Started then
        return
    end

    local package = ReplicatedStorage:WaitForChild("TargetingSuite")
    assert(not package:FindFirstChild("Remotes"), "Duplicate server start.")

    Started = true

    local remotes = Instance.new("Folder")
    remotes.Name = "Remotes"

    local request = Instance.new("RemoteFunction")
    request.Name = "Request"
    request.Parent = remotes

    Changed = Instance.new("RemoteEvent")
    Changed.Name = "Changed"
    Changed.Parent = remotes

    request.OnServerInvoke = function(player, payload)
        local now = os.clock()

        if now - (Requests[player] or -math.huge) < 0.1 then
            return snapshot(player, false, "Please wait briefly.")
        end

        Requests[player] = now

        if type(payload) ~= "table" then
            return snapshot(player, false, "Invalid request.")
        end

        if payload.Action == "Get" then
            return snapshot(player, true, "Synchronized.")
        end

        local ok, message = pcall(function()
            -- UI preferences are private to the requesting player.
            -- These actions never modify combat hitbox configuration.
            if payload.Action == "SaveUI" then
                local validated = validatePreferences(payload.Preferences)
                Preferences[player] = validated

                return storageAction(player, function()
                    Store:UpdateAsync(
                        "UI_" .. tostring(player.UserId),
                        function()
                            return validated
                        end
                    )

                    return "Personal settings saved."
                end)

            elseif payload.Action == "LoadUI" then
                local loaded = storageAction(player, function()
                    return Store:GetAsync("UI_" .. tostring(player.UserId))
                end)

                assert(loaded ~= nil, "No personal settings saved.")
                Preferences[player] = validatePreferences(loaded)

                return "Personal settings loaded."
            end

            assert(admin(player), "Administrator access required.")

            if payload.Action == "Set" then
                local changes = payload.Changes

                assert(type(changes) == "table", "Missing changes.")
                assert(count(changes) >= 1 and count(changes) <= 24, "Invalid batch.")

                local updated = copy(Configuration)

                for index, change in pairs(changes) do
                    assert(
                        type(index) == "number"
                            and index % 1 == 0
                            and index >= 1
                            and index <= 24,
                        "Invalid change array."
                    )

                    assert(type(change) == "table", "Invalid change.")

                    local value = validateField(change.Field, change.Value)
                    local target = layer(
                        updated,
                        change.Scope,
                        change.Key,
                        true
                    )

                    target[change.Field] = value
                end

                Configuration = updated
                publish()
                return "Hitbox settings synchronized."

            elseif payload.Action == "Reset" then
                local updated = copy(Configuration)

                if payload.Scope == "Global" then
                    updated.Global = copy(DEFAULT)
                else
                    local _, bucket, key = layer(
                        updated,
                        payload.Scope,
                        payload.Key,
                        false
                    )

                    bucket[key] = nil
                end

                Configuration = updated
                publish()
                return "Selected scope reset."

            elseif payload.Action == "Save" then
                local saved = copy(Configuration)

                return storageAction(player, function()
                    Store:UpdateAsync(
                        "HB_" .. tostring(player.UserId),
                        function()
                            return saved
                        end
                    )

                    return "Hitbox profile saved."
                end)

            elseif payload.Action == "Load" then
                local startRevision = Revision

                local loaded = storageAction(player, function()
                    return Store:GetAsync("HB_" .. tostring(player.UserId))
                end)

                assert(loaded ~= nil, "No saved hitbox profile.")
                assert(startRevision == Revision, "Settings changed during load.")

                Configuration = validateProfile(loaded)
                publish()

                return "Hitbox profile loaded into this server."
            end

            error("Unknown action.")
        end)

        local response = snapshot(player, ok, tostring(message))

        if payload.Action == "LoadUI" and ok then
            response.Preferences = copy(Preferences[player])
        end

        return response
    end

    remotes.Parent = package

    Players.PlayerRemoving:Connect(function(player)
        Requests[player] = nil
        StorageTimes[player] = nil
        StorageBusy[player] = nil
        Preferences[player] = nil

        for ticket, attack in pairs(Tickets) do
            if attack.Attacker == player then
                Tickets[ticket] = nil
            end
        end
    end)

    local elapsed = 0

    RunService.Heartbeat:Connect(function(dt)
        elapsed += dt

        if elapsed < 1 then
            return
        end

        elapsed = 0
        local now = os.clock()

        for ticket, attack in pairs(Tickets) do
            if now > attack.Expires or attack.Revision ~= Revision then
                Tickets[ticket] = nil
            end
        end
    end)
end

return API
]====]

local CLIENT_SOURCE = [====[
-- StarterPlayerScripts/TargetingSuiteClient
-- By 00B_qruel
--
-- Smart Aim V2, automatic rig scanning, independent highlights,
-- names, health bars, mobile control, and Hitbox V2 administration.
--
-- No client damage authority. No position offsets.

local Players = game:GetService("Players")
local Teams = game:GetService("Teams")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local Package = ReplicatedStorage:WaitForChild("TargetingSuite")

local previousKey = "__TargetingSmartV2_" .. tostring(game.PlaceId)
local previous = _G[previousKey]

if type(previous) == "table" and type(previous.Cleanup) == "function" then
    pcall(previous.Cleanup)
end

local Session = {}
_G[previousKey] = Session

local WindUI = require(Package:WaitForChild("WindUI"))

local Config = {
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
        FloatingX = 0.9,
        FloatingY = 0.65,
    },

    Visuals = {
        Highlights = true,
        Names = false,
        HealthBars = false,
        TeamCheck = true,
        OtherVisualsThroughWalls = false,
    },
}

local STYLE = {
    PlayerColor = Color3.fromRGB(110, 150, 255),
    Accent = Color3.fromRGB(102, 227, 255),
    FillTransparency = 0.65,
    OutlineTransparency = 0.10,
}

local State = {
    Running = true,
    Focused = true,

    Held = false,
    Toggled = false,
    TouchArmed = false,

    Target = nil,
    NextAcquire = 0,

    ScreenSize = Vector2.zero,
    ProjectionOffset = Vector2.zero,

    ScanWorkers = 0,
    VisualElapsed = math.huge,
}

local Records = {}
local Connections = {}
local MenuConnections = {}
local Controls = {}

local Syncing = false
local RenderName = "TargetingSuite_" .. HttpService:GenerateGUID(false)

local function finite(value)
    return type(value) == "number"
        and value == value
        and math.abs(value) < math.huge
end

local function copy(value)
    if type(value) ~= "table" then
        return value
    end

    local result = {}

    for key, item in pairs(value) do
        result[key] = copy(item)
    end

    return result
end

local function connect(signal, callback, bucket)
    local connection = signal:Connect(callback)
    table.insert(bucket or Connections, connection)
    return connection
end

local function disconnect(bucket)
    for _, connection in ipairs(bucket) do
        connection:Disconnect()
    end

    table.clear(bucket)
end

local function make(className, props, parent)
    local object = Instance.new(className)

    for key, value in pairs(props) do
        object[key] = value
    end

    object.Parent = parent
    return object
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
end

local function setConfig(group, field, value)
    if Config[group][field] == value then
        return
    end

    Config[group][field] = value

    if group == "Aim" and (
        field == "Enabled"
        or field == "KeybindEnabled"
        or field == "Key"
        or field == "ActivationMode"
    ) then
        resetActivation()
    end

    changed()
end

local camera = workspace.CurrentCamera
local viewport = camera and camera.ViewportSize or Vector2.new(1000, 700)

local Window = WindUI:CreateWindow({
    Title = "Targeting & Visuals — By 00B_qruel",
    Author = "By 00B_qruel",
    Icon = "scan",

    Size = UDim2.fromOffset(
        math.clamp(viewport.X - 36, 340, 620),
        math.clamp(viewport.Y - 60, 300, 520)
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
    Aim = Window:Tab({Title = "Smart Aim V2", Icon = "crosshair"}),
    Visuals = Window:Tab({Title = "Player Visuals", Icon = "eye"}),
    Hitbox = Window:Tab({Title = "Hitbox", Icon = "box"}),
    System = Window:Tab({Title = "System", Icon = "settings"}),
}

local function section(tab, title)
    tab:Section({Title = title})
end

local function paragraph(tab, title, text)
    return tab:Paragraph({Title = title, Desc = text})
end

local function register(group, field, control, dropdown)
    table.insert(Controls, {
        Group = group,
        Field = field,
        Control = control,
        Dropdown = dropdown,
    })

    return control
end

local function toggle(tab, title, group, field)
    return register(group, field, tab:Toggle({
        Title = title,
        Value = Config[group][field],

        Callback = function(value)
            if State.Running and not Syncing then
                setConfig(group, field, value)
            end
        end,
    }))
end

local function slider(tab, title, group, field, low, high, step)
    return register(group, field, tab:Slider({
        Title = title,
        Step = step or 1,
        Value = {Min = low, Max = high, Default = Config[group][field]},

        Callback = function(value)
            value = tonumber(value)

            if State.Running and not Syncing and finite(value) then
                setConfig(group, field, math.clamp(value, low, high))
            end
        end,
    }))
end

local function dropdown(tab, title, group, field, values)
    return register(group, field, tab:Dropdown({
        Title = title,
        Values = values,
        Value = Config[group][field],
        Multi = false,
        AllowNone = false,

        Callback = function(value)
            if State.Running
                and not Syncing
                and table.find(values, value) then
                setConfig(group, field, value)
            end
        end,
    }), true)
end

section(Tabs.Aim, "Activation")

local AimToggle = toggle(
    Tabs.Aim, "Enable Smart Aim V2", "Aim", "Enabled"
)

toggle(Tabs.Aim, "Require activation key", "Aim", "KeybindEnabled")

dropdown(Tabs.Aim, "Activation key", "Aim", "Key", {
    "E", "Q", "F", "LeftAlt", "MouseButton2",
})

dropdown(Tabs.Aim, "Activation mode", "Aim", "ActivationMode", {
    "Hold", "Toggle", "Always",
})

toggle(Tabs.Aim, "Show movable aim button", "Aim", "FloatingToggle")

section(Tabs.Aim, "Targeting")

dropdown(Tabs.Aim, "Preferred component", "Aim", "TargetPart", {
    "Auto", "Head", "Torso", "Root",
})

dropdown(Tabs.Aim, "Target priority", "Aim", "Priority", {
    "Crosshair", "Distance", "Lowest health",
})

toggle(Tabs.Aim, "Keep current valid target", "Aim", "StickyTarget")

slider(
    Tabs.Aim, "Smoothness — 0 instant / 100 soft",
    "Aim", "Smoothness", 0, 100
)

slider(
    Tabs.Aim, "Maximum distance — studs",
    "Aim", "MaxDistance", 50, 5000
)

section(Tabs.Aim, "Checks")

toggle(Tabs.Aim, "Ignore teammates", "Aim", "TeamCheck")
toggle(Tabs.Aim, "Aim wall check", "Aim", "WallCheck")
toggle(Tabs.Aim, "Ignore ForceField targets", "Aim", "ForceFieldCheck")

section(Tabs.Aim, "Field of view")

toggle(Tabs.Aim, "Show centered FOV circle", "Aim", "ShowFOV")
slider(Tabs.Aim, "FOV radius — pixels", "Aim", "FOV", 20, 800)

section(Tabs.Visuals, "Player overlays")

toggle(
    Tabs.Visuals,
    "Player highlights — through walls",
    "Visuals",
    "Highlights"
)

toggle(Tabs.Visuals, "Names above players", "Visuals", "Names")
toggle(Tabs.Visuals, "Health bars", "Visuals", "HealthBars")

section(Tabs.Visuals, "Visibility")

toggle(Tabs.Visuals, "Ignore teammates", "Visuals", "TeamCheck")

toggle(
    Tabs.Visuals,
    "Names and health bars through walls",
    "Visuals",
    "OtherVisualsThroughWalls"
)

paragraph(
    Tabs.Visuals,
    "Independent highlights",
    "Highlights use AlwaysOnTop independently of aim and label wall checks."
)

--==============================================================
-- CLIENT OVERLAYS
--==============================================================

local Overlay = make("ScreenGui", {
    Name = "TargetingSuiteOverlay",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    ScreenInsets = Enum.ScreenInsets.None,
    ClipToDeviceSafeArea = false,
    DisplayOrder = 20,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, PlayerGui)

local Canvas = make("Frame", {
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Active = false,
    Selectable = false,
}, Overlay)

local Artifacts = make("Folder", {
    Name = "TargetingSuiteClientVisuals",
}, workspace)

local FOVCircle = make("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Visible = false,
    Selectable = false,
}, Canvas)

make("UICorner", {CornerRadius = UDim.new(1, 0)}, FOVCircle)

make("UIStroke", {
    Color = STYLE.Accent,
    Thickness = 1.5,
    Transparency = 0.15,
}, FOVCircle)

local Floating = make("TextButton", {
    Name = "FloatingAim",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(Config.Aim.FloatingX, Config.Aim.FloatingY),
    Size = UDim2.fromOffset(126, 46),

    BackgroundColor3 = Color3.fromRGB(30, 35, 48),
    TextColor3 = Color3.new(1, 1, 1),
    Font = Enum.Font.GothamBold,
    TextSize = 14,
    Text = "AIM OFF",

    AutoButtonColor = false,
    Active = true,
    Selectable = false,
    ZIndex = 30,
}, Canvas)

make("UICorner", {CornerRadius = UDim.new(0, 14)}, Floating)
make("UIStroke", {Color = STYLE.Accent, Thickness = 1.2}, Floating)

local RayParams = RaycastParams.new()
RayParams.FilterType = Enum.RaycastFilterType.Exclude
RayParams.IgnoreWater = true

local function sameTeam(player)
    return not LocalPlayer.Neutral
        and not player.Neutral
        and LocalPlayer.Team ~= nil
        and LocalPlayer.Team == player.Team
end

local function teamAllowed(player, check)
    return player ~= LocalPlayer and (not check or not sameTeam(player))
end

local function screenGeometry(currentCamera)
    State.ScreenSize = Canvas.AbsoluteSize

    local ok, offset = pcall(function()
        return GuiService:GetInsetArea(Enum.ScreenInsets.DeviceSafeInsets).Min
            - GuiService:GetInsetArea(Enum.ScreenInsets.None).Min
    end)

    State.ProjectionOffset = ok and offset or Vector2.zero

    local ignore = {Artifacts, currentCamera}

    if LocalPlayer.Character then
        table.insert(ignore, LocalPlayer.Character)
    end

    RayParams.FilterDescendantsInstances = ignore
end

local function project(currentCamera, position)
    local p = currentCamera:WorldToViewportPoint(position)

    local point = Vector3.new(
        p.X + State.ProjectionOffset.X,
        p.Y + State.ProjectionOffset.Y,
        p.Z
    )

    return point, point.Z > 0
        and point.X >= 0
        and point.Y >= 0
        and point.X <= State.ScreenSize.X
        and point.Y <= State.ScreenSize.Y
end

local function visible(currentCamera, character, position)
    local origin = currentCamera.CFrame.Position
    local displacement = position - origin

    if displacement.Magnitude < 0.001 then
        return true
    end

    local result = workspace:Raycast(origin, displacement, RayParams)

    return not result or result.Instance:IsDescendantOf(character)
end

--==============================================================
-- AUTOMATIC SMART SCANNER
--==============================================================

local Scanner = {}

local function validPart(part, character)
    return part
        and part:IsA("BasePart")
        and part:IsDescendantOf(character)
        and part:GetAttribute("AimTargetable") ~= false
end

local function excluded(part, character)
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

local function role(part)
    local explicit = part:GetAttribute("AimRole")

    if explicit == "Head" or explicit == "Torso" or explicit == "Root" then
        return explicit
    end

    local name = part.Name:lower():gsub("[^%w]", "")

    if name:find("head", 1, true) or name:find("skull", 1, true) then
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

local function observe(record, object)
    if record.Observed[object] then
        return
    end

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
            if attribute == "AimRole" or attribute == "AimTargetable" then
                Scanner.Mark(record)
            end
        end, bucket)
    elseif object:IsA("Motor6D") then
        for _, property in ipairs({"Part0", "Part1"}) do
            connect(object:GetPropertyChangedSignal(property), function()
                Scanner.Mark(record)
            end, bucket)
        end
    elseif object:IsA("Humanoid") then
        connect(object:GetPropertyChangedSignal("RootPart"), function()
            Scanner.Mark(record)
        end, bucket)
    end
end

function Scanner.Bind(record, character)
    disconnect(record.CharacterConnections)

    for object, bucket in pairs(record.Observed) do
        disconnect(bucket)
        record.Observed[object] = nil
    end

    record.Generation += 1
    record.Revision += 1
    record.Character = character
    record.Scan = nil
    record.Dirty = character ~= nil
    record.Due = os.clock()

    changed()

    if not character then
        return
    end

    connect(character.DescendantAdded, function(object)
        observe(record, object)
        Scanner.Mark(record)
    end, record.CharacterConnections)

    connect(character.DescendantRemoving, function(object)
        if record.Observed[object] then
            disconnect(record.Observed[object])
            record.Observed[object] = nil
        end

        Scanner.Mark(record)
    end, record.CharacterConnections)

    connect(character:GetPropertyChangedSignal("PrimaryPart"), function()
        Scanner.Mark(record)
    end, record.CharacterConnections)

    observe(record, character)

    for _, object in ipairs(character:GetDescendants()) do
        observe(record, object)
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
        Parts = {},
        ByInstance = {},
        Roles = {Head = {}, Torso = {}, Root = {}, Body = {}},
        Root = nil,
        Head = nil,
        Humanoid = nil,
    }

    local motors = {}

    for index, object in ipairs(character:GetDescendants()) do
        if not current() then
            return nil
        end

        if object:IsA("Humanoid") then
            scan.Humanoid = scan.Humanoid or object

        elseif object:IsA("Motor6D") then
            table.insert(motors, object)

        elseif object:IsA("BasePart") and not excluded(object, character) then
            local item = {Part = object, Role = role(object)}
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
        or character:FindFirstChild("HumanoidRootPart", true)
        or character.PrimaryPart

    if not root or not scan.ByInstance[root] then
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
        local largest = -1

        for _, item in ipairs(scan.Parts) do
            local size = item.Part.Size
            local volume = size.X * size.Y * size.Z

            if volume > largest then
                largest = volume
                root = item.Part
            end
        end
    end

    scan.Root = root

    for _, motor in ipairs(motors) do
        if motor.Name:lower():find("neck", 1, true) then
            local item = scan.ByInstance[motor.Part1]

            if item and item.Role == "Body" then
                item.Role = "Head"
            end
        end
    end

    local highest = -math.huge

    for _, item in ipairs(scan.Parts) do
        local explicit = item.Part:GetAttribute("AimRole")

        if explicit == "Head" or explicit == "Torso" or explicit == "Root" then
            item.Role = explicit
        end

        table.insert(scan.Roles[item.Role], item.Part)

        local height = root
            and root.CFrame:PointToObjectSpace(item.Part.Position).Y
            or item.Part.Position.Y

        if height > highest then
            highest = height
            scan.Head = item.Part
        end
    end

    scan.Head = scan.Roles.Head[1] or scan.Head

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
            buildScan, record, character, generation, revision
        )

        record.Busy = false
        State.ScanWorkers = math.max(0, State.ScanWorkers - 1)

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
            warn("Smart scan:", scan)
        end
    end)
end

local function liveData(record)
    local character = record and record.Character
    local scan = record and record.Scan

    if not character
        or not character:IsDescendantOf(workspace)
        or not scan
        or record.Player.Character ~= character
        or not validPart(scan.Root, character) then
        return nil
    end

    local humanoid = scan.Humanoid
    local health
    local maximum

    if humanoid and humanoid:IsDescendantOf(character) then
        health = humanoid.Health
        maximum = humanoid.MaxHealth
    else
        health = character:GetAttribute("Health")
        maximum = character:GetAttribute("MaxHealth")
    end

    if not finite(health)
        or not finite(maximum)
        or health <= 0
        or maximum <= 0 then
        return nil
    end

    return {
        Character = character,
        Scan = scan,
        Root = scan.Root,
        Head = validPart(scan.Head, character) and scan.Head or scan.Root,
        Health = health,
        MaxHealth = maximum,
    }
end

local function components(data, mode)
    local result = {}
    local seen = {}

    local function add(part)
        if validPart(part, data.Character) and not seen[part] then
            seen[part] = true
            table.insert(result, part)
        end
    end

    local function addRole(name)
        for _, part in ipairs(data.Scan.Roles[name] or {}) do
            add(part)
        end
    end

    local function automatic()
        addRole("Head")
        add(data.Head)
        addRole("Torso")
        add(data.Root)

        for _, item in ipairs(data.Scan.Parts) do
            add(item.Part)
        end
    end

    if mode == "Auto" then
        automatic()
    elseif mode == "Root" then
        add(data.Root)
        addRole("Root")
    else
        addRole(mode)
    end

    if #result == 0 then
        automatic()
    end

    return result
end

--==============================================================
-- SMART AIM
--==============================================================

local function evaluate(player, currentCamera)
    local settings = Config.Aim

    if not teamAllowed(player, settings.TeamCheck) then
        return nil
    end

    local data = liveData(Records[player])

    if not data then
        return nil
    end

    if settings.ForceFieldCheck
        and data.Character:FindFirstChildWhichIsA("ForceField", true) then
        return nil
    end

    local origin = currentCamera.CFrame.Position

    if (data.Root.Position - origin).Magnitude > settings.MaxDistance then
        return nil
    end

    for _, part in ipairs(components(data, settings.TargetPart)) do
        local point, onScreen = project(currentCamera, part.Position)

        if onScreen then
            local distance = (part.Position - origin).Magnitude

            local screenDistance = (
                Vector2.new(point.X, point.Y) - State.ScreenSize * 0.5
            ).Magnitude

            if distance <= settings.MaxDistance
                and screenDistance <= settings.FOV
                and (
                    not settings.WallCheck
                    or visible(currentCamera, data.Character, part.Position)
                ) then

                local score = screenDistance

                if settings.Priority == "Distance" then
                    score = distance
                elseif settings.Priority == "Lowest health" then
                    score = data.Health
                end

                return {
                    Player = player,
                    Character = data.Character,
                    Part = part,
                    Score = score,
                }
            end
        end
    end
end

local function chooseTarget(currentCamera)
    local current = State.Target
        and evaluate(State.Target.Player, currentCamera)

    if current and Config.Aim.StickyTarget then
        State.Target = current
        return current
    end

    local now = os.clock()

    if now < State.NextAcquire then
        State.Target = current
        return current
    end

    State.NextAcquire = now + 0.05

    local best

    for player in pairs(Records) do
        local candidate = evaluate(player, currentCamera)

        if candidate and (not best or candidate.Score < best.Score) then
            best = candidate
        end
    end

    State.Target = best
    return best
end

local function aimRequested()
    local settings = Config.Aim

    return settings.Enabled and (
        State.TouchArmed
        or not settings.KeybindEnabled
        or settings.ActivationMode == "Always"
        or settings.ActivationMode == "Hold" and State.Held
        or settings.ActivationMode == "Toggle" and State.Toggled
    )
end

local function turnCamera(currentCamera, part, dt)
    if not part or not part.Parent then
        return
    end

    local position = currentCamera.CFrame.Position

    if (part.Position - position).Magnitude < 0.001 then
        return
    end

    local alpha = 1

    if Config.Aim.Smoothness > 0 then
        local normalized = Config.Aim.Smoothness / 100
        local response = 2 + (1 - normalized) ^ 2 * 58
        alpha = 1 - math.exp(-response * dt)
    end

    currentCamera.CFrame = currentCamera.CFrame:Lerp(
        CFrame.lookAt(position, part.Position),
        math.clamp(alpha, 0, 1)
    )
end

--==============================================================
-- ESP / INDEPENDENT HIGHLIGHTS
--==============================================================

local function createVisual(record)
    if record.Player == LocalPlayer then
        return
    end

    local frame = make("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Visible = false,
        Selectable = false,
    }, Canvas)

    local name = make("TextLabel", {
        AnchorPoint = Vector2.new(0.5, 1),
        Size = UDim2.fromOffset(280, 26),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Font = Enum.Font.GothamSemibold,
        TextSize = 13,
        TextColor3 = STYLE.PlayerColor,
        TextStrokeTransparency = 0.25,
        TextTruncate = Enum.TextTruncate.AtEnd,
        RichText = false,
        Selectable = false,
    }, frame)

    local health = make("Frame", {
        BackgroundColor3 = Color3.fromRGB(20, 20, 24),
        BorderSizePixel = 0,
        Selectable = false,
    }, frame)

    make("UIStroke", {Color = Color3.new(0, 0, 0)}, health)

    local fill = make("Frame", {
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.fromScale(0, 1),
        Size = UDim2.fromScale(1, 1),
        BorderSizePixel = 0,
        BackgroundColor3 = Color3.fromRGB(70, 220, 100),
        Selectable = false,
    }, health)

    local highlight = make("Highlight", {
        Name = "Highlight_" .. tostring(record.Player.UserId),
        Enabled = false,
        DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
        FillColor = STYLE.PlayerColor,
        OutlineColor = STYLE.PlayerColor,
        FillTransparency = STYLE.FillTransparency,
        OutlineTransparency = STYLE.OutlineTransparency,
    }, Artifacts)

    record.Visual = {
        Frame = frame,
        Name = name,
        Health = health,
        Fill = fill,
        Highlight = highlight,
    }
end

local function hideVisual(record)
    local visual = record.Visual

    if visual then
        visual.Frame.Visible = false
        visual.Highlight.Enabled = false
    end
end

local function bounds(currentCamera, character)
    local frame, size = character:GetBoundingBox()
    local half = size * 0.5

    local left = math.huge
    local top = math.huge
    local right = -math.huge
    local bottom = -math.huge

    for x = -1, 1, 2 do
        for y = -1, 1, 2 do
            for z = -1, 1, 2 do
                local point = project(
                    currentCamera,
                    frame:PointToWorldSpace(Vector3.new(
                        x * half.X, y * half.Y, z * half.Z
                    ))
                )

                if point.Z <= 0.1 then
                    return nil
                end

                left = math.min(left, point.X)
                top = math.min(top, point.Y)
                right = math.max(right, point.X)
                bottom = math.max(bottom, point.Y)
            end
        end
    end

    if right < 0 or bottom < 0
        or left > State.ScreenSize.X
        or top > State.ScreenSize.Y then
        return nil
    end

    return left, top, right, bottom
end

local function updateVisual(record, currentCamera)
    local visual = record.Visual

    if not visual then
        return
    end

    visual.Frame.Visible = false
    visual.Name.Visible = false
    visual.Health.Visible = false
    visual.Highlight.Enabled = false

    if not teamAllowed(record.Player, Config.Visuals.TeamCheck) then
        visual.Highlight.Adornee = nil
        return
    end

    local data = liveData(record)

    if not data then
        visual.Highlight.Adornee = nil
        return
    end

    -- Highlights are updated BEFORE other visuals' wall checks.
    visual.Highlight.Adornee = data.Character
    visual.Highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    visual.Highlight.Enabled = Config.Visuals.Highlights

    if not Config.Visuals.Names and not Config.Visuals.HealthBars then
        return
    end

    if not Config.Visuals.OtherVisualsThroughWalls
        and not visible(currentCamera, data.Character, data.Head.Position) then
        return
    end

    if Config.Visuals.Names then
        local point, onScreen = project(
            currentCamera,
            data.Head.Position + Vector3.new(
                0, data.Head.Size.Y * 0.5 + 0.35, 0
            )
        )

        if onScreen then
            visual.Name.Text = string.format(
                "%s (@%s)", record.Player.DisplayName, record.Player.Name
            )

            visual.Name.Position = UDim2.fromOffset(point.X, point.Y)
            visual.Name.Visible = true
        end
    end

    if Config.Visuals.HealthBars then
        local left, top, right, bottom = bounds(currentCamera, data.Character)

        if left then
            local fraction = math.clamp(data.Health / data.MaxHealth, 0, 1)

            visual.Health.Position = UDim2.fromOffset(right + 5, top)
            visual.Health.Size = UDim2.fromOffset(4, math.max(8, bottom - top))
            visual.Fill.Size = UDim2.fromScale(1, fraction)
            visual.Fill.BackgroundColor3 = Color3.fromHSV(fraction / 3, 0.85, 1)
            visual.Health.Visible = true
        end
    end

    visual.Frame.Visible = visual.Name.Visible or visual.Health.Visible
end

--==============================================================
-- PLAYER LIFECYCLE
--==============================================================

local function addPlayer(player)
    if Records[player] or not State.Running then
        return
    end

    local record = {
        Player = player,
        Character = nil,
        Scan = nil,
        Generation = 0,
        Revision = 0,
        Dirty = false,
        Busy = false,
        Due = 0,
        Observed = {},
        PlayerConnections = {},
        CharacterConnections = {},
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

        if player == LocalPlayer then
            resetActivation()
        end
    end, record.PlayerConnections)

    for _, property in ipairs({"Team", "Neutral"}) do
        connect(player:GetPropertyChangedSignal(property), changed, record.PlayerConnections)
    end

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

    disconnect(record.PlayerConnections)
    disconnect(record.CharacterConnections)

    for object, bucket in pairs(record.Observed) do
        disconnect(bucket)
        record.Observed[object] = nil
    end

    if record.Visual then
        record.Visual.Highlight:Destroy()
        record.Visual.Frame:Destroy()
    end

    changed()
end

connect(Players.PlayerAdded, addPlayer)
connect(Players.PlayerRemoving, removePlayer)

for _, player in ipairs(Players:GetPlayers()) do
    addPlayer(player)
end

--==============================================================
-- HITBOX V2 / SERVER SYNCHRONIZATION
--==============================================================

local HB = {
    Config = nil,
    Revision = -1,
    CanEdit = false,

    Scope = "Global",
    Key = nil,

    Pending = {},
    InFlight = {},
    Busy = false,
    Due = math.huge,

    Syncing = false,
    Ready = false,

    Boxes = {},
    Controls = {},
    TargetKeys = {},
}

local HBStatus = paragraph(
    Tabs.Hitbox, "Hitbox V2 — By 00B_qruel", "Connecting to server..."
)

local remotes = Package:WaitForChild("Remotes", 15)
local Request = remotes and remotes:WaitForChild("Request", 5)
local ServerChanged = remotes and remotes:WaitForChild("Changed", 5)

local function status(text)
    if State.Running then
        HBStatus:SetDesc(tostring(text))
    end
end

local function accept(response)
    if type(response) ~= "table" then
        return
    end

    if response.CanEdit ~= nil then
        HB.CanEdit = response.CanEdit == true
    end

    if type(response.Revision) == "number"
        and response.Revision >= HB.Revision
        and type(response.Config) == "table" then
        HB.Revision = response.Revision
        HB.Config = response.Config
    end
end

local function previewConfig()
    local result = copy(HB.Config)

    if not result then
        return nil
    end

    for _, batch in ipairs({HB.InFlight, HB.Pending}) do
        for _, change in pairs(batch) do
            local target

            if change.Scope == "Global" then
                target = result.Global
            else
                local bucket = change.Scope == "Team"
                    and result.Teams or result.Players

                if change.Key then
                    bucket[change.Key] = bucket[change.Key] or {}
                    target = bucket[change.Key]
                end
            end

            if target then
                target[change.Field] = copy(change.Value)
            end
        end
    end

    return result
end

local function resolve(config, teamName, userId)
    local result = copy(config.Global)
    local team = teamName and config.Teams[teamName]
    local personal = userId and config.Players[tostring(userId)]

    if team then
        for field, value in pairs(team) do
            result[field] = value
        end
    end

    if personal then
        for field, value in pairs(personal) do
            result[field] = value
        end
    end

    return result
end

local syncHB
local refreshTargets
local renderHitboxes
local teamDropdown
local targetDropdown

local function queue(field, value)
    if not HB.Ready or HB.Syncing or not State.Running then
        return
    end

    if not HB.CanEdit then
        status("Read-only: administrator access required.")
        syncHB()
        return
    end

    if HB.Scope ~= "Global" and not HB.Key then
        status("Select a team or player.")
        syncHB()
        return
    end

    local key = HB.Scope .. "\0" .. tostring(HB.Key) .. "\0" .. field

    local n = 0

    for _ in pairs(HB.Pending) do
        n += 1
    end

    if not HB.Pending[key] and n >= 24 then
        status("Waiting for pending changes to synchronize.")
        syncHB()
        return
    end

    HB.Pending[key] = {
        Scope = HB.Scope,
        Key = HB.Key,
        Field = field,
        Value = copy(value),
    }

    if HB.Due == math.huge then
        HB.Due = os.clock() + 0.18
    end

    status("Live preview — awaiting server approval.")
    renderHitboxes()
end

local function selectedSettings(config)
    if HB.Scope == "Global" then
        return config.Global
    elseif HB.Scope == "Team" then
        return resolve(config, HB.Key, nil)
    end

    local player = HB.Key
        and Players:GetPlayerByUserId(tonumber(HB.Key))

    return resolve(
        config,
        player and player.Team and player.Team.Name,
        HB.Key
    )
end

renderHitboxes = function()
    if not HB.Config then
        return
    end

    local config = previewConfig()
    local shown = {}

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local character = player.Character

            local humanoid = character
                and character:FindFirstChildWhichIsA("Humanoid", true)

            -- Matches the server's combat root selection.
            local root = humanoid and humanoid.RootPart
                or character
                    and character:FindFirstChild("HumanoidRootPart", true)
                or character and character.PrimaryPart

            local settings = resolve(
                config,
                player.Team and player.Team.Name,
                player.UserId
            )

            local allowed = settings.Enabled
                and settings.Visualization
                and character
                and character:IsDescendantOf(workspace)
                and humanoid
                and humanoid.Health > 0
                and root
                and root:IsA("BasePart")
                and root:IsDescendantOf(character)
                and not character:FindFirstChildWhichIsA("ForceField", true)

            if allowed and settings.TeamCheck and sameTeam(player) then
                allowed = false
            end

            if allowed and settings.SpecificTeams then
                allowed = player.Team
                    and table.find(settings.SelectedTeams, player.Team.Name) ~= nil
            end

            if allowed then
                local box = HB.Boxes[player]

                if not box then
                    box = make("BoxHandleAdornment", {
                        Name = "HitboxV2_" .. tostring(player.UserId),
                        CFrame = CFrame.identity,
                        AlwaysOnTop = false,
                        ZIndex = 1,
                    }, Artifacts)

                    HB.Boxes[player] = box
                end

                box.Adornee = root
                box.Size = Vector3.new(settings.X, settings.Y, settings.Z)
                box.Transparency = settings.Transparency
                box.Color3 = Color3.fromRGB(settings.R, settings.G, settings.B)
                box.Visible = true

                shown[player] = true
            end
        end
    end

    for player, box in pairs(HB.Boxes) do
        if not shown[player] then
            if player.Parent ~= Players then
                box:Destroy()
                HB.Boxes[player] = nil
            else
                box.Visible = false
                box.Adornee = nil
            end
        end
    end
end

local function perform(action)
    if not Request then
        status("Server unavailable.")
        return
    end

    if HB.Busy or next(HB.Pending) or next(HB.InFlight) then
        status("Wait for pending changes to finish.")
        return
    end

    if not HB.CanEdit then
        status("Administrator access required.")
        return
    end

    HB.Busy = true

    local scope = HB.Scope
    local key = HB.Key

    task.spawn(function()
        local ok, response = pcall(function()
            return Request:InvokeServer({
                Action = action,
                Scope = scope,
                Key = key,
            })
        end)

        HB.Busy = false

        if not State.Running then
            return
        end

        if ok and type(response) == "table" then
            accept(response)
            status(response.Message or "Completed.")
        else
            status("Server request failed.")
        end

        syncHB()
        renderHitboxes()
    end)
end

if Request and ServerChanged then
    connect(ServerChanged.OnClientEvent, function(response)
        accept(response)

        if HB.Ready then
            syncHB()
            renderHitboxes()
        end
    end)

    local ok, initial = pcall(function()
        return Request:InvokeServer({Action = "Get"})
    end)

    if ok then
        accept(initial)
    end
end

if HB.Config then
    section(Tabs.Hitbox, "Configuration scope")

    Tabs.Hitbox:Dropdown({
        Title = "Edit settings for",
        Values = {"Global", "Team", "Player"},
        Value = "Global",
        Multi = false,
        AllowNone = false,

        Callback = function(value)
            if HB.Ready and not HB.Syncing then
                HB.Scope = value
                HB.Key = nil
                refreshTargets()
                syncHB()
            end
        end,
    })

    targetDropdown = Tabs.Hitbox:Dropdown({
        Title = "Team / player",
        Values = {"Global defaults"},
        Value = "Global defaults",
        Multi = false,
        AllowNone = false,

        Callback = function(value)
            if HB.Ready and not HB.Syncing then
                HB.Key = HB.TargetKeys[value]
                syncHB()
            end
        end,
    })

    local function hbToggle(field, title)
        HB.Controls[field] = Tabs.Hitbox:Toggle({
            Title = title,
            Value = HB.Config.Global[field],

            Callback = function(value)
                queue(field, value)
            end,
        })
    end

    local function hbSlider(field, title, low, high, step)
        HB.Controls[field] = Tabs.Hitbox:Slider({
            Title = title,
            Step = step,
            Value = {
                Min = low,
                Max = high,
                Default = HB.Config.Global[field],
            },

            Callback = function(value)
                value = tonumber(value)

                if finite(value) then
                    queue(field, math.clamp(value, low, high))
                end
            end,
        })
    end

    section(Tabs.Hitbox, "Functional hitboxes")

    hbToggle("Enabled", "Enable hitbox expansion")
    hbSlider("X", "Width — X studs", 0.5, 30, 0.1)
    hbSlider("Y", "Height — Y studs", 0.5, 30, 0.1)
    hbSlider("Z", "Depth — Z studs", 0.5, 30, 0.1)

    section(Tabs.Hitbox, "Appearance")

    hbToggle("Visualization", "Show expanded hitboxes")
    hbSlider("Transparency", "Transparency", 0, 1, 0.05)
    hbSlider("R", "Red", 0, 255, 1)
    hbSlider("G", "Green", 0, 255, 1)
    hbSlider("B", "Blue", 0, 255, 1)

    section(Tabs.Hitbox, "Team filtering")

    hbToggle("TeamCheck", "Exclude attacker's teammates")
    hbToggle("SpecificTeams", "Enable team-specific targeting")

    teamDropdown = Tabs.Hitbox:Dropdown({
        Title = "Eligible target teams",
        Values = {},
        Value = {},
        Multi = true,
        AllowNone = true,

        Callback = function(values)
            queue("SelectedTeams", values)
        end,
    })

    syncHB = function()
        if not State.Running then
            return
        end

        local settings = selectedSettings(previewConfig())
        HB.Syncing = true

        for field, control in pairs(HB.Controls) do
            control:Set(settings[field])

            if HB.CanEdit then
                control:Unlock()
            else
                control:Lock()
            end
        end

        teamDropdown:Select(settings.SelectedTeams)

        if HB.CanEdit then
            teamDropdown:Unlock()
        else
            teamDropdown:Lock()
        end

        HB.Syncing = false
    end

    refreshTargets = function()
        if not State.Running then
            return
        end

        HB.Syncing = true

        local names = {}

        for _, team in ipairs(Teams:GetTeams()) do
            table.insert(names, team.Name)
        end

        table.sort(names)
        teamDropdown:Refresh(names)

        local labels = {}
        local selected
        local oldKey = HB.Key

        HB.TargetKeys = {}

        if HB.Scope == "Global" then
            labels = {"Global defaults"}
            selected = labels[1]

        elseif HB.Scope == "Team" then
            for _, name in ipairs(names) do
                table.insert(labels, name)
                HB.TargetKeys[name] = name

                if oldKey == name then
                    selected = name
                end
            end
        else
            for _, player in ipairs(Players:GetPlayers()) do
                local label = string.format(
                    "%s (@%s) [%d]",
                    player.DisplayName,
                    player.Name,
                    player.UserId
                )

                table.insert(labels, label)
                HB.TargetKeys[label] = tostring(player.UserId)

                if oldKey == tostring(player.UserId) then
                    selected = label
                end
            end

            table.sort(labels)
        end

        if #labels == 0 then
            labels = {"None available"}
        end

        selected = selected or labels[1]
        HB.Key = HB.TargetKeys[selected]

        targetDropdown:Refresh(labels)
        targetDropdown:Select(selected)

        HB.Syncing = false
    end

    section(Tabs.Hitbox, "Configuration management")

    Tabs.Hitbox:Button({
        Title = "Reset selected scope",
        Icon = "rotate-ccw",
        Callback = function()
            perform("Reset")
        end,
    })

    Tabs.Hitbox:Button({
        Title = "Save complete hitbox profile",
        Icon = "save",
        Callback = function()
            perform("Save")
        end,
    })

    Tabs.Hitbox:Button({
        Title = "Load saved hitbox profile",
        Icon = "folder-open",
        Callback = function()
            perform("Load")
        end,
    })

    paragraph(
        Tabs.Hitbox,
        "Inheritance",
        "Player overrides Team; Team overrides Global. "
            .. "Only changed fields become overrides. "
            .. "Reset restores inheritance. No offsets are used."
    )

    paragraph(
        Tabs.Hitbox,
        "Combat integration",
        "Your weapon server must call the installed HitboxV2 API. "
            .. "The configuration menu cannot apply damage."
    )

    HB.Ready = true
    refreshTargets()
    syncHB()

    status(HB.CanEdit
        and "Administrator controls ready. Sizes are in studs."
        or "Server-approved settings active. Controls are read-only."
    )
else
    status("Hitbox server unavailable. ESP and aim remain independent.")
end

--==============================================================
-- PERSONAL CONFIGURATION
--==============================================================

paragraph(Tabs.System, "Owner", "By 00B_qruel")

paragraph(
    Tabs.System,
    "Controls",
    "RightShift toggles the menu. "
        .. "The movable button can arm aiming on touch devices. "
        .. "Hitbox settings are approved by the server."
)

local PersonalStatus = paragraph(
    Tabs.System,
    "Personal settings",
    "Save/load applies only to your aim and visual preferences."
)

local function personalAction(action)
    if not Request then
        PersonalStatus:SetDesc("Server unavailable.")
        return
    end

    if HB.Busy or next(HB.Pending) or next(HB.InFlight) then
        PersonalStatus:SetDesc("Wait for pending server requests.")
        return
    end

    HB.Busy = true

    task.spawn(function()
        local ok, response = pcall(function()
            return Request:InvokeServer({
                Action = action,
                Preferences = action == "SaveUI" and Config or nil,
            })
        end)

        HB.Busy = false

        if not State.Running then
            return
        end

        if not ok or type(response) ~= "table" then
            PersonalStatus:SetDesc("Personal settings request failed.")
            return
        end

        if response.Ok and type(response.Preferences) == "table" then
            local incoming = response.Preferences

            for group, values in pairs(Config) do
                if type(incoming[group]) == "table" then
                    for field, default in pairs(values) do
                        local value = incoming[group][field]

                        if type(value) == type(default) then
                            Config[group][field] = value
                        end
                    end
                end
            end

            resetActivation()
            changed()

            Syncing = true

            for _, entry in ipairs(Controls) do
                local value = Config[entry.Group][entry.Field]

                if entry.Dropdown then
                    entry.Control:Select(value)
                else
                    entry.Control:Set(value)
                end
            end

            Syncing = false
        end

        PersonalStatus:SetDesc(response.Message or "Completed.")
    end)
end

Tabs.System:Button({
    Title = "Save personal settings",
    Icon = "save",
    Callback = function()
        personalAction("SaveUI")
    end,
})

Tabs.System:Button({
    Title = "Load personal settings",
    Icon = "folder-open",
    Callback = function()
        personalAction("LoadUI")
    end,
})

Tabs.System:Button({
    Title = "Release current target",
    Icon = "unlink",
    Callback = resetActivation,
})

--==============================================================
-- INPUT / MOBILE CONTROL
--==============================================================

local function matchesKey(input)
    if Config.Aim.Key == "MouseButton2" then
        return input.UserInputType == Enum.UserInputType.MouseButton2
    end

    return input.UserInputType == Enum.UserInputType.Keyboard
        and input.KeyCode.Name == Config.Aim.Key
end

connect(UserInputService.InputBegan, function(input, processed)
    if processed
        or not State.Focused
        or GuiService.MenuIsOpen
        or UserInputService:GetFocusedTextBox() then
        return
    end

    if Config.Aim.Enabled and Config.Aim.KeybindEnabled and matchesKey(input) then
        State.Held = true

        if Config.Aim.ActivationMode == "Toggle" then
            State.Toggled = not State.Toggled
            changed()
        end
    end
end)

connect(UserInputService.InputEnded, function(input)
    if matchesKey(input) then
        State.Held = false

        if Config.Aim.ActivationMode == "Hold" then
            changed()
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

connect(UserInputService.TextBoxFocused, resetActivation)
connect(GuiService.MenuOpened, resetActivation)

local Drag = {
    Input = nil,
    Start = nil,
    Position = nil,
    Moved = false,
    IgnoreUntil = 0,
}

local function clampFloating(position)
    local size = Canvas.AbsoluteSize

    if size.X <= 0 or size.Y <= 0 then
        return Vector2.new(0.5, 0.5)
    end

    local half = Floating.AbsoluteSize * 0.5

    return Vector2.new(
        math.clamp(
            position.X,
            half.X + 6,
            math.max(half.X + 6, size.X - half.X - 6)
        ) / size.X,

        math.clamp(
            position.Y,
            half.Y + 6,
            math.max(half.Y + 6, size.Y - half.Y - 6)
        ) / size.Y
    )
end

connect(Floating.InputBegan, function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1
        and input.UserInputType ~= Enum.UserInputType.Touch then
        return
    end

    Drag.Input = input
    Drag.Start = Vector2.new(input.Position.X, input.Position.Y)
    Drag.Position = Floating.AbsolutePosition + Floating.AbsoluteSize * 0.5
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

    if not touch and input.UserInputType ~= Enum.UserInputType.MouseMovement then
        return
    end

    local delta = Vector2.new(input.Position.X, input.Position.Y) - Drag.Start

    if delta.Magnitude > 7 then
        Drag.Moved = true
    end

    if Drag.Moved then
        local normalized = clampFloating(Drag.Position + delta)
        Floating.Position = UDim2.fromScale(normalized.X, normalized.Y)
    end
end)

connect(UserInputService.InputEnded, function(input)
    if not Drag.Input then
        return
    end

    local touch = Drag.Input.UserInputType == Enum.UserInputType.Touch

    if not (
        touch and input == Drag.Input
        or not touch and input.UserInputType == Enum.UserInputType.MouseButton1
    ) then
        return
    end

    if Drag.Moved then
        Drag.IgnoreUntil = os.clock() + 0.2

        local normalized = clampFloating(
            Floating.AbsolutePosition + Floating.AbsoluteSize * 0.5
        )

        Config.Aim.FloatingX = normalized.X
        Config.Aim.FloatingY = normalized.Y
    end

    Drag.Input = nil
end)

connect(Floating.Activated, function()
    if Drag.Moved or os.clock() < Drag.IgnoreUntil then
        return
    end

    local enabled = not (Config.Aim.Enabled and State.TouchArmed)

    setConfig("Aim", "Enabled", enabled)
    State.TouchArmed = enabled

    Syncing = true
    AimToggle:Set(enabled)
    Syncing = false
end)

local function updateFloating()
    Floating.Visible = Config.Aim.FloatingToggle

    local active = aimRequested()

    Floating.Text = not Config.Aim.Enabled
        and "AIM OFF"
        or active and "AIM ON"
        or "AIM READY"

    Floating.BackgroundColor3 = active
        and Color3.fromRGB(20, 105, 125)
        or Color3.fromRGB(30, 35, 48)

    if not Drag.Input and State.ScreenSize.X > 0 then
        local normalized = clampFloating(Vector2.new(
            Config.Aim.FloatingX * State.ScreenSize.X,
            Config.Aim.FloatingY * State.ScreenSize.Y
        ))

        Floating.Position = UDim2.fromScale(normalized.X, normalized.Y)
    end
end

--==============================================================
-- DISABLE MENU SELECTION NAVIGATION
--==============================================================

local MenuRoots = {}

local function menuObject(object)
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

local function clearSelection()
    if menuObject(GuiService.SelectedObject) then
        GuiService.SelectedObject = nil
    end
end

local function guard(object)
    if not object:IsA("GuiObject") or MenuConnections[object] then
        return
    end

    object.Selectable = false

    local bucket = {}
    MenuConnections[object] = bucket

    connect(object:GetPropertyChangedSignal("Selectable"), function()
        if State.Running and object.Selectable then
            object.Selectable = false
        end
    end, bucket)

    connect(object.Destroying, function()
        if MenuConnections[object] then
            disconnect(MenuConnections[object])
            MenuConnections[object] = nil
        end
    end, bucket)
end

for _, name in ipairs({
    "ScreenGui", "DropdownGui", "TooltipGui", "NotificationGui",
}) do
    local root = WindUI[name]

    if typeof(root) == "Instance" then
        table.insert(MenuRoots, root)

        for _, object in ipairs(root:GetDescendants()) do
            guard(object)
        end

        connect(root.DescendantAdded, guard)
    end
end

connect(GuiService:GetPropertyChangedSignal("SelectedObject"), clearSelection)
clearSelection()

--==============================================================
-- CLEANUP
--==============================================================

local WindowDestroyed = false

local function cleanup()
    if not State.Running then
        return
    end

    State.Running = false
    resetActivation()

    RunService:UnbindFromRenderStep(RenderName)
    clearSelection()
    disconnect(Connections)

    for _, record in pairs(Records) do
        record.Generation += 1
        record.Character = nil

        disconnect(record.PlayerConnections)
        disconnect(record.CharacterConnections)

        for object, bucket in pairs(record.Observed) do
            disconnect(bucket)
            record.Observed[object] = nil
        end
    end

    for object, bucket in pairs(MenuConnections) do
        disconnect(bucket)
        MenuConnections[object] = nil
    end

    Overlay:Destroy()
    Artifacts:Destroy()

    table.clear(Records)
    table.clear(HB.Boxes)

    Session.Cleanup = nil

    -- Unloading a client interface does not silently change
    -- the server's combat settings for everyone.
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
    Title = "Unload client menu and visuals",
    Icon = "trash-2",
    Callback = unload,
})

Session.Cleanup = unload

--==============================================================
-- BACKGROUND SCANNING / SYNCHRONIZATION
--==============================================================

local hitboxElapsed = 0
local listElapsed = 0

connect(RunService.Heartbeat, function(dt)
    if not State.Running then
        return
    end

    local now = os.clock()
    local own = Records[LocalPlayer]

    if own and own.Dirty and not own.Busy
        and own.Due <= now and State.ScanWorkers < 2 then
        Scanner.Start(own)
    end

    for _, record in pairs(Records) do
        if State.ScanWorkers >= 2 then
            break
        end

        if record.Dirty and not record.Busy and record.Due <= now then
            Scanner.Start(record)
        end
    end

    hitboxElapsed += dt
    listElapsed += dt

    if hitboxElapsed >= 0.05 then
        hitboxElapsed = 0
        renderHitboxes()
    end

    if HB.Ready and listElapsed >= 2 then
        listElapsed = 0
        refreshTargets()
        syncHB()
    end

    if not HB.Ready
        or HB.Busy
        or now < HB.Due
        or not next(HB.Pending) then
        return
    end

    HB.Busy = true
    HB.Due = math.huge
    HB.InFlight = HB.Pending
    HB.Pending = {}

    local changes = {}

    for _, change in pairs(HB.InFlight) do
        table.insert(changes, change)
    end

    task.spawn(function()
        local ok, response = pcall(function()
            return Request:InvokeServer({
                Action = "Set",
                Changes = changes,
            })
        end)

        HB.Busy = false
        HB.InFlight = {}

        if not State.Running then
            return
        end

        if ok and type(response) == "table" then
            accept(response)
            status(response.Message or "Synchronized.")
        else
            status("Update failed; unconfirmed preview reverted.")
        end

        syncHB()
        renderHitboxes()
    end)
end)

--==============================================================
-- RENDER LOOP
--==============================================================

local function hideAll()
    FOVCircle.Visible = false

    for _, record in pairs(Records) do
        hideVisual(record)
    end
end

RunService:BindToRenderStep(
    RenderName,
    Enum.RenderPriority.Camera.Value + 1,
    function(dt)
        if not State.Running then
            return
        end

        local currentCamera = workspace.CurrentCamera

        if not currentCamera then
            changed()
            hideAll()
            return
        end

        screenGeometry(currentCamera)
        updateFloating()

        if State.ScreenSize.X <= 0 or State.ScreenSize.Y <= 0 then
            hideAll()
            State.VisualElapsed = math.huge
            return
        end

        FOVCircle.Size = UDim2.fromOffset(
            Config.Aim.FOV * 2,
            Config.Aim.FOV * 2
        )

        FOVCircle.Visible = Config.Aim.Enabled and Config.Aim.ShowFOV

        local inputAllowed = State.Focused
            and liveData(Records[LocalPlayer]) ~= nil
            and not GuiService.MenuIsOpen
            and UserInputService:GetFocusedTextBox() == nil

        if inputAllowed and aimRequested() then
            local target = chooseTarget(currentCamera)

            if target then
                turnCamera(currentCamera, target.Part, dt)
            end
        else
            State.Target = nil
            State.NextAcquire = 0
        end

        State.VisualElapsed += dt

        if State.VisualElapsed >= 1 / 30 then
            State.VisualElapsed = 0

            for _, record in pairs(Records) do
                updateVisual(record, currentCamera)
            end
        end
    end
)

updateFloating()
]====]

--==============================================================
-- INSTALLATION / BACKUPS
--==============================================================

local backup = Instance.new("Folder")
backup.Name = "TargetingSuiteBackup_"
    .. os.date("!%Y%m%d_%H%M%S")
    .. "_"
    .. HttpService:GenerateGUID(false):sub(1, 8)

backup.Parent = ServerStorage

local function archive(parent, name)
    local old = parent:FindFirstChild(name)

    if not old then
        return
    end

    local saved = old:Clone()
    saved.Name = name .. "_From_" .. parent.Name

    if saved:IsA("BaseScript") then
        saved.Disabled = true
    end

    for _, descendant in ipairs(saved:GetDescendants()) do
        if descendant:IsA("BaseScript") then
            descendant.Disabled = true
        end
    end

    saved.Parent = backup
    old:Destroy()
end

-- Replace only this installer's own named objects.
archive(ReplicatedStorage, "TargetingSuite")
archive(ServerScriptService, "HitboxV2")
archive(ServerScriptService, "HitboxV2Start")
archive(starterScripts, "TargetingSuiteClient")

local package = Instance.new("Folder")
package.Name = "TargetingSuite"

local wind = Instance.new("ModuleScript")
wind.Name = "WindUI"
wind.Source = windSource
wind.Parent = package

package.Parent = ReplicatedStorage

local server = Instance.new("ModuleScript")
server.Name = "HitboxV2"
server.Source = SERVER_SOURCE
server:SetAttribute("InstallerUserId", installerUserId)
server.Parent = ServerScriptService

local start = Instance.new("Script")
start.Name = "HitboxV2Start"
start.Source = [[
require(script.Parent:WaitForChild("HitboxV2")).Start()
]]
start.Parent = ServerScriptService

local client = Instance.new("LocalScript")
client.Name = "TargetingSuiteClient"
client.Source = CLIENT_SOURCE
client.Parent = starterScripts

print("Targeting Suite + Hitbox V2 installed.")
print("Owner credit: By 00B_qruel")
print("Backup location: " .. backup:GetFullName())
print("Press Play to test. RightShift toggles the menu.")
print("No offsets were installed.")
print("Existing weapon damage handlers were NOT modified.")
print("Weapon integration API: ServerScriptService.HitboxV2")
