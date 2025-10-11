--// Mobile-Friendly Draggable UI + Tabs + Minimize + Multi-select Catch Power
-- Place as LocalScript in StarterPlayerScripts or StarterGui

--== Services ==--
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

--== Net (sleitnick_net) ==--
local Net = ReplicatedStorage:WaitForChild("Packages")
    :WaitForChild("_Index")
    :WaitForChild("sleitnick_net@0.2.0")
    :WaitForChild("net")

local RFChargeFishingRod    = Net:WaitForChild("RF/ChargeFishingRod")
local RFStartMinigame       = Net:WaitForChild("RF/RequestFishingMinigameStarted")
local REReplicateTextEffect = Net:WaitForChild("RE/ReplicateTextEffect")
local REFishingCompleted    = Net:WaitForChild("RE/FishingCompleted")
local RFPurchaseWeatherEvent = Net:WaitForChild("RF/PurchaseWeatherEvent")

--== Config ==--
local COOLDOWN_CATCH = 0.25
local RECHARGE_DELAY = 1.00
local MAX_RETRY_RF   = 2

-- Power buckets (multi-select)
local POWER_OPTIONS = {
    {key="GOOD",     min=0.50, max=0.50},
    {key="GREAT",    min=0.60, max=0.70},
    {key="AMAZING",  min=0.80, max=0.80},
    {key="PERFECT",  min=0.96, max=0.99},
}

-- Fixed-X mode (sesuai permintaanmu)
local FIXED_X_VALUE = -0.5718746185302734
local MODE_DIR = "fixed"  -- "fixed" | "look"

-- Contoh daftar teleport (isi sendiri posisimu)
local TELEPORTS = {
    {"Esoteric Island",      CFrame.new(2026, 27.40,   1390)},
    {"Iceland",    CFrame.new(1604, 4.29, 3276)},
    {"Creater Island",     CFrame.new(962, 7.4, 4872)},
    {"Esoteric Depths",     CFrame.new(2979, -1302, 1519)},
    {"Kohana",     CFrame.new(-684, 3.1, 796)},
    {"Kohana Volcano",     CFrame.new(-584, 49.2, 215)},
    {"Weather Machine",     CFrame.new(-1510, 6.5, 1894)},
    {"Coral Reefs",     CFrame.new(-2775, 4.1, 2150)},
    {"Tropical Grove",     CFrame.new(-2041, 6.3, 3663)},
    {"Sacred Temple", CFrame.new(1487, 7.9, -533)},
}

--== State ==--
local running   = false
local busyCatch = false
local lastCastAt = -math.huge

-- Multi-select storage -> set of keys
local selectedKeys = { PERFECT = true }  -- default pilih PERFECT

--== Helpers ==--
local function safeInvoke(rf, ...)
    local args = { ... }
    for _ = 1, MAX_RETRY_RF do
        local ok, res = pcall(function()
            return rf:InvokeServer(table.unpack(args))
        end)
        if ok then return true, res end
        task.wait(0.2)
    end
    return false, nil
end

local function choosePower()
    -- Ambil daftar opsi yang currently selected
    local pool = {}
    for _, opt in ipairs(POWER_OPTIONS) do
        if selectedKeys[opt.key] then
            table.insert(pool, opt)
        end
    end
    if #pool == 0 then
        -- fallback: PERFECT
        for _, opt in ipairs(POWER_OPTIONS) do
            if opt.key == "PERFECT" then return opt end
        end
        return POWER_OPTIONS[#POWER_OPTIONS]
    end
    return pool[math.random(1, #pool)]
end

local function clamp01(v)
    if v > 1 then return 1 elseif v < -1 then return -1 else return v end
end

local function randBetween(a, b)
    if a == b then return a end
    return a + (b - a) * math.random()
end

local function getDirXZ()
    -- Pilih 1 power secara acak dari multi-select
    local opt = choosePower()
    local m = randBetween(opt.min, opt.max)

    if MODE_DIR == "fixed" then
        return clamp01(FIXED_X_VALUE), clamp01(m)
    end

    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local root = char:WaitForChild("HumanoidRootPart")
    local v = root.CFrame.LookVector
    local mag = math.sqrt(v.X*v.X + v.Z*v.Z)
    if mag < 1e-6 then
        return clamp01(FIXED_X_VALUE), clamp01(m)
    end
    local ux, uz = v.X/mag, v.Z/mag
    return clamp01(ux * m), clamp01(uz * m)
end

local function charge()
    if not running then return end
    local ok1 = select(1, safeInvoke(RFChargeFishingRod, workspace:GetServerTimeNow()))
    if not ok1 then return end
    local x, z = getDirXZ()
    local ok2 = select(1, safeInvoke(RFStartMinigame, x, z))
    if ok2 then
        lastCastAt = workspace:GetServerTimeNow()
    end
end

-- Smart exclaim check (pakai AttachTo/Container/owner)
local function isMyExclaim(payload)
    if typeof(payload) ~= "table" then return false end
    local td = payload.TextData
    local effect = (td and td.EffectType) or payload.EffectType
    if effect ~= "Exclaim" then return false end

    local inst = (td and (td.AttachTo or td.Adornee))
              or payload.Container
              or payload.AttachTo

    if typeof(inst) ~= "Instance" then return false end

    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    if inst:IsDescendantOf(char) then return true end

    local owner = inst:FindFirstAncestorOfClass("Model")
    return owner and Players:GetPlayerFromCharacter(owner) == LocalPlayer
end

REReplicateTextEffect.OnClientEvent:Connect(function(payload)
    if not running then return end
    if not isMyExclaim(payload) then return end
    if busyCatch then return end

    busyCatch = true
    task.wait(1.8)
    pcall(function() REFishingCompleted:FireServer() end)

    task.delay(COOLDOWN_CATCH, function() busyCatch = false end)
    task.delay(RECHARGE_DELAY, function()
        if running then charge() end
    end)
end)

local WEATHER_DEBOUNCE = 0.5
local lastWeatherAt = 0

local function purchaseWeather(kind)
    local now = os.clock()
    if now - lastWeatherAt < WEATHER_DEBOUNCE then return end
    lastWeatherAt = now

    local ok, res = safeInvoke(RFPurchaseWeatherEvent, kind)
    if not ok then
        warn(("[Weather] purchase '%s' gagal"):format(tostring(kind)))
        return false
    end
    return true
end

--== UI BUILD ==--
local function buildUI()
    local screen = Instance.new("ScreenGui")
    screen.Name = "AF_Menu"
    screen.IgnoreGuiInset = true
    screen.DisplayOrder = 1000
    screen.ResetOnSpawn = false
    screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screen.Parent = LocalPlayer:WaitForChild("PlayerGui")

    -- Root (centered first time)
    local root = Instance.new("Frame")
    root.Name = "Root"
    root.AnchorPoint = Vector2.new(0.5, 0.5)
    root.Position = UDim2.fromScale(0.5, 0.5)      -- muncul di tengah
    root.Size = UDim2.fromScale(0.46, 0.45)         -- responsive untuk mobile
    root.BackgroundColor3 = Color3.fromRGB(22, 22, 22)
    root.BorderSizePixel = 0
    root.Parent = screen
    local rc = Instance.new("UICorner", root)
    rc.CornerRadius = UDim.new(0, 14)

    -- Header (drag handle + minimize)
    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.fromScale(1, 0.14)
    header.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    header.BorderSizePixel = 0
    header.Parent = root

    local hc = Instance.new("UICorner", header)
    hc.CornerRadius = UDim.new(0, 14)

    local title = Instance.new("TextLabel")
    title.BackgroundTransparency = 1
    title.Text = "Utility Menu"
    title.TextColor3 = Color3.fromRGB(235,235,235)
    title.Font = Enum.Font.GothamBold
    title.TextScaled = true
    title.Size = UDim2.fromScale(0.7, 1)
    title.Position = UDim2.fromScale(0.03, 0)
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = header

    local minimize = Instance.new("TextButton")
    minimize.Text = "–"
    minimize.Size = UDim2.fromScale(0.12, 0.7)
    minimize.Position = UDim2.fromScale(0.85, 0.15)
    minimize.BackgroundColor3 = Color3.fromRGB(50,50,50)
    minimize.TextColor3 = Color3.fromRGB(255,255,255)
    minimize.Font = Enum.Font.GothamBold
    minimize.TextScaled = true
    minimize.Parent = header
    local minc = Instance.new("UICorner", minimize)
    minc.CornerRadius = UDim.new(0, 10)

    -- Tab bar
    local tabs = Instance.new("Frame")
    tabs.Name = "Tabs"
    tabs.Size = UDim2.fromScale(1, 0.1)
    tabs.Position = UDim2.fromScale(0, 0.14)
    tabs.BackgroundTransparency = 1
    tabs.Parent = root

    local tabLayout = Instance.new("UIListLayout", tabs)
    tabLayout.FillDirection = Enum.FillDirection.Horizontal
    tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
    tabLayout.Padding = UDim.new(0, 8)

    local function makeTabButton(text)
        local b = Instance.new("TextButton")
        b.Text = text
        b.Size = UDim2.fromScale(0.25, 1)
        b.BackgroundColor3 = Color3.fromRGB(40,40,40)
        b.TextColor3 = Color3.fromRGB(255,255,255)
        b.Font = Enum.Font.GothamMedium
        b.TextScaled = true
        b.Parent = tabs
        local c = Instance.new("UICorner", b)
        c.CornerRadius = UDim.new(0, 8)
        return b
    end

    local tabAutomation = makeTabButton("Automation")
    local tabTeleport   = makeTabButton("Teleport")
    local tabWeather    = makeTabButton("Weather")

    -- Pages container
    local pages = Instance.new("Frame")
    pages.Name = "Pages"
    pages.Size = UDim2.fromScale(1, 0.76)
    pages.Position = UDim2.fromScale(0, 0.24)
    pages.BackgroundTransparency = 1
    pages.Parent = root

    -- Page helper
    local function makePage()
        local p = Instance.new("Frame")
        p.BackgroundTransparency = 1
        p.Size = UDim2.fromScale(1,1)
        p.Visible = false
        p.Parent = pages
        return p
    end

    -- Page: Automation
    local pgAuto = makePage(); pgAuto.Visible = true

    local autoList = Instance.new("UIListLayout", pgAuto)
    autoList.Padding = UDim.new(0, 10)
    autoList.SortOrder = Enum.SortOrder.LayoutOrder

    -- Row: Status + Toggle
    local status = Instance.new("TextLabel")
    status.BackgroundTransparency = 1
    status.Text = "Auto Fishing: OFF"
    status.TextColor3 = Color3.fromRGB(255,90,90)
    status.Font = Enum.Font.GothamMedium
    status.TextScaled = true
    status.Size = UDim2.fromScale(1, 0.16)
    status.Parent = pgAuto

    local toggle = Instance.new("TextButton")
    toggle.Text = "Start"
    toggle.TextScaled = true
    toggle.Font = Enum.Font.GothamBold
    toggle.Size = UDim2.fromScale(1, 0.18)
    toggle.BackgroundColor3 = Color3.fromRGB(55,55,55)
    toggle.TextColor3 = Color3.fromRGB(255,255,255)
    toggle.Parent = pgAuto
    Instance.new("UICorner", toggle).CornerRadius = UDim.new(0, 10)

    -- Group: Catch Options (multi-select grid)
    local caption = Instance.new("TextLabel")
    caption.BackgroundTransparency = 1
    caption.Text = "Catch Power (multi-select)"
    caption.TextColor3 = Color3.fromRGB(220,220,220)
    caption.Font = Enum.Font.GothamMedium
    caption.TextScaled = true
    caption.Size = UDim2.fromScale(1, 0.14)
    caption.Parent = pgAuto

    local grid = Instance.new("Frame")
    grid.BackgroundTransparency = 1
    grid.Size = UDim2.fromScale(1, 0.32)
    grid.Parent = pgAuto

    local gridLayout = Instance.new("UIGridLayout", grid)
    gridLayout.CellPadding = UDim2.fromScale(0.03, 0.08)
    gridLayout.CellSize    = UDim2.fromScale(0.46, 0.42)

    local optButtons = {}

    local function refreshOptButtons()
        for _, btn in ipairs(optButtons) do
            local key = btn:GetAttribute("Key")
            local on = selectedKeys[key] == true
            btn.BackgroundColor3 = on and Color3.fromRGB(80,80,140) or Color3.fromRGB(45,45,45)
        end
        status.Text = running and "Auto Fishing: ON" or "Auto Fishing: OFF"
        status.TextColor3 = running and Color3.fromRGB(120,255,120) or Color3.fromRGB(255,90,90)
        toggle.Text = running and "Stop" or "Start"
    end

    local function makeOpt(opt)
        local b = Instance.new("TextButton")
        b.Text = opt.key
        b:SetAttribute("Key", opt.key)
        b.TextScaled = true
        b.Font = Enum.Font.GothamMedium
        b.TextColor3 = Color3.fromRGB(255,255,255)
        b.BackgroundColor3 = Color3.fromRGB(45,45,45)
        b.Parent = grid
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)

        b.MouseButton1Click:Connect(function()
            local key = b:GetAttribute("Key")
            selectedKeys[key] = not selectedKeys[key]
            refreshOptButtons()
        end)
        table.insert(optButtons, b)
    end

    for _, opt in ipairs(POWER_OPTIONS) do makeOpt(opt) end
    refreshOptButtons()

    toggle.MouseButton1Click:Connect(function()
        running = not running
        refreshOptButtons()
        if running then charge() end
    end)

    -- Page: Teleport
    local pgTp = makePage()

    local tpList = Instance.new("UIListLayout", pgTp)
    tpList.SortOrder = Enum.SortOrder.LayoutOrder
    tpList.Padding = UDim.new(0, 10)

    local tpInfo = Instance.new("TextLabel")
    tpInfo.BackgroundTransparency = 1
    tpInfo.Text = "Teleport targets"
    tpInfo.TextColor3 = Color3.fromRGB(220,220,220)
    tpInfo.Font = Enum.Font.GothamMedium
    tpInfo.TextScaled = true
    tpInfo.Size = UDim2.fromScale(1, 0.16)
    tpInfo.Parent = pgTp

    local function makeTpButton(name, cf)
        local b = Instance.new("TextButton")
        b.Text = name
        b.TextScaled = true
        b.Font = Enum.Font.GothamBold
        b.TextColor3 = Color3.fromRGB(255,255,255)
        b.BackgroundColor3 = Color3.fromRGB(55,55,55)
        b.Size = UDim2.fromScale(1, 0.18)
        b.Parent = pgTp
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 10)

        b.MouseButton1Click:Connect(function()
            local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
            local root = char:FindFirstChild("HumanoidRootPart")
            if root then root.CFrame = cf end
        end)
    end

    for _, item in ipairs(TELEPORTS) do
        makeTpButton(item[1], item[2])
    end

    -- Page: Weather
    local pgWeather = makePage()
    
    local weatherList = Instance.new("UIListLayout", pgWeather)
    weatherList.SortOrder = Enum.SortOrder.LayoutOrder
    weatherList.Padding = UDim.new(0, 10)
    
    local wInfo = Instance.new("TextLabel")
    wInfo.BackgroundTransparency = 1
    wInfo.Text = "Purchase Weather"
    wInfo.TextColor3 = Color3.fromRGB(220,220,220)
    wInfo.Font = Enum.Font.GothamMedium
    wInfo.TextScaled = true
    wInfo.Size = UDim2.fromScale(1, 0.16)
    wInfo.Parent = pgWeather
    
    local function makeWeatherButton(label, kind)
        local b = Instance.new("TextButton")
        b.Text = label
        b.TextScaled = true
        b.Font = Enum.Font.GothamBold
        b.TextColor3 = Color3.fromRGB(255,255,255)
        b.BackgroundColor3 = Color3.fromRGB(55,55,55)
        b.Size = UDim2.fromScale(1, 0.18)
        b.Parent = pgWeather
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 10)
    
        b.MouseButton1Click:Connect(function()
            local ok = purchaseWeather(kind)
            if ok then
                wInfo.Text = ("Purchased: %s"):format(label)
                wInfo.TextColor3 = Color3.fromRGB(120,255,120)
                task.delay(1.2, function()
                    if pgWeather.Visible then
                        wInfo.Text = "Purchase Weather"
                        wInfo.TextColor3 = Color3.fromRGB(220,220,220)
                    end
                end)
            else
                wInfo.Text = ("Failed: %s"):format(label)
                wInfo.TextColor3 = Color3.fromRGB(255,90,90)
            end
        end)
    end
    
    makeWeatherButton("Storm",  "Storm")
    makeWeatherButton("Cloudy", "Cloudy")
    makeWeatherButton("Wind",   "Wind")

    -- Tab switching
    local function showPage(which)
        pgAuto.Visible    = (which == "auto")
        pgTp.Visible      = (which == "tp")
        pgWeather.Visible = (which == "weather")
    
        tabAutomation.BackgroundColor3 = (which=="auto")    and Color3.fromRGB(70,70,120) or Color3.fromRGB(40,40,40)
        tabTeleport.BackgroundColor3   = (which=="tp")      and Color3.fromRGB(70,70,120) or Color3.fromRGB(40,40,40)
        tabWeather.BackgroundColor3    = (which=="weather") and Color3.fromRGB(70,70,120) or Color3.fromRGB(40,40,40)
    end
    tabAutomation.MouseButton1Click:Connect(function() showPage("auto") end)
    tabTeleport.MouseButton1Click:Connect(function() showPage("tp") end)
    tabWeather.MouseButton1Click:Connect(function() showPage("weather") end)
    showPage("auto")

    -- Minimize → bubble
    local bubble -- created on minimize
    local minimized = false
    local function doMinimize()
        if minimized then return end
        minimized = true
        root.Visible = false

        bubble = Instance.new("TextButton")
        bubble.Name = "AF_Bubble"
        bubble.Text = "≡"
        bubble.Size = UDim2.fromScale(0.12, 0.08)
        bubble.Position = UDim2.fromScale(0.86, 0.06)
        bubble.BackgroundColor3 = Color3.fromRGB(55,55,55)
        bubble.TextScaled = true
        bubble.TextColor3 = Color3.fromRGB(255,255,255)
        bubble.Parent = screen
        Instance.new("UICorner", bubble).CornerRadius = UDim.new(1, 0)

        bubble.MouseButton1Click:Connect(function()
            minimized = false
            if bubble then bubble:Destroy() bubble=nil end
            root.Visible = true
        end)
    end
    minimize.MouseButton1Click:Connect(doMinimize)

    -- Dragging (touch & mouse)
    local dragging = false
    local dragStart, startPos

    local function updateDrag(input)
        local delta = input.Position - dragStart
        root.Position = UDim2.fromScale(
            math.clamp(startPos.X.Scale + delta.X / screen.AbsoluteSize.X, 0.05, 0.95),
            math.clamp(startPos.Y.Scale + delta.Y / screen.AbsoluteSize.Y, 0.05, 0.95)
        )
    end

    local dragArea = header  -- drag via header
    dragArea.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = root.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            updateDrag(input)
        end
    end)

    return screen
end

buildUI()
