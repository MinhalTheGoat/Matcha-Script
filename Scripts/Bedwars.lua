if not _G.loadedFromMain then
    local mainSource = ""
    pcall(function()
        if _G.developer then
            mainSource = readfile("rise/main.lua")
        else
            mainSource = game:HttpGet("https://raw.githubusercontent.com/MinhalTheGoat/Matcha-Script/refs/heads/main/main.lua")
        end
    end)

    if type(mainSource) == "string" and #mainSource > 0 then
        _G.loadedFromMain = true
        loadstring(mainSource)()
    else
        print("Bedwars.lua: main.lua not available")
    end
    return
end

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

local REPO = "https://raw.githubusercontent.com/MinhalTheGoat/Matcha-Script/main"

local function removeInfo(info)
    for _, d in ipairs(info.drawings) do d:Remove() end
end

if _G.bw_executed then
    if _G.bw_heartbeat then _G.bw_heartbeat:Disconnect() end
    for _, info in pairs(_G.bw_tracks or {}) do removeInfo(info) end
end
_G.bw_executed = true

local tracks = {} ; _G.bw_tracks = tracks

-- // TYPES

local function isDrop(name)
    return function(obj)
        return obj:IsA("BasePart") and obj.Name == name and obj.Parent ~= nil and obj.Parent.Name == "ItemDrops"
    end
end

local function isCharacter(obj)
    return obj:IsA("Model") and obj:FindFirstChild("HumanoidRootPart") and obj:FindFirstChild("Humanoid") ~= nil
end

local function typeConfig(o)
    return {
        key = o.key, title = o.title, color = o.color,
        validate = o.validate, target = o.target,
        label = o.label or o.title,
        image = o.image,
        isDrop = o.isDrop or false,
        enabled = false,
        name = true,
        box = true,
        distance = false,
        icon = false,
    }
end

-- order matters: kit objects are checked before players / entities
local types = {
    typeConfig({ key = "bee", title = "Bee", color = Color3.fromRGB(255, 200, 0), image = "bee.dat",
        validate = function(obj) return obj.Name == "Bee" and obj:IsA("Model") end,
        target = function(obj) return obj:FindFirstChild("HumanoidRootPart") or obj:FindFirstChild("Part") or obj:FindFirstChildWhichIsA("BasePart") end }),

    typeConfig({ key = "metal", title = "Metal", color = Color3.fromRGB(180, 180, 180), image = "iron.dat",
        validate = function(obj) return obj:FindFirstChild("hidden-metal-prompt") ~= nil and obj:FindFirstChild("Part") ~= nil end,
        target = function(obj) return obj.Part end }),

    typeConfig({ key = "elder", title = "Elder", color = Color3.fromRGB(180, 180, 180),
        validate = function(obj) return obj.Name == "TreeOrb" and obj:IsA("Model") and obj:FindFirstChild("Spirit") ~= nil end,
        target = function(obj) return obj.Spirit end }),

    typeConfig({ key = "star", title = "Star", color = Color3.fromRGB(180, 180, 180),
        validate = function(obj) return obj:FindFirstChild("stars_ProximityPrompt") ~= nil and obj:FindFirstChild("RootPart") ~= nil end,
        target = function(obj) return obj.RootPart end,
        label = function(obj) return obj.Name end,
        image = function(obj)
            if obj.Name == "CritStar" then return "crit_star.dat" end
            if obj.Name == "VitalityStar" then return "vitality_star.dat" end
        end }),

    typeConfig({ key = "deathadder", title = "DeathAdder", color = Color3.fromRGB(186, 85, 211),
        validate = function(obj) return obj.Name == "AlchemyCrystal" and obj:FindFirstChild("2") ~= nil end,
        target = function(obj) return obj["2"] end }),

    typeConfig({ key = "iron", title = "Iron", color = Color3.fromRGB(200, 200, 200), isDrop = true,
        validate = isDrop("iron"), target = function(obj) return obj end }),

    typeConfig({ key = "diamond", title = "Diamond", color = Color3.fromRGB(0, 191, 255), isDrop = true,
        validate = isDrop("diamond"), target = function(obj) return obj end }),

    typeConfig({ key = "emerald", title = "Emerald", color = Color3.fromRGB(0, 230, 115), isDrop = true,
        validate = isDrop("emerald"), target = function(obj) return obj end }),

    typeConfig({ key = "player", title = "Player", color = Color3.fromRGB(255, 255, 255),
        validate = function(obj)
            if not isCharacter(obj) then return false end
            if obj == LocalPlayer.Character or obj.Name == LocalPlayer.Name then return false end
            return Players:FindFirstChild(obj.Name) ~= nil
        end,
        target = function(obj) return obj.HumanoidRootPart end,
        label = function(obj) return obj.Name end }),

    typeConfig({ key = "bed", title = "Bed", color = Color3.fromRGB(255, 0, 120),
        validate = function(obj)
            return (obj:IsA("MeshPart") and string.lower(obj.Name) == "bed") or (obj:IsA("Model") and obj.Name == "bed")
        end,
        target = function(obj)
            if obj:IsA("Model") then
                return obj:FindFirstChildWhichIsA("BasePart") or obj.PrimaryPart
            end
            return obj
        end }),

    typeConfig({ key = "entity", title = "Entity", color = Color3.fromRGB(255, 100, 100),
        validate = function(obj)
            if not isCharacter(obj) then return false end
            if obj == LocalPlayer.Character or obj.Name == LocalPlayer.Name then return false end
            return Players:FindFirstChild(obj.Name) == nil
        end,
        target = function(obj) return obj.HumanoidRootPart end,
        label = function(obj) return obj.Name end }),
}

local opts = {
    distance = 500,
    iconSize = 50,
    amount = false,
    showKit = false,
    showEquipped = false,
    bedPlates = false,
}

-- // BED PLATES
-- rough block health values used to sort the list; blocks that store
-- their own health attribute use that instead
local blockHealth = {
    wool = 20,
    wood = 90,
    planks = 90,
    oak_planks = 90,
    stone = 150,
    ender_stone = 150,
    brick = 300,
    glass = 5,
    ice = 5,
    obsidian = 1200,
}

local function bedBlocksText(bed)
    local params = OverlapParams.new()
    params.MaxParts = 300
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { bed }

    local ok, parts = pcall(function()
        return workspace:GetPartBoundsInRadius(bed.Position, 14, params)
    end)
    if not ok or type(parts) ~= "table" then return "" end

    local found = {}
    for _, part in ipairs(parts) do
        local name = part.Name
        if not part:GetAttribute("NoBreak") and not found[name] then
            local hp = part:GetAttribute("health") or part:GetAttribute("Health") or blockHealth[name]
            if type(hp) == "number" and hp > 0 then
                found[name] = hp
            end
        end
    end

    local list = {}
    for name, hp in pairs(found) do list[#list + 1] = { name = name, hp = hp } end
    table.sort(list, function(a, b) return a.hp > b.hp end)

    local names = {}
    for i, entry in ipairs(list) do
        if i > 6 then break end
        names[i] = entry.name
    end
    return table.concat(names, ", ")
end

-- // CONFIG

local configPath = "rise/configs/bw_" .. tostring(game.PlaceId) .. ".json"

local function colorToTable(c) return { r = c.R, g = c.G, b = c.B } end

local function colorFromTable(t)
    if type(t) ~= "table" then return nil end
    local r, g, b = tonumber(t.r), tonumber(t.g), tonumber(t.b)
    if not (r and g and b) then return nil end
    return Color3.new(math.clamp(r, 0, 1), math.clamp(g, 0, 1), math.clamp(b, 0, 1))
end

local function saveConfig()
    pcall(function()
        local saved = {}
        for _, t in ipairs(types) do
            saved[t.key] = {
                enabled = t.enabled, name = t.name, box = t.box, distance = t.distance, icon = t.icon,
                color = colorToTable(t.color),
            }
        end
        writefile(configPath, HttpService:JSONEncode({ options = opts, types = saved }))    end)
end

local function loadConfig()
    pcall(function()
        if not isfile(configPath) then return end
        local content = readfile(configPath)
        if type(content) ~= "string" or #content == 0 then return end

        local parsed = HttpService:JSONDecode(content)
        if type(parsed) ~= "table" then return end

        local o = parsed.options
        if type(o) == "table" then
            if type(o.distance) == "number" then opts.distance = o.distance end
            if type(o.iconSize) == "number" then opts.iconSize = o.iconSize end
            if type(o.amount) == "boolean" then opts.amount = o.amount end
            if type(o.showKit) == "boolean" then opts.showKit = o.showKit end
            if type(o.showEquipped) == "boolean" then opts.showEquipped = o.showEquipped end
            if type(o.bedPlates) == "boolean" then opts.bedPlates = o.bedPlates end
        end

        if type(parsed.types) == "table" then
            for _, t in ipairs(types) do
                local s = parsed.types[t.key]
                if type(s) == "table" then
                    for _, k in ipairs({ "enabled", "name", "box", "distance", "icon" }) do
                        -- older configs saved drops with the name off
                        if type(s[k]) == "boolean" and not (t.isDrop and k == "name") then t[k] = s[k] end
                    end
                    local c = colorFromTable(s.color)
                    if c then t.color = c end
                end
            end
        end
    end)
end

loadConfig()

-- // HELPERS

local images = _G.bw_images or {}
_G.bw_images = images

local function loadImage(name)
    if images[name] then return images[name] end
    local data
    local filePath = "rise/assets/" .. name
    if isfile(filePath) then
        data = readfile(filePath)
    else
        local ok, res = pcall(function() return game:HttpGet(REPO .. "/Assets/" .. name) end)
        if ok then data = res end
    end
    if type(data) == "string" and #data > 0 then images[name] = data end
    return images[name]
end

local function hide(info)
    for _, d in ipairs(info.drawings) do d.Visible = false end
end

local function newText(color)
    local t = Drawing.new("Text")
    t.Text = "" ; t.Center = true ; t.Outline = true
    t.Color = color ; t.Size = 16 ; t.Visible = false
    return t
end

local function newBox(color)
    local b = Drawing.new("Square")
    b.Thickness = 1 ; b.Filled = false
    b.Color = color ; b.Visible = false
    return b
end

local function newIcon(data)
    local img = Drawing.new("Image")
    img.Visible = false ; img.Data = data
    img.Size = Vector2.new(44, 44) ; img.Rounding = 4 ; img.ZIndex = 5

    local bg = Drawing.new("Square")
    bg.Visible = false ; bg.Filled = true
    bg.Color = Color3.fromRGB(0, 0, 0) ; bg.Transparency = 0.5 ; bg.Corner = 10 ; bg.ZIndex = 4

    return img, bg
end

local function getHRP()
    local c = LocalPlayer.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function getPlayerKit(char)
    local plr = Players:FindFirstChild(char.Name)
    if plr then
        local kit = plr:GetAttribute("PlayingAsKits") or plr:GetAttribute("PlayingAsKit")
        if kit then return tostring(kit) end
    end
    return "None"
end

local function getEquippedItem(char)
    for _, child in ipairs(char:GetChildren()) do
        if child:GetAttribute("InvItem") == true then
            return child.Name
        end
    end
    return "None"
end

local function createInfo(obj, t, part)
    local label = type(t.label) == "function" and t.label(obj) or t.label
    local imageName = type(t.image) == "function" and t.image(obj) or t.image
    local data = imageName and loadImage(imageName) or nil

    local info = { type = t, obj = obj, part = part, label = label }
    info.text = newText(t.color)
    info.box = newBox(t.color)
    info.drawings = { info.text, info.box }

    if data then
        local ok, img, bg = pcall(newIcon, data)
        if ok and img then
            info.img = img ; info.bg = bg
            info.drawings = { info.text, info.box, img, bg }
        end
    end

    tracks[obj] = info
end

-- // SCAN

local function scan()
    local valid = {}

    local function check(obj)
        for _, t in ipairs(types) do
            if t.validate(obj) then
                local part = t.target(obj)
                if part then
                valid[obj] = true
                if not tracks[obj] then createInfo(obj, t, part) end
                if t.key == "bed" and opts.bedPlates then
                    tracks[obj].blocks = bedBlocksText(part)
                end
                end
                return
            end
        end
    end

    for _, obj in ipairs(workspace:GetChildren()) do check(obj) end
    local drops = workspace:FindFirstChild("ItemDrops")
    if drops then
        for _, obj in ipairs(drops:GetChildren()) do check(obj) end
    end

    for obj, info in pairs(tracks) do
        if not valid[obj] or not obj.Parent then removeInfo(info) ; tracks[obj] = nil end
    end
end

-- // UPDATE

local function update(info, hrp)
    local t = info.type
    local root = info.part
    if not t.enabled or not root.Parent then hide(info) return end

    local screen, on = WorldToScreen(root.Position)
    local dist = (hrp.Position - root.Position).Magnitude
    if not on or dist > opts.distance then hide(info) return end

    local topY
    if t.icon and info.img then
        local size = opts.iconSize
        info.img.Size = Vector2.new(size, size)
        info.img.Position = Vector2.new(screen.X - size / 2, screen.Y - size / 2)
        info.img.Visible = true
        if info.bg then
            info.bg.Size = Vector2.new(size + 10, size + 10)
            info.bg.Position = Vector2.new(screen.X - (size + 10) / 2, screen.Y - (size + 10) / 2)
            info.bg.Visible = true
        end
        topY = screen.Y - size / 2
    else
        local s = root.Size
        local tl = WorldToScreen((root.CFrame * CFrame.new(-s.X / 2, s.Y / 2, 0)).Position)
        local br = WorldToScreen((root.CFrame * CFrame.new(s.X / 2, -s.Y / 2, 0)).Position)
        local w = math.abs(tl.X - br.X)
        local h = math.abs(tl.Y - br.Y)
        info.box.Position = Vector2.new(screen.X - w / 2, screen.Y - h / 2)
        info.box.Size = Vector2.new(w, h)
        info.box.Color = t.color
        info.box.Visible = t.box and not t.isDrop
        topY = screen.Y - h / 2
    end

    local lines = {}
    if t.name then lines[#lines + 1] = info.label end
    if t.distance then lines[#lines + 1] = math.floor(dist) .. "m" end
    if t.isDrop and opts.amount then lines[#lines + 1] = "x" .. tostring(info.obj:GetAttribute("Amount") or 1) end
    if t.key == "player" and opts.showKit then
        local kit = getPlayerKit(info.obj)
        lines[#lines + 1] = "Kit: " .. string.upper(string.sub(kit, 1, 1)) .. string.sub(kit, 2)
    end
    if t.key == "player" and opts.showEquipped then lines[#lines + 1] = "Holding: " .. getEquippedItem(info.obj) end
    if t.key == "bed" and opts.bedPlates and info.blocks and #info.blocks > 0 then
        lines[#lines + 1] = info.blocks
    end

    -- with an icon the label sits underneath it, otherwise above the box
    local textY = (t.icon and info.img) and (topY + opts.iconSize + 6) or (topY - 16 - (#lines - 1) * 18)
    info.text.Position = Vector2.new(screen.X, textY)
    info.text.Color = t.color
    info.text.Text = table.concat(lines, "\n")
    info.text.Visible = #lines > 0
end

-- // UI

UI.AddTab("Bedwars", function(tab)

    local function addType(sec, t)
        local key = "bw_" .. t.key
        sec:Toggle(key .. "_on", t.title .. " ESP", t.enabled, function(state)
            t.enabled = state
            if not state then
                for _, info in pairs(tracks) do if info.type == t then hide(info) end end
            end
            saveConfig()
        end)
        -- item drops only get their ESP toggle
        if t.isDrop then return end
        sec:ColorPicker(key .. "_col", t.color.R, t.color.G, t.color.B, 1, function(color)
            t.color = color
            saveConfig()
        end)
        if t.image then
            sec:Toggle(key .. "_icon", t.title .. " Icon", t.icon, function(state)
                t.icon = state
                saveConfig()
            end)
        end
        sec:Toggle(key .. "_name", t.title .. " Name", t.name, function(state)
            t.name = state
            saveConfig()
        end)
        sec:Toggle(key .. "_box", t.title .. " Box", t.box, function(state)
            t.box = state
            saveConfig()
        end)
        sec:Toggle(key .. "_dist", t.title .. " Distance", t.distance, function(state)
            t.distance = state
            saveConfig()
        end)
    end

    local byKey = {}
    for _, t in ipairs(types) do byKey[t.key] = t end

    local sec = tab:Section("Kit ESP", "Left")

    -- // BEE
    addType(sec, byKey.bee)
    sec:Spacing()

    -- // METAL
    addType(sec, byKey.metal)
    sec:Spacing()

    -- // ELDER
    addType(sec, byKey.elder)
    sec:Spacing()

    -- // STAR
    addType(sec, byKey.star)
    sec:Spacing()

    -- // DEATHADDER
    addType(sec, byKey.deathadder)

    sec = tab:Section("Item ESP", "Left")

    -- // IRON
    addType(sec, byKey.iron)
    sec:Spacing()

    -- // DIAMOND
    addType(sec, byKey.diamond)
    sec:Spacing()

    -- // EMERALD
    addType(sec, byKey.emerald)
    sec:Spacing()

    sec:Toggle("bw_amount", "Show Amount", opts.amount, function(state)
        opts.amount = state
        saveConfig()
    end)

    sec = tab:Section("Game ESP", "Left")

    -- // PLAYER
    addType(sec, byKey.player)
    sec:Toggle("bw_show_kit", "Show Kit", opts.showKit, function(state)
        opts.showKit = state
        saveConfig()
    end)
    sec:Toggle("bw_show_equipped", "Show Equipped", opts.showEquipped, function(state)
        opts.showEquipped = state
        saveConfig()
    end)
    sec:Toggle("bw_bed_plates", "Bed Plates", opts.bedPlates, function(state)
        opts.bedPlates = state
        if not state then
            for _, info in pairs(tracks) do info.blocks = nil end
        end
        saveConfig()
    end)
    sec:Spacing()

    -- // BED
    addType(sec, byKey.bed)
    sec:Spacing()

    -- // ENTITY
    addType(sec, byKey.entity)

    sec = tab:Section("Options", "Left")

    sec:SliderInt("bw_distance", "Max Distance", 50, 2000, opts.distance, function(val)
        opts.distance = val
        saveConfig()
    end)

end)

-- // LOOP

scan()

local scanTimer = 0
_G.bw_heartbeat = RunService.Heartbeat:Connect(function(dt)
    scanTimer = scanTimer + dt
    if scanTimer >= 1 then
        scanTimer = 0
        scan()
    end
    if not next(tracks) then return end

    local hrp = getHRP()
    if not hrp then
        for _, info in pairs(tracks) do hide(info) end
        return
    end
    for _, info in pairs(tracks) do update(info, hrp) end
end)
