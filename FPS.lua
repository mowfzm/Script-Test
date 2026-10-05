--// ================= FPS TAB (module) =================
-- Loaded by MainLocal.lua with a ctx table (see "FPS TAB" there).
-- Layout: Performance monitor (FPS, frame time, ping, memory, graph)
--         Optimize  : FPS Profile · FPS Cap · Auto Boost
--         Screen    : White Screen · Black Screen · Idle Saver
--         Interface : FPS Overlay · Remove Notification · Hide Chat & Player List
--         Reset All

return function(ctx)
    local FPSTab, Theme, ScreenGui = ctx.Tab, ctx.Theme, ctx.ScreenGui
    local LocalPlayer, CoreGui, MainUI = ctx.LocalPlayer, ctx.CoreGui, ctx.MainUI
    local Saved, saveSettings = ctx.Saved, ctx.saveSettings
    local ANCHOR_CENTER, CENTER = ctx.ANCHOR_CENTER, ctx.CENTER
    local EASE_QUAD, DIR_IN, DIR_OUT = ctx.EASE_QUAD, ctx.DIR_IN, ctx.DIR_OUT
    local new, corner, stroke, padding = ctx.new, ctx.corner, ctx.stroke, ctx.padding
    local list, label, tween, pressScale = ctx.list, ctx.label, ctx.tween, ctx.pressScale
    local FunctionScroll, CreateToggleOption = ctx.FunctionScroll, ctx.CreateToggleOption
    local isLocked, setLocked = ctx.isLocked, ctx.setLocked

    local RunService       = game:GetService("RunService")
    local Lighting         = game:GetService("Lighting")
    local StarterGui       = game:GetService("StarterGui")
    local TextService      = game:GetService("TextService")
    local Stats            = game:GetService("Stats")
    local UserInputService = game:GetService("UserInputService")
    local HttpService      = game:GetService("HttpService")

    local function setProp(inst, prop, value)
        return pcall(function() inst[prop] = value end)
    end

    --// ================= LIFECYCLE =================
    -- MainLocal destroys the old ScreenGui on reload, so Destroying is the only cleanup hook needed.
    local destroyed = false
    local teardown = {}

    local function onDestroy(fn)
        teardown[#teardown + 1] = fn
    end

    ScreenGui.Destroying:Connect(function()
        destroyed = true
        for _, fn in ipairs(teardown) do pcall(fn) end
    end)

    --// ================= SAVED CHOICES =================
    -- Small file next to MainLocal's settings: remembers the picked modes and the overlay position.
    -- Nothing is applied on load, every toggle starts off.
    local Prefs = {}
    do
        local FILE = "Elysera_Fps.json"
        local canFS = typeof(readfile) == "function" and typeof(writefile) == "function"
            and typeof(isfile) == "function"
        local data, queued = {}, false

        if canFS then
            local ok, decoded = pcall(function()
                if isfile(FILE) then return HttpService:JSONDecode(readfile(FILE)) end
            end)
            if ok and type(decoded) == "table" then data = decoded end
        end

        function Prefs.get(key) return data[key] end

        -- Saved value if it is still one of the allowed entries, otherwise the default
        function Prefs.pick(key, allowed, default)
            for _, v in ipairs(allowed) do
                if data[key] == v then return v end
            end
            return default
        end

        function Prefs.set(key, value)
            data[key] = value
            if not canFS or queued then return end
            queued = true
            task.delay(0.3, function() -- several quick changes become one write
                queued = false
                pcall(writefile, FILE, HttpService:JSONEncode(data))
            end)
        end
    end

    --// ================= FPS CAP =================
    local FpsCap = {}
    do
        local COVER_CAP, FALLBACK_CAP = 15, 60
        local canSet = typeof(setfpscap) == "function"
        local original
        if typeof(getfpscap) == "function" then
            local ok, v = pcall(getfpscap)
            if ok and type(v) == "number" and v > 0 then original = v end
        end

        local userCap, coverCap, engaged

        local function apply()
            if not canSet then return end
            local cap = userCap
            if coverCap and (not cap or coverCap < cap) then cap = coverCap end
            if cap then
                engaged = true
                pcall(setfpscap, cap)
            elseif engaged then -- only restore what we changed
                engaged = false
                pcall(setfpscap, original or FALLBACK_CAP)
            end
        end

        function FpsCap.supported() return canSet end
        function FpsCap.getUser() return userCap end

        function FpsCap.setUser(fps)
            userCap = fps
            apply()
        end

        -- Covered screen caps FPS only if the cap can be restored afterwards
        function FpsCap.setCover(on)
            coverCap = (on and (original or userCap)) and COVER_CAP or nil
            apply()
        end

        function FpsCap.restore()
            userCap, coverCap = nil, nil
            apply()
        end
    end

    --// ================= SHARED UI =================
    -- Down arrow drawn from two bars rotated ±45° (rotate the holder: 0 = down, -90 = right)
    local function createChevron(parent, props, color, len, thick)
        props.BackgroundTransparency = 1
        local Holder = new("Frame", props, parent)
        local dx = len * 0.3536
        local bars = {}
        for i, rot in ipairs({ 45, -45 }) do
            bars[i] = new("Frame", {
                AnchorPoint = ANCHOR_CENTER,
                Position = UDim2.new(0.5, i == 1 and -dx or dx, 0.5, 0),
                Size = UDim2.fromOffset(len, thick),
                Rotation = rot,
                BackgroundColor3 = color,
                BorderSizePixel = 0,
            }, Holder)
            corner(bars[i], thick / 2)
        end
        return Holder, function(c)
            for _, b in ipairs(bars) do b.BackgroundColor3 = c end
        end
    end

    -- Collapsible group: title + short subtitle, accent bar, "N on" pill while something inside is on.
    -- opts: { subtitle, collapsed } -> { Body, track(switch) }
    local function createSection(parent, title, order, opts)
        opts = opts or {}
        local open = not opts.collapsed
        local activeCount = 0
        local api = {}

        local Root = new("Frame", {
            Name = "Section_" .. title,
            LayoutOrder = order,
            BackgroundTransparency = 1,
            AutomaticSize = Enum.AutomaticSize.Y,
            Size = UDim2.new(1, 0, 0, 0),
        }, parent)
        list(Root, 6)

        local REST = Theme.Header
        local HOVER = Theme.Header:Lerp(Theme.Border, 0.35)

        local Header = new("TextButton", {
            Name = "Header",
            LayoutOrder = 0,
            Size = UDim2.new(1, 0, 0, 52),
            Text = "",
            BackgroundColor3 = REST,
            BorderSizePixel = 0,
            AutoButtonColor = false,
        }, Root)
        corner(Header, 8)
        stroke(Header)

        local Bar = new("Frame", {
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 8, 0.5, 0),
            Size = UDim2.fromOffset(3, 26),
            BackgroundColor3 = Theme.Border,
            BorderSizePixel = 0,
        }, Header)
        corner(Bar, 2)

        label(Header, {
            Position = UDim2.fromOffset(20, 8),
            Size = UDim2.new(1, -118, 0, 20),
            Text = title,
            TextSize = 14,
            TextColor3 = Theme.Text,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
        })
        label(Header, {
            Position = UDim2.fromOffset(20, 28),
            Size = UDim2.new(1, -118, 0, 16),
            Font = Enum.Font.Gotham,
            Text = opts.subtitle or "",
            TextSize = 11,
            TextColor3 = Theme.SubText,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
        })

        local Pill = new("Frame", {
            Name = "ActivePill",
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -40, 0.5, 0),
            Size = UDim2.fromOffset(46, 20),
            BackgroundColor3 = Theme.ToggleKnobOn,
            BorderSizePixel = 0,
            Visible = false,
        }, Header)
        corner(Pill, 10)
        new("UIGradient", { Color = ColorSequence.new(Theme.AccentPurple, Theme.AccentPink) }, Pill)
        local PillText = label(Pill, {
            Size = UDim2.fromScale(1, 1),
            TextSize = 11,
            TextColor3 = Theme.ToggleKnobOn,
            TextXAlignment = Enum.TextXAlignment.Center,
            Text = "",
        })

        local Chevron, setChevronColor = createChevron(Header, {
            Name = "Chevron",
            AnchorPoint = ANCHOR_CENTER,
            Position = UDim2.new(1, -24, 0.5, 0),
            Size = UDim2.fromOffset(20, 20),
        }, Theme.SubText, 10, 2)

        local Body = new("Frame", {
            Name = "Body",
            LayoutOrder = 1,
            BackgroundTransparency = 1,
            AutomaticSize = Enum.AutomaticSize.Y,
            Size = UDim2.new(1, 0, 0, 0),
        }, Root)
        list(Body, 6)

        local function render(animate)
            Body.Visible = open
            local rot = open and 0 or -90
            local barColor = (activeCount > 0) and Theme.AccentPink or Theme.Border
            if animate then
                tween(Chevron, 0.15, { Rotation = rot })
                tween(Bar, 0.15, { BackgroundColor3 = barColor })
            else
                Chevron.Rotation = rot
                Bar.BackgroundColor3 = barColor
            end
            setChevronColor(open and Theme.Text or Theme.SubText)
            Pill.Visible = activeCount > 0
            PillText.Text = activeCount .. " on"
        end

        Header.MouseEnter:Connect(function()
            tween(Header, 0.12, { BackgroundColor3 = HOVER })
        end)
        Header.MouseLeave:Connect(function()
            tween(Header, 0.12, { BackgroundColor3 = REST })
        end)
        Header.Activated:Connect(function()
            if isLocked() then return end
            open = not open
            render(true)
        end)

        -- Count every toggle of this section so the header shows how many are on
        function api.track(switch)
            switch:GetAttributeChangedSignal("Toggled"):Connect(function()
                local on = switch:GetAttribute("Toggled") == true
                activeCount = math.max(0, activeCount + (on and 1 or -1))
                render(true)
            end)
        end

        render(false)
        api.Body = Body
        return api
    end

    --// ================= MODE SELECTOR (toggle + dropdown) =================
    -- Row: title + toggle on the first line, right-aligned winbox (mode name + arrow) below it.
    -- The arrow opens a list under the row; the UI is locked (not dimmed) until a mode is picked
    -- or the user taps outside the list.
    local createModeRow
    do
        local POP_GAP, ITEM_H, POP_PAD = 4, 30, 4
        local BOX_H, ARROW_W, GAP = 26, 28, 6
        local BOX_MIN_W, BOX_MAX_W = 96, 220
        local ROW_TOP = 50

        local function textWidth(text)
            local ok, size = pcall(TextService.GetTextSize, TextService, text, 13,
                Enum.Font.GothamBold, Vector2.new(1000, 100))
            return ok and size.X or #text * 8
        end

        local PopBlocker = new("TextButton", {
            Name = "ModeBlocker",
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Text = "",
            AutoButtonColor = false,
            Visible = false,
            ZIndex = 15,
        }, MainUI)

        local PopList = new("CanvasGroup", {
            Name = "ModeList",
            AnchorPoint = Vector2.new(1, 0),
            BackgroundColor3 = Theme.Background,
            BorderSizePixel = 0,
            GroupTransparency = 1,
            Visible = false,
            ZIndex = 16,
        }, MainUI)
        corner(PopList, 10)
        stroke(PopList)

        local PopItems = new("Frame", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            ZIndex = 16,
        }, PopList)
        padding(PopItems, POP_PAD, POP_PAD, POP_PAD, POP_PAD)
        list(PopItems, 2)

        local Popup = { open = false, owner = nil, token = 0 }

        local function closePopup()
            if not Popup.open then return end
            Popup.open = false
            Popup.token += 1
            local token = Popup.token
            PopBlocker.Visible = false
            setLocked(false)
            local owner = Popup.owner
            Popup.owner = nil
            if owner then owner.onClosed() end
            tween(PopList, 0.1, { GroupTransparency = 1 }, EASE_QUAD, DIR_IN).Completed:Connect(function()
                if Popup.token == token then PopList.Visible = false end
            end)
        end

        local function openPopup(api)
            if Popup.open or isLocked() then return end

            for _, c in ipairs(PopItems:GetChildren()) do
                if c:IsA("TextButton") then c:Destroy() end
            end

            local current, maxW = api.getMode(), 0
            for i, m in ipairs(api.modes) do
                maxW = math.max(maxW, textWidth(m))
                local selected = (m == current)
                local Item = new("TextButton", {
                    LayoutOrder = i,
                    Size = UDim2.new(1, 0, 0, ITEM_H),
                    BackgroundColor3 = Theme.Header,
                    BackgroundTransparency = selected and 0 or 1,
                    BorderSizePixel = 0,
                    AutoButtonColor = false,
                    Text = m,
                    Font = Enum.Font.GothamBold,
                    TextSize = 13,
                    TextColor3 = selected and Theme.Sakura or Theme.Text,
                    ZIndex = 17,
                }, PopItems)
                corner(Item, 6)
                if not selected then
                    Item.MouseEnter:Connect(function()
                        tween(Item, 0.12, { BackgroundTransparency = 0.5 })
                    end)
                    Item.MouseLeave:Connect(function()
                        tween(Item, 0.12, { BackgroundTransparency = 1 })
                    end)
                end
                Item.Activated:Connect(function()
                    closePopup()
                    api.select(m)
                end)
            end

            local n = #api.modes
            local w = math.max(maxW + 32, 110)
            local h = n * ITEM_H + (n - 1) * 2 + POP_PAD * 2

            -- Open right under the row, right edges aligned; flip above if there is no room below
            local mp, ms = MainUI.AbsolutePosition, MainUI.AbsoluteSize
            local ap, asz = api.Frame.AbsolutePosition, api.Frame.AbsoluteSize
            local x = (ap.X + asz.X) - mp.X
            local y = (ap.Y + asz.Y) - mp.Y + POP_GAP
            if y + h > ms.Y - 6 then
                y = (ap.Y - mp.Y) - POP_GAP - h
            end
            y = math.max(y, 4)

            Popup.open, Popup.owner = true, api
            Popup.token += 1
            setLocked(true)
            PopBlocker.Visible = true

            PopList.Size = UDim2.fromOffset(w, h)
            PopList.Position = UDim2.fromOffset(x, y - 4)
            PopList.GroupTransparency = 1
            PopList.Visible = true
            tween(PopList, 0.12, { GroupTransparency = 0, Position = UDim2.fromOffset(x, y) }, EASE_QUAD, DIR_OUT)
            api.onOpened()
        end

        PopBlocker.Activated:Connect(closePopup)
        FunctionScroll:GetPropertyChangedSignal("CanvasPosition"):Connect(closePopup)
        MainUI:GetPropertyChangedSignal("AbsoluteSize"):Connect(closePopup)
        MainUI:GetPropertyChangedSignal("Visible"):Connect(function()
            if not MainUI.Visible then closePopup() end
        end)
        onDestroy(function()
            closePopup()
            PopBlocker:Destroy()
            PopList:Destroy()
        end)

        -- createModeRow(parent, title, modes, default, onSelect, hints) -> api
        -- hints: optional { [mode] = text, default = text }, shown to the left of the winbox
        -- api: Frame, Switch, setState, modes, getMode, setMode (silent), select (calls onSelect)
        function createModeRow(parent, title, modes, default, onSelect, hints)
            local Switch, setState = CreateToggleOption(parent, title, ROW_TOP + 34)
            local Frame = Switch.Parent
            Switch.AnchorPoint = Vector2.new(1, 0)
            Switch.Position = UDim2.new(1, -12, 0, (ROW_TOP - 24) / 2)
            local Title = Frame:FindFirstChildOfClass("TextLabel")
            if Title then Title.Size = UDim2.new(1, -80, 0, ROW_TOP) end

            local current = default
            local function boxWidth(text)
                return math.clamp(textWidth(text) + 2 * (ARROW_W + GAP), BOX_MIN_W, BOX_MAX_W)
            end

            local Box = new("Frame", {
                Name = "ModeBox",
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, -12, 0, ROW_TOP - 4),
                Size = UDim2.fromOffset(boxWidth(current), BOX_H),
                BackgroundColor3 = Theme.Header,
                BorderSizePixel = 0,
            }, Frame)
            corner(Box, 6)
            stroke(Box)

            local Hint
            if hints then
                Hint = label(Frame, {
                    Name = "Hint",
                    Position = UDim2.fromOffset(14, ROW_TOP - 4),
                    Size = UDim2.new(1, -(boxWidth(current) + 36), 0, BOX_H),
                    Font = Enum.Font.Gotham,
                    Text = hints[current] or hints.default or "",
                    TextSize = 11,
                    TextColor3 = Theme.SubText,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    TextTruncate = Enum.TextTruncate.AtEnd,
                })
            end

            local ModeText = label(Box, {
                Size = UDim2.fromScale(1, 1),
                Text = current,
                TextSize = 13,
                TextColor3 = Theme.Text,
                TextXAlignment = Enum.TextXAlignment.Center,
                TextTruncate = Enum.TextTruncate.AtEnd,
            })

            local ArrowBtn = new("TextButton", {
                Name = "Arrow",
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, -2, 0.5, 0),
                Size = UDim2.fromOffset(ARROW_W, BOX_H - 4),
                BackgroundTransparency = 1,
                Text = "",
                AutoButtonColor = false,
            }, Box)
            pressScale(ArrowBtn, 0.9)

            -- Down arrow drawn from two bars rotated ±45°
            local Chev = new("Frame", {
                AnchorPoint = ANCHOR_CENTER,
                Position = CENTER,
                Size = UDim2.fromOffset(12, 12),
                BackgroundTransparency = 1,
            }, ArrowBtn)
            for _, side in ipairs({ -1, 1 }) do
                corner(new("Frame", {
                    AnchorPoint = ANCHOR_CENTER,
                    Position = UDim2.fromOffset(6 + side * 2.5, 5.5),
                    Size = UDim2.fromOffset(7, 2),
                    Rotation = -side * 45,
                    BackgroundColor3 = Theme.SubText,
                    BorderSizePixel = 0,
                }, Chev), 1)
            end

            local api = { Frame = Frame, Switch = Switch, setState = setState, modes = modes }
            function api.getMode() return current end
            function api.setMode(m)
                if m == current then return end
                current = m
                ModeText.Text = m
                tween(Box, 0.15, { Size = UDim2.fromOffset(boxWidth(m), BOX_H) })
                if Hint then
                    Hint.Text = hints[m] or hints.default or ""
                    tween(Hint, 0.15, { Size = UDim2.new(1, -(boxWidth(m) + 36), 0, BOX_H) })
                end
            end
            function api.select(m)
                if m == current then return end
                api.setMode(m)
                if onSelect then onSelect(m) end
            end
            function api.onOpened() tween(Chev, 0.15, { Rotation = 180 }) end
            function api.onClosed() tween(Chev, 0.15, { Rotation = 0 }) end

            ArrowBtn.Activated:Connect(function()
                if isLocked() then return end
                openPopup(api)
            end)
            return api
        end
    end

    --// ================= SECTIONS =================
    local Optimize  = createSection(FPSTab, "Optimize", 2, { subtitle = "FPS profile and FPS cap" })
    local ScreenSec = createSection(FPSTab, "Screen", 3, {
        subtitle = "White, black and idle saver", collapsed = true,
    })
    local Interface = createSection(FPSTab, "Interface", 4, {
        subtitle = "Overlay, notifications, chat", collapsed = true,
    })

    local switches = {} -- every toggle of the tab: { Switch, set } (section pills and Reset All)
    local function addToggle(section, Switch, setState)
        section.track(Switch)
        switches[#switches + 1] = { Switch = Switch, set = setState }
    end

    --// ================= WHITE / BLACK SCREEN =================
    local Cover = new("ScreenGui", {
        Name = "ElyseraCover", -- MainLocal also removes this name on reload
        DisplayOrder = 5,      -- below the UI (10), so the UI stays usable
        IgnoreGuiInset = true,
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        Enabled = false,
    }, CoreGui)
    local CoverFrame = new("Frame", {
        Size = UDim2.fromScale(1, 1),
        BorderSizePixel = 0,
        BackgroundColor3 = Color3.new(0, 0, 0),
    }, Cover)

    local WhiteSwitch, setWhite = CreateToggleOption(ScreenSec.Body, "White Screen")
    WhiteSwitch.Parent.LayoutOrder = 1
    local BlackSwitch, setBlack = CreateToggleOption(ScreenSec.Body, "Black Screen")
    BlackSwitch.Parent.LayoutOrder = 2
    addToggle(ScreenSec, WhiteSwitch, setWhite)
    addToggle(ScreenSec, BlackSwitch, setBlack)

    -- The screen is covered by the White / Black switches or by the Idle Saver
    local coverActive, autoCover = false, false

    local function refreshScreen()
        local white = WhiteSwitch:GetAttribute("Toggled") == true
        local black = BlackSwitch:GetAttribute("Toggled") == true
        local on = white or black or autoCover
        if on then
            CoverFrame.BackgroundColor3 = white and Color3.new(1, 1, 1) or Color3.new(0, 0, 0)
        end
        Cover.Enabled = on
        if on ~= coverActive then
            coverActive = on
            pcall(function() RunService:Set3dRenderingEnabled(not on) end)
            FpsCap.setCover(on)
        end
    end

    WhiteSwitch:GetAttributeChangedSignal("Toggled"):Connect(function()
        if WhiteSwitch:GetAttribute("Toggled") then setBlack(false) end
        refreshScreen()
    end)
    BlackSwitch:GetAttributeChangedSignal("Toggled"):Connect(function()
        if BlackSwitch:GetAttribute("Toggled") then setWhite(false) end
        refreshScreen()
    end)

    local Screen = {}
    function Screen.setAuto(on)
        if autoCover == on then return end
        autoCover = on
        refreshScreen()
    end

    onDestroy(function()
        if coverActive then
            coverActive = false
            pcall(function() RunService:Set3dRenderingEnabled(true) end)
        end
        Cover:Destroy()
        FpsCap.restore()
    end)

    --// ================= IDLE SAVER =================
    -- No input for a while -> black screen + low FPS through the same cover. Any input wakes it up.
    local Saver = {}
    local SAVER_MODES = { "After 1 min", "After 3 min", "After 5 min", "After 10 min" }
    do
        local conns, run, lastInput, covered = {}, 0, os.clock(), false
        local COUNTS = { -- InputChanged also fires for sensors and idle thumbsticks: only real input counts
            [Enum.UserInputType.MouseMovement] = true,
            [Enum.UserInputType.MouseWheel] = true,
            [Enum.UserInputType.Touch] = true,
            [Enum.UserInputType.Gamepad1] = true,
        }

        local function wake()
            lastInput = os.clock()
            if covered then
                covered = false
                Screen.setAuto(false)
            end
        end

        function Saver.stop()
            run += 1
            for _, c in ipairs(conns) do c:Disconnect() end
            table.clear(conns)
            if covered then
                covered = false
                Screen.setAuto(false)
            end
        end

        function Saver.start(seconds)
            Saver.stop()
            local my = run
            lastInput = os.clock()
            conns[1] = UserInputService.InputBegan:Connect(wake)
            conns[2] = UserInputService.InputChanged:Connect(function(input)
                if COUNTS[input.UserInputType] then wake() end
            end)
            task.spawn(function()
                while run == my and not destroyed do
                    task.wait(1)
                    if run ~= my then break end
                    if #UserInputService:GetKeysPressed() > 0 then
                        wake() -- a key held down is activity too, even without new events
                    elseif not covered and os.clock() - lastInput >= seconds then
                        covered = true
                        Screen.setAuto(true)
                    end
                end
            end)
        end

        function Saver.seconds(modeText)
            return (tonumber(string.match(modeText, "(%d+)")) or 3) * 60
        end

        onDestroy(Saver.stop)
    end

    --// ================= HIDE CHAT & PLAYER LIST =================
    -- Fewer UI elements to draw (the player list is expensive in big servers). Only what we hid is restored.
    local HideUi = {}
    do
        local TYPES = { Enum.CoreGuiType.PlayerList, Enum.CoreGuiType.Chat }
        local hiddenByUs, active = {}, false

        function HideUi.enable()
            if active then return end
            active = true
            for _, t in ipairs(TYPES) do
                local ok, was = pcall(StarterGui.GetCoreGuiEnabled, StarterGui, t)
                if ok and was then
                    hiddenByUs[#hiddenByUs + 1] = t
                    pcall(StarterGui.SetCoreGuiEnabled, StarterGui, t, false)
                end
            end
        end

        function HideUi.disable()
            if not active then return end
            active = false
            for _, t in ipairs(hiddenByUs) do
                pcall(StarterGui.SetCoreGuiEnabled, StarterGui, t, true)
            end
            table.clear(hiddenByUs)
        end

        onDestroy(HideUi.disable)
    end

    --// ================= REMOVE NOTIFICATION =================
    local Notif = {}
    do
        local NOTIF_WORDS = {
            notification = true, notifications = true, notif = true, toast = true,
            announcement = true, announce = true, notice = true,
        }
        local nameCache = {}

        local function isNotifName(name)
            local hit = nameCache[name]
            if hit == nil then
                hit = false
                local spaced = (name:gsub("(%l)(%u)", "%1 %2")) -- QuestNotif -> Quest Notif
                spaced = (spaced:gsub("(%u)(%u%l)", "%1 %2"))   -- UINotification -> UI Notification
                spaced = (spaced:gsub("[^%w]+", " "))
                for word in string.gmatch(string.lower(spaced), "%S+") do
                    if NOTIF_WORDS[word] then
                        hit = true
                        break
                    end
                end
                nameCache[name] = hit
            end
            return hit
        end

        -- SetCore("SendNotification") hook: installed once per executor session, shared across
        -- reloads through getgenv, and a pass-through whenever the toggle is off.
        local state
        do
            local okEnv, env = pcall(function() return getgenv() end)
            env = okEnv and env or _G
            state = env.__ElyseraNotif
            if not state then
                state = { on = false, hooked = false }
                env.__ElyseraNotif = state
            end
        end

        local function installHook()
            if state.hooked then return end
            if typeof(hookfunction) ~= "function" or typeof(newcclosure) ~= "function"
                or typeof(checkcaller) ~= "function" then
                return
            end
            local old
            local ok, res = pcall(hookfunction, StarterGui.SetCore, newcclosure(function(self, name, ...)
                if state.on and name == "SendNotification" and self == StarterGui and not checkcaller() then
                    return
                end
                return old(self, name, ...)
            end))
            if ok and res then
                old = res
                state.hooked = true
            end
        end

        local hidden = setmetatable({}, { __mode = "k" }) -- gui -> { prop, orig, conn }
        local conns = {}
        local active, run = false, 0

        local function hideGui(inst, prop)
            if hidden[inst] then return end
            local rec = { prop = prop, orig = inst[prop] }
            hidden[inst] = rec
            setProp(inst, prop, false)
            rec.conn = inst:GetPropertyChangedSignal(prop):Connect(function()
                if inst[prop] then setProp(inst, prop, false) end
            end)
        end

        local function scanGui(inst)
            if not active or not isNotifName(inst.Name) then return end
            local prop = (inst:IsA("ScreenGui") and "Enabled") or (inst:IsA("GuiObject") and "Visible")
            if not prop then return end
            if inst:FindFirstChildWhichIsA("TextBox", true) then return end -- never hide input UI (chat)
            hideGui(inst, prop)
        end

        function Notif.enable()
            if active then return end
            active = true
            run += 1
            local myRun = run
            installHook()
            state.on = true

            pcall(function()
                local rg = CoreGui:FindFirstChild("RobloxGui")
                local frame = rg and rg:FindFirstChild("NotificationFrame")
                if frame then hideGui(frame, "Visible") end
            end)

            local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
            if not pg then return end
            conns[#conns + 1] = pg.DescendantAdded:Connect(function(d)
                task.defer(scanGui, d)
            end)
            task.spawn(function()
                local items = pg:GetDescendants()
                for i = 1, #items do
                    if run ~= myRun then return end
                    scanGui(items[i])
                    if i % 150 == 0 then task.wait() end
                end
            end)
        end

        function Notif.disable()
            if not active then return end
            active = false
            run += 1
            state.on = false
            for _, c in ipairs(conns) do c:Disconnect() end
            table.clear(conns)
            for inst, rec in pairs(hidden) do
                if rec.conn then rec.conn:Disconnect() end
                setProp(inst, rec.prop, rec.orig)
            end
            table.clear(hidden)
            table.clear(nameCache)
        end
    end

    --// ================= OPTIMIZER =================
    -- Every change is recorded (original value + the value we set) and only reverted if the
    -- property still holds our value, so anything the game changed in the meantime is left alone.
    local Opt = {
        snapshot = setmetatable({}, { __mode = "k" }), -- inst -> { [prop] = { original, applied, hidden } }
        conns = {},        -- connections created while a profile is active
        routes = {},       -- ClassName -> { handler, ... }
        partHandlers = {}, -- handlers for every BasePart
        runId = 0,         -- bumped on restore: cancels background scans
        restoring = false,
        watching = false,
        needRescan = false,
    }

    local hiddenOk
    local function hiddenAvailable()
        if hiddenOk == nil then
            hiddenOk = false
            if typeof(gethiddenproperty) == "function" and typeof(sethiddenproperty) == "function" then
                local ok, v = pcall(gethiddenproperty, Lighting, "Technology")
                hiddenOk = ok and v ~= nil
            end
        end
        return hiddenOk
    end

    local function probe(inst, prop, value, hidden)
        local cur
        if hidden then cur = gethiddenproperty(inst, prop) else cur = inst[prop] end
        if cur == value then return false end
        local now -- read back: the engine may round the value (e.g. float32)
        if hidden then
            sethiddenproperty(inst, prop, value)
            now = gethiddenproperty(inst, prop)
        else
            inst[prop] = value
            now = inst[prop]
        end
        return true, cur, now
    end

    local function capture(inst, prop, value, hidden)
        if Opt.restoring then
            Opt.needRescan = true
            return
        end
        local ok, changed, prev, now = pcall(probe, inst, prop, value, hidden)
        if not ok or not changed then return end
        local rec = Opt.snapshot[inst]
        if not rec then
            rec = {}
            Opt.snapshot[inst] = rec
        end
        local e = rec[prop]
        if e then
            e[2] = now -- applied again: keep the first original
        else
            rec[prop] = { prev, now, hidden }
        end
    end

    local function revert(inst, prop, e)
        local cur
        if e[3] then cur = gethiddenproperty(inst, prop) else cur = inst[prop] end
        if cur ~= e[2] then return end
        if e[3] then sethiddenproperty(inst, prop, e[1]) else inst[prop] = e[1] end
    end

    --// ---- Routing: scan / watch / queue ----
    local partCache = {}
    local function isPart(inst)
        local cn = inst.ClassName
        local v = partCache[cn]
        if v == nil then
            v = inst:IsA("BasePart")
            partCache[cn] = v
        end
        return v
    end

    local function register(key, handler)
        if key == "BasePart" then
            Opt.partHandlers[#Opt.partHandlers + 1] = handler
            return
        end
        local hs = Opt.routes[key]
        if not hs then
            hs = {}
            Opt.routes[key] = hs
        end
        hs[#hs + 1] = handler
    end

    local function addConn(conn)
        Opt.conns[#Opt.conns + 1] = conn
    end

    local function hasHandlers()
        return next(Opt.routes) ~= nil or #Opt.partHandlers > 0
    end

    local function wants(inst)
        return Opt.routes[inst.ClassName] ~= nil or (#Opt.partHandlers > 0 and isPart(inst))
    end

    local function route(inst)
        local hs = Opt.routes[inst.ClassName]
        if hs then
            for i = 1, #hs do hs[i](inst) end
        end
        if #Opt.partHandlers > 0 and isPart(inst) then
            for i = 1, #Opt.partHandlers do Opt.partHandlers[i](inst) end
        end
    end

    local SCAN_BUDGET = 0.002 -- seconds per frame
    local function scan(root, myRun)
        local stack, top, visited = { root }, 1, 0
        local char = LocalPlayer.Character
        local t0 = os.clock()
        while top > 0 do
            local inst = stack[top]
            stack[top] = nil
            top -= 1
            if inst ~= char then -- never touch our own character
                if wants(inst) then pcall(route, inst) end
                local kids = inst:GetChildren()
                for i = 1, #kids do
                    top += 1
                    stack[top] = kids[i]
                end
            end
            visited += 1
            if visited % 64 == 0 and os.clock() - t0 >= (coverActive and 0.006 or SCAN_BUDGET) then
                RunService.Heartbeat:Wait()
                if myRun ~= Opt.runId then return end
                char = LocalPlayer.Character
                t0 = os.clock()
            end
        end
    end

    local queue, qHead, qTail, pump = {}, 1, 0, nil
    local DRAIN_BUDGET, QUEUE_CAP, RESCAN_GAP = 0.0015, 10000, 5
    local lastRescan = 0

    local function stopPump()
        if pump then
            pump:Disconnect()
            pump = nil
        end
    end

    local function clearQueue()
        table.clear(queue)
        qHead, qTail = 1, 0
        stopPump()
    end

    local function drain()
        local t0 = os.clock()
        while qHead <= qTail do
            local inst = queue[qHead]
            queue[qHead] = nil
            qHead += 1
            local char = LocalPlayer.Character
            if inst.Parent and not (char and inst:IsDescendantOf(char)) then pcall(route, inst) end
            if os.clock() - t0 >= DRAIN_BUDGET then return end
        end
        qHead, qTail = 1, 0
        stopPump()
        if Opt.needRescan and hasHandlers() and os.clock() - lastRescan >= RESCAN_GAP then
            Opt.needRescan = false
            lastRescan = os.clock()
            task.spawn(scan, workspace, Opt.runId)
        end
    end

    local function enqueue(inst)
        if qTail - qHead + 1 >= QUEUE_CAP then
            Opt.needRescan = true -- too many at once: rescan when the queue is idle
            return
        end
        qTail += 1
        queue[qTail] = inst
        if not pump then pump = RunService.Heartbeat:Connect(drain) end
    end

    local function watchWorkspace()
        if Opt.watching then return end
        Opt.watching = true
        addConn(workspace.DescendantAdded:Connect(function(inst)
            if Opt.restoring then
                Opt.needRescan = true
            elseif wants(inst) then
                enqueue(inst)
            end
        end))
    end

    --// ---- Restore ----
    local RESTORE_BUDGET = 0.004
    function Opt.restore(sync)
        Opt.restoring = true
        Opt.runId += 1
        for _, c in ipairs(Opt.conns) do pcall(c.Disconnect, c) end
        table.clear(Opt.conns)
        table.clear(Opt.routes)
        table.clear(Opt.partHandlers)
        clearQueue()
        Opt.watching, Opt.needRescan = false, false

        local t0 = os.clock()
        for inst, rec in pairs(Opt.snapshot) do
            for prop, e in pairs(rec) do pcall(revert, inst, prop, e) end
            Opt.snapshot[inst] = nil
            if not sync and os.clock() - t0 >= RESTORE_BUDGET then
                task.wait()
                t0 = os.clock()
            end
        end
        Opt.restoring = false
    end

    --// ---- Features ----
    local Features = {}
    local EFFECT_LEVEL = { -- class -> minimum level that disables it
        BlurEffect = 1, DepthOfFieldEffect = 1, SunRaysEffect = 1, BloomEffect = 1,
        ColorCorrectionEffect = 3,
    }
    local LIGHT_CLASSES = { "PointLight", "SpotLight", "SurfaceLight" }
    local COSMETIC_CLASSES = { "Smoke", "Fire", "Sparkles", "Trail", "Beam" }
    local KEEP_MATERIAL = { -- materials that matter visually / for gameplay
        [Enum.Material.Glass] = true, [Enum.Material.ForceField] = true,
        [Enum.Material.Neon] = true, [Enum.Material.Water] = true,
    }

    -- Only ever lowers the level. Automatic (0) is left alone unless the profile forces a level.
    function Features.quality(spec)
        local okR, rendering = pcall(function() return settings().Rendering end)
        if not okR or not rendering then return end
        local cur = rendering.QualityLevel.Value
        local target
        if cur == 0 then
            if not (spec.force and spec.cap) then return end
            target = spec.cap
        else
            target = math.clamp(cur - (spec.delta or 0), 1, cur)
            if spec.cap then target = math.min(target, spec.cap) end
        end
        capture(rendering, "QualityLevel", Enum.QualityLevel:FromValue(target))
    end

    function Features.lighting(level)
        capture(Lighting, "GlobalShadows", false)
        if level >= 2 then
            capture(Lighting, "ShadowSoftness", 0)
            capture(Lighting, "EnvironmentDiffuseScale", 0)
            capture(Lighting, "EnvironmentSpecularScale", 0)
            local terrain = workspace:FindFirstChildOfClass("Terrain")
            local clouds = terrain and terrain:FindFirstChildOfClass("Clouds")
            if clouds then capture(clouds, "Enabled", false) end
        end
        if level >= 3 then
            for _, child in ipairs(Lighting:GetChildren()) do
                if child:IsA("Atmosphere") then
                    capture(child, "Density", 0)
                    capture(child, "Haze", 0)
                    capture(child, "Glare", 0)
                end
            end
            if hiddenAvailable() then
                capture(Lighting, "Technology", Enum.Technology.Compatibility, true)
            end
        end
    end

    -- One ChildAdded connection on the current camera, re-attached when the camera changes
    local function watchCamera(handle)
        local camConn
        local function attach(cam)
            if camConn then
                camConn:Disconnect()
                camConn = nil
            end
            if not cam then return end
            for _, c in ipairs(cam:GetChildren()) do handle(c) end
            camConn = cam.ChildAdded:Connect(handle)
        end
        attach(workspace.CurrentCamera)
        local changed = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
            attach(workspace.CurrentCamera)
        end)
        return {
            Disconnect = function()
                changed:Disconnect()
                if camConn then
                    camConn:Disconnect()
                    camConn = nil
                end
            end,
        }
    end

    function Features.postFx(level)
        local function handle(inst)
            local need = EFFECT_LEVEL[inst.ClassName]
            if need and level >= need then capture(inst, "Enabled", false) end
        end
        for _, c in ipairs(Lighting:GetChildren()) do handle(c) end
        addConn(Lighting.ChildAdded:Connect(handle))
        addConn(watchCamera(handle))

        for _, class in ipairs(LIGHT_CLASSES) do
            register(class, function(l)
                if level >= 2 then capture(l, "Enabled", false) else capture(l, "Shadows", false) end
            end)
        end
        if level >= 2 then
            register("Highlight", function(h) capture(h, "Enabled", false) end)
        end
    end

    function Features.terrain(level)
        local terrain = workspace:FindFirstChildOfClass("Terrain")
        if not terrain then return end
        capture(terrain, "WaterWaveSize", 0)
        capture(terrain, "WaterWaveSpeed", 0)
        if level >= 2 then
            capture(terrain, "WaterReflectance", 0)
            if hiddenAvailable() then capture(terrain, "Decoration", false, true) end
        end
    end

    function Features.particles(spec)
        local scale = spec.rate
        register("ParticleEmitter", function(pe)
            local rate = pe.Rate
            if rate > 0 then capture(pe, "Rate", math.min(rate, math.max(1, rate * scale))) end
        end)
        if spec.cosmetic then
            for _, class in ipairs(COSMETIC_CLASSES) do
                register(class, function(inst) capture(inst, "Enabled", false) end)
            end
        end
    end

    function Features.parts(tier)
        register("BasePart", function(p)
            if p.ClassName == "Terrain" then return end
            if p.Reflectance > 0 then capture(p, "Reflectance", 0) end
            if p.ClassName == "MeshPart" then
                capture(p, "RenderFidelity", Enum.RenderFidelity.Performance)
            end
            if tier >= 2 and not KEEP_MATERIAL[p.Material] then
                capture(p, "Material", Enum.Material.SmoothPlastic)
            end
        end)
    end

    --// ---- Profiles ----
    local ORDER = { "quality", "lighting", "postFx", "terrain", "particles", "parts" }
    local MODES = { "Balanced", "Performance", "Extreme" }
    local PROFILES = {
        Balanced = {
            quality = { delta = 4 }, lighting = 1, postFx = 1, terrain = 1, parts = 1,
            particles = { rate = 0.5 },
        },
        Performance = {
            quality = { cap = 3 }, lighting = 2, postFx = 2, terrain = 1, parts = 1,
            particles = { rate = 0.2, cosmetic = true },
        },
        Extreme = { -- hidden properties (if the executor has them), part materials, overrides Automatic quality
            quality = { cap = 1, force = true }, lighting = 3, postFx = 3, terrain = 2, parts = 2,
            particles = { rate = 0.1, cosmetic = true },
        },
    }

    local function applyProfile(name)
        local spec = PROFILES[name]
        if not spec then return end
        for _, key in ipairs(ORDER) do
            local level = spec[key]
            if level then pcall(Features[key], level) end -- one failing feature must not block the rest
        end
        if hasHandlers() then
            watchWorkspace() -- start watching before the scan so nothing slips through
            task.spawn(scan, workspace, Opt.runId)
        end
    end

    -- Serialized worker: always restore to the original state, then apply the wanted profile
    local Ctl = { mode = "Balanced", enabled = false }
    local dirty, working, worker = false, false, nil

    local function reconcile()
        dirty = true
        if working then return end
        working = true
        worker = task.spawn(function()
            while dirty and not destroyed do
                dirty = false
                Opt.restore(false)
                if Ctl.enabled then applyProfile(Ctl.mode) end
            end
            working = false
        end)
    end

    onDestroy(function()
        dirty = false
        if worker then pcall(task.cancel, worker) end
        Opt.restoring = false
        Opt.restore(true)
    end)

    --// ================= PERFORMANCE METER =================
    -- One Heartbeat sampler shared by the monitor card (while the tab is on screen) and the overlay.
    -- It only runs while somebody wants it.
    local STATUS = {
        smooth = { text = "Smooth", color = Theme.Sakura },
        fair   = { text = "Fair",   color = Theme.AccentPurple },
        low    = { text = "Low",    color = Theme.Danger },
    }

    local Meter = { fps = 0, ms = 0, ping = nil, mem = nil, listeners = {} }
    do
        local beat
        local wanted = {}
        local frames, elapsed, lastSlow = 0, 0, 0

        local function readPing()
            local ok, v = pcall(function()
                return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
            end)
            if ok and type(v) == "number" and v > 0 then return v end
            local ok2, p = pcall(function() return LocalPlayer:GetNetworkPing() * 2000 end)
            if ok2 and type(p) == "number" and p > 0 then return p end
            return nil
        end

        local function readMemory()
            local ok, v = pcall(function() return Stats:GetTotalMemoryUsageMb() end)
            return (ok and type(v) == "number") and v or nil
        end

        local function onBeat(dt)
            if dt > 1 then -- app was suspended: drop the sample
                frames, elapsed = 0, 0
                return
            end
            frames += 1
            elapsed += dt
            if elapsed < 0.5 then return end

            Meter.fps = frames / elapsed
            Meter.ms = elapsed / frames * 1000
            frames, elapsed = 0, 0

            local now = os.clock()
            if now - lastSlow >= 1 then -- ping and memory change slowly
                lastSlow = now
                Meter.ping, Meter.mem = readPing(), readMemory()
            end
            for i = 1, #Meter.listeners do pcall(Meter.listeners[i], Meter) end
        end

        function Meter.want(key, on)
            wanted[key] = on or nil
            local want = not destroyed and next(wanted) ~= nil
            if want and not beat then
                frames, elapsed, lastSlow = 0, 0, 0
                beat = RunService.Heartbeat:Connect(onBeat)
            elseif not want and beat then
                beat:Disconnect()
                beat = nil
            end
        end

        -- Judged against the user's FPS cap when there is one (30 FPS locked is not "low")
        function Meter.level(fps)
            local cap = FpsCap.getUser()
            local smooth = cap and math.min(50, cap * 0.85) or 50
            local low = cap and math.min(30, cap * 0.5) or 30
            if fps >= smooth then return "smooth" end
            if fps >= low then return "fair" end
            return "low"
        end

        onDestroy(function() Meter.want("card", false) Meter.want("overlay", false) end)
    end

    local function hex(color) return color:ToHex() end
    local function rounded(n) return math.floor(n + 0.5) end
    local function formatMemory(mb)
        if mb >= 1024 then return string.format("%.1f GB", mb / 1024) end
        return rounded(mb) .. " MB"
    end

    --// ================= PERFORMANCE MONITOR CARD =================
    do
        local BARS = 40
        local hist = {}

        local Card = new("Frame", {
            Name = "Monitor",
            LayoutOrder = 1,
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundColor3 = Theme.Panel,
            BorderSizePixel = 0,
        }, FPSTab)
        corner(Card, 8)
        stroke(Card)
        padding(Card, 14, 14, 12, 12)
        list(Card, 10)

        local Top = new("Frame", {
            LayoutOrder = 1,
            Size = UDim2.new(1, 0, 0, 40),
            BackgroundTransparency = 1,
        }, Card)
        local Big = label(Top, {
            Size = UDim2.new(0, 0, 1, 0),
            AutomaticSize = Enum.AutomaticSize.X,
            RichText = true,
            Text = "--",
            TextSize = 34,
            TextColor3 = Theme.Sakura,
            TextXAlignment = Enum.TextXAlignment.Left,
        })

        local Chip = new("Frame", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, 0, 0.5, 0),
            Size = UDim2.fromOffset(0, 24),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundColor3 = Theme.Sakura,
            BackgroundTransparency = 0.82,
            BorderSizePixel = 0,
        }, Top)
        corner(Chip, 12)
        local ChipStroke = stroke(Chip, Theme.Sakura)
        ChipStroke.Transparency = 0.5
        padding(Chip, 12, 12, 0, 0)
        local ChipText = label(Chip, {
            Size = UDim2.new(0, 0, 1, 0),
            AutomaticSize = Enum.AutomaticSize.X,
            Text = "Measuring",
            TextSize = 12,
            TextColor3 = Theme.Sakura,
            TextXAlignment = Enum.TextXAlignment.Center,
        })

        local StatsRow = new("Frame", {
            LayoutOrder = 2,
            Size = UDim2.new(1, 0, 0, 34),
            BackgroundTransparency = 1,
        }, Card)
        list(StatsRow, 0, { FillDirection = Enum.FillDirection.Horizontal })

        local function stat(order, caption)
            local Col = new("Frame", {
                LayoutOrder = order,
                Size = UDim2.new(1 / 3, 0, 1, 0),
                BackgroundTransparency = 1,
            }, StatsRow)
            label(Col, {
                Size = UDim2.new(1, 0, 0, 14),
                Font = Enum.Font.Gotham,
                Text = caption,
                TextSize = 11,
                TextColor3 = Theme.SubText,
                TextXAlignment = Enum.TextXAlignment.Left,
            })
            return label(Col, {
                Position = UDim2.fromOffset(0, 15),
                Size = UDim2.new(1, 0, 0, 18),
                Text = "--",
                TextSize = 14,
                TextColor3 = Theme.Text,
                TextXAlignment = Enum.TextXAlignment.Left,
            })
        end
        local FrameVal = stat(1, "Frame time")
        local PingVal = stat(2, "Ping")
        local MemVal = stat(3, "Memory")

        local Graph = new("Frame", {
            Name = "Graph",
            LayoutOrder = 3,
            Size = UDim2.new(1, 0, 0, 46),
            BackgroundColor3 = Theme.PanelAlt,
            BorderSizePixel = 0,
            ClipsDescendants = true,
        }, Card)
        corner(Graph, 6)
        stroke(Graph)
        local Plot = new("Frame", {
            Name = "Plot",
            Position = UDim2.fromOffset(4, 4),
            Size = UDim2.new(1, -8, 1, -8),
            BackgroundTransparency = 1,
        }, Graph)

        local bars = {}
        for i = 1, BARS do
            bars[i] = new("Frame", {
                Name = "Bar",
                AnchorPoint = Vector2.new(0, 1),
                Position = UDim2.new((i - 1) / BARS, 0, 1, 0),
                Size = UDim2.new(1 / BARS, -1, 0, 0),
                BackgroundColor3 = Theme.Sakura,
                BorderSizePixel = 0,
                Visible = false,
            }, Plot)
        end
        local Guide = new("Frame", { -- the 30 FPS line
            AnchorPoint = Vector2.new(0, 0.5),
            Size = UDim2.new(1, 0, 0, 1),
            BackgroundColor3 = Theme.Border,
            BackgroundTransparency = 0.35,
            BorderSizePixel = 0,
            ZIndex = 2,
        }, Plot)

        local function drawGraph()
            local n, top = #hist, 60
            for i = 1, n do
                if hist[i] > top then top = hist[i] end
            end
            top = math.ceil(top / 30) * 30
            for i = 1, BARS do
                local v = hist[n - (BARS - i)]
                local bar = bars[i]
                if v then
                    bar.Visible = true
                    bar.Size = UDim2.new(1 / BARS, -1, math.clamp(v / top, 0.04, 1), 0)
                    bar.BackgroundColor3 = STATUS[Meter.level(v)].color
                else
                    bar.Visible = false
                end
            end
            Guide.Position = UDim2.new(0, 0, 1 - 30 / top, 0)
        end

        local function setChip(text, color)
            ChipText.Text = text
            ChipText.TextColor3 = color
            Chip.BackgroundColor3 = color
            ChipStroke.Color = color
        end

        local function render(m)
            PingVal.Text = m.ping and (rounded(m.ping) .. " ms") or "--"
            MemVal.Text = m.mem and formatMemory(m.mem) or "--"

            if coverActive then
                Big.Text = string.format('<font color="#%s">OFF</font><font size="13" color="#%s"> rendering</font>',
                    hex(Theme.SubText), hex(Theme.SubText))
                FrameVal.Text = "--"
                setChip("Saving power", Theme.SubText)
                return
            end

            local fps = m.fps
            local status = STATUS[Meter.level(fps)]
            Big.Text = string.format('<font color="#%s">%d</font><font size="13" color="#%s"> FPS</font>',
                hex(status.color), rounded(fps), hex(Theme.SubText))
            FrameVal.Text = string.format("%.1f ms", m.ms)
            setChip(status.text, status.color)

            hist[#hist + 1] = fps
            if #hist > BARS then table.remove(hist, 1) end
            drawGraph()
        end

        Meter.listeners[#Meter.listeners + 1] = function(m)
            if Card.Parent and FPSTab.Visible then render(m) end
        end

        -- Only sample while the tab is actually on screen
        local function refresh()
            local want = not destroyed and FPSTab.Visible and MainUI.Visible
            if want then table.clear(hist) end
            Meter.want("card", want)
        end
        FPSTab:GetPropertyChangedSignal("Visible"):Connect(refresh)
        MainUI:GetPropertyChangedSignal("Visible"):Connect(refresh)
        refresh()
    end

    --// ================= FPS OVERLAY =================
    -- Small pill with FPS and ping that stays on screen (above the cover, below the UI).
    -- Drag it anywhere; the position is remembered.
    local Overlay = {}
    do
        local px, py = 0.5, 0.01 -- centered at the top
        local saved = Prefs.get("overlay")
        if type(saved) == "table" then
            local x, y = tonumber(saved.x), tonumber(saved.y)
            if x and y and x == x and y == y then
                px, py = math.clamp(x, 0, 1), math.clamp(y, 0, 1)
            end
        end

        local Gui = new("ScreenGui", {
            Name = "ElyseraFpsOverlay",
            DisplayOrder = 6,
            IgnoreGuiInset = true,
            ResetOnSpawn = false,
            ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
            Enabled = false,
        }, CoreGui)

        local Pill = new("Frame", {
            Name = "Pill",
            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.fromScale(px, py),
            Size = UDim2.fromOffset(150, 26),
            BackgroundColor3 = Theme.Panel,
            BackgroundTransparency = 0.1,
            BorderSizePixel = 0,
            Active = true,
        }, Gui)
        corner(Pill, 13)
        stroke(Pill)

        local Text = label(Pill, {
            Size = UDim2.fromScale(1, 1),
            RichText = true,
            Text = "",
            TextSize = 13,
            TextColor3 = Theme.Text,
            TextXAlignment = Enum.TextXAlignment.Center,
        })

        local function render(m)
            if coverActive then
                Text.Text = string.format('<font color="#%s">Rendering off</font>', hex(Theme.SubText))
                return
            end
            local status = STATUS[Meter.level(m.fps)]
            local text = string.format('<font color="#%s">%d</font> FPS', hex(status.color), rounded(m.fps))
            if m.ping then
                text = text .. string.format(' <font color="#%s">·</font> %d ms', hex(Theme.SubText), rounded(m.ping))
            end
            Text.Text = text
        end

        Meter.listeners[#Meter.listeners + 1] = function(m)
            if Gui.Enabled then render(m) end
        end

        -- Keep the pill fully on screen and remember where it is (as a fraction of the screen)
        local function settle()
            local vp, size, pos = Gui.AbsoluteSize, Pill.AbsoluteSize, Pill.AbsolutePosition
            if vp.X <= 0 or vp.Y <= 0 then return end
            local cx = math.clamp(pos.X + size.X / 2, size.X / 2, math.max(size.X / 2, vp.X - size.X / 2))
            local ty = math.clamp(pos.Y, 0, math.max(0, vp.Y - size.Y))
            px, py = cx / vp.X, ty / vp.Y
            Pill.Position = UDim2.fromScale(px, py)
            Prefs.set("overlay", { x = px, y = py })
        end

        Pill.InputBegan:Connect(function(input)
            local kind = input.UserInputType
            if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then return end
            local startInput, startPos = input.Position, Pill.Position
            local moveConn, endConn
            moveConn = UserInputService.InputChanged:Connect(function(i)
                if i.UserInputType == Enum.UserInputType.MouseMovement or i == input then
                    local d = i.Position - startInput
                    Pill.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                        startPos.Y.Scale, startPos.Y.Offset + d.Y)
                end
            end)
            endConn = input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    moveConn:Disconnect()
                    endConn:Disconnect()
                    settle()
                end
            end)
        end)

        function Overlay.setEnabled(on)
            Gui.Enabled = on
            Meter.want("overlay", on)
        end

        onDestroy(function() Gui:Destroy() end)
    end

    --// ================= OPTIMIZE ROWS =================
    -- MainLocal only persists the FpsMode attribute (see saveSettings), so the profile is saved there;
    -- the other choices go through Prefs.
    local startMode = "Balanced"
    for _, m in ipairs(MODES) do
        if Saved.fpsMode == m then startMode = m end
    end
    Ctl.mode = startMode
    ScreenGui:SetAttribute("FpsMode", startMode)

    local Profile = createModeRow(Optimize.Body, "FPS Profile", MODES, startMode, function(m)
        Ctl.mode = m
        ScreenGui:SetAttribute("FpsMode", m)
        saveSettings()
        if Ctl.enabled then reconcile() end
    end, {
        Balanced = "Shadows and blur effects off",
        Performance = "Also lights and effects off",
        Extreme = "Lowest quality, flat materials",
    })
    Profile.Frame.LayoutOrder = 1
    Profile.Switch:GetAttributeChangedSignal("Toggled"):Connect(function()
        Ctl.enabled = Profile.Switch:GetAttribute("Toggled") == true
        reconcile()
    end)
    addToggle(Optimize, Profile.Switch, Profile.setState)

    local CAP_MODES = { "30 FPS", "60 FPS", "90 FPS", "120 FPS", "144 FPS", "Unlimited" }
    local function parseFps(text)
        if text == "Unlimited" then return 999 end
        return tonumber(string.match(text, "^(%d+)"))
    end

    local CapRow
    CapRow = createModeRow(Optimize.Body, "FPS Cap", CAP_MODES, Prefs.pick("cap", CAP_MODES, "60 FPS"), function(m)
        Prefs.set("cap", m)
        if CapRow.Switch:GetAttribute("Toggled") then FpsCap.setUser(parseFps(m)) end
    end, { default = "Lower cap saves battery and heat", Unlimited = "No limit, uses more power" })
    CapRow.Frame.LayoutOrder = 2
    CapRow.Frame.Visible = FpsCap.supported() -- hidden when the executor has no setfpscap
    CapRow.Switch:GetAttributeChangedSignal("Toggled"):Connect(function()
        if CapRow.Switch:GetAttribute("Toggled") then
            FpsCap.setUser(parseFps(CapRow.getMode()))
        else
            FpsCap.setUser(nil)
        end
    end)
    addToggle(Optimize, CapRow.Switch, CapRow.setState)

    -- Auto Boost: when FPS stays low for a few seconds, turn the FPS Profile on (once), then switch off
    local AUTO_MODES = { "Below 20 FPS", "Below 30 FPS", "Below 40 FPS" }
    local AutoRow
    AutoRow = createModeRow(Optimize.Body, "Auto Boost", AUTO_MODES, Prefs.pick("auto", AUTO_MODES, "Below 30 FPS"),
        function(m) Prefs.set("auto", m) end, { default = "Profile turns on if FPS stays low" })
    AutoRow.Frame.LayoutOrder = 3
    addToggle(Optimize, AutoRow.Switch, AutoRow.setState)
    do
        local LOW_SECONDS = 6
        local lowSince

        local function limit()
            local v = tonumber(string.match(AutoRow.getMode(), "(%d+)")) or 30
            local cap = FpsCap.getUser()
            return cap and math.min(v, cap * 0.7) or v -- a deliberate cap is not "low FPS"
        end

        Meter.listeners[#Meter.listeners + 1] = function(m)
            if not AutoRow.Switch:GetAttribute("Toggled") then return end
            if coverActive or Ctl.enabled or m.fps >= limit() then
                lowSince = nil
                return
            end
            local now = os.clock()
            lowSince = lowSince or now
            if now - lowSince >= LOW_SECONDS then
                lowSince = nil
                Profile.setState(true)  -- the normal switch, so the UI stays in sync
                AutoRow.setState(false) -- one shot
            end
        end

        -- Sample only while armed and the profile is still off
        local function sync()
            lowSince = nil
            Meter.want("auto", AutoRow.Switch:GetAttribute("Toggled") == true and not Ctl.enabled)
        end
        AutoRow.Switch:GetAttributeChangedSignal("Toggled"):Connect(sync)
        Profile.Switch:GetAttributeChangedSignal("Toggled"):Connect(sync)
    end

    --// ================= SCREEN ROWS =================
    local SaverRow
    SaverRow = createModeRow(ScreenSec.Body, "Idle Saver", SAVER_MODES, Prefs.pick("saver", SAVER_MODES, "After 3 min"),
        function(m)
            Prefs.set("saver", m)
            if SaverRow.Switch:GetAttribute("Toggled") then Saver.start(Saver.seconds(m)) end
        end, { default = "Black screen and low FPS when idle" })
    SaverRow.Frame.LayoutOrder = 3
    SaverRow.Switch:GetAttributeChangedSignal("Toggled"):Connect(function()
        if SaverRow.Switch:GetAttribute("Toggled") then
            Saver.start(Saver.seconds(SaverRow.getMode()))
        else
            Saver.stop()
        end
    end)
    addToggle(ScreenSec, SaverRow.Switch, SaverRow.setState)

    --// ================= INTERFACE ROWS =================
    local OverlaySwitch, setOverlay = CreateToggleOption(Interface.Body, "FPS Overlay")
    OverlaySwitch.Parent.LayoutOrder = 1
    OverlaySwitch:GetAttributeChangedSignal("Toggled"):Connect(function()
        Overlay.setEnabled(OverlaySwitch:GetAttribute("Toggled") == true)
    end)
    addToggle(Interface, OverlaySwitch, setOverlay)

    local NotifSwitch, setNotif = CreateToggleOption(Interface.Body, "Remove Notification")
    NotifSwitch.Parent.LayoutOrder = 2
    NotifSwitch:GetAttributeChangedSignal("Toggled"):Connect(function()
        if NotifSwitch:GetAttribute("Toggled") then Notif.enable() else Notif.disable() end
    end)
    onDestroy(Notif.disable)
    addToggle(Interface, NotifSwitch, setNotif)

    local HideSwitch, setHide = CreateToggleOption(Interface.Body, "Hide Chat & Player List")
    HideSwitch.Parent.LayoutOrder = 3
    HideSwitch:GetAttributeChangedSignal("Toggled"):Connect(function()
        if HideSwitch:GetAttribute("Toggled") then HideUi.enable() else HideUi.disable() end
    end)
    addToggle(Interface, HideSwitch, setHide)

    --// ================= RESET ALL =================
    local ResetBtn = new("TextButton", {
        Name = "ResetAll",
        LayoutOrder = 5,
        Size = UDim2.new(1, 0, 0, 40),
        Text = "Reset All",
        BackgroundColor3 = Theme.PanelAlt,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Font = Enum.Font.GothamBold,
        TextSize = 14,
        TextColor3 = Theme.Text,
    }, FPSTab)
    corner(ResetBtn, 8)
    stroke(ResetBtn)
    pressScale(ResetBtn, 0.98)
    ResetBtn.MouseEnter:Connect(function()
        tween(ResetBtn, 0.15, { BackgroundColor3 = Theme.Header })
    end)
    ResetBtn.MouseLeave:Connect(function()
        tween(ResetBtn, 0.15, { BackgroundColor3 = Theme.PanelAlt })
    end)

    local resetToken = 0
    ResetBtn.Activated:Connect(function()
        if isLocked() then return end
        local n = 0
        for _, t in ipairs(switches) do
            if t.Switch:GetAttribute("Toggled") == true then
                n += 1
                t.set(false)
            end
        end
        resetToken += 1
        local my = resetToken
        ResetBtn.Text = (n > 0) and ("Reset " .. n .. (n == 1 and " feature" or " features")) or "Nothing to reset"
        task.delay(1.5, function()
            if my == resetToken and ResetBtn.Parent then ResetBtn.Text = "Reset All" end
        end)
    end)
end
