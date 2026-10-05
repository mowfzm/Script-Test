--// ================= STATUS & SERVER TAB (module) =================
-- File này được script chính (test.lua) nạp vào và gọi với 1 bảng ctx
-- chứa các hàm/biến dùng chung của UI.

return function(ctx)
    local StatusServerTab     = ctx.Tab

    local Theme               = ctx.Theme
    local ScreenGui           = ctx.ScreenGui
    local LocalPlayer         = ctx.LocalPlayer
    local TeleportService     = ctx.TeleportService
    local HttpService         = ctx.HttpService
    local Players             = game:GetService("Players")
    local Stats               = game:GetService("Stats")

    local new                 = ctx.new
    local corner              = ctx.corner
    local stroke              = ctx.stroke
    local padding             = ctx.padding
    local label               = ctx.label

    local CreateInfoRow       = ctx.CreateInfoRow
    local CreateCard          = ctx.CreateCard
    local CreateStyledButton  = ctx.CreateStyledButton
    local CreateToggleOption  = ctx.CreateToggleOption
    local flashButtonFeedback = ctx.flashButtonFeedback
    local flashStrokeError    = ctx.flashStrokeError
    local bindBoxFocus        = ctx.bindBoxFocus
    local guarded             = ctx.guarded
    local isLocked            = ctx.isLocked -- thay cho biến uiLocked của file chính

    --// ---------- Cấu hình ----------
    local SPAM_JOIN_DELAY  = 1.5  -- giây giữa 2 lần Spam Join (tự tăng khi bị lỗi liên tiếp)
    local PENDING_TIMEOUT  = 10   -- sau bấy nhiêu giây coi như teleport trước đó đã xong/hết hạn
    local HOP_WAIT_RESULT  = 6    -- chờ tối đa bấy nhiêu giây xem teleport có bị từ chối không
    local HOP_MAX_ATTEMPTS = 3    -- số server thử tối đa cho mỗi lần Hop
    local PAGE_DELAY       = 0.3  -- nghỉ giữa các trang API để tránh 429

    local ScriptStartTime = os.time() -- os.clock() là CPU time, không phải thời gian thực

    --// ---------- Tiện ích ----------
    local function formatTime(seconds)
        if type(seconds) ~= "number" then return "--" end
        seconds = math.max(0, math.floor(seconds))
        return string.format("%dh%dm%ds", seconds // 3600, seconds % 3600 // 60, seconds % 60)
    end

    local function copyToClipboard(text)
        local fn = setclipboard or toclipboard or set_clipboard
            or (Clipboard and Clipboard.set)
            or (syn and syn.write_clipboard)
        if not fn then return false end
        return (pcall(fn, text))
    end

    -- JobId của Roblox luôn có dạng GUID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    local function isValidJobId(jobId)
        return type(jobId) == "string"
            and jobId:match("^%x+%-%x+%-%x+%-%x+%-%x+$") ~= nil
    end

    --// ---------- Trạng thái teleport dùng chung ----------
    -- teleportPending = true khi vừa gọi teleport và chưa biết kết quả.
    -- Nếu thành công, client sẽ rời server (script dừng); nếu thất bại,
    -- TeleportInitFailed sẽ báo về và ta mở khoá lại.
    local teleportPending = false
    local pendingToken    = 0
    local failStreak      = 0

    local function markPending()
        teleportPending = true
        pendingToken += 1
        local token = pendingToken
        task.delay(PENDING_TIMEOUT, function()
            if pendingToken == token then teleportPending = false end
        end)
    end

    local failedConn = TeleportService.TeleportInitFailed:Connect(function(player)
        if player ~= LocalPlayer then return end
        pendingToken += 1
        teleportPending = false
        failStreak += 1
    end)

    ScreenGui.Destroying:Connect(function()
        failedConn:Disconnect()
    end)

    -- Trả về ok, lý do (ngắn, vừa nút 70px)
    local function joinServer(jobId)
        if not isValidJobId(jobId) then return false, "Invalid" end
        if jobId == game.JobId then return false, "Same" end
        if teleportPending then return false, "Busy" end
        local ok = pcall(TeleportService.TeleportToPlaceInstance, TeleportService, game.PlaceId, jobId, LocalPlayer)
        if not ok then return false, "Failed" end
        markPending()
        return true
    end

    --// ---------- Các dòng thông tin cập nhật liên tục ----------
    local liveRows = {}

    local function CreateLiveRow(parent, title, getText)
        local Frame = CreateInfoRow(parent, title)

        local Value = label(Frame, {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, 0, 0.5, 0),
            Size = UDim2.fromOffset(110, 24),
            Text = "--",
            TextSize = 15,
            TextXAlignment = Enum.TextXAlignment.Right,
            TextColor3 = Theme.AccentPink,
        })

        table.insert(liveRows, { Value = Value, get = getText })
        return Frame
    end

    local function refreshLiveRows()
        for _, row in ipairs(liveRows) do
            local ok, txt = pcall(row.get)
            if ok and type(txt) == "string" and row.Value.Text ~= txt then
                row.Value.Text = txt
            end
        end
    end

    local function CreateCopyRow(parent, title, getText, showValue)
        local Frame, Left = CreateInfoRow(parent, title)

        if showValue then
            label(Left, {
                LayoutOrder = 2,
                Size = UDim2.new(0, 0, 1, 0),
                AutomaticSize = Enum.AutomaticSize.X,
                Text = getText(),
                TextSize = 15,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextColor3 = Theme.AccentPink,
            })
        end

        local Btn = CreateStyledButton(Frame, "Copy", 70)
        Btn.Activated:Connect(guarded(function(done)
            local text = getText()
            local ok = text ~= "" and copyToClipboard(text)
            flashButtonFeedback(Btn, "Copy", ok and "Copied!" or "Failed", not ok)
            done()
        end))
        return Frame
    end

    CreateLiveRow(StatusServerTab, "Timer", function()
        return formatTime(os.time() - ScriptStartTime)
    end)

    -- time() = số giây kể từ khi client vào server này (reset khi teleport sang server khác)
    CreateLiveRow(StatusServerTab, "Time Played", function()
        return formatTime(time())
    end)

    CreateLiveRow(StatusServerTab, "Players", function()
        return string.format("%d/%d", #Players:GetPlayers(), Players.MaxPlayers)
    end)

    local pingItem
    pcall(function()
        pingItem = Stats.Network.ServerStatsItem["Data Ping"]
    end)
    CreateLiveRow(StatusServerTab, "Ping", function()
        if not pingItem then return "--" end
        return string.format("%d ms", math.floor(pingItem:GetValue() + 0.5))
    end)

    -- 1 vòng lặp duy nhất cho tất cả các dòng live (thay vì mỗi dòng 1 vòng)
    task.spawn(function()
        while ScreenGui.Parent do
            refreshLiveRows()
            task.wait(0.5)
        end
    end)

    CreateCopyRow(StatusServerTab, "PlaceID", function() return tostring(game.PlaceId) end, true)

    --// ---------- Server Hopper ----------
    do
        local Card = CreateCard(StatusServerTab, "ServerHopper", 12, 14, 12)

        label(Card, {
            LayoutOrder = 1,
            Size = UDim2.new(1, 0, 0, 20),
            Text = "Server Hopper",
            TextSize = 15,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextColor3 = Theme.Text,
        })

        local Box = new("TextBox", {
            LayoutOrder = 2,
            Size = UDim2.new(1, 0, 0, 34),
            BackgroundColor3 = Theme.PanelAlt,
            BorderSizePixel = 0,
            Text = "",
            PlaceholderText = "",
            ClearTextOnFocus = false,
            Font = Enum.Font.Gotham,
            TextSize = 14,
            TextColor3 = Theme.Text,
            TextXAlignment = Enum.TextXAlignment.Left,
            ClipsDescendants = true,
        }, Card)
        corner(Box, 6)
        local BoxStroke = stroke(Box)
        padding(Box, 10, 10)

        local Placeholder = label(Box, {
            Size = UDim2.fromScale(1, 1),
            Text = "Paste your JobId here",
            Font = Enum.Font.Gotham,
            TextSize = 14,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextColor3 = Theme.SubText,
            TextTransparency = 0.5,
        })

        local function refreshPlaceholder()
            Placeholder.Visible = Box.Text == "" and not Box:IsFocused()
        end

        bindBoxFocus(Box, BoxStroke, refreshPlaceholder, function()
            Box.Text = (Box.Text:gsub("^%s+", ""):gsub("%s+$", ""))
            refreshPlaceholder()
        end)
        Box:GetPropertyChangedSignal("Text"):Connect(refreshPlaceholder)

        local function getJobId()
            return (Box.Text:gsub("[%s\"']", ""))
        end

        -- Join JobId
        local JoinFrame = CreateInfoRow(Card, "Join JobId", 40)
        JoinFrame.LayoutOrder = 3
        JoinFrame.BackgroundColor3 = Theme.PanelAlt

        local JoinBtn = CreateStyledButton(JoinFrame, "Join", 70)
        local joinBusy = false
        JoinBtn.Activated:Connect(function()
            if isLocked() or joinBusy then return end
            local jobId = getJobId()
            if jobId == "" then
                flashStrokeError(BoxStroke)
                flashButtonFeedback(JoinBtn, "Join", "Empty", true, 0.8)
                return
            end

            local ok, reason = joinServer(jobId)
            if not ok then
                if reason == "Invalid" or reason == "Same" then
                    flashStrokeError(BoxStroke)
                end
                flashButtonFeedback(JoinBtn, "Join", reason or "Failed", true, 0.8)
                return
            end

            joinBusy = true
            flashButtonFeedback(JoinBtn, "Join", "Joining...", false)
            task.delay(1.2, function() joinBusy = false end)
        end)

        -- Spam Join
        local Switch = CreateToggleOption(Card, "Spam Join", 40)
        Switch.Parent.LayoutOrder = 4
        Switch.Parent.BackgroundColor3 = Theme.PanelAlt

        local runId = 0

        local function stopSpam()
            Switch:SetAttribute("Toggled", false)
        end

        Switch:GetAttributeChangedSignal("Toggled"):Connect(function()
            runId += 1
            if not Switch:GetAttribute("Toggled") then return end

            -- JobId rỗng / sai / trùng server hiện tại: báo lỗi và tự tắt, không chạy vòng lặp vô ích
            local firstId = getJobId()
            if not isValidJobId(firstId) or firstId == game.JobId then
                flashStrokeError(BoxStroke)
                stopSpam()
                return
            end

            failStreak = 0
            local myRun = runId
            task.spawn(function()
                while Switch:GetAttribute("Toggled") and myRun == runId and ScreenGui.Parent do
                    local jobId = getJobId()
                    if not isValidJobId(jobId) or jobId == game.JobId then
                        flashStrokeError(BoxStroke)
                        stopSpam()
                        break
                    end

                    if not isLocked() then
                        joinServer(jobId) -- tự bỏ qua nếu teleport trước đó chưa có kết quả
                    end

                    -- lỗi liên tiếp thì giãn dần để khỏi bị Roblox giới hạn
                    task.wait(SPAM_JOIN_DELAY + math.min(failStreak, 5) * 0.5)
                end
            end)
        end)
    end

    CreateCopyRow(StatusServerTab, "Copy Server JobId", function() return game.JobId end, false)

    --// ---------- Rejoin ----------
    do
        local Frame = CreateInfoRow(StatusServerTab, "Rejoin Server")
        local RejoinBtn = CreateStyledButton(Frame, "Rejoin", 70)
        RejoinBtn.Activated:Connect(guarded(function(done)
            local ok = false
            if not teleportPending then
                ok = pcall(function()
                    if game.JobId == "" then
                        TeleportService:Teleport(game.PlaceId, LocalPlayer)
                    else
                        TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
                    end
                end)
                if ok then markPending() end
            end
            flashButtonFeedback(RejoinBtn, "Rejoin", ok and "Rejoining..." or "Failed", not ok)
            done()
        end))
    end

    --// ---------- Server Hop ----------
    do
        local failedJobIds = {} -- server đã thử mà bị từ chối, không chọn lại

        local function httpRequest(url)
            local fn = (syn and syn.request) or http_request or request
                or (http and http.request) or (fluxus and fluxus.request)
            if not fn then return nil, "No HTTP" end

            local ok, res = pcall(fn, { Url = url, Method = "GET" })
            if not ok or type(res) ~= "table" then return nil, "Failed" end

            local code = res.StatusCode
            if code == 429 then return nil, "Limited" end
            if type(code) == "number" and (code < 200 or code >= 300) then return nil, "Failed" end

            if type(res.Body) == "string" then return res.Body end
            return nil, "Failed"
        end

        local function isUsable(srv)
            return type(srv) == "table"
                and type(srv.id) == "string"
                and srv.id ~= game.JobId
                and not failedJobIds[srv.id]
                and type(srv.playing) == "number"
                and type(srv.maxPlayers) == "number"
                and srv.playing < srv.maxPlayers
        end

        -- sortOrder: 1 = ít người trước (Asc), 2 = đông người trước (Desc)
        -- Dừng sớm khi đã đủ `enough` ứng viên để bớt request.
        local function collectServers(sortOrder, maxPages, enough, accept)
            local list, cursor, lastErr = {}, "", nil

            for page = 1, maxPages do
                local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=%d&limit=100")
                    :format(game.PlaceId, sortOrder)
                if cursor ~= "" then url ..= "&cursor=" .. HttpService:UrlEncode(cursor) end

                local body, err = httpRequest(url)
                if not body then
                    lastErr = err
                    break
                end

                local ok, data = pcall(HttpService.JSONDecode, HttpService, body)
                if not ok or type(data) ~= "table" or type(data.data) ~= "table" then
                    lastErr = "Failed"
                    break
                end

                for _, srv in ipairs(data.data) do
                    if isUsable(srv) and accept(srv) then
                        table.insert(list, srv)
                    end
                end

                if #list >= enough then break end

                cursor = data.nextPageCursor
                if type(cursor) ~= "string" or cursor == "" then break end
                if page < maxPages then task.wait(PAGE_DELAY) end
            end

            return list, lastErr
        end

        -- xáo trộn n phần tử đầu của list
        local function shuffle(list, n)
            for i = math.min(n, #list), 2, -1 do
                local j = math.random(1, i)
                list[i], list[j] = list[j], list[i]
            end
        end

        local function pickServers(pickLeast)
            if pickLeast then
                -- Asc: server ít người nằm ở các trang đầu. Bỏ server 0 người (thường sắp đóng).
                local list, err = collectServers(1, 2, 20, function(srv)
                    return srv.playing >= 1
                end)
                table.sort(list, function(a, b) return a.playing < b.playing end)
                shuffle(list, 5) -- xáo 5 server ít người nhất để nhiều người dùng khỏi đụng nhau
                return list, err
            end

            -- Hop ngẫu nhiên: tránh server gần đầy (dễ bị GameFull)
            local list, err = collectServers(2, 5, 30, function(srv)
                return srv.playing <= math.max(0, srv.maxPlayers - 2)
            end)
            shuffle(list, #list)
            return list, err
        end

        -- Trả về true nếu đang teleport, hoặc false + lý do ngắn
        local function hopServer(pickLeast)
            local candidates, err = pickServers(pickLeast)
            if #candidates == 0 then return false, err or "No server" end

            local tried = 0
            for _, srv in ipairs(candidates) do
                if tried >= HOP_MAX_ATTEMPTS then break end
                tried += 1

                local ok, reason = joinServer(srv.id)
                if not ok then
                    if reason == "Busy" then return false, "Busy" end
                    failedJobIds[srv.id] = true
                else
                    -- chờ xem Roblox có từ chối không (server đầy / đã đóng...)
                    for _ = 1, math.ceil(HOP_WAIT_RESULT / 0.2) do
                        if not teleportPending then break end
                        task.wait(0.2)
                    end
                    if teleportPending then return true end -- vẫn đang teleport: coi như thành công
                    failedJobIds[srv.id] = true             -- bị từ chối: thử server kế tiếp
                end
            end

            return false, "Failed"
        end

        local function bindHopButton(title, pickLeast)
            local Frame = CreateInfoRow(StatusServerTab, title)
            local Btn = CreateStyledButton(Frame, "Hop", 70)
            Btn.Activated:Connect(guarded(function(done)
                Btn.Text, Btn.TextColor3 = "Finding...", Theme.SubText
                task.spawn(function()
                    local ok, result, reason = pcall(hopServer, pickLeast)
                    if ok and result then
                        flashButtonFeedback(Btn, "Hop", "Hopping...", false)
                    else
                        flashButtonFeedback(Btn, "Hop", (ok and reason) or "Failed", true)
                    end
                    done()
                end)
            end))
        end

        bindHopButton("Server Hop", false)
        bindHopButton("Server Hop With Less People", true)
    end
end
