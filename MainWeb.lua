--// ================= SERVICES =================
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Players          = game:GetService("Players")
local CoreGui          = game:GetService("CoreGui")
local HttpService      = game:GetService("HttpService")
local RunService       = game:GetService("RunService")
local TeleportService  = game:GetService("TeleportService")
local Workspace        = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

--// ================= CLEANUP PREVIOUS INSTANCE =================
if CoreGui:FindFirstChild("ElyseraUI") then
    CoreGui.ElyseraUI:Destroy()
end
if CoreGui:FindFirstChild("ElyseraCover") then
    CoreGui.ElyseraCover:Destroy()
end

--// ================= THEME =================
local Theme = {
    Background     = Color3.fromRGB(29, 21, 52),    -- #1D1534 main background
    Panel          = Color3.fromRGB(33, 21, 58),    -- #21153A cards, buttons, dialogs
    PanelAlt       = Color3.fromRGB(37, 25, 66),    -- #251942 sidebar, tab / function panels
    Header         = Color3.fromRGB(49, 32, 75),    -- #31204B top bar, highlight tab
    Border         = Color3.fromRGB(84, 53, 128),   -- #543580 purple border
    AccentPink     = Color3.fromRGB(243, 99, 225),  -- #F363E1 primary accent
    AccentPurple   = Color3.fromRGB(175, 88, 249),  -- #AF58F9 neon purple
    Sakura         = Color3.fromRGB(255, 183, 213), -- #FFB7D5 selected tab text
    Text           = Color3.fromRGB(226, 190, 250), -- #E2BEFA primary text
    SubText        = Color3.fromRGB(191, 157, 238), -- #BF9DEE secondary text
    Danger         = Color3.fromRGB(247, 118, 142), -- #F7768E close / danger
    ToggleTrackOff = Color3.fromRGB(71, 48, 112),   -- #473070 switch track (off)
    ToggleKnobOn   = Color3.fromRGB(255, 255, 255), -- #FFFFFF switch knob (on)
}

--// ================= CONFIG =================
local UI_NAME             = "Elysera"
local UI_W, UI_H          = 650, 420
local MIN_UI_W, MIN_UI_H  = 420, 260
local TOGGLE_SIZE         = 50
local POPUP_TIME          = 0.25
local CLOSE_TIME          = 0.20
local TOPBAR_HEIGHT       = 40
local SAVE_FILE           = "Elysera_Settings.json"
local SAVE_DELAY          = 0.3

local MARGIN_EDGE         = 8
local MARGIN_GAP          = 10
local TAB_PANEL_WIDTH     = 150
local HIGHLIGHT_HEIGHT    = 56
local HIGHLIGHT_GAP       = 8

local CENTER        = UDim2.fromScale(0.5, 0.5)
local ANCHOR_CENTER = Vector2.new(0.5, 0.5)
local EASE_QUAD     = Enum.EasingStyle.Quad
local EASE_QUINT    = Enum.EasingStyle.Quint
local EASE_BACK     = Enum.EasingStyle.Back
local EASE_LINEAR   = Enum.EasingStyle.Linear
local DIR_IN        = Enum.EasingDirection.In
local DIR_OUT       = Enum.EasingDirection.Out

local uiLocked = false

--// ================= ROOT =================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "ElyseraUI"
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.ResetOnSpawn = false
ScreenGui.DisplayOrder = 10
ScreenGui.Parent = CoreGui

--// ================= UTILITY =================
local Connections = {}
local function track(conn)
    Connections[#Connections + 1] = conn
    return conn
end

ScreenGui.Destroying:Connect(function()
    for _, c in ipairs(Connections) do c:Disconnect() end
end)

local function new(class, props, parent)
    local inst = Instance.new(class)
    for k, v in pairs(props) do inst[k] = v end
    inst.Parent = parent
    return inst
end

local function corner(inst, radius)
    return new("UICorner", { CornerRadius = UDim.new(0, radius or 8) }, inst)
end

local function stroke(inst, color, thickness)
    return new("UIStroke", { Color = color or Theme.Border, Thickness = thickness or 1 }, inst)
end

local function padding(inst, left, right, top, bottom)
    return new("UIPadding", {
        PaddingLeft   = UDim.new(0, left or 0),
        PaddingRight  = UDim.new(0, right or 0),
        PaddingTop    = UDim.new(0, top or 0),
        PaddingBottom = UDim.new(0, bottom or 0),
    }, inst)
end

local function list(inst, gap, props)
    props = props or {}
    props.SortOrder = Enum.SortOrder.LayoutOrder
    props.Padding = UDim.new(0, gap or 0)
    return new("UIListLayout", props, inst)
end

local function label(parent, props)
    props.BackgroundTransparency = 1
    props.Font = props.Font or Enum.Font.GothamBold
    return new("TextLabel", props, parent)
end

local function tween(inst, time, props, style, dir)
    local t = TweenService:Create(inst, TweenInfo.new(time, style or EASE_QUAD, dir or DIR_OUT), props)
    t:Play()
    return t
end

local function isPress(input)
    return input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
end

local function isMove(input)
    return input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch
end

local function makeDraggable(handle, target, onEnd, onClick, threshold)
    threshold = threshold or 0
    local dragging, moved, dragStart, startPos

    handle.InputBegan:Connect(function(input)
        if uiLocked or not isPress(input) then return end
        dragging, moved = true, false
        dragStart, startPos = input.Position, target.Position

        input.Changed:Connect(function()
            if input.UserInputState ~= Enum.UserInputState.End then return end
            if dragging then
                if moved then
                    if onEnd then onEnd() end
                elseif onClick and not uiLocked then
                    onClick()
                end
            end
            dragging = false
        end)
    end)

    track(UserInputService.InputChanged:Connect(function(input)
        if uiLocked then dragging = false return end
        if not dragging or not isMove(input) then return end
        local delta = input.Position - dragStart
        if not moved and delta.Magnitude > threshold then moved = true end
        if moved then
            target.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end))
end

local function pressScale(btn, downScale)
    local scale = new("UIScale", {}, btn)
    local function release()
        tween(scale, 0.2, { Scale = 1 }, EASE_BACK, DIR_OUT)
    end
    btn.MouseButton1Down:Connect(function()
        if uiLocked then return end
        tween(scale, 0.08, { Scale = downScale })
    end)
    btn.MouseButton1Up:Connect(release)
    btn.MouseLeave:Connect(release)
end

--// ================= SAVED SETTINGS (position / size) =================
local canFS = typeof(writefile) == "function"
    and typeof(readfile) == "function"
    and typeof(isfile) == "function"

local function num(v, default)
    return (type(v) == "number" and v == v and math.abs(v) < 1e6) and v or default
end

local function getViewport()
    local camera = Workspace.CurrentCamera
    return camera and camera.ViewportSize or Vector2.new(1280, 720)
end

local function loadSettings()
    if not canFS then return {} end
    local ok, data = pcall(function()
        if isfile(SAVE_FILE) then
            return HttpService:JSONDecode(readfile(SAVE_FILE))
        end
    end)
    return (ok and type(data) == "table") and data or {}
end

local Saved = loadSettings()
local viewport0 = getViewport()

local curW = math.clamp(num(Saved.w, UI_W), MIN_UI_W, math.max(MIN_UI_W, viewport0.X))
local curH = math.clamp(num(Saved.h, UI_H), MIN_UI_H, math.max(MIN_UI_H, viewport0.Y))

local maxOffX = math.max(0, (viewport0.X - curW) / 2)
local maxOffY = math.max(0, (viewport0.Y - curH) / 2)
local uiPosition = UDim2.new(
    0.5, math.clamp(num(Saved.uiX, 0), -maxOffX, maxOffX),
    0.5, math.clamp(num(Saved.uiY, 0), -maxOffY, maxOffY)
)

local DEFAULT_TOGGLE_POS = UDim2.new(0, 20, 0.5, -TOGGLE_SIZE / 2)
local togglePosition = DEFAULT_TOGGLE_POS
if type(Saved.toggle) == "table" then
    local xs, xo = num(Saved.toggle[1], 0), num(Saved.toggle[2], 20)
    local ys, yo = num(Saved.toggle[3], 0.5), num(Saved.toggle[4], -TOGGLE_SIZE / 2)
    local absX = viewport0.X * xs + xo
    local absY = viewport0.Y * ys + yo
    xo += math.clamp(absX, 0, math.max(0, viewport0.X - TOGGLE_SIZE)) - absX
    yo += math.clamp(absY, 0, math.max(0, viewport0.Y - TOGGLE_SIZE)) - absY
    togglePosition = UDim2.new(xs, xo, ys, yo)
end

local ToggleButton
local saveQueued = false
local function saveSettings()
    if not canFS or saveQueued then return end
    saveQueued = true
    task.delay(SAVE_DELAY, function()
        saveQueued = false
        local t = ToggleButton and ToggleButton.Position or togglePosition
        local data = {
            w = curW, h = curH,
            uiX = uiPosition.X.Offset, uiY = uiPosition.Y.Offset,
            toggle = { t.X.Scale, t.X.Offset, t.Y.Scale, t.Y.Offset },
            fpsMode = ScreenGui:GetAttribute("FpsMode"), -- mode FPS Profile đã chọn (không tự áp khi nạp)
        }
        pcall(writefile, SAVE_FILE, HttpService:JSONEncode(data))
    end)
end

--// ================= FLOATING TOGGLE BUTTON =================
ToggleButton = new("TextButton", {
    Name = "MG_Toggle",
    Size = UDim2.fromOffset(TOGGLE_SIZE, TOGGLE_SIZE),
    Position = togglePosition,
    BackgroundColor3 = Theme.Panel,
    Text = "",
    AutoButtonColor = false,
}, ScreenGui)
corner(ToggleButton, 14)
stroke(ToggleButton)

do
    local ICON_PX = 32
    local unit = ICON_PX / 48
    local V = Vector2.new

    local Holder = new("Frame", {
        Name = "Icon",
        AnchorPoint = ANCHOR_CENTER,
        Position = CENTER,
        Size = UDim2.fromOffset(ICON_PX, ICON_PX),
        BackgroundTransparency = 1,
    }, ToggleButton)

    local function segment(a, b, thick, color)
        local d, mid = b - a, (a + b) / 2
        corner(new("Frame", {
            AnchorPoint = ANCHOR_CENTER,
            Position = UDim2.fromOffset(mid.X, mid.Y),
            Size = UDim2.fromOffset(d.Magnitude + thick, thick),
            Rotation = math.deg(math.atan2(d.Y, d.X)),
            BackgroundColor3 = color,
            BorderSizePixel = 0,
        }, Holder), thick / 2)
    end

    local function roundPath(pts, r)
        if r <= 0 or #pts < 3 then return pts end
        local out = { pts[1] }
        for i = 2, #pts - 1 do
            local P, A, B = pts[i], pts[i - 1], pts[i + 1]
            local p1 = P + (A - P).Unit * r
            local p2 = P + (B - P).Unit * r
            for step = 0, 5 do
                local t = step / 5
                table.insert(out, p1:Lerp(P, t):Lerp(P:Lerp(p2, t), t))
            end
        end
        table.insert(out, pts[#pts])
        return out
    end

    local function drawPath(pts, radius, width, color, inner)
        pts = roundPath(pts, radius)
        local mapped = {}
        for i, p in ipairs(pts) do
            if inner then p = p * 0.55 + V(10.8, 10.8) end
            mapped[i] = p * unit
        end
        local thick = (inner and width * 0.55 or width) * unit
        for i = 1, #mapped - 1 do
            segment(mapped[i], mapped[i + 1], thick, color)
        end
    end

    local F, S = Theme.AccentPurple, Theme.AccentPink

    drawPath({ V(4, 34), V(4, 44), V(14, 44) }, 0, 4, F)
    drawPath({ V(34, 44), V(44, 44), V(44, 34) }, 0, 4, F)
    drawPath({ V(34, 4), V(44, 4), V(44, 14) }, 0, 4, F)
    drawPath({ V(14, 4), V(4, 4), V(4, 14) }, 0, 4, F)

    drawPath({ V(20, 15), V(24, 19), V(28, 15) }, 0, 6, S, true)
    drawPath({ V(24, 19), V(24, 4), V(44, 4), V(44, 19) }, 4, 6, S, true)
    drawPath({ V(28, 33), V(24, 29), V(20, 33) }, 0, 6, S, true)
    drawPath({ V(24, 29), V(24, 44), V(4, 44), V(4, 29) }, 4, 6, S, true)
    drawPath({ V(33, 20), V(29, 24), V(33, 28) }, 0, 6, S, true)
    drawPath({ V(29, 24), V(44, 24), V(44, 44), V(29, 44) }, 4, 6, S, true)
    drawPath({ V(15, 28), V(19, 24), V(15, 20) }, 0, 6, S, true)
    drawPath({ V(19, 24), V(4, 24), V(4, 4), V(19, 4) }, 4, 6, S, true)
end

--// ================= MAIN WINDOW =================
local MainUI = new("CanvasGroup", {
    Name = "MG_Main",
    AnchorPoint = ANCHOR_CENTER,
    Position = uiPosition,
    Size = UDim2.fromOffset(curW, curH),
    GroupTransparency = 1,
    BackgroundColor3 = Theme.Background,
    BorderSizePixel = 0,
    ClipsDescendants = true,
    Visible = false,
}, ScreenGui)
corner(MainUI, 12)
local MainUIStroke = stroke(MainUI)

--// ---- Top bar ----
local TopBar = new("Frame", {
    Name = "TopBar",
    Size = UDim2.new(1, 0, 0, TOPBAR_HEIGHT),
    BackgroundColor3 = Theme.Header,
    BorderSizePixel = 0,
    Active = true,
}, MainUI)
corner(TopBar, 12)

new("Frame", {
    Size = UDim2.new(1, 0, 0, 12),
    Position = UDim2.new(0, 0, 1, -12),
    BackgroundColor3 = Theme.Header,
    BorderSizePixel = 0,
}, TopBar)

new("Frame", {
    Size = UDim2.new(1, 0, 0, 2),
    Position = UDim2.new(0, 0, 1, -2),
    BackgroundColor3 = Theme.AccentPink,
    BorderSizePixel = 0,
    ZIndex = 2,
}, TopBar)

label(TopBar, {
    Size = UDim2.new(1, -180, 1, 0),
    Position = UDim2.fromOffset(16, 0),
    Text = UI_NAME,
    TextSize = 18,
    TextColor3 = Theme.AccentPink,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 2,
})

--// ---- Topbar icons ----
local TOPBAR_BTN_SIZE   = 26
local TOPBAR_BTN_GAP    = 6
local TOPBAR_BTN_MARGIN = 8
local ICON_SIZE         = 14

local function iconBar(holder, w, h, color, rotation)
    return corner(new("Frame", {
        AnchorPoint = ANCHOR_CENTER,
        Position = CENTER,
        Size = UDim2.fromOffset(w, h),
        Rotation = rotation or 0,
        BackgroundColor3 = color,
        BorderSizePixel = 0,
    }, holder), 1)
end

local function iconBox(holder, size, color, radius, thickness, pos, fill)
    local f = new("Frame", {
        AnchorPoint = ANCHOR_CENTER,
        Position = pos or CENTER,
        Size = UDim2.fromOffset(size, size),
        BackgroundColor3 = fill,
        BackgroundTransparency = fill and 0 or 1,
        BorderSizePixel = 0,
    }, holder)
    corner(f, radius)
    stroke(f, color, thickness)
end

local Icons = {}

function Icons.minimize(h, c)
    iconBar(h, ICON_SIZE, 1.5, c)
end

function Icons.maximize(h, c)
    iconBox(h, ICON_SIZE, c, 3, 1.4)
end

function Icons.restore(h, c, bg)
    iconBox(h, ICON_SIZE - 4, c, 2, 1.3, UDim2.new(0.5, 2, 0.5, -2), bg)
    iconBox(h, ICON_SIZE - 4, c, 2, 1.3, UDim2.new(0.5, -2, 0.5, 2), bg)
end

function Icons.close(h, c)
    iconBar(h, ICON_SIZE + 2, 1.5, c, 45)
    iconBar(h, ICON_SIZE + 2, 1.5, c, -45)
end

function Icons.resize(h, c)
    iconBox(h, ICON_SIZE, c, 3, 1.4)
    iconBar(h, ICON_SIZE * 0.95, 1.5, c, -45)
end

function Icons.reset(h, c)
    local Ring = new("Frame", {
        AnchorPoint = ANCHOR_CENTER,
        Position = CENTER,
        Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE),
        BackgroundTransparency = 1,
    }, h)
    corner(Ring, 100)
    new("UIGradient", {
        Rotation = 45,
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0.00, 1),
            NumberSequenceKeypoint.new(0.22, 1),
            NumberSequenceKeypoint.new(0.23, 0),
            NumberSequenceKeypoint.new(1.00, 0),
        }),
    }, stroke(Ring, c, 1.5))

    for _, r in ipairs({
        { UDim2.fromOffset(0, 0),   UDim2.fromOffset(1.5, 5) },
        { UDim2.fromOffset(0, 3.5), UDim2.fromOffset(5, 1.5) },
    }) do
        corner(new("Frame", {
            Position = r[1], Size = r[2],
            BackgroundColor3 = c, BorderSizePixel = 0,
        }, h), 1)
    end
end

-- Icon vẽ theo SVG (viewBox 48x48, nét 4, đầu/khớp bo tròn)
local function svgStroke(h, pts, color, closed)
    local unit  = h.Size.X.Offset / 48
    local thick = 4 * unit
    local n = #pts
    for i = 1, closed and n or n - 1 do
        local a, b = pts[i] * unit, pts[i % n + 1] * unit
        local d, mid = b - a, (a + b) / 2
        corner(new("Frame", {
            AnchorPoint = ANCHOR_CENTER,
            Position = UDim2.fromOffset(mid.X, mid.Y),
            Size = UDim2.fromOffset(d.Magnitude + thick, thick),
            Rotation = math.deg(math.atan2(d.Y, d.X)),
            BackgroundColor3 = color,
            BorderSizePixel = 0,
        }, h), thick / 2)
    end
end

function Icons.delete(h, c)
    local V = Vector2.new
    svgStroke(h, { V(8, 8), V(40, 40) }, c)
    svgStroke(h, { V(8, 40), V(40, 8) }, c)
end

function Icons.play(h, c)
    local V = Vector2.new
    svgStroke(h, {
        V(15, 24), V(15, 11.876), V(25.5, 17.938),
        V(36, 24), V(25.5, 30.062), V(15, 36.124),
    }, c, true)
end

local function drawIcon(holder, kind, color, bgColor)
    holder:ClearAllChildren()
    Icons[kind](holder, color, bgColor)
end

local function createTopbarButton(kind, order, iconColor)
    iconColor = iconColor or Theme.Text
    local xOffset = -(TOPBAR_BTN_MARGIN + TOPBAR_BTN_SIZE * order + TOPBAR_BTN_GAP * (order - 1))

    local Btn = new("TextButton", {
        Size = UDim2.fromOffset(TOPBAR_BTN_SIZE, TOPBAR_BTN_SIZE),
        Position = UDim2.new(1, xOffset, 0.5, -TOPBAR_BTN_SIZE / 2),
        BackgroundColor3 = Theme.PanelAlt,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 2,
    }, TopBar)
    corner(Btn, 6)

    local IconHolder = new("Frame", {
        Name = "Icon",
        AnchorPoint = ANCHOR_CENTER,
        Position = CENTER,
        Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE),
        BackgroundTransparency = 1,
        ZIndex = 3,
    }, Btn)

    drawIcon(IconHolder, kind, iconColor, Theme.PanelAlt)
    return Btn, IconHolder
end

local CloseBtn                     = createTopbarButton("close", 1, Theme.Danger)
local MaximizeBtn, MaximizeIcon    = createTopbarButton("maximize", 2)
local MinimizeBtn                  = createTopbarButton("minimize", 3)
local ResizeBtn, ResizeIcon        = createTopbarButton("resize", 4)
local ResetBtn                     = createTopbarButton("reset", 5)

--// ---- Body ----
local Body = new("Frame", {
    Name = "Body",
    Size = UDim2.new(1, 0, 1, -TOPBAR_HEIGHT),
    Position = UDim2.fromOffset(0, TOPBAR_HEIGHT),
    BackgroundTransparency = 1,
}, MainUI)

local FunctionPanel = new("Frame", {
    Name = "FunctionPanel",
    Position = UDim2.fromOffset(MARGIN_EDGE + TAB_PANEL_WIDTH + MARGIN_GAP, MARGIN_EDGE),
    Size = UDim2.new(1, -(MARGIN_EDGE + TAB_PANEL_WIDTH + MARGIN_GAP + MARGIN_EDGE), 1, -(MARGIN_EDGE * 2)),
    BackgroundColor3 = Theme.PanelAlt,
    BorderSizePixel = 0,
}, Body)
corner(FunctionPanel, 8)
stroke(FunctionPanel)

local FunctionScroll = new("ScrollingFrame", {
    Name = "FunctionScroll",
    Size = UDim2.new(1, -8, 1, -8),
    Position = UDim2.fromOffset(4, 4),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 5,
    ScrollBarImageColor3 = Theme.AccentPink,
    CanvasSize = UDim2.new(),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, FunctionPanel)
list(FunctionScroll, 10)
padding(FunctionScroll, 4, 4)

local TabColumn = new("Frame", {
    Name = "TabColumn",
    Position = UDim2.fromOffset(MARGIN_EDGE, MARGIN_EDGE),
    Size = UDim2.new(0, TAB_PANEL_WIDTH, 1, -(MARGIN_EDGE * 2)),
    BackgroundTransparency = 1,
}, Body)

local TabPanel = new("Frame", {
    Name = "TabPanel",
    Size = UDim2.new(1, 0, 1, -(HIGHLIGHT_HEIGHT + HIGHLIGHT_GAP)),
    BackgroundColor3 = Theme.PanelAlt,
    BorderSizePixel = 0,
}, TabColumn)
corner(TabPanel, 8)
stroke(TabPanel)

local TabScroll = new("ScrollingFrame", {
    Name = "TabScroll",
    Size = UDim2.new(1, -8, 1, -8),
    Position = UDim2.fromOffset(4, 4),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 4,
    ScrollBarImageColor3 = Theme.AccentPink,
    CanvasSize = UDim2.new(),
}, TabPanel)
padding(TabScroll, 3, 3, 3, 3)

--// ---- Highlight tab (player info) ----
local HighlightTab = new("Frame", {
    Name = "HighlightTab",
    AnchorPoint = Vector2.new(0, 1),
    Position = UDim2.fromScale(0, 1),
    Size = UDim2.new(1, 0, 0, HIGHLIGHT_HEIGHT),
    BackgroundColor3 = Theme.Header,
    BorderSizePixel = 0,
}, TabColumn)
corner(HighlightTab, 8)

do
    local HighlightStroke = stroke(HighlightTab, Theme.AccentPurple, 2)
    local Gradient = new("UIGradient", {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0.00, 1),
            NumberSequenceKeypoint.new(0.04, 0),
            NumberSequenceKeypoint.new(0.14, 0),
            NumberSequenceKeypoint.new(0.20, 1),
            NumberSequenceKeypoint.new(0.50, 1),
            NumberSequenceKeypoint.new(0.54, 0),
            NumberSequenceKeypoint.new(0.64, 0),
            NumberSequenceKeypoint.new(0.70, 1),
            NumberSequenceKeypoint.new(1.00, 1),
        }),
    }, HighlightStroke)
    TweenService:Create(Gradient, TweenInfo.new(2, EASE_LINEAR, DIR_IN, -1), { Rotation = 360 }):Play()

    local Avatar = new("ImageLabel", {
        Size = UDim2.fromOffset(32, 32),
        Position = UDim2.new(0, 8, 0.5, -16),
        BackgroundColor3 = Theme.Panel,
        ScaleType = Enum.ScaleType.Crop,
        ZIndex = 2,
    }, HighlightTab)
    corner(Avatar, 16)
    stroke(Avatar)

    local TextHolder = new("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 48, 0.5, 0),
        Size = UDim2.new(1, -56, 0, 32),
        BackgroundTransparency = 1,
        ZIndex = 2,
    }, HighlightTab)
    list(TextHolder, 0, { VerticalAlignment = Enum.VerticalAlignment.Center })

    label(TextHolder, {
        LayoutOrder = 1,
        Size = UDim2.new(1, 0, 0, 18),
        Text = LocalPlayer.DisplayName,
        TextSize = 13,
        TextColor3 = Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ZIndex = 2,
    })
    label(TextHolder, {
        LayoutOrder = 2,
        Size = UDim2.new(1, 0, 0, 14),
        Text = "@" .. LocalPlayer.Name,
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextColor3 = Theme.SubText,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ZIndex = 2,
    })

    task.spawn(function()
        local ok, content = pcall(Players.GetUserThumbnailAsync, Players,
            LocalPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
        if ok and content then Avatar.Image = content end
    end)
end

--// ================= DRAG SUPPORT =================
local isMaximized = false

local function commitUIState()
    if isMaximized then return end
    local p = MainUI.Position
    uiPosition = UDim2.new(0.5, p.X.Offset, 0.5, p.Y.Offset)
    curW, curH = MainUI.Size.X.Offset, MainUI.Size.Y.Offset
    saveSettings()
end

makeDraggable(TopBar, MainUI, commitUIState)

local OVERLAY_TRANSPARENCY = 0.45 -- 0 = đen đặc, 1 = trong suốt hoàn toàn

local InteractionBlocker = new("Frame", {
    Name = "InteractionBlocker",
    Size = UDim2.fromScale(1, 1),
    BackgroundColor3 = Color3.new(0, 0, 0),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Active = true,
    Visible = false,
    ZIndex = 20,
}, MainUI)

--// ================= DIALOGS =================
local DIALOG_SIZE     = UDim2.fromOffset(310, 160)
local BUBBLE_IN_TIME  = 0.3
local FADE_IN_TIME    = BUBBLE_IN_TIME * 2
local BUBBLE_OUT_TIME = BUBBLE_IN_TIME * 0.7
local FADE_OUT_TIME   = BUBBLE_OUT_TIME / 3

local WHITE = Color3.new(1, 1, 1)
local overlayTween

local function setOverlay(on)
    if overlayTween then overlayTween:Cancel() end
    if on then
        InteractionBlocker.Visible = true
        overlayTween = tween(InteractionBlocker, FADE_IN_TIME, { BackgroundTransparency = OVERLAY_TRANSPARENCY }, EASE_QUAD, DIR_OUT)
    else
        overlayTween = tween(InteractionBlocker, BUBBLE_OUT_TIME, { BackgroundTransparency = 1 }, EASE_QUAD, DIR_IN)
        overlayTween.Completed:Connect(function(state)
            if state == Enum.PlaybackState.Completed then
                InteractionBlocker.Visible = false
            end
        end)
    end
end

local function createDialog(name, title, message, yesColor, yesText, noText)
    local Box = new("CanvasGroup", {
        Name = name,
        Visible = false,
        AnchorPoint = ANCHOR_CENTER,
        Position = CENTER,
        Size = UDim2.new(),
        BackgroundColor3 = Theme.Panel,
        BorderSizePixel = 0,
        GroupTransparency = 1,
        ZIndex = 51,
    }, ScreenGui)
    corner(Box, 12)

    -- nền chuyển sắc nhẹ: PanelAlt (trên) -> Panel (dưới)
    -- (đặt trên Frame riêng, vì UIGradient trên CanvasGroup sẽ nhuộm luôn cả chữ và nút bên trong)
    Box.BackgroundTransparency = 1
    local Bg = new("Frame", {
        Name = "Bg",
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = WHITE,
        BorderSizePixel = 0,
        ZIndex = 51,
    }, Box)
    corner(Bg, 12)
    new("UIGradient", {
        Color = ColorSequence.new(Theme.PanelAlt, Theme.Panel),
        Rotation = 90,
    }, Bg)

    -- viền gradient tím -> màu nhấn của hộp
    local BoxStroke = stroke(Box, WHITE, 1.5)
    new("UIGradient", {
        Color = ColorSequence.new(Theme.AccentPurple, yesColor),
        Rotation = 45,
    }, BoxStroke)

    -- thanh accent phía trên
    local Accent = new("Frame", {
        Size = UDim2.new(1, 0, 0, 3),
        BackgroundColor3 = WHITE,
        BorderSizePixel = 0,
        ZIndex = 52,
    }, Box)
    new("UIGradient", {
        Color = ColorSequence.new(Theme.AccentPurple, yesColor),
    }, Accent)

    -- tiêu đề
    label(Box, {
        Size = UDim2.new(1, -32, 0, 20),
        Position = UDim2.fromOffset(16, 16),
        Text = string.upper(title),
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = Theme.Sakura,
        ZIndex = 52,
    })

    -- nội dung
    local MessageLabel = label(Box, {
        Size = UDim2.new(1, -32, 0, 44),
        Position = UDim2.fromOffset(16, 40),
        Text = message,
        TextSize = 16,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        TextColor3 = Theme.Text,
        ZIndex = 52,
    })

    -- đường kẻ phân cách
    new("Frame", {
        Size = UDim2.new(1, -32, 0, 1),
        Position = UDim2.new(0, 16, 1, -60),
        BackgroundColor3 = Theme.Border,
        BackgroundTransparency = 0.5,
        BorderSizePixel = 0,
        ZIndex = 52,
    }, Box)

    local function button(text, pos, bg, textColor, outlined)
        local Btn = new("TextButton", {
            Size = UDim2.new(0.5, -22, 0, 34),
            Position = pos,
            BackgroundColor3 = bg,
            Text = text,
            Font = Enum.Font.GothamBold,
            TextSize = 14,
            TextColor3 = textColor,
            AutoButtonColor = false,
            ZIndex = 52,
        }, Box)
        corner(Btn, 8)
        local S = outlined and stroke(Btn, Theme.Border, 1) or nil
        pressScale(Btn, 0.95)

        Btn.MouseEnter:Connect(function()
            if outlined then
                tween(Btn, 0.15, { BackgroundColor3 = Theme.Header, TextColor3 = Theme.Sakura })
                if S then tween(S, 0.15, { Color = Theme.AccentPurple }) end
            else
                tween(Btn, 0.15, { BackgroundColor3 = bg:Lerp(WHITE, 0.15) })
            end
        end)
        Btn.MouseLeave:Connect(function()
            if outlined then
                tween(Btn, 0.15, { BackgroundColor3 = bg, TextColor3 = textColor })
                if S then tween(S, 0.15, { Color = Theme.Border }) end
            else
                tween(Btn, 0.15, { BackgroundColor3 = bg })
            end
        end)
        return Btn
    end

    local Yes = button(yesText or "Yes", UDim2.new(0, 16, 1, -46), yesColor, Theme.Background)
    local No  = button(noText or "No", UDim2.new(1, -16, 1, -46), Theme.PanelAlt, Theme.Text, true)
    No.AnchorPoint = Vector2.new(1, 0)

    local hideToken = 0

    local function show()
        hideToken += 1
        setOverlay(true)
        Box.Visible = true
        Box.GroupTransparency = 1
        Box.Size = UDim2.new()
        tween(Box, BUBBLE_IN_TIME, { Size = DIALOG_SIZE }, EASE_QUAD, DIR_OUT)
        tween(Box, FADE_IN_TIME, { GroupTransparency = 0 }, EASE_QUAD, DIR_OUT)
    end

    local function hide()
        hideToken += 1
        local token = hideToken
        setOverlay(false)
        local sizeTween = tween(Box, BUBBLE_OUT_TIME, { Size = UDim2.new() }, EASE_QUAD, DIR_IN)
        tween(Box, FADE_OUT_TIME, { GroupTransparency = 1 }, EASE_QUAD, DIR_IN)
        sizeTween.Completed:Connect(function(state)
            if state ~= Enum.PlaybackState.Completed or token ~= hideToken then return end
            Box.Visible = false
        end)
    end

    No.MouseButton1Click:Connect(hide)
    return { Box = Box, Yes = Yes, Message = MessageLabel, show = show, hide = hide }
end

local CloseDialog = createDialog("ConfirmBox", "Close script", "You want to close this script?", Theme.Danger)
local ResetDialog = createDialog("NotBox2", "Reset UI", "Do you want to reset UI?", Theme.AccentPink)
-- NotBoxDe (tab Script): xác nhận xoá function, nội dung được gán lại mỗi lần mở
local DeleteDialog = createDialog("NotBoxDe", "Delete function", "Do you want to delete this function?", Theme.Danger, "Yes, Delete", "Cancel")

--// ================= OPEN / CLOSE ANIMATION =================
local isOpen = false
local fadeTween
local ScriptDialog -- NotBoxA (tab Script), được tạo ở phần SCRIPT TAB

local function fadeMainUI(time, target, dir)
    if fadeTween then fadeTween:Cancel() end
    fadeTween = tween(MainUI, time, { GroupTransparency = target }, EASE_QUAD, dir)
    return fadeTween
end

local function openUI()
    isOpen = true
    MainUI.Visible = true
    fadeMainUI(POPUP_TIME, 0, DIR_OUT)
end

local function closeUI()
    isOpen = false
    if CloseDialog.Box.Visible then CloseDialog.hide() end
    if ResetDialog.Box.Visible then ResetDialog.hide() end
    if DeleteDialog.Box.Visible then DeleteDialog.hide() end
    if ScriptDialog and ScriptDialog.Box.Visible then ScriptDialog.hide() end
    fadeMainUI(CLOSE_TIME, 1, DIR_IN).Completed:Connect(function(state)
        if state == Enum.PlaybackState.Completed and not isOpen then
            MainUI.Visible = false
        end
    end)
end

makeDraggable(ToggleButton, ToggleButton, saveSettings, function()
    if isOpen then closeUI() else openUI() end
end, 5)

--// ---- Minimize ----
MinimizeBtn.MouseButton1Click:Connect(function()
    if uiLocked then return end
    if isOpen then closeUI() end
end)

--// ---- Maximize / Restore ----
local preMaxSize, preMaxPos

local function toggleMaximize()
    if isMaximized then
        isMaximized = false
        drawIcon(MaximizeIcon, "maximize", Theme.Text, Theme.PanelAlt)
        tween(MainUI, 0.25, { Size = preMaxSize, Position = preMaxPos }, EASE_QUAD, DIR_OUT)
    else
        preMaxSize, preMaxPos = MainUI.Size, MainUI.Position
        isMaximized = true
        drawIcon(MaximizeIcon, "restore", Theme.Text, Theme.PanelAlt)
        local viewport = getViewport()
        tween(MainUI, 0.25, {
            Size = UDim2.fromOffset(viewport.X, viewport.Y),
            Position = CENTER,
        }, EASE_QUAD, DIR_OUT)
    end
end

MaximizeBtn.MouseButton1Click:Connect(function()
    if uiLocked then return end
    toggleMaximize()
end)

--// ---- Close ----
CloseBtn.MouseButton1Click:Connect(function()
    if uiLocked then return end
    CloseDialog.show()
end)
CloseDialog.Yes.MouseButton1Click:Connect(function()
    ScreenGui:Destroy()
end)

--// ---- Reset ----
local function resetLayout()
    if isMaximized then
        isMaximized = false
        drawIcon(MaximizeIcon, "maximize", Theme.Text, Theme.PanelAlt)
    end

    curW, curH = UI_W, UI_H
    uiPosition = CENTER

    local props = { Position = uiPosition }
    if isOpen then props.Size = UDim2.fromOffset(curW, curH) end
    tween(MainUI, 0.2, props, EASE_QUAD, DIR_OUT)
    tween(ToggleButton, 0.2, { Position = DEFAULT_TOGGLE_POS }, EASE_QUAD, DIR_OUT)

    saveSettings()
end

ResetBtn.MouseButton1Click:Connect(function()
    if uiLocked then return end
    ResetDialog.show()
end)
ResetDialog.Yes.MouseButton1Click:Connect(function()
    resetLayout()
    ResetDialog.hide()
end)

--// ================= RESIZE MODE =================
local RESIZE_HANDLE_SIZE = 18
local resizeMode = false
local resizeDragCorner
local resizeFixedX, resizeFixedY = 0, 0

local CORNER_ANCHORS = {
    TL = Vector2.new(0, 0),
    TR = Vector2.new(1, 0),
    BL = Vector2.new(0, 1),
    BR = Vector2.new(1, 1),
}
local ResizeHandles = {}

local function updateResizeHandlePositions()
    local pos, size = MainUI.AbsolutePosition, MainUI.AbsoluteSize
    for cornerName, handle in pairs(ResizeHandles) do
        local a = CORNER_ANCHORS[cornerName]
        handle.Position = UDim2.fromOffset(pos.X + size.X * a.X, pos.Y + size.Y * a.Y)
    end
end

for cornerName, anchor in pairs(CORNER_ANCHORS) do
    local Handle = new("Frame", {
        Name = "ResizeHandle",
        AnchorPoint = ANCHOR_CENTER,
        Size = UDim2.fromOffset(RESIZE_HANDLE_SIZE, RESIZE_HANDLE_SIZE),
        BackgroundColor3 = Theme.AccentPink,
        BorderSizePixel = 0,
        Visible = false,
        Active = true,
        ZIndex = 100,
    }, ScreenGui)
    corner(Handle, 6)
    stroke(Handle, Theme.Text, 1.5)
    ResizeHandles[cornerName] = Handle

    local Grip = new("TextButton", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 101,
    }, Handle)

    Grip.InputBegan:Connect(function(input)
        if not resizeMode or not isPress(input) then return end

        local pos, size = MainUI.AbsolutePosition, MainUI.AbsoluteSize
        resizeFixedX = pos.X + size.X * (1 - anchor.X)
        resizeFixedY = pos.Y + size.Y * (1 - anchor.Y)
        resizeDragCorner = cornerName

        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End and resizeDragCorner == cornerName then
                resizeDragCorner = nil
                commitUIState()
            end
        end)
    end)
end

local function onMainUIRectChanged()
    if resizeMode then updateResizeHandlePositions() end
end
MainUI:GetPropertyChangedSignal("AbsolutePosition"):Connect(onMainUIRectChanged)
MainUI:GetPropertyChangedSignal("AbsoluteSize"):Connect(onMainUIRectChanged)

track(UserInputService.InputChanged:Connect(function(input)
    if not resizeMode or not resizeDragCorner or not isMove(input) then return end

    local mouseX, mouseY = input.Position.X, input.Position.Y
    local newW = math.max(MIN_UI_W, math.abs(mouseX - resizeFixedX))
    local newH = math.max(MIN_UI_H, math.abs(mouseY - resizeFixedY))

    local movingX = resizeFixedX + (mouseX >= resizeFixedX and 1 or -1) * newW
    local movingY = resizeFixedY + (mouseY >= resizeFixedY and 1 or -1) * newH
    local viewport = getViewport()

    MainUI.Size = UDim2.fromOffset(newW, newH)
    MainUI.Position = UDim2.new(
        0.5, (resizeFixedX + movingX) / 2 - viewport.X * 0.5,
        0.5, (resizeFixedY + movingY) / 2 - viewport.Y * 0.5
    )
    updateResizeHandlePositions()
end))

local function setResizeMode(enabled)
    resizeMode = enabled
    uiLocked = enabled
    resizeDragCorner = nil
    drawIcon(ResizeIcon, "resize", enabled and Theme.AccentPink or Theme.Text, Theme.PanelAlt)
    tween(MainUIStroke, 0.2, {
        Color = enabled and Theme.AccentPink or Theme.Border,
        Thickness = enabled and 2 or 1,
    })
    for _, h in pairs(ResizeHandles) do h.Visible = enabled end
    if enabled then updateResizeHandlePositions() end
end

ResizeBtn.MouseButton1Click:Connect(function()
    setResizeMode(not resizeMode)
end)

--// ================= TAB SYSTEM =================
local TAB_HEIGHT          = 34
local TAB_GAP             = 6
local TAB_TEXT_PAD        = 14
local TAB_TEXT_PAD_ACTIVE = 18
local TAB_BAR_HEIGHT      = 20

local CONTENT_EDGE     = 2
local CONTENT_FADE_OUT = 0.12
local CONTENT_FADE_IN  = 0.22
local CONTENT_SLIDE    = 10

local TabData = {}
local tabCount = 0
local activeTab
local switchToken = 0
local ContentTweens = {}

local TabPill = new("Frame", {
    Name = "TabPill",
    Size = UDim2.new(1, 0, 0, TAB_HEIGHT),
    BackgroundColor3 = Color3.new(1, 1, 1),
    BackgroundTransparency = 0,
    BorderSizePixel = 0,
    Visible = false,
    ZIndex = 1,
}, TabScroll)
corner(TabPill, 6)

-- Kiểu highlight của tab list: nền tím -> hồng mờ dần từ trái sang phải + thanh accent bên trái
-- (khác với Player Info: viền tím sáng chạy vòng quanh)
new("UIGradient", {
    Color = ColorSequence.new(Theme.AccentPurple, Theme.AccentPink),
    Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0.00, 0.55),
        NumberSequenceKeypoint.new(0.60, 0.85),
        NumberSequenceKeypoint.new(1.00, 1.00),
    }),
}, TabPill)

local PillBar = new("Frame", {
    Name = "AccentBar",
    AnchorPoint = Vector2.new(0, 0.5),
    Position = UDim2.new(0, 6, 0.5, 0),
    Size = UDim2.fromOffset(3, TAB_BAR_HEIGHT),
    BackgroundColor3 = Theme.AccentPink,
    BorderSizePixel = 0,
}, TabPill)
corner(PillBar, 2)
local PillBarGlow = stroke(PillBar, Theme.AccentPink, 3)
PillBarGlow.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
PillBarGlow.Transparency = 0.75

local function cancelContentTween(content)
    local t = ContentTweens[content]
    if t then
        t:Cancel()
        ContentTweens[content] = nil
    end
end

local function selectTab(name)
    if activeTab == name then return end
    local previous = activeTab
    activeTab = name
    switchToken += 1
    local token = switchToken

    for tabName, t in pairs(TabData) do
        local selected = tabName == name
        tween(t.btn, 0.2, {
            BackgroundTransparency = 1,
            TextColor3 = selected and Theme.Sakura or Theme.SubText,
        })
        tween(t.pad, 0.25, {
            PaddingLeft = UDim.new(0, selected and TAB_TEXT_PAD_ACTIVE or TAB_TEXT_PAD),
        }, EASE_QUINT, DIR_OUT)
    end

    local target = UDim2.fromOffset(0, TabData[name].index * (TAB_HEIGHT + TAB_GAP))
    if TabPill.Visible then
        tween(TabPill, 0.25, { Position = target }, EASE_QUINT, DIR_OUT)
        tween(PillBar, 0.1, { Size = UDim2.fromOffset(3, 8) }).Completed:Once(function()
            tween(PillBar, 0.25, { Size = UDim2.fromOffset(3, TAB_BAR_HEIGHT) }, EASE_BACK, DIR_OUT)
        end)
    else
        TabPill.Position = target
        TabPill.Visible = true
    end

    for tabName, t in pairs(TabData) do
        if tabName ~= name and tabName ~= previous then
            cancelContentTween(t.content)
            t.content.Visible = false
        end
    end

    local newContent, pad = TabData[name].content, TabData[name].contentPad

    local function fadeIn()
        if token ~= switchToken then return end
        cancelContentTween(newContent)

        if not newContent.Visible then
            newContent.GroupTransparency = 1
            pad.PaddingTop = UDim.new(0, CONTENT_EDGE + CONTENT_SLIDE)
            newContent.Visible = true
        end

        ContentTweens[newContent] = tween(newContent, CONTENT_FADE_IN, { GroupTransparency = 0 }, EASE_QUAD, DIR_OUT)
        tween(pad, CONTENT_FADE_IN, { PaddingTop = UDim.new(0, CONTENT_EDGE) }, EASE_QUINT, DIR_OUT)
    end

    local oldContent = previous and TabData[previous].content
    if oldContent and oldContent.Visible then
        cancelContentTween(oldContent)
        local fade = tween(oldContent, CONTENT_FADE_OUT, { GroupTransparency = 1 }, EASE_QUAD, DIR_IN)
        ContentTweens[oldContent] = fade
        fade.Completed:Connect(function(state)
            if state ~= Enum.PlaybackState.Completed then return end
            oldContent.Visible = false
            ContentTweens[oldContent] = nil
            fadeIn()
        end)
    else
        fadeIn()
    end
end

local function CreateTab(name)
    tabCount += 1
    local index = tabCount - 1
    TabScroll.CanvasSize = UDim2.fromOffset(0, tabCount * (TAB_HEIGHT + TAB_GAP) - TAB_GAP + 6)

    local Btn = new("TextButton", {
        Name = "Tab_" .. name,
        AnchorPoint = ANCHOR_CENTER,
        Position = UDim2.new(0.5, 0, 0, index * (TAB_HEIGHT + TAB_GAP) + TAB_HEIGHT / 2),
        Size = UDim2.new(1, 0, 0, TAB_HEIGHT),
        BackgroundColor3 = Theme.Header,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = name,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextColor3 = Theme.SubText,
        TextXAlignment = Enum.TextXAlignment.Left,
        AutoButtonColor = false,
        TextWrapped = true,
        ZIndex = 2,
    }, TabScroll)
    corner(Btn, 6)
    local Pad = padding(Btn, TAB_TEXT_PAD, 8)
    pressScale(Btn, 0.97)

    Btn.MouseEnter:Connect(function()
        if uiLocked or activeTab == name then return end
        tween(Btn, 0.15, { BackgroundTransparency = 0.5, TextColor3 = Theme.Text })
        tween(Pad, 0.15, { PaddingLeft = UDim.new(0, TAB_TEXT_PAD + 2) })
    end)
    Btn.MouseLeave:Connect(function()
        if activeTab == name then return end
        tween(Btn, 0.15, { BackgroundTransparency = 1, TextColor3 = Theme.SubText })
        tween(Pad, 0.15, { PaddingLeft = UDim.new(0, TAB_TEXT_PAD) })
    end)
    Btn.MouseButton1Click:Connect(function()
        if uiLocked then return end
        selectTab(name)
    end)

    local Content = new("CanvasGroup", {
        Name = "TabContent_" .. name,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        GroupTransparency = 1,
        Visible = false,
    }, FunctionScroll)
    local ContentPad = padding(Content, CONTENT_EDGE, CONTENT_EDGE, CONTENT_EDGE, CONTENT_EDGE)
    list(Content, 10)

    TabData[name] = { index = index, btn = Btn, pad = Pad, content = Content, contentPad = ContentPad }

    if tabCount == 1 then selectTab(name) end
    return Content
end

--// ================= FUNCTION ELEMENT BUILDERS =================
local function CreateToggleOption(parent, title, height)
    local Frame = new("Frame", {
        Size = UDim2.new(1, 0, 0, height or 50),
        BackgroundColor3 = Theme.Panel,
        BorderSizePixel = 0,
    }, parent)
    corner(Frame, 8)
    stroke(Frame)

    label(Frame, {
        Size = UDim2.new(1, -80, 1, 0),
        Position = UDim2.fromOffset(14, 0),
        Text = title,
        TextSize = 15,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = Theme.Text,
    })

    local pxW, pxH, rightOffset = 46, 24, 12
    local Switch = new("TextButton", {
        Size = UDim2.fromOffset(pxW, pxH),
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -rightOffset, 0.5, 0),
        BackgroundColor3 = Theme.ToggleTrackOff,
        Text = "",
        AutoButtonColor = false,
    }, Frame)
    corner(Switch, 12)

    local SwitchGradient = new("UIGradient", {
        Color = ColorSequence.new(Theme.AccentPurple, Theme.AccentPink),
        Enabled = false,
    }, Switch)

    local Knob = new("Frame", {
        Size = UDim2.fromOffset(pxH - 4, pxH - 4),
        Position = UDim2.fromOffset(2, 2),
        BackgroundColor3 = Theme.Text,
        BorderSizePixel = 0,
    }, Switch)
    corner(Knob, 10)

    local state = false
    Switch:SetAttribute("Toggled", false)

    local function setState(value)
        value = value and true or false
        if state == value then return end
        state = value
        Switch:SetAttribute("Toggled", state)

        SwitchGradient.Enabled = state
        tween(Switch, 0.18, { BackgroundColor3 = state and Theme.AccentPink or Theme.ToggleTrackOff })
        tween(Knob, 0.18, {
            Position = state and UDim2.new(1, -(pxH - 2), 0, 2) or UDim2.fromOffset(2, 2),
            BackgroundColor3 = state and Theme.ToggleKnobOn or Theme.Text,
        })
    end

    Switch.MouseButton1Click:Connect(function()
        if uiLocked then return end
        setState(not state)
    end)

    return Switch, setState
end

local function CreateSectionLabel(parent, text)
    return label(parent, {
        Size = UDim2.new(1, 0, 0, 24),
        Text = text,
        TextSize = 13,
        TextColor3 = Theme.SubText,
        TextXAlignment = Enum.TextXAlignment.Left,
    })
end

local function CreateCard(parent, name, padV, padL, padR)
    local Card = new("Frame", {
        Name = name,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = Theme.Panel,
        BorderSizePixel = 0,
    }, parent)
    corner(Card, 8)
    stroke(Card)
    padding(Card, padL, padR, padV, padV)
    list(Card, 8)
    return Card
end

local function CreateStyledButton(parent, btnText, width)
    local Btn = new("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.fromOffset(width or 70, 28),
        BackgroundColor3 = Theme.Header,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = btnText,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextColor3 = Theme.Text,
    }, parent)
    corner(Btn, 6)
    stroke(Btn)
    pressScale(Btn, 0.95)

    Btn.MouseEnter:Connect(function()
        if uiLocked then return end
        tween(Btn, 0.15, { BackgroundColor3 = Theme.Border })
    end)
    Btn.MouseLeave:Connect(function()
        tween(Btn, 0.15, { BackgroundColor3 = Theme.Header })
    end)

    return Btn
end

local function flashButtonFeedback(Btn, defaultText, feedbackText, isError, holdTime)
    Btn.Text = feedbackText
    Btn.TextColor3 = isError and Theme.Danger or Theme.Sakura
    task.delay(holdTime or 1.2, function()
        Btn.Text = defaultText
        Btn.TextColor3 = Theme.Text
    end)
end

local function CreateInfoRow(parent, title, height)
    local Frame = new("Frame", {
        Size = UDim2.new(1, 0, 0, height or 50),
        BackgroundColor3 = Theme.Panel,
        BorderSizePixel = 0,
        ClipsDescendants = true,
    }, parent)
    corner(Frame, 8)
    stroke(Frame)
    padding(Frame, 14, 12)

    local Left = new("Frame", {
        Name = "Left",
        Size = UDim2.new(1, -90, 1, 0),
        BackgroundTransparency = 1,
        ClipsDescendants = true,
    }, Frame)
    list(Left, 8, {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
    })

    label(Left, {
        Name = "Title",
        LayoutOrder = 1,
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = title,
        TextSize = 15,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = Theme.Text,
    })

    return Frame, Left
end

local function bindBoxFocus(Box, BoxStroke, onFocus, onLost)
    Box.Focused:Connect(function()
        if uiLocked then Box:ReleaseFocus() return end
        tween(BoxStroke, 0.15, { Color = Theme.AccentPurple })
        if onFocus then onFocus() end
    end)
    Box.FocusLost:Connect(function()
        tween(BoxStroke, 0.15, { Color = Theme.Border })
        if onLost then onLost() end
    end)
end

local function flashStrokeError(BoxStroke)
    BoxStroke.Color = Theme.Danger
    tween(BoxStroke, 0.6, { Color = Theme.Border })
end

local function guarded(fn)
    local busy = false
    return function()
        if uiLocked or busy then return end
        busy = true
        fn(function()
            task.delay(1.2, function() busy = false end)
        end)
    end
end

--// ================= TABS =================
local StatusServerTab = CreateTab("Status & Server")
local LocalTab        = CreateTab("Local")
local FPSTab          = CreateTab("FPS")
local ScriptTab       = CreateTab("Script")
local SettingsTab     = CreateTab("Settings")

--// ================= SCRIPT TAB =================
-- Code của tab nằm ở file riêng, nạp từ GitHub: Script.lua
do
    local MODULE_FILE = "Script.lua"
    local MODULE_URL  = "https://raw.githubusercontent.com/mowfzm/Script-Test/refs/heads/main/Script.lua"
    local ok, err = pcall(function()
        local src = game:HttpGet(MODULE_URL)
        local init = assert(loadstring(src, "=" .. MODULE_FILE))()
        -- Module trả về ScriptDialog (khai báo sẵn ở phần OPEN / CLOSE để closeUI dùng)
        ScriptDialog = init({
            Tab                = ScriptTab,
            Theme              = Theme,
            ScreenGui          = ScreenGui,
            HttpService        = HttpService,
            UI_NAME            = UI_NAME,
            canFS              = canFS,
            WHITE              = WHITE,
            CENTER             = CENTER,
            ANCHOR_CENTER      = ANCHOR_CENTER,
            EASE_QUAD          = EASE_QUAD,
            DIR_IN             = DIR_IN,
            DIR_OUT            = DIR_OUT,
            BUBBLE_IN_TIME     = BUBBLE_IN_TIME,
            BUBBLE_OUT_TIME    = BUBBLE_OUT_TIME,
            FADE_IN_TIME       = FADE_IN_TIME,
            FADE_OUT_TIME      = FADE_OUT_TIME,
            CONTENT_EDGE       = CONTENT_EDGE,
            new                = new,
            corner             = corner,
            stroke             = stroke,
            padding            = padding,
            list               = list,
            label              = label,
            tween              = tween,
            pressScale         = pressScale,
            drawIcon           = drawIcon,
            setOverlay         = setOverlay,
            FunctionScroll     = FunctionScroll,
            DeleteDialog       = DeleteDialog,
            CreateInfoRow      = CreateInfoRow,
            CreateStyledButton = CreateStyledButton,
            flashStrokeError   = flashStrokeError,
            bindBoxFocus       = bindBoxFocus,
            isLocked           = function() return uiLocked end,
        })
    end)
    if not ok then warn("[Elysera] Không nạp được " .. MODULE_FILE .. ": " .. tostring(err)) end
end

--// ================= STATUS & SERVER TAB =================
-- Code của tab nằm ở file riêng, nạp từ GitHub: Status_Server.lua
do
    local MODULE_FILE = "Status_Server.lua"
    local MODULE_URL  = "https://raw.githubusercontent.com/mowfzm/Script-Test/refs/heads/main/Status_Server.lua"
    local ok, err = pcall(function()
        local src = game:HttpGet(MODULE_URL)
        local init = assert(loadstring(src, "=" .. MODULE_FILE))()
        init({
            Tab               = StatusServerTab,
            Theme             = Theme,
            ScreenGui         = ScreenGui,
            LocalPlayer       = LocalPlayer,
            TeleportService   = TeleportService,
            HttpService       = HttpService,
            new               = new,
            corner            = corner,
            stroke            = stroke,
            padding           = padding,
            label             = label,
            CreateInfoRow     = CreateInfoRow,
            CreateCard        = CreateCard,
            CreateStyledButton = CreateStyledButton,
            CreateToggleOption = CreateToggleOption,
            flashButtonFeedback = flashButtonFeedback,
            flashStrokeError  = flashStrokeError,
            bindBoxFocus      = bindBoxFocus,
            guarded           = guarded,
            isLocked          = function() return uiLocked end,
        })
    end)
    if not ok then warn("[Elysera] Không nạp được " .. MODULE_FILE .. ": " .. tostring(err)) end
end

--// ================= LOCAL TAB =================
-- Code của tab nằm ở file riêng, nạp từ GitHub: Local.lua
do
    local MODULE_FILE = "Local.lua"
    local MODULE_URL  = "https://raw.githubusercontent.com/mowfzm/Script-Test/refs/heads/main/Local.lua"
    local ok, err = pcall(function()
        local src = game:HttpGet(MODULE_URL)
        local init = assert(loadstring(src, "=" .. MODULE_FILE))()
        init({
            Tab                = LocalTab,
            Theme              = Theme,
            ScreenGui          = ScreenGui,
            LocalPlayer        = LocalPlayer,
            Players            = Players,
            RunService         = RunService,
            UserInputService   = UserInputService,
            Workspace          = Workspace,
            CoreGui            = CoreGui,
            new                = new,
            corner             = corner,
            stroke             = stroke,
            padding            = padding,
            list               = list,
            CreateCard         = CreateCard,
            CreateToggleOption = CreateToggleOption,
            flashStrokeError   = flashStrokeError,
            bindBoxFocus       = bindBoxFocus,
        })
    end)
    if not ok then warn("[Elysera] Không nạp được " .. MODULE_FILE .. ": " .. tostring(err)) end
end

--// ================= FPS TAB =================
-- Code của tab nằm ở file riêng, nạp từ GitHub: FPS.lua
do
    local MODULE_FILE = "FPS.lua"
    local MODULE_URL  = "https://raw.githubusercontent.com/mowfzm/Script-Test/refs/heads/main/FPS.lua"
    local ok, err = pcall(function()
        local src = game:HttpGet(MODULE_URL)
        local init = assert(loadstring(src, "=" .. MODULE_FILE))()
        init({
            Tab                 = FPSTab,
            Theme               = Theme,
            ScreenGui           = ScreenGui,
            LocalPlayer         = LocalPlayer,
            CoreGui             = CoreGui,
            MainUI              = MainUI,
            Saved               = Saved,
            saveSettings        = saveSettings,
            ANCHOR_CENTER       = ANCHOR_CENTER,
            CENTER              = CENTER,
            EASE_QUAD           = EASE_QUAD,
            DIR_IN              = DIR_IN,
            DIR_OUT             = DIR_OUT,
            new                 = new,
            corner              = corner,
            stroke              = stroke,
            padding             = padding,
            list                = list,
            label               = label,
            tween               = tween,
            pressScale          = pressScale,
            FunctionScroll      = FunctionScroll,
            CreateInfoRow       = CreateInfoRow,
            CreateStyledButton  = CreateStyledButton,
            CreateToggleOption  = CreateToggleOption,
            flashButtonFeedback = flashButtonFeedback,
            isLocked            = function() return uiLocked end,
            setLocked           = function(v) uiLocked = v end,
        })
    end)
    if not ok then warn("[Elysera] Không nạp được " .. MODULE_FILE .. ": " .. tostring(err)) end
end

--// ================= SETTINGS TAB =================
do
    local function setProp(inst, prop, value)
        pcall(function() inst[prop] = value end)
    end

    --// ---------- Anti Chat ----------
    local TextChatService = game:GetService("TextChatService")

    local AntiChatSwitch = CreateToggleOption(SettingsTab, "Anti Chat")
    AntiChatSwitch.Parent.LayoutOrder = 1

    local antiChatOn    = false
    local chatHooked    = false
    local antiChatConns = {}
    local antiChatBoxes = {}
    local chatBarConfig, chatBarOriginal

    -- Chặn tin nhắn gửi từ script (game hoặc executor) ở tầng __namecall / hookfunction.
    -- Hook không gỡ được nên dùng cờ antiChatOn: tắt toggle thì hook chỉ đi qua.
    local function isChatCall(self, method)
        if typeof(self) ~= "Instance" then return false end
        if method == "FireServer" then
            return self.ClassName == "RemoteEvent" and self.Name == "SayMessageRequest"
        elseif method == "SendAsync" then
            return self.ClassName == "TextChannel"
        elseif method == "Chat" then
            return self == LocalPlayer
        end
        return false
    end

    local function installChatHook()
        if chatHooked then return end

        if hookmetamethod and getnamecallmethod and newcclosure then
            pcall(function()
                local old
                old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
                    if antiChatOn and isChatCall(self, getnamecallmethod()) then
                        return
                    end
                    return old(self, ...)
                end))
                chatHooked = true
            end)
        end

        -- Bắt thêm trường hợp gọi kiểu remote.FireServer(remote, ...) / channel.SendAsync(channel, ...)
        if hookfunction and newcclosure then
            pcall(function()
                local oldFire
                oldFire = hookfunction(Instance.new("RemoteEvent").FireServer, newcclosure(function(self, ...)
                    if antiChatOn and isChatCall(self, "FireServer") then return end
                    return oldFire(self, ...)
                end))
                chatHooked = true
            end)
            pcall(function()
                local oldSend
                oldSend = hookfunction(Instance.new("TextChannel").SendAsync, newcclosure(function(self, ...)
                    if antiChatOn and isChatCall(self, "SendAsync") then return end
                    return oldSend(self, ...)
                end))
                chatHooked = true
            end)
        end
    end

    -- Chặn ở giao diện. Khung chat cũ (Legacy): không cho ChatBar nhận focus -> không gõ/gửi được
    local function blockLegacyChatBar(box)
        if antiChatBoxes[box] then return end
        antiChatBoxes[box] = true
        if box:IsFocused() then box:ReleaseFocus() end
        table.insert(antiChatConns, box.Focused:Connect(function()
            box:ReleaseFocus()
        end))
    end

    local function scanLegacyChat(inst)
        if inst.Name == "ChatBar" and inst:IsA("TextBox") then
            blockLegacyChatBar(inst)
        end
    end

    local function disableAntiChat()
        antiChatOn = false
        for _, c in ipairs(antiChatConns) do c:Disconnect() end
        table.clear(antiChatConns)
        table.clear(antiChatBoxes)

        if chatBarConfig then
            if chatBarOriginal ~= nil then
                setProp(chatBarConfig, "Enabled", chatBarOriginal)
            end
            chatBarConfig, chatBarOriginal = nil, nil
        end
    end

    local function enableAntiChat()
        disableAntiChat()
        antiChatOn = true
        installChatHook()

        -- Khung chat mới (TextChatService): tắt thanh nhập tin nhắn
        pcall(function()
            local cfg = TextChatService:FindFirstChildOfClass("ChatInputBarConfiguration")
            if cfg then
                chatBarConfig, chatBarOriginal = cfg, cfg.Enabled
                cfg.Enabled = false
                table.insert(antiChatConns, cfg:GetPropertyChangedSignal("Enabled"):Connect(function()
                    if cfg.Enabled then setProp(cfg, "Enabled", false) end
                end))
            end
        end)

        local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if pg then
            local chatGui = pg:FindFirstChild("Chat")
            if chatGui then
                for _, d in ipairs(chatGui:GetDescendants()) do scanLegacyChat(d) end
            end
            table.insert(antiChatConns, pg.DescendantAdded:Connect(scanLegacyChat))
        end
    end

    AntiChatSwitch:GetAttributeChangedSignal("Toggled"):Connect(function()
        if AntiChatSwitch:GetAttribute("Toggled") then
            enableAntiChat()
        else
            disableAntiChat()
        end
    end)

    --// ---------- Cleanup ----------
    ScreenGui.Destroying:Connect(function()
        disableAntiChat()
    end)
end

--// ================= EXPOSED API =================
local Elysera = {
    ScreenGui = ScreenGui,
    Theme = Theme,
    Open = openUI,
    Close = closeUI,
    CreateTab = CreateTab,
    CreateToggleOption = CreateToggleOption,
    CreateSectionLabel = CreateSectionLabel,
    SelectTab = selectTab,
}

--// ================= INITIAL STATE =================
openUI()

return Elysera
