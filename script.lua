--// Mountain Expedition Recorder
--// Compatible with Delta Executor Android
--// Features: Record, Save, Load, Replay paths with checkpoints

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local Humanoid = Character:WaitForChild("Humanoid")
local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart")

--// Configuration
local Config = {
    RecordInterval = 0.1, -- seconds between position recordings
    TeleportSpeed = 100, -- studs per second for replay
    SaveFolder = "MountainRecorder",
    FileExtension = ".json"
}

--// State Management
local State = {
    IsRecording = false,
    IsReplaying = false,
    RecordedData = {
        Positions = {},
        Checkpoints = {},
        StartTime = nil,
        MapName = "Expedition",
        TotalDistance = 0
    },
    CurrentRecording = {},
    UI = nil
}

--// Utility Functions
local function GetSavePath(filename)
    return Config.SaveFolder .. "/" .. filename .. Config.FileExtension
end

local function EnsureFolderExists()
    local success = pcall(function()
        -- Delta Executor compatible folder creation
        if not isfolder(Config.SaveFolder) then
            makefolder(Config.SaveFolder)
        end
    end)
    return success
end

local function CalculateDistance(pos1, pos2)
    return (pos1 - pos2).Magnitude
end

--// Recording Functions
local function StartRecording()
    if State.IsRecording then
        warn("Already recording!")
        return
    end
    
    if State.IsReplaying then
        warn("Cannot record while replaying!")
        return
    end
    
    State.IsRecording = true
    State.CurrentRecording = {
        Positions = {},
        Checkpoints = {},
        StartTime = tick(),
        MapName = "Expedition_" .. os.date("%Y%m%d_%H%M%S"),
        TotalDistance = 0
    }
    
    -- Record initial position
    table.insert(State.CurrentRecording.Positions, {
        Position = HumanoidRootPart.Position,
        Time = 0,
        Action = "start"
    })
    
    print("🎬 Recording Started!")
    
    -- Start recording loop
    spawn(function()
        local lastPosition = HumanoidRootPart.Position
        local startTime = tick()
        
        while State.IsRecording do
            wait(Config.RecordInterval)
            
            if not State.IsRecording then break end
            
            local currentPos = HumanoidRootPart.Position
            local distance = CalculateDistance(lastPosition, currentPos)
            
            if distance > 0.1 then -- Only record if moved significantly
                table.insert(State.CurrentRecording.Positions, {
                    Position = {currentPos.X, currentPos.Y, currentPos.Z},
                    Time = tick() - startTime,
                    Distance = distance,
                    Velocity = HumanoidRootPart.Velocity.Magnitude
                })
                
                State.CurrentRecording.TotalDistance = State.CurrentRecording.TotalDistance + distance
                lastPosition = currentPos
            end
        end
    end)
    
    UpdateUIStatus("Recording...")
end

local function StopRecording()
    if not State.IsRecording then
        warn("Not recording!")
        return
    end
    
    State.IsRecording = false
    State.RecordedData = State.CurrentRecording
    
    print("⏹️ Recording Stopped!")
    print("📊 Stats:")
    print("  - Duration: " .. string.format("%.2f", tick() - State.CurrentRecording.StartTime) .. "s")
    print("  - Points recorded: " .. #State.CurrentRecording.Positions)
    print("  - Total distance: " .. string.format("%.2f", State.CurrentRecording.TotalDistance) .. " studs")
    
    UpdateUIStatus("Recording Saved - " .. #State.CurrentRecording.Positions .. " points")
end

local function AddCheckpoint(checkpointName)
    if not State.IsRecording then
        warn("Start recording first!")
        return
    end
    
    local checkpointData = {
        Name = checkpointName or ("Checkpoint_" .. (#State.CurrentRecording.Checkpoints + 1)),
        Position = {HumanoidRootPart.Position.X, HumanoidRootPart.Position.Y, HumanoidRootPart.Position.Z},
        Time = tick() - State.CurrentRecording.StartTime,
        Index = #State.CurrentRecording.Positions + 1
    }
    
    table.insert(State.CurrentRecording.Checkpoints, checkpointData)
    table.insert(State.CurrentRecording.Positions, {
        Position = {HumanoidRootPart.Position.X, HumanoidRootPart.Position.Y, HumanoidRootPart.Position.Z},
        Time = checkpointData.Time,
        Action = "checkpoint",
        CheckpointName = checkpointData.Name
    })
    
    print("📍 Checkpoint added: " .. checkpointData.Name)
end

--// Save/Load Functions
local function SaveRecording(customName)
    if #State.RecordedData.Positions == 0 then
        warn("No recording to save!")
        return
    end
    
    EnsureFolderExists()
    
    local filename = customName or State.RecordedData.MapName
    local filepath = GetSavePath(filename)
    
    local saveData = {
        Version = "1.0",
        SavedAt = os.date("%Y-%m-%d %H:%M:%S"),
        Data = State.RecordedData
    }
    
    local success, err = pcall(function()
        local jsonData = HttpService:JSONEncode(saveData)
        writefile(filepath, jsonData)
    end)
    
    if success then
        print("💾 Recording saved to: " .. filepath)
        UpdateUIStatus("Saved: " .. filename)
    else
        warn("Failed to save: " .. tostring(err))
    end
end

local function LoadRecording(filename)
    local filepath = GetSavePath(filename)
    
    local success, data = pcall(function()
        if not isfile(filepath) then
            error("File not found: " .. filepath)
        end
        local content = readfile(filepath)
        return HttpService:JSONDecode(content)
    end)
    
    if success and data then
        State.RecordedData = data.Data
        print("📂 Recording loaded: " .. filename)
        print("  - Checkpoints: " .. #State.RecordedData.Checkpoints)
        print("  - Path points: " .. #State.RecordedData.Positions)
        UpdateUIStatus("Loaded: " .. filename .. " (" .. #State.RecordedData.Positions .. " points)")
        return true
    else
        warn("Failed to load: " .. tostring(data))
        return false
    end
end

local function ListRecordings()
    EnsureFolderExists()
    
    local files = listfiles(Config.SaveFolder)
    local recordings = {}
    
    for _, file in ipairs(files) do
        if file:match(Config.FileExtension .. "$") then
            local name = file:match("([^/\\]+)" .. Config.FileExtension .. "$")
            table.insert(recordings, name)
        end
    end
    
    return recordings
end

--// Replay Functions
local function ReplayRecording(startFromCheckpoint)
    if State.IsRecording then
        warn("Stop recording first!")
        return
    end
    
    if State.IsReplaying then
        warn("Already replaying!")
        return
    end
    
    if #State.RecordedData.Positions == 0 then
        warn("No recording loaded!")
        return
    end
    
    State.IsReplaying = true
    print("▶️ Starting replay...")
    UpdateUIStatus("Replaying...")
    
    spawn(function()
        local positions = State.RecordedData.Positions
        local startIndex = 1
        
        -- Find checkpoint index if specified
        if startFromCheckpoint then
            for i, point in ipairs(positions) do
                if point.Action == "checkpoint" and point.CheckpointName == startFromCheckpoint then
                    startIndex = i
                    print("Starting from checkpoint: " .. startFromCheckpoint)
                    break
                end
            end
        end
        
        for i = startIndex, #positions do
            if not State.IsReplaying then
                print("⏸️ Replay stopped")
                break
            end
            
            local point = positions[i]
            local targetPos = typeof(point.Position) == "table" 
                and Vector3.new(point.Position[1], point.Position[2], point.Position[3])
                or point.Position
            
            -- Smooth teleport using Tween
            local distance = CalculateDistance(HumanoidRootPart.Position, targetPos)
            local duration = distance / Config.TeleportSpeed
            
            local tween = TweenService:Create(
                HumanoidRootPart,
                TweenInfo.new(duration, Enum.EasingStyle.Linear),
                {CFrame = CFrame.new(targetPos)}
            )
            
            tween:Play()
            tween.Completed:Wait()
            
            -- Show checkpoint notification
            if point.Action == "checkpoint" then
                print("🏁 Reached: " .. (point.CheckpointName or "Checkpoint"))
            end
            
            -- Small delay between points
            if i < #positions then
                local nextPoint = positions[i + 1]
                local waitTime = (nextPoint.Time or 0) - (point.Time or 0)
                if waitTime > 0 then
                    wait(math.min(waitTime, 0.5))
                end
            end
        end
        
        State.IsReplaying = false
        print("✅ Replay completed!")
        UpdateUIStatus("Replay completed")
    end)
end

local function StopReplay()
    State.IsReplaying = false
    UpdateUIStatus("Replay stopped")
end

--// UI Creation (Delta Executor Compatible)
local function CreateUI()
    -- Destroy existing UI
    if State.UI then
        State.UI:Destroy()
    end
    
    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "MountainRecorderUI"
    ScreenGui.ResetOnSpawn = false
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    
    -- Main Frame
    local MainFrame = Instance.new("Frame")
    MainFrame.Name = "MainFrame"
    MainFrame.Size = UDim2.new(0, 300, 0, 400)
    MainFrame.Position = UDim2.new(0.5, -150, 0.5, -200)
    MainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    MainFrame.BorderSizePixel = 0
    MainFrame.Active = true
    MainFrame.Draggable = true
    MainFrame.Parent = ScreenGui
    
    -- Corner Radius
    local Corner = Instance.new("UICorner")
    Corner.CornerRadius = UDim.new(0, 10)
    Corner.Parent = MainFrame
    
    -- Title
    local Title = Instance.new("TextLabel")
    Title.Name = "Title"
    Title.Size = UDim2.new(1, 0, 0, 40)
    Title.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    Title.Text = "🏔️ Mountain Recorder"
    Title.TextColor3 = Color3.fromRGB(255, 255, 255)
    Title.TextSize = 18
    Title.Font = Enum.Font.GothamBold
    Title.Parent = MainFrame
    
    local TitleCorner = Instance.new("UICorner")
    TitleCorner.CornerRadius = UDim.new(0, 10)
    TitleCorner.Parent = Title
    
    -- Status Label
    local StatusLabel = Instance.new("TextLabel")
    StatusLabel.Name = "Status"
    StatusLabel.Size = UDim2.new(1, -20, 0, 30)
    StatusLabel.Position = UDim2.new(0, 10, 0, 50)
    StatusLabel.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    StatusLabel.Text = "Status: Ready"
    StatusLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
    StatusLabel.TextSize = 14
    StatusLabel.Font = Enum.Font.Gotham
    StatusLabel.Parent = MainFrame
    
    local StatusCorner = Instance.new("UICorner")
    StatusCorner.CornerRadius = UDim.new(0, 5)
    StatusCorner.Parent = StatusLabel
    
    -- Button Container
    local ButtonContainer = Instance.new("ScrollingFrame")
    ButtonContainer.Name = "Buttons"
    ButtonContainer.Size = UDim2.new(1, -20, 1, -100)
    ButtonContainer.Position = UDim2.new(0, 10, 0, 90)
    ButtonContainer.BackgroundTransparency = 1
    ButtonContainer.ScrollBarThickness = 5
    ButtonContainer.Parent = MainFrame
    
    local UIListLayout = Instance.new("UIListLayout")
    UIListLayout.Padding = UDim.new(0, 10)
    UIListLayout.Parent = ButtonContainer
    
    -- Button Creation Function
    local function CreateButton(name, callback, color)
        local Button = Instance.new("TextButton")
        Button.Name = name
        Button.Size = UDim2.new(1, 0, 0, 40)
        Button.BackgroundColor3 = color or Color3.fromRGB(60, 60, 60)
        Button.Text = name
        Button.TextColor3 = Color3.fromRGB(255, 255, 255)
        Button.TextSize = 14
        Button.Font = Enum.Font.GothamBold
        Button.Parent = ButtonContainer
        
        local ButtonCorner = Instance.new("UICorner")
        ButtonCorner.CornerRadius = UDim.new(0, 8)
        ButtonCorner.Parent = Button
        
        Button.MouseButton1Click:Connect(callback)
        
        -- Hover effect
        Button.MouseEnter:Connect(function()
            TweenService:Create(Button, TweenInfo.new(0.2), {BackgroundColor3 = color and color:Lerp(Color3.new(1,1,1), 0.2) or Color3.fromRGB(80, 80, 80)}):Play()
        end)
        
        Button.MouseLeave:Connect(function()
            TweenService:Create(Button, TweenInfo.new(0.2), {BackgroundColor3 = color or Color3.fromRGB(60, 60, 60)}):Play()
        end)
        
        return Button
    end
    
    -- Control Buttons
    CreateButton("▶️ Start Recording", function()
        StartRecording()
    end, Color3.fromRGB(0, 150, 0))
    
    CreateButton("⏹️ Stop Recording", function()
        StopRecording()
    end, Color3.fromRGB(150, 0, 0))
    
    CreateButton("📍 Add Checkpoint", function()
        -- Simple input for checkpoint name
        local name = "Checkpoint_" .. ((State.CurrentRecording.Checkpoints and #State.CurrentRecording.Checkpoints + 1) or 1)
        AddCheckpoint(name)
    end, Color3.fromRGB(0, 100, 150))
    
    CreateButton("▶️ Replay Recording", function()
        ReplayRecording()
    end, Color3.fromRGB(150, 100, 0))
    
    CreateButton("⏸️ Stop Replay", function()
        StopReplay()
    end, Color3.fromRGB(100, 0, 0))
    
    CreateButton("💾 Save Recording", function()
        SaveRecording()
    end, Color3.fromRGB(0, 100, 100))
    
    CreateButton("📂 Load Recording", function()
        -- List and load recordings
        local recordings = ListRecordings()
        if #recordings > 0 then
            print("Available recordings:")
            for i, name in ipairs(recordings) do
                print(i .. ". " .. name)
            end
            -- Load the most recent one for simplicity
            LoadRecording(recordings[#recordings])
        else
            warn("No recordings found!")
        end
    end, Color3.fromRGB(100, 100, 0))
    
    CreateButton("📋 List Recordings", function()
        local recordings = ListRecordings()
        print("=== Saved Recordings ===")
        for i, name in ipairs(recordings) do
            print(i .. ". " .. name)
        end
        print("=======================")
    end, Color3.fromRGB(80, 80, 80))
    
    CreateButton("🔧 Settings", function()
        print("Current Settings:")
        print("  Record Interval: " .. Config.RecordInterval .. "s")
        print("  Teleport Speed: " .. Config.TeleportSpeed .. " studs/s")
        print("  Save Folder: " .. Config.SaveFolder)
    end, Color3.fromRGB(60, 60, 80))
    
    -- Close Button
    local CloseButton = Instance.new("TextButton")
    CloseButton.Name = "Close"
    CloseButton.Size = UDim2.new(0, 30, 0, 30)
    CloseButton.Position = UDim2.new(1, -35, 0, 5)
    CloseButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
    CloseButton.Text = "X"
    CloseButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    CloseButton.TextSize = 16
    CloseButton.Font = Enum.Font.GothamBold
    CloseButton.Parent = MainFrame
    
    local CloseCorner = Instance.new("UICorner")
    CloseCorner.CornerRadius = UDim.new(0, 6)
    CloseCorner.Parent = CloseButton
    
    CloseButton.MouseButton1Click:Connect(function()
        ScreenGui:Destroy()
        State.UI = nil
    end)
    
    -- Minimize Button
    local MinButton = Instance.new("TextButton")
    MinButton.Name = "Minimize"
    MinButton.Size = UDim2.new(0, 30, 0, 30)
    MinButton.Position = UDim2.new(1, -70, 0, 5)
    MinButton.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
    MinButton.Text = "-"
    MinButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    MinButton.TextSize = 16
    MinButton.Font = Enum.Font.GothamBold
    MinButton.Parent = MainFrame
    
    local MinCorner = Instance.new("UICorner")
    MinCorner.CornerRadius = UDim.new(0, 6)
    MinCorner.Parent = MinButton
    
    local minimized = false
    MinButton.MouseButton1Click:Connect(function()
        minimized = not minimized
        ButtonContainer.Visible = not minimized
        Title.Visible = not minimized
        StatusLabel.Visible = not minimized
        MainFrame.Size = minimized and UDim2.new(0, 120, 0, 40) or UDim2.new(0, 300, 0, 400)
    end)
    
    -- Store UI reference
    State.UI = ScreenGui
    State.StatusLabel = StatusLabel
    
    -- Parent to CoreGui or PlayerGui
    pcall(function()
        ScreenGui.Parent = game:GetService("CoreGui")
    end)
    
    if not ScreenGui.Parent then
        ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    end
    
    return ScreenGui
end

-- Update UI Status
function UpdateUIStatus(text)
    if State.StatusLabel then
        State.StatusLabel.Text = "Status: " .. text
    end
end

--// Keybinds (Optional)
local function SetupKeybinds()
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        
        -- F1 - Start/Stop Recording
        if input.KeyCode == Enum.KeyCode.F1 then
            if State.IsRecording then
                StopRecording()
            else
                StartRecording()
            end
        end
        
        -- F2 - Add Checkpoint
        if input.KeyCode == Enum.KeyCode.F2 then
            AddCheckpoint()
        end
        
        -- F3 - Quick Save
        if input.KeyCode == Enum.KeyCode.F3 then
            SaveRecording()
        end
        
        -- F4 - Quick Load Last
        if input.KeyCode == Enum.KeyCode.F4 then
            local recordings = ListRecordings()
            if #recordings > 0 then
                LoadRecording(recordings[#recordings])
            end
        end
    end)
end

--// Auto-load Character
LocalPlayer.CharacterAdded:Connect(function(char)
    Character = char
    Humanoid = char:WaitForChild("Humanoid")
    HumanoidRootPart = char:WaitForChild("HumanoidRootPart")
end)

--// Initialize
print("========================================")
print("🏔️ Mountain Expedition Recorder Loaded")
print("========================================")
print("Commands:")
print("  - F1: Start/Stop Recording")
print("  - F2: Add Checkpoint")
print("  - F3: Quick Save")
print("  - F4: Quick Load Last")
print("")
print("Use the UI or functions directly:")
print("  StartRecording()")
print("  StopRecording()")
print("  AddCheckpoint('Summit')")
print("  SaveRecording('MyRun')")
print("  LoadRecording('MyRun')")
print("  ReplayRecording()")
print("========================================")

-- Create UI
CreateUI()
SetupKeybinds()

-- Return module for external access
return {
    Start = StartRecording,
    Stop = StopRecording,
    Checkpoint = AddCheckpoint,
    Save = SaveRecording,
    Load = LoadRecording,
    Replay = ReplayRecording,
    List = ListRecordings,
    Config = Config,
    State = State
}
