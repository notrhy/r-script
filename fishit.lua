local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local vu = game:GetService("VirtualUser")
local vim = game:GetService("VirtualInputManager")

local Net = ReplicatedStorage:WaitForChild("Packages")
    :WaitForChild("_Index")
    :WaitForChild("sleitnick_net@0.2.0")
    :WaitForChild("net")

local RFChargeFishingRod = Net:WaitForChild("RF/ChargeFishingRod")
local RFStartMinigame = Net:WaitForChild("RF/RequestFishingMinigameStarted")
local REReplicateTextEffect = Net:WaitForChild("RE/ReplicateTextEffect")
local REFishingCompleted = Net:WaitForChild("RE/FishingCompleted")
local RFSellAllItems = Net:WaitForChild("RF/SellAllItems")
local RFCancelFishingInputs = Net:WaitForChild("RF/CancelFishingInputs")

local running = false
local minigameStarted = false
local MAX_RETRY_RF = 2
local RECHARGE_DELAY = 1.01

local function safeInvoke(rf, ...)
    local args = { ... }
    local delay = 0.08
    for _ = 1, MAX_RETRY_RF do
        local ok, res = pcall(function()
            return rf:InvokeServer(table.unpack(args))
        end)
        if ok then return true, res end
        task.wait(delay)
        delay = math.min(delay * 2, 0.5)
    end
    return false, nil
end

local function click(duration)
	local seconds = (duration or 300) / 1000
	local viewport = workspace.CurrentCamera.ViewportSize
	local x, y = viewport.X * 0.1, viewport.Y * 0.9

	local timeout = 1.2
	local retryDelay = 0.25

	repeat
		minigameStarted = false

		vim:SendMouseButtonEvent(x, y, 0, true, game, 0)
		task.wait(seconds)
		vim:SendMouseButtonEvent(x, y, 0, false, game, 0)

		local start = tick()
		while tick() - start < timeout do
			if minigameStarted then
				return
			end
			task.wait(0.05)
		end

		print("[AUTO] Click gagal, ulangi...")
		task.wait(retryDelay)
	until not running
end

local function cancelFishing()
    select(1, safeInvoke(RFCancelFishingInputs))
    task.wait(0.1)
end

local function repair()
    cancelFishing()
    click()
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

    local char = LocalPlayer.Character
    if char and inst:IsDescendantOf(char) then return true end

    local ownerModel = inst:FindFirstAncestorOfClass("Model")
    local ownerPlr = ownerModel and Players:GetPlayerFromCharacter(ownerModel)
    return ownerPlr == LocalPlayer
end

LocalPlayer.Idled:Connect(function()
	print("🕒 Player idle, mengirim input virtual...")
	vu:Button2Down(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
	task.wait(1)
	vu:Button2Up(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
end)

local function resetCharacter()
	local char = LocalPlayer.Character
	if not char then return end

	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local lastCFrame = hrp.CFrame

	char:BreakJoints()

	local newChar = LocalPlayer.CharacterAdded:Wait()
	local newHRP = newChar:WaitForChild("HumanoidRootPart")

	task.wait(0.1)
	newHRP.CFrame = lastCFrame
	print("[RESET] Karakter dikembalikan ke posisi lama.")
end

local function sellFish()
    safeInvoke(RFSellAllItems)
end

REReplicateTextEffect.OnClientEvent:Connect(function(payload)
    if not running or not isMyExclaim(payload) then return end
    task.wait(0.85)
    REFishingCompleted:FireServer()

    task.delay(RECHARGE_DELAY, function()
        if running then cancelFishing() click() end
    end)
end)

local autoFishing

local function main()
    running = not running
    if running then
        autoFishing.BackgroundColor3 = Color3.fromRGB(50, 200, 90)
        click()
    else
        autoFishing.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    end
end

local meta_t = getrawmetatable(game)
local oldNamecall = meta_t.__namecall
setreadonly(meta_t, false)

meta_t.__namecall = function(self, ...)
	local method = getnamecallmethod()
	local args = { ... }

	if self == RFStartMinigame and method == "InvokeServer" then
		minigameStarted = true
	end

	return oldNamecall(self, ...)
end

setreadonly(meta_t, true)

local function createResetButton()
	local screen = Instance.new("ScreenGui")
	screen.Name = "ResetButtonUI"
	screen.ResetOnSpawn = false
	screen.Parent = LocalPlayer:WaitForChild("PlayerGui")

	local container = Instance.new("Frame")
	container.BackgroundTransparency = 1
	container.AnchorPoint = Vector2.new(0.5, 0)
	container.Position = UDim2.new(0.094, -60, 0.150, 0)
	container.Size = UDim2.new(0, 120, 0, 100)
	container.Parent = screen

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.Padding = UDim.new(0, 10)
	layout.Parent = container

    autoFishing = Instance.new("TextButton")
    autoFishing.Size = UDim2.new(1, 0, 0, 40)
	autoFishing.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	autoFishing.TextColor3 = Color3.new(1, 1, 1)
	autoFishing.Font = Enum.Font.GothamBold
	autoFishing.TextSize = 16
	autoFishing.Text = "Auto Fishing"
	autoFishing.Parent = container
	autoFishing.MouseButton1Click:Connect(main)

    local repairButton = Instance.new("TextButton")
    repairButton.Size = UDim2.new(1, 0, 0, 40)
	repairButton.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	repairButton.TextColor3 = Color3.new(1, 1, 1)
	repairButton.Font = Enum.Font.GothamBold
	repairButton.TextSize = 16
	repairButton.Text = "Repair"
	repairButton.Parent = container
	repairButton.MouseButton1Click:Connect(repair)

	local sellButton = Instance.new("TextButton")
	sellButton.Size = UDim2.new(1, 0, 0, 40)
	sellButton.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	sellButton.TextColor3 = Color3.new(1, 1, 1)
	sellButton.Font = Enum.Font.GothamBold
	sellButton.TextSize = 16
	sellButton.Text = "Sell Fish"
	sellButton.Parent = container
	sellButton.MouseButton1Click:Connect(sellFish)

	local resetButton = Instance.new("TextButton")
	resetButton.Size = UDim2.new(1, 0, 0, 40)
	resetButton.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	resetButton.TextColor3 = Color3.new(1, 1, 1)
	resetButton.Font = Enum.Font.GothamBold
	resetButton.TextSize = 16
	resetButton.Text = "Reset Character"
	resetButton.Parent = container
	resetButton.MouseButton1Click:Connect(resetCharacter)
end

createResetButton()
