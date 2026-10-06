--// ================= LOCAL TAB (module) =================
-- Loaded by MainUI (MainLocal.lua) and called with a ctx table of shared UI helpers.
--
-- File structure:
--   Core     : shared foundation (input parsing, toggle binding, character lifecycle, fly input, teleport history)
--              + shared UI pieces (toggle row, status badge, presets, mode dropdown, button, input, sections)
--   Features : Movement (Speed, Jump Boost, Gravity, Infinite Jump, Noclip, Fly)
--              Teleport (Click Teleport, Waypoints, Players) + Quick actions (Back, Unstuck, Respawn)
--              Camera (Field of View, Max Zoom), Visual (ESP, Hide Players, Full Bright)
--              Safety (Anti AFK, Anti Void), Reset All
-- Grouped into 2 tables to stay under Luau's limit of 200 locals per chunk.

return function(ctx)
    local LocalTab         = ctx.Tab
    local Theme            = ctx.Theme
    local ScreenGui        = ctx.ScreenGui
    local LocalPlayer      = ctx.LocalPlayer

    local Players          = ctx.Players
    local RunService       = ctx.RunService
    local UserInputService = ctx.UserInputService
    local Workspace        = ctx.Workspace
    local CoreGui          = ctx.CoreGui
    local Lighting         = game:GetService("Lighting")
    local TextService      = game:GetService("TextService")
    local TweenService     = game:GetService("TweenService")

    local new, corner, stroke, padding, list = ctx.new, ctx.corner, ctx.stroke, ctx.padding, ctx.list

    local CreateCard         = ctx.CreateCard
    local CreateToggleOption = ctx.CreateToggleOption   -- returns Switch, setState
    local flashStrokeError   = ctx.flashStrokeError
    local bindBoxFocus       = ctx.bindBoxFocus
    -- MainUI's resize mode locks the whole UI; the loader may pass isLocked (optional)
    local isLocked           = ctx.isLocked or function() return false end

    local Core, Features = {}, {}

    -- In-world ESP colors only (all UI colors come from Theme)
    local WHITE = Color3.fromRGB(255, 255, 255)
    local GREEN = Color3.fromRGB(60, 255, 90)
    local RED   = Color3.fromRGB(255, 60, 60)

    local BADGE_COLORS = {
        active  = Theme.AccentPink,
        waiting = Theme.AccentPurple,
        invalid = Theme.Danger,
    }

    -- Enlarged "·" separator (RichText); labels that use it must have RichText = true
    Core.DOT = ' <font size="22"><b>·</b></font> '

    --// =====================================================
    --//  FOUNDATION (Core)
    --// =====================================================

    function Core.GetHumanoid()
        local c = LocalPlayer.Character
        return c and c:FindFirstChildOfClass("Humanoid")
    end

    function Core.GetRoot()
        local c = LocalPlayer.Character
        return c and c:FindFirstChild("HumanoidRootPart")
    end

    --// ---------- Parse numeric input box ----------
    function Core.SanitizeNumber(s)
        s = s:gsub("[^%d%.]", "")
        local dot = s:find(".", 1, true)
        if dot then
            s = s:sub(1, dot) .. (s:sub(dot + 1):gsub("%.", ""))
        end
        return s:sub(1, 7)
    end

    function Core.FormatValue(v)
        return tostring(math.floor(v * 100 + 0.5) / 100)
    end

    -- opts: { max = 1000, default = nil }
    -- return: { status = "ok" | "clamped" | "empty" | "invalid", value, effective, text }
    function Core.ParseNumericInput(rawText, opts)
        opts = opts or {}
        local clean = Core.SanitizeNumber(rawText or "")
        if clean == "" then
            return { status = "empty", effective = opts.default }
        end
        local n = tonumber(clean)
        if clean == "." or not n or n ~= n then
            return { status = "invalid", effective = opts.default }
        end
        local eff = math.clamp(n, 0, opts.max or math.huge)
        return {
            status = (eff ~= n) and "clamped" or "ok",
            value = n,
            effective = eff,
            text = Core.FormatValue(eff),
        }
    end

    --// ---------- BindToggle: shared contract for every feature ----------
    -- Set = the setState returned by MainUI's CreateToggleOption (keeps the switch visuals in sync)
    -- cfg: { start, stop, onReset, badge }
    -- start() returns false => rejected (the switch reverts to OFF on its own)
    local features = {}                       -- creation order; Reset All stops them in reverse

    function Core.BindToggle(Switch, Set, cfg)
        local active = false
        local listeners = {}
        local handle = {}

        local function notify()
            for _, fn in ipairs(listeners) do pcall(fn, active) end
        end

        local function doStart()
            if active then return end
            active = true
            local ok, res = pcall(cfg.start)
            if not ok or res == false then
                if not ok then warn("[Local] start error:", res) end
                pcall(cfg.stop)
                active = false
                Set(false)
                if not ok and cfg.badge then cfg.badge.set("invalid", "Startup error") end
                return
            end
            notify()
        end

        local function doStop()
            if not active then return end
            active = false
            pcall(cfg.stop)
            notify()
        end

        Switch:GetAttributeChangedSignal("Toggled"):Connect(function()
            if Switch:GetAttribute("Toggled") then doStart() else doStop() end
        end)

        function handle.isOn() return active end
        function handle.onChanged(fn) listeners[#listeners + 1] = fn end
        function handle.stop()
            Set(false)
            doStop()
        end

        features[#features + 1] = { handle = handle, onReset = cfg.onReset }
        return handle
    end

    -- Turns off every feature and restores original values. Returns the number of features turned off.
    function Core.ResetAll()
        pcall(Core.CloseDropdown)
        local n = 0
        for i = #features, 1, -1 do
            local f = features[i]
            if f.handle.isOn() then n += 1 end
            pcall(f.handle.stop)
            if f.onReset then pcall(f.onReset) end
        end
        return n
    end

    -- For things that are not toggles but still hold state (e.g. viewing a player): handle = { isOn(), stop() }
    function Core.Register(handle, onReset)
        features[#features + 1] = { handle = handle, onReset = onReset }
    end

    -- Callbacks that run when the GUI is destroyed (global connections must be released there)
    Core.hooks = {}
    function Core.OnDestroy(fn)
        Core.hooks[#Core.hooks + 1] = fn
    end

    --// ---------- TrackCharacter: tracks the character lifecycle ----------
    -- onChar(char, hum, root) -> (optional) returns a cleanup function
    -- opts: { onDied = false }
    function Core.TrackCharacter(player, onChar, opts)
        local onDied = opts and opts.onDied
        local token, cleanup, diedConn = 0, nil, nil

        local function runCleanup()
            if diedConn then diedConn:Disconnect() diedConn = nil end
            local fn = cleanup
            cleanup = nil
            if fn then pcall(fn) end
        end

        local function handle(char)
            token += 1
            local my = token
            runCleanup()
            local hum = char:WaitForChild("Humanoid", 10)
            local root = char:WaitForChild("HumanoidRootPart", 10)
            if my ~= token or not hum or not root or not char.Parent then return end
            local ok, fn = pcall(onChar, char, hum, root)
            if not ok then
                warn("[Local] TrackCharacter:", fn)
                return
            end
            cleanup = (type(fn) == "function") and fn or nil
            if onDied then
                diedConn = hum.Died:Connect(function()
                    if my == token then runCleanup() end
                end)
            end
        end

        local added = player.CharacterAdded:Connect(function(c) task.spawn(handle, c) end)
        local removing = player.CharacterRemoving:Connect(function()
            token += 1
            runCleanup()
        end)
        if player.Character then task.spawn(handle, player.Character) end

        return {
            destroy = function()
                token += 1
                added:Disconnect()
                removing:Disconnect()
                runCleanup()
            end,
        }
    end

    --// ---------- Flight controls: read input (fly in the camera direction) ----------
    local controlModule, controlLoading = nil, false

    -- Look up the game's ControlModule without blocking; retries once per second, up to 10 times
    function Core.LoadControls()
        if controlModule or controlLoading then return end
        controlLoading = true
        task.spawn(function()
            for _ = 1, 10 do
                local ok, m = pcall(function()
                    local scripts = LocalPlayer:FindFirstChild("PlayerScripts")
                    local pm = scripts and scripts:FindFirstChild("PlayerModule")
                    local cm = pm and pm:FindFirstChild("ControlModule")
                    return cm and require(cm)
                end)
                if ok and m then
                    controlModule = m
                    break
                end
                task.wait(1)
            end
            controlLoading = false
        end)
    end

    -- upUntil: os.clock() deadline of the "jump = go up" press (written by JumpRequest)
    -- return: world direction, length <= 1
    function Core.ReadFlyDirection(upUntil)
        if UserInputService:GetFocusedTextBox() then return Vector3.zero end

        local move
        if controlModule then
            local ok, v = pcall(controlModule.GetMoveVector, controlModule)
            if ok and typeof(v) == "Vector3" then move = v end
        end
        if not move then                                              -- keyboard fallback
            local x, z = 0, 0
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then z -= 1 end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then z += 1 end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then x -= 1 end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then x += 1 end
            move = Vector3.new(x, 0, z)
        end

        local dir = Vector3.zero
        local cam = Workspace.CurrentCamera
        if cam then
            local cf = cam.CFrame
            dir = cf.RightVector * move.X - cf.LookVector * move.Z      -- along the camera direction
        end

        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir += Vector3.yAxis end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
            or UserInputService:IsKeyDown(Enum.KeyCode.Q) then
            dir -= Vector3.yAxis
        end
        if os.clock() < upUntil then dir += Vector3.yAxis end

        if dir.Magnitude > 1 then dir = dir.Unit end
        return dir
    end

    --// =====================================================
    --//  SHARED UI
    --// =====================================================

    -- Toggle row with a "Stack" (vertical layout frame) for attaching a Status Badge / Preset / Winbox right below it.
    -- The original row created by CreateToggleOption is moved into the Stack.
    function Core.CreateToggleRow(parent, title)
        local Switch, Set = CreateToggleOption(parent, title, 50)
        local Row = Switch.Parent

        local Stack = new("Frame", {
            Name = "Stack",
            BackgroundTransparency = 1,
            AutomaticSize = Enum.AutomaticSize.Y,
            Size = UDim2.new(1, 0, 0, 0),
        }, parent)
        list(Stack, 4)

        Row.Parent = Stack
        Row.LayoutOrder = 1
        return {
            Switch = Switch,
            Set = Set,
            Row = Row,
            Label = Row:FindFirstChildOfClass("TextLabel"),
            Stack = Stack,
        }
    end

    --// ---------- Status Badge: short status line under each feature ----------
    -- state: "off" (hidden) | "waiting" | "active" | "paused" | "invalid"
    function Core.CreateStatusBadge(row)
        local Line = new("Frame", {
            Name = "Status",
            LayoutOrder = 2,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 16),
            Visible = false,
        }, row.Stack)

        local Dot = new("Frame", {
            Position = UDim2.fromOffset(14, 4),
            Size = UDim2.fromOffset(8, 8),
            BackgroundColor3 = Theme.SubText,
            BorderSizePixel = 0,
        }, Line)
        corner(Dot, 4)

        local Text = new("TextLabel", {
            Position = UDim2.fromOffset(28, 0),
            Size = UDim2.new(1, -34, 1, 0),
            BackgroundTransparency = 1,
            Font = Enum.Font.Gotham,
            TextSize = 11,
            RichText = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            TextColor3 = Theme.SubText,
            Text = "",
        }, Line)

        local api = {}
        local state, curText = "off", nil
        local flashText, flashColor, flashToken = nil, nil, 0

        local function render()
            if flashText then
                Line.Visible = true
                Dot.BackgroundColor3 = flashColor
                Text.Text = flashText
                return
            end
            if state == "off" then
                Line.Visible = false
                return
            end
            Line.Visible = true
            Dot.BackgroundColor3 = BADGE_COLORS[state] or Theme.SubText
            Text.Text = curText or ""
        end

        function api.set(s, text)
            if state == s and curText == text then return end
            state, curText = s, text
            render()
        end

        -- Temporary notice, then automatically returns to the base state
        function api.flash(text, seconds, s)
            flashToken += 1
            local my = flashToken
            flashText, flashColor = text, BADGE_COLORS[s or "waiting"] or Theme.SubText
            render()
            task.delay(seconds or 3, function()
                if my == flashToken then
                    flashText = nil
                    render()
                end
            end)
        end

        return api
    end

    --// ---------- Self-sizing "label + input box + switch" row ----------
    -- opts: { placeholder, max }
    function Core.CreateToggleWithBox(parent, title, opts)
        opts = opts or {}
        local R = Core.CreateToggleRow(parent, title)
        local Row, Label = R.Row, R.Label
        local boxH = UserInputService.TouchEnabled and 34 or 30

        local Box = new("TextBox", {
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 100, 0.5, 0),
            Size = UDim2.new(1, -176, 0, boxH),
            BackgroundColor3 = Theme.PanelAlt,
            BorderSizePixel = 0,
            Text = "",
            PlaceholderText = opts.placeholder or "Value",
            PlaceholderColor3 = Theme.SubText,
            ClearTextOnFocus = false,
            Font = Enum.Font.Gotham,
            TextSize = 14,
            TextColor3 = Theme.Text,
            ClipsDescendants = true,
        }, Row)
        corner(Box, 6)
        local BoxStroke = stroke(Box)

        new("UISizeConstraint", {
            MinSize = Vector2.new(48, 0),
            MaxSize = Vector2.new(110, math.huge),
        }, Box)

        -- Label width is measured from the actual text
        local labelW = TextService:GetTextSize(Label.Text, Label.TextSize, Label.Font, Vector2.new(1000, 50)).X + 4
        Label.TextTruncate = Enum.TextTruncate.AtEnd

        -- Narrow window: the box drops below the label
        local function relayout()
            local rowW = Row.AbsoluteSize.X
            local stacked = rowW > 0 and rowW < 300
            local lw = labelW
            if rowW > 0 then lw = math.min(labelW, math.max(40, rowW * 0.45)) end

            Label.Position = UDim2.new(0, 14, 0, stacked and 4 or 0)
            Label.Size = stacked and UDim2.new(0, lw, 0, 32) or UDim2.new(0, lw, 1, 0)
            if stacked then
                Row.Size = UDim2.new(Row.Size.X.Scale, Row.Size.X.Offset, 0, 76)
                Box.AnchorPoint = Vector2.new(0, 0)
                Box.Position = UDim2.new(0, 14, 0, 40)
                Box.Size = UDim2.new(1, -(14 + 70 + 6), 0, boxH)
            else
                Row.Size = UDim2.new(Row.Size.X.Scale, Row.Size.X.Offset, 0, 50)
                Box.AnchorPoint = Vector2.new(0, 0.5)
                Box.Position = UDim2.new(0, 14 + lw + 6, 0.5, 0)
                Box.Size = UDim2.new(1, -(14 + lw + 6 + 70), 0, boxH)
            end
        end
        relayout()
        Row:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)

        -- While typing, only filter characters; write the normalized value once the box loses focus
        Box:GetPropertyChangedSignal("Text"):Connect(function()
            local clean = Core.SanitizeNumber(Box.Text)
            if clean ~= Box.Text then Box.Text = clean end
        end)
        bindBoxFocus(Box, BoxStroke)
        Box.FocusLost:Connect(function()
            local r = Core.ParseNumericInput(Box.Text, { max = opts.max })
            if (r.status == "ok" or r.status == "clamped") and Box.Text ~= r.text then
                Box.Text = r.text
            end
        end)

        R.Box = Box
        R.flashError = function() flashStrokeError(BoxStroke) end
        return R
    end

    --// ---------- Preset: row of quick-value buttons under the input box ----------
    -- presets: { { label = "Original", noHighlight = true|nil, value = function(original) ... end | number }, ... }
    -- opts: { getOriginal = function() return number|nil end }
    function Core.CreatePresetRow(row, presets, opts)
        local getOriginal = opts and opts.getOriginal

        local Bar = new("Frame", {
            Name = "Presets",
            LayoutOrder = 3,
            BackgroundTransparency = 1,
            AutomaticSize = Enum.AutomaticSize.Y,
            Size = UDim2.new(1, 0, 0, 0),
        }, row.Stack)
        padding(Bar, 14, 14, 0, 4)
        list(Bar, 6, { FillDirection = Enum.FillDirection.Horizontal, Wraps = true })

        local function valueOf(p)
            local v = p.value
            if type(v) ~= "function" then return v end
            local ok, r = pcall(v, getOriginal and getOriginal() or nil)
            return ok and r or nil
        end

        local chips = {}
        for i, p in ipairs(presets) do
            local chip = new("TextButton", {
                LayoutOrder = i,
                Size = UDim2.fromOffset(52, 32),
                Text = p.label,
                RichText = true,
                BackgroundColor3 = Theme.PanelAlt,
                BorderSizePixel = 0,
                Font = Enum.Font.GothamBold,
                TextSize = 12,
                TextColor3 = Theme.Text,
            }, Bar)
            corner(chip, 6)
            chips[i] = { btn = chip, stroke = stroke(chip), preset = p }

            chip.Activated:Connect(function()
                if isLocked() then return end
                local v = valueOf(p)
                if v then row.Box.Text = Core.FormatValue(v) end
            end)
        end

        local api = {}
        -- Highlight the button whose value matches the currently applied value
        function api.markActive(effective)
            for _, c in ipairs(chips) do
                local v = valueOf(c.preset)
                local on = not c.preset.noHighlight and effective ~= nil and v ~= nil and math.abs(v - effective) < 0.005
                c.btn.TextColor3 = on and Theme.Sakura or Theme.Text
                c.stroke.Color = on and Theme.AccentPink or Theme.Border
            end
        end
        return api
    end

    --// ---------- Winbox mode selector + floating mode list ----------
    -- The Winbox is right-aligned and sized to its content (growing to the left), with centered text;
    -- a down-arrow button sits on the right edge. Tapping it opens the list right below the winbox
    -- (with a small gap, right edges aligned). While the list is open, the UI underneath is disabled;
    -- picking a mode or tapping outside the list hides the list.
    local DD = { layer = nil, panel = nil, close = nil }
    local DD_GAP, DD_ITEM_H, DD_ARROW_W = 5, 32, 26
    local DD_SIZE, DD_LIST_SIZE = 13, 14

    function Core.CloseDropdown()
        if DD.close then DD.close() end
    end

    local function ensureDropdownLayer()
        if DD.layer and DD.layer.Parent then return DD.layer end

        local layer = new("Frame", {
            Name = "ModeDropdownLayer",
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Visible = false,
            ZIndex = 100,
        }, ScreenGui)

        -- Full-screen blocker: disables the UI underneath (without dimming) and catches taps outside
        local blocker = new("TextButton", {
            Name = "Blocker",
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Text = "",
            AutoButtonColor = false,
            ZIndex = 100,
        }, layer)
        blocker.Activated:Connect(function() Core.CloseDropdown() end)

        -- Same theme as MainUI
        local panel = new("Frame", {
            Name = "Panel",
            BackgroundColor3 = Theme.Panel,
            BorderSizePixel = 0,
            Active = true,
            ZIndex = 101,
        }, layer)
        corner(panel, 8)
        stroke(panel)
        list(panel, 2)
        padding(panel, 4, 4, 4, 4)

        DD.layer, DD.panel = layer, panel
        return layer
    end

    local function measureText(text, size)
        return TextService:GetTextSize(text, size, Enum.Font.Gotham, Vector2.new(1000, 28)).X
    end

    -- modes: { { id = "bright", label = "Bright" }, ... }
    -- onSelect(mode, index) is called when the user selects a mode
    function Core.CreateModeDropdown(parent, modes, startIndex, onSelect)
        local index = startIndex or 1

        local Winbox = new("Frame", {
            Name = "ModeWinbox",
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -14, 0.5, 0),
            Size = UDim2.fromOffset(100, 28),
            BackgroundColor3 = Theme.PanelAlt,
            BorderSizePixel = 0,
        }, parent)
        corner(Winbox, 6)
        stroke(Winbox)

        -- Text centered across the whole winbox (from the left edge to the right edge of the arrow button)
        local Label = new("TextLabel", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Font = Enum.Font.Gotham,
            TextSize = DD_SIZE,
            TextColor3 = Theme.Text,
            Text = "",
        }, Winbox)

        new("TextLabel", {
            Name = "Arrow",
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, 0, 0, 0),
            Size = UDim2.new(0, DD_ARROW_W, 1, 0),
            BackgroundTransparency = 1,
            Font = Enum.Font.GothamBold,
            TextSize = 16,
            TextColor3 = Theme.SubText,
            Text = "▼",
        }, Winbox)

        local Hit = new("TextButton", {
            Name = "Hit",
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Text = "",
            AutoButtonColor = false,
            ZIndex = 3,
        }, Winbox)

        local function setIndex(i, silent)
            index = i
            local m = modes[i]
            Label.Text = m.label
            -- Sized to its content, leaving room for the arrow button on both sides so the text sits exactly in the center
            Winbox.Size = UDim2.fromOffset(math.max(84, measureText(m.label, DD_SIZE) + 2 * (DD_ARROW_W + 6)), 28)
            if not silent and onSelect then onSelect(m, i) end
        end

        local function close()
            if DD.layer then DD.layer.Visible = false end
            DD.close = nil
        end

        local function open()
            if isLocked() then return end
            Core.CloseDropdown()
            local layer = ensureDropdownLayer()
            local panel = DD.panel

            for _, c in ipairs(panel:GetChildren()) do
                if c:IsA("TextButton") then c:Destroy() end
            end

            local maxW = 0
            for i, m in ipairs(modes) do
                maxW = math.max(maxW, measureText(m.label, DD_LIST_SIZE))
                local selected = (i == index)
                local item = new("TextButton", {
                    LayoutOrder = i,
                    Size = UDim2.new(1, 0, 0, DD_ITEM_H),
                    BackgroundColor3 = Theme.Text,
                    BackgroundTransparency = selected and 0.88 or 1,
                    BorderSizePixel = 0,
                    AutoButtonColor = false,
                    Text = m.label,
                    Font = selected and Enum.Font.GothamBold or Enum.Font.Gotham,
                    TextSize = DD_LIST_SIZE,
                    TextColor3 = selected and Theme.Sakura or Theme.Text,
                    ZIndex = 102,
                }, panel)
                corner(item, 6)
                item.Activated:Connect(function()
                    close()
                    setIndex(i)
                end)
            end

            local tb = UserInputService:GetFocusedTextBox()
            if tb then tb:ReleaseFocus() end

            layer.Visible = true
            local lp, ls = layer.AbsolutePosition, layer.AbsoluteSize
            local ap, as = Winbox.AbsolutePosition, Winbox.AbsoluteSize

            local w = math.max(as.X, maxW + 32)
            local h = #modes * DD_ITEM_H + (#modes - 1) * 2 + 8
            local x = ap.X + as.X - lp.X                      -- right edge aligned with the winbox
            local below = ap.Y + as.Y - lp.Y + DD_GAP
            local above = ap.Y - lp.Y - DD_GAP

            -- Opens right below by default; only flips above when there isn't enough room below
            if below + h > ls.Y - 6 and above - h >= 6 then
                panel.AnchorPoint = Vector2.new(1, 1)
                panel.Position = UDim2.fromOffset(x, above)
            else
                panel.AnchorPoint = Vector2.new(1, 0)
                panel.Position = UDim2.fromOffset(x, below)
            end
            panel.Size = UDim2.fromOffset(w, h)
            DD.close = close
        end

        Hit.Activated:Connect(open)
        setIndex(index, true)
    end

    --// ---------- Small shared helpers ----------
    -- UIStroke on a TextButton/TextBox/TextLabel outlines the TEXT by default (Contextual mode);
    -- these strokes are meant to draw the border, so the mode is set explicitly.
    function Core.BorderStroke(inst, color, thickness)
        local s = stroke(inst, color, thickness)
        s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        return s
    end

    function Core.Tween(inst, time, props)
        TweenService:Create(inst, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
    end

    function Core.Label(parent, props)
        props.BackgroundTransparency = 1
        props.Font = props.Font or Enum.Font.Gotham
        props.TextColor3 = props.TextColor3 or Theme.Text
        props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
        return new("TextLabel", props, parent)
    end

    function Core.Trim(s)
        return (s:gsub("^%s+", ""):gsub("%s+$", ""))
    end

    -- Cuts a string to at most maxChars characters (UTF-8 safe)
    function Core.ClipText(s, maxChars)
        local cut = utf8.offset(s, maxChars + 1)
        if cut then return s:sub(1, cut - 1) end
        return s
    end

    -- Escapes text that goes into a RichText label
    function Core.EscapeRich(s)
        return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
    end

    --// ---------- Teleport: shared by Click TP, Waypoints and Players ----------
    -- History keeps the spot you stood on before the last teleport, so "Back" can undo it.
    Core.History = { cf = nil, listeners = {} }

    function Core.TeleportTo(cf)
        local root = Core.GetRoot()
        if not root then return false end
        Core.History.cf = root.CFrame
        root.CFrame = cf
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        for _, fn in ipairs(Core.History.listeners) do pcall(fn) end
        return true
    end

    -- Jump back to the previous spot. The current spot becomes the new "previous", so pressing it twice toggles.
    function Core.GoBack()
        local target = Core.History.cf
        if not target then return false end
        return Core.TeleportTo(target)
    end

    --// ---------- Button: pill button with hover / press feedback ----------
    -- opts: { size, position, anchor, order, name, textSize, radius, variant = "default" | "accent" }
    -- return: { Button, onClick(fn), setText(text), setEnabled(on), setActive(on), flash(text, seconds, isError) }
    function Core.CreateButton(parent, text, opts)
        opts = opts or {}
        local accent = opts.variant == "accent"
        local restBg = accent and Theme.ToggleKnobOn or Theme.Header
        local restText = accent and Theme.ToggleKnobOn or Theme.Text

        local Btn = new("TextButton", {
            Name = opts.name or "Button",
            AnchorPoint = opts.anchor,
            Position = opts.position,
            LayoutOrder = opts.order or 0,
            Size = opts.size or UDim2.fromOffset(70, 28),
            BackgroundColor3 = restBg,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Text = accent and "" or text,
            RichText = true,
            Font = Enum.Font.GothamBold,
            TextSize = opts.textSize or 13,
            TextColor3 = restText,
            TextTruncate = Enum.TextTruncate.AtEnd,
        }, parent)
        corner(Btn, opts.radius or 6)

        -- Accent buttons: a UIGradient tints everything its own object draws (text included), so the
        -- caption is a child label. Default buttons draw their text themselves.
        local BtnStroke
        local Caption = Btn
        if accent then
            new("UIGradient", { Color = ColorSequence.new(Theme.AccentPurple, Theme.AccentPink) }, Btn)
            Caption = new("TextLabel", {
                Name = "Caption",
                Size = UDim2.fromScale(1, 1),
                BackgroundTransparency = 1,
                Text = text,
                RichText = true,
                Font = Enum.Font.GothamBold,
                TextSize = opts.textSize or 13,
                TextColor3 = restText,
                TextTruncate = Enum.TextTruncate.AtEnd,
            }, Btn)
        else
            BtnStroke = Core.BorderStroke(Btn)
        end
        local Scale = new("UIScale", { Scale = 1 }, Btn)

        local api = { Button = Btn }
        local enabled, hovered = true, false
        local baseText, flashToken = text, 0
        local textColor = restText

        local function paint()
            if accent then
                local t = enabled and (hovered and 0.15 or 0) or 0.55
                Core.Tween(Btn, 0.12, { BackgroundTransparency = t })
            else
                local c = (enabled and hovered) and Theme.Border or restBg
                Core.Tween(Btn, 0.12, { BackgroundColor3 = c })
            end
        end

        Btn.MouseEnter:Connect(function()
            hovered = true
            paint()
        end)
        Btn.MouseLeave:Connect(function()
            hovered = false
            paint()
            Core.Tween(Scale, 0.1, { Scale = 1 })
        end)
        Btn.MouseButton1Down:Connect(function()
            if enabled then Core.Tween(Scale, 0.08, { Scale = 0.95 }) end
        end)
        Btn.MouseButton1Up:Connect(function()
            Core.Tween(Scale, 0.12, { Scale = 1 })
        end)

        function api.onClick(fn)
            Btn.Activated:Connect(function()
                if isLocked() or not enabled then return end
                fn()
            end)
        end

        function api.setText(t)
            baseText = t
            flashToken += 1                              -- a pending flash must not overwrite the new text
            Caption.Text = t
            Caption.TextColor3 = textColor
        end

        function api.setEnabled(on)
            enabled = on and true or false
            Caption.TextTransparency = enabled and 0 or 0.5
            if BtnStroke then BtnStroke.Transparency = enabled and 0 or 0.5 end
            paint()
        end

        -- Highlighted look for toggle-like buttons (e.g. "Stop" while spectating)
        function api.setActive(on)
            if accent then return end
            textColor = on and Theme.Sakura or Theme.Text
            Caption.TextColor3 = textColor
            BtnStroke.Color = on and Theme.AccentPink or Theme.Border
        end

        -- Temporary label on the button, then back to the base text
        function api.flash(t, seconds, isError)
            flashToken += 1
            local my = flashToken
            Caption.Text = t
            if not accent then Caption.TextColor3 = isError and Theme.Danger or Theme.Sakura end
            task.delay(seconds or 1.2, function()
                if my == flashToken and Btn.Parent then
                    Caption.Text = baseText
                    Caption.TextColor3 = textColor
                end
            end)
        end

        return api
    end

    --// ---------- Chevron: arrow drawn from two rotated bars (no font glyph needed) ----------
    -- props: layout of the holder frame. Rotate the returned holder to animate it (0 = pointing down).
    -- return: holder, setColor(color)
    function Core.CreateChevron(parent, props, color, len, thick)
        len, thick = len or 8, thick or 2
        props.BackgroundTransparency = 1
        local Holder = new("Frame", props, parent)

        local dx = len * 0.3536                                    -- half of the bar's horizontal extent at 45 degrees
        local bars = {}
        for i, rot in ipairs({ 45, -45 }) do
            bars[i] = new("Frame", {
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.new(0.5, (i == 1) and -dx or dx, 0.5, 0),
                Size = UDim2.fromOffset(len, thick),
                Rotation = rot,
                BackgroundColor3 = color or Theme.SubText,
                BorderSizePixel = 0,
            }, Holder)
            corner(bars[i], thick / 2)
        end

        return Holder, function(c)
            for _, b in ipairs(bars) do b.BackgroundColor3 = c end
        end
    end

    --// ---------- Section: collapsible group ----------
    -- opts: { subtitle = "what is inside", collapsed = true }
    function Core.CreateSectionGroup(parent, title, order, opts)
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

        local HEADER_REST = Theme.Header
        local HEADER_HOVER = Theme.Header:Lerp(Theme.Border, 0.35)

        local Header = new("TextButton", {
            Name = "Header",
            LayoutOrder = 0,
            Size = UDim2.new(1, 0, 0, 52),
            Text = "",
            BackgroundColor3 = HEADER_REST,
            BorderSizePixel = 0,
            AutoButtonColor = false,
        }, Root)
        corner(Header, 8)
        Core.BorderStroke(Header)

        -- Accent bar on the left: pink while something in this section is on
        local Bar = new("Frame", {
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 8, 0.5, 0),
            Size = UDim2.fromOffset(3, 26),
            BackgroundColor3 = Theme.Border,
            BorderSizePixel = 0,
        }, Header)
        corner(Bar, 2)

        Core.Label(Header, {
            Position = UDim2.fromOffset(20, 8),
            Size = UDim2.new(1, -118, 0, 20),
            Font = Enum.Font.GothamBold,
            TextSize = 14,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Text = title,
        })
        Core.Label(Header, {
            Position = UDim2.fromOffset(20, 28),
            Size = UDim2.new(1, -118, 0, 16),
            TextSize = 11,
            TextColor3 = Theme.SubText,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Text = opts.subtitle or "",
        })

        -- "N on" pill
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
        local PillText = Core.Label(Pill, {
            Size = UDim2.fromScale(1, 1),
            Font = Enum.Font.GothamBold,
            TextSize = 11,
            TextColor3 = Theme.ToggleKnobOn,
            TextXAlignment = Enum.TextXAlignment.Center,
            Text = "",
        })

        local Chevron, setChevronColor = Core.CreateChevron(Header, {
            Name = "Chevron",
            AnchorPoint = Vector2.new(0.5, 0.5),
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
                Core.Tween(Chevron, 0.15, { Rotation = rot })
                Core.Tween(Bar, 0.15, { BackgroundColor3 = barColor })
            else
                Chevron.Rotation = rot
                Bar.BackgroundColor3 = barColor
            end
            setChevronColor(open and Theme.Text or Theme.SubText)
            Pill.Visible = activeCount > 0
            PillText.Text = activeCount .. " on"
        end

        Header.MouseEnter:Connect(function()
            Core.Tween(Header, 0.12, { BackgroundColor3 = HEADER_HOVER })
        end)
        Header.MouseLeave:Connect(function()
            Core.Tween(Header, 0.12, { BackgroundColor3 = HEADER_REST })
        end)
        Header.Activated:Connect(function()
            if isLocked() then return end
            open = not open
            render(true)
        end)

        -- Attach the handle from BindToggle so the header shows how many features are on
        function api.trackSwitch(handle)
            handle.onChanged(function(on)
                activeCount = math.max(0, activeCount + (on and 1 or -1))
                render(true)
            end)
        end

        render(false)
        api.Body = Body
        return api
    end

    --// ---------- Text input: rounded box with the same focus glow as the number boxes ----------
    -- opts: { size, position, anchor, order }
    -- return: Box, BoxStroke
    function Core.CreateInput(parent, placeholder, opts)
        opts = opts or {}
        local Box = new("TextBox", {
            Name = "Input",
            AnchorPoint = opts.anchor,
            Position = opts.position,
            LayoutOrder = opts.order or 0,
            Size = opts.size or UDim2.new(1, 0, 0, UserInputService.TouchEnabled and 34 or 30),
            BackgroundColor3 = Theme.PanelAlt,
            BorderSizePixel = 0,
            Text = "",
            PlaceholderText = placeholder,
            PlaceholderColor3 = Theme.SubText,
            ClearTextOnFocus = false,
            Font = Enum.Font.Gotham,
            TextSize = 14,
            TextColor3 = Theme.Text,
            TextXAlignment = Enum.TextXAlignment.Left,
            ClipsDescendants = true,
        }, parent)
        corner(Box, 6)
        local BoxStroke = Core.BorderStroke(Box)
        padding(Box, 10, 10)
        bindBoxFocus(Box, BoxStroke)
        return Box, BoxStroke
    end

    --// ---------- Note: small right-aligned text that can flash a message, then fall back to its base text ----------
    -- props: layout of the label. return: { Label, setBase(text), flash(text, isError, seconds) }
    function Core.CreateNote(parent, props)
        props.TextSize = props.TextSize or 12
        props.TextXAlignment = Enum.TextXAlignment.Right
        props.TextColor3 = Theme.SubText
        props.TextTruncate = Enum.TextTruncate.AtEnd
        local L = Core.Label(parent, props)
        local base, token = "", 0
        local api = { Label = L }

        function api.setBase(text)
            base = text
            token += 1
            L.Text = text
            L.TextColor3 = Theme.SubText
        end

        function api.flash(text, isError, seconds)
            token += 1
            local my = token
            L.Text = text
            L.TextColor3 = isError and Theme.Danger or Theme.Sakura
            task.delay(seconds or 1.8, function()
                if my == token and L.Parent then
                    L.Text = base
                    L.TextColor3 = Theme.SubText
                end
            end)
        end

        return api
    end

    --// =====================================================
    --//  FEATURES
    --// =====================================================

    --// ---------------- Speed / Jump Boost ----------------
    -- cfg: { title, max, props, snapshot, apply, restore, getValue, isApplied, fromSnapshot, presets }
    function Features.CreateHumanoidBoost(parent, cfg)
        local row = Core.CreateToggleWithBox(parent, cfg.title, { max = cfg.max })
        local badge = Core.CreateStatusBadge(row)
        local snaps = setmetatable({}, { __mode = "k" })
        local tracker, currentHum, presetApi
        local active = false
        local parsed = { status = "empty" }
        local overrides = { n = 0, t = 0, pausedUntil = 0 }

        local function reparse()
            parsed = Core.ParseNumericInput(row.Box.Text, { max = cfg.max })
        end
        reparse()

        -- The game's original value: taken from the snapshot if running, otherwise read directly
        local function getOriginal()
            local hum = Core.GetHumanoid()
            if not hum then return nil end
            local st = snaps[hum]
            if st ~= nil then return cfg.fromSnapshot(st) end
            local ok, v = pcall(cfg.getValue, hum)
            if ok and type(v) == "number" then return v end
            return nil
        end

        local function showActive(v)
            local word = (parsed.status == "clamped") and "Capped" or "Running"
            badge.set("active", word .. Core.DOT .. Core.FormatValue(v))
        end

        local function applyTo(hum)
            local v = parsed.effective
            if not v then
                if snaps[hum] ~= nil then
                    cfg.restore(hum, snaps[hum])
                    snaps[hum] = nil
                end
                badge.set("paused", "Waiting for value")
                return
            end
            if snaps[hum] == nil then snaps[hum] = cfg.snapshot(hum) end
            cfg.apply(hum, v)
            showActive(v)
        end

        -- The game (or another script) changes the value: treat the new value as the new "original" and reapply.
        -- Limited to at most 30 times per second so we don't constantly fight the game.
        local function onExternal(hum)
            if hum ~= currentHum or snaps[hum] == nil then return end
            local v = parsed.effective
            if not v or cfg.isApplied(hum, v) then return end

            local now = os.clock()
            if now < overrides.pausedUntil then return end
            if now - overrides.t > 1 then
                overrides.t, overrides.n = now, 0
            end
            overrides.n += 1
            if overrides.n > 30 then
                overrides.pausedUntil = now + 1
                badge.set("paused", "Overridden by game")
                return
            end

            snaps[hum] = cfg.snapshot(hum)
            cfg.apply(hum, v)
            showActive(v)
        end

        local function start()
            reparse()
            if parsed.effective == nil then
                badge.flash("Enter a valid value", 2.5, "invalid")
                row.flashError()
                return false
            end
            active = true
            badge.set("waiting", "Waiting for character")

            tracker = Core.TrackCharacter(LocalPlayer, function(_, hum)
                currentHum = hum
                applyTo(hum)
                local sigs = {}
                for _, prop in ipairs(cfg.props) do
                    sigs[#sigs + 1] = hum:GetPropertyChangedSignal(prop):Connect(function()
                        onExternal(hum)
                    end)
                end
                return function()
                    for _, s in ipairs(sigs) do s:Disconnect() end
                    if snaps[hum] ~= nil and hum.Parent then cfg.restore(hum, snaps[hum]) end
                    snaps[hum] = nil
                    if currentHum == hum then currentHum = nil end
                end
            end)
        end

        local function stop()
            active = false
            if tracker then tracker.destroy() tracker = nil end
            currentHum = nil
            badge.set("off")
        end

        -- Prefill the input box with the Humanoid's current value (if the box is empty)
        local function prefill()
            task.spawn(function()
                local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
                local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 10)
                if not hum then return end
                local ok, v = pcall(cfg.getValue, hum)
                if ok and type(v) == "number" and v == v and row.Box.Parent and row.Box.Text == "" then
                    row.Box.Text = Core.FormatValue(v)
                end
            end)
        end
        prefill()

        row.Box:GetPropertyChangedSignal("Text"):Connect(function()
            reparse()
            if presetApi then presetApi.markActive(parsed.effective) end
            if active and currentHum then applyTo(currentHum) end
        end)

        local handle = Core.BindToggle(row.Switch, row.Set, {
            start = start,
            stop = stop,
            badge = badge,
            onReset = function()
                row.Box.Text = ""
                prefill()
            end,
        })

        presetApi = Core.CreatePresetRow(row, cfg.presets, { getOriginal = getOriginal })
        presetApi.markActive(parsed.effective)
        return handle
    end

    local function boostPresets(maxValue)
        return {
            { label = "Original", noHighlight = true, value = function(o) return o end },
            { label = '<font size="20">×</font>2',  value = function(o) return o and o * 2 end },
            { label = '<font size="20">×</font>4',  value = function(o) return o and o * 4 end },
            { label = "Max", value = maxValue },
        }
    end

    local SPEED_CFG = {
        title = "Speed", max = 1000,
        props = { "WalkSpeed" },
        snapshot = function(hum) return hum.WalkSpeed end,
        apply = function(hum, v) if hum.WalkSpeed ~= v then hum.WalkSpeed = v end end,
        restore = function(hum, ws) hum.WalkSpeed = ws end,
        getValue = function(hum) return hum.WalkSpeed end,
        isApplied = function(hum, v) return math.abs(hum.WalkSpeed - v) < 1e-3 end,
        fromSnapshot = function(st) return st end,
        presets = boostPresets(1000),
    }

    local JUMP_CFG = {
        title = "Jump Boost", max = 1000,
        props = { "JumpPower", "UseJumpPower" },
        snapshot = function(hum)
            return { use = hum.UseJumpPower, power = hum.JumpPower, height = hum.JumpHeight }
        end,
        apply = function(hum, v)
            if not hum.UseJumpPower then hum.UseJumpPower = true end
            if hum.JumpPower ~= v then hum.JumpPower = v end
        end,
        restore = function(hum, st)
            hum.JumpPower = st.power
            hum.JumpHeight = st.height
            hum.UseJumpPower = st.use
        end,
        getValue = function(hum)
            if hum.UseJumpPower then return hum.JumpPower end
            -- The game uses JumpHeight -> convert to the equivalent JumpPower
            return math.sqrt(2 * Workspace.Gravity * hum.JumpHeight)
        end,
        isApplied = function(hum, v)
            return hum.UseJumpPower and math.abs(hum.JumpPower - v) < 1e-3
        end,
        fromSnapshot = function(st)
            if st.use then return st.power end
            return math.sqrt(2 * Workspace.Gravity * st.height)
        end,
        presets = boostPresets(1000),
    }

    --// ---------------- Infinite Jump ----------------
    function Features.CreateInfiniteJump(parent)
        local Switch, Set = CreateToggleOption(parent, "Infinite Jump", 50)
        local conn

        return Core.BindToggle(Switch, Set, {
            start = function()
                conn = UserInputService.JumpRequest:Connect(function()
                    local hum = Core.GetHumanoid()
                    if hum and hum.Health > 0 then
                        hum:ChangeState(Enum.HumanoidStateType.Jumping)
                    end
                end)
            end,
            stop = function()
                if conn then conn:Disconnect() conn = nil end
            end,
        })
    end

    --// ---------------- Noclip ----------------
    function Features.CreateNoclip(parent)
        local row = Core.CreateToggleRow(parent, "Noclip")
        local badge = Core.CreateStatusBadge(row)
        local tracker

        local function start()
            badge.set("waiting", "Waiting for character")
            tracker = Core.TrackCharacter(LocalPlayer, function(char)
                local parts, original, conns = {}, {}, {}

                local function add(inst)
                    if inst:IsA("BasePart") and original[inst] == nil then
                        original[inst] = inst.CanCollide          -- only store the original value once
                        parts[#parts + 1] = inst
                    end
                end
                for _, d in ipairs(char:GetDescendants()) do add(d) end
                conns[1] = char.DescendantAdded:Connect(add)

                -- The Humanoid can re-enable CanCollide every physics step, so Stepped is still needed,
                -- but it only iterates the cached array (no GetDescendants every frame)
                conns[2] = RunService.Stepped:Connect(function()
                    for i = #parts, 1, -1 do
                        local p = parts[i]
                        if p.Parent then
                            if p.CanCollide then p.CanCollide = false end
                        else
                            table.remove(parts, i)
                            original[p] = nil
                        end
                    end
                end)
                badge.set("active", "Running")

                return function()
                    for _, c in ipairs(conns) do c:Disconnect() end
                    for p, was in pairs(original) do
                        if p.Parent then p.CanCollide = was end   -- restore the exact original value
                    end
                end
            end)
        end

        local function stop()
            if tracker then tracker.destroy() tracker = nil end
            badge.set("off")
        end

        return Core.BindToggle(row.Switch, row.Set, { start = start, stop = stop, badge = badge })
    end

    --// ---------------- Fly ----------------
    function Features.CreateFly(parent)
        local DEFAULT, MAX = 60, 1000
        local row = Core.CreateToggleWithBox(parent, "Fly", { placeholder = tostring(DEFAULT), max = MAX })
        local badge = Core.CreateStatusBadge(row)
        local upUntil = 0                                          -- JumpRequest = "go up" for a moment
        local vel = Vector3.zero                                   -- current velocity (a sudden brake can zero it)
        local active, seated = false, false
        local tracker, jumpConn, brakeConn
        local parsed = { status = "empty", effective = DEFAULT }

        local function updateBadge()
            if parsed.status == "ok" then
                badge.set("active", "Flying" .. Core.DOT .. Core.FormatValue(parsed.effective))
            elseif parsed.status == "clamped" then
                badge.set("active", "Capped" .. Core.DOT .. Core.FormatValue(parsed.effective))
            else
                badge.set("active", "Using default " .. DEFAULT)
            end
        end

        local function reparse()
            parsed = Core.ParseNumericInput(row.Box.Text, { max = MAX, default = DEFAULT })
            if active and not seated then updateBadge() end
        end
        row.Box:GetPropertyChangedSignal("Text"):Connect(reparse)
        reparse()

        local function start()
            active, seated = true, false
            reparse()
            badge.set("waiting", "Waiting for character")

            jumpConn = UserInputService.JumpRequest:Connect(function()
                upUntil = os.clock() + 0.25
            end)
            -- X key: sudden brake (instantly sets velocity to 0)
            brakeConn = UserInputService.InputBegan:Connect(function(i, gp)
                if not gp and i.KeyCode == Enum.KeyCode.X then vel = Vector3.zero end
            end)
            Core.LoadControls()                                     -- try loading ControlModule early

            tracker = Core.TrackCharacter(LocalPlayer, function(_, hum, root)
                local snap = { platformStand = hum.PlatformStand, autoRotate = hum.AutoRotate }

                local att = new("Attachment", { Name = "ElyseraFlyAtt" }, root)
                local lv = new("LinearVelocity", {
                    Name = "ElyseraFlyLV",
                    Attachment0 = att,
                    RelativeTo = Enum.ActuatorRelativeTo.World,
                    MaxForce = 1e9,
                    VectorVelocity = Vector3.zero,
                }, root)
                local ao = new("AlignOrientation", {
                    Name = "ElyseraFlyAO",
                    Mode = Enum.OrientationAlignmentMode.OneAttachment,
                    Attachment0 = att,
                    RigidityEnabled = false,
                    MaxTorque = 1e9,
                    Responsiveness = 50,
                }, root)
                hum.PlatformStand = true
                hum.AutoRotate = false
                vel = Vector3.zero
                seated = false
                updateBadge()

                local conn = RunService.RenderStepped:Connect(function(dt)
                    if hum.Health <= 0 or not root.Parent then return end

                    -- Seated: pause Fly instead of forcing PlatformStand
                    if hum.SeatPart then
                        if not seated then
                            seated = true
                            vel = Vector3.zero
                            lv.VectorVelocity = vel
                            badge.set("paused", "Seated")
                        end
                        return
                    elseif seated then
                        seated = false
                        updateBadge()
                    end

                    local speed = parsed.effective or DEFAULT
                    local dir = Core.ReadFlyDirection(upUntil)        -- along the camera direction
                    vel = vel:Lerp(dir * speed, math.clamp(dt / 0.12, 0, 1))
                    lv.VectorVelocity = vel

                    local cam = Workspace.CurrentCamera
                    if cam then
                        local look = cam.CFrame.LookVector
                        look = Vector3.new(look.X, 0, look.Z)
                        if look.Magnitude > 0.001 then
                            ao.CFrame = CFrame.lookAt(Vector3.zero, look)
                        end
                    end
                end)

                return function()                                    -- respawn / death / turned off
                    conn:Disconnect()
                    lv:Destroy()
                    ao:Destroy()
                    att:Destroy()
                    if hum.Parent then
                        hum.PlatformStand = snap.platformStand       -- restore the exact original state
                        hum.AutoRotate = snap.autoRotate
                    end
                end
            end, { onDied = true })
        end

        local function stop()
            active, seated = false, false
            if jumpConn then jumpConn:Disconnect() jumpConn = nil end
            if brakeConn then brakeConn:Disconnect() brakeConn = nil end
            if tracker then tracker.destroy() tracker = nil end
            vel = Vector3.zero
            badge.set("off")
        end

        local handle = Core.BindToggle(row.Switch, row.Set, {
            start = start,
            stop = stop,
            badge = badge,
            onReset = function() row.Box.Text = "" end,
        })

        Core.CreatePresetRow(row, {
            { label = "30",  value = 30 },
            { label = "60",  value = 60 },
            { label = "120", value = 120 },
            { label = "250", value = 250 },
        })
        return handle
    end

    --// ---------------- Full Bright ----------------
    local FB_MODES = {
        { id = "bright", label = "Bright" },
        { id = "fog",    label = "Bright + no fog" },
        { id = "perf",   label = "Performance" },
    }

    -- Lighting.Color3 helper: lift each channel to at least `floor`
    local function liftColor(c, floor)
        return Color3.new(math.max(c.R, floor), math.max(c.G, floor), math.max(c.B, floor))
    end

    -- Only brightens, never darker than the original map
    local function fullBrightProps(modeId)
        local props = {
            Brightness           = function(b) return math.max(b, 2) end,
            Ambient              = function(c) return liftColor(c, 0.6) end,
            OutdoorAmbient       = function(c) return liftColor(c, 0.5) end,
            ExposureCompensation = function(e) return math.max(e, 0.3) end,
        }
        if modeId == "fog" or modeId == "perf" then
            props.FogEnd = function(f) return math.max(f, 100000) end
        end
        if modeId == "perf" then
            props.GlobalShadows = function() return false end
        end
        return props
    end

    function Features.CreateFullBright(parent)
        local row = Core.CreateToggleRow(parent, "Full Bright")
        local badge = Core.CreateStatusBadge(row)

        -- Winbox mode selector row (right-aligned, below the name + switch)
        local ModeRow = new("Frame", {
            Name = "ModeRow",
            LayoutOrder = 3,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 36),
        }, row.Stack)

        local mode = FB_MODES[1]
        local handle

        -- Lighting bookkeeping: base = the game's own value, last = the value read back after our write
        -- (float properties get rounded, so compare against the value read back, not the value we assigned)
        local claim, base, last, conns = nil, {}, {}, {}
        local writing = false

        local function write(p)
            local v = claim[p](base[p])
            if Lighting[p] ~= v then
                writing = true                                -- our own write must not count as a game change
                Lighting[p] = v
                writing = false
            end
            last[p] = Lighting[p]
        end

        -- Give a property back to the game and stop watching it
        local function giveBack(p)
            local c = conns[p]
            if c then c:Disconnect() conns[p] = nil end
            local b = base[p]
            base[p], last[p] = nil, nil
            if b ~= nil and Lighting[p] ~= b then Lighting[p] = b end
        end

        local function apply()
            local props = fullBrightProps(mode.id)
            if claim then
                for p in pairs(claim) do                     -- properties the previous mode touched but this one doesn't
                    if not props[p] then giveBack(p) end
                end
            end
            claim = props
            for p in pairs(props) do
                if not conns[p] then
                    base[p] = Lighting[p]
                    conns[p] = Lighting:GetPropertyChangedSignal(p):Connect(function()
                        if writing or not claim or not claim[p] then return end
                        local now = Lighting[p]
                        if now == last[p] then return end    -- written by us
                        base[p] = now                         -- the game changed it: new baseline
                        write(p)
                    end)
                end
                write(p)
            end
            badge.set("active", mode.label)
        end

        local function release()
            if claim then
                for p in pairs(claim) do giveBack(p) end
                claim = nil
            end
            badge.set("off")
        end

        handle = Core.BindToggle(row.Switch, row.Set, { start = apply, stop = release, badge = badge })

        Core.CreateModeDropdown(ModeRow, FB_MODES, 1, function(m)
            mode = m
            if handle.isOn() then apply() end
        end)
        return handle
    end

    --// ---------------- ESP ----------------
    -- ESP settings. The "Hide ..." switches default to OFF (= fully visible) because
    -- CreateToggleOption doesn't support presetting ON.
    function Features.CreateEspOptions(Card, onChange)
        local opts = {
            teamMode = false,
            occluded = false,
            hide = { name = false, dist = false, hp = false, team = false },
        }
        local items = {}
        local order = 2

        local function bind(label, apply)
            local Holder = new("Frame", {
                LayoutOrder = order,
                Size = UDim2.new(1, 0, 0, 40),
                BackgroundTransparency = 1,
            }, Card)
            order += 1
            padding(Holder, 18)

            local sw, set = CreateToggleOption(Holder, label, 40)
            sw.Parent.BackgroundColor3 = Theme.PanelAlt
            sw:GetAttributeChangedSignal("Toggled"):Connect(function()
                apply(sw:GetAttribute("Toggled") == true)
                onChange(opts)
            end)

            -- Dim overlay + click blocker while ESP is off
            local Dim = new("Frame", {
                Size = UDim2.fromScale(1, 1),
                BackgroundColor3 = Color3.new(0, 0, 0),
                BackgroundTransparency = 0.5,
                BorderSizePixel = 0,
                Active = true,
                ZIndex = 50,
            }, Holder)
            corner(Dim, 8)

            items[#items + 1] = { set = set, dim = Dim }
        end

        bind("Esp Team Player", function(on) opts.teamMode = on end)
        bind("Hide Name",       function(on) opts.hide.name = on end)
        bind("Hide Distance",   function(on) opts.hide.dist = on end)
        bind("Hide HP",         function(on) opts.hide.hp = on end)
        bind("Hide Team",       function(on) opts.hide.team = on end)
        bind("Only when visible", function(on) opts.occluded = on end)

        local ui = {}
        function ui.setEnabled(enabled)
            for _, it in ipairs(items) do it.dim.Visible = not enabled end
        end
        function ui.reset()
            for _, it in ipairs(items) do it.set(false) end
        end
        return opts, ui
    end

    -- ESP is event-driven and shows every player (no limit on distance / player count).
    -- opts: { teamMode, occluded, hide = { name, dist, hp, team } }
    function Features.CreateEspController(opts)
        local entries, trackers, conns, folder, stopLoop = {}, {}, {}, nil, nil

        local function teamColor(p)
            if not opts.teamMode then return WHITE end
            local mine, theirs = LocalPlayer.Team, p.Team
            if not mine or not theirs then return WHITE end         -- no team: neutral
            return (mine == theirs) and GREEN or RED
        end

        local function makeLine(parent, order)
            return new("TextLabel", {
                LayoutOrder = order,
                Size = UDim2.new(1, 0, 0, 16),
                BackgroundTransparency = 1,
                Font = Enum.Font.GothamBold,
                TextSize = 13,
                TextColor3 = WHITE,
                TextStrokeColor3 = Color3.new(0, 0, 0),
                TextStrokeTransparency = 0.25,
                Text = "",
            }, parent)
        end

        local function applyStyle(e)
            local h = opts.hide
            e.nameLine.Visible = not h.name
            e.distLine.Visible = not h.dist
            e.hpLine.Visible = not h.hp
            e.teamLine.Visible = (not h.team) and e.teamLine.Text ~= ""
            e.bb.Enabled = e.nameLine.Visible or e.distLine.Visible
                or e.hpLine.Visible or e.teamLine.Visible
            e.bb.AlwaysOnTop = not opts.occluded
            e.hl.DepthMode = opts.occluded and Enum.HighlightDepthMode.Occluded
                or Enum.HighlightDepthMode.AlwaysOnTop
        end

        local function refreshColor(p, e)
            local color = teamColor(p)
            e.hl.OutlineColor = color
            e.nameLine.TextColor3 = color
            e.distLine.TextColor3 = color
            e.teamLine.TextColor3 = color
            e.teamLine.Text = p.Team and p.Team.Name or ""
            applyStyle(e)
        end

        local function refreshHp(e)
            local hp = math.floor(math.min(e.hum.Health, 1e9) + 0.5)
            local maxHp = math.max(1, math.floor(math.min(e.hum.MaxHealth, 1e9) + 0.5))
            if e.hp ~= hp or e.maxHp ~= maxHp then
                e.hp, e.maxHp = hp, maxHp
                e.hpLine.Text = string.format("HP: %d/%d", hp, maxHp)
                e.hpLine.TextColor3 = RED:Lerp(GREEN, math.clamp(hp / maxHp, 0, 1))
            end
        end

        local function buildVisuals(p, e)
            local char = e.char
            e.hl = new("Highlight", {
                Name = "ESP_" .. p.Name,
                Adornee = char,
                DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
                FillTransparency = 1,
                OutlineTransparency = 0,
                OutlineColor = WHITE,
            }, folder)

            e.bb = new("BillboardGui", {
                Name = "ESPInfo_" .. p.Name,
                Adornee = char:FindFirstChild("Head") or e.root,
                AlwaysOnTop = true,
                LightInfluence = 0,
                Size = UDim2.fromOffset(170, 64),
                StudsOffsetWorldSpace = Vector3.new(0, 2.8, 0),
            }, folder)
            list(e.bb, 0, { VerticalAlignment = Enum.VerticalAlignment.Bottom })

            e.nameLine = makeLine(e.bb, 1)
            e.teamLine = makeLine(e.bb, 2)
            e.distLine = makeLine(e.bb, 3)
            e.hpLine   = makeLine(e.bb, 4)

            e.nameLine.Text = p.DisplayName ~= p.Name
                and (p.DisplayName .. " (@" .. p.Name .. ")")
                or p.DisplayName
        end

        local function destroyVisuals(e)
            if e.hl then e.hl:Destroy() e.hl = nil end
            if e.bb then e.bb:Destroy() e.bb = nil end
        end

        local function track(p)
            if p == LocalPlayer or trackers[p] then return end
            trackers[p] = Core.TrackCharacter(p, function(char, hum, root)
                local e = { char = char, hum = hum, root = root, dist = nil, hp = nil, maxHp = nil }
                buildVisuals(p, e)
                entries[p] = e
                refreshColor(p, e)
                refreshHp(e)

                local c1 = hum.HealthChanged:Connect(function() refreshHp(e) end)
                local c2 = hum:GetPropertyChangedSignal("MaxHealth"):Connect(function() refreshHp(e) end)
                local c3 = p:GetPropertyChangedSignal("Team"):Connect(function() refreshColor(p, e) end)
                return function()                                    -- respawn / death / leaving the server
                    c1:Disconnect()
                    c2:Disconnect()
                    c3:Disconnect()
                    destroyVisuals(e)
                    entries[p] = nil
                end
            end, { onDied = true })
        end

        -- 8 times per second: only update the distance text
        local function updateDistances()
            local cam = Workspace.CurrentCamera
            local myRoot = Core.GetRoot()
            local origin = myRoot and myRoot.Position or (cam and cam.CFrame.Position) or Vector3.zero
            for _, e in pairs(entries) do
                if e.distLine and e.root.Parent then
                    local d = math.floor((e.root.Position - origin).Magnitude + 0.5)
                    if e.dist ~= d then
                        e.dist = d
                        e.distLine.Text = d .. "m"
                    end
                end
            end
        end

        local function syncDistanceLoop()
            if opts.hide.dist or not folder then
                if stopLoop then stopLoop() stopLoop = nil end
            elseif not stopLoop then
                local alive = true
                stopLoop = function() alive = false end
                task.spawn(function()
                    while alive do
                        pcall(updateDistances)
                        task.wait(0.125)
                    end
                end)
            end
        end

        local C = {}

        function C.start()
            if folder then return end
            folder = new("Folder", { Name = "ElyseraESP" }, CoreGui)
            for _, p in ipairs(Players:GetPlayers()) do track(p) end
            conns[1] = Players.PlayerAdded:Connect(track)
            conns[2] = Players.PlayerRemoving:Connect(function(p)
                if trackers[p] then
                    trackers[p].destroy()
                    trackers[p] = nil
                end
            end)
            conns[3] = LocalPlayer:GetPropertyChangedSignal("Team"):Connect(function()
                for p, e in pairs(entries) do refreshColor(p, e) end
            end)
            syncDistanceLoop()
        end

        function C.stop()
            if stopLoop then stopLoop() stopLoop = nil end
            for _, c in ipairs(conns) do c:Disconnect() end
            table.clear(conns)
            for p, t in pairs(trackers) do
                t.destroy()
                trackers[p] = nil
            end
            if folder then folder:Destroy() folder = nil end
        end

        -- Called by CreateEspOptions when the user changes a setting
        function C.refreshStyle()
            if not folder then return end
            for p, e in pairs(entries) do refreshColor(p, e) end
            syncDistanceLoop()
            if not opts.hide.dist then updateDistances() end
        end

        return C
    end

    function Features.CreateEsp(parent)
        local Card = CreateCard(parent, "EspPlayer", 10, 10, 10)

        local Switch, Set = CreateToggleOption(Card, "Esp Player", 40)
        Switch.Parent.LayoutOrder = 1
        Switch.Parent.BackgroundColor3 = Theme.PanelAlt

        local controller
        local opts, ui = Features.CreateEspOptions(Card, function()
            if controller then controller.refreshStyle() end
        end)
        controller = Features.CreateEspController(opts)
        ui.setEnabled(false)

        return Core.BindToggle(Switch, Set, {
            start = function()
                controller.start()
                ui.setEnabled(true)
            end,
            stop = function()
                controller.stop()
                ui.setEnabled(false)
            end,
            onReset = ui.reset,
        })
    end

    --// ---------------- Camera / Gravity: boost for a single instance ----------------
    -- Same behavior as Speed / Jump Boost: the game's own value is snapshotted, restored when turned off, and
    -- re-applied if the game changes it (at most 30 times per second, so we never fight the game).
    -- cfg: { title, max, min, waitFor, props, getTarget, watch, snapshot, apply, restore, getValue,
    --        isApplied, fromSnapshot, presets }
    function Features.CreateTargetBoost(parent, cfg)
        local row = Core.CreateToggleWithBox(parent, cfg.title, { max = cfg.max })
        local badge = Core.CreateStatusBadge(row)
        local snaps = setmetatable({}, { __mode = "k" })           -- target -> the game's own value
        local current, watchConn, presetApi
        local sigs = {}
        local active = false
        local parsed = { status = "empty" }
        local overrides = { n = 0, t = 0, pausedUntil = 0 }

        local function reparse()
            parsed = Core.ParseNumericInput(row.Box.Text, { max = cfg.max })
            if cfg.min and parsed.effective and parsed.effective < cfg.min then
                parsed.effective, parsed.status = cfg.min, "clamped"
            end
        end
        reparse()

        local function getOriginal()
            local t = cfg.getTarget()
            if not t then return nil end
            local st = snaps[t]
            if st ~= nil then return cfg.fromSnapshot(st) end
            local ok, v = pcall(cfg.getValue, t)
            if ok and type(v) == "number" then return v end
            return nil
        end

        local function showActive(v)
            local word = (parsed.status == "clamped") and "Capped" or "Running"
            badge.set("active", word .. Core.DOT .. Core.FormatValue(v))
        end

        local function applyTo(t)
            local v = parsed.effective
            if not v then
                if snaps[t] ~= nil then
                    pcall(cfg.restore, t, snaps[t])
                    snaps[t] = nil
                end
                badge.set("paused", "Waiting for value")
                return
            end
            if snaps[t] == nil then snaps[t] = cfg.snapshot(t) end
            cfg.apply(t, v)
            showActive(v)
        end

        -- The game changed the value: its new value becomes the new "original" (even while we are paused, so
        -- turning off always gives back what the game wants right now), then we apply ours again
        local function onExternal(t)
            if t ~= current or snaps[t] == nil then return end
            local v = parsed.effective
            if not v or cfg.isApplied(t, v) then return end

            snaps[t] = cfg.snapshot(t)
            local now = os.clock()
            if now < overrides.pausedUntil then return end
            if now - overrides.t > 1 then
                overrides.t, overrides.n = now, 0
            end
            overrides.n += 1
            if overrides.n > 30 then
                overrides.pausedUntil = now + 1
                badge.set("paused", "Overridden by game")
                return
            end

            cfg.apply(t, v)
            showActive(v)
        end

        -- Stop watching the target and give the game its own value back
        local function unbind()
            for _, s in ipairs(sigs) do s:Disconnect() end
            table.clear(sigs)
            local t = current
            current = nil
            if t and snaps[t] ~= nil then
                pcall(cfg.restore, t, snaps[t])
                snaps[t] = nil
            end
        end

        local function attach()
            unbind()
            local t = cfg.getTarget()
            if not t then
                badge.set("waiting", "Waiting for " .. (cfg.waitFor or "target"))
                return
            end
            current = t
            applyTo(t)
            for _, prop in ipairs(cfg.props) do
                sigs[#sigs + 1] = t:GetPropertyChangedSignal(prop):Connect(function()
                    onExternal(t)
                end)
            end
        end

        local function start()
            reparse()
            if parsed.effective == nil then
                badge.flash("Enter a valid value", 2.5, "invalid")
                row.flashError()
                return false
            end
            active = true
            attach()
            if cfg.watch then watchConn = cfg.watch(attach) end
        end

        local function stop()
            active = false
            if watchConn then watchConn:Disconnect() watchConn = nil end
            unbind()
            badge.set("off")
        end

        -- Prefill the input box with the current value (if the box is empty)
        local function prefill()
            local t = cfg.getTarget()
            if not t then return end
            local ok, v = pcall(cfg.getValue, t)
            if ok and type(v) == "number" and v == v and v < 1e6 and row.Box.Text == "" then
                row.Box.Text = Core.FormatValue(v)
            end
        end
        prefill()

        row.Box:GetPropertyChangedSignal("Text"):Connect(function()
            reparse()
            if presetApi then presetApi.markActive(parsed.effective) end
            if active and current then applyTo(current) end
        end)

        local handle = Core.BindToggle(row.Switch, row.Set, {
            start = start,
            stop = stop,
            badge = badge,
            onReset = function()
                row.Box.Text = ""
                prefill()
            end,
        })

        presetApi = Core.CreatePresetRow(row, cfg.presets, { getOriginal = getOriginal })
        presetApi.markActive(parsed.effective)
        return handle
    end

    local function originalPreset()
        return { label = "Original", noHighlight = true, value = function(o) return o end }
    end

    local FOV_CFG = {
        title = "Field of View", max = 120, min = 1, waitFor = "camera",
        props = { "FieldOfView" },
        getTarget = function() return Workspace.CurrentCamera end,
        watch = function(cb)                                       -- the game swapped the camera: attach to the new one
            return Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(cb)
        end,
        snapshot = function(cam) return cam.FieldOfView end,
        apply = function(cam, v) if math.abs(cam.FieldOfView - v) > 1e-3 then cam.FieldOfView = v end end,
        restore = function(cam, fov) cam.FieldOfView = fov end,
        getValue = function(cam) return cam.FieldOfView end,
        isApplied = function(cam, v) return math.abs(cam.FieldOfView - v) < 1e-3 end,
        fromSnapshot = function(st) return st end,
        presets = {
            originalPreset(),
            { label = "90",  value = 90 },
            { label = "105", value = 105 },
            { label = "120", value = 120 },
        },
    }

    local ZOOM_CFG = {
        title = "Max Zoom", max = 1000, waitFor = "player",
        props = { "CameraMaxZoomDistance" },
        getTarget = function() return LocalPlayer end,
        snapshot = function(p) return p.CameraMaxZoomDistance end,
        apply = function(p, v) if p.CameraMaxZoomDistance ~= v then p.CameraMaxZoomDistance = v end end,
        restore = function(p, z) p.CameraMaxZoomDistance = z end,
        getValue = function(p) return p.CameraMaxZoomDistance end,
        isApplied = function(p, v) return math.abs(p.CameraMaxZoomDistance - v) < 1e-3 end,
        fromSnapshot = function(st) return st end,
        presets = boostPresets(1000),
    }

    local GRAVITY_CFG = {
        title = "Gravity", max = 500, waitFor = "workspace",
        props = { "Gravity" },
        getTarget = function() return Workspace end,
        snapshot = function(w) return w.Gravity end,
        apply = function(w, v) if math.abs(w.Gravity - v) > 1e-3 then w.Gravity = v end end,
        restore = function(w, g) w.Gravity = g end,
        getValue = function(w) return w.Gravity end,
        isApplied = function(w, v) return math.abs(w.Gravity - v) < 1e-3 end,
        fromSnapshot = function(st) return st end,
        presets = {
            originalPreset(),
            { label = '<font size="20">×</font>0.5',  value = function(o) return o and o * 0.5 end },
            { label = '<font size="20">×</font>0.25', value = function(o) return o and o * 0.25 end },
            { label = "Zero", value = 0 },
        },
    }

    --// ---------------- Anti AFK ----------------
    -- Roblox kicks players after 20 minutes without input. VirtualUser "clicks" when the Idled event fires,
    -- which resets that timer. Nothing runs until Idled fires, so it costs nothing while you play.
    function Features.CreateAntiAfk(parent)
        local row = Core.CreateToggleRow(parent, "Anti AFK")
        local badge = Core.CreateStatusBadge(row)
        local conn, resets = nil, 0

        local function start()
            local VirtualUser = game:GetService("VirtualUser")
            resets = 0
            conn = LocalPlayer.Idled:Connect(function()
                pcall(function()
                    VirtualUser:CaptureController()
                    VirtualUser:ClickButton2(Vector2.zero)
                end)
                resets += 1
                badge.set("active", "Idle timer reset" .. Core.DOT .. resets .. (resets == 1 and " time" or " times"))
            end)
            badge.set("active", "Protected from idle kick")
        end

        local function stop()
            if conn then conn:Disconnect() conn = nil end
            badge.set("off")
        end

        return Core.BindToggle(row.Switch, row.Set, { start = start, stop = stop, badge = badge })
    end

    --// ---------------- Anti Void ----------------
    -- Remembers the last spot you stood on. If you fall below the void line (e.g. out of the map with Noclip),
    -- you are put back there. One Heartbeat read per frame, the safe spot is sampled 5 times per second.
    function Features.CreateAntiVoid(parent)
        local row = Core.CreateToggleRow(parent, "Anti Void")
        local badge = Core.CreateStatusBadge(row)
        local tracker, rescues = nil, 0

        -- Height below which a fall counts as "into the void"
        local function voidLine()
            local h = Workspace.FallenPartsDestroyHeight
            if h ~= h or h < -10000 then h = -10000 end
            return h + 80
        end

        local function showStatus()
            badge.set("active", rescues == 0 and "Watching"
                or ("Rescued " .. rescues .. (rescues == 1 and " time" or " times")))
        end

        local function start()
            rescues = 0
            badge.set("waiting", "Waiting for character")
            tracker = Core.TrackCharacter(LocalPlayer, function(_, hum, root)
                local safe, lastSample, cooldown = root.CFrame, 0, 0
                showStatus()

                local conn = RunService.Heartbeat:Connect(function()
                    if hum.Health <= 0 or not root.Parent then return end
                    local now = os.clock()
                    if root.Position.Y < voidLine() then
                        if now >= cooldown then
                            cooldown = now + 1
                            root.CFrame = safe + Vector3.new(0, 4, 0)
                            root.AssemblyLinearVelocity = Vector3.zero
                            root.AssemblyAngularVelocity = Vector3.zero
                            rescues += 1
                            showStatus()
                        end
                    elseif now - lastSample > 0.2 then
                        lastSample = now
                        if hum.FloorMaterial ~= Enum.Material.Air then safe = root.CFrame end
                    end
                end)
                return function() conn:Disconnect() end
            end, { onDied = true })
        end

        local function stop()
            if tracker then tracker.destroy() tracker = nil end
            badge.set("off")
        end

        return Core.BindToggle(row.Switch, row.Set, { start = start, stop = stop, badge = badge })
    end

    --// ---------------- Click Teleport ----------------
    -- PC: hold Ctrl and click. Mobile: tap the ground (TouchTapInWorld ignores swipes and taps on the UI).
    -- Every teleport remembers where you came from, so "Back" can undo it.
    function Features.CreateClickTp(parent)
        local row = Core.CreateToggleRow(parent, "Click Teleport")
        local badge = Core.CreateStatusBadge(row)
        local conns = {}
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.IgnoreWater = true

        local hasTouch, hasKeys = UserInputService.TouchEnabled, UserInputService.KeyboardEnabled
        local hint = (hasTouch and not hasKeys) and "Tap the ground to teleport"
            or (hasTouch and "Ctrl + click or tap the ground" or "Hold Ctrl + click to teleport")

        local function teleportAlong(ray)
            local char, hum, root = LocalPlayer.Character, Core.GetHumanoid(), Core.GetRoot()
            if not (char and hum and root) or hum.Health <= 0 then
                badge.flash("No character to move", 1.5, "invalid")
                return
            end
            params.FilterDescendantsInstances = { char }
            local hit = Workspace:Raycast(ray.Origin, ray.Direction * 3000, params)
            if not hit then return end

            -- Stand on the surface (not inside it); on walls, step a little away from them
            local lift = math.max(hum.HipHeight + root.Size.Y / 2, 3)
            local push = Vector3.new(hit.Normal.X, 0, hit.Normal.Z) * 1.5
            local pos = hit.Position + push + Vector3.new(0, lift, 0)
            local facing = root.CFrame - root.CFrame.Position
            if Core.TeleportTo(CFrame.new(pos) * facing) then
                badge.flash("Teleported", 1, "active")
            end
        end

        local function ctrlDown()
            return UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
                or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
        end

        local function start()
            conns[1] = UserInputService.InputBegan:Connect(function(input, processed)
                if processed or input.UserInputType ~= Enum.UserInputType.MouseButton1 or not ctrlDown() then
                    return
                end
                local cam = Workspace.CurrentCamera
                if not cam then return end
                local m = UserInputService:GetMouseLocation()
                teleportAlong(cam:ViewportPointToRay(m.X, m.Y))
            end)
            if hasTouch then
                conns[2] = UserInputService.TouchTapInWorld:Connect(function(pos, processedByUI)
                    if processedByUI then return end
                    local cam = Workspace.CurrentCamera
                    if not cam then return end
                    teleportAlong(cam:ScreenPointToRay(pos.X, pos.Y))
                end)
            end
            badge.set("active", hint)
        end

        local function stop()
            for _, c in ipairs(conns) do c:Disconnect() end
            table.clear(conns)
            badge.set("off")
        end

        return Core.BindToggle(row.Switch, row.Set, { start = start, stop = stop, badge = badge })
    end

    --// ---------------- Hide Players ----------------
    -- Hides other players on your screen only: parts via LocalTransparencyModifier (a client-side multiplier),
    -- face decals and the name tag. Everything is put back when turned off, on respawn and when a player leaves.
    function Features.CreateHidePlayers(parent)
        local row = Core.CreateToggleRow(parent, "Hide Players")
        local badge = Core.CreateStatusBadge(row)
        local trackers, conns, hidden = {}, {}, 0

        local function status()
            if hidden == 0 then
                badge.set("active", "Active")
            else
                badge.set("active", "Hiding " .. hidden .. (hidden == 1 and " player" or " players"))
            end
        end

        local function track(p)
            if p == LocalPlayer or trackers[p] then return end
            trackers[p] = Core.TrackCharacter(p, function(char, hum)
                local parts, decals = {}, {}
                local nameMode = hum.DisplayDistanceType

                local function hide(inst)
                    if inst:IsA("BasePart") then
                        parts[inst] = true
                        inst.LocalTransparencyModifier = 1
                    elseif inst:IsA("Decal") then                      -- also covers Texture
                        if decals[inst] == nil then decals[inst] = inst.Transparency end
                        inst.Transparency = 1
                    end
                end

                hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
                for _, d in ipairs(char:GetDescendants()) do hide(d) end
                local added = char.DescendantAdded:Connect(hide)        -- accessories load in a moment later

                hidden += 1
                status()
                return function()
                    added:Disconnect()
                    for inst in pairs(parts) do
                        if inst.Parent then inst.LocalTransparencyModifier = 0 end
                    end
                    for inst, t in pairs(decals) do
                        if inst.Parent then inst.Transparency = t end
                    end
                    if hum.Parent then hum.DisplayDistanceType = nameMode end
                    hidden = math.max(0, hidden - 1)
                    status()
                end
            end)
        end

        local function start()
            hidden = 0
            for _, p in ipairs(Players:GetPlayers()) do track(p) end
            conns[1] = Players.PlayerAdded:Connect(track)
            conns[2] = Players.PlayerRemoving:Connect(function(p)
                local t = trackers[p]
                if t then
                    t.destroy()
                    trackers[p] = nil
                end
            end)
            status()
        end

        local function stop()
            for _, c in ipairs(conns) do c:Disconnect() end
            table.clear(conns)
            for p, t in pairs(trackers) do
                t.destroy()
                trackers[p] = nil
            end
            hidden = 0
            badge.set("off")
        end

        return Core.BindToggle(row.Switch, row.Set, { start = start, stop = stop, badge = badge })
    end

    --// ---------------- Quick actions: Back / Unstuck / Respawn ----------------
    function Features.CreateQuickActions(parent, order)
        local Card = CreateCard(parent, "QuickActions", 10, 12, 12)
        Card.LayoutOrder = order

        Core.Label(Card, {
            LayoutOrder = 1,
            Size = UDim2.new(1, 0, 0, 16),
            Font = Enum.Font.GothamBold,
            TextSize = 12,
            TextColor3 = Theme.SubText,
            Text = "QUICK ACTIONS",
        })

        local Grid = new("Frame", {
            LayoutOrder = 2,
            Size = UDim2.new(1, 0, 0, 34),
            BackgroundTransparency = 1,
        }, Card)
        new("UIGridLayout", {
            CellSize = UDim2.new(1 / 3, -6, 1, 0),
            CellPadding = UDim2.fromOffset(9, 0),
            SortOrder = Enum.SortOrder.LayoutOrder,
            FillDirectionMaxCells = 3,
        }, Grid)

        local back    = Core.CreateButton(Grid, "Back",    { order = 1, textSize = 13, radius = 8 })
        local unstuck = Core.CreateButton(Grid, "Unstuck", { order = 2, textSize = 13, radius = 8 })
        local respawn = Core.CreateButton(Grid, "Respawn", { order = 3, textSize = 13, radius = 8 })

        -- Back: only usable once there is a previous position to return to
        back.setEnabled(Core.History.cf ~= nil)
        Core.History.listeners[#Core.History.listeners + 1] = function()
            back.setEnabled(Core.History.cf ~= nil)
        end
        back.onClick(function()
            if not Core.GoBack() then back.flash("No character", 1.2, true) end
        end)

        -- Unstuck: lift 8 studs, cancel momentum, get out of a seat
        unstuck.onClick(function()
            local root, hum = Core.GetRoot(), Core.GetHumanoid()
            if not (root and hum) then
                unstuck.flash("No character", 1.2, true)
                return
            end
            hum.Sit = false
            root.CFrame = root.CFrame + Vector3.new(0, 8, 0)
            root.AssemblyLinearVelocity = Vector3.zero
            hum:ChangeState(Enum.HumanoidStateType.GettingUp)
            unstuck.flash("Done", 1)
        end)

        -- Respawn: asks for a second tap within 2 seconds so a stray tap cannot reset your progress
        local armed = false
        respawn.onClick(function()
            if not armed then
                armed = true
                respawn.flash("Tap again", 2, true)
                task.delay(2, function() armed = false end)
                return
            end
            armed = false
            local char, hum = LocalPlayer.Character, Core.GetHumanoid()
            if not char then
                respawn.flash("No character", 1.2, true)
                return
            end
            if hum then hum.Health = 0 end
            pcall(function() char:BreakJoints() end)
        end)

        return Card
    end

    --// ---------------- Waypoints ----------------
    -- Save the spot you stand on, jump back to it later. Saved per game (PlaceId) in Elysera_Waypoints.json
    -- when the executor has file access; otherwise they last until you leave the game.
    function Features.CreateWaypoints(parent)
        local FILE, MAX = "Elysera_Waypoints.json", 15
        local HttpService = game:GetService("HttpService")
        local canFS = typeof(readfile) == "function" and typeof(writefile) == "function" and typeof(isfile) == "function"
        local placeKey = tostring(game.PlaceId)

        -- One file for every game: { [PlaceId] = { { n = name, x, y, z, r = yaw in degrees }, ... } }
        local store = {}
        if canFS then
            pcall(function()
                if isfile(FILE) then
                    local data = HttpService:JSONDecode(readfile(FILE))
                    if type(data) == "table" then store = data end
                end
            end)
        end

        local points = {}
        if type(store[placeKey]) == "table" then
            for _, p in ipairs(store[placeKey]) do
                if #points < MAX and type(p) == "table"
                    and type(p.x) == "number" and type(p.y) == "number" and type(p.z) == "number" then
                    points[#points + 1] = {
                        n = Core.ClipText(tostring(p.n or "Point"), 24),
                        x = p.x, y = p.y, z = p.z,
                        r = tonumber(p.r) or 0,
                    }
                end
            end
        end
        store[placeKey] = points

        local saveQueued = false
        local function save()
            if not canFS or saveQueued then return end
            saveQueued = true
            task.delay(0.4, function()                       -- several quick edits become one write
                saveQueued = false
                pcall(function() writefile(FILE, HttpService:JSONEncode(store)) end)
            end)
        end

        local Card = CreateCard(parent, "Waypoints", 12, 12, 12)

        local Header = new("Frame", {
            LayoutOrder = 1,
            Size = UDim2.new(1, 0, 0, 22),
            BackgroundTransparency = 1,
        }, Card)
        Core.Label(Header, {
            Size = UDim2.new(0.5, 0, 1, 0),
            Font = Enum.Font.GothamBold,
            TextSize = 15,
            Text = "Waypoints",
        })
        local note = Core.CreateNote(Header, {
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.fromScale(1, 0),
            Size = UDim2.new(0.5, 0, 1, 0),
        })

        local InputRow = new("Frame", {
            LayoutOrder = 2,
            Size = UDim2.new(1, 0, 0, 34),
            BackgroundTransparency = 1,
        }, Card)
        local Box = Core.CreateInput(InputRow, "Name (optional)", {
            size = UDim2.new(1, -96, 1, 0),
        })
        local SaveBtn = Core.CreateButton(InputRow, "Save here", {
            anchor = Vector2.new(1, 0.5),
            position = UDim2.new(1, 0, 0.5, 0),
            size = UDim2.fromOffset(88, 34),
            variant = "accent",
            radius = 6,
        })

        local List = new("Frame", {
            LayoutOrder = 3,
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
        }, Card)
        list(List, 6)

        local Empty = Core.Label(List, {
            LayoutOrder = 0,
            Size = UDim2.new(1, 0, 0, 32),
            TextSize = 12,
            TextColor3 = Theme.SubText,
            TextWrapped = true,
            Text = "No waypoints yet. Stand where you want to come back to and tap Save here.",
        })

        if not canFS then
            Core.Label(Card, {
                LayoutOrder = 4,
                Size = UDim2.new(1, 0, 0, 28),
                TextSize = 11,
                TextColor3 = Theme.SubText,
                TextWrapped = true,
                Text = "This executor has no file access, so waypoints are kept only until you leave the game.",
            })
        end

        local rebuild

        local function makeRow(p)
            local Row = new("Frame", {
                Name = "Waypoint",
                LayoutOrder = #points - table.find(points, p) + 1,   -- newest on top
                Size = UDim2.new(1, 0, 0, 42),
                BackgroundColor3 = Theme.PanelAlt,
                BorderSizePixel = 0,
            }, List)
            corner(Row, 6)
            stroke(Row)

            Core.Label(Row, {
                Position = UDim2.fromOffset(10, 5),
                Size = UDim2.new(1, -100, 0, 18),
                Font = Enum.Font.GothamBold,
                TextSize = 13,
                TextTruncate = Enum.TextTruncate.AtEnd,
                Text = p.n,
            })
            Core.Label(Row, {
                Position = UDim2.fromOffset(10, 23),
                Size = UDim2.new(1, -100, 0, 14),
                TextSize = 11,
                TextColor3 = Theme.SubText,
                Text = string.format("%d, %d, %d", math.floor(p.x + 0.5), math.floor(p.y + 0.5), math.floor(p.z + 0.5)),
            })

            local go = Core.CreateButton(Row, "Go", {
                anchor = Vector2.new(1, 0.5),
                position = UDim2.new(1, -44, 0.5, 0),
                size = UDim2.fromOffset(44, 26),
                variant = "accent",
            })
            local del = Core.CreateButton(Row, "×", {
                anchor = Vector2.new(1, 0.5),
                position = UDim2.new(1, -8, 0.5, 0),
                size = UDim2.fromOffset(30, 26),
                textSize = 18,
            })
            del.Button.TextColor3 = Theme.Danger

            go.onClick(function()
                local cf = CFrame.new(p.x, p.y, p.z) * CFrame.Angles(0, math.rad(p.r), 0)
                if Core.TeleportTo(cf) then
                    note.flash("Teleported to " .. p.n)
                else
                    note.flash("No character", true)
                end
            end)
            del.onClick(function()
                local idx = table.find(points, p)
                if idx then table.remove(points, idx) end
                save()
                rebuild()
                note.flash("Deleted " .. p.n)
            end)
        end

        rebuild = function()
            for _, c in ipairs(List:GetChildren()) do
                if c.Name == "Waypoint" then c:Destroy() end
            end
            for _, p in ipairs(points) do makeRow(p) end
            Empty.Visible = (#points == 0)
            note.setBase(#points .. "/" .. MAX)
        end

        local function saveHere()
            local root = Core.GetRoot()
            if not root then
                note.flash("No character", true)
                return
            end
            if #points >= MAX then
                note.flash("Limit reached (" .. MAX .. ")", true)
                return
            end
            local name = Core.ClipText(Core.Trim(Box.Text), 24)
            if name == "" then                                       -- first free "Point N"
                local taken = {}
                for _, p in ipairs(points) do taken[p.n] = true end
                local n = 1
                while taken["Point " .. n] do n += 1 end
                name = "Point " .. n
            end
            local pos = root.Position
            local _, yaw = root.CFrame:ToOrientation()
            points[#points + 1] = { n = name, x = pos.X, y = pos.Y, z = pos.Z, r = math.deg(yaw) }
            Box.Text = ""
            save()
            rebuild()
            note.flash("Saved " .. name)
        end

        SaveBtn.onClick(saveHere)
        Box.FocusLost:Connect(function(enter)
            if enter and not isLocked() then saveHere() end
        end)

        rebuild()
        return Card
    end

    --// ---------------- Players: find, teleport, view ----------------
    -- Only 6 rows exist and they are reused, so a 100-player server costs the same as a 6-player one;
    -- the search box narrows the list. While viewing someone, a floating "Stop" pill stays on screen so
    -- the menu can be closed.
    function Features.CreatePlayers(parent)
        local ROWS = 6
        local Card = CreateCard(parent, "PlayersCard", 12, 12, 12)

        local Header = new("Frame", {
            LayoutOrder = 1,
            Size = UDim2.new(1, 0, 0, 24),
            BackgroundTransparency = 1,
        }, Card)
        local Title = Core.Label(Header, {
            Size = UDim2.new(1, -72, 1, 0),
            Font = Enum.Font.GothamBold,
            TextSize = 15,
            RichText = true,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Text = "Players",
        })
        local StopTop = Core.CreateButton(Header, "Stop", {
            anchor = Vector2.new(1, 0.5),
            position = UDim2.new(1, 0, 0.5, 0),
            size = UDim2.fromOffset(64, 24),
            variant = "accent",
            textSize = 12,
        })
        StopTop.Button.Visible = false

        local Search = Core.CreateInput(Card, "Search players", { order = 2, size = UDim2.new(1, 0, 0, 32) })

        local List = new("Frame", {
            LayoutOrder = 3,
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
        }, Card)
        list(List, 6)
        local Empty = Core.Label(List, {
            LayoutOrder = 0,
            Size = UDim2.new(1, 0, 0, 24),
            TextSize = 12,
            TextColor3 = Theme.SubText,
            Text = "",
            Visible = false,
        })
        local More = Core.Label(Card, {
            LayoutOrder = 4,
            Size = UDim2.new(1, 0, 0, 16),
            TextSize = 11,
            TextColor3 = Theme.SubText,
            Text = "",
            Visible = false,
        })

        -- Floating pill (top center, under the Roblox top bar): visible only while viewing
        local Hud = new("Frame", {
            Name = "ViewHud",
            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.new(0.5, 0, 0, 56),
            Size = UDim2.fromOffset(0, 38),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundColor3 = Theme.Panel,
            BorderSizePixel = 0,
            Visible = false,
            ZIndex = 30,
        }, ScreenGui)
        corner(Hud, 19)
        stroke(Hud, Theme.AccentPink, 1.5)
        padding(Hud, 16, 6, 0, 0)
        list(Hud, 10, {
            FillDirection = Enum.FillDirection.Horizontal,
            VerticalAlignment = Enum.VerticalAlignment.Center,
        })
        local HudText = Core.Label(Hud, {
            LayoutOrder = 1,
            Size = UDim2.fromOffset(0, 38),
            AutomaticSize = Enum.AutomaticSize.X,
            Font = Enum.Font.GothamBold,
            TextSize = 13,
            RichText = true,
            ZIndex = 31,
            Text = "",
        })
        local HudStop = Core.CreateButton(Hud, "Stop", {
            order = 2,
            size = UDim2.fromOffset(60, 26),
            variant = "accent",
            radius = 13,
            textSize = 12,
        })
        HudStop.Button.ZIndex = 31

        local viewing, othersCount = nil, 0
        local viewConns, listeners = {}, {}
        local savedSubject, viewToken = nil, 0
        local rows, refreshQueued = {}, false
        local refresh                                           -- assigned below (rows need it, it needs rows)

        -- Only off <-> on transitions are announced (switching to another player is still just "on")
        local lastOn = false
        local function notify()
            local on = viewing ~= nil
            if on == lastOn then return end
            lastOn = on
            for _, fn in ipairs(listeners) do pcall(fn, on) end
        end

        local function renderTitle()
            if viewing then
                local text = '<font color="#' .. Theme.Sakura:ToHex() .. '">Viewing</font>'
                    .. Core.DOT .. Core.EscapeRich(viewing.DisplayName)
                Title.Text, HudText.Text = text, text
            else
                Title.Text = "Players" .. Core.DOT .. othersCount
            end
            StopTop.Button.Visible = viewing ~= nil
            Hud.Visible = viewing ~= nil
        end

        -- keepCamera = true when someone else already moved the camera (respawn, game script)
        local function stopView(keepCamera)
            if not viewing then return end
            viewing = nil
            viewToken += 1
            for _, c in ipairs(viewConns) do c:Disconnect() end
            table.clear(viewConns)
            if not keepCamera then
                local cam = Workspace.CurrentCamera
                if cam then
                    local subject = savedSubject
                    if not (subject and subject.Parent) then subject = Core.GetHumanoid() end
                    if subject then cam.CameraSubject = subject end
                end
            end
            savedSubject = nil
            renderTitle()
            refresh()
            notify()
        end

        local function startView(p)
            local cam = Workspace.CurrentCamera
            if not cam or p.Parent ~= Players then return end
            if viewing then
                for _, c in ipairs(viewConns) do c:Disconnect() end   -- switching target: keep the first saved subject
                table.clear(viewConns)
            else
                savedSubject = cam.CameraSubject
            end
            viewing = p
            viewToken += 1
            local my = viewToken

            local function point()
                task.spawn(function()
                    local char = p.Character
                    local hum = char and (char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 5))
                    if my ~= viewToken or not hum then return end
                    local c = Workspace.CurrentCamera
                    if c then c.CameraSubject = hum end
                end)
            end
            point()

            viewConns[1] = p.CharacterAdded:Connect(point)                  -- they respawned: follow the new character
            viewConns[2] = LocalPlayer.CharacterAdded:Connect(function()    -- you respawned: the game resets the camera
                stopView(true)
            end)
            viewConns[3] = Players.PlayerRemoving:Connect(function(who)
                if who == p then stopView() end
            end)
            viewConns[4] = cam:GetPropertyChangedSignal("CameraSubject"):Connect(function()
                local mine = Core.GetHumanoid()
                if mine and cam.CameraSubject == mine then stopView(true) end   -- the camera went back to you
            end)

            renderTitle()
            refresh()
            notify()
        end

        local function teleportToPlayer(p)
            local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
            if not root then return false end
            return Core.TeleportTo(root.CFrame * CFrame.new(0, 0, 4))       -- 4 studs behind them
        end

        local function makeRow(i)
            local Row = new("Frame", {
                Name = "PlayerRow",
                LayoutOrder = i,
                Size = UDim2.new(1, 0, 0, 42),
                BackgroundColor3 = Theme.PanelAlt,
                BorderSizePixel = 0,
                Visible = false,
            }, List)
            corner(Row, 6)
            stroke(Row)

            local nameL = Core.Label(Row, {
                Position = UDim2.fromOffset(10, 5),
                Size = UDim2.new(1, -132, 0, 18),
                Font = Enum.Font.GothamBold,
                TextSize = 13,
                TextTruncate = Enum.TextTruncate.AtEnd,
            })
            local userL = Core.Label(Row, {
                Position = UDim2.fromOffset(10, 23),
                Size = UDim2.new(1, -132, 0, 14),
                TextSize = 11,
                TextColor3 = Theme.SubText,
                TextTruncate = Enum.TextTruncate.AtEnd,
            })
            local tp = Core.CreateButton(Row, "TP", {
                anchor = Vector2.new(1, 0.5),
                position = UDim2.new(1, -8, 0.5, 0),
                size = UDim2.fromOffset(44, 26),
                variant = "accent",
            })
            local view = Core.CreateButton(Row, "View", {
                anchor = Vector2.new(1, 0.5),
                position = UDim2.new(1, -58, 0.5, 0),
                size = UDim2.fromOffset(54, 26),
            })

            local r = { frame = Row, name = nameL, user = userL, view = view, tp = tp, player = nil }
            tp.onClick(function()
                if not r.player then return end
                if not teleportToPlayer(r.player) then tp.flash("!", 1, true) end
            end)
            view.onClick(function()
                local p = r.player
                if not p then return end
                if viewing == p then stopView() else startView(p) end
            end)
            rows[i] = r
            return r
        end

        refresh = function()
            refreshQueued = false
            local q = Core.Trim(Search.Text):lower()
            local found, total = {}, 0
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LocalPlayer and p.Parent == Players then
                    total += 1
                    local dn = p.DisplayName:lower()
                    if q == "" or dn:find(q, 1, true) or p.Name:lower():find(q, 1, true) then
                        found[#found + 1] = { p = p, key = dn }
                    end
                end
            end
            table.sort(found, function(a, b)                         -- the viewed player first, then A-Z
                local av, bv = a.p == viewing, b.p == viewing
                if av ~= bv then return av end
                if a.key ~= b.key then return a.key < b.key end
                return a.p.UserId < b.p.UserId
            end)
            othersCount = total

            local shown = math.min(#found, ROWS)
            for i = 1, ROWS do
                local r = rows[i]
                if i <= shown then
                    r = r or makeRow(i)
                    local p = found[i].p
                    local on = (p == viewing)
                    r.player = p
                    r.name.Text = p.DisplayName
                    r.user.Text = "@" .. p.Name
                    r.view.setText(on and "Stop" or "View")
                    r.view.setActive(on)
                    r.frame.Visible = true
                elseif r then
                    r.player = nil
                    r.frame.Visible = false
                end
            end

            Empty.Visible = (#found == 0)
            if #found == 0 then
                Empty.Text = (total == 0) and "No other players in this server." or "No player matches your search."
            end
            More.Visible = (#found > shown)
            if #found > shown then
                More.Text = string.format("Showing %d of %d · type a name to find the rest", shown, #found)
            end
            renderTitle()
        end

        local function queueRefresh()
            if refreshQueued then return end
            refreshQueued = true
            task.defer(refresh)
        end

        StopTop.onClick(function() stopView() end)
        HudStop.onClick(function() stopView() end)

        local conns = {
            Players.PlayerAdded:Connect(queueRefresh),
            Players.PlayerRemoving:Connect(function() task.delay(0.25, queueRefresh) end),
            Search:GetPropertyChangedSignal("Text"):Connect(queueRefresh),
        }
        Core.OnDestroy(function()
            for _, c in ipairs(conns) do c:Disconnect() end
        end)

        -- Viewing counts as "on": Reset All stops it and the section header shows the "1 on" pill
        local handle = {
            isOn = function() return viewing ~= nil end,
            stop = function() stopView() end,
            onChanged = function(fn) listeners[#listeners + 1] = fn end,
        }
        Core.Register(handle)

        refresh()
        return handle
    end

    --// ---------------- Reset All ----------------
    function Features.CreateResetAll(parent, order)
        local btn = new("TextButton", {
            LayoutOrder = order,
            Size = UDim2.new(1, 0, 0, 40),
            Text = "Reset All",
            BackgroundColor3 = Theme.PanelAlt,
            BorderSizePixel = 0,
            Font = Enum.Font.GothamBold,
            TextSize = 14,
            TextColor3 = Theme.Text,
        }, parent)
        corner(btn, 8)
        stroke(btn)

        local token = 0
        btn.Activated:Connect(function()
            if isLocked() then return end
            local n = Core.ResetAll()
            token += 1
            local my = token
            btn.Text = (n > 0) and ("Reset " .. n .. (n == 1 and " feature" or " features")) or "Nothing to reset"
            task.delay(1.5, function()
                if my == token and btn.Parent then btn.Text = "Reset All" end
            end)
        end)
        return btn
    end

    --// =====================================================
    --//  BUILD UI
    --// =====================================================
    Features.CreateQuickActions(LocalTab, 1)

    local Movement = Core.CreateSectionGroup(LocalTab, "Movement", 2, {
        subtitle = "Speed, jump, gravity, noclip, fly",
    })
    local Teleport = Core.CreateSectionGroup(LocalTab, "Teleport", 3, {
        subtitle = "Click teleport, waypoints, players", collapsed = true,
    })
    local Camera = Core.CreateSectionGroup(LocalTab, "Camera", 4, {
        subtitle = "Field of view and zoom distance", collapsed = true,
    })
    local Visual = Core.CreateSectionGroup(LocalTab, "Visual", 5, {
        subtitle = "ESP, hide players, full bright", collapsed = true,
    })
    local Safety = Core.CreateSectionGroup(LocalTab, "Safety", 6, {
        subtitle = "Anti AFK and Anti Void", collapsed = true,
    })

    Movement.trackSwitch(Features.CreateHumanoidBoost(Movement.Body, SPEED_CFG))
    Movement.trackSwitch(Features.CreateHumanoidBoost(Movement.Body, JUMP_CFG))
    Movement.trackSwitch(Features.CreateTargetBoost(Movement.Body, GRAVITY_CFG))
    Movement.trackSwitch(Features.CreateInfiniteJump(Movement.Body))
    Movement.trackSwitch(Features.CreateNoclip(Movement.Body))
    Movement.trackSwitch(Features.CreateFly(Movement.Body))

    Teleport.trackSwitch(Features.CreateClickTp(Teleport.Body))
    Features.CreateWaypoints(Teleport.Body)
    Teleport.trackSwitch(Features.CreatePlayers(Teleport.Body))

    Camera.trackSwitch(Features.CreateTargetBoost(Camera.Body, FOV_CFG))
    Camera.trackSwitch(Features.CreateTargetBoost(Camera.Body, ZOOM_CFG))

    Visual.trackSwitch(Features.CreateEsp(Visual.Body))
    Visual.trackSwitch(Features.CreateHidePlayers(Visual.Body))
    Visual.trackSwitch(Features.CreateFullBright(Visual.Body))

    Safety.trackSwitch(Features.CreateAntiAfk(Safety.Body))
    Safety.trackSwitch(Features.CreateAntiVoid(Safety.Body))

    Features.CreateResetAll(LocalTab, 7)

    -- GUI destroyed: reuse the Reset All path to clean everything up, then release global connections
    ScreenGui.Destroying:Connect(function()
        Core.ResetAll()
        for _, fn in ipairs(Core.hooks) do pcall(fn) end
    end)
end
