local SCRIPT_URL = "https://raw.githubusercontent.com/fluxgitscripts/vending-rob/refs/heads/main/vending-rob.lua"

local Players             = game:GetService("Players")
local TweenService        = game:GetService("TweenService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local StarterGui          = game:GetService("StarterGui")
local Workspace           = game:GetService("Workspace")
local TeleportService     = game:GetService("TeleportService")
local HttpService         = game:GetService("HttpService")

local queue_on_teleport = syn and syn.queue_on_teleport or queue_on_teleport or (fluxus and fluxus.queue_on_teleport)

local plr = Players.LocalPlayer

local EJw = game:GetService("ReplicatedStorage"):WaitForChild("EJw")
local RemoteEvents = {
    RobEvent = EJw:WaitForChild("a3126821-130a-4135-80e1-1d28cece4007"),
    SellItem = EJw:WaitForChild("eb233e6a-acb9-4169-acb9-129fe8cb06bb"),
}

local VENDING_COLLECT_CODE   = "wRl"
local ProximityPromptTimeBet = 2.5

_G.vendingActive      = false
_G.flightSpeed        = 160
_G.vendingPoliceRange = 55

local vendingLoopThread    = nil
local instantCollectThread = nil

local teleportActive   = false
local currentTween     = nil
local currentTweenConn = nil

local SERVERHOP_POSITION = Vector3.new(-1292.9005126953125, -2, 3685.330810546875)
local DROP_Y             = -2

-- ============================================================
-- HILFSFUNKTIONEN
-- ============================================================
local function getChar()
    local char = plr.Character
    if not char then return nil, nil, nil end
    local hum  = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    return char, hum, root
end

local function notify(title, text)
    StarterGui:SetCore("SendNotification", {
        Title = title,
        Text  = text,
        Time  = 4
    })
end

local function stopCurrentTween()
    if currentTween then currentTween:Cancel(); currentTween = nil end
    if currentTweenConn then currentTweenConn:Disconnect(); currentTweenConn = nil end
    teleportActive = false
end

local function isPoliceNearby()
    local _, _, root = getChar()
    if not root then return false end
    local hum = root.Parent:FindFirstChildOfClass("Humanoid")
    if hum and hum.Health <= 25 then return true end

    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= plr and p.Team and p.Team.Name == "Police" then
            local pChar = p.Character
            if pChar and pChar:FindFirstChild("HumanoidRootPart") then
                if (pChar.HumanoidRootPart.Position - root.Position).Magnitude <= _G.vendingPoliceRange then
                    return true
                end
            end
        end
    end
    return false
end

-- ============================================================
-- AUTO COLLECT LOGIK (Hintergrund)
-- ============================================================
local function startAutoCollect()
    local myName = plr.Name
    local dropsFolder = Workspace:WaitForChild("Drops")
    local Collected = {}

    local function collectDrop(obj)
        if Collected[obj] or obj.Transparency ~= 0 then return end
        Collected[obj] = true
        task.spawn(function()
            RemoteEvents.RobEvent:FireServer(obj, VENDING_COLLECT_CODE, true)
            task.wait(ProximityPromptTimeBet)
            RemoteEvents.RobEvent:FireServer(obj, VENDING_COLLECT_CODE, false)
            task.wait(0.3)
            Collected[obj] = nil
        end)
    end

    while _G.vendingActive do
        local _, _, root = getChar()
        if root then
            for _, obj in ipairs(dropsFolder:GetChildren()) do
                if obj:IsA("MeshPart") and obj.Name == myName and (obj.Position - root.Position).Magnitude <= 30 then
                    collectDrop(obj)
                end
            end
        end
        task.wait(0.25)
    end
end

-- ============================================================
-- TWEEN & MOVEMENT
-- ============================================================
local function tweenTo(destination)
    if teleportActive then stopCurrentTween() end
    teleportActive = true

    local char, hum, hrp = getChar()
    local vehicle = Workspace.Vehicles:FindFirstChild(plr.Name)
    if not vehicle then teleportActive = false return false end

    local driveSeat = vehicle:FindFirstChild("DriveSeat", true) or vehicle:FindFirstChildWhichIsA("VehicleSeat", true)
    if not driveSeat then teleportActive = false return false end
    vehicle.PrimaryPart = driveSeat

    if hum and hum.SeatPart ~= driveSeat then
        if hrp then hrp.CFrame = driveSeat.CFrame end
        task.wait(0.1)
        driveSeat:Sit(hum)
    end

    local targetCF = (typeof(destination) == "CFrame") and destination or CFrame.new(destination)
    local duration = (vehicle:GetPivot().Position - targetCF.Position).Magnitude / _G.flightSpeed

    local val = Instance.new("CFrameValue")
    val.Value = vehicle:GetPivot()
    currentTweenConn = val.Changed:Connect(function(newCF) vehicle:PivotTo(newCF) end)
    currentTween = TweenService:Create(val, TweenInfo.new(duration, Enum.EasingStyle.Linear), {Value = targetCF})
    currentTween:Play()
    currentTween.Completed:Wait()

    currentTweenConn:Disconnect()
    val:Destroy()
    teleportActive = false
    return true
end

local function plrTween(targetCFrame)
    local _, _, root = getChar()
    if not root then return end
    local tw = TweenService:Create(root, TweenInfo.new(0.5, Enum.EasingStyle.Linear), {CFrame = targetCFrame})
    tw:Play()
    tw.Completed:Wait()
end

-- ============================================================
-- VENDING RAUB LOGIK
-- ============================================================
local function VendingRob(targetVending)
    local glass = targetVending:FindFirstChild("Glass")
    if not glass then return false end

    local targetPos = glass.Position - glass.CFrame.LookVector * 1.5
    local success = tweenTo(CFrame.lookAt(targetPos, glass.Position))
    if not success then return false end

    task.wait(0.5)
    local _, hum = getChar()
    if hum then hum.Sit = false end
    task.wait(0.6)

    plrTween(CFrame.lookAt(glass.Position - glass.CFrame.LookVector * 1.5, glass.Position))
    task.wait(0.3)

    for i = 1, 10 do
        if isPoliceNearby() then break end
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F, false, game)
        task.wait(0.1)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F, false, game)
        task.wait(0.35)
    end

    task.wait(1)
    return true
end

-- ============================================================
-- SERVERHOP
-- ============================================================
local function doServerHop()
    notify("Server Hop", "Changing Server...")
    task.wait(1)

    if queue_on_teleport then
        local payload = [[
            wait(3)
            loadstring(game:HttpGet("]] .. SCRIPT_URL .. [["))()
        ]]
        pcall(function() queue_on_teleport(payload) end)
    end

    local success, servers = pcall(function()
        return HttpService:JSONDecode(
            game:HttpGet("https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100")
        ).data
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

local function findNearestVending()
    local folder = Workspace:FindFirstChild("Robberies") and Workspace.Robberies:FindFirstChild("VendingMachines")
    if not folder then return nil end
    local _, _, root = getChar()
    if not root then return nil end

    local nearest, minDist = nil, math.huge
    for _, model in ipairs(folder:GetChildren()) do
        local light = model:FindFirstChild("Light")
        if light and math.abs(light.Color.R - 73/255) < 0.1 then
            local dist = (light.Position - root.Position).Magnitude
            if dist < minDist then
                minDist = dist
                nearest = model
            end
        end
    end
    return nearest
end

-- ============================================================
-- MAIN LOOP
-- ============================================================
local function vendingMainLoop()
    while _G.vendingActive do
        if not Workspace.Vehicles:FindFirstChild(plr.Name) then
            notify("Vehicle", "Please spawn a vehicle!")
            task.wait(3)
            continue
        end

        local target = findNearestVending()
        if not target then
            tweenTo(CFrame.new(SERVERHOP_POSITION))
            doServerHop()
            break
        end

        VendingRob(target)
        task.wait(1)
    end
end

-- ============================================================
-- UI SETUP (Orion)
-- ============================================================
local OrionLib = loadstring(game:HttpGet("https://moon-hub.pages.dev/orion.lua"))()
local Window = OrionLib:MakeWindow({Name = "Vending Rob (10 Hits)", SaveConfig = true, ConfigFolder = "VendingConfig"})

local MainTab = Window:MakeTab({Name = "Main"})

MainTab:AddToggle({
    Name = "Activate Vending Rob",
    Default = false,
    Callback = function(Value)
        _G.vendingActive = Value
        if Value then
            vendingLoopThread = task.spawn(vendingMainLoop)
            instantCollectThread = task.spawn(startAutoCollect)
        else
            if vendingLoopThread then task.cancel(vendingLoopThread) end
            if instantCollectThread then task.cancel(instantCollectThread) end
            stopCurrentTween()
        end
    end
})

MainTab:AddSlider({
    Name = "Flight Speed",
    Min = 50, Max = 300, Default = 160,
    Callback = function(Value) _G.flightSpeed = Value end
})

OrionLib:Init()
