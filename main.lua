api:set_lua_name("GPT Resolver")

----------------------------------------------------
-- Vector3 Helpers (NO metatable, no engine Vector3)
----------------------------------------------------
local function new_vec(x, y, z)
    return { X = x or 0, Y = y or 0, Z = z or 0 }
end

local function add_vec(a, b)
    return new_vec(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
local function sub_vec(a, b)
    return new_vec(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
local function mul_vec(a, s)
    return new_vec(a.X * s, a.Y * s, a.Z * s)
end
local function mag_vec(v)
    return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
end
local function tostring_vec(a)
    return string.format("(%0.1f, %0.1f, %0.1f)", a.X, a.Y, a.Z)
end
local function safe_vec(v)
    if not v then return new_vec(0, 0, 0) end
    return new_vec(v.X or 0, v.Y or 0, v.Z or 0)
end

local function dist(a, b)
    return mag_vec(sub_vec(a, b))
end

local function safe_get_ui(name)
    local ok, obj = pcall(function() return api:get_ui_object(name) end)
    if not ok or not obj then
        api:notify("[GPT Resolver] Missing UI element: " .. name)
        return { GetValue = function() return false end }
    end
    return obj
end

----------------------------------------------------
-- UI Setup (Tab, Groupbox, Credit Label)
----------------------------------------------------
local tabs = { main = api:AddTab("GPT Resolver") }
local gb = tabs.main:AddLeftGroupbox("Main Features")
gb:AddLabel("#Credits to Norby For The Name") -- CREDIT LABEL HERE!

gb:AddToggle("ai_resolver_toggle", { Text = "AI Resolver (Ultimate)", Default = false })
gb:AddToggle("trashtalk_toggle", { Text = "Trashtalk (GPT Resolver)", Default = false })

local ai_toggle = safe_get_ui("ai_resolver_toggle")
local trashtalk_toggle = safe_get_ui("trashtalk_toggle")

----------------------------------------------------
-- Trashtalk System (robust on hit)
----------------------------------------------------
local hit_cache, last_tr_msg = {}, {}
local trashtalk_msgs = {
    "GPT Resolver domination. You got resolved!",
    "You just got outsmarted by GPT Resolver.",
    "Your fake doesn't work. GPT Resolver reads you.",
    "GPT Resolver makes anti-aim pointless.",
    "Outplayed and resolved: GPT style!",
    "Try harder, GPT Resolver is too strong.",
    "Skill issue? Or GPT Resolver issue?",
    "Maybe update your anti-aim. GPT Resolver 100%."
}
local rare_msgs = {
    "GPT Resolver just ended your career.",
    "This is a masterclass. GPT Resolver never loses.",
    "GPT Resolver's resolver just retired you.",
    "You vs GPT Resolver = Easy History Lesson!"
}

local function safe_chat(msg)
    local ok = pcall(function() api:chat(msg) end)
    if not ok then
        local s, e = pcall(function()
            local ReplicatedStorage = game:GetService("ReplicatedStorage")
            if ReplicatedStorage:FindFirstChild("DefaultChatSystemChatEvents") then
                ReplicatedStorage.DefaultChatSystemChatEvents
                    .SayMessageRequest:FireServer(msg, "All")
            end
        end)
        if not s then
            warn("[GPT Resolver] Chat send failed:", e)
        end
    end
end

local function send_chat_once(target_id)
    local pool = (math.random() < 0.05) and rare_msgs or trashtalk_msgs
    local msg
    repeat
        msg = pool[math.random(1, #pool)]
    until msg ~= last_tr_msg[target_id] or #pool == 1
    safe_chat(msg)
    last_tr_msg[target_id] = msg
end

local function register_hit_event()
    local ok = pcall(function()
        api:on_event("localplayer_hit_player", function(event)
            if not trashtalk_toggle:GetValue() then return end
            if not event then return end
            local target = event.Target or event.TargetPlayer
            if not target then return end

            local target_id = tostring(target.UserId or target.Name or "unknown")
            local tick = api:utility_tick()
            if hit_cache[target_id] and (tick - hit_cache[target_id]) < 30 then return end

            send_chat_once(target_id)
            hit_cache[target_id] = tick
        end)
    end)

    if not ok then
        local players = game:GetService("Players")
        local lp = players.LocalPlayer
        local old_health = {}

        game:GetService("RunService").Heartbeat:Connect(function()
            if not trashtalk_toggle:GetValue() then return end
            for _, p in ipairs(players:GetPlayers()) do
                if p ~= lp and p.Character and p.Character:FindFirstChild("Humanoid") then
                    local h = p.Character.Humanoid
                    local hp = h.Health
                    local old = old_health[p] or hp
                    if hp < old then
                        local target_id = tostring(p.UserId or p.Name or "unknown")
                        local tick = tick()
                        if not hit_cache[target_id] or (tick - (hit_cache[target_id] or 0)) > 30 then
                            send_chat_once(target_id)
                            hit_cache[target_id] = tick
                        end
                    end
                    old_health[p] = hp
                end
            end
        end)
    end
end

register_hit_event()

----------------------------------------------------
-- AI Resolver System (anti-fake, void, jitter, etc.)
----------------------------------------------------
local ai_model = {}
local global_feedback = { hits = 0, misses = 0, last_feedback_tick = 0, aggression_mult = 1, conf_threshold = 0.65 }

local JITTER_DIST = 30
local TELEPORT_DIST = 60
local LAST_POS_COUNT = 5
local VOID_DIST = 500
local MAP_BOUNDS = 10000

local function update_last_positions(data, pos)
    data.last_positions = data.last_positions or {}
    table.insert(data.last_positions, pos)
    if #data.last_positions > LAST_POS_COUNT then
        table.remove(data.last_positions, 1)
    end
end

local function avg_position(positions)
    local x, y, z = 0, 0, 0
    for _, v in ipairs(positions) do
        x = x + v.X
        y = y + v.Y
        z = z + v.Z
    end
    local n = #positions
    return new_vec(x / n, y / n, z / n)
end

local function broadcast_signature(id, signature)
    local msg = "[GPT Resolver] Signature: " .. (signature or "Unknown") .. " for " .. tostring(id)
    api:notify(msg)
end

local function movement_state(target)
    local fpos = api.get_client_cframe(target)
    if not fpos or not fpos.Velocity then return "unknown" end
    local vel = fpos.Velocity
    if mag_vec(vel) > 50 then return "sprinting"
    elseif mag_vec(vel) > 15 then return "running"
    elseif mag_vec(vel) <= 2 then return "idle"
    else return "moving" end
end

local function exp_smooth(last, new, alpha)
    if not last then return new end
    return add_vec(mul_vec(last, (1 - alpha)), mul_vec(new, alpha))
end

local function ai_track(target)
    if not target or not target.UserId then return end
    local id = target.UserId
    local fpos = api:get_client_cframe(target)
    if not fpos or not fpos.Position then return end

    if not ai_model[id] then
        ai_model[id] = {
            history = {},
            anomalies = 0, confidence = 1, aggression = 1,
            smooth_alpha = 0.5, predict_dt = 0.15,
            hits = 0, misses = 0,
            last_signature = "Normal",
            last_valid_pos = safe_vec(fpos.Position),
            void_spam = false
        }
    end

    local data = ai_model[id]
    local now = os.clock()
    local pos = safe_vec(fpos.Position)

    table.insert(data.history, {
        pos = pos,
        head = safe_vec(fpos.Head or pos),
        time = now,
        state = movement_state(target)
    })
    if #data.history > 50 then table.remove(data.history, 1) end

    update_last_positions(data, pos)

    local signature = "Normal"
    local is_void = false
    if #data.last_positions >= 2 then
        local prev = data.last_positions[#data.last_positions - 1]
        local jump = dist(pos, prev)
        if math.abs(pos.X) > MAP_BOUNDS or math.abs(pos.Y) > MAP_BOUNDS or math.abs(pos.Z) > MAP_BOUNDS then
            signature = "Void"
            is_void = true
        elseif jump > VOID_DIST then
            signature = "Void"
            is_void = true
        elseif jump > TELEPORT_DIST then
            signature = "Teleport"
            data.anomalies = (data.anomalies or 0) + 1
        elseif jump > JITTER_DIST then
            signature = "Jitter"
            data.anomalies = (data.anomalies or 0) + 1
        elseif #data.last_positions >= 3 then
            local recent = 0
            for i = 2, #data.last_positions do
                if dist(data.last_positions[i], data.last_positions[i - 1]) < 1 then
                    recent = recent + 1
                end
            end
            if recent >= (#data.last_positions - 2) and jump > JITTER_DIST then
                signature = "FakeLag"
                data.anomalies = (data.anomalies or 0) + 1
            end
        end
    end

    if is_void then
        data.void_spam = true
    else
        data.last_valid_pos = pos
        data.void_spam = false
    end

    if signature ~= data.last_signature then
        broadcast_signature(id, signature)
        data.last_signature = signature
    end

    ai_model[id] = data
end

local function cubic_predict(data)
    local h = data.history
    local n = #h
    if n < 4 then return h[n] and h[n].pos or nil end

    local times, xs, ys, zs = {}, {}, {}, {}
    for i = math.max(1, n - 7), n do
        table.insert(times, h[i].time)
        table.insert(xs, h[i].pos.X)
        table.insert(ys, h[i].pos.Y)
        table.insert(zs, h[i].pos.Z)
    end
    local dt = times[#times] - times[1]
    if dt == 0 then return h[n].pos end

    local vels = {}
    for i = 2, #times do
        local dt_i = (times[i] - times[i - 1])
        if dt_i ~= 0 then
            local vel = new_vec(
                (xs[i] - xs[i - 1]) / dt_i,
                (ys[i] - ys[i - 1]) / dt_i,
                (zs[i] - zs[i - 1]) / dt_i
            )
            table.insert(vels, vel)
        end
    end
    if #vels == 0 then return h[n].pos end
    local median_vel = vels[math.floor(#vels / 2) + 1] or new_vec(0, 0, 0)
    return add_vec(h[n].pos, mul_vec(median_vel, (data.predict_dt or 0.15)))
end

local function ai_predict(target)
    if not target or not target.UserId then return nil, 0 end
    local id = target.UserId
    local data = ai_model[id]
    if not data or not data.history then return nil, 0 end
    local hist = data.history
    if #hist < 3 then return hist[#hist] and hist[#hist].pos or nil, 1 end

    local pred
    if (data.void_spam or data.last_signature == "Void") and data.last_valid_pos then
        pred = data.last_valid_pos
    elseif (data.anomalies or 0) >= 2 or (data.last_signature ~= "Normal") then
        pred = avg_position(data.last_positions or {hist[#hist].pos})
    else
        pred = cubic_predict(data)
    end

    local ping = api.get_ping and api:get_ping(target) or 0
    if ping > 120 then pred = add_vec(pred, new_vec(0, 0, math.min(20, ping * 0.02))) end

    local confidence = (0.7 + math.min(#hist / 10, 0.3)) * (data.aggression or 1) * (global_feedback.aggression_mult or 1)
    data.last_pred = pred
    data.confidence = confidence

    if ai_toggle:GetValue() then
        local conf_threshold = global_feedback.conf_threshold or 0.65
        if confidence > conf_threshold then
            api:notify(string.format("[GPT Resolver][AI] Pos: %s | Conf: %.2f | Agg: %.2f", tostring_vec(pred), confidence, data.aggression))
        end
    end

    ai_model[id] = data
    return pred, confidence
end

----------------------------------------------------
-- Main Resolver Loop
----------------------------------------------------
api:on_event("game_tick", function()
    if not ai_toggle:GetValue() then return end

    local tick = api:utility_tick()
    if (tick - (global_feedback.last_feedback_tick or 0)) > 50 then
        -- Optionally: auto_tune_parameters()
    end

    local players = api:get_players() or {}
    for _, player in ipairs(players) do
        ai_track(player)
        ai_predict(player)
    end
end)
