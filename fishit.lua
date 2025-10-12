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
local RECHARGE_DELAY = 0.5
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
    {"Crater Island",     CFrame.new(962, 7.4, 4872)},
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
local selectedKeys = { PERFECT = true }

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

-- ==== ANIMATION CONFIG ====
local ANIM_IDS = {
    Cast   = "rbxassetid://92624107165273",
    Wait   = "rbxassetid://134965425664034",
    Reel   = "rbxassetid://114959536562596",
}

local _tracks = {}
local function getAnimator()
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local hum  = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid")
    local ani  = hum:FindFirstChildOfClass("Animator")
    if not ani then ani = Instance.new("Animator"); ani.Parent = hum end
    return ani
end

local function ensureTrack(id)
    if not id or id == "" then return nil end
    local t = _tracks[id]
    if t and t.IsPlaying ~= nil then return t end
    local animator = getAnimator()
    local a = Instance.new("Animation"); a.AnimationId = id
    t = animator:LoadAnimation(a); _tracks[id] = t
    return t
end

local function playOnce(id, fade)
    local t = ensureTrack(id); if not t then return nil end
    t.Looped = false; t:Play(fade or 0.12); return t
end

local function playLoop(id, fade)
    local t = ensureTrack(id); if not t then return nil end
    t.Looped = true;  t:Play(fade or 0.12); return t
end

local function stop(id, fade)
    local t = _tracks[id]; if t and t.IsPlaying then t:Stop(fade or 0.12) end
end

local function stopAll()
    for id,t in pairs(_tracks) do pcall(function() if t.IsPlaying then t:Stop(0.1) end end) end
end

local _isCasting = false
local _waitActive = false
local _reelActive = false

local function charge()
    if not running or _isCasting then return end
    _isCasting = true
    _waitActive = false
    _reelActive = false
    stopAll()

	playOnce(ANIM_IDS.Cast)
    task.wait(0.5)
    local ok1 = select(1, safeInvoke(RFChargeFishingRod, workspace:GetServerTimeNow()))
    if not ok1 then
        _isCasting = false
        return
    end

	task.delay(0.1, function()
		if _isCasting and running then
			stop(ANIM_IDS.Cast)
			_waitActive = true
			playLoop(ANIM_IDS.Wait)
		end
	end)

    local x, z = getDirXZ()
    local ok2 = select(1, safeInvoke(RFStartMinigame, x, z))

    if ok2 then
        lastCastAt = workspace:GetServerTimeNow()
    else
        _isCasting = false
    end
end

REReplicateTextEffect.OnClientEvent:Connect(function(payload)
    if not running then return end
    if not isMyExclaim(payload) then return end
    if busyCatch then return end

    busyCatch = true
    _waitActive = false
    stop(ANIM_IDS.Wait)
    _reelActive = true
    playLoop(ANIM_IDS.Reel)

    task.wait(1.05)

    pcall(function() REFishingCompleted:FireServer() end)

    _reelActive = false
    stop(ANIM_IDS.Reel)

    _isCasting = false

    task.delay(COOLDOWN_CATCH, function() busyCatch = false end)
    task.delay(RECHARGE_DELAY, function()
        if running then charge() end
    end)
end)

local function onAutoOff()
    running = false
    _isCasting = false
    _waitActive = false
    _reelActive = false
    busyCatch = false
    stopAll()
end

local WEATHER_DEBOUNCE = 0.5
local lastWeatherAt = 0

-- ==== PURCHASE WEATHER helper ====
local function purchaseWeather(kind)
	local rf
	pcall(function()
		rf = ReplicatedStorage.Packages
			:WaitForChild("_Index", 1)
			:FindFirstChild("sleitnick_net@0.2.0")
		rf = rf and rf:FindFirstChild("net")
		rf = rf and rf:FindFirstChild("RF/PurchaseWeatherEvent")
	end)
	if rf and rf:IsA("RemoteFunction") then
		local ok, res = pcall(function() return rf:InvokeServer(kind) end)
		return ok and (res ~= false)
	else
		warn("[UI] RF/PurchaseWeatherEvent tidak ditemukan; simulasi false")
		return false
	end
end

local running = (typeof(running)=="boolean") and running or false
local function callSetAuto(state)
	local ok = pcall(function()
		if typeof(setAuto) == "function" then setAuto(state) end
	end)
	running = state
	return ok
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

	-- ===== Shield: blokir tap ke game + klik tengah = minimize =====
	local shield = Instance.new("TextButton")
	shield.Name = "InputShield"
	shield.BackgroundTransparency = 1
	shield.AutoButtonColor = false
	shield.Text = ""
	shield.Active = true
	shield.Size = UDim2.fromScale(1,1)
	shield.Position = UDim2.fromScale(0,0)
	shield.ZIndex = 50
	shield.Parent = screen

	-- ===== Sidebar kiri (pepet kiri, full tinggi) =====
	local sidebar = Instance.new("Frame")
	sidebar.Name = "Sidebar"
	sidebar.AnchorPoint = Vector2.new(0, 0)
	sidebar.Position = UDim2.fromScale(0, 0)
	sidebar.BackgroundColor3 = Color3.fromRGB(26,26,26)
	sidebar.BorderSizePixel = 0
	sidebar.ZIndex = 60
	sidebar.Parent = screen

	-- Header
	local head = Instance.new("Frame")
	head.Size = UDim2.fromScale(1, 0.16)
	head.BackgroundColor3 = Color3.fromRGB(32,32,32)
	head.BorderSizePixel = 0
	head.ZIndex = 61
	head.Parent = sidebar

	local logo = Instance.new("ImageLabel")
	logo.BackgroundTransparency = 1
	logo.Image = LOGO_ASSET_ID
	logo.ScaleType = Enum.ScaleType.Fit
	logo.Size = UDim2.fromScale(0.24, 0.74)
	logo.Position = UDim2.fromScale(0.06, 0.13)
	logo.ZIndex = 62
	logo.Parent = head

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Text = "The Universe"
	title.TextColor3 = Color3.fromRGB(235,235,235)
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.Size = UDim2.fromScale(0.56, 0.74)
	title.Position = UDim2.fromScale(0.34, 0.13)
	title.ZIndex = 62
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = head

	local minimize = Instance.new("TextButton")

	local tabArea = Instance.new("Frame")
	tabArea.BackgroundTransparency = 1
	tabArea.Size = UDim2.fromScale(1, 0.84)
	tabArea.Position = UDim2.fromScale(0, 0.16)
	tabArea.ZIndex = 60
	tabArea.Parent = sidebar

	-- container tab (punya padding kiri/kanan)
	local tabPad = Instance.new("UIPadding", tabArea)
	tabPad.PaddingLeft  = UDim.new(0, 8)
	tabPad.PaddingRight = UDim.new(0, 8)

	local tabLayout = Instance.new("UIListLayout", tabArea)
	tabLayout.FillDirection = Enum.FillDirection.Vertical
	tabLayout.Padding = UDim.new(0, 6)
	tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	tabLayout.VerticalAlignment   = Enum.VerticalAlignment.Top

	local function makeTab(name, iconId)
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(1, -16, 0, 40)
		b.BackgroundColor3 = Color3.fromRGB(40,40,40)
		b.Text = ""
		b.ZIndex = 60
		b.AutoButtonColor = true
		b.Parent = tabArea

		local pad = Instance.new("UIPadding", b)
		pad.PaddingLeft  = UDim.new(0, 10)
		pad.PaddingRight = UDim.new(0, 10)

		local corner = Instance.new("UICorner", b)
		corner.CornerRadius = UDim.new(0, 8)

		local layout = Instance.new("UIListLayout", b)
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
		layout.VerticalAlignment   = Enum.VerticalAlignment.Center
		layout.Padding = UDim.new(0, 8)

		local icon = Instance.new("ImageLabel")
		icon.Size = UDim2.fromOffset(20, 20)
		icon.BackgroundTransparency = 1
		icon.Image = iconId or "rbxassetid://3926305904"
		icon.ImageRectOffset = Vector2.new(84, 204)
		icon.ImageRectSize   = Vector2.new(36, 36)
		icon.Parent = b

		local txt = Instance.new("TextLabel")
		txt.Text = name
		txt.BackgroundTransparency = 1
		txt.TextColor3 = Color3.fromRGB(255,255,255)
		txt.Font = Enum.Font.GothamMedium
		txt.TextScaled = false
		txt.TextSize = 20
		txt.TextXAlignment = Enum.TextXAlignment.Left
		txt.TextWrapped = false
		txt.TextTruncate = Enum.TextTruncate.AtEnd
		txt.ClipsDescendants = true
		txt.Parent = b
		txt.Size = UDim2.new(1, -(20 + 8), 1, 0)
		txt.TextTruncate = Enum.TextTruncate.AtEnd

		return b
	end

	local tabAutomation = makeTab("Automation")
	local tabTeleport   = makeTab("Teleport")
	local tabWeather    = makeTab("Weather")

	-- ===== Panel kanan (pepet kanan, full tinggi) =====
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = UDim2.fromScale(1, 0)
	panel.BackgroundColor3 = Color3.fromRGB(26,26,26)
	panel.BorderSizePixel = 0
	panel.ZIndex = 60
	panel.Parent = screen

	local pages = Instance.new("Frame")
	pages.BackgroundTransparency = 1
	pages.Size = UDim2.fromScale(1,1)
	pages.Parent = panel
	pages.ZIndex = 60

	local function makePage()
		local p = Instance.new("Frame")
		p.BackgroundTransparency = 1
		p.Size = UDim2.fromScale(1,1)
		p.Visible = false
		p.ZIndex = 60
		p.Parent = pages
		return p
	end

	local function makeScroll(parent, fracHeight)
		local sf = Instance.new("ScrollingFrame")
		sf.BackgroundTransparency = 1
		sf.Size = UDim2.fromScale(1, fracHeight or 1)
		sf.CanvasSize = UDim2.new(0,0,0,0)
		sf.AutomaticCanvasSize = Enum.AutomaticSize.Y
		sf.ScrollBarThickness = 6
		sf.BorderSizePixel = 0
		sf.ZIndex = 60
		sf.Parent = parent
		local layout = Instance.new("UIListLayout", sf)
		layout.Padding = UDim.new(0, 8)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		return sf
	end
	
	-- ====== Layout: 3 kolom (kiri 1/3, tengah 1/3, kanan 1/3) ======
	local SIDE_FRAC = 1/3

	local function layoutThirds()
		-- kiri = 1/3 layar
		sidebar.Size     = UDim2.new(SIDE_FRAC, 0, 1, 0)
		sidebar.Position = UDim2.new(0, 0, 0, 0)

		-- kanan = 1/3 layar (anchor kanan)
		panel.Size     = UDim2.new(SIDE_FRAC, 0, 1, 0)
		panel.Position = UDim2.new(1, 0, 0, 0)  -- dengan AnchorPoint (1,0)

		-- tengah otomatis = sisa (1 - 1/3 - 1/3 = 1/3)
		-- kamu gak perlu buat frame khusus “tengah” karena game view bakal terlihat di area sisa.
		-- Kalau nanti ingin overlay komponen di tengah, tinggal buat Frame ketiga di sini.
	end

	layoutThirds()
	screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutThirds)

	-- ====================================================
	-- ========= UI Helpers (DRY) =========
	local TweenService = game:GetService("TweenService")

	local ASSETS = {
		chevron = "rbxassetid://6031090990",
		check   = "rbxassetid://6031068420",
	}

	local function vstack(parent, pad)
		local p = Instance.new("UIPadding", parent)
		p.PaddingLeft, p.PaddingRight, p.PaddingTop, p.PaddingBottom = UDim.new(0,8), UDim.new(0,8), UDim.new(0,8), UDim.new(0,8)
		local l = Instance.new("UIListLayout", parent)
		l.FillDirection, l.SortOrder, l.Padding = Enum.FillDirection.Vertical, Enum.SortOrder.LayoutOrder, UDim.new(0, pad or 8)
		return l
	end

	local function makePageStd(titleText, parentPage, useScroll)
		local root = useScroll and makeScroll(parentPage, 1) or parentPage
		vstack(root, 8)
		local title = Instance.new("TextLabel")
		title.BackgroundTransparency = 1
		title.Text = titleText
		title.TextColor3 = Color3.fromRGB(220,220,220)
		title.Font = Enum.Font.GothamBold
		title.TextScaled = false
		title.TextSize = 22
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.Size = UDim2.new(1,0,0,28)
		title.ZIndex = 60
		title.Parent = root

		local divider = Instance.new("Frame")
		divider.Size = UDim2.new(1,0,0,1)
		divider.BackgroundColor3 = Color3.fromRGB(70,70,70)
		divider.BorderSizePixel = 0
		divider.ZIndex = 60
		divider.Parent = root
		return root
	end

	local function makeChevron(parent)
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Size = UDim2.fromOffset(18, 18)
		img.AnchorPoint = Vector2.new(1, 0.5)
		img.Position = UDim2.fromScale(1, 0.5)
		img.Image = ASSETS.chevron
		img.ScaleType = Enum.ScaleType.Fit
		img.Rotation = 0
		img.Parent = parent
		return img
	end

	-- Card collapsible: builder(body) dipanggil sekali utk isi; return api {setExpanded, body}
	local function makeCard(parent, titleText, opts)
		opts = opts or {}
		local borderColor = opts.strokeColor or Color3.fromRGB(70,70,80)
		local bg = opts.bgColor or Color3.fromRGB(36,36,36)

		local card = Instance.new("Frame")
		card.Size = UDim2.fromScale(1,0)
		card.AutomaticSize = Enum.AutomaticSize.Y
		card.BackgroundColor3 = bg
		card.BackgroundTransparency = 0.05
		card.Parent = parent
		card.ZIndex = 60
		local corner = Instance.new("UICorner", card); corner.CornerRadius = UDim.new(0,12)
		local stroke = Instance.new("UIStroke", card)
		stroke.Thickness, stroke.Color, stroke.Transparency = 1, borderColor, 0.25

		local stack = Instance.new("UIListLayout", card)
		stack.FillDirection, stack.SortOrder, stack.Padding = Enum.FillDirection.Vertical, Enum.SortOrder.LayoutOrder, UDim.new(0,6)

		local header = Instance.new("TextButton")
		header.BackgroundTransparency, header.AutoButtonColor, header.Text = 1, false, ""
		header.Size = UDim2.new(1,0,0,44)
		header.Parent = card
		local pad = Instance.new("UIPadding", header)
		pad.PaddingLeft, pad.PaddingRight = UDim.new(0,12), UDim.new(0,12)

		local title = Instance.new("TextLabel")
		title.BackgroundTransparency = 1
		title.Text = titleText
		title.Font = Enum.Font.GothamBold
		title.TextSize = 18
		title.TextColor3 = Color3.fromRGB(235,235,235)
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.Size = UDim2.fromScale(1,1)
		title.Parent = header

		local chev = makeChevron(header)

		local mask = Instance.new("Frame")
		mask.BackgroundTransparency = 1
		mask.ClipsDescendants = true
		mask.Size = UDim2.new(1,0,0,0)
		mask.Parent = card

		local body = Instance.new("Frame")
		body.BackgroundTransparency = 1
		body.Size = UDim2.fromScale(1,0)
		body.AutomaticSize = Enum.AutomaticSize.Y
		body.Parent = mask
		local bpad = Instance.new("UIPadding", body)
		bpad.PaddingLeft, bpad.PaddingRight, bpad.PaddingTop, bpad.PaddingBottom = UDim.new(0,10), UDim.new(0,10), UDim.new(0,6), UDim.new(0,10)
		local blay = Instance.new("UIListLayout", body)
		blay.FillDirection, blay.SortOrder, blay.Padding = Enum.FillDirection.Vertical, Enum.SortOrder.LayoutOrder, UDim.new(0,8)

		local expanded, tweenTime = false, 0.18
		local function resizeMask(instantly)
			local h = math.ceil(body.AbsoluteSize.Y)
			local goal = { Size = UDim2.new(1,0,0, expanded and h or 0) }
			if instantly then mask.Size = goal.Size
			else TweenService:Create(mask, TweenInfo.new(tweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play() end
		end
		body:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			if expanded then resizeMask(false) end
		end)
		local function setExpanded(v, animate)
			expanded = v
			if animate then TweenService:Create(chev, TweenInfo.new(0.15), {Rotation = v and 90 or 0}):Play()
			else chev.Rotation = v and 90 or 0 end
			resizeMask(not animate)
		end
		setExpanded(false, true)
		header.MouseButton1Click:Connect(function() setExpanded(not expanded, true) end)

		return {root=card, header=header, titleLabel=title, body=body, setExpanded=setExpanded}
	end

	local function makeRow(parent, labelText)
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1,0,0,44)
		row.BackgroundColor3 = Color3.fromRGB(46,46,46)
		row.BorderSizePixel = 0
		row.Parent = parent
		local c = Instance.new("UICorner", row); c.CornerRadius = UDim.new(0,10)

		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Text = labelText
		label.TextColor3 = Color3.fromRGB(230,230,230)
		label.Font = Enum.Font.GothamMedium
		label.TextScaled, label.TextSize = false, 16
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Size = UDim2.new(0.6,0,1,0)
		label.Position = UDim2.fromScale(0.05,0)
		label.Parent = row
		return row, label
	end

	local function makeSwitch(parentRow, initial, onChange)
		local switch = Instance.new("Frame")
		switch.AnchorPoint, switch.Position = Vector2.new(1,0.5), UDim2.fromScale(0.92,0.5)
		switch.Size = UDim2.fromScale(0.20,0.6)
		switch.BackgroundColor3 = Color3.fromRGB(70,70,70)
		switch.Parent = parentRow
		local sCorner = Instance.new("UICorner", switch); sCorner.CornerRadius = UDim.new(1,0)

		local knob = Instance.new("Frame")
		knob.AnchorPoint, knob.Position = Vector2.new(0,0.5), UDim2.fromScale(0.05,0.5)
		knob.Size = UDim2.fromScale(0.42,0.78)
		knob.BackgroundColor3 = Color3.fromRGB(235,235,235)
		knob.Parent = switch
		local kCorner = Instance.new("UICorner", knob); kCorner.CornerRadius = UDim.new(1,0)

		local state = initial
		local function apply(animate)
			local bg = state and Color3.fromRGB(90,130,90) or Color3.fromRGB(70,70,70)
			local x  = state and 0.53 or 0.05
			if animate then
				TweenService:Create(switch, TweenInfo.new(0.15), {BackgroundColor3=bg}):Play()
				TweenService:Create(knob,   TweenInfo.new(0.15), {Position=UDim2.fromScale(x,0.5)}):Play()
			else
				switch.BackgroundColor3 = bg
				knob.Position = UDim2.fromScale(x,0.5)
			end
		end
		apply(false)

		switch.InputBegan:Connect(function(input)
			if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
				state = not state
				apply(true)
				if onChange then onChange(state) end
			end
		end)

		return {
			set = function(v) state=v; apply(true) end,
			get = function() return state end,
		}
	end

	local function makeRadioGroup(parent, items, defaultKey)
		local rows, selected = {}, defaultKey
		local function refresh()
			for _, it in ipairs(rows) do
				local on = (it.key == selected)
				it.row.BackgroundColor3 = on and Color3.fromRGB(80,120,80) or Color3.fromRGB(55,55,55)
				if it.check then it.check.Visible = on end
			end
		end
		local function add(label, key)
			local row = Instance.new("TextButton")
			row.Text, row.AutoButtonColor = "", true
			row.Size = UDim2.new(1,0,0,40)
			row.BackgroundColor3 = Color3.fromRGB(55,55,55)
			row.Parent = parent
			local rc = Instance.new("UICorner", row); rc.CornerRadius = UDim.new(0,8)

			local txt = Instance.new("TextLabel")
			txt.BackgroundTransparency = 1
			txt.Text, txt.Font, txt.TextSize = label, Enum.Font.GothamMedium, 16
			txt.TextColor3, txt.TextXAlignment = Color3.fromRGB(255,255,255), Enum.TextXAlignment.Left
			txt.Size, txt.Position = UDim2.new(1,-40,1,0), UDim2.new(0,12,0,0)
			txt.Parent = row

			row.MouseButton1Click:Connect(function() selected = key; refresh() end)
			table.insert(rows, {row=row, key=key})
		end
		for _, it in ipairs(items) do add(it.label, it.key) end
		refresh()
		return {
			get = function() return selected end,
			set = function(k) selected=k; refresh() end,
		}
	end

	-- ========= Pages =========

	-- === AUTOMATION PAGE (Full Scroll) ===
	local pgAuto = makePage()
	pgAuto.Visible = true

	-- Scrolling container untuk seluruh halaman
	local autoScroll = Instance.new("ScrollingFrame")
	autoScroll.Name = "AutoViewport"
	autoScroll.Parent = pgAuto
	autoScroll.BackgroundTransparency = 1
	autoScroll.Size = UDim2.fromScale(1, 1)
	autoScroll.CanvasSize = UDim2.new(0,0,0,0)
	autoScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	autoScroll.ScrollBarThickness = 6

	local autoLayout = Instance.new("UIListLayout")
	autoLayout.Parent = autoScroll
	autoLayout.Padding = UDim.new(0, 8)
	autoLayout.SortOrder = Enum.SortOrder.LayoutOrder

	-- judul/toolbar halaman, kalau ada:
	makePageStd("Automation", autoScroll, false)

	-- ====== Fishing card dkk taruh ke autoScroll (BUKAN pgAuto langsung) ======
	local fishing = makeCard(autoScroll, "Fishing")
	local r1 = select(1, makeRow(fishing.body, "Auto Fishing"))
	local sw = makeSwitch(r1, running, function(on) setAuto(on) end)

	local power = makeCard(fishing.body, "Custom Power Charge", {bgColor = Color3.fromRGB(46,46,46)})

	-- --- Scroll khusus daftar power (biar viewport page tetap padat) ---
	local powerList = Instance.new("ScrollingFrame")
	powerList.Name = "PowerList"
	powerList.Parent = power.body
	powerList.BackgroundTransparency = 1
	powerList.ScrollBarThickness = 6
	powerList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	powerList.CanvasSize = UDim2.new(0,0,0,0)
	-- tinggi viewport lokal: clamp agar tidak memanjang
	powerList.Size = UDim2.new(1, 0, 0, math.clamp(#POWER_OPTIONS * 40, 160, 240))

	local plLayout = Instance.new("UIListLayout", powerList)
	plLayout.Padding = UDim.new(0, 6)
	plLayout.SortOrder = Enum.SortOrder.LayoutOrder

	-- radio group di dalam powerList (BUKAN power.body)
	local radioItems = {}
	for _, opt in ipairs(POWER_OPTIONS) do
		radioItems[#radioItems+1] = { label = opt.key, key = opt.key }
	end
	local selectedPowerKey = "PERFECT"
	local rg = makeRadioGroup(powerList, radioItems, selectedPowerKey)

	-- == Teleport ==
	local pgTp = makePage()
	local tpScroll = makeScroll(pgTp, 1)
	vstack(tpScroll, 8)
	makePageStd("Teleport", tpScroll, false)

	local tpCard = makeCard(tpScroll, "Teleport targets")
	for _, item in ipairs(TELEPORTS) do
		local btn = Instance.new("TextButton")
		btn.Text, btn.TextScaled, btn.TextSize = item[1], false, 16
		btn.Font, btn.TextColor3 = Enum.Font.GothamMedium, Color3.fromRGB(255,255,255)
		btn.BackgroundColor3 = Color3.fromRGB(55,55,55)
		btn.Size = UDim2.new(1,0,0,40)
		btn.Parent = tpCard.body
		local bc = Instance.new("UICorner", btn); bc.CornerRadius = UDim.new(0,8)
		btn.MouseButton1Click:Connect(function()
			local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
			local root = char:FindFirstChild("HumanoidRootPart")
			if root then root.CFrame = item[2] end
		end)
	end

	-- == Weather ==
	local pgWeather = makePage()
	local wScroll = makeScroll(pgWeather, 1)
	vstack(wScroll, 8)
	makePageStd("Weather", wScroll, false)

	local wCard = makeCard(wScroll, "Select Weather")
	local selectedWeatherDefault = "Storm"
	local wGroup = makeRadioGroup(wCard.body, {
		{label="Storm",  key="Storm"},
		{label="Cloudy", key="Cloudy"},
		{label="Wind",   key="Wind"},
	}, selectedWeatherDefault)

	local purchaseBtn = Instance.new("TextButton")
	purchaseBtn.Text, purchaseBtn.TextScaled, purchaseBtn.TextSize = "Purchase", false, 16
	purchaseBtn.Font, purchaseBtn.TextColor3 = Enum.Font.GothamBold, Color3.fromRGB(255,255,255)
	purchaseBtn.BackgroundColor3 = Color3.fromRGB(70,70,120)
	purchaseBtn.Size = UDim2.new(1,0,0,40)
	purchaseBtn.Parent = wCard.body
	local pc = Instance.new("UICorner", purchaseBtn); pc.CornerRadius = UDim.new(0,8)

	purchaseBtn.MouseButton1Click:Connect(function()
		local choice = wGroup.get()
		local ok = purchaseWeather(choice)
		if ok then
			wCard.titleLabel.Text = ("Purchased: %s"):format(choice)
			wCard.titleLabel.TextColor3 = Color3.fromRGB(120,255,120)
		else
			wCard.titleLabel.Text = ("Failed: %s"):format(choice)
			wCard.titleLabel.TextColor3 = Color3.fromRGB(255,90,90)
		end
		task.delay(1.2, function()
			if pgWeather.Visible then
				wCard.titleLabel.Text = "Select Weather"
				wCard.titleLabel.TextColor3 = Color3.fromRGB(235,235,235)
			end
		end)
	end)

	-- ===== Tab switching =====
	local function showPage(which)
		pgAuto.Visible    = (which == "auto")
		pgTp.Visible      = (which == "tp")
		pgWeather.Visible = (which == "weather")
		local act, inact = Color3.fromRGB(70,70,120), Color3.fromRGB(40,40,40)
		tabAutomation.BackgroundColor3 = (which=="auto")    and act or inact
		tabTeleport.BackgroundColor3   = (which=="tp")      and act or inact
		tabWeather.BackgroundColor3    = (which=="weather") and act or inact
	end
	tabAutomation.MouseButton1Click:Connect(function() showPage("auto") end)
	tabTeleport.MouseButton1Click:Connect(function() showPage("tp") end)
	tabWeather.MouseButton1Click:Connect(function() showPage("weather") end)
	showPage("auto")

	-- ===== Minimize: logo-only, draggable =====
	local bubble
	local minimized = false
	-- simpan posisi terakhir (default kanan-atas)
	local lastBubblePos = UDim2.fromScale(0.88, 0.08)

	local function clampBubblePos(pos, sizePx)
		local sx, sy = screen.AbsoluteSize.X, screen.AbsoluteSize.Y
		local w, h = sizePx or 64, sizePx or 64
		local minX = w / sx
		local minY = h / sy
		local x = math.clamp(pos.X.Scale, 0.02, 1 - minX - 0.02)
		local y = math.clamp(pos.Y.Scale, 0.02, 1 - minY - 0.02)
		return UDim2.fromScale(x, y)
	end

	local function trackBubblePosition(btn)
		btn:GetPropertyChangedSignal("Position"):Connect(function()
			lastBubblePos = clampBubblePos(btn.Position, btn.AbsoluteSize.X)
		end)
	end

	-- panggil ini setelah bubble dibuat
	local function makeDraggable(imgBtn)
		local dragging = false
		local dragStart, startPos
		local UIS = game:GetService("UserInputService")

		imgBtn.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				dragging = true
				dragStart = input.Position
				startPos = imgBtn.Position
			end
		end)

		UIS.InputChanged:Connect(function(input)
			if not dragging then return end
			if input.UserInputType ~= Enum.UserInputType.MouseMovement
				and input.UserInputType ~= Enum.UserInputType.Touch then return end
			local delta = input.Position - dragStart
			imgBtn.Position = UDim2.fromScale(
				math.clamp(startPos.X.Scale + delta.X / screen.AbsoluteSize.X, 0, 1),
				math.clamp(startPos.Y.Scale + delta.Y / screen.AbsoluteSize.Y, 0, 1)
			)
			-- lastBubblePos akan ikut ter-update via trackBubblePosition()
		end)

		UIS.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				dragging = false
			end
		end)
	end

	-- kalau window di-resize, re-clamp pos
	screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if bubble then
			bubble.Position = clampBubblePos(bubble.Position, bubble.AbsoluteSize.X)
		else
			lastBubblePos = clampBubblePos(lastBubblePos, 64)
		end
	end)

	-- MINIMIZE: selalu pakai lastBubblePos terbaru
	local function minimizeNow()
		if minimized then return end
		minimized = true
		sidebar.Visible = false
		panel.Visible = false
		shield.Visible = false

		bubble = Instance.new("ImageButton")
		bubble.Name = "AF_LogoBubble"
		bubble.Image = LOGO_ASSET_ID
		bubble.AutoButtonColor = true
		bubble.BackgroundTransparency = 0
		bubble.BackgroundColor3 = Color3.fromRGB(55,55,55)
		bubble.Size = UDim2.fromOffset(64, 64)
		bubble.Position = clampBubblePos(lastBubblePos, 64)
		bubble.ZIndex = 60
		bubble.Parent = screen

		local ar = Instance.new("UIAspectRatioConstraint", bubble)
		ar.AspectRatio = 1

		local bubCorner = Instance.new("UICorner", bubble)
		bubCorner.CornerRadius = UDim.new(1, 0)

		trackBubblePosition(bubble) -- <== selalu pantau perubahan posisi
		makeDraggable(bubble)

		bubble.MouseButton1Click:Connect(function()
			minimized = false
			if bubble then bubble:Destroy(); bubble = nil end
			sidebar.Visible = true
			panel.Visible   = true
			shield.Visible  = true
		end)
	end

	-- Jika kamu pakai “klik tengah shield” utk minimize:
	-- pastikan handler-nya memanggil MINIMIZE yang sama,
	-- dan sebelum Destroy bubble (kalau ada), simpan posnya dulu.
	shield.MouseButton2Click:Connect(function()
		if bubble then lastBubblePos = clampBubblePos(bubble.Position, bubble.AbsoluteSize.X) end
		minimizeNow()
	end)

	-- klik area tengah (shield) → minimize, kecuali klik di sidebar/panel
	shield.MouseButton1Click:Connect(function()
		local UIS = game:GetService("UserInputService")
		local pos = UIS:GetMouseLocation()
		local function within(gui)
			local p = gui.AbsolutePosition
			local s = gui.AbsoluteSize
			return pos.X >= p.X and pos.X <= p.X+s.X and pos.Y >= p.Y and pos.Y <= p.Y+s.Y
		end
		if within(sidebar) or within(panel) then return end
		minimizeNow()
	end)

	return screen
end

buildUI()
