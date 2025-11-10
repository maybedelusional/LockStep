api:set_lua_name("GPT Resolver")

local WEBHOOK_URL = "https://discord.com/api/webhooks/1419036511977996530/Ntte4EhLNnVJkrxzqPI0zDwn3acO7c0ydsPC4MKK41q2SQy0U-lCQbpx3BD6DygVs591" -- Optional: add your Discord webhook here!

local BRUTE_OFFSETS = {
    {X=0,Y=0,Z=0},{X=16,Y=0,Z=0},{X=-16,Y=0,Z=0},{X=0,Y=0,Z=16},{X=0,Y=0,Z=-16},
    {X=0,Y=12,Z=0},{X=0,Y=-12,Z=0},{X=22,Y=0,Z=22},{X=-22,Y=0,Z=-22}
}
local VOID_DIST, JITTER_DIST, TELEPORT_DIST = 420, 36, 80
local LAST_POS_HISTORY, PATTERN_WINDOW = 12, 18

local tab = api:add_tab("GPT Resolver")
local gb = tab:add_left_groupbox("Main Features")
gb:add_label("#Credits to Norby For The Name")
gb:add_toggle("ai_resolver_toggle", { Text = "AI Resolver (Ultimate)", Default = false })
gb:add_toggle("trashtalk_toggle", { Text = "Trashtalk (GPT Resolver)", Default = false })
local ai_toggle, trashtalk_toggle = api:get_ui("ai_resolver_toggle"), api:get_ui("trashtalk_toggle")

-- VECTOR UTILS
local function vec(x,y,z) return {X=x or 0, Y=y or 0, Z=z or 0} end
local function vadd(a,b) return vec(a.X+b.X, a.Y+b.Y, a.Z+b.Z) end
local function vsub(a,b) return vec(a.X-b.X, a.Y-b.Y, a.Z-b.Z) end
local function vmul(a,s) return vec(a.X*s, a.Y*s, a.Z*s) end
local function vmag(a) return math.sqrt(a.X*a.X+a.Y*a.Y+a.Z*a.Z) end
local function vdist(a,b) return vmag(vsub(a,b)) end
local function vcopy(a) return vec(a.X, a.Y, a.Z) end
local function vavg(tbl) local x,y,z=0,0,0 for _,v in ipairs(tbl) do x=x+v.X y=y+v.Y z=z+v.Z end local n=#tbl return vec(x/n, y/n, z/n) end

-- WEBHOOK LOGGER (Batch, Rate Limit Safe)
local webhook_q, sending = {}, false
local function log_webhook(event, msg)
    if not WEBHOOK_URL or WEBHOOK_URL=="" then return end
    table.insert(webhook_q, string.format("**[%s]** %s", event, msg))
    if not sending then
        sending = true
        spawn(function()
            while #webhook_q > 0 do
                local payload = table.remove(webhook_q, 1)
                pcall(function()
                    syn.request({
                        Url = WEBHOOK_URL,
                        Method = "POST",
                        Headers = { ["Content-Type"] = "application/json" },
                        Body = game:GetService("HttpService"):JSONEncode({ content = payload })
                    })
                end)
                wait(1.6)
            end
            sending = false
        end)
    end
end

-- SITUATIONAL TRASHTALK
local trashtalks = {
    normal = {
        "GPT Resolver domination. You got resolved!",
        "Outplayed and resolved: GPT style!",
        "Skill issue? Or GPT Resolver issue?"
    },
    void = {
        "Nice try hiding in the void—GPT Resolver still finds you!",
        "You can run to the void, but you can't hide."
    },
    brute = {
        "Took some guessing, but you’re out of fakes now.",
        "GPT Resolver brute-forced your last hope!"
    },
    missstreak = {
        "Not even your exploit can save you forever.",
        "Enjoy your luck while it lasts, I'm coming."
    }
}
local trashtalk_last = {}
local function do_trashtalk(id, mode)
    if not trashtalk_toggle:get() then return end
    local pool = trashtalks[mode] or trashtalks.normal
    local msg
    repeat msg = pool[math.random(1,#pool)] until msg ~= trashtalk_last[id] or #pool==1
    api:chat(msg)
    trashtalk_last[id] = msg
end

-- HIT/MISS LOGGING
local misslog = {}
local function log_miss(uid, reason)
    misslog[uid] = misslog[uid] or {miss=0,hit=0}
    misslog[uid].miss = misslog[uid].miss + 1
    misslog[uid].last_reason = reason
    log_webhook("Miss", ("%s missed (%s) [#%d]"):format(uid,reason,misslog[uid].miss))
end
local function log_hit(uid, reason)
    misslog[uid] = misslog[uid] or {miss=0,hit=0}
    misslog[uid].hit = misslog[uid].hit + 1
    misslog[uid].last_reason = reason
    log_webhook("Hit", ("%s hit (%s) [#%d]"):format(uid,reason,misslog[uid].hit))
end

-- RESOLVER STATE & LOGIC
local resolver = {}

local function shuffle_offsets(order)
    for i=#order,2,-1 do local j=math.random(i) order[i],order[j]=order[j],order[i] end
end

local function auto_tune(data)
    -- On long miss streaks, become more aggressive
    if data.miss_streak >= 5 then
        data.aggression = math.min((data.aggression or 1) + 0.25, 2.3)
        data.predict_dt = math.max((data.predict_dt or 0.19) - 0.02, 0.10)
        if not data.brute_order or #data.brute_order==0 then
            data.brute_order = {}
            for i=1,#BRUTE_OFFSETS do table.insert(data.brute_order, i) end
            shuffle_offsets(data.brute_order)
        end
    elseif data.miss_streak == 0 then
        data.aggression = 1
        data.predict_dt = 0.19
        data.brute_order = {}
    end
end

-- ADVANCED PATTERN RECOGNITION
local function recognize_pattern(hist)
    if #hist < PATTERN_WINDOW then return "none" end
    local switches, last_big, stable, total, period = 0, 0, 0, 0, {}
    for i = 4, #hist do
        local d1 = vdist(hist[i], hist[i-1])
        local d2 = vdist(hist[i-2], hist[i-3])
        if math.abs(d1 - d2) > 18 then switches = switches + 1 end
        if d1 > VOID_DIST*0.85 then last_big = last_big + 1 end
        if d1 < 2 then stable = stable + 1 end
        total = total + d1
        if i%2==0 then table.insert(period, d1) end
    end
    local period_var=0 if #period>3 then
        local avg=0 for _,v in ipairs(period) do avg=avg+v end avg=avg/#period
        for _,v in ipairs(period) do period_var=period_var+(v-avg)^2 end period_var=period_var/#period
    end
    if switches > #hist/3 then return "alternating" end
    if last_big > #hist/4 then return "void-hop" end
    if stable > #hist/3 then return "static" end
    if total/#hist > 32 then return "jitter" end
    if period_var > 180 then return "periodic" end
    return "none"
end

api:on_event("game_tick", function()
    if not ai_toggle:get() then return end
    local players = api:get_players() or {} -- Always table, never nil!
    for _, plr in ipairs(players) do
        local id = tostring(plr.UserId or plr.Name or "unknown")
        resolver[id] = resolver[id] or {
            hist={}, last_pattern="none", brute_idx=1, miss_streak=0,
            brute_learned=nil, bruting=false, aim_pos=nil, aggression=1, predict_dt=0.19, brute_order={}
        }
        local data = resolver[id]
        local fpos = api:get_cframe(plr)
        if not fpos or not fpos.Position then goto cont end
        local cur = vcopy(fpos.Position)
        table.insert(data.hist, cur)
        if #data.hist > LAST_POS_HISTORY then table.remove(data.hist, 1) end

        -- Pattern recognition & logging
        local pattern = recognize_pattern(data.hist)
        if pattern ~= data.last_pattern then
            data.last_pattern = pattern
            if pattern ~= "none" then
                log_webhook("Pattern", id.." exploit pattern: "..pattern)
                do_trashtalk(id, pattern=="void-hop" and "void" or "normal")
            end
        end

        -- Signature detection
        local signature, brute_needed = "Normal", false
        if #data.hist >= 2 then
            local jump = vdist(cur, data.hist[#data.hist-1])
            if jump > VOID_DIST then signature="Void" end
            if jump > TELEPORT_DIST then signature="Teleport" end
            if jump > JITTER_DIST then signature="Jitter" end
        end
        if signature == "Void" or pattern~="none" then brute_needed = true end
        if data.miss_streak >= 3 or brute_needed then data.bruting = true end

        -- Auto-tuning (adaptive AI)
        auto_tune(data)

        -- Bruteforce resolver logic
        if data.bruting then
            local idx = data.brute_learned or data.brute_order[data.brute_idx] or data.brute_idx
            data.aim_pos = vadd(cur, BRUTE_OFFSETS[idx])
            data.brute_idx = ((data.brute_idx) % #BRUTE_OFFSETS) + 1
        else
            -- Aggressive prediction
            local prev = data.hist[#data.hist-1] or cur
            data.aim_pos = vadd(cur, vmul(vsub(cur, prev), data.predict_dt or 0.19))
        end
        resolver[id] = data
        ::cont::
    end
end)

api:on_event("localplayer_hit_player", function(event)
    local t = event.Target or event.TargetPlayer
    if not t then return end
    local id = tostring(t.UserId or t.Name or "unknown")
    if not resolver[id] then return end
    if resolver[id].bruting then
        do_trashtalk(id, "brute")
        log_webhook("BruteSuccess", id.." resolved with offset #" .. resolver[id].brute_idx)
        resolver[id].brute_learned = resolver[id].brute_idx
        resolver[id].bruting = false
    else
        do_trashtalk(id, "normal")
    end
    log_hit(id, "resolver")
    resolver[id].miss_streak = 0
end)

api:on_event("localplayer_miss_player", function(event)
    local t = event.Target or event.TargetPlayer
    if not t then return end
    local id = tostring(t.UserId or t.Name or "unknown")
    if not resolver[id] then return end
    resolver[id].miss_streak = (resolver[id].miss_streak or 0) + 1
    local reason = resolver[id].last_pattern ~= "none" and resolver[id].last_pattern or "unknown"
    if resolver[id].miss_streak == 3 then
        do_trashtalk(id, "missstreak")
        log_miss(id, reason)
        log_webhook("MissStreak", id.." miss streak ("..reason..")")
    end
end)

-- Always use resolver[target_id].aim_pos as your live aim/shoot position for each player.
