local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local vu = game:GetService("VirtualUser")

local Net = ReplicatedStorage:WaitForChild("Packages")
    :WaitForChild("_Index")
    :WaitForChild("sleitnick_net@0.2.0")
    :WaitForChild("net")

local RFChargeFishingRod = Net:WaitForChild("RF/ChargeFishingRod")
local RFStartMinigame = Net:WaitForChild("RF/RequestFishingMinigameStarted")
local REReplicateTextEffect = Net:WaitForChild("RE/ReplicateTextEffect")
local REFishingCompleted = Net:WaitForChild("RE/FishingCompleted")

local running = true

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

REReplicateTextEffect.OnClientEvent:Connect(function(payload)
    if not running or not isMyExclaim(payload) then return end
    task.wait(1.05)
    REFishingCompleted:FireServer()
end)
