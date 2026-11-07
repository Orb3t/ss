--// Orbit Hub (standalone) - v2
--// No UI library, no Drawing API, no executor-only functions required.
--// Works with any executor (including very low UNC) and on mobile.
--// Open / close: tap the floating icon, or press the menu key (default RightShift).

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

------------------------------------------------------------
-- Options you can tweak
------------------------------------------------------------
local FLY_SPEED = 60
local GUI_NAME = "OrbitHub"
local ESP_GUI_NAME = "OrbitHubESP"

------------------------------------------------------------
-- Environment / GUI mounting (all optional functions are pcall-guarded)
------------------------------------------------------------
local env = _G
pcall(function()
    if getgenv then env = getgenv() end
end)

local function getPlayerGui()
    return LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 10)
end

local function candidateParents()
    local list = {}
    pcall(function()
        if gethui then
            local h = gethui()
            if h then table.insert(list, h) end
        end
    end)
    pcall(function()
        table.insert(list, game:GetService("CoreGui"))
    end)
    local pg = getPlayerGui()
    if pg then table.insert(list, pg) end
    return list
end

local function removeOldGuis()
    for _, parent in ipairs(candidateParents()) do
        pcall(function()
            local a = parent:FindFirstChild(GUI_NAME)
            if a then a:Destroy() end
            local b = parent:FindFirstChild(ESP_GUI_NAME)
            if b then b:Destroy() end
        end)
    end
end

local function mountGui(gui)
    pcall(function()
        if syn and syn.protect_gui then syn.protect_gui(gui) end
    end)
    for _, parent in ipairs(candidateParents()) do
        local ok = pcall(function()
            gui.Parent = parent
        end)
        if ok and gui.Parent == parent then
            return true
        end
    end
    return false
end

if env.OrbitHubCleanup then
    pcall(env.OrbitHubCleanup)
end
removeOldGuis()

------------------------------------------------------------
-- Character helpers
------------------------------------------------------------
local function getHumanoid()
    local c = LocalPlayer.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function getRoot()
    local c = LocalPlayer.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local startHum = getHumanoid()
local defaultWalkSpeed = startHum and math.floor(startHum.WalkSpeed + 0.5) or 16
local defaultJumpPower = startHum and math.floor(startHum.JumpPower + 0.5) or 50

local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local mobileButtonsWanted = isMobile -- what the "On-screen Buttons" toggle asks for

local function getViewport()
    local cam = workspace.CurrentCamera
    if cam and cam.ViewportSize.X > 0 then
        return cam.ViewportSize
    end
    return Vector2.new(800, 600)
end

------------------------------------------------------------
-- Config
------------------------------------------------------------
local WHITE = Color3.fromRGB(255, 255, 255)

local Config = {
    MenuKey = Enum.KeyCode.RightShift,
    FloatingIcon = true,
    Aim = {
        Enabled = false,
        Key = Enum.UserInputType.MouseButton2,
        Sticky = false,
        TeamCheck = false,
        WallCheck = false,
        Smooth = false,
        Smoothness = 5,
        -- field of view
        FOV = false,
        FOVSize = 120,
        FOVColor = WHITE,
        OnlyInFOV = false,
        DynamicFOV = false,
        -- shake
        Shake = false,
        ShakeAmount = 5,
        -- players that are never targeted: [UserId] = true
        Whitelist = {},
    },
    ESP = {
        Names = false,
        Boxes = false,
        Tracers = false,
        Skeletons = false,
        NamesColor = WHITE,
        BoxesColor = WHITE,
        TracersColor = WHITE,
        SkeletonsColor = WHITE,
        -- players that get no ESP: [UserId] = true
        Whitelist = {},
    },
    Move = {
        WalkSpeed = false,
        WalkSpeedValue = defaultWalkSpeed,
        Jump = false,
        JumpValue = defaultJumpPower,
        Fly = false,
        FlyKey = Enum.KeyCode.F,
        Noclip = false,
        NoclipKey = Enum.KeyCode.N,
        BunnyHop = false,
        BunnyHopKey = Enum.KeyCode.B,
        Anchor = false,
        AnchorKey = Enum.KeyCode.X,
        ShowWaypoints = false,
    },
    UI = {
        PanicKey = Enum.KeyCode.End,
        -- keybind list (position is a percentage of the free screen space)
        KeybindList = false,
        KeybindListX = 2,
        KeybindListY = 35,
        -- watermark
        Watermark = false,
        WatermarkTitle = "Orbit Hub",
        WatermarkPos = "TopRight",
        WatermarkFPS = true,
        WatermarkPing = true,
        WatermarkDate = true,
        WatermarkTime = true,
        WatermarkPlayers = true,
    },
}

local connections = {}

local function connect(signal, fn)
    local c = signal:Connect(fn)
    table.insert(connections, c)
    return c
end

-- feature state
local aimHeld = false
local stickyActive = false
local currentTarget = nil

local flyToggle, noclipToggle, floatToggle, bunnyToggle, anchorToggle
local allToggles = {} -- every feature toggle (used by the panic key)
local flyBV, flyBG
local noclipParts = {}

local listening = nil -- { set = fn(bind), cancel = fn(), button = btn }

local function isWhitelisted(set, player)
    return set[player.UserId] == true
end

------------------------------------------------------------
-- Theme (neutral surfaces are fixed, only the accent changes)
------------------------------------------------------------
local RGB = Color3.fromRGB

local C = {
    Background = RGB(9, 8, 8),
    Surface = RGB(15, 14, 15),
    SurfaceAlt = RGB(20, 20, 21),
    Hover = RGB(28, 28, 30),
    Border = RGB(36, 37, 37),
    SectionBorder = RGB(32, 33, 36),
    Text = RGB(255, 255, 255),
    TextDim = RGB(180, 184, 200),
    TextMute = RGB(118, 122, 136),
}

local accents = {
    Orbit = RGB(138, 156, 229),
    Violet = RGB(160, 112, 255),
    Ocean = RGB(56, 178, 255),
    Crimson = RGB(238, 80, 104),
    Emerald = RGB(52, 208, 134),
    Amber = RGB(255, 168, 66),
    Rainbow = RGB(255, 0, 0),
}
local accentOrder = { "Orbit", "Violet", "Ocean", "Crimson", "Emerald", "Amber", "Rainbow" }

local state = {
    themeName = "Orbit",
    rainbow = false,
    activeTab = nil,
}

local function setAccent(color)
    state.accent = color
    state.accentDark = color:Lerp(Color3.new(0, 0, 0), 0.45)
    state.gradient = ColorSequence.new(state.accentDark, state.accent)
end
setAccent(accents.Orbit)

local accentRegistry = {} -- { instance, property, kind }
local refreshers = {}     -- functions that repaint state-dependent elements

local function accentValue(kind)
    if kind == "Accent" then return state.accent end
    if kind == "Dark" then return state.accentDark end
    return state.gradient
end

-- kind: "Accent" (Color3), "Dark" (Color3) or "Gradient" (ColorSequence)
local function bindAccent(inst, prop, kind)
    table.insert(accentRegistry, { inst, prop, kind })
    inst[prop] = accentValue(kind)
end

local function pruneRegistry()
    for i = #accentRegistry, 1, -1 do
        if accentRegistry[i][1].Parent == nil then
            table.remove(accentRegistry, i)
        end
    end
end

local function applyAccent()
    for _, e in ipairs(accentRegistry) do
        e[1][e[2]] = accentValue(e[3])
    end
    for _, fn in ipairs(refreshers) do
        fn()
    end
end

------------------------------------------------------------
-- UI helpers
------------------------------------------------------------
local FONT
do
    local ok, f = pcall(function()
        return Font.new("rbxassetid://12187365364", Enum.FontWeight.SemiBold, Enum.FontStyle.Normal)
    end)
    FONT = ok and f or Font.fromEnum(Enum.Font.GothamSemibold)
end

local function new(class, props, children)
    local inst = Instance.new(class)
    for k, v in pairs(props or {}) do
        inst[k] = v
    end
    for _, c in ipairs(children or {}) do
        c.Parent = inst
    end
    return inst
end

local function corner(radius)
    return new("UICorner", { CornerRadius = UDim.new(0, radius) })
end

local function cornerFull()
    return new("UICorner", { CornerRadius = UDim.new(1, 0) })
end

local function stroke(parent, color, thickness, transparency)
    local s = new("UIStroke", {
        Color = color or C.Border,
        Thickness = thickness or 1,
        Transparency = transparency or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    })
    s.Parent = parent
    return s
end

local function label(props)
    props.BackgroundTransparency = 1
    props.BorderSizePixel = 0
    props.FontFace = props.FontFace or FONT
    props.TextSize = props.TextSize or 13
    props.TextColor3 = props.TextColor3 or C.Text
    props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
    return new("TextLabel", props)
end

local function tween(inst, props, t, style)
    local tw = TweenService:Create(
        inst,
        TweenInfo.new(t or 0.12, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        props
    )
    tw:Play()
    return tw
end

local function icon(id)
    return "rbxassetid://" .. tostring(id)
end

local ICONS = {
    crosshair = 10709818534,
    eye = 10723346959,
    move = 10734900011,
    settings = 10734950309,
    sliders = 10734963400,
    scan = 10734942565,
    activity = 10709752035,
    users = 10747373426,
    user = 10747373176,
    zap = 10734975486,
    palette = 10734910430,
    pointer = 10734898476,
    box = 10709782497,
    glow = 8992230677,
}

local RAINBOW = ColorSequence.new({
    ColorSequenceKeypoint.new(0.00, RGB(255, 0, 0)),
    ColorSequenceKeypoint.new(0.17, RGB(255, 255, 0)),
    ColorSequenceKeypoint.new(0.33, RGB(0, 255, 0)),
    ColorSequenceKeypoint.new(0.50, RGB(0, 255, 255)),
    ColorSequenceKeypoint.new(0.67, RGB(0, 0, 255)),
    ColorSequenceKeypoint.new(0.83, RGB(255, 0, 255)),
    ColorSequenceKeypoint.new(1.00, RGB(255, 0, 0)),
})

local function bindName(b)
    if b == Enum.UserInputType.MouseButton2 then return "RMB" end
    if b == Enum.UserInputType.MouseButton3 then return "MMB" end
    local name = b.Name
    name = (name:gsub("^Left(%u)", "L%1"))
    name = (name:gsub("^Right(%u)", "R%1"))
    name = (name:gsub("Control", "Ctrl"))
    return name
end

local function bindMatches(b, input)
    if typeof(b) ~= "EnumItem" then return false end
    if b.EnumType == Enum.KeyCode then
        return input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == b
    end
    return input.UserInputType == b
end

local function isPress(input)
    return input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
end

local function isMove(input)
    return input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch
end

local function toHex(c)
    return string.format("#%02X%02X%02X",
        math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

-- Drag helper: works with mouse and touch.
-- threshold: pixels to move before dragging starts (0 = immediately)
-- onTap: called when released without having dragged
-- clamp: function(offsetX, offsetY) -> offsetX, offsetY
local function makeDraggable(handle, target, threshold, onTap, clamp)
    local dragging = false
    local moved = false
    local startInput, startPos

    handle.InputBegan:Connect(function(input)
        if isPress(input) then
            dragging = true
            moved = false
            startInput = input.Position
            startPos = target.Position

            local conn
            conn = input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    if dragging and not moved and onTap then
                        onTap()
                    end
                    dragging = false
                    if conn then conn:Disconnect() end
                end
            end)
        end
    end)

    connect(UserInputService.InputChanged, function(input)
        if dragging and isMove(input) then
            local delta = input.Position - startInput
            if not moved and delta.Magnitude >= threshold then
                moved = true
            end
            if moved then
                local ox = startPos.X.Offset + delta.X
                local oy = startPos.Y.Offset + delta.Y
                if clamp then
                    ox, oy = clamp(ox, oy)
                end
                target.Position = UDim2.new(startPos.X.Scale, ox, startPos.Y.Scale, oy)
            end
        end
    end)
end

local function clampToScreen(size)
    return function(ox, oy)
        local vp = getViewport()
        return math.clamp(ox, 0, math.max(vp.X - size, 0)),
            math.clamp(oy, 0, math.max(vp.Y - size, 0))
    end
end

------------------------------------------------------------
-- GUI roots
------------------------------------------------------------
local screenGui = new("ScreenGui", {
    Name = GUI_NAME,
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 1000,
})

local espGui = new("ScreenGui", {
    Name = ESP_GUI_NAME,
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 1,
})

-- small message at the bottom of the screen
local toastFrame = new("Frame", {
    AnchorPoint = Vector2.new(0.5, 1),
    Position = UDim2.new(0.5, 0, 1, -24),
    Size = UDim2.fromOffset(280, 30),
    BackgroundColor3 = C.Surface,
    BorderSizePixel = 0,
    Visible = false,
    ZIndex = 100,
}, { corner(6) })
stroke(toastFrame, C.Border)
local toastLabel = label({
    Size = UDim2.new(1, -16, 1, 0),
    Position = UDim2.fromOffset(8, 0),
    TextSize = 12,
    TextColor3 = C.TextDim,
    TextXAlignment = Enum.TextXAlignment.Center,
    TextTruncate = Enum.TextTruncate.AtEnd,
    ZIndex = 101,
})
toastLabel.Parent = toastFrame
toastFrame.Parent = screenGui

local toastToken = 0
local function toast(text)
    toastToken = toastToken + 1
    local mine = toastToken
    toastLabel.Text = text
    toastFrame.Visible = true
    task.delay(2.6, function()
        if mine == toastToken then
            toastFrame.Visible = false
        end
    end)
end

------------------------------------------------------------
-- Main window (compact, portrait, vertical tab rail on the left)
------------------------------------------------------------
local WIN_W, WIN_H = 340, 480
local SIDEBAR_W = 58
local HEADER_H = 38

local main = new("Frame", {
    Name = "Main",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0.5, 0, 0.5, 0),
    Size = UDim2.fromOffset(WIN_W, WIN_H),
    BackgroundColor3 = C.Background,
    BorderSizePixel = 0,
    Active = true,
}, { corner(8) })
local mainScale = new("UIScale", { Scale = 1 })
mainScale.Parent = main
main.Parent = screenGui

-- outer border is drawn on top of everything so the rounded edge stays clean
local frameBorder = new("Frame", {
    Size = UDim2.new(1, 0, 1, 0),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ZIndex = 60,
}, { corner(8) })
stroke(frameBorder, C.Border)
frameBorder.Parent = main

-- sidebar -------------------------------------------------
local sidebar = new("Frame", {
    Name = "Sidebar",
    Size = UDim2.new(0, SIDEBAR_W, 1, 0),
    BackgroundColor3 = C.Surface,
    BorderSizePixel = 0,
}, { corner(8) })
sidebar.Parent = main

local sidebarFill = new("Frame", {
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, 0, 0, 0),
    Size = UDim2.new(0, 10, 1, 0),
    BackgroundColor3 = C.Surface,
    BorderSizePixel = 0,
})
sidebarFill.Parent = sidebar

local sidebarLine = new("Frame", {
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, 0, 0, 0),
    Size = UDim2.new(0, 1, 1, 0),
    BackgroundColor3 = C.Border,
    BorderSizePixel = 0,
    ZIndex = 2,
})
sidebarLine.Parent = sidebar

-- logo (also a drag handle)
local logo = new("Frame", {
    Name = "Logo",
    Size = UDim2.new(1, 0, 0, 58),
    BackgroundTransparency = 1,
    Active = true,
})
logo.Parent = sidebar

local logoGlow = new("ImageLabel", {
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0.5, 0, 0.5, 2),
    Size = UDim2.fromOffset(54, 54),
    BackgroundTransparency = 1,
    Image = icon(ICONS.glow),
    ImageTransparency = 0.82,
})
bindAccent(logoGlow, "ImageColor3", "Accent")
logoGlow.Parent = logo

local logoRing = new("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0.5, 0, 0.5, 2),
    Size = UDim2.fromOffset(26, 26),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
}, { cornerFull() })
stroke(logoRing, C.TextMute, 1, 0.45)
logoRing.Parent = logo

local logoPlanet = new("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0.5, 0, 0.5, 2),
    Size = UDim2.fromOffset(12, 12),
    BackgroundColor3 = WHITE,
    BorderSizePixel = 0,
}, { cornerFull() })
do
    local g = new("UIGradient", { Rotation = 90 })
    bindAccent(g, "Color", "Gradient")
    g.Parent = logoPlanet
end
logoPlanet.Parent = logo

local logoMoon = new("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0.5, 9, 0.5, -7),
    Size = UDim2.fromOffset(5, 5),
    BackgroundColor3 = WHITE,
    BorderSizePixel = 0,
}, { cornerFull() })
logoMoon.Parent = logo

local tabList = new("Frame", {
    Name = "Tabs",
    Position = UDim2.fromOffset(0, 58),
    Size = UDim2.new(1, 0, 1, -58),
    BackgroundTransparency = 1,
}, {
    new("UIListLayout", {
        Padding = UDim.new(0, 4),
        SortOrder = Enum.SortOrder.LayoutOrder,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
    }),
})
tabList.Parent = sidebar

-- header --------------------------------------------------
local header = new("Frame", {
    Name = "Header",
    Position = UDim2.fromOffset(SIDEBAR_W, 0),
    Size = UDim2.new(1, -SIDEBAR_W, 0, HEADER_H),
    BackgroundTransparency = 1,
    Active = true,
})
header.Parent = main

local titleLabel = label({
    Position = UDim2.fromOffset(14, 0),
    Size = UDim2.new(1, -50, 1, 0),
    TextSize = 14,
    RichText = true,
    Text = "Orbit",
})
titleLabel.Parent = header

local function setTitle(pageName)
    titleLabel.Text = 'Orbit <font color="#767A88">/  ' .. pageName .. "</font>"
end

local headerLine = new("Frame", {
    AnchorPoint = Vector2.new(0, 1),
    Position = UDim2.new(0, 0, 1, 0),
    Size = UDim2.new(1, 0, 0, 1),
    BackgroundColor3 = C.Border,
    BorderSizePixel = 0,
})
headerLine.Parent = header

local closeBtn = new("TextButton", {
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -8, 0.5, 0),
    Size = UDim2.fromOffset(24, 24),
    BackgroundColor3 = C.Hover,
    BackgroundTransparency = 1,
    Text = "",
    AutoButtonColor = false,
    BorderSizePixel = 0,
}, { corner(5) })
for _, rot in ipairs({ 45, -45 }) do
    local bar = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.fromOffset(11, 2),
        Rotation = rot,
        BackgroundColor3 = C.TextDim,
        BorderSizePixel = 0,
    }, { cornerFull() })
    bar.Parent = closeBtn
end
closeBtn.MouseEnter:Connect(function() tween(closeBtn, { BackgroundTransparency = 0 }, 0.1) end)
closeBtn.MouseLeave:Connect(function() tween(closeBtn, { BackgroundTransparency = 1 }, 0.1) end)
closeBtn.Parent = header

-- content (holds one scrolling page per tab) ----------------
local content = new("Frame", {
    Name = "Content",
    Position = UDim2.fromOffset(SIDEBAR_W, HEADER_H),
    Size = UDim2.new(1, -SIDEBAR_W, 1, -HEADER_H),
    BackgroundTransparency = 1,
}, {
    new("UIPadding", {
        PaddingTop = UDim.new(0, 8),
        PaddingLeft = UDim.new(0, 8),
        PaddingRight = UDim.new(0, 4),
        PaddingBottom = UDim.new(0, 8),
    }),
})
content.Parent = main

local function layoutMain()
    local vp = getViewport()
    local w = math.clamp(math.floor(vp.X * 0.94), 250, WIN_W)
    local h = math.clamp(math.floor(vp.Y * 0.88), 220, WIN_H)
    main.Size = UDim2.fromOffset(w, h)
end
layoutMain()

local function clampMain(ox, oy)
    local vp = getViewport()
    local hx = vp.X / 2 - 60
    local hy = vp.Y / 2 - 30
    return math.clamp(ox, -hx, hx), math.clamp(oy, -hy, hy)
end

makeDraggable(header, main, 0, nil, clampMain)
makeDraggable(logo, main, 0, nil, clampMain)

local menuOpen = true
local menuToken = 0
local panicHidden = false -- set by the panic key, cleared when the menu is opened again
local onMenuShown         -- assigned later (restores the floating icon / overlays)

local function setMenuVisible(v)
    menuOpen = v
    menuToken = menuToken + 1
    local mine = menuToken
    if v then
        panicHidden = false
        if onMenuShown then onMenuShown() end
        mainScale.Scale = 0.94
        main.Visible = true
        tween(mainScale, { Scale = 1 }, 0.16)
    else
        tween(mainScale, { Scale = 0.95 }, 0.1)
        task.delay(0.1, function()
            if mine == menuToken then
                main.Visible = false
            end
        end)
    end
end

closeBtn.Activated:Connect(function()
    setMenuVisible(false)
    if not Config.FloatingIcon then
        if isMobile then
            if floatToggle then floatToggle:Set(true) end
            toast("Floating icon restored so you can reopen the menu")
        else
            toast("Press " .. bindName(Config.MenuKey) .. " to reopen the menu")
        end
    end
end)

------------------------------------------------------------
-- Scroll lock (so sliders don't scroll the page on touch)
------------------------------------------------------------
local pages = {}

local function setScrollLock(locked)
    for _, page in pairs(pages) do
        page.ScrollingEnabled = not locked
    end
end

------------------------------------------------------------
-- Color picker popup (shared by every color swatch)
------------------------------------------------------------
local PICK_W = 200
local SV_H = 112

local picker = { Target = nil, H = 0, S = 0, V = 1, Open = false }

local pickerOverlay = new("TextButton", {
    Size = UDim2.new(1, 0, 1, 0),
    BackgroundColor3 = Color3.new(0, 0, 0),
    BackgroundTransparency = 0.45,
    Text = "",
    AutoButtonColor = false,
    BorderSizePixel = 0,
    Visible = false,
    ZIndex = 40,
}, { corner(8) })
pickerOverlay.Parent = main

local pickerFrame = new("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0.5, 0, 0.5, 0),
    Size = UDim2.fromOffset(PICK_W, 208),
    BackgroundColor3 = C.Surface,
    BorderSizePixel = 0,
    Active = true,
    Visible = false,
    ZIndex = 41,
}, { corner(6) })
stroke(pickerFrame, C.Border)
pickerFrame.Parent = main

label({ Text = "Color", Position = UDim2.fromOffset(12, 8), Size = UDim2.new(0.5, 0, 0, 16) }).Parent = pickerFrame

local pickerHex = label({
    Text = "#FFFFFF",
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -12, 0, 8),
    Size = UDim2.new(0.5, -12, 0, 16),
    TextSize = 12,
    TextColor3 = C.TextDim,
    TextXAlignment = Enum.TextXAlignment.Right,
})
pickerHex.Parent = pickerFrame

local svBox = new("Frame", {
    Position = UDim2.fromOffset(12, 30),
    Size = UDim2.new(1, -24, 0, SV_H),
    BackgroundColor3 = Color3.fromHSV(0, 1, 1),
    BorderSizePixel = 0,
}, { corner(5) })
stroke(svBox, C.Border)
svBox.Parent = pickerFrame

new("Frame", {
    Size = UDim2.new(1, 0, 1, 0),
    BackgroundColor3 = WHITE,
    BorderSizePixel = 0,
}, {
    corner(5),
    new("UIGradient", { Transparency = NumberSequence.new(0, 1) }),
}).Parent = svBox

new("Frame", {
    Size = UDim2.new(1, 0, 1, 0),
    BackgroundColor3 = Color3.new(0, 0, 0),
    BorderSizePixel = 0,
}, {
    corner(5),
    new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(1, 0) }),
}).Parent = svBox

local svHit = new("TextButton", {
    Size = UDim2.new(1, 0, 1, 0),
    BackgroundTransparency = 1,
    Text = "",
    AutoButtonColor = false,
    ZIndex = 3,
})
svHit.Parent = svBox

local svCursor = new("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5),
    Size = UDim2.fromOffset(11, 11),
    BackgroundColor3 = WHITE,
    BorderSizePixel = 0,
    ZIndex = 4,
}, { cornerFull() })
stroke(svCursor, WHITE, 2)
svCursor.Parent = svBox

local hueBar = new("Frame", {
    Position = UDim2.fromOffset(12, 30 + SV_H + 10),
    Size = UDim2.new(1, -24, 0, 12),
    BackgroundColor3 = WHITE,
    BorderSizePixel = 0,
}, {
    corner(6),
    new("UIGradient", { Color = RAINBOW }),
})
hueBar.Parent = pickerFrame

local hueHit = new("TextButton", {
    Size = UDim2.new(1, 0, 1, 0),
    BackgroundTransparency = 1,
    Text = "",
    AutoButtonColor = false,
    ZIndex = 3,
})
hueHit.Parent = hueBar

local hueCursor = new("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0, 0, 0.5, 0),
    Size = UDim2.fromOffset(6, 18),
    BackgroundColor3 = WHITE,
    BorderSizePixel = 0,
    ZIndex = 4,
}, { corner(3) })
stroke(hueCursor, C.Background, 1, 0.3)
hueCursor.Parent = hueBar

local doneBtn = new("TextButton", {
    Position = UDim2.fromOffset(12, 30 + SV_H + 10 + 12 + 14),
    Size = UDim2.new(1, -24, 0, 24),
    BackgroundColor3 = WHITE,
    Text = "",
    AutoButtonColor = false,
    BorderSizePixel = 0,
}, { corner(5) })
do
    -- the gradient tints text too, so the label is a separate child
    local g = new("UIGradient", { Rotation = -90 })
    bindAccent(g, "Color", "Gradient")
    g.Parent = doneBtn
end
label({
    Text = "Done",
    Size = UDim2.new(1, 0, 1, 0),
    TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Center,
}).Parent = doneBtn
doneBtn.Parent = pickerFrame

local function updatePickerVisuals(applyToTarget)
    local color = Color3.fromHSV(picker.H, picker.S, picker.V)
    svBox.BackgroundColor3 = Color3.fromHSV(picker.H, 1, 1)
    svCursor.Position = UDim2.new(picker.S, 0, 1 - picker.V, 0)
    svCursor.BackgroundColor3 = color
    hueCursor.Position = UDim2.new(picker.H, 0, 0.5, 0)
    hueCursor.BackgroundColor3 = Color3.fromHSV(picker.H, 1, 1)
    pickerHex.Text = toHex(color)
    if applyToTarget and picker.Target then
        picker.Target:Set(color)
    end
end

local function closePicker()
    picker.Open = false
    picker.Target = nil
    pickerFrame.Visible = false
    pickerOverlay.Visible = false
end

local function openPicker(target)
    picker.Target = target
    picker.Open = true
    picker.H, picker.S, picker.V = target.Value:ToHSV()
    pickerOverlay.Visible = true
    pickerFrame.Visible = true
    updatePickerVisuals(false)
end

pickerOverlay.Activated:Connect(closePicker)
doneBtn.Activated:Connect(closePicker)

local draggingSV = false
local draggingHue = false

local function svFromPos(pos)
    local w = math.max(svBox.AbsoluteSize.X, 1)
    local h = math.max(svBox.AbsoluteSize.Y, 1)
    picker.S = math.clamp((pos.X - svBox.AbsolutePosition.X) / w, 0, 1)
    picker.V = 1 - math.clamp((pos.Y - svBox.AbsolutePosition.Y) / h, 0, 1)
    updatePickerVisuals(true)
end

local function hueFromPos(pos)
    picker.H = math.clamp((pos.X - hueBar.AbsolutePosition.X) / math.max(hueBar.AbsoluteSize.X, 1), 0, 1)
    updatePickerVisuals(true)
end

svHit.InputBegan:Connect(function(input)
    if isPress(input) then
        draggingSV = true
        svFromPos(input.Position)
    end
end)

hueHit.InputBegan:Connect(function(input)
    if isPress(input) then
        draggingHue = true
        hueFromPos(input.Position)
    end
end)

connect(UserInputService.InputChanged, function(input)
    if isMove(input) then
        if draggingSV then
            svFromPos(input.Position)
        elseif draggingHue then
            hueFromPos(input.Position)
        end
    end
end)

connect(UserInputService.InputEnded, function(input)
    if isPress(input) then
        draggingSV = false
        draggingHue = false
    end
end)

------------------------------------------------------------
-- Widgets
------------------------------------------------------------
local function newPage()
    local page = new("ScrollingFrame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 1, 0),
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollBarThickness = 2,
        ScrollBarImageTransparency = 0.1,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ElasticBehavior = Enum.ElasticBehavior.Never,
        Visible = false,
    }, {
        new("UIListLayout", {
            Padding = UDim.new(0, 8),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }),
        new("UIPadding", {
            PaddingRight = UDim.new(0, 6),
            PaddingBottom = UDim.new(0, 2),
        }),
    })
    bindAccent(page, "ScrollBarImageColor3", "Accent")
    page.Parent = content
    return page
end

local function nextOrder(sec)
    sec.n = sec.n + 1
    return sec.n
end

local function newSection(page, name, iconId)
    local card = new("Frame", {
        LayoutOrder = #page:GetChildren(),
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = C.Surface,
        BorderSizePixel = 0,
    }, {
        corner(6),
        new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }),
    })
    stroke(card, C.SectionBorder)
    card.Parent = page

    local head = new("Frame", {
        LayoutOrder = 1,
        Size = UDim2.new(1, 0, 0, 30),
        BackgroundTransparency = 1,
    })
    head.Parent = card

    local ic = new("ImageLabel", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 10, 0.5, 0),
        Size = UDim2.fromOffset(14, 14),
        BackgroundTransparency = 1,
        Image = icon(iconId),
    })
    bindAccent(ic, "ImageColor3", "Accent")
    ic.Parent = head

    label({
        Text = name,
        Position = UDim2.fromOffset(30, 0),
        Size = UDim2.new(1, -40, 1, 0),
    }).Parent = head

    new("Frame", {
        LayoutOrder = 2,
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = C.SectionBorder,
        BorderSizePixel = 0,
    }).Parent = card

    local body = new("Frame", {
        LayoutOrder = 3,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
    }, {
        new("UIListLayout", {
            Padding = UDim.new(0, 6),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }),
        new("UIPadding", {
            PaddingTop = UDim.new(0, 8),
            PaddingLeft = UDim.new(0, 10),
            PaddingRight = UDim.new(0, 10),
            PaddingBottom = UDim.new(0, 8),
        }),
    })
    body.Parent = card

    return { Body = body, n = 0 }
end

-- A row with a label on the left and a right-aligned container for controls.
-- asButton: the whole row is tappable (used by toggles).
local function makeRow(sec, text, asButton)
    local props = {
        LayoutOrder = nextOrder(sec),
        Size = UDim2.new(1, 0, 0, 26),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
    }
    local row
    if asButton then
        props.Text = ""
        props.AutoButtonColor = false
        row = new("TextButton", props)
    else
        row = new("Frame", props)
    end
    row.Parent = sec.Body

    local lbl = label({
        Text = text,
        Size = UDim2.new(1, -50, 1, 0),
        TextTransparency = 0.2,
        TextTruncate = Enum.TextTruncate.AtEnd,
    })
    lbl.Parent = row

    local right = new("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
    }, {
        new("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            HorizontalAlignment = Enum.HorizontalAlignment.Right,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            Padding = UDim.new(0, 8),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }),
    })
    right.Parent = row

    local function relabel()
        lbl.Size = UDim2.new(1, -(right.AbsoluteSize.X + 8), 1, 0)
    end
    right:GetPropertyChangedSignal("AbsoluteSize"):Connect(relabel)
    relabel()

    return { Row = row, Label = lbl, Right = right }
end

-- isInterface = true keeps the toggle out of the panic key's "turn everything off" list
local function addToggle(sec, text, default, callback, isInterface)
    local r = makeRow(sec, text, true)

    local switch = new("Frame", {
        LayoutOrder = 100,
        Size = UDim2.fromOffset(28, 14),
        BackgroundColor3 = C.SurfaceAlt,
        BorderSizePixel = 0,
    }, { cornerFull() })
    stroke(switch, C.Border)
    switch.Parent = r.Right

    local overlay = new("Frame", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = WHITE,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
    }, { cornerFull() })
    do
        local g = new("UIGradient", { Rotation = -90 })
        bindAccent(g, "Color", "Gradient")
        g.Parent = overlay
    end
    overlay.Parent = switch

    local knob = new("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 3, 0.5, 0),
        Size = UDim2.fromOffset(8, 8),
        BackgroundColor3 = C.TextDim,
        BorderSizePixel = 0,
        ZIndex = 2,
    }, { cornerFull() })
    knob.Parent = switch

    local obj = { Value = default and true or false, Right = r.Right }
    if not isInterface then table.insert(allToggles, obj) end

    local function paint(animate)
        local on = obj.Value
        local goalPos = on and UDim2.new(0, 17, 0.5, 0) or UDim2.new(0, 3, 0.5, 0)
        local goalColor = on and C.Text or C.TextDim
        if animate then
            tween(overlay, { BackgroundTransparency = on and 0 or 1 }, 0.12)
            tween(knob, { Position = goalPos, BackgroundColor3 = goalColor }, 0.12)
        else
            overlay.BackgroundTransparency = on and 0 or 1
            knob.Position = goalPos
            knob.BackgroundColor3 = goalColor
        end
    end

    function obj:Set(v, silent)
        self.Value = v and true or false
        paint(true)
        if not silent and callback then
            callback(self.Value)
        end
    end

    r.Row.Activated:Connect(function()
        obj:Set(not obj.Value)
    end)
    r.Row.MouseEnter:Connect(function() tween(r.Label, { TextTransparency = 0 }, 0.1) end)
    r.Row.MouseLeave:Connect(function() tween(r.Label, { TextTransparency = 0.2 }, 0.1) end)

    paint(false)
    return obj
end

local function addKeybind(right, default, onChanged)
    local btn = new("TextButton", {
        LayoutOrder = 1,
        AutomaticSize = Enum.AutomaticSize.X,
        Size = UDim2.fromOffset(0, 18),
        BackgroundColor3 = C.SurfaceAlt,
        FontFace = FONT,
        TextSize = 11,
        TextColor3 = C.TextDim,
        Text = "",
        AutoButtonColor = false,
        BorderSizePixel = 0,
    }, {
        corner(4),
        new("UIPadding", { PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7) }),
        new("UISizeConstraint", { MinSize = Vector2.new(36, 0) }),
    })
    stroke(btn, C.Border)
    btn.Parent = right

    local obj = { Value = default }

    local function show()
        btn.Text = bindName(obj.Value)
        btn.TextColor3 = C.TextDim
    end
    show()

    btn.Activated:Connect(function()
        local old = listening
        listening = nil
        if old then
            old.cancel()
            if old.button == btn then return end -- tapping again cancels
        end

        btn.Text = "..."
        btn.TextColor3 = state.accent
        listening = {
            button = btn,
            set = function(v)
                obj.Value = v
                show()
                onChanged(v)
            end,
            cancel = show,
        }
    end)

    return obj
end

local function addKeybindRow(sec, text, default, onChanged)
    local r = makeRow(sec, text, false)
    return addKeybind(r.Right, default, onChanged)
end

local function addColorSwatch(right, default, onChanged)
    local obj = { Value = default }

    local btn = new("TextButton", {
        LayoutOrder = 2,
        Size = UDim2.fromOffset(22, 14),
        Text = "",
        AutoButtonColor = false,
        BorderSizePixel = 0,
        BackgroundColor3 = default,
    }, { corner(4) })
    stroke(btn, C.Border)
    btn.Parent = right

    obj.Button = btn

    function obj:Set(c)
        self.Value = c
        btn.BackgroundColor3 = c
        onChanged(c)
    end

    btn.Activated:Connect(function()
        openPicker(obj)
    end)

    return obj
end

local function addSlider(sec, cfg)
    -- cfg: Name, Min, Max, Value, Step, Suffix, Callback
    local min, max = cfg.Min, cfg.Max
    local step = cfg.Step or 1
    local suffix = cfg.Suffix or ""

    local row = new("Frame", {
        LayoutOrder = nextOrder(sec),
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 40),
    })
    row.Parent = sec.Body

    label({
        Text = cfg.Name,
        Size = UDim2.new(1, -70, 0, 16),
        TextTransparency = 0.2,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }).Parent = row

    local valueLabel = label({
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, 0, 0, 0),
        Size = UDim2.fromOffset(70, 16),
        TextSize = 12,
        TextColor3 = C.TextDim,
        TextXAlignment = Enum.TextXAlignment.Right,
    })
    valueLabel.Parent = row

    local holder = new("TextButton", {
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        Position = UDim2.new(0, 0, 0, 18),
        Size = UDim2.new(1, 0, 0, 22),
    })
    holder.Parent = row

    local track = new("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.new(1, 0, 0, 6),
        BackgroundColor3 = C.SurfaceAlt,
        BorderSizePixel = 0,
    }, { cornerFull() })
    stroke(track, C.Border)
    track.Parent = holder

    local fill = new("Frame", {
        Size = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = WHITE,
        BorderSizePixel = 0,
    }, { cornerFull() })
    do
        local g = new("UIGradient", { Rotation = 0 })
        bindAccent(g, "Color", "Gradient")
        g.Parent = fill
    end
    fill.Parent = track

    local knob = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.fromOffset(11, 11),
        BackgroundColor3 = WHITE,
        BorderSizePixel = 0,
        ZIndex = 2,
    }, { cornerFull() })
    knob.Parent = track

    local obj = { Value = cfg.Value }

    local function fmt(v)
        return tostring(math.floor(v * 100 + 0.5) / 100) .. suffix
    end

    local function render()
        local rel = (obj.Value - min) / math.max(max - min, 1e-6)
        rel = math.clamp(rel, 0, 1)
        fill.Size = UDim2.new(rel, 0, 1, 0)
        knob.Position = UDim2.new(rel, 0, 0.5, 0)
        valueLabel.Text = fmt(obj.Value)
    end

    local function setValue(v, silent)
        v = math.clamp(v, min, max)
        if v ~= obj.Value then
            obj.Value = v
            render()
            if not silent and cfg.Callback then cfg.Callback(v) end
        end
    end

    local function setFromX(x)
        local rel = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
        local raw = min + rel * (max - min)
        setValue(min + math.floor((raw - min) / step + 0.5) * step)
    end

    function obj:Set(v, silent)
        setValue(v, silent)
    end

    local dragging = false

    holder.InputBegan:Connect(function(input)
        if isPress(input) then
            dragging = true
            setScrollLock(true)
            setFromX(input.Position.X)
        end
    end)

    connect(UserInputService.InputChanged, function(input)
        if dragging and isMove(input) then
            setFromX(input.Position.X)
        end
    end)

    connect(UserInputService.InputEnded, function(input)
        if dragging and isPress(input) then
            dragging = false
            setScrollLock(false)
        end
    end)

    render()
    return obj
end

-- Text box row: label on the left, input on the right. onChanged(text) fires when focus is lost.
local function addTextBox(sec, name, default, placeholder, onChanged)
    local r = makeRow(sec, name, false)

    local wrap = new("Frame", {
        LayoutOrder = 1,
        Size = UDim2.fromOffset(130, 20),
        BackgroundColor3 = C.SurfaceAlt,
        BorderSizePixel = 0,
    }, { corner(4) })
    stroke(wrap, C.Border)
    wrap.Parent = r.Right

    local box = new("TextBox", {
        Size = UDim2.new(1, -12, 1, 0),
        Position = UDim2.fromOffset(6, 0),
        BackgroundTransparency = 1,
        FontFace = FONT,
        TextSize = 11,
        TextColor3 = C.Text,
        PlaceholderText = placeholder or "",
        PlaceholderColor3 = C.TextMute,
        Text = default or "",
        ClearTextOnFocus = false,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
    })
    box.Parent = wrap

    -- keep names short
    box:GetPropertyChangedSignal("Text"):Connect(function()
        if #box.Text > 24 then
            box.Text = box.Text:sub(1, 24)
        end
    end)

    local obj = { Box = box }
    function obj:Get() return box.Text end
    function obj:Set(t) box.Text = t or "" end

    box.FocusLost:Connect(function()
        if onChanged then onChanged(box.Text) end
    end)

    return obj
end

local function addButton(sec, text, callback)
    local btn = new("TextButton", {
        LayoutOrder = nextOrder(sec),
        Size = UDim2.new(1, 0, 0, 26),
        BackgroundColor3 = C.SurfaceAlt,
        FontFace = FONT,
        Text = text,
        TextSize = 13,
        TextColor3 = C.TextDim,
        AutoButtonColor = false,
        BorderSizePixel = 0,
    }, { corner(5) })
    stroke(btn, C.Border)
    btn.Parent = sec.Body

    local hoverFill = new("Frame", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = WHITE,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
    }, { corner(5) })
    do
        local g = new("UIGradient", { Rotation = -90 })
        bindAccent(g, "Color", "Gradient")
        g.Parent = hoverFill
    end
    hoverFill.Parent = btn

    btn.MouseEnter:Connect(function()
        tween(hoverFill, { BackgroundTransparency = 0.8 }, 0.1)
        tween(btn, { TextColor3 = C.Text }, 0.1)
    end)
    btn.MouseLeave:Connect(function()
        tween(hoverFill, { BackgroundTransparency = 1 }, 0.1)
        tween(btn, { TextColor3 = C.TextDim }, 0.1)
    end)
    btn.InputBegan:Connect(function(input)
        if isPress(input) then tween(hoverFill, { BackgroundTransparency = 0.55 }, 0.06) end
    end)
    btn.InputEnded:Connect(function(input)
        if isPress(input) then tween(hoverFill, { BackgroundTransparency = 0.8 }, 0.1) end
    end)
    btn.Activated:Connect(callback)
    return btn
end

-- Dropdown: single-select (Theme) or multi-select with search (player lists)
-- cfg: Name, Multi, GetOptions() -> { {Key=, Text=, Search=, Swatch=}, ... },
--      Selected (multi: table key->true), Value (single: key),
--      Callback(key) (single), OnChange() (multi)
local function addDropdown(sec, cfg)
    local ROW_H = 22
    local MAX_ROWS = 6
    local multi = cfg.Multi and true or false
    local searchH = multi and 26 or 0

    local container = new("Frame", {
        LayoutOrder = nextOrder(sec),
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
    }, {
        new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
    })
    container.Parent = sec.Body

    local head = new("TextButton", {
        LayoutOrder = 1,
        Size = UDim2.new(1, 0, 0, 26),
        BackgroundColor3 = C.SurfaceAlt,
        Text = "",
        AutoButtonColor = false,
        BorderSizePixel = 0,
    }, { corner(5) })
    stroke(head, C.Border)
    head.Parent = container

    label({
        Text = cfg.Name,
        Position = UDim2.fromOffset(8, 0),
        Size = UDim2.new(0.45, -8, 1, 0),
        TextTransparency = 0.2,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }).Parent = head

    local valueLabel = label({
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -26, 0, 0),
        Size = UDim2.new(0.55, -30, 1, 0),
        TextSize = 12,
        TextColor3 = C.TextDim,
        TextXAlignment = Enum.TextXAlignment.Right,
        TextTruncate = Enum.TextTruncate.AtEnd,
    })
    valueLabel.Parent = head

    -- chevron drawn with two bars so it needs no image asset
    local chev = new("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -9, 0.5, 0),
        Size = UDim2.fromOffset(10, 10),
        BackgroundTransparency = 1,
    })
    chev.Parent = head
    for _, d in ipairs({ { 2.9, 45 }, { 7.1, -45 } }) do
        new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0, d[1], 0, 4.5),
            Size = UDim2.fromOffset(6, 1.5),
            Rotation = d[2],
            BackgroundColor3 = C.TextDim,
            BorderSizePixel = 0,
        }).Parent = chev
    end

    local wrap = new("Frame", {
        LayoutOrder = 2,
        Size = UDim2.new(1, 0, 0, 0),
        BackgroundColor3 = C.Background,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Visible = false,
    }, { corner(5) })
    stroke(wrap, C.Border)
    wrap.Parent = container

    local searchBox, clearBtn
    if multi then
        local sbWrap = new("Frame", {
            Position = UDim2.fromOffset(4, 4),
            Size = UDim2.new(1, -54, 0, 22),
            BackgroundColor3 = C.SurfaceAlt,
            BorderSizePixel = 0,
        }, { corner(4) })
        stroke(sbWrap, C.Border)
        sbWrap.Parent = wrap

        searchBox = new("TextBox", {
            Size = UDim2.new(1, -16, 1, 0),
            Position = UDim2.fromOffset(8, 0),
            BackgroundTransparency = 1,
            FontFace = FONT,
            TextSize = 12,
            TextColor3 = C.Text,
            PlaceholderText = "Search players",
            PlaceholderColor3 = C.TextMute,
            Text = "",
            ClearTextOnFocus = false,
            TextXAlignment = Enum.TextXAlignment.Left,
        })
        searchBox.Parent = sbWrap

        clearBtn = new("TextButton", {
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, -4, 0, 4),
            Size = UDim2.fromOffset(44, 22),
            BackgroundColor3 = C.SurfaceAlt,
            FontFace = FONT,
            Text = "Clear",
            TextSize = 12,
            TextColor3 = C.TextDim,
            AutoButtonColor = false,
            BorderSizePixel = 0,
        }, { corner(4) })
        stroke(clearBtn, C.Border)
        clearBtn.Parent = wrap
    end

    local list = new("ScrollingFrame", {
        Position = UDim2.fromOffset(4, 4 + searchH),
        Size = UDim2.new(1, -8, 0, ROW_H),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollBarThickness = 2,
        ScrollBarImageTransparency = 0.1,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ElasticBehavior = Enum.ElasticBehavior.Never,
    }, {
        new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }),
        new("UIPadding", { PaddingRight = UDim.new(0, 4) }),
    })
    bindAccent(list, "ScrollBarImageColor3", "Accent")
    list.Parent = wrap

    local obj = { Value = cfg.Value }
    local open = false
    local shown = {} -- options currently rendered
    local allOptions = {}

    local function listHeight(count)
        local rows = math.max(math.min(count, MAX_ROWS), 1)
        return rows * ROW_H + (rows - 1) * 2
    end

    local function targetHeight()
        return 4 + searchH + listHeight(#shown) + 4
    end

    local function headerText()
        if multi then
            local n, first = 0, nil
            for _, o in ipairs(allOptions) do
                if cfg.Selected[o.Key] then
                    n = n + 1
                    first = first or o.Text
                end
            end
            if n == 0 then return "None" end
            if n == 1 then return first end
            return tostring(n) .. " selected"
        end
        for _, o in ipairs(allOptions) do
            if o.Key == obj.Value then return o.Text end
        end
        if obj.Value == nil then return cfg.Placeholder or "None" end
        return tostring(obj.Value)
    end

    local function updateHeader()
        valueLabel.Text = headerText()
    end

    local function resize()
        list.Size = UDim2.new(1, -8, 0, listHeight(#shown))
        if open then
            tween(wrap, { Size = UDim2.new(1, 0, 0, targetHeight()) }, 0.15)
        end
    end

    local function rebuild()
        for _, ch in ipairs(list:GetChildren()) do
            if ch:IsA("GuiObject") then ch:Destroy() end
        end
        pruneRegistry()

        allOptions = cfg.GetOptions()
        local q = searchBox and searchBox.Text:lower() or ""
        shown = {}
        for _, o in ipairs(allOptions) do
            if q == "" or (o.Search or o.Text:lower()):find(q, 1, true) then
                table.insert(shown, o)
            end
        end

        if #shown == 0 then
            label({
                Size = UDim2.new(1, 0, 0, ROW_H),
                Text = (#allOptions == 0) and (cfg.EmptyText or "No players in server") or "No matches",
                TextSize = 12,
                TextColor3 = C.TextMute,
                TextXAlignment = Enum.TextXAlignment.Center,
            }).Parent = list
        end

        for i, o in ipairs(shown) do
            local rowBtn = new("TextButton", {
                LayoutOrder = i,
                Size = UDim2.new(1, 0, 0, ROW_H),
                BackgroundColor3 = C.Hover,
                BackgroundTransparency = 1,
                Text = "",
                AutoButtonColor = false,
                BorderSizePixel = 0,
            }, { corner(4) })
            rowBtn.Parent = list

            local textX = 8
            local box, boxFill, tick
            if multi then
                textX = 28
                box = new("Frame", {
                    AnchorPoint = Vector2.new(0, 0.5),
                    Position = UDim2.new(0, 8, 0.5, 0),
                    Size = UDim2.fromOffset(12, 12),
                    BackgroundColor3 = C.SurfaceAlt,
                    BorderSizePixel = 0,
                }, { corner(3) })
                stroke(box, C.Border)
                box.Parent = rowBtn

                boxFill = new("Frame", {
                    Size = UDim2.new(1, 0, 1, 0),
                    BackgroundColor3 = WHITE,
                    BorderSizePixel = 0,
                }, { corner(3) })
                local g = new("UIGradient", { Rotation = -90 })
                bindAccent(g, "Color", "Gradient")
                g.Parent = boxFill
                boxFill.Parent = box

                tick = new("TextLabel", {
                    Size = UDim2.new(1, 0, 1, 0),
                    BackgroundTransparency = 1,
                    Font = Enum.Font.GothamBold,
                    Text = "✓",
                    TextSize = 10,
                    TextColor3 = WHITE,
                    ZIndex = 3,
                })
                tick.Parent = box
            end

            local txt = label({
                Position = UDim2.fromOffset(textX, 0),
                Size = UDim2.new(1, -(textX + (o.Swatch and 24 or 6)), 1, 0),
                Text = o.Text,
                TextTruncate = Enum.TextTruncate.AtEnd,
            })
            txt.Parent = rowBtn

            if o.Swatch then
                local dot = new("Frame", {
                    AnchorPoint = Vector2.new(1, 0.5),
                    Position = UDim2.new(1, -8, 0.5, 0),
                    Size = UDim2.fromOffset(10, 10),
                    BackgroundColor3 = WHITE,
                    BorderSizePixel = 0,
                }, { cornerFull() })
                if o.Swatch == "rainbow" then
                    new("UIGradient", { Color = RAINBOW }).Parent = dot
                else
                    dot.BackgroundColor3 = o.Swatch
                end
                dot.Parent = rowBtn
            end

            local function paint()
                local on
                if multi then on = cfg.Selected[o.Key] == true else on = (obj.Value == o.Key) end
                txt.TextTransparency = on and 0 or 0.4
                if multi then
                    boxFill.BackgroundTransparency = on and 0 or 1
                    tick.TextTransparency = on and 0 or 1
                end
            end
            paint()

            rowBtn.MouseEnter:Connect(function() tween(rowBtn, { BackgroundTransparency = 0.35 }, 0.08) end)
            rowBtn.MouseLeave:Connect(function() tween(rowBtn, { BackgroundTransparency = 1 }, 0.08) end)

            rowBtn.Activated:Connect(function()
                if multi then
                    if cfg.Selected[o.Key] then
                        cfg.Selected[o.Key] = nil
                    else
                        cfg.Selected[o.Key] = true
                    end
                    paint()
                    updateHeader()
                    if cfg.OnChange then cfg.OnChange() end
                else
                    obj.Value = o.Key
                    updateHeader()
                    if cfg.Callback then cfg.Callback(o.Key) end
                    for _, ch in ipairs(list:GetChildren()) do
                        -- repaint the other rows (selected highlight)
                        if ch:IsA("TextButton") then
                            local t = ch:FindFirstChildOfClass("TextLabel")
                            if t then t.TextTransparency = (ch == rowBtn) and 0 or 0.4 end
                        end
                    end
                end
            end)
        end

        updateHeader()
        resize()
    end

    local function setOpen(v)
        open = v
        if v then
            wrap.Visible = true
            rebuild()
            wrap.Size = UDim2.new(1, 0, 0, 0)
        end
        tween(wrap, { Size = UDim2.new(1, 0, 0, v and targetHeight() or 0) }, 0.15)
        tween(chev, { Rotation = v and 180 or 0 }, 0.15)
        if not v then
            task.delay(0.17, function()
                if not open then wrap.Visible = false end
            end)
        end
    end

    head.Activated:Connect(function()
        setOpen(not open)
    end)
    head.MouseEnter:Connect(function() tween(head, { BackgroundColor3 = C.Hover }, 0.1) end)
    head.MouseLeave:Connect(function() tween(head, { BackgroundColor3 = C.SurfaceAlt }, 0.1) end)

    if searchBox then
        searchBox:GetPropertyChangedSignal("Text"):Connect(rebuild)
        clearBtn.Activated:Connect(function()
            for k in pairs(cfg.Selected) do cfg.Selected[k] = nil end
            rebuild()
            if cfg.OnChange then cfg.OnChange() end
        end)
    end

    function obj:Refresh()
        if open then
            rebuild()
        else
            allOptions = cfg.GetOptions()
            updateHeader()
        end
    end

    allOptions = cfg.GetOptions()
    updateHeader()
    return obj
end

-- player lists (shared by both whitelists) ------------------
local leavingPlayer = nil
local playerDropdowns = {}

local function getPlayerOptions()
    local list = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p ~= leavingPlayer then
            local shownName = p.Name
            if p.DisplayName ~= p.Name then
                shownName = p.DisplayName .. " (@" .. p.Name .. ")"
            end
            table.insert(list, {
                Key = p.UserId,
                Text = shownName,
                Search = (p.DisplayName .. " " .. p.Name):lower(),
                Sort = p.DisplayName:lower(),
            })
        end
    end
    table.sort(list, function(a, b) return a.Sort < b.Sort end)
    return list
end

local function addPlayerDropdown(sec, name, selectedSet)
    local dd = addDropdown(sec, {
        Name = name,
        Multi = true,
        GetOptions = getPlayerOptions,
        Selected = selectedSet,
    })
    table.insert(playerDropdowns, dd)
    return dd
end

local function refreshPlayerDropdowns()
    for _, dd in ipairs(playerDropdowns) do
        dd:Refresh()
    end
end

------------------------------------------------------------
-- Tabs (vertical rail on the left)
------------------------------------------------------------
local tabButtons = {}
local tabDefs = {
    { "Aimbot", ICONS.crosshair, "Aimbot" },
    { "ESP", ICONS.eye, "ESP" },
    { "Movement", ICONS.move, "Move" },
    { "Settings", ICONS.settings, "Settings" },
}

local function refreshTabs()
    for name, t in pairs(tabButtons) do
        local active = (name == state.activeTab)
        t.Button.BackgroundTransparency = active and 0 or 1
        t.Icon.ImageColor3 = active and state.accent or C.TextDim
        t.Icon.ImageTransparency = active and 0 or 0.25
        t.Label.TextColor3 = active and C.Text or C.TextMute
        t.Bar.Visible = active
    end
end
table.insert(refreshers, refreshTabs)

local function setTab(name)
    state.activeTab = name
    closePicker()
    for pageName, page in pairs(pages) do
        page.Visible = (pageName == name)
    end
    setTitle(name)
    refreshTabs()
end

for i, def in ipairs(tabDefs) do
    local name, iconId, short = def[1], def[2], def[3]

    local btn = new("TextButton", {
        LayoutOrder = i,
        Size = UDim2.new(1, -10, 0, 46),
        BackgroundColor3 = C.SurfaceAlt,
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        BorderSizePixel = 0,
    }, { corner(6) })
    btn.Parent = tabList

    local ic = new("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, 8),
        Size = UDim2.fromOffset(18, 18),
        BackgroundTransparency = 1,
        Image = icon(iconId),
    })
    ic.Parent = btn

    local lbl = label({
        Text = short,
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 1, -5),
        Size = UDim2.new(1, 0, 0, 12),
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Center,
    })
    lbl.Parent = btn

    local bar = new("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, -5, 0.5, 0),
        Size = UDim2.fromOffset(2, 22),
        BorderSizePixel = 0,
        Visible = false,
    }, { cornerFull() })
    bindAccent(bar, "BackgroundColor3", "Accent")
    bar.Parent = btn

    tabButtons[name] = { Button = btn, Icon = ic, Label = lbl, Bar = bar }
    pages[name] = newPage()

    btn.Activated:Connect(function()
        setTab(name)
    end)
    btn.MouseEnter:Connect(function()
        if state.activeTab ~= name then
            tween(btn, { BackgroundTransparency = 0.6 }, 0.1)
        end
    end)
    btn.MouseLeave:Connect(function()
        if state.activeTab ~= name then
            tween(btn, { BackgroundTransparency = 1 }, 0.1)
        end
    end)
end

------------------------------------------------------------
-- Floating open/close button (draggable)
------------------------------------------------------------
local FLOAT_SIZE = 44

local floatBtn = new("TextButton", {
    Name = "FloatingToggle",
    Position = UDim2.fromOffset(16, 110),
    Size = UDim2.fromOffset(FLOAT_SIZE, FLOAT_SIZE),
    BackgroundColor3 = C.Surface,
    Text = "",
    AutoButtonColor = false,
    BorderSizePixel = 0,
    ZIndex = 50,
    Visible = Config.FloatingIcon,
}, { cornerFull() })
do
    local s = stroke(floatBtn, C.Border, 1.5)
    bindAccent(s, "Color", "Accent")
end
floatBtn.Parent = screenGui

local floatGlow = new("ImageLabel", {
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0.5, 0, 0.5, 0),
    Size = UDim2.fromOffset(66, 66),
    BackgroundTransparency = 1,
    Image = icon(ICONS.glow),
    ImageTransparency = 0.86,
    ZIndex = 50,
})
bindAccent(floatGlow, "ImageColor3", "Accent")
floatGlow.Parent = floatBtn

local floatRing = new("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0.5, 0, 0.5, 0),
    Size = UDim2.fromOffset(28, 28),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ZIndex = 51,
}, { cornerFull() })
stroke(floatRing, C.TextMute, 1, 0.45)
floatRing.Parent = floatBtn

local floatPlanet = new("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0.5, 0, 0.5, 0),
    Size = UDim2.fromOffset(13, 13),
    BackgroundColor3 = WHITE,
    BorderSizePixel = 0,
    ZIndex = 52,
}, { cornerFull() })
do
    local g = new("UIGradient", { Rotation = 90 })
    bindAccent(g, "Color", "Gradient")
    g.Parent = floatPlanet
end
floatPlanet.Parent = floatBtn

local floatMoon = new("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0.5, 10, 0.5, -8),
    Size = UDim2.fromOffset(6, 6),
    BackgroundColor3 = WHITE,
    BorderSizePixel = 0,
    ZIndex = 53,
}, { cornerFull() })
floatMoon.Parent = floatBtn

makeDraggable(floatBtn, floatBtn, 8, function()
    setMenuVisible(not menuOpen)
end, clampToScreen(FLOAT_SIZE))

------------------------------------------------------------
-- On-screen action buttons (for touch devices)
------------------------------------------------------------
local mobileGroup = new("Frame", {
    Name = "MobileButtons",
    BackgroundTransparency = 1,
    Size = UDim2.new(1, 0, 1, 0),
    Visible = isMobile,
})
mobileGroup.Parent = screenGui

local MOBILE_SIZE = 42

local function makeRoundButton(text, order)
    local vp = getViewport()
    local b = new("TextButton", {
        Position = UDim2.fromOffset(math.max(vp.X - 70, 10), 90 + (order - 1) * 52),
        Size = UDim2.fromOffset(MOBILE_SIZE, MOBILE_SIZE),
        BackgroundColor3 = C.Surface,
        FontFace = FONT,
        Text = text,
        TextSize = 11,
        TextColor3 = C.Text,
        AutoButtonColor = false,
        BorderSizePixel = 0,
        ZIndex = 40,
    }, { cornerFull() })
    stroke(b, C.Border, 1.5)
    b.Parent = mobileGroup
    return b
end

local aimBtn = makeRoundButton("AIM", 1)
local flyBtn = makeRoundButton("FLY", 2)
local noclipBtn = makeRoundButton("NC", 3)

local mobileClamp = clampToScreen(MOBILE_SIZE)
makeDraggable(aimBtn, aimBtn, 10, nil, mobileClamp)
makeDraggable(flyBtn, flyBtn, 10, function()
    if flyToggle then flyToggle:Set(not flyToggle.Value) end
end, mobileClamp)
makeDraggable(noclipBtn, noclipBtn, 10, function()
    if noclipToggle then noclipToggle:Set(not noclipToggle.Value) end
end, mobileClamp)

aimBtn.InputBegan:Connect(function(input)
    if not isPress(input) or not Config.Aim.Enabled then return end
    if Config.Aim.Sticky then
        stickyActive = not stickyActive
        currentTarget = nil
    else
        aimHeld = true
        currentTarget = nil
        local conn
        conn = input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                aimHeld = false
                if conn then conn:Disconnect() end
            end
        end)
    end
end)

------------------------------------------------------------
-- Feature helpers used by the pages
------------------------------------------------------------
local function aimActive()
    if not Config.Aim.Enabled then return false end
    if Config.Aim.Sticky then return stickyActive end
    return aimHeld
end

local function resetAim()
    aimHeld = false
    stickyActive = false
    currentTarget = nil
end

local function stopFly()
    if flyBV then flyBV:Destroy() flyBV = nil end
    if flyBG then flyBG:Destroy() flyBG = nil end
    local hum = getHumanoid()
    if hum then hum.PlatformStand = false end
end

local function restoreNoclip()
    for part in pairs(noclipParts) do
        if part and part.Parent then
            part.CanCollide = true
        end
    end
    noclipParts = {}
end

local function stopAnchor()
    local root = getRoot()
    if root then root.Anchored = false end
end

local function applyThemeByName(name)
    local color = accents[name]
    if not color then return end
    state.themeName = name
    state.rainbow = (name == "Rainbow")
    setAccent(color)
    applyAccent()
end

local unloadAll -- defined near the bottom

------------------------------------------------------------
-- Confirm-unload modal (lives inside the main window)
------------------------------------------------------------
local unloadOverlay = new("TextButton", {
    Size = UDim2.new(1, 0, 1, 0),
    BackgroundColor3 = Color3.new(0, 0, 0),
    BackgroundTransparency = 0.35,
    Text = "",
    AutoButtonColor = false,
    BorderSizePixel = 0,
    Visible = false,
    ZIndex = 50,
}, { corner(8) })
unloadOverlay.Parent = main

local unloadFrame = new("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0.5, 0, 0.5, 0),
    Size = UDim2.new(1, -40, 0, 128),
    BackgroundColor3 = C.Surface,
    BorderSizePixel = 0,
    Active = true,
    Visible = false,
    ZIndex = 51,
}, {
    corner(6),
    new("UISizeConstraint", { MaxSize = Vector2.new(250, 128) }),
})
stroke(unloadFrame, C.Border)
unloadFrame.Parent = main

label({
    Text = "Unload Orbit Hub?",
    Position = UDim2.fromOffset(12, 10),
    Size = UDim2.new(1, -24, 0, 18),
    TextSize = 14,
}).Parent = unloadFrame

label({
    Text = "This turns off every feature and removes the interface. You will need to run the script again to use it.",
    Position = UDim2.fromOffset(12, 32),
    Size = UDim2.new(1, -24, 0, 52),
    TextSize = 12,
    TextColor3 = C.TextDim,
    TextWrapped = true,
    TextYAlignment = Enum.TextYAlignment.Top,
}).Parent = unloadFrame

local function makeModalButton(text, position, primary)
    local btn = new("TextButton", {
        Position = position,
        Size = UDim2.new(0.5, -16, 0, 26),
        BackgroundColor3 = primary and WHITE or C.SurfaceAlt,
        Text = "",
        AutoButtonColor = false,
        BorderSizePixel = 0,
    }, { corner(5) })
    if primary then
        -- the gradient tints text too, so the label is a separate child
        local g = new("UIGradient", { Rotation = -90 })
        bindAccent(g, "Color", "Gradient")
        g.Parent = btn
    else
        stroke(btn, C.Border)
    end
    label({
        Text = text,
        Size = UDim2.new(1, 0, 1, 0),
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextColor3 = primary and C.Text or C.TextDim,
    }).Parent = btn
    btn.Parent = unloadFrame
    return btn
end

local unloadCancel = makeModalButton("Cancel", UDim2.new(0, 12, 1, -38), false)
local unloadConfirm = makeModalButton("Confirm", UDim2.new(0.5, 4, 1, -38), true)

local function hideUnloadModal()
    unloadOverlay.Visible = false
    unloadFrame.Visible = false
end

local function showUnloadModal()
    closePicker()
    unloadOverlay.Visible = true
    unloadFrame.Visible = true
end

unloadCancel.Activated:Connect(hideUnloadModal)
unloadOverlay.Activated:Connect(hideUnloadModal) -- tapping outside also cancels
unloadConfirm.Activated:Connect(function()
    hideUnloadModal()
    unloadAll()
end)

------------------------------------------------------------
-- Keybind list panel (drawn in the ESP gui, below the menu)
------------------------------------------------------------
local KB_W = 170

local kbPanel = new("Frame", {
    Name = "KeybindList",
    Position = UDim2.fromOffset(16, 200),
    Size = UDim2.fromOffset(KB_W, 0),
    AutomaticSize = Enum.AutomaticSize.Y,
    BackgroundColor3 = C.Background,
    BackgroundTransparency = 0.08,
    BorderSizePixel = 0,
    Active = true,
    Visible = false,
}, {
    corner(6),
    new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }),
    new("UIPadding", { PaddingBottom = UDim.new(0, 4) }),
})
stroke(kbPanel, C.Border)
kbPanel.Parent = espGui

local kbHead = new("Frame", {
    LayoutOrder = 0,
    Size = UDim2.new(1, 0, 0, 22),
    BackgroundTransparency = 1,
    Active = true,
})
kbHead.Parent = kbPanel

label({
    Text = "Keybinds",
    Position = UDim2.fromOffset(8, 0),
    Size = UDim2.new(1, -16, 1, 0),
    TextSize = 12,
}).Parent = kbHead

do
    local line = new("Frame", {
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 0, 1, 0),
        Size = UDim2.new(1, 0, 0, 1),
        BorderSizePixel = 0,
    })
    bindAccent(line, "BackgroundColor3", "Accent")
    line.Parent = kbHead
end

local kbRows = {}

local function getKbRow(i)
    local r = kbRows[i]
    if r then return r end

    local f = new("Frame", {
        LayoutOrder = i,
        Size = UDim2.new(1, 0, 0, 18),
        BackgroundTransparency = 1,
        Visible = false,
    })
    local nameLbl = label({
        Position = UDim2.fromOffset(8, 0),
        Size = UDim2.new(0.5, -8, 1, 0),
        TextSize = 12,
        TextTruncate = Enum.TextTruncate.AtEnd,
    })
    nameLbl.Parent = f
    local valLbl = label({
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -8, 0, 0),
        Size = UDim2.new(0.5, -8, 1, 0),
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Right,
    })
    valLbl.Parent = f
    f.Parent = kbPanel

    r = { Frame = f, Name = nameLbl, Value = valLbl }
    kbRows[i] = r
    return r
end

-- features whose keybind is currently relevant, and what state they are in
local function collectKeybinds()
    local list = {}
    local function add(name, bind, status, engaged)
        table.insert(list, { name, bindName(bind), status, engaged })
    end

    if Config.Aim.Enabled then
        local engaged = aimActive()
        if Config.Aim.Sticky then
            add("Aimbot", Config.Aim.Key, engaged and "Toggled" or "Idle", engaged)
        else
            add("Aimbot", Config.Aim.Key, engaged and "Holding" or "Idle", engaged)
        end
    end
    if Config.Move.Fly then add("Fly", Config.Move.FlyKey, "Toggled", true) end
    if Config.Move.Noclip then add("Noclip", Config.Move.NoclipKey, "Toggled", true) end
    if Config.Move.BunnyHop then add("Bunny Hop", Config.Move.BunnyHopKey, "Toggled", true) end
    if Config.Move.Anchor then add("Anchor", Config.Move.AnchorKey, "Toggled", true) end

    return list
end

local kbXSlider, kbYSlider -- created in the Settings page

-- free space the panel can move in (so 0%..100% always stays on screen)
local function kbAvailable()
    local vp = getViewport()
    local s = kbPanel.AbsoluteSize
    local w = s.X > 0 and s.X or KB_W
    local h = s.Y > 0 and s.Y or 60
    return math.max(vp.X - w, 0), math.max(vp.Y - h, 0)
end

local function applyKbPosition()
    local ax, ay = kbAvailable()
    kbPanel.Position = UDim2.fromOffset(
        math.floor(ax * Config.UI.KeybindListX / 100),
        math.floor(ay * Config.UI.KeybindListY / 100)
    )
end

-- after dragging the panel by hand, move the sliders to match
local function syncKbSliders()
    local ax, ay = kbAvailable()
    local px = math.clamp(math.floor(kbPanel.Position.X.Offset / math.max(ax, 1) * 100 + 0.5), 0, 100)
    local py = math.clamp(math.floor(kbPanel.Position.Y.Offset / math.max(ay, 1) * 100 + 0.5), 0, 100)
    Config.UI.KeybindListX = px
    Config.UI.KeybindListY = py
    if kbXSlider then kbXSlider:Set(px, true) end
    if kbYSlider then kbYSlider:Set(py, true) end
end

local function updateKeybindList()
    local visible = Config.UI.KeybindList and not panicHidden
    kbPanel.Visible = visible
    if not visible then return end

    local entries = collectKeybinds()
    if #entries == 0 then
        entries = { { "None active", "", "", false } }
    end

    for i, e in ipairs(entries) do
        local r = getKbRow(i)
        r.Frame.Visible = true
        r.Name.Text = e[1]
        r.Name.TextColor3 = e[4] and C.Text or C.TextMute
        if e[2] ~= "" then
            r.Value.Text = "[" .. e[2] .. "] " .. e[3]
        else
            r.Value.Text = ""
        end
        r.Value.TextColor3 = e[4] and state.accent or C.TextMute
    end
    for i = #entries + 1, #kbRows do
        kbRows[i].Frame.Visible = false
    end

    -- keep the panel on screen if it grew
    local ax, ay = kbAvailable()
    local pos = kbPanel.Position
    local nx = math.clamp(pos.X.Offset, 0, ax)
    local ny = math.clamp(pos.Y.Offset, 0, ay)
    if nx ~= pos.X.Offset or ny ~= pos.Y.Offset then
        kbPanel.Position = UDim2.fromOffset(nx, ny)
    end
end

do
    local clamp = function(ox, oy)
        local ax, ay = kbAvailable()
        return math.clamp(ox, 0, ax), math.clamp(oy, 0, ay)
    end
    makeDraggable(kbHead, kbPanel, 0, nil, clamp)

    local pressed = false
    kbHead.InputBegan:Connect(function(input)
        if isPress(input) then pressed = true end
    end)
    connect(UserInputService.InputEnded, function(input)
        if pressed and isPress(input) then
            pressed = false
            syncKbSliders()
        end
    end)
end
applyKbPosition()

------------------------------------------------------------
-- Watermark (FPS, ping, date, time, player count)
------------------------------------------------------------
local WM_PRESETS = {
    TopLeft = { Vector2.new(0, 0), UDim2.new(0, 10, 0, 44) },
    TopRight = { Vector2.new(1, 0), UDim2.new(1, -10, 0, 44) },
    BottomLeft = { Vector2.new(0, 1), UDim2.new(0, 10, 1, -10) },
    BottomRight = { Vector2.new(1, 1), UDim2.new(1, -10, 1, -10) },
}

local wmFrame = new("Frame", {
    Name = "Watermark",
    Size = UDim2.fromOffset(0, 22),
    AutomaticSize = Enum.AutomaticSize.X,
    BackgroundColor3 = C.Background,
    BackgroundTransparency = 0.08,
    BorderSizePixel = 0,
    Visible = false,
}, {
    corner(5),
    new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }),
})
stroke(wmFrame, C.Border)
wmFrame.Parent = espGui

local wmLabel = label({
    Size = UDim2.new(0, 0, 1, 0),
    AutomaticSize = Enum.AutomaticSize.X,
    TextSize = 12,
    TextColor3 = C.TextDim,
    Text = "",
})
wmLabel.Parent = wmFrame

do
    local bar = new("Frame", {
        Size = UDim2.new(1, 0, 0, 2),
        BorderSizePixel = 0,
    })
    bindAccent(bar, "BackgroundColor3", "Accent")
    bar.Parent = wmFrame
end

local function applyWatermarkPos()
    local p = WM_PRESETS[Config.UI.WatermarkPos] or WM_PRESETS.TopRight
    wmFrame.AnchorPoint = p[1]
    wmFrame.Position = p[2]
end
applyWatermarkPos()

local fpsValue = 0

local function getPing()
    local ms
    pcall(function()
        ms = game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue()
    end)
    if not ms then
        pcall(function() ms = LocalPlayer:GetNetworkPing() * 1000 end)
    end
    return ms and math.floor(ms + 0.5) or nil
end

local function updateWatermark()
    local u = Config.UI
    local visible = u.Watermark and not panicHidden
    wmFrame.Visible = visible
    if not visible then return end

    local parts = {}
    if u.WatermarkTitle ~= "" then
        table.insert(parts, u.WatermarkTitle)
    end
    if u.WatermarkFPS then
        table.insert(parts, (fpsValue > 0 and tostring(fpsValue) or "--") .. " FPS")
    end
    if u.WatermarkPing then
        local p = getPing()
        table.insert(parts, (p and tostring(p) or "--") .. " ms")
    end
    if u.WatermarkDate then
        table.insert(parts, os.date("%Y-%m-%d")) -- local date
    end
    if u.WatermarkTime then
        table.insert(parts, os.date("%H:%M:%S")) -- local time
    end
    if u.WatermarkPlayers then
        table.insert(parts, #Players:GetPlayers() .. "/" .. Players.MaxPlayers .. " players")
    end

    wmLabel.Text = (#parts > 0) and table.concat(parts, "  |  ") or "Watermark"
end

------------------------------------------------------------
-- Waypoints (create / rename / delete / teleport / 3D markers)
------------------------------------------------------------
local WP_FILE = "OrbitHub_Waypoints.json"
local waypoints = {} -- { { Id = n, Name = "...", Pos = Vector3 } }
local waypointNextId = 1
local selectedWaypoint = nil -- Id of the selected waypoint
local waypointDropdown, waypointNameBox -- created in the Movement page

local function trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Saving to disk only happens when the executor offers readfile/writefile (all guarded).
-- Waypoints are stored per game (PlaceId).
local function readWaypointFile()
    local all = {}
    pcall(function()
        if isfile and readfile and isfile(WP_FILE) then
            all = HttpService:JSONDecode(readfile(WP_FILE))
        end
    end)
    return type(all) == "table" and all or {}
end

local function saveWaypoints()
    pcall(function()
        if not writefile then return end
        local all = readWaypointFile()
        local list = {}
        for _, w in ipairs(waypoints) do
            table.insert(list, { n = w.Name, x = w.Pos.X, y = w.Pos.Y, z = w.Pos.Z })
        end
        all[tostring(game.PlaceId)] = list
        writefile(WP_FILE, HttpService:JSONEncode(all))
    end)
end

do
    local list = readWaypointFile()[tostring(game.PlaceId)]
    if type(list) == "table" then
        for _, w in ipairs(list) do
            if type(w) == "table" and tonumber(w.x) and tonumber(w.y) and tonumber(w.z) then
                table.insert(waypoints, {
                    Id = waypointNextId,
                    Name = tostring(w.n or ("Waypoint " .. waypointNextId)),
                    Pos = Vector3.new(w.x, w.y, w.z),
                })
                waypointNextId = waypointNextId + 1
            end
        end
    end
end

local function findWaypoint(id)
    for i, w in ipairs(waypoints) do
        if w.Id == id then return w, i end
    end
    return nil
end

-- 3D markers: a glowing pillar with a cap and a name tag, parked under the camera
local markerFolder = nil
local markers = {} -- { Part, Cap, Label, Waypoint }

local function clearMarkers()
    markers = {}
    if markerFolder then
        pcall(function() markerFolder:Destroy() end)
        markerFolder = nil
    end
end

local rebuildWaypointMarkers

local function updateWaypointMarkers()
    if #markers == 0 then return end

    if markerFolder and not markerFolder:IsDescendantOf(workspace) then
        rebuildWaypointMarkers() -- the camera was replaced
        return
    end

    local root = getRoot()
    for _, m in ipairs(markers) do
        if root then
            local dist = math.floor((root.Position - m.Waypoint.Pos).Magnitude + 0.5)
            m.Label.Text = string.format("%s  [%d studs]", m.Waypoint.Name, dist)
        else
            m.Label.Text = m.Waypoint.Name
        end
    end
end

rebuildWaypointMarkers = function()
    clearMarkers()
    if not Config.Move.ShowWaypoints or #waypoints == 0 then return end

    markerFolder = new("Folder", { Name = "OrbitHubWaypoints" })

    for _, w in ipairs(waypoints) do
        local function basePart(props)
            props.Anchored = true
            props.CanCollide = false
            props.CanQuery = false
            props.CanTouch = false
            props.CastShadow = false
            props.Material = Enum.Material.Neon
            props.Color = state.accent
            props.Transparency = 0.2
            return new("Part", props)
        end

        local pillar = basePart({
            Name = "Marker",
            Size = Vector3.new(0.5, 8, 0.5),
            Position = w.Pos + Vector3.new(0, 1, 0),
        })
        local cap = basePart({
            Name = "MarkerCap",
            Shape = Enum.PartType.Ball,
            Size = Vector3.new(1.6, 1.6, 1.6),
            Position = w.Pos + Vector3.new(0, 5, 0),
        })

        local tag = new("BillboardGui", {
            Adornee = pillar,
            AlwaysOnTop = true,
            LightInfluence = 0,
            Size = UDim2.fromOffset(170, 30),
            StudsOffset = Vector3.new(0, 5.5, 0),
        })
        local lbl = label({
            Size = UDim2.new(1, 0, 1, 0),
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Center,
            TextStrokeTransparency = 0.4,
            Text = w.Name,
        })
        lbl.Parent = tag
        tag.Parent = pillar

        pillar.Parent = markerFolder
        cap.Parent = markerFolder
        table.insert(markers, { Part = pillar, Cap = cap, Label = lbl, Waypoint = w })
    end

    markerFolder.Parent = workspace.CurrentCamera or workspace
    updateWaypointMarkers()
end

-- markers follow the accent color
table.insert(refreshers, function()
    for _, m in ipairs(markers) do
        m.Part.Color = state.accent
        m.Cap.Color = state.accent
    end
end)

local function refreshWaypointUI()
    if waypointDropdown then
        waypointDropdown.Value = selectedWaypoint
        waypointDropdown:Refresh()
    end
    rebuildWaypointMarkers()
end

local function addWaypoint(name)
    local root = getRoot()
    if not root then
        toast("No character to save a position from")
        return false
    end
    name = trim(name)
    if name == "" then name = "Waypoint " .. waypointNextId end

    local w = { Id = waypointNextId, Name = name, Pos = root.Position }
    waypointNextId = waypointNextId + 1
    table.insert(waypoints, w)
    selectedWaypoint = w.Id
    saveWaypoints()
    refreshWaypointUI()
    toast("Saved: " .. w.Name)
    return true
end

local function renameWaypoint(newName)
    local w = findWaypoint(selectedWaypoint)
    if not w then
        toast("Select a waypoint first")
        return false
    end
    newName = trim(newName)
    if newName == "" then
        toast("Type the new name in the Name box first")
        return false
    end
    w.Name = newName
    saveWaypoints()
    refreshWaypointUI()
    toast("Renamed to " .. newName)
    return true
end

local function deleteWaypoint()
    local w, i = findWaypoint(selectedWaypoint)
    if not w then
        toast("Select a waypoint first")
        return
    end
    table.remove(waypoints, i)
    selectedWaypoint = nil
    saveWaypoints()
    refreshWaypointUI()
    toast("Deleted: " .. w.Name)
end

local function teleportToWaypoint()
    local w = findWaypoint(selectedWaypoint)
    if not w then
        toast("Select a waypoint first")
        return
    end
    local root = getRoot()
    if not root then return end
    local rotation = root.CFrame - root.CFrame.Position
    root.CFrame = CFrame.new(w.Pos) * rotation
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    toast("Teleported to " .. w.Name)
end

------------------------------------------------------------
-- Panic key: features off, character reset, GUI closed
------------------------------------------------------------
local function panic()
    -- 1) every feature toggle off (their callbacks restore speed, fly, noclip, anchor...)
    for _, t in ipairs(allToggles) do
        if t.Value then
            pcall(function() t:Set(false) end)
        end
    end
    resetAim()
    stopFly()
    restoreNoclip()
    stopAnchor()
    clearMarkers()

    -- 2) reset the character
    pcall(function()
        local hum = getHumanoid()
        if hum then hum.Health = 0 end
        local char = LocalPlayer.Character
        if char then char:BreakJoints() end
    end)

    -- 3) close the GUI (the menu key brings everything back)
    closePicker()
    hideUnloadModal()
    panicHidden = true
    setMenuVisible(false)
    if not isMobile then floatBtn.Visible = false end
    mobileGroup.Visible = false
    updateWatermark()
    updateKeybindList()
end

onMenuShown = function()
    floatBtn.Visible = Config.FloatingIcon
    mobileGroup.Visible = mobileButtonsWanted
    updateWatermark()
    updateKeybindList()
end

-- FPS counter + slow refresh of the overlays (5 times a second is plenty)
do
    local frames, clock, overlayClock = 0, 0, 0
    connect(RunService.RenderStepped, function(dt)
        frames = frames + 1
        clock = clock + dt
        if clock >= 0.5 then
            fpsValue = math.floor(frames / clock + 0.5)
            frames = 0
            clock = 0
        end

        overlayClock = overlayClock + dt
        if overlayClock < 0.2 then return end
        overlayClock = 0

        updateWatermark()
        updateKeybindList()
        updateWaypointMarkers()
    end)
end

------------------------------------------------------------
-- Pages
------------------------------------------------------------

-- AIMBOT
do
    local page = pages["Aimbot"]

    local aim = newSection(page, "Aimbot", ICONS.crosshair)
    local aimToggle = addToggle(aim, "Enabled", false, function(v)
        Config.Aim.Enabled = v
        resetAim()
    end)
    addKeybind(aimToggle.Right, Config.Aim.Key, function(b)
        Config.Aim.Key = b
        resetAim()
    end)
    addToggle(aim, "Sticky Aim", false, function(v)
        Config.Aim.Sticky = v
        resetAim()
    end)
    addToggle(aim, "Team Check", false, function(v)
        Config.Aim.TeamCheck = v
    end)
    addToggle(aim, "Wall Check", false, function(v)
        Config.Aim.WallCheck = v
    end)

    local smooth = newSection(page, "Smoothing", ICONS.sliders)
    addToggle(smooth, "Smoothing", false, function(v)
        Config.Aim.Smooth = v
    end)
    addSlider(smooth, {
        Name = "Smoothness",
        Min = 1, Max = 10, Value = Config.Aim.Smoothness,
        Callback = function(v) Config.Aim.Smoothness = v end,
    })

    local fov = newSection(page, "Field of View", ICONS.scan)
    local fovToggle = addToggle(fov, "FOV Circle", false, function(v)
        Config.Aim.FOV = v
    end)
    addColorSwatch(fovToggle.Right, Config.Aim.FOVColor, function(c)
        Config.Aim.FOVColor = c
    end)
    addSlider(fov, {
        Name = "FOV Size",
        Min = 20, Max = 500, Value = Config.Aim.FOVSize, Suffix = " px",
        Callback = function(v) Config.Aim.FOVSize = v end,
    })
    addToggle(fov, "Aim Only in FOV", false, function(v)
        Config.Aim.OnlyInFOV = v
        currentTarget = nil
    end)
    addToggle(fov, "Dynamic FOV", false, function(v)
        Config.Aim.DynamicFOV = v
    end)

    local shake = newSection(page, "Shake", ICONS.activity)
    addToggle(shake, "Aim Shake", false, function(v)
        Config.Aim.Shake = v
    end)
    addSlider(shake, {
        Name = "Shake Amount",
        Min = 1, Max = 20, Value = Config.Aim.ShakeAmount,
        Callback = function(v) Config.Aim.ShakeAmount = v end,
    })

    local wl = newSection(page, "Player Whitelist", ICONS.users)
    addPlayerDropdown(wl, "Players", Config.Aim.Whitelist)
end

-- ESP
do
    local page = pages["ESP"]
    local sec = newSection(page, "Visuals", ICONS.eye)

    local function espRow(text, flag, colorFlag)
        local t = addToggle(sec, text, false, function(v)
            Config.ESP[flag] = v
        end)
        addColorSwatch(t.Right, Config.ESP[colorFlag], function(c)
            Config.ESP[colorFlag] = c
        end)
    end

    espRow("Names", "Names", "NamesColor")
    espRow("Boxes", "Boxes", "BoxesColor")
    espRow("Tracers", "Tracers", "TracersColor")
    espRow("Skeletons", "Skeletons", "SkeletonsColor")

    local wl = newSection(page, "Player Whitelist", ICONS.users)
    addPlayerDropdown(wl, "Excluded", Config.ESP.Whitelist)
end

-- MOVEMENT
do
    local page = pages["Movement"]
    local character = newSection(page, "Character", ICONS.user)

    addToggle(character, "WalkSpeed", false, function(v)
        Config.Move.WalkSpeed = v
        if not v then
            local hum = getHumanoid()
            if hum then hum.WalkSpeed = defaultWalkSpeed end
        end
    end)
    addSlider(character, {
        Name = "WalkSpeed Value",
        Min = defaultWalkSpeed, Max = math.max(100, defaultWalkSpeed + 1), Value = defaultWalkSpeed,
        Callback = function(v) Config.Move.WalkSpeedValue = v end,
    })

    addToggle(character, "Jump Power", false, function(v)
        Config.Move.Jump = v
        if not v then
            local hum = getHumanoid()
            if hum then hum.JumpPower = defaultJumpPower end
        end
    end)
    addSlider(character, {
        Name = "Jump Power Value",
        Min = defaultJumpPower, Max = math.max(200, defaultJumpPower + 1), Value = defaultJumpPower,
        Callback = function(v) Config.Move.JumpValue = v end,
    })

    local abilities = newSection(page, "Abilities", ICONS.zap)

    flyToggle = addToggle(abilities, "Fly", false, function(v)
        Config.Move.Fly = v
        if not v then stopFly() end
    end)
    addKeybind(flyToggle.Right, Config.Move.FlyKey, function(b)
        Config.Move.FlyKey = b
    end)

    noclipToggle = addToggle(abilities, "Noclip", false, function(v)
        Config.Move.Noclip = v
        if not v then restoreNoclip() end
    end)
    addKeybind(noclipToggle.Right, Config.Move.NoclipKey, function(b)
        Config.Move.NoclipKey = b
    end)

    local extras = newSection(page, "Movement Extras", ICONS.zap)

    bunnyToggle = addToggle(extras, "Bunny Hop", false, function(v)
        Config.Move.BunnyHop = v
    end)
    addKeybind(bunnyToggle.Right, Config.Move.BunnyHopKey, function(b)
        Config.Move.BunnyHopKey = b
    end)

    anchorToggle = addToggle(extras, "Anchor / Freeze", false, function(v)
        Config.Move.Anchor = v
        if not v then stopAnchor() end
    end)
    addKeybind(anchorToggle.Right, Config.Move.AnchorKey, function(b)
        Config.Move.AnchorKey = b
    end)

    local wp = newSection(page, "Waypoints", ICONS.pointer)

    waypointNameBox = addTextBox(wp, "Name", "", "New or new name")
    addButton(wp, "Save Current Position", function()
        if addWaypoint(waypointNameBox:Get()) then
            waypointNameBox:Set("")
        end
    end)

    waypointDropdown = addDropdown(wp, {
        Name = "Waypoint",
        Value = selectedWaypoint,
        Placeholder = "None selected",
        EmptyText = "No waypoints saved",
        GetOptions = function()
            local opts = {}
            for _, w in ipairs(waypoints) do
                table.insert(opts, { Key = w.Id, Text = w.Name })
            end
            return opts
        end,
        Callback = function(id)
            selectedWaypoint = id
        end,
    })

    addButton(wp, "Teleport to Waypoint", teleportToWaypoint)
    addButton(wp, "Rename Selected", function()
        if renameWaypoint(waypointNameBox:Get()) then
            waypointNameBox:Set("")
        end
    end)
    addButton(wp, "Delete Selected", deleteWaypoint)

    addToggle(wp, "Visualize Waypoints", false, function(v)
        Config.Move.ShowWaypoints = v
        rebuildWaypointMarkers()
    end)
end

-- SETTINGS
do
    local page = pages["Settings"]

    local ui = newSection(page, "Interface", ICONS.pointer)
    floatToggle = addToggle(ui, "Floating Icon", Config.FloatingIcon, function(v)
        Config.FloatingIcon = v
        floatBtn.Visible = v and not panicHidden
        if not v and isMobile then
            toast("Icon hidden. It comes back if you close the menu.")
        end
    end, true)
    addToggle(ui, "On-screen Buttons", isMobile, function(v)
        mobileButtonsWanted = v
        mobileGroup.Visible = v and not panicHidden
    end, true)
    addKeybindRow(ui, "Menu Key", Config.MenuKey, function(b)
        Config.MenuKey = b
    end)

    local panicSec = newSection(page, "Panic Key", ICONS.zap)
    addKeybindRow(panicSec, "Panic Key", Config.UI.PanicKey, function(b)
        Config.UI.PanicKey = b
    end)

    local kb = newSection(page, "Keybind List", ICONS.activity)
    addToggle(kb, "Show Keybind List", Config.UI.KeybindList, function(v)
        Config.UI.KeybindList = v
        if v then applyKbPosition() end
        updateKeybindList()
    end, true)
    kbXSlider = addSlider(kb, {
        Name = "Position X",
        Min = 0, Max = 100, Value = Config.UI.KeybindListX, Suffix = "%",
        Callback = function(v)
            Config.UI.KeybindListX = v
            applyKbPosition()
        end,
    })
    kbYSlider = addSlider(kb, {
        Name = "Position Y",
        Min = 0, Max = 100, Value = Config.UI.KeybindListY, Suffix = "%",
        Callback = function(v)
            Config.UI.KeybindListY = v
            applyKbPosition()
        end,
    })
    addButton(kb, "Reset Position", function()
        kbXSlider:Set(2)
        kbYSlider:Set(35)
        Config.UI.KeybindListX = 2
        Config.UI.KeybindListY = 35
        applyKbPosition()
    end)

    local wm = newSection(page, "Watermark", ICONS.scan)
    addToggle(wm, "Show Watermark", Config.UI.Watermark, function(v)
        Config.UI.Watermark = v
        updateWatermark()
    end, true)
    addTextBox(wm, "Title", Config.UI.WatermarkTitle, "Watermark title", function(t)
        Config.UI.WatermarkTitle = trim(t)
        updateWatermark()
    end)
    local function wmToggle(text, flag)
        addToggle(wm, text, Config.UI[flag], function(v)
            Config.UI[flag] = v
            updateWatermark()
        end, true)
    end
    wmToggle("FPS", "WatermarkFPS")
    wmToggle("Ping", "WatermarkPing")
    wmToggle("Date", "WatermarkDate")
    wmToggle("Time", "WatermarkTime")
    wmToggle("Server Players", "WatermarkPlayers")
    addDropdown(wm, {
        Name = "Position",
        Value = Config.UI.WatermarkPos,
        GetOptions = function()
            return {
                { Key = "TopLeft", Text = "Top Left" },
                { Key = "TopRight", Text = "Top Right" },
                { Key = "BottomLeft", Text = "Bottom Left" },
                { Key = "BottomRight", Text = "Bottom Right" },
            }
        end,
        Callback = function(key)
            Config.UI.WatermarkPos = key
            applyWatermarkPos()
        end,
    })

    local theme = newSection(page, "Theme", ICONS.palette)
    addDropdown(theme, {
        Name = "Accent",
        Value = state.themeName,
        GetOptions = function()
            local opts = {}
            for _, name in ipairs(accentOrder) do
                table.insert(opts, {
                    Key = name,
                    Text = name,
                    Swatch = (name == "Rainbow") and "rainbow" or accents[name],
                })
            end
            return opts
        end,
        Callback = applyThemeByName,
    })

    local about = newSection(page, "Orbit Hub", ICONS.box)
    addButton(about, "Unload Orbit Hub", showUnloadModal)
end

------------------------------------------------------------
-- AIMBOT logic
------------------------------------------------------------
local function sameTeam(player)
    if LocalPlayer.Neutral or player.Neutral then return false end
    return player.TeamColor == LocalPlayer.TeamColor
end

-- returns character, head when the player is a valid target
local function getTargetParts(player)
    if player == LocalPlayer then return nil end
    if isWhitelisted(Config.Aim.Whitelist, player) then return nil end
    local char = player.Character
    if not char then return nil end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local head = char:FindFirstChild("Head")
    if not hum or not head or hum.Health <= 0 then return nil end
    if Config.Aim.TeamCheck and sameTeam(player) then return nil end
    return char, head
end

local function isVisible(char, head)
    local cam = workspace.CurrentCamera
    local origin = cam.CFrame.Position

    local ignore = { cam }
    if LocalPlayer.Character then
        table.insert(ignore, LocalPlayer.Character)
    end

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = ignore
    params.IgnoreWater = true

    local result = workspace:Raycast(origin, head.Position - origin, params)
    return result == nil or result.Instance:IsDescendantOf(char)
end

local function getAimReference()
    if UserInputService.MouseEnabled then
        return UserInputService:GetMouseLocation()
    end
    return getViewport() / 2
end

-- center of the FOV circle: the cursor when Dynamic FOV is on, else the screen center
local function getFovCenter()
    if Config.Aim.DynamicFOV and UserInputService.MouseEnabled then
        return UserInputService:GetMouseLocation()
    end
    return getViewport() / 2
end

local function getClosestTarget()
    local cam = workspace.CurrentCamera
    local onlyFov = Config.Aim.OnlyInFOV
    local ref = onlyFov and getFovCenter() or getAimReference()
    local radius = Config.Aim.FOVSize
    local best, bestDist = nil, math.huge

    for _, plr in ipairs(Players:GetPlayers()) do
        local char, head = getTargetParts(plr)
        if char then
            local sp, onScreen = cam:WorldToViewportPoint(head.Position)
            if onScreen then
                local d = (Vector2.new(sp.X, sp.Y) - ref).Magnitude
                if d < bestDist and (not onlyFov or d <= radius) then
                    if not Config.Aim.WallCheck or isVisible(char, head) then
                        best, bestDist = plr, d
                    end
                end
            end
        end
    end

    return best
end

RunService:BindToRenderStep("OrbitHubAim", Enum.RenderPriority.Camera.Value + 1, function(dt)
    if not aimActive() then
        currentTarget = nil
        return
    end

    local cam = workspace.CurrentCamera

    -- keep the current target while it stays valid
    if currentTarget then
        local char, head = getTargetParts(currentTarget)
        if not char or (Config.Aim.WallCheck and not isVisible(char, head)) then
            currentTarget = nil
        elseif Config.Aim.OnlyInFOV then
            local sp, onScreen = cam:WorldToViewportPoint(head.Position)
            local d = (Vector2.new(sp.X, sp.Y) - getFovCenter()).Magnitude
            if not onScreen or d > Config.Aim.FOVSize then
                currentTarget = nil
            end
        end
    end

    if not currentTarget then
        currentTarget = getClosestTarget()
    end
    if not currentTarget then return end

    local _, head = getTargetParts(currentTarget)
    if not head then return end

    local goal = CFrame.new(cam.CFrame.Position, head.Position)

    -- shake: small random rotation around the aim point
    if Config.Aim.Shake then
        local a = math.rad(Config.Aim.ShakeAmount * 0.08)
        goal = goal * CFrame.Angles((math.random() * 2 - 1) * a, (math.random() * 2 - 1) * a, 0)
    end

    local alpha = 1
    if Config.Aim.Smooth then
        alpha = math.clamp((1 / (1 + Config.Aim.Smoothness * 1.5)) * dt * 60, 0, 1)
    end

    cam.CFrame = cam.CFrame:Lerp(goal, alpha)
end)

------------------------------------------------------------
-- FOV circle (plain GUI frame, no Drawing API)
------------------------------------------------------------
local fovCircle = new("Frame", {
    Name = "FOV",
    AnchorPoint = Vector2.new(0.5, 0.5),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Size = UDim2.fromOffset(240, 240),
    Visible = false,
}, { cornerFull() })
local fovStroke = new("UIStroke", {
    Thickness = 1.5,
    Transparency = 0.2,
    Color = Config.Aim.FOVColor,
    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
})
fovStroke.Parent = fovCircle
fovCircle.Parent = espGui

connect(RunService.RenderStepped, function()
    if not Config.Aim.FOV then
        if fovCircle.Visible then fovCircle.Visible = false end
        return
    end
    local c = getFovCenter()
    local d = Config.Aim.FOVSize * 2
    fovCircle.Size = UDim2.fromOffset(d, d)
    fovCircle.Position = UDim2.fromOffset(c.X, c.Y)
    fovStroke.Color = Config.Aim.FOVColor
    fovCircle.Visible = true
end)

------------------------------------------------------------
-- ESP logic (plain GUI frames: works on every executor and on mobile)
------------------------------------------------------------
local ESP = { Objects = {} }

local R15_BONES = {
    { "Head", "UpperTorso" }, { "UpperTorso", "LowerTorso" },
    { "UpperTorso", "LeftUpperArm" }, { "LeftUpperArm", "LeftLowerArm" }, { "LeftLowerArm", "LeftHand" },
    { "UpperTorso", "RightUpperArm" }, { "RightUpperArm", "RightLowerArm" }, { "RightLowerArm", "RightHand" },
    { "LowerTorso", "LeftUpperLeg" }, { "LeftUpperLeg", "LeftLowerLeg" }, { "LeftLowerLeg", "LeftFoot" },
    { "LowerTorso", "RightUpperLeg" }, { "RightUpperLeg", "RightLowerLeg" }, { "RightLowerLeg", "RightFoot" },
}

local R6_BONES = {
    { "Head", "Torso" },
    { "Torso", "Left Arm" }, { "Torso", "Right Arm" },
    { "Torso", "Left Leg" }, { "Torso", "Right Leg" },
}

local function newLine()
    local f = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        BorderSizePixel = 0,
        Visible = false,
        Size = UDim2.fromOffset(0, 2),
    })
    f.Parent = espGui
    return f
end

local function setLine(f, a, b, color)
    local dx, dy = b.X - a.X, b.Y - a.Y
    f.BackgroundColor3 = color
    f.Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy), 2)
    f.Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
    f.Rotation = math.deg(math.atan2(dy, dx))
    f.Visible = true
end

local function createESP(player)
    if player == LocalPlayer or ESP.Objects[player] then return end

    local o = {}

    o.Name = new("TextLabel", {
        AnchorPoint = Vector2.new(0.5, 1),
        BackgroundTransparency = 1,
        Size = UDim2.fromOffset(200, 16),
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextStrokeTransparency = 0.3,
        TextStrokeColor3 = Color3.new(0, 0, 0),
        Visible = false,
    })
    o.Name.Parent = espGui

    o.Box = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Visible = false,
    })
    o.BoxStroke = new("UIStroke", {
        Thickness = 1.5,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    })
    o.BoxStroke.Parent = o.Box
    o.Box.Parent = espGui

    o.Tracer = newLine()
    o.Skel = {}
    for i = 1, #R15_BONES do
        o.Skel[i] = newLine()
    end

    ESP.Objects[player] = o
end

local function removeESP(player)
    local o = ESP.Objects[player]
    if not o then return end
    pcall(function() o.Name:Destroy() end)
    pcall(function() o.Box:Destroy() end)
    pcall(function() o.Tracer:Destroy() end)
    for _, l in ipairs(o.Skel) do
        pcall(function() l:Destroy() end)
    end
    ESP.Objects[player] = nil
end

local function hideESP(o)
    o.Name.Visible = false
    o.Box.Visible = false
    o.Tracer.Visible = false
    for _, l in ipairs(o.Skel) do l.Visible = false end
end

local function updatePlayerESP(player, o, cam, viewport)
    if isWhitelisted(Config.ESP.Whitelist, player) then
        hideESP(o)
        return
    end

    local char = player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")

    if not hum or not root or hum.Health <= 0 then
        hideESP(o)
        return
    end

    local rootPos, onScreen = cam:WorldToViewportPoint(root.Position)
    if not onScreen or rootPos.Z <= 0 then
        hideESP(o)
        return
    end

    local cfg = Config.ESP
    local top = cam:WorldToViewportPoint(root.Position + Vector3.new(0, 2.8, 0))
    local bottom = cam:WorldToViewportPoint(root.Position - Vector3.new(0, 3.2, 0))
    local height = math.abs(bottom.Y - top.Y)
    local width = height * 0.55

    -- Names
    if cfg.Names then
        o.Name.Text = player.DisplayName
        o.Name.TextColor3 = cfg.NamesColor
        o.Name.Position = UDim2.fromOffset(rootPos.X, top.Y - 2)
        o.Name.Visible = true
    else
        o.Name.Visible = false
    end

    -- Boxes
    if cfg.Boxes then
        o.Box.Size = UDim2.fromOffset(width, height)
        o.Box.Position = UDim2.fromOffset(rootPos.X, top.Y)
        o.BoxStroke.Color = cfg.BoxesColor
        o.Box.Visible = true
    else
        o.Box.Visible = false
    end

    -- Tracers
    if cfg.Tracers then
        setLine(o.Tracer, Vector2.new(viewport.X / 2, viewport.Y), Vector2.new(rootPos.X, bottom.Y), cfg.TracersColor)
    else
        o.Tracer.Visible = false
    end

    -- Skeletons
    if cfg.Skeletons then
        local bones = char:FindFirstChild("UpperTorso") and R15_BONES or R6_BONES
        for i, line in ipairs(o.Skel) do
            local pair = bones[i]
            local shown = false
            if pair then
                local a = char:FindFirstChild(pair[1])
                local b = char:FindFirstChild(pair[2])
                if a and b then
                    local pa = cam:WorldToViewportPoint(a.Position)
                    local pb = cam:WorldToViewportPoint(b.Position)
                    if pa.Z > 0 and pb.Z > 0 then
                        setLine(line, Vector2.new(pa.X, pa.Y), Vector2.new(pb.X, pb.Y), cfg.SkeletonsColor)
                        shown = true
                    end
                end
            end
            if not shown then line.Visible = false end
        end
    else
        for _, line in ipairs(o.Skel) do line.Visible = false end
    end
end

for _, p in ipairs(Players:GetPlayers()) do
    createESP(p)
end

connect(Players.PlayerAdded, function(p)
    createESP(p)
    refreshPlayerDropdowns()
end)

connect(Players.PlayerRemoving, function(p)
    removeESP(p)
    leavingPlayer = p
    refreshPlayerDropdowns()
    leavingPlayer = nil
end)

connect(RunService.RenderStepped, function()
    local cam = workspace.CurrentCamera
    if not cam then return end
    local viewport = cam.ViewportSize
    for player, o in pairs(ESP.Objects) do
        updatePlayerESP(player, o, cam, viewport)
    end
end)

------------------------------------------------------------
-- MOVEMENT logic
------------------------------------------------------------
-- Camera-relative move vector from the game's own controls (keyboard, touch
-- joystick or gamepad). Falls back to Humanoid.MoveDirection if unavailable.
local getMoveVector = nil
pcall(function()
    local scripts = LocalPlayer:FindFirstChild("PlayerScripts")
    local moduleScript = scripts and scripts:FindFirstChild("PlayerModule")
    if moduleScript then
        local controls = require(moduleScript):GetControls()
        getMoveVector = function()
            return controls:GetMoveVector()
        end
    end
end)

connect(RunService.Heartbeat, function()
    local hum = getHumanoid()
    if hum then
        if Config.Move.WalkSpeed then
            hum.WalkSpeed = Config.Move.WalkSpeedValue
        end
        if Config.Move.Jump then
            if not hum.UseJumpPower then hum.UseJumpPower = true end
            hum.JumpPower = Config.Move.JumpValue
        end
    end

    -- Bunny hop: jump again as soon as the character lands (while moving or holding Space)
    if hum and Config.Move.BunnyHop and not Config.Move.Fly and hum.Health > 0 and not hum.Sit then
        local typing = UserInputService:GetFocusedTextBox() ~= nil
        local wantsJump = hum.MoveDirection.Magnitude > 0
            or (not typing and UserInputService:IsKeyDown(Enum.KeyCode.Space))
        if wantsJump and hum.FloorMaterial ~= Enum.Material.Air then
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end

    -- Anchor / freeze: keep the root part locked (also after a respawn)
    if Config.Move.Anchor then
        local anchorRoot = getRoot()
        if anchorRoot and not anchorRoot.Anchored then
            anchorRoot.Anchored = true
        end
    end

    -- Fly
    local root = getRoot()
    if not Config.Move.Fly or not hum or not root or hum.Health <= 0 then
        if flyBV or flyBG then stopFly() end
        return
    end

    if not flyBV or flyBV.Parent ~= root or not flyBG or flyBG.Parent ~= root then
        stopFly()

        flyBV = Instance.new("BodyVelocity")
        flyBV.MaxForce = Vector3.new(1e9, 1e9, 1e9)
        flyBV.Velocity = Vector3.new(0, 0, 0)
        flyBV.Parent = root

        flyBG = Instance.new("BodyGyro")
        flyBG.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
        flyBG.P = 1e4
        flyBG.D = 500
        flyBG.CFrame = root.CFrame
        flyBG.Parent = root
    end

    hum.PlatformStand = true

    local cam = workspace.CurrentCamera
    local dir = Vector3.new(0, 0, 0)

    local usedControls = false
    if getMoveVector then
        local ok, mv = pcall(getMoveVector)
        if ok and mv then
            dir = cam.CFrame:VectorToWorldSpace(Vector3.new(mv.X, 0, mv.Z))
            usedControls = true
        end
    end
    if not usedControls then
        dir = hum.MoveDirection
    end

    if UserInputService:GetFocusedTextBox() == nil then
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir = dir + Vector3.new(0, 1, 0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then dir = dir - Vector3.new(0, 1, 0) end
    end

    if dir.Magnitude > 0 then
        dir = dir.Unit * FLY_SPEED
    end

    flyBV.Velocity = dir
    flyBG.CFrame = CFrame.new(root.Position, root.Position + cam.CFrame.LookVector)
end)

connect(RunService.Stepped, function()
    if not Config.Move.Noclip then return end
    local char = LocalPlayer.Character
    if not char then return end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") and part.CanCollide then
            noclipParts[part] = true
            part.CanCollide = false
        end
    end
end)

------------------------------------------------------------
-- Central input handling
------------------------------------------------------------
connect(UserInputService.InputBegan, function(input, gameProcessed)
    -- 1) waiting for a new key for a key selector
    if listening then
        local newBind = nil
        local cancelled = false

        if input.UserInputType == Enum.UserInputType.Keyboard then
            if input.KeyCode == Enum.KeyCode.Escape then
                cancelled = true
            elseif input.KeyCode ~= Enum.KeyCode.Unknown then
                newBind = input.KeyCode
            end
        elseif input.UserInputType == Enum.UserInputType.MouseButton2
            or input.UserInputType == Enum.UserInputType.MouseButton3 then
            newBind = input.UserInputType
        end

        if newBind or cancelled then
            local l = listening
            listening = nil
            if cancelled then
                l.cancel()
            else
                l.set(newBind)
            end
        end
        return
    end

    -- panic key: works even if the game used the key, but not while typing in a text box
    if bindMatches(Config.UI.PanicKey, input) and UserInputService:GetFocusedTextBox() == nil then
        panic()
        return
    end

    if gameProcessed then return end

    -- 2) menu key
    if bindMatches(Config.MenuKey, input) then
        setMenuVisible(not menuOpen)
        return
    end

    -- 3) aim key
    if Config.Aim.Enabled and bindMatches(Config.Aim.Key, input) then
        if Config.Aim.Sticky then
            stickyActive = not stickyActive
            currentTarget = nil
        else
            aimHeld = true
            currentTarget = nil
        end
    end

    -- 4) fly / noclip hotkeys flip their toggles
    if flyToggle and bindMatches(Config.Move.FlyKey, input) then
        flyToggle:Set(not flyToggle.Value)
    end
    if noclipToggle and bindMatches(Config.Move.NoclipKey, input) then
        noclipToggle:Set(not noclipToggle.Value)
    end
    if bunnyToggle and bindMatches(Config.Move.BunnyHopKey, input) then
        bunnyToggle:Set(not bunnyToggle.Value)
    end
    if anchorToggle and bindMatches(Config.Move.AnchorKey, input) then
        anchorToggle:Set(not anchorToggle.Value)
    end
end)

connect(UserInputService.InputEnded, function(input)
    if bindMatches(Config.Aim.Key, input) then
        aimHeld = false
    end
end)

------------------------------------------------------------
-- Rainbow theme loop + on-screen button feedback
------------------------------------------------------------
local rainbowClock = 0

connect(RunService.Heartbeat, function(dt)
    if mobileGroup.Visible then
        aimBtn.BackgroundColor3 = aimActive() and state.accentDark or C.Surface
        flyBtn.BackgroundColor3 = Config.Move.Fly and state.accentDark or C.Surface
        noclipBtn.BackgroundColor3 = Config.Move.Noclip and state.accentDark or C.Surface
    end

    if not state.rainbow then return end
    rainbowClock = rainbowClock + dt
    if rainbowClock < 1 / 30 then return end
    rainbowClock = 0
    setAccent(Color3.fromHSV((tick() % 6) / 6, 0.7, 1))
    applyAccent()
end)

local camConn
local function watchCamera()
    if camConn then camConn:Disconnect() camConn = nil end
    local cam = workspace.CurrentCamera
    if cam then
        camConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(layoutMain)
        table.insert(connections, camConn)
    end
end
watchCamera()
connect(workspace:GetPropertyChangedSignal("CurrentCamera"), function()
    watchCamera()
    layoutMain()
end)

------------------------------------------------------------
-- Cleanup / unload
------------------------------------------------------------
local function cleanup()
    state.rainbow = false

    for _, c in ipairs(connections) do
        pcall(function() c:Disconnect() end)
    end
    connections = {}

    pcall(function() RunService:UnbindFromRenderStep("OrbitHubAim") end)

    for player in pairs(ESP.Objects) do
        removeESP(player)
    end

    stopFly()
    restoreNoclip()
    stopAnchor()
    clearMarkers()

    local hum = getHumanoid()
    if hum then
        if Config.Move.WalkSpeed then hum.WalkSpeed = defaultWalkSpeed end
        if Config.Move.Jump then hum.JumpPower = defaultJumpPower end
    end
    Config.Move.WalkSpeed = false
    Config.Move.Jump = false
    Config.Move.Fly = false
    Config.Move.Noclip = false
    Config.Move.BunnyHop = false
    Config.Move.Anchor = false
    Config.Move.ShowWaypoints = false
    Config.Aim.Enabled = false

    pcall(function() screenGui:Destroy() end)
    pcall(function() espGui:Destroy() end)

    env.OrbitHubCleanup = nil
end

unloadAll = cleanup
env.OrbitHubCleanup = cleanup

------------------------------------------------------------
-- Init
------------------------------------------------------------
applyAccent()
setTab("Aimbot")

if not mountGui(screenGui) then
    warn("[Orbit Hub] Could not parent the GUI to any container.")
end
mountGui(espGui)
