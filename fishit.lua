--// Rhy Tools v2 - Automation + Teleport, draggable + minimize + tabs

--== Services & Player ==--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

--== Net (sleitnick net) ==--
local Net = ReplicatedStorage:WaitForChild("Packages")
    :WaitForChild("_Index")
    :WaitForChild("sleitnick_net@0.2.0")
    :WaitForChild("net")

local RFChargeFishingRod    = Net:WaitForChild("RF/ChargeFishingRod")
local RFStartMinigame       = Net:WaitForChild("RF/RequestFishingMinigameStarted")
local REReplicateTextEffect = Net:WaitForChild("RE/ReplicateTextEffect")
local REFishingCompleted    = Net:WaitForChild("RE/FishingCompleted")

--== Auto Fish Params ==--
local COOLDOWN_CATCH = 0.25
local RECHARGE_DELAY = 1.00
local MAX_RETRY_RF   = 2

-- Power (arah lempar) single-select
local POWER_OPTIONS = {
    {key="OK",       min=0.10, max=0.20},
    {key="GOOD",     min=0.50, max=0.50},
    {key="GREAT",    min=0.60, max=0.70},
    {key="AMAZING",  min=0.80, max=0.80},
    {key="PERFECT",  min=0.96, max=0.99},
}
local selectedPower = POWER_OPTIONS[#POWER_OPTIONS]

-- Catch Options (multi-select) -> pilih random salah satu ketika Exclaim
local CATCH_OPTIONS = {
    {key="0.50s", t=0.50},
    {key="0.75s", t=0.75},
    {key="1.00s", t=1.00},
    {key="1.25s", t=1.25},
    {key="1.50s", t=1.50},
    {key="1.90s", t=1.90},
}
local catchSelected = { ["1.90s"]=true } -- default: satu opsi aktif

-- Direction mode: X fixed (sesuai preferensimu), Y/Z mengikuti power
local FIXED_X_VALUE = -0.5718746185302734
local USE_LOOKVECTOR = false -- bisa diubah via kode; UI fokus ke power & catch

--== State ==--
local running = false
local busyCatch = false

--== Helpers ==--
local function safeInvoke(rf, ...)
    local args = { ... }
    for _ = 1, MAX_RETRY_RF do
        local ok, res = pcall(function() return rf:InvokeServer(table.unpack(args)) end)
        if ok then return true, res end
        task.wait(0.2)
    end
    return false, nil
end

local function randBetween(a, b)
    return a + (b - a) * math.random()
end

local function clamp01(v)
    if v > 1 then return 1 elseif v < -1 then return -1 else return v end
end

local function getDirXZ()
    local m = randBetween(selectedPower.min, selectedPower.max)
    if not USE_LOOKVECTOR then
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
    return clamp01(ux*m), clamp01(uz*m)
end

local function pickCatchDelay()
    local pool = {}
    for _, opt in ipairs(CATCH_OPTIONS) do
        if catchSelected[opt.key] then table.insert(pool, opt.t) end
    end
    if #pool == 0 then return 0.5 end -- fallback
    return pool[math.random(1, #pool)]
end

local function charge()
    if not running then return end
    local ok1 = select(1, safeInvoke(RFChargeFishingRod, workspace:GetServerTimeNow()))
    if not ok1 then warn("[AutoFish] Charge gagal"); return end
    local x, z = getDirXZ()
    local ok2 = select(1, safeInvoke(RFStartMinigame, x, z))
    if not ok2 then warn(("[AutoFish] Start gagal (x=%.3f, z=%.3f)"):format(x, z)); return end
end

--== Exclaim -> Catch (filter punyamu: AttachTo/Container owner == LocalPlayer) ==--
local function isMyExclaim(payload)
    if typeof(payload) ~= "table" then return false end
    local td = payload.TextData
    local effect = (td and td.EffectType) or payload.EffectType
    if effect ~= "Exclaim" then return false end

    local inst = (td and (td.AttachTo or td.Adornee)) or payload.Container or payload.AttachTo
    if typeof(inst) ~= "Instance" then return false end

    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    if inst == char:FindFirstChild("Head") or inst:IsDescendantOf(char) then
        return true
    end
    local ownerModel = inst:FindFirstAncestorOfClass("Model")
    return ownerModel and Players:GetPlayerFromCharacter(ownerModel) == LocalPlayer
end

REReplicateTextEffect.OnClientEvent:Connect(function(payload)
    if not running then return end
    if not isMyExclaim(payload) then return end
    if busyCatch then return end

    busyCatch = true
    local strikeDelay = pickCatchDelay()
    task.wait(strikeDelay)
    pcall(function() REFishingCompleted:FireServer() end)

    task.delay(COOLDOWN_CATCH, function() busyCatch = false end)
    task.delay(RECHARGE_DELAY, function() if running then charge() end end)
end)

--==================================================
--== UI SYSTEM (draggable + tabs + minimize)     ==--
--==================================================

local function makeDraggable(frame, dragHandle)
    local dragging = false
    local dragStart, startPos

    local function update(input)
        local delta = input.Position - dragStart
        frame.Position = UDim2.new(0, startPos.X + delta.X, 0, startPos.Y + delta.Y)
    end

    dragHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or
           input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = Vector2.new(frame.Position.X.Offset, frame.Position.Y.Offset)
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            update(input)
        end
    end)
end

local function centerFrame(screen, frame)
    -- hitung posisi tengah (pakai offset)
    RunService.Heartbeat:Wait() -- tunggu size final
    local ss = screen.AbsoluteSize
    local fs = frame.AbsoluteSize
    local x = (ss.X - fs.X) / 2
    local y = (ss.Y - fs.Y) / 2
    frame.Position = UDim2.new(0, math.floor(x), 0, math.floor(y))
end

local ui = {} -- refs

local function buildUI()
    local screen = Instance.new("ScreenGui")
    screen.Name = "RhyToolsUI"
    screen.ResetOnSpawn = false
    screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screen.Parent = LocalPlayer:WaitForChild("PlayerGui")

    -- Root frame (offset-based for draggable)
    local root = Instance.new("Frame")
    root.Name = "Root"
    root.Size = UDim2.fromOffset(380, 340)
    root.Position = UDim2.new(0.5, -190, 0.5, -170) -- sementara; akan di-center ulang
    root.BackgroundColor3 = Color3.fromRGB(22,22,26)
    root.BorderSizePixel = 0
    root.Parent = screen
    Instance.new("UICorner", root).CornerRadius = UDim.new(0, 12)

    -- Title bar
    local titleBar = Instance.new("Frame")
    titleBar.Size = UDim2.new(1, 0, 0, 34)
    titleBar.BackgroundColor3 = Color3.fromRGB(30,30,36)
    titleBar.BorderSizePixel = 0
    titleBar.Parent = root
    Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 12)

    local title = Instance.new("TextLabel")
    title.Text = "Rhy Tools"
    title.Font = Enum.Font.GothamBold
    title.TextScaled = true
    title.TextColor3 = Color3.fromRGB(235,235,235)
    title.BackgroundTransparency = 1
    title.Size = UDim2.new(1, -90, 1, 0)
    title.Position = UDim2.fromOffset(10, 0)
    title.Parent = titleBar

    local btnMin = Instance.new("TextButton")
    btnMin.Text = "—"
    btnMin.Font = Enum.Font.GothamBold
    btnMin.TextScaled = true
    btnMin.TextColor3 = Color3.fromRGB(255,255,255)
    btnMin.BackgroundColor3 = Color3.fromRGB(50,50,60)
    btnMin.Size = UDim2.fromOffset(34, 24)
    btnMin.Position = UDim2.new(1, -44, 0.5, -12)
    btnMin.Parent = titleBar
    Instance.new("UICorner", btnMin).CornerRadius = UDim.new(0, 8)

    makeDraggable(root, titleBar)

    -- Tab bar
    local tabBar = Instance.new("Frame")
    tabBar.Size = UDim2.new(1, -20, 0, 32)
    tabBar.Position = UDim2.fromOffset(10, 44)
    tabBar.BackgroundTransparency = 1
    tabBar.Parent = root

    local tabLayout = Instance.new("UIListLayout")
    tabLayout.FillDirection = Enum.FillDirection.Horizontal
    tabLayout.Padding = UDim.new(0, 8)
    tabLayout.Parent = tabBar

    local function mkTabButton(text)
        local b = Instance.new("TextButton")
        b.Text = text
        b.Font = Enum.Font.GothamMedium
        b.TextScaled = true
        b.TextColor3 = Color3.fromRGB(255,255,255)
        b.BackgroundColor3 = Color3.fromRGB(40,40,48)
        b.Size = UDim2.fromOffset(120, 32)
        b.Parent = tabBar
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
        return b
    end

    local tabAutomation = mkTabButton("Automation")
    local tabTeleport   = mkTabButton("Teleport")

    -- Content area
    local content = Instance.new("Frame")
    content.Name = "Content"
    content.Position = UDim2.fromOffset(10, 84)
    content.Size = UDim2.new(1, -20, 1, -94)
    content.BackgroundTransparency = 1
    content.Parent = root

    -- Two pages
    local pageAutomation = Instance.new("Frame")
    pageAutomation.Size = UDim2.fromScale(1,1)
    pageAutomation.BackgroundTransparency = 1
    pageAutomation.Parent = content

    local pageTeleport = Instance.new("Frame")
    pageTeleport.Size = UDim2.fromScale(1,1)
    pageTeleport.BackgroundTransparency = 1
    pageTeleport.Visible = false
    pageTeleport.Parent = content

    -- ---------- Automation page ----------
    local list = Instance.new("UIListLayout")
    list.Padding = UDim.new(0, 8)
    list.Parent = pageAutomation

    -- Row: Auto Fishing toggle & status
    local row1 = Instance.new("Frame")
    row1.Size = UDim2.new(1, 0, 0, 40)
    row1.BackgroundTransparency = 1
    row1.Parent = pageAutomation
    local r1Layout = Instance.new("UIListLayout")
    r1Layout.FillDirection = Enum.FillDirection.Horizontal
    r1Layout.Padding = UDim.new(0, 8)
    r1Layout.Parent = row1

    local btnToggle = Instance.new("TextButton")
    btnToggle.Text = "Start"
    btnToggle.Font = Enum.Font.GothamBold
    btnToggle.TextScaled = true
    btnToggle.TextColor3 = Color3.new(1,1,1)
    btnToggle.BackgroundColor3 = Color3.fromRGB(53,120,65)
    btnToggle.Size = UDim2.fromOffset(120, 40)
    btnToggle.Parent = row1
    Instance.new("UICorner", btnToggle).CornerRadius = UDim.new(0, 10)

    local status = Instance.new("TextLabel")
    status.Text = "OFF"
    status.Font = Enum.Font.GothamMedium
    status.TextScaled = true
    status.TextColor3 = Color3.fromRGB(255,70,70)
    status.BackgroundTransparency = 1
    status.Size = UDim2.new(1, -128, 1, 0)
    status.Parent = row1

    -- Row: Power (single-select)
    local powerBox = Instance.new("Frame")
    powerBox.Size = UDim2.new(1, 0, 0, 84)
    powerBox.BackgroundTransparency = 1
    powerBox.Parent = pageAutomation
    local powerGrid = Instance.new("UIGridLayout")
    powerGrid.CellPadding = UDim2.fromOffset(8, 8)
    powerGrid.CellSize = UDim2.fromOffset(110, 32)
    powerGrid.Parent = powerBox

    local powerButtons = {}
    local function mkPower(opt)
        local b = Instance.new("TextButton")
        b.Text = opt.key
        b.Font = Enum.Font.GothamMedium
        b.TextScaled = true
        b.TextColor3 = Color3.new(1,1,1)
        b.BackgroundColor3 = Color3.fromRGB(40,40,40)
        b.Parent = powerBox
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
        b:SetAttribute("Key", opt.key)
        b.MouseButton1Click:Connect(function()
            selectedPower = opt
            for _, x in ipairs(powerButtons) do
                local k = x:GetAttribute("Key")
                x.BackgroundColor3 = (k == selectedPower.key) and Color3.fromRGB(70,70,120) or Color3.fromRGB(40,40,40)
            end
        end)
        table.insert(powerButtons, b)
    end
    for _, opt in ipairs(POWER_OPTIONS) do mkPower(opt) end

    -- Row: Catch Options (multi-select)
    local catchBox = Instance.new("Frame")
    catchBox.Size = UDim2.new(1, 0, 0, 124)
    catchBox.BackgroundTransparency = 1
    catchBox.Parent = pageAutomation
    local catchGrid = Instance.new("UIGridLayout")
    catchGrid.CellPadding = UDim2.fromOffset(8, 8)
    catchGrid.CellSize = UDim2.fromOffset(110, 32)
    catchGrid.Parent = catchBox

    local function styleCatch(btn)
        local key = btn:GetAttribute("Key")
        btn.BackgroundColor3 = catchSelected[key] and Color3.fromRGB(70,120,70) or Color3.fromRGB(40,40,40)
        btn.TextColor3 = Color3.new(1,1,1)
    end
    local function mkCatch(opt)
        local b = Instance.new("TextButton")
        b.Text = opt.key
        b.Font = Enum.Font.GothamMedium
        b.TextScaled = true
        b.BackgroundColor3 = Color3.fromRGB(40,40,40)
        b.Parent = catchBox
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
        b:SetAttribute("Key", opt.key)
        styleCatch(b)
        b.MouseButton1Click:Connect(function()
            local key = b:GetAttribute("Key")
            catchSelected[key] = not catchSelected[key]
            styleCatch(b)
        end)
    end
    for _, opt in ipairs(CATCH_OPTIONS) do mkCatch(opt) end

    -- ---------- Teleport page ----------
    local teleList = Instance.new("UIListLayout")
    teleList.Padding = UDim.new(0, 8)
    teleList.Parent = pageTeleport

    local rowT = Instance.new("Frame")
    rowT.Size = UDim2.new(1, 0, 0, 36)
    rowT.BackgroundTransparency = 1
    rowT.Parent = pageTeleport
    local rTLayout = Instance.new("UIListLayout")
    rTLayout.FillDirection = Enum.FillDirection.Horizontal
    rTLayout.Padding = UDim.new(0, 6)
    rTLayout.Parent = rowT

    local function mkBox(placeholder)
        local tb = Instance.new("TextBox")
        tb.PlaceholderText = placeholder
        tb.Text = ""
        tb.Font = Enum.Font.Gotham
        tb.TextScaled = true
        tb.ClearTextOnFocus = false
        tb.TextColor3 = Color3.new(1,1,1)
        tb.BackgroundColor3 = Color3.fromRGB(40,40,48)
        tb.Size = UDim2.fromOffset(100, 36)
        tb.Parent = rowT
        Instance.new("UICorner", tb).CornerRadius = UDim.new(0, 8)
        return tb
    end
    local tbX = mkBox("X")
    local tbY = mkBox("Y")
    local tbZ = mkBox("Z")

    local btnUseCur = Instance.new("TextButton")
    btnUseCur.Text = "Use Current"
    btnUseCur.Font = Enum.Font.GothamMedium
    btnUseCur.TextScaled = true
    btnUseCur.TextColor3 = Color3.new(1,1,1)
    btnUseCur.BackgroundColor3 = Color3.fromRGB(50,60,80)
    btnUseCur.Size = UDim2.fromOffset(120, 36)
    btnUseCur.Parent = rowT
    Instance.new("UICorner", btnUseCur).CornerRadius = UDim.new(0, 8)

    local btnGo = Instance.new("TextButton")
    btnGo.Text = "Teleport"
    btnGo.Font = Enum.Font.GothamBold
    btnGo.TextScaled = true
    btnGo.TextColor3 = Color3.new(1,1,1)
    btnGo.BackgroundColor3 = Color3.fromRGB(70,120,80)
    btnGo.Size = UDim2.fromOffset(120, 36)
    btnGo.Parent = rowT
    Instance.new("UICorner", btnGo).CornerRadius = UDim.new(0, 8)

    btnUseCur.MouseButton1Click:Connect(function()
        local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
        local root = char:FindFirstChild("HumanoidRootPart")
        if not root then return end
        tbX.Text = string.format("%.2f", root.Position.X)
        tbY.Text = string.format("%.2f", root.Position.Y)
        tbZ.Text = string.format("%.2f", root.Position.Z)
    end)

    btnGo.MouseButton1Click:Connect(function()
        local x = tonumber(tbX.Text)
        local y = tonumber(tbY.Text)
        local z = tonumber(tbZ.Text)
        if not (x and y and z) then return end
        local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
        local root = char:FindFirstChild("HumanoidRootPart")
        if not root then return end
        root.CFrame = CFrame.new(x, y, z)
    end)

    -- Tab switching
    local function selectTab(which)
        pageAutomation.Visible = (which == "auto")
        pageTeleport.Visible   = (which == "tele")
        tabAutomation.BackgroundColor3 = (which=="auto") and Color3.fromRGB(70,70,120) or Color3.fromRGB(40,40,48)
        tabTeleport.BackgroundColor3   = (which=="tele") and Color3.fromRGB(70,70,120) or Color3.fromRGB(40,40,48)
    end
    tabAutomation.MouseButton1Click:Connect(function() selectTab("auto") end)
