local SCRIPT_URL = "https://raw.githubusercontent.com/fluxgitscripts/vending-rob/refs/heads/main/vending-rob.lua"

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")

local queue_on_teleport = syn and syn.queue_on_teleport or queue_on_teleport or fluxus and fluxus.queue_on_teleport

local plr = Players.LocalPlayer
local totalHits = 0

local EJw = game:GetService("ReplicatedStorage"):WaitForChild("EJw")
local RemoteEvents = {
    RobEvent = EJw:WaitForChild("a3126821-130a-4135-80e1-1d28cece4007"),
}

local VENDING_COLLECT_CODE = "wRl"
local ProximityPromptTimeBet = 2.5

_G.vendingActive = false
_G.flightSpeed = 160
_G.vendingPoliceRange = 55

local vendingLoopThread = nil
local instantCollectThread = nil
local teleportActive = false
local currentTween = nil
local currentTweenConn = nil

local SERVERHOP_POSITION = Vector3.new(-1292.9005126953125, -2, 3685.330810546875)
local DROP_Y = -2

local function getChar()
    local char = plr.Character
    if not char then return nil end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    return char, hum, root
end

local function notify(title, text)
    StarterGui:SetCore("SendNotification", {
        Title = title,
        Text = text,
        Time = 4
    })
end

local function doServerHop()
    notify("Server Hop", "Limit reached or No Vending - Hopping!")
    task.wait(1)
    
    if queue_on_teleport and SCRIPT_URL ~= "" then
        local payload = string.format('task.wait(5); loadstring(game:HttpGet("%s"))()', SCRIPT_URL)
        pcall(function() queue_on_teleport(payload) end)
    end
    
    local success, servers = pcall(function()
        return HttpService:JSONDecode(game:HttpGet("https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100")).data
    end)
    
    if success and servers then
        for _, server in pairs(servers) do
            if server.playing < server.maxPlayers and server.id ~= game.JobId then
                TeleportService:TeleportToPlaceInstance(game.PlaceId, server.id, plr)
                return
            end
        end
    end
    TeleportService:Teleport(game.PlaceId, plr)
end

local function tweenTo(destination)
    if teleportActive then 
        if currentTween then currentTween:Cancel() end
        if currentTweenConn then currentTweenConn:Disconnect() end
    end
    teleportActive = true

    local char, hum, hrp = getChar()
    local vehicle = Workspace.Vehicles:FindFirstChild(plr.Name)
    if not vehicle then teleportActive = false return false end

    local driveSeat = vehicle:FindFirstChild("DriveSeat", true) or vehicle:FindFirstChildWhichIsA("VehicleSeat", true)
    if not driveSeat then teleportActive = false return false end
    vehicle.PrimaryPart = driveSeat

    local targetCF = (typeof(destination) == "CFrame") and destination or CFrame.new(destination)
    local dist = (vehicle:GetPivot().Position - targetCF.Position).Magnitude
    local duration = dist / _G.flightSpeed

    local val = Instance.new("CFrameValue")
    val.Value = vehicle:GetPivot()
    currentTweenConn = val.Changed:Connect(function(newCF)
        vehicle:PivotTo(newCF)
    end)

    currentTween = TweenService:Create(val, TweenInfo.new(duration, Enum.EasingStyle.Linear), {Value = targetCF})
    currentTween:Play()
    currentTween.Completed:Wait()

    currentTweenConn:Disconnect()
    val:Destroy()
    teleportActive = false
    return true
end

local function VendingRob(targetVending)
    if totalHits >= 10 then return false end
    
    local glass = targetVending:FindFirstChild("Glass")
    if not glass then return false end

    local targetPos = glass.Position - glass.CFrame.LookVector * 1.5
    tweenTo(CFrame.lookAt(targetPos, glass.Position))
    
    task.wait(0.5)
    local char, hum, root = getChar()
    if hum then hum.Sit = false end
    task.wait(0.5)

    for i = 1, 10 do
        if totalHits >= 10 then break end
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F, false, game)
        task.wait(0.1)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F, false, game)
        totalHits = totalHits + 1
        task.wait(0.4)
    end

    if totalHits >= 10 then
        _G.vendingActive = false
        doServerHop()
    end
    
    return true
end

local function findNearestVending()
    local folder = Workspace:FindFirstChild("Robberies") and Workspace.Robberies:FindFirstChild("VendingMachines")
    if not folder then return nil end
    local _, _, root = getChar()
    if not root then return nil end
    
    for _, model in ipairs(folder:GetChildren()) do
        local light = model:FindFirstChild("Light")
        if light and light.Color.G > 0.5 then
            return model
        end
    end
    return nil
end

local function vendingMainLoop()
    while _G.vendingActive and totalHits < 10 do
        local target = findNearestVending()
        if target then
            VendingRob(target)
        else
            doServerHop()
            break
        end
        task.wait(2)
    end
end

local OrionLib = loadstring(game:HttpGet("https://moon-hub.pages.dev/orion.lua"))()
local Window = OrionLib:MakeWindow({Name = "Vending Rob (10 Hits Max)", SaveConfig = true, ConfigFolder = "VendingConfig"})
local MainTab = Window:MakeTab({Name = "Main", Icon = "rbxassetid://4483345998"})

MainTab:AddToggle({
    Name = "Start AutoRob (10 Hits Total)",
    Default = false,
    Callback = function(Value)
        _G.vendingActive = Value
        if Value then
            totalHits = 0
            task.spawn(vendingMainLoop)
        end
    end
})

OrionLib:Init()
