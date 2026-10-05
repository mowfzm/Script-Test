--// ================= SCRIPT TAB (module) =================
-- This file is loaded by the main script (test.lua) and called with a ctx table
-- containing the shared UI functions/variables. Returns ScriptDialog so the main file
-- can use it when closing the UI (closeUI).

return function(ctx)
    local ScriptTab           = ctx.Tab

    local Theme               = ctx.Theme
    local ScreenGui           = ctx.ScreenGui
    local HttpService         = ctx.HttpService
    local UI_NAME             = ctx.UI_NAME
    local canFS               = ctx.canFS

    local WHITE               = ctx.WHITE
    local CENTER              = ctx.CENTER
    local ANCHOR_CENTER       = ctx.ANCHOR_CENTER
    local EASE_QUAD           = ctx.EASE_QUAD
    local DIR_IN              = ctx.DIR_IN
    local DIR_OUT             = ctx.DIR_OUT
    local BUBBLE_IN_TIME      = ctx.BUBBLE_IN_TIME
    local BUBBLE_OUT_TIME     = ctx.BUBBLE_OUT_TIME
    local FADE_IN_TIME        = ctx.FADE_IN_TIME
    local FADE_OUT_TIME       = ctx.FADE_OUT_TIME
    local CONTENT_EDGE        = ctx.CONTENT_EDGE

    local new                 = ctx.new
    local corner              = ctx.corner
    local stroke              = ctx.stroke
    local padding             = ctx.padding
    local list                = ctx.list
    local label               = ctx.label
    local tween               = ctx.tween
    local pressScale          = ctx.pressScale
    local drawIcon            = ctx.drawIcon
    local setOverlay          = ctx.setOverlay

    local FunctionScroll      = ctx.FunctionScroll
    local DeleteDialog        = ctx.DeleteDialog

    local CreateInfoRow       = ctx.CreateInfoRow
    local CreateStyledButton  = ctx.CreateStyledButton
    local flashStrokeError    = ctx.flashStrokeError
    local bindBoxFocus        = ctx.bindBoxFocus
    local isLocked            = ctx.isLocked -- replaces the main file's uiLocked variable

    --// ---- Constants ----
    local SCRIPT_FILE         = "L-scr.json"
    local BACKUP_FILE         = "L-scr.bak.json"
    local SCHEMA_VERSION      = 2
    local EXPORT_FORMAT       = "L-script-export"

    local MAX_NAME_LEN        = 60
    local MAX_SCRIPT_LEN      = 200000
    local MAX_IMPORT_ITEMS    = 200
    local MAX_IMPORT_BYTES    = 2000000
    local UNDO_SECONDS        = 6 -- 0 = delete immediately, no Undo

    local SEARCH_MIN_ITEMS    = 5
    local SEARCH_H            = 30
    local PINNED_HEIGHT       = 36
    local TAB_LIST_GAP        = 10

    --// ---- Module state ----
    local ScriptList = {}                               -- array of v2 entries (plain data only, saved to file)
    local Rows       = {}                               -- [entry.id] = { Row, entry, nameLower, refresh }
    local Running    = {}                               -- [entry.id] = { thread, startedAt, onState }
    local View       = { query = "", sort = "added" }

    -- forward declarations (assigned in the UI block below)
    local OutputPanel, StatusLabel, SearchRow, SearchBox, EmptyLabel, ScriptDialog
    local applyListView, CreateScriptRow, fitListPanel

    local function labelRef(parent, props)
        local inst = label(parent, props)
        if typeof(inst) == "Instance" then return inst end
        return parent:FindFirstChild(props.Name)
    end

    local function shorten(text, n)
        return #text > n and (text:sub(1, n) .. "...") or text
    end

    --// ---- Icons / icon buttons ----
    local function tintIcon(holder, color)
        for _, child in ipairs(holder:GetChildren()) do
            if child:IsA("Frame") then child.BackgroundColor3 = color end
        end
    end

    local function drawDots(holder, color)
        for i = 0, 2 do
            corner(new("Frame", {
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.new(0.5, 0, 0.5, (i - 1) * 6),
                Size = UDim2.fromOffset(4, 4),
                BackgroundColor3 = color,
                BorderSizePixel = 0,
            }, holder), 2)
        end
    end

    local function CreateIconButton(parent, kind, rightOffset, iconColor)
        local Btn = new("TextButton", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -rightOffset, 0.5, 0),
            Size = UDim2.fromOffset(28, 28),
            BackgroundColor3 = Theme.Header,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Text = "",
        }, parent)
        corner(Btn, 6)
        stroke(Btn)
        pressScale(Btn, 0.92)

        local Holder = new("Frame", {
            Name = "Icon",
            AnchorPoint = ANCHOR_CENTER,
            Position = CENTER,
            Size = UDim2.fromOffset(18, 18),
            BackgroundTransparency = 1,
        }, Btn)
        if kind == "more" then
            drawDots(Holder, iconColor)
        else
            drawIcon(Holder, kind, iconColor, Theme.Header)
        end

        Btn.MouseEnter:Connect(function()
            if isLocked() then return end
            tween(Btn, 0.15, { BackgroundColor3 = Theme.Border })
        end)
        Btn.MouseLeave:Connect(function()
            tween(Btn, 0.15, { BackgroundColor3 = Theme.Header })
        end)
        return Btn, Holder
    end

    --// ---- showToast: short notification, optionally with an action button ----
    local TOAST_W, MAX_TOASTS = 300, 3
    local TOAST_COLORS = {
        info    = Theme.SubText,
        success = Theme.Sakura,
        warn    = Theme.AccentPurple,
        error   = Theme.Danger,
    }
    local ToastHost
    local toastQueue, toastSeq = {}, 0
    local lastToast = { text = "", at = 0 }

    local function getToastHost()
        if ToastHost and ToastHost.Parent then return ToastHost end
        local w = math.min(TOAST_W, ScreenGui.AbsoluteSize.X - 24)
        ToastHost = new("Frame", {
            Name = "ToastHost",
            AnchorPoint = Vector2.new(0.5, 1),
            Position = UDim2.new(0.5, 0, 1, -20),
            Size = UDim2.fromOffset(w, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            ZIndex = 70,
        }, ScreenGui)
        new("UIListLayout", {
            Padding = UDim.new(0, 6),
            SortOrder = Enum.SortOrder.LayoutOrder,
            HorizontalAlignment = Enum.HorizontalAlignment.Center,
            VerticalAlignment = Enum.VerticalAlignment.Bottom,
        }, ToastHost)
        return ToastHost
    end

    local function showToast(message, kind, opts)
        opts = opts or {}
        message = tostring(message)
        local noop = { dismiss = function() end }
        if not ScreenGui.Parent then return noop end

        local now = os.clock()
        if message == lastToast.text and now - lastToast.at < 1 then return noop end
        lastToast.text, lastToast.at = message, now

        local host = getToastHost()
        if #toastQueue >= MAX_TOASTS then toastQueue[1].dismiss() end

        toastSeq = toastSeq + 1
        local color = TOAST_COLORS[kind or "info"] or TOAST_COLORS.info
        local Pill = new("CanvasGroup", {
            LayoutOrder = toastSeq,
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundColor3 = Theme.Panel,
            GroupTransparency = 1,
            ZIndex = 71,
        }, host)
        corner(Pill, 8)
        stroke(Pill, color, 1)
        padding(Pill, 12, 12, 6, 6)

        local actionW = opts.actionText and 64 or 0
        new("TextLabel", {
            Size = UDim2.new(1, -actionW, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            Text = message,
            TextWrapped = true,
            Font = Enum.Font.Gotham,
            TextSize = 13,
            TextColor3 = Theme.Text,
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = 72,
        }, Pill)

        local toast, closed = {}, false
        function toast.dismiss()
            if closed then return end
            closed = true
            local i = table.find(toastQueue, toast)
            if i then table.remove(toastQueue, i) end
            local t = tween(Pill, 0.2, { GroupTransparency = 1 }, EASE_QUAD, DIR_IN)
            t.Completed:Connect(function()
                if Pill.Parent then Pill:Destroy() end
            end)
        end

        if opts.actionText then
            local Act = new("TextButton", {
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, 0, 0.5, 0),
                Size = UDim2.fromOffset(actionW - 6, 32),
                BackgroundTransparency = 1,
                Text = opts.actionText,
                Font = Enum.Font.GothamBold,
                TextSize = 13,
                TextColor3 = Theme.AccentPink,
                ZIndex = 73,
            }, Pill)
            Act.MouseButton1Click:Connect(function()
                toast.dismiss()
                if opts.onAction then task.spawn(opts.onAction) end
            end)
        end

        toastQueue[#toastQueue + 1] = toast
        tween(Pill, 0.15, { GroupTransparency = 0 }, EASE_QUAD, DIR_OUT)
        task.delay(opts.duration or (kind == "error" and 5 or 2.5), toast.dismiss)
        return toast
    end

    --// ---- createEntry: the single source for creating v2 entries ----
    local function sanitizeName(rawName)
        local s = tostring(rawName or "")
        s = s:gsub("%c+", " ")
        s = s:gsub("%s+", " ")
        s = s:match("^%s*(.-)%s*$")
        local len = utf8.len(s)
        if not len then
            s = s:sub(1, MAX_NAME_LEN)
        elseif len > MAX_NAME_LEN then
            s = s:sub(1, utf8.offset(s, MAX_NAME_LEN + 1) - 1)
        end
        return s
    end

    local function nameTaken(name, exceptId)
        local key = name:lower()
        for _, e in ipairs(ScriptList) do
            if e.id ~= exceptId and e.name:lower() == key then return true end
        end
        return false
    end

    local function makeUniqueName(name, exceptId)
        if not nameTaken(name, exceptId) then return name end
        local n = 2
        while nameTaken(("%s (%d)"):format(name, n), exceptId) do n = n + 1 end
        return ("%s (%d)"):format(name, n)
    end

    local function idTaken(id)
        for _, e in ipairs(ScriptList) do
            if e.id == id then return true end
        end
        return false
    end

    local function createEntry(name, code, base, opts)
        base, opts = base or {}, opts or {}

        name = sanitizeName(name)
        if name == "" then return nil, "empty_name" end
        if type(code) ~= "string" or code:match("^%s*$") then return nil, "empty_script" end
        if #code > MAX_SCRIPT_LEN then return nil, "too_long" end

        local wanted = name
        if not opts.keepName then name = makeUniqueName(name, base.id) end

        local id = base.id
        if type(id) ~= "string" or id == "" or idTaken(id) then
            id = HttpService:GenerateGUID(false)
        end

        local now = os.time()
        return {
            id        = id,
            name      = name,
            script    = code,
            createdAt = tonumber(base.createdAt) or now,
            updatedAt = tonumber(base.updatedAt) or now,
            favorite  = base.favorite == true,
        }, (name ~= wanted) and "renamed" or nil
    end

    --// ---- Save / load library ----
    local STATUS = {
        saved  = { "Saved",        Theme.SubText },
        error  = { "Save failed",  Theme.Danger  },
        memory = { "Session only", Theme.SubText },
    }

    local function setSaveStatus(state)
        local s = STATUS[state]
        if StatusLabel and s then
            StatusLabel.Text, StatusLabel.TextColor3 = s[1], s[2]
        end
    end

    local function jsonValid(body)
        return (pcall(HttpService.JSONDecode, HttpService, body))
    end

    local function saveLibrary()
        if not canFS then
            setSaveStatus("memory")
            return true, "memory_only"
        end

        local okEnc, json = pcall(HttpService.JSONEncode, HttpService,
            { version = SCHEMA_VERSION, scripts = ScriptList })
        if not okEnc then
            setSaveStatus("error")
            return false, "encode: " .. tostring(json)
        end

        -- only back up when the current file is still readable
        pcall(function()
            if isfile(SCRIPT_FILE) then
                local old = readfile(SCRIPT_FILE)
                if old ~= "" and jsonValid(old) then writefile(BACKUP_FILE, old) end
            end
        end)

        local okW, errW = pcall(writefile, SCRIPT_FILE, json)
        if not okW then
            setSaveStatus("error")
            return false, tostring(errW)
        end

        local okR, back = pcall(readfile, SCRIPT_FILE)
        if not okR or back ~= json then
            setSaveStatus("error")
            return false, "verify_failed"
        end

        setSaveStatus("saved")
        return true
    end

    local function reportSaveFailure(err)
        showToast("Save failed: " .. tostring(err), "error", {
            duration = 6,
            actionText = "Retry",
            onAction = function()
                if saveLibrary() then showToast("Saved", "success", { duration = 1.5 }) end
            end,
        })
    end

    local saveQueued = false
    local function scheduleSave(delay)
        if saveQueued then return end
        saveQueued = true
        task.delay(delay or 0.4, function()
            saveQueued = false
            local ok, err = saveLibrary()
            if not ok then showToast("Auto-save failed: " .. tostring(err), "error") end
        end)
    end

    local function readJson(path)
        local okF, exists = pcall(isfile, path)
        if not okF or not exists then return nil, "missing" end
        local okR, body = pcall(readfile, path)
        if not okR then return nil, "unreadable" end
        local okD, data = pcall(HttpService.JSONDecode, HttpService, body)
        if not okD then return nil, "bad_json", body end
        return data, nil, body
    end

    local function extractItems(data)
        if type(data) ~= "table" then return nil end
        if data.version and type(data.scripts) == "table" then
            return data.scripts, tonumber(data.version) or 1
        end
        return data, 1 -- legacy format: array of { name, script }
    end

    local function loadLibrary()
        local report = { status = "ok", loaded = 0, skipped = 0 }
        if not canFS then report.status = "memory_only"; return report end

        local data, why, body = readJson(SCRIPT_FILE)
        if why == "missing" then report.status = "empty"; return report end

        if why then -- corrupted: keep the corrupted copy, then try the backup
            if body then
                report.corruptFile = ("L-scr.corrupt-%d.json"):format(os.time())
                pcall(writefile, report.corruptFile, body)
            end
            data, why, body = readJson(BACKUP_FILE)
            if why then report.status = "corrupt"; return report end
            report.status = "recovered"
        end

        local items, version = extractItems(data)
        if not items then report.status = "corrupt"; return report end

        for _, item in ipairs(items) do
            local entry = type(item) == "table"
                and createEntry(item.name, item.script, item, { keepName = true })
            if entry then
                ScriptList[#ScriptList + 1] = entry
                report.loaded = report.loaded + 1
            else
                report.skipped = report.skipped + 1
            end
        end

        local needSave = report.status == "recovered"
        if version < SCHEMA_VERSION then
            report.migrated = version
            needSave = true
            pcall(writefile, ("L-scr.v%d.bak.json"):format(version), body)
        end
        if needSave then saveLibrary() end
        return report
    end

    local function announceLoad(report)
        if report.status == "recovered" then
            showToast("Library was damaged - restored from backup", "warn", { duration = 5 })
        elseif report.status == "corrupt" then
            local kept = report.corruptFile and (" Copy kept: " .. report.corruptFile) or ""
            showToast("Library file is damaged." .. kept, "error", { duration = 6 })
        elseif report.status == "memory_only" then
            setSaveStatus("memory")
        end
        if report.status == "ok" or report.status == "empty" or report.status == "recovered" then
            setSaveStatus("saved")
        end
        if report.skipped > 0 then
            showToast(("%d invalid script(s) were skipped"):format(report.skipped), "warn")
        end
    end

    --// ---- compileScript: trial compile, does not run ----
    local compileCache = setmetatable({}, { __mode = "k" }) -- [entry] = { src, fn }

    local function compileScript(source, chunkName)
        if typeof(loadstring) ~= "function" then
            return false, nil, { kind = "unavailable", message = "loadstring is not available" }
        end
        local safe = ((chunkName or "UserScript"):gsub("[^%w_]", "_"))
        local ok, fn, err = pcall(loadstring, source, "=" .. safe)
        if not ok then
            return false, nil, { kind = "compile", message = tostring(fn) }
        end
        if not fn then
            local text = tostring(err)
            local line, msg = text:match(":(%d+):%s*(.*)$")
            return false, nil, {
                kind = "compile", line = tonumber(line), message = msg or text,
            }
        end
        return true, fn
    end

    local function getCompiled(entry)
        local c = compileCache[entry]
        if c and c.src == entry.script then return true, c.fn end
        local ok, fn, info = compileScript(entry.script, entry.name)
        if ok then compileCache[entry] = { src = entry.script, fn = fn } end
        return ok, fn, info
    end

    local function describe(info)
        return info.line and ("Line %d: %s"):format(info.line, info.message) or info.message
    end

    local pendingSaveAnyway -- { code, expires }
    local function validateForSave(code)
        local ok, _, info = compileScript(code, "Preview")
        if ok or info.kind == "unavailable" then return true end

        local now = os.clock()
        local p = pendingSaveAnyway
        if p and p.code == code and now < p.expires then
            pendingSaveAnyway = nil
            return true -- second Save within 5 seconds = Save anyway
        end
        pendingSaveAnyway = { code = code, expires = now + 5 }
        return false, describe(info)
    end

    --// ---- runScript / stopScript ----
    local function logOut(level, name, text)
        if OutputPanel then OutputPanel.append(level, name, text) end
    end

    local function runScript(entry, onState)
        onState = onState or function() end
        if Running[entry.id] then return false, "already_running" end

        local ok, fn, info = getCompiled(entry)
        if not ok then
            logOut("error", entry.name, "Compile error - " .. describe(info))
            onState("error")
            return false, "compile"
        end

        local state = { startedAt = os.clock(), onState = onState }
        Running[entry.id] = state
        onState("running")
        task.delay(0.4, function()
            if Running[entry.id] == state then onState("running_long") end
        end)

        state.thread = task.spawn(function()
            local okRun, err = xpcall(fn, function(e)
                return debug.traceback(tostring(e), 2)
            end)
            if Running[entry.id] ~= state then return end -- already Stopped
            Running[entry.id] = nil
            if okRun then
                logOut("ok", entry.name,
                    ("Finished in %.2fs"):format(os.clock() - state.startedAt))
                onState("ok")
            else
                logOut("error", entry.name, "Runtime error - " .. tostring(err))
                onState("error")
            end
        end)
        return true
    end

    local function stopScript(entry)
        local state = Running[entry.id]
        if not state then return false end
        Running[entry.id] = nil
        if state.thread and task.cancel then pcall(task.cancel, state.thread) end
        logOut("info", entry.name, "Stopped (main thread only)")
        state.onState("idle")
        return true
    end

    --// ---- Export / import library ----
    local function safeFileName(name)
        local s = (name:gsub("[^%w_%-]+", "_"))
        if s:match("^_*$") then s = "script" end
        return s:sub(1, 30)
    end

    local function exportLibrary(entry)
        local items = entry and { entry } or ScriptList
        if #items == 0 then
            showToast("Nothing to export", "warn")
            return false
        end

        local payload = {
            format = EXPORT_FORMAT, version = 1, exportedAt = os.time(), scripts = {},
        }
        for _, e in ipairs(items) do
            payload.scripts[#payload.scripts + 1] = { name = e.name, script = e.script }
        end
        local okEnc, json = pcall(HttpService.JSONEncode, HttpService, payload)
        if not okEnc then
            showToast("Export failed", "error")
            return false
        end

        local fileName
        if canFS then
            fileName = ("L-export-%s-%s.json"):format(
                entry and safeFileName(entry.name) or "all", os.date("%Y%m%d-%H%M%S"))
            if not pcall(writefile, fileName, json) then fileName = nil end
        end
        local clip = setclipboard or toclipboard
        local copied = typeof(clip) == "function" and pcall(clip, json)

        if fileName then
            local tail = copied and " (copied)" or ""
            showToast("Exported to " .. fileName .. tail, "success", { duration = 4 })
        elseif copied then
            showToast("Export copied to clipboard", "success")
        else
            showToast("Export needs file access or clipboard", "error")
            return false
        end
        return true, fileName
    end

    local function importLibrary(text)
        text = tostring(text or ""):match("^%s*(.-)%s*$")
        if text == "" then return nil, "Nothing to import" end

        -- allow typing a file name instead of pasting the content
        if canFS and #text < 200 and not text:find("[{%[\r\n]") then
            local okF, exists = pcall(isfile, text)
            if okF and exists then
                local okR, body = pcall(readfile, text)
                if okR then text = body end
            end
        end
        if #text > MAX_IMPORT_BYTES then return nil, "Input is too large" end

        local okDec, data = pcall(HttpService.JSONDecode, HttpService, text)
        if not okDec or type(data) ~= "table"
            or data.format ~= EXPORT_FORMAT or type(data.scripts) ~= "table" then
            return nil, "Not a valid exported script file"
        end

        local added, skipped = {}, 0
        for _, item in ipairs(data.scripts) do
            local entry = #added < MAX_IMPORT_ITEMS and type(item) == "table"
                and createEntry(item.name, item.script)
            if entry then
                ScriptList[#ScriptList + 1] = entry
                added[#added + 1] = entry
            else
                skipped = skipped + 1
            end
        end
        if #added == 0 then return nil, "No valid scripts found" end

        local ok, err = saveLibrary()
        if not ok then
            for _ = 1, #added do table.remove(ScriptList) end -- rollback
            return nil, "Save failed: " .. tostring(err)
        end
        for _, entry in ipairs(added) do CreateScriptRow(entry) end
        applyListView()
        return { added = #added, skipped = skipped }
    end

    --// ---- Output panel: run / error history, collapsible ----
    local function createOutputPanel(onResize)
        local HEADER_H, BODY_H, MAX_LINES = 28, 110, 50
        local LEVEL_COLORS = { ok = Theme.Sakura, error = Theme.Danger, info = Theme.SubText }
        local expanded, unread, seq = false, 0, 0
        local plain, labels = {}, {}

        local Panel = new("Frame", {
            Name = "OutputPanel",
            LayoutOrder = 4,
            Size = UDim2.new(1, 0, 0, HEADER_H),
            BackgroundColor3 = Theme.PanelAlt,
            BorderSizePixel = 0,
            ClipsDescendants = true,
        }, ScriptTab)
        corner(Panel, 8)
        stroke(Panel)

        local Header = new("TextButton", {
            Size = UDim2.new(1, -110, 0, HEADER_H),
            BackgroundTransparency = 1,
            AutoButtonColor = false,
            Text = "Output",
            Font = Enum.Font.GothamBold,
            TextSize = 13,
            TextColor3 = Theme.SubText,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, Panel)
        padding(Header, 10, 0)

        local function miniButton(text, rightOffset)
            return new("TextButton", {
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, -rightOffset, 0, 2),
                Size = UDim2.fromOffset(48, HEADER_H - 4),
                BackgroundTransparency = 1,
                Text = text,
                Font = Enum.Font.Gotham,
                TextSize = 12,
                TextColor3 = Theme.AccentPink,
            }, Panel)
        end
        local CopyBtn, ClearBtn = miniButton("Copy", 56), miniButton("Clear", 6)

        local Body = new("ScrollingFrame", {
            Position = UDim2.fromOffset(0, HEADER_H),
            Size = UDim2.new(1, 0, 1, -HEADER_H),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ScrollBarThickness = 4,
            ScrollBarImageColor3 = Theme.AccentPink,
            CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
        }, Panel)
        new("UIListLayout", {
            Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder,
        }, Body)
        padding(Body, 8, 8, 4, 4)

        local function refreshHeader()
            local bad = unread > 0 and not expanded
            Header.Text = bad and ("Output  -  %d new error(s)"):format(unread) or "Output"
            Header.TextColor3 = bad and Theme.Danger or Theme.SubText
        end

        local function append(level, name, text)
            seq = seq + 1
            local line = ("[%s] %s: %s"):format(os.date("%H:%M:%S"), name, text)
            plain[#plain + 1] = line
            labels[#labels + 1] = new("TextLabel", {
                LayoutOrder = seq,
                Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundTransparency = 1,
                Text = line,
                TextWrapped = true,
                TextSelectable = true,
                Font = Enum.Font.Code,
                TextSize = 12,
                TextColor3 = LEVEL_COLORS[level] or Theme.Text,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextYAlignment = Enum.TextYAlignment.Top,
            }, Body)
            if #labels > MAX_LINES then
                table.remove(plain, 1)
                table.remove(labels, 1):Destroy()
            end
            if level == "error" and not expanded then unread = unread + 1 end
            refreshHeader()
            task.defer(function()
                Body.CanvasPosition = Vector2.new(0, Body.AbsoluteCanvasSize.Y)
            end)
        end

        local function clear()
            for _, l in ipairs(labels) do l:Destroy() end
            table.clear(labels)
            table.clear(plain)
            unread = 0
            refreshHeader()
        end

        local function toggle()
            expanded = not expanded
            if expanded then unread = 0 end
            refreshHeader()
            tween(Panel, 0.15, {
                Size = UDim2.new(1, 0, 0, expanded and (HEADER_H + BODY_H) or HEADER_H),
            }, EASE_QUAD, DIR_OUT)
        end

        local function copyAll()
            if #plain == 0 then return end
            local clip = setclipboard or toclipboard
            if typeof(clip) == "function" and pcall(clip, table.concat(plain, "\n")) then
                showToast("Output copied", "success", { duration = 1.5 })
            else
                showToast("Clipboard is not available", "warn")
            end
        end

        Header.MouseButton1Click:Connect(toggle)
        CopyBtn.MouseButton1Click:Connect(copyAll)
        ClearBtn.MouseButton1Click:Connect(clear)
        if onResize then Panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(onResize) end

        return {
            Frame = Panel, append = append, clear = clear,
            toggle = toggle, copyAll = copyAll,
        }
    end

    --// ---- NotBoxA: Add / Edit / Import ----
    local function createScriptDialog()
        local ACCENT = Theme.AccentPink
        local TEXT = {
            addTitle = "ADD SCRIPT", editTitle = "EDIT SCRIPT", importTitle = "IMPORT SCRIPTS",
            save = "Save", saveChanges = "Save Changes", import = "Import",
            cancel = "Cancel", discard = "Discard?",
            namePlaceholder = "Enter your name script here",
            codePlaceholder = "Enter your script here",
            importPlaceholder = "Paste exported JSON or a file name",
        }

        local Box = new("CanvasGroup", {
            Name = "NotBoxA",
            Visible = false,
            AnchorPoint = ANCHOR_CENTER,
            Position = CENTER,
            Size = UDim2.new(),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            GroupTransparency = 1,
            ZIndex = 51,
        }, ScreenGui)
        corner(Box, 12)

        local Bg = new("Frame", {
            Size = UDim2.fromScale(1, 1),
            BackgroundColor3 = WHITE,
            BorderSizePixel = 0,
            ZIndex = 51,
        }, Box)
        corner(Bg, 12)
        new("UIGradient", { Color = ColorSequence.new(Theme.PanelAlt, Theme.Panel), Rotation = 90 }, Bg)

        new("UIGradient", {
            Color = ColorSequence.new(Theme.AccentPurple, ACCENT),
            Rotation = 45,
        }, stroke(Box, WHITE, 1.5))

        new("UIGradient", {
            Color = ColorSequence.new(Theme.AccentPurple, ACCENT),
        }, new("Frame", {
            Size = UDim2.new(1, 0, 0, 3),
            BackgroundColor3 = WHITE,
            BorderSizePixel = 0,
            ZIndex = 52,
        }, Box))

        local TitleLabel = labelRef(Box, {
            Name = "DialogTitle",
            Size = UDim2.new(1, -32, 0, 20),
            Position = UDim2.fromOffset(16, 14),
            Text = TEXT.addTitle,
            TextSize = 13,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextColor3 = Theme.Sakura,
            ZIndex = 52,
        })

        local function fieldLabel(name, text, y)
            return labelRef(Box, {
                Name = name,
                Size = UDim2.new(1, -32, 0, 16),
                Position = UDim2.fromOffset(16, y),
                Text = text,
                TextSize = 13,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextColor3 = Theme.SubText,
                ZIndex = 52,
            })
        end

        -- TextBoxA1: Script Name
        local NameLabel = fieldLabel("NameLabel", "Script Name", 42)
        local NameBox = new("TextBox", {
            Position = UDim2.fromOffset(16, 62),
            Size = UDim2.new(1, -32, 0, 32),
            BackgroundColor3 = Theme.PanelAlt,
            BorderSizePixel = 0,
            Text = "",
            PlaceholderText = TEXT.namePlaceholder,
            PlaceholderColor3 = Theme.SubText,
            ClearTextOnFocus = false,
            Font = Enum.Font.Gotham,
            TextSize = 14,
            TextColor3 = Theme.Text,
            TextXAlignment = Enum.TextXAlignment.Left,
            ClipsDescendants = true,
            ZIndex = 52,
        }, Box)
        corner(NameBox, 6)
        padding(NameBox, 8, 8)
        local NameStroke = stroke(NameBox)
        bindBoxFocus(NameBox, NameStroke)

        -- TextBoxA2: Script (two-way scrolling frame, no line wrapping to preserve indentation)
        fieldLabel("CodeLabel", "Script", 102)
        local CodeHolder = new("ScrollingFrame", {
            Position = UDim2.fromOffset(16, 122),
            Size = UDim2.new(1, -32, 1, -194), -- scales with the dialog height
            BackgroundColor3 = Theme.PanelAlt,
            BorderSizePixel = 0,
            ScrollBarThickness = 4,
            ScrollBarImageColor3 = Theme.AccentPink,
            ScrollingDirection = Enum.ScrollingDirection.XY,
            CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.XY,
            ZIndex = 52,
        }, Box)
        corner(CodeHolder, 6)
        local CodeStroke = stroke(CodeHolder)

        local CodeBox = new("TextBox", {
            Size = UDim2.fromOffset(240, 96), -- minimum size, adjusted again in show()
            AutomaticSize = Enum.AutomaticSize.XY,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Text = "",
            PlaceholderText = TEXT.codePlaceholder,
            PlaceholderColor3 = Theme.SubText,
            ClearTextOnFocus = false,
            MultiLine = true,
            TextWrapped = false,
            Font = Enum.Font.Code,
            TextSize = 13,
            TextColor3 = Theme.Text,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
            ZIndex = 53,
        }, CodeHolder)
        padding(CodeBox, 8, 8, 6, 6)
        bindBoxFocus(CodeBox, CodeStroke)

        -- the scrolling frame doesn't follow the cursor on its own: drag CanvasPosition manually so the cursor always stays in view
        local function followCaret()
            pcall(function()
                local cur = CodeBox.CursorPosition
                if cur < 1 then return end
                local TextService = game:GetService("TextService")
                local huge = Vector2.new(1e6, 1e6)
                local before = CodeBox.Text:sub(1, cur - 1)
                local lastLine = before:match("([^\n]*)$")
                local _, breaks = before:gsub("\n", "")
                local lineH = TextService:GetTextSize("A", CodeBox.TextSize, CodeBox.Font, huge).Y
                local w = TextService:GetTextSize(lastLine, CodeBox.TextSize, CodeBox.Font, huge).X
                local cx, cy = 8 + w, 6 + breaks * lineH
                local win, pos = CodeHolder.AbsoluteWindowSize, CodeHolder.CanvasPosition
                local nx, ny = pos.X, pos.Y
                if cx > pos.X + win.X - 16 then
                    nx = cx - win.X + 32
                elseif cx < pos.X then
                    nx = math.max(0, cx - 32)
                end
                if cy + lineH > pos.Y + win.Y - 6 then
                    ny = cy + lineH - win.Y + 12
                elseif cy < pos.Y then
                    ny = math.max(0, cy - 6)
                end
                if nx ~= pos.X or ny ~= pos.Y then
                    CodeHolder.CanvasPosition = Vector2.new(nx, ny)
                end
            end)
        end
        CodeBox:GetPropertyChangedSignal("CursorPosition"):Connect(followCaret)

        new("Frame", {
            Size = UDim2.new(1, -32, 0, 1),
            Position = UDim2.new(0, 16, 1, -60),
            BackgroundColor3 = Theme.Border,
            BackgroundTransparency = 0.5,
            BorderSizePixel = 0,
            ZIndex = 52,
        }, Box)

        local function option(text, pos, bg, textColor, outlined)
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
                    tween(S, 0.15, { Color = Theme.AccentPurple })
                else
                    tween(Btn, 0.15, { BackgroundColor3 = bg:Lerp(WHITE, 0.15) })
                end
            end)
            Btn.MouseLeave:Connect(function()
                if outlined then
                    tween(Btn, 0.15, { BackgroundColor3 = bg, TextColor3 = textColor })
                    tween(S, 0.15, { Color = Theme.Border })
                else
                    tween(Btn, 0.15, { BackgroundColor3 = bg })
                end
            end)
            return Btn
        end

        local Save   = option(TEXT.save, UDim2.new(0, 16, 1, -46), ACCENT, Theme.Background)
        local Cancel = option(TEXT.cancel, UDim2.new(1, -16, 1, -46), Theme.PanelAlt, Theme.Text, true)
        Cancel.AnchorPoint = Vector2.new(1, 0)

        --// Dialog state
        local mode, current = "add", nil
        local baseline = { name = "", code = "" }
        local hideToken, discardUntil = 0, 0

        local function fitSize()
            local vp = ScreenGui.AbsoluteSize
            return UDim2.fromOffset(math.min(330, vp.X - 24), math.min(290, vp.Y - 24))
        end

        local function isDirty()
            return NameBox.Text ~= baseline.name or CodeBox.Text ~= baseline.code
        end

        local function show(newMode, entry)
            mode, current = newMode or "add", entry
            baseline = { name = entry and entry.name or "", code = entry and entry.script or "" }
            NameBox.Text, CodeBox.Text = baseline.name, baseline.code
            CodeHolder.CanvasPosition = Vector2.new(0, 0)

            local isImport = mode == "import"
            NameBox.Visible = not isImport
            if NameLabel then NameLabel.Visible = not isImport end
            CodeBox.PlaceholderText = isImport and TEXT.importPlaceholder or TEXT.codePlaceholder
            if TitleLabel then
                TitleLabel.Text = (mode == "edit" and TEXT.editTitle)
                    or (isImport and TEXT.importTitle) or TEXT.addTitle
            end
            Save.Text = (mode == "edit" and TEXT.saveChanges)
                or (isImport and TEXT.import) or TEXT.save
            Cancel.Text, discardUntil = TEXT.cancel, 0

            local target = fitSize()
            CodeBox.Size = UDim2.fromOffset(target.X.Offset - 34, 96)

            hideToken = hideToken + 1
            setOverlay(true)
            Box.Visible = true
            Box.GroupTransparency = 1
            Box.Size = UDim2.new()
            tween(Box, BUBBLE_IN_TIME, { Size = target }, EASE_QUAD, DIR_OUT)
            tween(Box, FADE_IN_TIME, { GroupTransparency = 0 }, EASE_QUAD, DIR_OUT)
        end

        local function hide()
            hideToken = hideToken + 1
            local token = hideToken
            NameBox:ReleaseFocus()
            CodeBox:ReleaseFocus()
            local sizeTween = tween(Box, BUBBLE_OUT_TIME, { Size = UDim2.new() }, EASE_QUAD, DIR_IN)
            tween(Box, FADE_OUT_TIME, { GroupTransparency = 1 }, EASE_QUAD, DIR_IN)
            sizeTween.Completed:Connect(function(state)
                if state ~= Enum.PlaybackState.Completed or token ~= hideToken then return end
                Box.Visible = false
                current = nil
                setOverlay(false) -- only turn off the overlay once the animation has finished
            end)
        end

        Cancel.MouseButton1Click:Connect(function()
            if not isDirty() or os.clock() < discardUntil then
                hide()
                return
            end
            discardUntil = os.clock() + 3
            Cancel.Text = TEXT.discard
            task.delay(3, function()
                if os.clock() >= discardUntil then Cancel.Text = TEXT.cancel end
            end)
        end)

        NameBox.FocusLost:Connect(function(enterPressed)
            if enterPressed then CodeBox:CaptureFocus() end
        end)

        return {
            Box = Box, show = show, hide = hide, isDirty = isDirty,
            getMode = function() return mode end,
            getEntry = function() return current end,
            Save = Save, Cancel = Cancel,
            NameBox = NameBox, NameStroke = NameStroke,
            CodeBox = CodeBox, CodeStroke = CodeStroke,
        }
    end

    ScriptDialog = createScriptDialog()

    --// ---- Entry actions: Add / Edit / Import / Delete / Duplicate / Pin ----
    local function openEditDialog(entry)
        if isLocked() then return end
        ScriptDialog.show("edit", entry)
    end

    local function commitEdit(entry, rawName, code)
        local name = makeUniqueName(rawName, entry.id)
        if name == entry.name and code == entry.script then
            ScriptDialog.hide()
            return
        end
        local before = { entry.name, entry.script, entry.updatedAt }
        entry.name, entry.script, entry.updatedAt = name, code, os.time()

        local ok, err = saveLibrary()
        if not ok then
            entry.name, entry.script, entry.updatedAt = before[1], before[2], before[3]
            showToast("Save failed: " .. tostring(err), "error")
            return -- keep the dialog open so the text being typed isn't lost
        end

        Rows[entry.id].refresh()
        applyListView()
        ScriptDialog.hide()
        local msg = name ~= rawName and ('Saved as "%s"'):format(name) or "Saved changes"
        showToast(msg, "success")
    end

    local function commitAdd(name, code)
        local entry, flag = createEntry(name, code)
        if not entry then
            showToast(flag == "too_long" and "Script is too large" or "Invalid script", "error")
            return
        end
        ScriptList[#ScriptList + 1] = entry
        local ok, err = saveLibrary()
        if not ok then
            table.remove(ScriptList) -- rollback
            showToast("Save failed: " .. tostring(err), "error")
            return
        end
        CreateScriptRow(entry)
        applyListView()
        ScriptDialog.hide()
        local msg = flag == "renamed" and ('Saved as "%s"'):format(entry.name) or "Script saved"
        showToast(msg, "success")
    end

    local function commitImport(text)
        local result, err = importLibrary(text)
        if not result then
            flashStrokeError(ScriptDialog.CodeStroke)
            showToast(err, "error")
            return
        end
        ScriptDialog.hide()
        local extra = result.skipped > 0 and (", skipped " .. result.skipped) or ""
        showToast(("Imported %d script(s)%s. Review before running."):format(result.added, extra),
            "success", { duration = 4 })
    end

    -- NotBoxDe: action awaiting confirmation
    local pendingConfirm

    DeleteDialog.Yes.MouseButton1Click:Connect(function()
        local action = pendingConfirm
        pendingConfirm = nil
        DeleteDialog.hide()
        if action then action() end
    end)

    local function askConfirm(message, onYes)
        pendingConfirm = onYes
        DeleteDialog.Message.Text = message
        DeleteDialog.show()
    end

    local function deleteScript(entry)
        local idx = table.find(ScriptList, entry)
        if not idx then return false end

        table.remove(ScriptList, idx)
        local ok, err = saveLibrary()
        if not ok then
            table.insert(ScriptList, idx, entry) -- rollback
            showToast("Could not delete: " .. tostring(err), "error")
            return false
        end

        local rec = Rows[entry.id]
        if rec then rec.Row.Visible = false end
        applyListView()

        local undone = false
        local function finalize()
            if undone then return end
            if rec and rec.Row.Parent then rec.Row:Destroy() end
            Rows[entry.id] = nil
        end
        if UNDO_SECONDS <= 0 then finalize(); return true end

        showToast(('Deleted "%s"'):format(shorten(entry.name, 24)), "info", {
            duration = UNDO_SECONDS,
            actionText = "Undo",
            onAction = function()
                table.insert(ScriptList, math.min(idx, #ScriptList + 1), entry)
                local okU, errU = saveLibrary()
                if not okU then
                    table.remove(ScriptList, table.find(ScriptList, entry))
                    showToast("Could not restore: " .. tostring(errU), "error")
                    return
                end
                undone = true
                if rec then rec.Row.Visible = true end
                applyListView()
            end,
        })
        task.delay(UNDO_SECONDS + 0.3, finalize)
        return true
    end

    local function duplicateScript(entry)
        local idx = table.find(ScriptList, entry)
        if not idx then return nil end

        local copy = createEntry(entry.name .. " (copy)", entry.script)
        if not copy then
            showToast("Could not duplicate this script", "error")
            return nil
        end

        table.insert(ScriptList, idx + 1, copy)
        local ok, err = saveLibrary()
        if not ok then
            table.remove(ScriptList, idx + 1) -- rollback
            showToast("Save failed: " .. tostring(err), "error")
            return nil
        end

        CreateScriptRow(copy)
        applyListView()
        showToast(('Duplicated as "%s"'):format(shorten(copy.name, 24)), "success", {
            duration = 4,
            actionText = "Rename",
            onAction = function() openEditDialog(copy) end,
        })
        return copy
    end

    local function toggleFavorite(entry)
        entry.favorite = not entry.favorite
        local rec = Rows[entry.id]
        if rec then rec.refresh() end
        applyListView()
        scheduleSave()
        showToast(entry.favorite and "Pinned to top" or "Unpinned", "info", { duration = 1.5 })
        return entry.favorite
    end

    --// ---- Shared floating menu (row + header) ----
    local MenuCatcher

    local function closeContextMenu()
        if MenuCatcher then
            MenuCatcher:Destroy()
            MenuCatcher = nil
        end
    end

    local function openContextMenu(anchor, items)
        closeContextMenu()
        local ITEM_H, MENU_W, PAD = 34, 156, 4
        local origin, screen = ScreenGui.AbsolutePosition, ScreenGui.AbsoluteSize
        local h = #items * ITEM_H + PAD * 2

        MenuCatcher = new("TextButton", {
            Name = "MenuCatcher",
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Text = "",
            AutoButtonColor = false,
            ZIndex = 60,
        }, ScreenGui)
        MenuCatcher.MouseButton1Click:Connect(closeContextMenu)

        local ax = anchor.AbsolutePosition.X - origin.X + anchor.AbsoluteSize.X
        local ay = anchor.AbsolutePosition.Y - origin.Y
        local x = math.max(8, math.min(ax - MENU_W, screen.X - MENU_W - 8))
        local y = ay + anchor.AbsoluteSize.Y + 4
        if y + h > screen.Y - 8 then y = ay - h - 4 end
        y = math.max(8, y)

        local Menu = new("CanvasGroup", {
            Position = UDim2.fromOffset(x, y),
            Size = UDim2.fromOffset(MENU_W, h),
            BackgroundColor3 = Theme.Panel,
            GroupTransparency = 1,
            ZIndex = 61,
        }, MenuCatcher)
        corner(Menu, 8)
        stroke(Menu, Theme.Border, 1)
        padding(Menu, PAD, PAD, PAD, PAD)
        new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, Menu)

        for i, item in ipairs(items) do
            local Btn = new("TextButton", {
                LayoutOrder = i,
                Size = UDim2.new(1, 0, 0, ITEM_H),
                BackgroundColor3 = Theme.Border,
                BackgroundTransparency = 1,
                AutoButtonColor = false,
                Text = item.text,
                Font = Enum.Font.Gotham,
                TextSize = 14,
                TextColor3 = item.color or Theme.Text,
                TextXAlignment = Enum.TextXAlignment.Left,
                ZIndex = 62,
            }, Menu)
            corner(Btn, 6)
            padding(Btn, 10, 10)
            Btn.MouseEnter:Connect(function() tween(Btn, 0.1, { BackgroundTransparency = 0.7 }) end)
            Btn.MouseLeave:Connect(function() tween(Btn, 0.1, { BackgroundTransparency = 1 }) end)
            Btn.MouseButton1Click:Connect(function()
                closeContextMenu()
                if not isLocked() then item.run() end
            end)
        end
        tween(Menu, 0.12, { GroupTransparency = 0 }, EASE_QUAD, DIR_OUT)
    end

    local function buildRowItems(entry)
        return {
            { text = "Edit",      run = function() openEditDialog(entry) end },
            { text = "Duplicate", run = function() duplicateScript(entry) end },
            { text = entry.favorite and "Unpin from top" or "Pin to top",
              run = function() toggleFavorite(entry) end },
            { text = "Export",    run = function() exportLibrary(entry) end },
            { text = "Delete", color = Theme.Danger, run = function()
                askConfirm(('Do you want to delete "%s"?'):format(shorten(entry.name, 30)),
                    function() deleteScript(entry) end)
            end },
        }
    end

    local function buildLibraryItems()
        return {
            { text = "Export all", run = function() exportLibrary() end },
            { text = "Import",     run = function() ScriptDialog.show("import") end },
        }
    end

    do
        -- Function panel 1: pinned at the top, no frame / no border
        local Pinned = new("Frame", {
            Name = "FunctionPanel1",
            LayoutOrder = 1,
            Size = UDim2.new(1, 0, 0, PINNED_HEIGHT),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
        }, ScriptTab)
        padding(Pinned, 4, 0)

        label(Pinned, {
            Size = UDim2.new(1, -190, 1, 0),
            Text = "Other Script",
            TextSize = 15,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            TextColor3 = Theme.Text,
        })
        StatusLabel = labelRef(Pinned, {
            Name = "SaveStatus",
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -114, 0.5, 0),
            Size = UDim2.fromOffset(72, 16),
            Text = "",
            TextSize = 11,
            TextXAlignment = Enum.TextXAlignment.Right,
            TextColor3 = Theme.SubText,
        })
        local LibMoreBtn = CreateIconButton(Pinned, "more", 78, Theme.SubText)
        local AddBtn = CreateStyledButton(Pinned, "+ Add", 70) -- ButtonA

        -- Search + sort bar (only shown when there are at least SEARCH_MIN_ITEMS scripts)
        local SORT_MODES  = { "added", "name", "edited" }
        local SORT_LABELS = { added = "Sort: Added", name = "Sort: A-Z", edited = "Sort: Edited" }

        SearchRow = new("Frame", {
            Name = "SearchRow",
            LayoutOrder = 2,
            Visible = false,
            Size = UDim2.new(1, 0, 0, SEARCH_H),
            BackgroundTransparency = 1,
        }, ScriptTab)

        SearchBox = new("TextBox", {
            Size = UDim2.new(1, -94, 1, 0),
            BackgroundColor3 = Theme.PanelAlt,
            BorderSizePixel = 0,
            Text = "",
            PlaceholderText = "Search scripts",
            PlaceholderColor3 = Theme.SubText,
            ClearTextOnFocus = false,
            ClipsDescendants = true,
            Font = Enum.Font.Gotham,
            TextSize = 13,
            TextColor3 = Theme.Text,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, SearchRow)
        corner(SearchBox, 6)
        padding(SearchBox, 8, 28)
        bindBoxFocus(SearchBox, stroke(SearchBox))

        local ClearBtn = new("TextButton", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -100, 0.5, 0),
            Size = UDim2.fromOffset(24, 24),
            BackgroundTransparency = 1,
            Text = "x",
            Font = Enum.Font.GothamBold,
            TextSize = 14,
            TextColor3 = Theme.SubText,
            Visible = false,
            ZIndex = 2,
        }, SearchRow)
        ClearBtn.MouseButton1Click:Connect(function() SearchBox.Text = "" end)

        local SortBtn = new("TextButton", {
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, 0, 0, 0),
            Size = UDim2.fromOffset(88, SEARCH_H),
            BackgroundTransparency = 1,
            Text = SORT_LABELS.added,
            Font = Enum.Font.Gotham,
            TextSize = 12,
            TextColor3 = Theme.AccentPink,
        }, SearchRow)

        -- Function panel 2: function list built from NotBoxA (its own scrolling frame; "Other Script" above stays fixed)
        local ListPanel = new("ScrollingFrame", {
            Name = "FunctionPanel2",
            LayoutOrder = 3,
            Size = UDim2.new(1, 0, 0, 100),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ScrollBarThickness = 4,
            ScrollBarImageColor3 = Theme.AccentPink,
            ScrollingDirection = Enum.ScrollingDirection.Y,
            CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
        }, ScriptTab)
        list(ListPanel, 10)
        padding(ListPanel, 2, 8, 2, 2) -- leave room for the row's UIStroke border (ScrollingFrame clips any border that sticks out) + the scrollbar

        EmptyLabel = new("TextLabel", {
            Name = "EmptyHint",
            LayoutOrder = -1,
            Size = UDim2.new(1, 0, 0, 40),
            BackgroundTransparency = 1,
            Text = "",
            TextWrapped = true,
            Font = Enum.Font.Gotham,
            TextSize = 13,
            TextColor3 = Theme.SubText,
            Visible = false,
        }, ListPanel)

        -- List frame height = what remains of FunctionScroll after subtracting the blocks above/below -> the Script tab doesn't scroll on the outside
        fitListPanel = function()
            local used = CONTENT_EDGE * 2 + PINNED_HEIGHT + TAB_LIST_GAP + 2
            if SearchRow.Visible then used = used + SEARCH_H + TAB_LIST_GAP end
            if OutputPanel then used = used + OutputPanel.Frame.AbsoluteSize.Y + TAB_LIST_GAP end
            ListPanel.Size = UDim2.new(1, 0, 0, math.max(80, FunctionScroll.AbsoluteSize.Y - used))
        end
        FunctionScroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitListPanel)

        local function orderedEntries()
            local arr = table.clone(ScriptList)
            if View.sort == "name" then
                table.sort(arr, function(a, b)
                    local x, y = a.name:lower(), b.name:lower()
                    if x ~= y then return x < y end
                    return a.id < b.id
                end)
            elseif View.sort == "edited" then
                table.sort(arr, function(a, b)
                    if a.updatedAt ~= b.updatedAt then return a.updatedAt > b.updatedAt end
                    return a.id < b.id
                end)
            end
            return arr
        end

        applyListView = function()
            local q = View.query:lower()
            local shown = 0
            for i, entry in ipairs(orderedEntries()) do
                local rec = Rows[entry.id]
                if rec then
                    local match = q == "" or rec.nameLower:find(q, 1, true) ~= nil
                    rec.Row.Visible = match
                    rec.Row.LayoutOrder = (entry.favorite and 0 or 100000) + i
                    if match then shown = shown + 1 end
                end
            end

            EmptyLabel.Visible = shown == 0
            EmptyLabel.Text = #ScriptList == 0
                and 'No scripts yet. Tap "+ Add" to create one.'
                or ('No scripts match "%s"'):format(View.query)

            local showSearch = #ScriptList >= SEARCH_MIN_ITEMS
            if SearchRow.Visible ~= showSearch then
                SearchRow.Visible = showSearch
                if not showSearch then
                    View.query = ""
                    SearchBox.Text = ""
                end
                fitListPanel()
            end
        end

        SortBtn.MouseButton1Click:Connect(function()
            local i = table.find(SORT_MODES, View.sort) or 1
            View.sort = SORT_MODES[i % #SORT_MODES + 1]
            SortBtn.Text = SORT_LABELS[View.sort]
            applyListView()
        end)

        local searchToken = 0
        SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
            ClearBtn.Visible = SearchBox.Text ~= ""
            searchToken = searchToken + 1
            local token = searchToken
            task.delay(0.15, function()
                if token ~= searchToken then return end
                View.query = SearchBox.Text:match("^%s*(.-)%s*$")
                applyListView()
            end)
        end)
        SearchBox.FocusLost:Connect(function(_, input)
            if input and input.KeyCode == Enum.KeyCode.Escape then SearchBox.Text = "" end
        end)

        CreateScriptRow = function(entry)
            local Row, Left = CreateInfoRow(ListPanel, entry.name)
            Row.Name = "Script_" .. entry.id

            Left.Size = UDim2.new(1, -76, 1, 0)
            local Title = Left:FindFirstChild("Title")
            Title.AutomaticSize = Enum.AutomaticSize.None
            Title.Size = UDim2.new(1, 0, 1, 0)
            Title.TextTruncate = Enum.TextTruncate.AtEnd
            local baseColor = Title.TextColor3

            -- indicator bar for pinned scripts
            local FavBar = new("Frame", {
                AnchorPoint = Vector2.new(0, 0.5),
                Position = UDim2.new(0, 3, 0.5, 0),
                Size = UDim2.new(0, 3, 0.6, 0),
                BackgroundColor3 = Theme.AccentPink,
                BorderSizePixel = 0,
                Visible = false,
            }, Row)
            corner(FavBar, 2)

            local PLAY_COLOR = Theme.AccentPink
            local ExecBtn, ExecIcon = CreateIconButton(Row, "play", 0, PLAY_COLOR)
            local MoreBtn = CreateIconButton(Row, "more", 34, Theme.SubText)

            local rec = { Row = Row, entry = entry }
            Rows[entry.id] = rec
            function rec.refresh()
                Title.Text = entry.name
                Title.TextColor3 = entry.favorite and Theme.Sakura or baseColor
                FavBar.Visible = entry.favorite
                rec.nameLower = entry.name:lower()
            end
            rec.refresh()

            local function showStopIcon(color)
                for _, c in ipairs(ExecIcon:GetChildren()) do c:Destroy() end
                new("Frame", {
                    AnchorPoint = ANCHOR_CENTER,
                    Position = CENTER,
                    Size = UDim2.fromOffset(10, 10),
                    BackgroundColor3 = color,
                    BorderSizePixel = 0,
                }, ExecIcon)
            end

            local function resetPlayIcon()
                for _, c in ipairs(ExecIcon:GetChildren()) do c:Destroy() end
                drawIcon(ExecIcon, "play", PLAY_COLOR, Theme.Header)
            end

            local function setRunVisual(state)
                if not ExecIcon.Parent then return end
                if state == "running" then return end
                if state == "running_long" then
                    showStopIcon(Theme.Danger)
                    return
                end
                resetPlayIcon()
                if state == "ok" or state == "error" then
                    tintIcon(ExecIcon, state == "ok" and Theme.Sakura or Theme.Danger)
                    task.delay(1, function()
                        if ExecIcon.Parent then tintIcon(ExecIcon, PLAY_COLOR) end
                    end)
                end
            end

            ExecBtn.MouseButton1Click:Connect(function()
                if isLocked() then return end
                if Running[entry.id] then stopScript(entry); return end
                runScript(entry, setRunVisual)
            end)

            MoreBtn.MouseButton1Click:Connect(function()
                if isLocked() then return end
                openContextMenu(MoreBtn, buildRowItems(entry))
            end)
            return rec
        end

        OutputPanel = createOutputPanel(fitListPanel)
        fitListPanel()

        LibMoreBtn.MouseButton1Click:Connect(function()
            if isLocked() then return end
            openContextMenu(LibMoreBtn, buildLibraryItems())
        end)

        local report = loadLibrary()
        for _, entry in ipairs(ScriptList) do CreateScriptRow(entry) end
        applyListView()
        announceLoad(report)

        AddBtn.MouseButton1Click:Connect(function()
            if isLocked() then return end
            ScriptDialog.show("add")
        end)

        -- Options 1: Save (Add / Edit / Import)
        ScriptDialog.Save.MouseButton1Click:Connect(function()
            local dialogMode = ScriptDialog.getMode()
            local code = ScriptDialog.CodeBox.Text
            if dialogMode == "import" then
                commitImport(code)
                return
            end

            local name = sanitizeName(ScriptDialog.NameBox.Text)
            local invalid = false
            if name == "" then
                flashStrokeError(ScriptDialog.NameStroke)
                invalid = true
            end
            if code:match("^%s*$") then
                flashStrokeError(ScriptDialog.CodeStroke)
                invalid = true
            end
            if invalid then return end

            local okSyntax, warnText = validateForSave(code)
            if not okSyntax then
                flashStrokeError(ScriptDialog.CodeStroke)
                showToast(warnText .. " - tap Save again to save anyway", "warn", { duration = 5 })
                return
            end

            if dialogMode == "edit" then
                commitEdit(ScriptDialog.getEntry(), name, code)
            else
                commitAdd(name, code)
            end
        end)
    end

    return ScriptDialog
end
