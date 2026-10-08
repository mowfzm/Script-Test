local MAX_DEPTH = 2
local EXTENSIONS = { mp3 = true, ogg = true, wav = true }
local BASE = "iamosulazer"
local ICONS = BASE .. "/icons"
local STATE_FILE = BASE .. "/Last State.txt"
local FALLBACK = BASE .. "/fallback.png"
local SAMPLE_DIR = BASE .. "/Your Playlist"
local SAMPLE_SONG = SAMPLE_DIR .. "/Bad Apple.ogg"
local FALLBACK_URL = "https://raw.githubusercontent.com/3-7x/CoolOsuThing/refs/heads/main/osu.png"
local SAMPLE_URL = "https://raw.githubusercontent.com/3-7x/CoolOsuThing/refs/heads/main/Bad%20Apple.ogg"
local ICON_SCALE = .6
local ICON_FILES = {
    prev = { ICONS .. "/prev.png", "https://raw.githubusercontent.com/3-7x/CoolOsuThing/refs/heads/main/previous.png" },
    play = { ICONS .. "/play.png", "https://raw.githubusercontent.com/3-7x/CoolOsuThing/refs/heads/main/play.png" },
    pause = { ICONS .. "/pause.png", "https://raw.githubusercontent.com/3-7x/CoolOsuThing/refs/heads/main/pause.png" },
    next = { ICONS .. "/next.png", "https://raw.githubusercontent.com/3-7x/CoolOsuThing/refs/heads/main/next.png" },
    record = { ICONS .. "/record.png", "https://raw.githubusercontent.com/3-7x/CoolOsuThing/refs/heads/main/disc.png" },
    --settings = { ICONS .. "/settings.png", "https://raw.githubusercontent.com/3-7x/CoolOsuThing/refs/heads/main/gear.png" },
    --playlist = { ICONS .. "/playlist.png", "https://raw.githubusercontent.com/3-7x/CoolOsuThing/refs/heads/main/note.png" },
    -- these were ugly anyway
}

local function mkdir(p)
    if not isfolder(p) then pcall(makefolder, p) end
end

local function fetch(path, url, png)
    if isfile(path) then return true end
    return (pcall(function()
        local data = game:HttpGet(url)
        if png then assert(data:sub(2, 4) == "PNG") else assert(#data > 4096) end
        writefile(path, data)
    end))
end

local firstRun = not isfolder(BASE)
mkdir(BASE)
mkdir(ICONS)
if not isfile(STATE_FILE) then pcall(writefile, STATE_FILE, "{}") end
fetch(FALLBACK, FALLBACK_URL, true)
if firstRun then
    mkdir(SAMPLE_DIR)
    fetch(SAMPLE_SONG, SAMPLE_URL)
end

local ICON = {}
for key, info in ICON_FILES do
    ICON[key] = ""
    if fetch(info[1], info[2], true) then
        pcall(function() ICON[key] = getcustomasset(info[1]) end)
    end
end

local SENS, COUNT, INNER, MINL, MAXL, BARW = 12, 96, 82, 3, 120, 3

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local TS = game:GetService("TweenService")
local RS = game:GetService("RunService")
local CAS = game:GetService("ContextActionService")
local TXT = game:GetService("TextService")
local Player = Players.LocalPlayer

local collection, connections = {}, {}

local State = {}
pcall(function() State = game:GetService("HttpService"):JSONDecode(readfile(STATE_FILE)) end)
if type(State) ~= "table" then State = {} end
local function saveState()
    pcall(function() writefile(STATE_FILE, game:GetService("HttpService"):JSONEncode(State)) end)
end

local Cfg = {
    rainbow = State.rainbow == true,
    mode = State.mode or "Spectrum",
    showName = State.showName ~= false,
    showTime = State.showTime ~= false,
    scale = tonumber(State.scale) or 1,
    volume = math.clamp(tonumber(State.volume) or 1, 0, 10),
}
local cur, playing, startedAt, pausedAt

local function make(class, parent, props)
    local o = Instance.new(class)
    if props then
        for k, v in props do o[k] = v end
    end
    o.Parent = parent
    collection[#collection + 1] = o
    return o
end

local function connect(signal, fn)
    local c = signal:Connect(fn)
    connections[#connections + 1] = c
    return c
end

local function cleanup()
    for _, c in connections do
        pcall(function() c:Disconnect() end)
    end
    for i = #collection, 1, -1 do
        pcall(function() collection[i]:Destroy() end)
        collection[i] = nil
    end
end

local function tween(o, t, props, style, dir)
    local tw = TS:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
    tw:Play()
    return tw
end

local function ease(x) return 1 - (1 - x) ^ 3 end

local function shuffle(t)
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
end

local categories, songs = {}, {}
local SKIP = { icons = true }
local IMAGE_EXTENSIONS = { png = true, jpg = true, jpeg = true, webp = true }

local function norm(p) return (p:gsub("\\", "/"):gsub("/+$", "")) end

local function scanDir(dir, depth)
    local ok, files = pcall(listfiles, dir)
    if (not ok or type(files) ~= "table") and dir == "" then
        ok, files = pcall(listfiles, ".")
    end
    if not ok or type(files) ~= "table" then return end
    local list, dirs, covers = {}, {}, {}
    for _, path in files do
        if isfolder(path) then
            local last = norm(path):match("([^/]+)$")
            if not (last and SKIP[last:lower()]) then dirs[#dirs + 1] = path end
        else
            local ext = path:match("%.(%w+)$")
            ext = ext and ext:lower()
            if ext and EXTENSIONS[ext] then
                list[#list + 1] = { path = path, name = path:match("([^/\\]+)%.%w+$"), dir = dir }
            elseif dir ~= "" and ext and IMAGE_EXTENSIONS[ext] then
                covers[#covers + 1] = path
            end
        end
    end
    if #list > 0 then
        shuffle(list)
        local label = norm(dir)
        if label == "" then
            label = "workspace"
        elseif label:sub(1, #BASE + 1) == BASE .. "/" then
            label = label:sub(#BASE + 2)
        end
        categories[#categories + 1] = { dir = dir, label = label, songs = list, covers = covers }
        for _, s in list do
            songs[#songs + 1] = s
            s.idx = #songs
        end
    end
    if depth < MAX_DEPTH then
        for _, d in dirs do scanDir(d, depth + 1) end
    end
end
scanDir(getgenv().ScanWholeWorkspace and "" or BASE, 0)

local lastSong
for _, s in songs do
    if s.path == State.lastSong then
        lastSong = s
        break
    end
end

local function asset(p)
    local ok, r = pcall(getcustomasset, p)
    return ok and r or ""
end
local defaultCover = isfile(FALLBACK) and asset(FALLBACK) or ""

local function audioOf(s)
    if not s.audio then s.audio = getcustomasset(s.path) end
    return s.audio
end

local function coverOf(s)
    if not s.playlistImages then
        for _, cat in categories do
            if cat.dir == s.dir then
                s.playlistImages = cat.covers
                break
            end
        end
    end
    local images = s.playlistImages
    if images and #images > 0 then
        local p = images[math.random(#images)]
        return isfile(p) and asset(p) or defaultCover
    end
    return defaultCover
end

local AudioPlayer = make("AudioPlayer", workspace, { Looping = false })
AudioPlayer.Volume = Cfg.volume
local Analyzer = make("AudioAnalyzer", workspace, { SpectrumEnabled = true, WindowSize = Enum.AudioWindowSize.Medium })
make("Wire", Analyzer, { SourceInstance = AudioPlayer, TargetInstance = Analyzer })
local Equalizer = make("AudioEqualizer", workspace)
make("Wire", Equalizer, { SourceInstance = AudioPlayer, TargetInstance = Equalizer })
local Output = make("AudioDeviceOutput", workspace)
make("Wire", Output, { SourceInstance = Equalizer, TargetInstance = Output })

local Gui = make("ScreenGui", Player:WaitForChild("PlayerGui"), { Name = "Orbitune", IgnoreGuiInset = true, ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
local Holder = make("Frame", Gui, {
    Name = "Holder", Size = UDim2.fromOffset(360, 360), Position = UDim2.fromScale(.5, .5),
    AnchorPoint = Vector2.new(.5, .5), BackgroundTransparency = 1,
})
local HolderScale = make("UIScale", Holder, { Scale = Cfg.scale })

local Circle = make("Frame", Holder, {
    Name = "Circle", Size = UDim2.fromOffset(150, 150), Position = UDim2.fromScale(.5, .5),
    AnchorPoint = Vector2.new(.5, .5), BackgroundColor3 = Color3.fromRGB(18, 18, 24),
    BorderSizePixel = 0, ClipsDescendants = true,
})
make("UICorner", Circle, { CornerRadius = UDim.new(1, 0) })
make("UIStroke", Circle, { Thickness = 2, Color = Color3.new(1, 1, 1), Transparency = .8, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })

local osu = make("ImageLabel", Circle, {
    Name = "Cover", Image = lastSong and coverOf(lastSong) or defaultCover, AnchorPoint = Vector2.new(.5, .5),
    Position = UDim2.fromScale(.5, .5), Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
})
make("UICorner", osu, { CornerRadius = UDim.new(1, 0) })

local BarsFolder = make("Frame", Holder, { Name = "Bars", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
local Bars = {}

local function setBar(b, len)
    local c = b.Dir * (INNER + len / 2)
    b.Frame.Size = UDim2.fromOffset(BARW, len)
    b.Frame.Position = UDim2.new(.5, c.X, .5, c.Y)
end

for i = 1, COUNT do
    local ang = math.rad(30 - (-30 + (i - 1) / (COUNT - 1) * 300))
    local f = make("Frame", BarsFolder, {
        Name = "Bar" .. i, AnchorPoint = Vector2.new(.5, .5), Rotation = math.deg(ang) + 90,
        BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
    })
    make("UICorner", f, { CornerRadius = UDim.new(1, 0) })
    Bars[i] = { Frame = f, Dir = Vector2.new(math.cos(ang), math.sin(ang)) }
    setBar(Bars[i], MINL)
end

task.spawn(function()
    local sm, rnd = table.create(COUNT, 0), table.create(COUNT, 0)
    local t, dt, nextRnd, wasRainbow = 0, .016, 0, false
    while Gui.Parent do
        t += dt
        local mode = Cfg.mode
        local sp = mode == "Spectrum" and Analyzer:GetSpectrum() or nil
        local n = sp and #sp or 0
        local lv = mode == "Loudness" and math.clamp(Analyzer.RmsLevel * 3.5, 0, 1) or 0
        if mode == "Random" and t >= nextRnd then
            nextRnd = t + .09
            local amp = playing and 1 or 0
            for i = 1, COUNT do rnd[i] = math.random() * amp end
        end
        local rainbow = Cfg.rainbow
        for i, b in Bars do
            local v
            if mode == "Spectrum" then
                v = n > 0 and math.clamp((sp[math.floor((i - 1) / COUNT * n) + 1] or 0) * SENS, 0, 1) or 0
            elseif mode == "Loudness" then
                v = lv * (.8 + .2 * math.sin(t * 6 + i * .3))
            else
                v = rnd[i]
            end
            sm[i] += (v - sm[i]) * .16
            setBar(b, MINL + (MAXL - MINL) * sm[i])
            if rainbow then
                b.Frame.BackgroundColor3 = Color3.fromHSV((t * .15 + i / COUNT) % 1, .75, 1)
            end
        end
        if wasRainbow and not rainbow then
            for _, b in Bars do b.Frame.BackgroundColor3 = Color3.new(1, 1, 1) end
        end
        wasRainbow = rainbow
        osu.Rotation = math.sin(t * .3)
        dt = task.wait()
    end
end)

local listOpen, ready, dragMoved = false, false, false
local dragging, dragStart, startPos

connect(Circle.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or (input.UserInputType == Enum.UserInputType.Touch and not listOpen) then
        dragging, dragStart, startPos = true, input.Position, Holder.Position
    end
end)
connect(UIS.InputEnded, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)
connect(UIS.InputChanged, function(input)
    if not dragging then return end
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        local d = input.Position - dragStart
        Holder.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
    end
end)

local R = 75
local Ri = R * .92
local D = Ri * .62
local BORDER, GAP = 2, 2
local cx, cy = R, R

local ACCENT_A = Color3.fromRGB(140, 100, 255)
local ACCENT_B = Color3.fromRGB(255, 200, 255)
local BTN_IDLE = Color3.fromRGB(10, 10, 10)
local BTN_HOVER = Color3.fromRGB(40, 40, 40)
local BTN_PRESS = Color3.fromRGB(30, 30, 30)
local TEXT_IDLE = Color3.fromRGB(230, 232, 245)
local TEXT_HOVER = Color3.new(1, 1, 1)
local SONG_ON = Color3.fromRGB(190, 170, 255)
local A_IDLE, A_HOVER, A_PRESS = 1, 1, 1

local function disc(parent, size, pos, color, z)
    local f = make("Frame", parent, {
        Size = UDim2.fromOffset(size, size), Position = pos, BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = z,
    })
    make("UICorner", f, { CornerRadius = UDim.new(1, 0) })
    return f
end

local IslandFolder = make("Frame", Circle, { Name = "Island", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 3 })
local island = make("Frame", IslandFolder, {
    Name = "Body", BackgroundTransparency = 1, ClipsDescendants = true,
    Position = UDim2.fromOffset(cx - Ri, cy - Ri), Size = UDim2.fromOffset(Ri * 2, Ri - D), ZIndex = 2,
})
local islandDisc = disc(island, Ri * 2, UDim2.fromOffset(0, 0), Color3.new(1, 1, 1), 2)
islandDisc.BackgroundTransparency = 1
make("UIGradient", islandDisc, { Color = ColorSequence.new(ACCENT_A, ACCENT_B) })

local Ri2, D2 = Ri - BORDER, D + BORDER
local btnW, btnH = Ri2 - GAP / 2, Ri2 - D2

local function icon(parent, key, glyph, size, box)
    local t = make("TextLabel", parent, {
        AnchorPoint = Vector2.new(.5, .5), Size = UDim2.fromOffset(box or size + 8, box or size + 8), BackgroundTransparency = 1,
        TextColor3 = TEXT_IDLE, Font = Enum.Font.BuilderSans, TextSize = size,
    })
    local img = make("ImageLabel", t, {
        AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5),
        Size = UDim2.fromScale(ICON_SCALE, ICON_SCALE), BackgroundTransparency = 1,
    })
    local function set(k, g)
        local id = ICON[k] or ""
        img.Image = id
        img.Visible = id ~= ""
        t.Text = id ~= "" and "" or g
    end
    set(key, glyph)
    return t, set, img
end

local function makeButton(name, left, circleX, key, text, size, callback, shift)
    local b = make("TextButton", IslandFolder, {
        Name = name, BackgroundTransparency = 1, ClipsDescendants = true, AutoButtonColor = false, Text = "",
        Position = UDim2.fromOffset(left, cy - Ri2), Size = UDim2.fromOffset(btnW, btnH), ZIndex = 3,
    })
    local c = disc(b, Ri2 * 2, UDim2.fromOffset(circleX, 0), BTN_IDLE, 3)
    c.BackgroundTransparency = A_IDLE
    local l, _, img = icon(b, key, text, size, 34)
    l.Position = UDim2.new(.5, shift, .5, 0)
    l.TextTransparency = .15
    l.TextStrokeColor3 = Color3.new(0, 0, 0)
    l.TextStrokeTransparency = .7
    l.ZIndex = 4
    img.ZIndex = 5
    img.ImageTransparency = .15
    local ls = make("UIScale", l)
    local hov, prs = false, false
    local function refresh()
        if prs then
            tween(c, .08, { BackgroundColor3 = BTN_PRESS, BackgroundTransparency = A_PRESS })
            tween(ls, .08, { Scale = .9 })
            tween(l, .08, { Position = UDim2.new(.5, shift, .5, 1), TextTransparency = 0 })
            tween(img, .08, { ImageTransparency = 0 })
        elseif hov then
            tween(c, .2, { BackgroundColor3 = BTN_HOVER, BackgroundTransparency = A_HOVER })
            tween(ls, .2, { Scale = 1.01 }, Enum.EasingStyle.Back)
            tween(l, .2, { Position = UDim2.new(.5, shift, .5, -1), TextColor3 = TEXT_HOVER, TextTransparency = 0 })
            tween(img, .2, { ImageTransparency = 0 })
        else
            tween(c, .25, { BackgroundColor3 = BTN_IDLE, BackgroundTransparency = A_IDLE })
            tween(ls, .25, { Scale = 1 })
            tween(l, .25, { Position = UDim2.new(.5, shift, .5, 0), TextColor3 = TEXT_IDLE, TextTransparency = .15 })
            tween(img, .25, { ImageTransparency = .15 })
        end
    end
    connect(b.MouseEnter, function() hov = true; refresh() end)
    connect(b.MouseLeave, function() hov, prs = false, false; refresh() end)
    connect(b.MouseButton1Down, function() prs = true; refresh() end)
    connect(b.MouseButton1Up, function() prs = false; refresh() end)
    connect(b.Activated, callback)
end

local BASE_W, PAD, MAIN_H, OPT_H = 126, 4, 28, 24
local MIN_S, S0, FY, COVER_T = .38, 48, cy, .9
local ITEM_BG = Color3.fromRGB(26, 26, 38)
local ITEM_HL = Color3.fromRGB(64, 64, 100)

local Lists = {}

local function newList()
    local L = { entries = {}, scroll = 0, st = 0, alpha = 0, target = 0, lastWheel = 0 }
    local E = L.entries
    local frame = make("Frame", Circle, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 6, Visible = false })
    Lists[#Lists + 1] = L

    local function centers()
        local t, out = 0, {}
        for i, e in E do
            out[i] = t + e.tgtH / 2
            t += e.tgtH
        end
        return out
    end

    function L.clamp(v)
        local tc = centers()
        if #tc == 0 then return 0 end
        local hi = tc[1]
        for i, e in E do
            if e.tgtH > 0 then hi = tc[i] end
        end
        return math.clamp(v, tc[1], hi)
    end

    function L.focus(e) L.st = L.clamp(centers()[e.idx]) end

    function L.snap()
        local tc = centers()
        L.scroll, L.st = tc[1] or 0, tc[1] or 0
    end

    function L.add(kind, text, h, indent, ts, color)
        local b = make("TextButton", frame, {
            AnchorPoint = Vector2.new(.5, .5), Size = UDim2.fromOffset(BASE_W, h), Position = UDim2.fromOffset(cx, FY),
            BackgroundColor3 = ITEM_BG, BorderSizePixel = 0, AutoButtonColor = false, Text = "",
            ClipsDescendants = true, Visible = false,
        })
        make("UICorner", b, { CornerRadius = UDim.new(0, 9) })
        local stroke = make("UIStroke", b, { Thickness = 1, Color = Color3.new(1, 1, 1), Transparency = .9, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
        local scale = make("UIScale", b)
        local label = make("TextLabel", b, {
            AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(0, indent, .5, 0), Size = UDim2.new(1, -(indent + 26), 0, h),
            BackgroundTransparency = 1, Text = text, TextColor3 = color or TEXT_IDLE, Font = Enum.Font.BuilderSans,
            TextSize = ts or 13, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
        })
        local e = {
            idx = #E + 1, kind = kind, frame = b, stroke = stroke, scale = scale, label = label,
            baseH = h, slot = h + PAD, curH = h + PAD, tgtH = h + PAD,
            hover = 0, hoverT = 0, press = 0, pressT = 0, flash = 0, fill = 0, state = false,
        }
        connect(b.MouseEnter, function() e.hoverT = 1 end)
        connect(b.MouseLeave, function() e.hoverT, e.pressT = 0, 0 end)
        connect(b.MouseButton1Down, function() e.pressT = 1 end)
        connect(b.MouseButton1Up, function() e.pressT = 0 end)
        E[#E + 1] = e
        return e
    end

    local function tap(e, fn)
        connect(e.frame.Activated, function()
            if dragMoved then return end
            fn()
        end)
    end
    L.tap = tap

    local function indicator(e, round, size)
        e.ind = make("Frame", e.frame, {
            AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -10, .5, 0), Size = UDim2.fromOffset(size, size),
            BackgroundColor3 = ACCENT_B, BackgroundTransparency = 1, BorderSizePixel = 0,
        })
        make("UICorner", e.ind, { CornerRadius = round and UDim.new(1, 0) or UDim.new(.32, 0) })
        e.indStroke = make("UIStroke", e.ind, { Thickness = 1.5, Color = Color3.new(1, 1, 1), ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
    end

    function L.toggle(text, default, cb)
        local e = L.add("toggle", text, MAIN_H, 12, 11)
        e.state = default and true or false
        e.fill = e.state and 1 or 0
        indicator(e, false, 14)
        tap(e, function()
            e.state = not e.state
            L.focus(e)
            if cb then cb(e.state) else print(text, e.state) end
        end)
        return e
    end

    function L.button(text, cb, ts)
        local e = L.add("button", text, MAIN_H, 0, ts)
        e.label.TextXAlignment = Enum.TextXAlignment.Center
        e.label.Position = UDim2.new(0, 0, .5, 0)
        e.label.Size = UDim2.new(1, 0, 0, MAIN_H)
        tap(e, function()
            e.flash = 1
            L.focus(e)
            if cb then cb() else print(text) end
        end)
        return e
    end

    function L.textbox(text, default, cb)
        local e = L.add("textbox", text, MAIN_H, 12, 11)
        e.label.Size = UDim2.new(1, -(12 + 62), 0, MAIN_H)
        e.last = tostring(default)
        local box = make("TextBox", e.frame, {
            AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -8, .5, 0), Size = UDim2.fromOffset(46, 18),
            BackgroundColor3 = Color3.fromRGB(12, 12, 18), BorderSizePixel = 0, Text = e.last, TextColor3 = TEXT_HOVER,
            PlaceholderText = "0-10", Font = Enum.Font.BuilderSans, TextSize = 11, ClearTextOnFocus = false,
        })
        make("UICorner", box, { CornerRadius = UDim.new(0, 6) })
        connect(box.FocusLost, function()
            local n = tonumber(box.Text)
            if n then
                n = math.clamp(n, 0, 10)
                e.last = tostring(math.floor(n * 100 + .5) / 100)
                box.Text = e.last
                if cb then cb(n) end
            else
                box.Text = e.last
            end
        end)
        e.box = box
        e.tick = function(_, vis)
            box.TextTransparency = 1 - vis
            box.BackgroundTransparency = 1 - .8 * vis
        end
        return e
    end

    function L.header(text)
        local e = L.add("header", text, 18, 0, 10, ACCENT_B)
        e.flat = true
        e.label.Font = Enum.Font.BuilderSans
        e.label.TextXAlignment = Enum.TextXAlignment.Center
        e.label.Position = UDim2.new(0, 0, .5, 0)
        e.label.Size = UDim2.new(1, 0, 0, 18)
        return e
    end

    local function setOpen(h, open)
        h.open = open
        h.arrowT = open and 180 or 0
        for _, o in h.options do o.tgtH = open and o.slot or 0 end
        local tc = centers()
        L.st = L.clamp(open and tc[h.idx] + #h.options * (OPT_H + PAD) / 2 or tc[h.idx])
    end

    function L.dropdown(text, multi, opts, cb, def)
        local h = L.add("dropdown", text, MAIN_H, 12, 11)
        h.arrow = make("TextLabel", h.frame, {
            AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -10, .5, 0), Size = UDim2.fromOffset(14, 14),
            BackgroundTransparency = 1, Text = "▼", TextColor3 = TEXT_IDLE, Font = Enum.Font.BuilderSans, TextSize = 9,
        })
        h.arrowRot, h.arrowT, h.open, h.options = 0, 0, false, {}
        for i, name in opts do
            local o = L.add("option", name, OPT_H, 20, 11)
            o.curH, o.tgtH = 0, 0
            o.state = (not multi) and i == (def or 1)
            o.fill = o.state and 1 or 0
            indicator(o, not multi, 10)
            h.options[#h.options + 1] = o
            tap(o, function()
                if multi then
                    o.state = not o.state
                else
                    for _, s in h.options do s.state = (s == o) end
                    setOpen(h, false)
                end
                if cb then cb(name, o.state) else print(text, name, o.state) end
            end)
        end
        tap(h, function() setOpen(h, not h.open) end)
        return h
    end

    connect(RS.RenderStepped, function(dt)
        local k = 1 - math.exp(-dt * 14)
        if L.alpha < L.target then
            L.alpha = math.min(L.target, L.alpha + dt * 2.4)
        elseif L.alpha > L.target then
            L.alpha = math.max(L.target, L.alpha - dt * 2.4)
        end
        local alpha = L.alpha
        frame.Visible = alpha > .001
        if not frame.Visible then return end

        if L.lastWheel > 0 and os.clock() - L.lastWheel > .15 then
            L.lastWheel = 0
            local tc, best, bd = centers(), L.st, math.huge
            for i, e in E do
                if e.tgtH > 0 then
                    local d = math.abs(tc[i] - L.st)
                    if d < bd then best, bd = tc[i], d end
                end
            end
            L.st = best
        end
        L.scroll += (L.st - L.scroll) * k

        local top = 0
        for _, e in E do
            e.curH += (e.tgtH - e.curH) * k
            if math.abs(e.tgtH - e.curH) < .05 then e.curH = e.tgtH end
            e.c = top + e.curH / 2
            top += e.curH

            local frac, f = e.curH / e.slot, e.frame
            if frac < .02 then
                f.Visible = false
                continue
            end

            local p = e.c - L.scroll
            local a = math.abs(p)
            local s0 = MIN_S + (1 - MIN_S) / (1 + (a / S0) ^ 2)
            local off = MIN_S * a + (1 - MIN_S) * S0 * math.atan(a / S0)
            local y = FY + (p < 0 and -off or off)

            local lag = math.min(a / 32, 7) * .07
            local en = ease(math.clamp((alpha - lag) / .5, 0, 1))
            y += (1 - en) * 70

            local h = e.baseH * frac
            local dyEff = math.abs(y - cy) + h * .5 * s0
            local allowed = 2 * math.sqrt(math.max(0, (R - 4) ^ 2 - dyEff ^ 2))
            local s = math.min(s0, allowed / BASE_W)
            local edge = math.clamp((y - 34) / 16, 0, 1) * math.clamp((146 - y) / 16, 0, 1)
            local vis = en * edge * frac

            if vis < .02 or s < .08 then
                f.Visible = false
                continue
            end
            f.Visible = true

            e.hover += (e.hoverT - e.hover) * k
            e.press += (e.pressT - e.press) * k
            e.flash *= 1 - math.min(1, dt * 6)
            local focus = (s0 - MIN_S) / (1 - MIN_S)

            f.Position = UDim2.fromOffset(cx, y)
            f.Size = UDim2.fromOffset(BASE_W, h)
            e.scale.Scale = s * (1 - .05 * e.press)
            if e.flat then
                f.BackgroundTransparency = 1
                e.stroke.Transparency = 1
            else
                f.BackgroundColor3 = ITEM_BG:Lerp(ITEM_HL, math.clamp(e.hover * .7 + e.flash, 0, 1))
                f.BackgroundTransparency = 1 - (.3 + .4 * focus) * vis
                e.stroke.Transparency = 1 - (.1 + .25 * focus) * vis
                e.label.TextColor3 = TEXT_IDLE:Lerp(TEXT_HOVER, e.hover)
            end
            e.label.TextTransparency = 1 - (1 - .55 * (1 - focus)) * vis

            if e.ind then
                e.fill += ((e.state and 1 or 0) - e.fill) * k
                e.ind.BackgroundTransparency = 1 - e.fill * vis
                e.indStroke.Transparency = 1 - .8 * vis
            end
            if e.arrow then
                e.arrowRot += (e.arrowT - e.arrowRot) * k
                e.arrow.Rotation = e.arrowRot
                e.arrow.TextTransparency = 1 - .8 * vis
            end
            if e.tick then e.tick(e, vis, focus) end
        end
    end)

    return L
end

local function activeList()
    for _, L in Lists do
        if L.target == 1 then return L end
    end
end

local function toggleList(L)
    if not ready then return end
    local was = L.target == 1
    for _, o in Lists do o.target = 0 end
    if not was then
        L.target = 1
        if L.onOpen then L.onOpen() end
    end
    listOpen = not was
end

local Settings, Playlist = newList(), newList()

makeButton("ButtonLeft", cx - Ri2, 0, "settings", "∙∙∙", 18, function() toggleList(Settings) end, 20)
makeButton("ButtonRight", cx + GAP / 2, -(Ri2 + GAP / 2), "playlist", "♪", 18, function() toggleList(Playlist) end, -20)

local Zone = make("Frame", Circle, { Name = "Zone", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 10 })
local zoneHover, lastWheelAt = false, 0
connect(Zone.MouseEnter, function() zoneHover = true end)
connect(Zone.MouseLeave, function() zoneHover = false end)

local function wheelScroll(z)
    local L = activeList()
    if not L then return false end
    local over = zoneHover
    if not over then
        for _, e in L.entries do
            if e.hoverT == 1 then over = true break end
        end
    end
    if not over then return false end
    if os.clock() - lastWheelAt > .02 then
        lastWheelAt = os.clock()
        L.st = L.clamp(L.st - z * (MAIN_H + PAD))
        L.lastWheel = os.clock()
    end
    return true
end

CAS:BindActionAtPriority("OrbituneWheel", function(_, _, input)
    return wheelScroll(input.Position.Z) and Enum.ContextActionResult.Sink or Enum.ContextActionResult.Pass
end, false, Enum.ContextActionPriority.High.Value, Enum.UserInputType.MouseWheel)
connections[#connections + 1] = { Disconnect = function() CAS:UnbindAction("OrbituneWheel") end }

connect(UIS.InputChanged, function(input)
    if input.UserInputType == Enum.UserInputType.MouseWheel then wheelScroll(input.Position.Z) end
end)

local touchInput, touchY0, touchS0
connect(Zone.InputBegan, function(input)
    local L = activeList()
    if input.UserInputType ~= Enum.UserInputType.Touch or not L then return end
    touchInput, touchY0, touchS0 = input, input.Position.Y, L.st
    dragMoved = false
    L.lastWheel = 0
end)
connect(UIS.InputChanged, function(input)
    local L = activeList()
    if input ~= touchInput or not L then return end
    local dy = (input.Position.Y - touchY0) / HolderScale.Scale
    if math.abs(dy) > 6 then dragMoved = true end
    if dragMoved then L.st = L.clamp(touchS0 - dy) end
end)
connect(UIS.InputEnded, function(input)
    if input ~= touchInput then return end
    touchInput = nil
    local L = activeList()
    if dragMoved and L then L.lastWheel = os.clock() end
    task.delay(.1, function() dragMoved = false end)
end)

local function openAlpha()
    local m = 0
    for _, L in Lists do m = math.max(m, L.alpha) end
    return m
end

connect(RS.RenderStepped, function()
    osu.ImageTransparency = COVER_T * ease(openAlpha())
end)

local closing = false
local function unload()
    if not ready or closing then return end
    closing = true
    tween(AudioPlayer, .5, { Volume = 0 }, Enum.EasingStyle.Linear)
    tween(HolderScale, .4, { Scale = 0 }, Enum.EasingStyle.Cubic).Completed:Wait()
    cleanup()
end

local Controls = make("Frame", Holder, { Name = "Controls", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 8, Visible = false })
local pops = {}
local playSong, step, toggle

-- prev / play / next + time label live in Cluster so they can slide up together
local Cluster = make("Frame", Controls, { Name = "Cluster", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
local TimeLabel = make("TextLabel", Cluster, {
    Name = "Time", AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromOffset(180, 245), Size = UDim2.fromOffset(64, 8),
    BackgroundTransparency = 1, Text = "0:00 / 0:00", TextColor3 = Color3.fromRGB(205, 210, 230), TextTransparency = .2,
    TextStrokeTransparency = .6, Font = Enum.Font.BuilderSans, TextSize = 8,
})

local function ctrl(dx, dy, size, key, glyph, gsize, cb)
    local b = make("TextButton", Cluster, {
        AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromOffset(180 + dx, 180 + dy), Size = UDim2.fromOffset(size, size),
        BackgroundColor3 = BTN_IDLE, BackgroundTransparency = .25, BorderSizePixel = 0, AutoButtonColor = false, Text = "",
    })
    make("UICorner", b, { CornerRadius = UDim.new(1, 0) })
    make("UIStroke", b, { Thickness = 1.5, Color = Color3.new(1, 1, 1), Transparency = .8 })
    local sc = make("UIScale", b, { Scale = 0 })
    pops[#pops + 1] = sc
    local t, set = icon(b, key, glyph, gsize)
    t.Position = UDim2.fromScale(.5, .5)
    connect(b.MouseEnter, function()
        tween(sc, .15, { Scale = 1.1 })
        tween(b, .15, { BackgroundColor3 = BTN_HOVER })
    end)
    connect(b.MouseLeave, function()
        tween(sc, .15, { Scale = 1 })
        tween(b, .15, { BackgroundColor3 = BTN_IDLE })
    end)
    connect(b.MouseButton1Down, function() tween(sc, .08, { Scale = .88 }) end)
    connect(b.MouseButton1Up, function() tween(sc, .12, { Scale = 1.1 }) end)
    connect(b.Activated, cb)
    return b, set
end

ctrl(-27, 84, 24, "prev", "◀◀", 10, function() step(-1) end)
local _, setPlay = ctrl(0, 94, 27, "play", "▶", 13, function() toggle() end)
_.Position += UDim2.fromOffset(0,-4) 
ctrl(27, 84, 24, "next", "▶▶", 10, function() step(1) end)

local NAME_W = 116
local NameTint = make("Frame", Controls, {
    AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromOffset(180, 299), Size = UDim2.fromOffset(NAME_W + 14, 20),
    BackgroundColor3 = Color3.fromRGB(8, 8, 12), BackgroundTransparency = .45, BorderSizePixel = 0,
})
make("UICorner", NameTint, { CornerRadius = UDim.new(1, 0) })
NameTint.Active = true
local NameFrame = make("Frame", Holder, {
    Name = "NameBox", AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromOffset(180, 119 + 180),
    Size = UDim2.fromOffset(NAME_W, 16), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 8,
})
local NameLabel = make("TextLabel", NameFrame, {
    Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", TextTransparency = 1,
    TextColor3 = Color3.fromRGB(205, 210, 230), Font = Enum.Font.BuilderSans, TextSize = 12,
})
local nameToken = 0

local function setName(str, dim)
    nameToken += 1
    local my = nameToken
    local function w(t) return TXT:GetTextSize(t, 12, Enum.Font.BuilderSans, Vector2.new(1e5, 20)).X end
    NameLabel.Text = str
    if w(str) <= NAME_W then
        tween(NameLabel, .25, { TextTransparency = dim or .1 })
        return
    end
    local n = utf8.len(str) or #str
    local function head(k) return str:sub(1, (utf8.offset(str, k + 1) or #str + 1) - 1) end
    local function tail(k) return str:sub(utf8.offset(str, k) or 1) end
    local hk, tk = n, 1
    while hk > 1 and w(head(hk) .. "...") > NAME_W do hk -= 1 end
    while tk < n and w("..." .. tail(tk)) > NAME_W do tk += 1 end
    local a, b = head(hk) .. "...", "..." .. tail(tk)
    task.spawn(function()
        local i = 0
        while nameToken == my and Gui.Parent do
            NameLabel.Text = i % 2 == 0 and a or b
            i += 1
            NameLabel.TextTransparency = 1
            tween(NameLabel, .25, { TextTransparency = .1 })
            task.wait(2.2)
            if nameToken ~= my then break end
            tween(NameLabel, .25, { TextTransparency = 1 })
            task.wait(.3)
        end
    end)
end

cur, playing, startedAt, pausedAt = nil, false, 0, 0

-- progress bar (NameTint) + time label + layout
do
    local ProgFill = make("Frame", NameTint, {
        Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = .6, BorderSizePixel = 0,
    })
    make("UICorner", ProgFill, { CornerRadius = UDim.new(1, 0) })
    make("UIGradient", ProgFill, { Color = ColorSequence.new(ACCENT_A, ACCENT_B) })

    local function fmt(s)
        s = math.max(0, math.floor(s))
        return string.format("%d:%02d", s // 60, s % 60)
    end
    local function curPos()
        if not cur then return 0 end
        return playing and AudioPlayer.TimePosition or pausedAt
    end

    local seeking, seekFrac, seekInput = false, 0, nil
    local function fracAt(x)
        return math.clamp((x - NameTint.AbsolutePosition.X) / math.max(NameTint.AbsoluteSize.X, 1), 0, 1)
    end

    connect(NameTint.InputBegan, function(input)
        local ut = input.UserInputType
        if (ut == Enum.UserInputType.MouseButton1 or ut == Enum.UserInputType.Touch) and cur then
            seeking, seekInput, seekFrac = true, input, fracAt(input.Position.X)
        end
    end)
    connect(UIS.InputChanged, function(input)
        if not seeking then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement or input == seekInput then
            seekFrac = fracAt(input.Position.X)
        end
    end)
    connect(UIS.InputEnded, function(input)
        if not seeking then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input == seekInput then
            seeking = false
            local len = AudioPlayer.TimeLength
            if cur and len > 0 then
                local t = math.min(seekFrac * len, len - .05)
                if playing then AudioPlayer.TimePosition = t else pausedAt = t end
            end
        end
    end)

    local lastTxt = ""
    connect(RS.RenderStepped, function()
        local len = cur and AudioPlayer.TimeLength or 0
        local pos = seeking and seekFrac * len or curPos()
        ProgFill.Size = UDim2.fromScale(len > 0 and math.clamp(pos / len, 0, 1) or 0, 1)
        if Cfg.showTime then
            local txt = fmt(pos) .. " / " .. fmt(len)
            if txt ~= lastTxt then
                lastTxt = txt
                TimeLabel.Text = txt
            end
        end
    end)

    function Cfg.applyLayout()
        NameTint.Visible, NameFrame.Visible = Cfg.showName, Cfg.showName
        TimeLabel.Visible = Cfg.showTime
    end
end

local function refreshPlay()
    setPlay(playing and "pause" or "play", playing and "❚❚" or "▶")
end

playSong = function(s)
    if not s then return end
    cur, playing, startedAt = s, true, os.clock()
    pausedAt = 0
    State.lastSong = s.path
    saveState()
    AudioPlayer:Stop()
    AudioPlayer.Asset = audioOf(s)
    AudioPlayer.TimePosition = 0
    AudioPlayer:Play()
    osu.Image = coverOf(s)
    setName(s.name)
    refreshPlay()
    local nx = songs[s.idx % #songs + 1]
    task.spawn(function() pcall(audioOf, nx) end)
end

step = function(d)
    local n = #songs
    if n == 0 then return end
    local i = cur and cur.idx or (d > 0 and 0 or 1)
    playSong(songs[(i - 1 + d) % n + 1])
end

toggle = function()
    if #songs == 0 then return end
    if not cur then return playSong(lastSong or songs[1]) end
    if playing then
        pausedAt = AudioPlayer.TimePosition
        playing = false
        AudioPlayer:Stop()
    else
        AudioPlayer.TimePosition = pausedAt
        AudioPlayer:Play()
        playing = true
    end
    refreshPlay()
end

connect(AudioPlayer.Ended, function()
    if playing and os.clock() - startedAt > .5 then step(1) end
end)

-- settings menu
do
    local SCALES = { ["70%"] = .7, ["80%"] = .8, ["100%"] = 1, ["120%"] = 1.2, ["140%"] = 1.4 }

    -- dB offsets: low < 400Hz, mid 400-4000Hz, high > 4000Hz (AudioEqualizer defaults)
    local EQ_PRESETS = {
        ["Bass Boost"] = { low = 8 },
        ["Vocal Boost"] = { low = -2, mid = 5 },
        ["Treble Boost"] = { high = 6 },
        ["Warm"] = { low = 3, high = -3 },
        ["V-Shape"] = { low = 6, mid = -3, high = 5 },
        ["Lo-Fi"] = { low = 2, high = -18 },
    }
    local eqActive = type(State.eq) == "table" and State.eq or {}
    local function applyEQ()
        local lo, mi, hi = 0, 0, 0
        for name, on in eqActive do
            local p = on and EQ_PRESETS[name]
            if p then
                lo += p.low or 0
                mi += p.mid or 0
                hi += p.high or 0
            end
        end
        Equalizer.LowGain = math.clamp(lo, -80, 10)
        Equalizer.MidGain = math.clamp(mi, -80, 10)
        Equalizer.HighGain = math.clamp(hi, -80, 10)
    end

    local hideKey = State.hideKey and Enum.KeyCode[State.hideKey] or nil
    local listening, hideBtn = false, nil
    local function keyName(k)
        return (k.Name:gsub("Right", "R"):gsub("Left", "L"):gsub("Control", "Ctrl"))
    end

    local scaleNames = { "70%", "80%", "100%", "120%", "140%" }
    local scaleDef = 3
    for i, name in scaleNames do if SCALES[name] == Cfg.scale then scaleDef = i break end end
    Settings.toggle("Rainbow Bars", Cfg.rainbow, function(v)
        Cfg.rainbow = v
        State.rainbow = v
        saveState()
    end)
    Settings.dropdown("Reaction Mode", false, { "Spectrum", "Loudness", "Random" }, function(name)
        Cfg.mode = name
        State.mode = name
        saveState()
    end, table.find({ "Spectrum", "Loudness", "Random" }, Cfg.mode) or 1)
    Settings.toggle("Show Name", Cfg.showName, function(v)
        Cfg.showName = v
        State.showName = v
        Cfg.applyLayout()
        saveState()
    end)
    Settings.toggle("Show Time", Cfg.showTime, function(v)
        Cfg.showTime = v
        State.showTime = v
        Cfg.applyLayout()
        saveState()
    end)
    Settings.dropdown("UI Scale", false, scaleNames, function(name)
        Cfg.scale = SCALES[name]
        State.scale = Cfg.scale
        tween(HolderScale, .3, { Scale = Cfg.scale }, Enum.EasingStyle.Cubic)
        saveState()
    end, scaleDef)
    Settings.textbox("Volume", Cfg.volume, function(v)
        Cfg.volume = v
        State.volume = v
        AudioPlayer.Volume = v
        saveState()
    end)
    local sfxDropdown = Settings.dropdown("SFX", true, { "Bass Boost", "Vocal Boost", "Treble Boost", "Warm", "V-Shape", "Lo-Fi" }, function(name, on)
        eqActive[name] = on
        State.eq = eqActive
        applyEQ()
        saveState()
    end)
    for _, o in sfxDropdown.options do
        o.state = eqActive[o.label.Text] == true
        o.fill = o.state and 1 or 0
    end
    applyEQ()
    Settings.button("Play Random", function()
        local n = #songs
        if n == 0 then return end
        local s = songs[math.random(n)]
        if n > 1 then
            while s == cur do s = songs[math.random(n)] end
        end
        playSong(s)
    end)
    hideBtn = Settings.button("Hide Bind [" .. (hideKey and keyName(hideKey) or "None") .. "]", function()
        listening = true
        hideBtn.label.Text = "press a key"
    end, 11)
    Settings.button("Unload UI", unload)
    Settings.snap()
    State.rainbow = Cfg.rainbow
    State.mode = Cfg.mode
    State.showName = Cfg.showName
    State.showTime = Cfg.showTime
    State.scale = Cfg.scale
    State.volume = Cfg.volume
    State.eq = eqActive
    State.hideKey = hideKey and hideKey.Name or nil
    Cfg.applyLayout()
    saveState()

    connect(UIS.InputBegan, function(input, gp)
        if listening then
            if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
            listening = false
            hideKey = input.KeyCode ~= Enum.KeyCode.Escape and input.KeyCode or nil
            State.hideKey = hideKey and hideKey.Name or nil
            saveState()
            hideBtn.label.Text = "Hide Bind [" .. (hideKey and keyName(hideKey) or "None") .. "]"
            return
        end
        if gp or not hideKey or input.KeyCode ~= hideKey or UIS:GetFocusedTextBox() then return end
        Gui.Enabled = not Gui.Enabled
        if not Gui.Enabled then
            for _, L in Lists do L.target = 0 end
            listOpen, zoneHover = false, false
        end
    end)
end

if #songs == 0 then Playlist.header("no songs found") end
for _, cat in categories do
    Playlist.header(cat.label)
    for _, s in cat.songs do
        local e = Playlist.add("song", s.name, OPT_H, 26, 12)
        s.entry = e
        local rec, _, img = icon(e.frame, "record", "◉", 13)
        rec.Position = UDim2.new(0, 14, .5, 0)
        rec.TextColor3 = SONG_ON
        e.tick = function(_, vis)
            local on = cur == s
            local tr = 1 - (on and vis or 0)
            rec.TextTransparency, img.ImageTransparency = tr, tr
            if on then
                e.label.TextColor3 = SONG_ON
                if playing then rec.Rotation = (os.clock() * 220) % 360 end
            end
        end
        Playlist.tap(e, function()
            e.flash = 1
            playSong(s)
        end)
    end
end
Playlist.snap()
Playlist.onOpen = function()
    local s = cur or lastSong or songs[1]
    if s and s.entry then Playlist.focus(s.entry) end
end

local Card = make("Frame", Circle, {
    Name = "Intro", AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5), Size = UDim2.fromScale(1, 1),
    BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 20,
})
local CardScale = make("UIScale", Card)
local texts = {}
make("UICorner", Card, { CornerRadius = UDim.new(1, 0) })
make("UIGradient", Card, { Color = ColorSequence.new(Color3.fromRGB(24, 18, 44), Color3.fromRGB(12, 22, 38)), Rotation = 45 })

local function lbl(text, y, w, h, size, font, color, tr)
    local t = make("TextLabel", Card, {
        AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, y), Size = UDim2.fromOffset(w, h),
        BackgroundTransparency = 1, Text = text, TextColor3 = color, TextTransparency = tr or 0,
        Font = font, TextSize = size, TextWrapped = true, ZIndex = 21,
    })
    texts[#texts + 1] = t
    return t
end

local infoText = #songs == 0 and "no songs found" or (#songs .. (#songs == 1 and " song" or " songs") .. " found!")
lbl(infoText, .3, 120, 16, 12, Enum.Font.BuilderSans, Color3.fromRGB(165, 178, 208))
lbl("Thank you for using this script!", .5, 112, 34, 13, Enum.Font.BuilderSans, Color3.fromRGB(160, 120, 255))
local preText = lbl("preloading songs..", .72, 120, 12, 10, Enum.Font.BuilderSans, Color3.fromRGB(150, 150, 178), .45)
local track = make("Frame", Card, {
    AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .8), Size = UDim2.fromOffset(56, 3),
    BackgroundColor3 = Color3.fromRGB(40, 40, 62), BorderSizePixel = 0, ZIndex = 21,
})
make("UICorner", track, { CornerRadius = UDim.new(1, 0) })
local fill = make("Frame", track, { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 22 })
make("UICorner", fill, { CornerRadius = UDim.new(1, 0) })
make("UIGradient", fill, { Color = ColorSequence.new(ACCENT_A, ACCENT_B) })

local function dismiss()
    tween(CardScale, .6, { Scale = 1.15 }, Enum.EasingStyle.Cubic)
    tween(Card, .6, { BackgroundTransparency = 1 }, Enum.EasingStyle.Cubic)
    for _, t in texts do tween(t, .45, { TextTransparency = 1 }) end
    tween(track, .45, { BackgroundTransparency = 1 })
    tween(fill, .45, { BackgroundTransparency = 1 })
    task.wait(.6)
    Card.Visible = false
end

task.spawn(function()
    local t0 = os.clock()
    for i, s in songs do
        preText.Text = "preloading songs " .. i .. "/" .. #songs
        tween(fill, .15, { Size = UDim2.fromScale(i / #songs, 1) })
        if i % 3 == 0 then task.wait() end
    end
    if #songs == 0 then tween(fill, .3, { Size = UDim2.fromScale(1, 1) }) end
    task.wait(math.max(.3, 2.6 - (os.clock() - t0)))
    preText.Text = "ready"
    task.wait(.25)
    dismiss()
    Controls.Visible = true
    for i, sc in pops do
        task.delay(.08 * i, function() tween(sc, .4, { Scale = 1 }, Enum.EasingStyle.Back) end)
    end
    setName(#songs > 0 and "nothing playing" or "no songs found", .55)
    ready = true
end)

tween(HolderScale, .45, { Scale = Cfg.scale }, Enum.EasingStyle.Cubic)
Cluster.Position = UDim2.fromOffset(0,3)
