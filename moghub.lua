--[[----------------------------------------------------------------------------
    FFR_Regen -- MogHub plugin (settings page in the Mods menu)

    BATTLE: HP and MP each come back either with a normal attack (the attacker) or at the start of each
    character's turn, done by the game itself with its own numbers and bars: the mod only edits data tables, at
    run time (nothing is saved, switching the plugin off puts everything back). Each stat: amount as percent of
    max or as fixed points (ParamList[3] 0, as on the game's "自動MP回復（微）"), and a chance (activationProbability).
    A "only below X %" threshold has no native condition (eSkillEffectActivationCondition has none for HP/MP).

    HOW (found with the discovery builds and dev_eval)
      effect  : SKILL_EFFECT_DATA rows of type ParameterVariation (2) that the game uses nowhere else; ParamList =
                value, parameter (1 HP, 2 MP, 4 Limit), mode (2 = percent of max). One per stat, its timing set
                by the mode:
                  attack : at once (applyTiming / proceedTiming 1 AddEffect, lasting 1 action)
                  turn   : like the game's own "オートリジェネ" (1077 / effect 1176) and "毎ターンMP3％回復"
                           (1255 / effect 1283): applyTiming / proceedTiming 2 ActionBegin, never ending,
                           params 4 and 5 as there (-1, 1 for HP / 0 for MP)
      attack  : every playable unit (the rows of UNIT_BATTLE_CMD_DATA) has the SKILL_DATA rows "<name>_通常攻撃" and
                "<name>_簡易通常攻撃"; a free slot of their 8 effect slots (effectBundleList, effectId -1) gets the
                effect: TargetType 0 (Self), targetRelation 1 (Friendlies), activeSkillAddTiming 1
      turn    : PASSIVE_SKILL_DATA row 1032 (an enemy-only counter talk no unit or equipment refers to) carries the
                effects in its 3 slots (passiveSkillAddTiming 54, as on the game's own passives), and is appended
                to UNIT_PARAMETER.passiveSkillList of every playable unit (empty in the game; TArray append works)

    Battle only: walking regen is not part of this plugin.
    ----------------------------------------------------------------------------]]
local mod, kit = ...

local OFF, ATTACK, TURN = 0, 1, 2
local MODES = { { OFF, "Off" }, { ATTACK, "Normal attack" }, { TURN, "Turn start" } }
-- the values are the effect's ParamList[3]: 2 = percent of max, 0 = fixed points (the game's "自動MP回復（微）")
local PERCENT, POINTS = 2, 0
local UNITS = { { PERCENT, "% of max" }, { POINTS, "Points" } }
-- tens plus a third and two thirds
local CHANCES = {}
for _, v in ipairs({ 10, 20, 30, 33, 40, 50, 60, 66, 70, 80, 90, 100 }) do CHANCES[#CHANCES + 1] = { v, v .. " %" } end

local cfg = mod:settings{
    { header = "Battle" },
    { key = "ModeHP", label = "HP regen", type = "choice", default = TURN, choices = MODES,
      help = "Off, with each normal attack (the attacker), or at the start of each character's turn." },
    { key = "UnitHP", label = "HP amount as", type = "choice", default = PERCENT, choices = UNITS,
      help = "Share of max HP, or a fixed number of HP that does not grow with the level." },
    { key = "PercentHP", label = "HP per regen", type = "number", min = 1, max = 100, step = 1, default = 5,
      format = "%g %%", help = "HP restored each time." },
    { key = "ChanceHP", label = "HP chance", type = "choice", default = 33, choices = CHANCES,
      help = "Chance that the regen happens each time." },
    { key = "ModeMP", label = "MP regen", type = "choice", default = TURN, choices = MODES,
      help = "Off, with each normal attack (the attacker), or at the start of each character's turn." },
    { key = "UnitMP", label = "MP amount as", type = "choice", default = POINTS, choices = UNITS,
      help = "Share of max MP, or a fixed number of MP that does not grow with the level." },
    { key = "PercentMP", label = "MP per regen", type = "number", min = 1, max = 100, step = 1, default = 5,
      format = "%g %%", help = "MP restored each time." },
    { key = "ChanceMP", label = "MP chance", type = "choice", default = 33, choices = CHANCES,
      help = "Chance that the regen happens each time." },
}

local logged = {}
local function logOnce(key, fmt, ...)
    if logged[key] then return end
    logged[key] = true
    mod:log(fmt, ...)
end

---------------------------------------------------------------------------------------------------
-- BATTLE
---------------------------------------------------------------------------------------------------
local SUFFIXES = { "_通常攻撃", "_簡易通常攻撃" }
local PARAMETER_VARIATION = 2
local HOST = 1032   -- PASSIVE_SKILL_DATA row that carries the turn effects
-- the stats: setting keys, ParamList parameter, ParamList[5] of the game's own per-turn regen effects
local STATS = {
    { k = "hp", mode = "ModeHP", unit = "UnitHP", pct = "PercentHP", chance = "ChanceHP", param = 1, fifth = 1 },
    { k = "mp", mode = "ModeMP", unit = "UnitMP", pct = "PercentMP", chance = "ChanceMP", param = 2, fifth = 0 },
}
-- how a chosen effect acts, by mode
local SHAPES = {
    [ATTACK] = { applyTiming = 1, proceedTiming = 1, effectEndActionNum = 1, activationProbability = 100, addProbability = 100 },
    [TURN]   = { applyTiming = 2, proceedTiming = 2, effectEndActionNum = -1, activationProbability = 100, addProbability = 100 },
}
local INSTANT = SHAPES[ATTACK]

-- the menu's numbers can come as floats (2.0); the effect params are integers
local function pct(v) return math.floor((tonumber(v) or 0) + 0.5) end

local function modeOf(s)
    local m = tonumber(cfg[s.mode]) or OFF
    if pct(cfg[s.pct]) <= 0 then return OFF end
    return m
end

local function unitOf(s) return cfg[s.unit] == POINTS and POINTS or PERCENT end
local function chanceOf(s) return math.max(1, math.min(100, pct(cfg[s.chance]))) end

-- the amount's menu text follows the unit: "10 %" or "5 MP"
local function amountFormats()
    for _, s in ipairs(STATS) do
        pcall(function()
            local term = mod:t(s.k == "hp" and "termHP" or "termMP", s.k == "hp" and "HP" or "MP")
            cfg._.byKey[s.pct].format = unitOf(s) == POINTS and ("%g " .. term) or "%g %%"
        end)
    end
end
amountFormats()

local function rowsOf(struct, fn)
    local ok, err = pcall(function() kit.tables.rows(struct, fn) end)
    if not ok then logOnce("rows:" .. struct, "reading %s failed: %s", struct, tostring(err)) end
end

-- a slot entry's effect id; PASSIVE_SKILL_DATA might hold plain numbers instead of entries
local function entryId(list, i)
    local ok, id = pcall(function()
        local e = list[i]
        if type(e) == "number" then return e end
        return e.effectId
    end)
    return ok and id or nil
end

-- names of the normal-attack rows and the ids of every playable unit
local function playables()
    local want, ids, n = {}, {}, 0
    rowsOf("UNIT_BATTLE_CMD_DATA", function(row, rowName)
        n = n + 1
        ids[row.ID] = true
        for _, s in ipairs(SUFFIXES) do want[tostring(rowName) .. s] = true end
    end)
    return want, ids, n
end

---------------------------------------------------------------------------------------------------
-- Which ParameterVariation effects does the game use itself? Once per game start; our attack rows and the host
-- passive are left out. The instant ones first.
---------------------------------------------------------------------------------------------------
local chosen   -- { hp = effect id or false, mp = effect id or false }
local hostFree -- the host passive is referred to by nothing of the game's

local function chooseEffects(want)
    local refs, candidates = {}, {}
    rowsOf("SKILL_EFFECT_DATA", function(row)
        if row.EffectType ~= PARAMETER_VARIATION then return end
        local id = row.ID
        if refs[id] then return end
        local instant = true
        for k, v in pairs(INSTANT) do if row[k] ~= v then instant = false end end
        refs[id] = 0
        candidates[#candidates + 1] = { id = id, instant = instant }
    end)
    table.sort(candidates, function(a, b)
        if a.instant ~= b.instant then return a.instant end
        return a.id < b.id
    end)
    local function note(id) if refs[id] then refs[id] = refs[id] + 1 end end
    for _, struct in ipairs({ "SKILL_DATA", "PASSIVE_SKILL_DATA" }) do
        rowsOf(struct, function(row, rowName)
            if want[tostring(rowName)] or (struct == "PASSIVE_SKILL_DATA" and row.ID == HOST) then return end
            local list = row.effectBundleList
            local okL, n = pcall(function() return #list end)
            for i = 1, (okL and n or 0) do note(entryId(list, i)) end
        end)
    end
    rowsOf("SKILL_EFFECT_DATA", function(row)
        local own = row.ID
        for _, v in ipairs(kit.ue.values(row.ParamList)) do if v ~= own then note(v) end end
    end)
    local free = {}
    for _, c in ipairs(candidates) do if refs[c.id] == 0 then free[#free + 1] = c.id end end
    mod:log("%d ParameterVariation effects, %d unused: %s", #candidates, #free, table.concat(free, ", "))
    chosen = { hp = free[1] or false, mp = free[2] or false }
    mod:log("chosen: HP effect %s, MP effect %s", tostring(chosen.hp), tostring(chosen.mp))

    -- the host passive: no unit (apart from ours) and no equipment may carry it
    local hostRefs = 0
    rowsOf("UNIT_PARAMETER", function(row)
        for _, v in ipairs(kit.ue.values(row.passiveSkillList)) do if v == HOST then hostRefs = hostRefs + 1 end end
    end)
    rowsOf("EQUIPMENT_ITEM_DATA", function(row)
        for _, v in ipairs(kit.ue.values(row.passiveList)) do if v == HOST then hostRefs = hostRefs + 1 end end
    end)
    local found = false
    rowsOf("PASSIVE_SKILL_DATA", function(row) if row.ID == HOST then found = true end end)
    hostFree = found and hostRefs == 0
    if not hostFree then mod:log("passive %d %s: turn start regen stays off", HOST, found and "is in use" or "not found") end
end

---------------------------------------------------------------------------------------------------
-- The chosen effects' timing and values; the game's own are kept and put back
---------------------------------------------------------------------------------------------------
local origEffect = {}   -- effect id -> { fields = {...}, params = { first five } }

-- specs: effect id -> { shape = SHAPES[mode], params = { 1..5 } } or false (the game's own back)
local function setEffects(specs)
    rowsOf("SKILL_EFFECT_DATA", function(row)
        local id = row.ID
        local spec = specs[id]
        if spec == nil then return end
        local p = row.ParamList
        if not origEffect[id] then
            local o = { fields = {}, params = {} }
            for k in pairs(INSTANT) do o.fields[k] = row[k] end
            local cur = kit.ue.values(p)
            for i = 1, 5 do o.params[i] = cur[i] end
            origEffect[id] = o
        end
        local o = origEffect[id]
        for k, v in pairs(spec and spec.shape or o.fields) do
            if row[k] ~= v then
                pcall(function() row[k] = v end)
                mod:log("effect %d %s = %s (read back %s)", id, k, tostring(v), tostring(row[k]))
            end
        end
        local cur = kit.ue.values(p)
        local changed = false
        for i = 1, 5 do
            local v = spec and spec.params[i]
            if v == nil then v = o.params[i] end
            if cur[i] ~= v then
                pcall(function() p[i] = v end)
                changed = true
            end
        end
        if changed then
            local b = kit.ue.values(p)
            mod:log("effect %d params %s,%s,%s,%s,%s", id, tostring(b[1]), tostring(b[2]), tostring(b[3]),
                tostring(b[4]), tostring(b[5]))
        end
    end)
end

---------------------------------------------------------------------------------------------------
-- Attack rows: free slots get the attack-mode effects
---------------------------------------------------------------------------------------------------
local patched = {}      -- "row|slot" -> the slot's original fields

local function restoreSlot(list, i, key)
    local p = patched[key]
    if not p then return end
    pcall(function()
        local e = list[i]
        for k, v in pairs(p) do e[k] = v end
    end)
    patched[key] = nil
end

local function syncSlots(want, desired)
    local wrote, full = 0, 0
    rowsOf("SKILL_DATA", function(row, rowName)
        local rn = tostring(rowName)
        local list = row.effectBundleList
        local okL, n = pcall(function() return #list end)
        if not okL then return end
        local wanted = want[rn] and desired or {}
        local isWanted = {}
        for _, id in ipairs(wanted) do isWanted[id] = true end
        -- our slots that hold an effect no longer wanted (setting changed, or the plugin off) are emptied again
        for i = 1, n do
            local key = rn .. "|" .. i
            if patched[key] and not isWanted[entryId(list, i)] then restoreSlot(list, i, key); wrote = wrote + 1 end
        end
        for _, id in ipairs(wanted) do
            local have = false
            for i = 1, n do if entryId(list, i) == id then have = true end end
            if not have then
                local slot
                for i = 1, n do if entryId(list, i) == -1 then slot = i; break end end
                if not slot then
                    full = full + 1
                    logOnce("full:" .. rn, "%s has no free effect slot, left alone", rn)
                else
                    local ok = pcall(function()
                        local e = list[slot]
                        patched[rn .. "|" .. slot] = { effectId = e.effectId, TargetType = e.TargetType,
                            targetRelation = e.targetRelation, activeSkillAddTiming = e.activeSkillAddTiming,
                            passiveSkillAddTiming = e.passiveSkillAddTiming }
                        e.effectId = id
                        e.TargetType = 0              -- Self
                        e.targetRelation = 1          -- Friendlies
                        e.activeSkillAddTiming = 1    -- AfterDamageCalculation
                        e.passiveSkillAddTiming = 0
                    end)
                    if ok then wrote = wrote + 1 end
                end
            end
        end
    end)
    if wrote > 0 then mod:log("attack rows: %d slot(s) changed%s", wrote, full > 0 and (", " .. full .. " row(s) full") or "") end
end

---------------------------------------------------------------------------------------------------
-- Turn start: the host passive carries the turn-mode effects, every playable unit carries the host
---------------------------------------------------------------------------------------------------
local hostOrig   -- the host's slots as the game had them: { { effectId, ... }, ... }
local SLOT_FIELDS = { "effectId", "TargetType", "targetRelation", "activeSkillAddTiming", "passiveSkillAddTiming" }

local function syncHost(desired)
    rowsOf("PASSIVE_SKILL_DATA", function(row)
        if row.ID ~= HOST then return end
        local list = row.effectBundleList
        local n = #list
        if not hostOrig then
            hostOrig = {}
            for i = 1, n do
                local e, o = list[i], {}
                for _, f in ipairs(SLOT_FIELDS) do o[f] = e[f] end
                hostOrig[i] = o
            end
        end
        local changed = false
        for i = 1, n do
            local e = list[i]
            -- ours: like the slot of the game's "オートリジェネ"; the rest empty while in use, the game's own otherwise
            local want = hostOrig[i]
            if #desired > 0 then
                want = { effectId = desired[i] or -1, TargetType = 0, targetRelation = 1, activeSkillAddTiming = 1,
                         passiveSkillAddTiming = 54 }
            end
            for _, f in ipairs(SLOT_FIELDS) do
                if e[f] ~= want[f] then
                    pcall(function() e[f] = want[f] end)
                    changed = true
                end
            end
        end
        if changed then mod:log("passive %d slots: %s", HOST, #desired > 0 and table.concat(desired, ", ") or "the game's own") end
    end)
end

-- managed: passive id -> true (every playable unit carries it) / false (none does); the list's other entries stay
-- (the game leaves these lists empty)
local function syncUnits(ids, managed)
    local added, removed = {}, {}
    rowsOf("UNIT_PARAMETER", function(row)
        if not ids[row.ID] then return end
        local arr = row.passiveSkillList
        local has = {}
        for _, v in ipairs(kit.ue.values(arr)) do has[v] = true end
        local drop = false
        for pid, on in pairs(managed) do
            if on and not has[pid] then
                pcall(function() arr[arr:GetArrayNum() + 1] = pid end)
                added[pid] = (added[pid] or 0) + 1
            elseif not on and has[pid] then
                drop = true
                removed[pid] = (removed[pid] or 0) + 1
            end
        end
        if drop then
            pcall(function()
                local vals = kit.ue.values(arr)
                arr:Empty()
                for _, v in ipairs(vals) do if managed[v] ~= false then arr[arr:GetArrayNum() + 1] = v end end
            end)
        end
    end)
    for pid, n in pairs(added) do mod:log("passive %d given to %d unit(s)", pid, n) end
    for pid, n in pairs(removed) do mod:log("passive %d taken from %d unit(s)", pid, n) end
end

-- which passives the units should carry now
local function managedPassives(turn)
    local m = {}
    if hostFree then m[HOST] = #turn > 0 end
    return m
end

---------------------------------------------------------------------------------------------------
-- Keeping it in step: after a load, every few seconds (the game reloads some tables on map changes), when a
-- setting changes; never during a battle. Switching the plugin off undoes everything.
---------------------------------------------------------------------------------------------------
local function plan()
    local specs, attack, turn = {}, {}, {}
    for _, s in ipairs(STATS) do
        local id = chosen[s.k]
        if id then
            local mode = modeOf(s)
            if mode == TURN and not hostFree then mode = OFF end
            local v, unit = pct(cfg[s.pct]), unitOf(s)
            local shape
            if mode ~= OFF then
                -- the chance is the effect's own activationProbability; addProbability stays 100, so the turn
                -- effect is still given at the start of the battle and only its firing each turn is rolled
                shape = {}
                for k, x in pairs(SHAPES[mode]) do shape[k] = x end
                shape.activationProbability = chanceOf(s)
            end
            if mode == ATTACK then
                specs[id] = { shape = shape, params = { v, s.param, unit } }
                attack[#attack + 1] = id
            elseif mode == TURN then
                specs[id] = { shape = shape, params = { v, s.param, unit, -1, s.fifth } }
                turn[#turn + 1] = id
            else
                specs[id] = false
            end
        end
    end
    return specs, attack, turn
end

local function sync()
    if kit.events.battle then return end
    local want, ids, units = playables()
    if units == 0 then return end   -- tables not loaded yet
    if not chosen then chooseEffects(want) end
    local specs, attack, turn = plan()
    setEffects(specs)
    syncSlots(want, attack)
    if hostFree then syncHost(turn) end
    syncUnits(ids, managedPassives(turn))
end

-- After a load: is it really in place? Reads the rows back and says so on screen for 5 s, green when everything
-- holds what the menu asks for, amber with the reason otherwise.
local function report()
    local NOTICE_MS = 5000
    local want, ids, units = playables()
    if units == 0 then
        mod:notice(mod:t("statusNoTables", "Regen NOT active: the game's tables were not found"), "warn", NOTICE_MS)
        return
    end
    local _, attack, turn = plan()
    local parts = {}
    for _, s in ipairs(STATS) do
        local term = mod:t(s.k == "hp" and "termHP" or "termMP", s.k == "hp" and "HP" or "MP")
        local id = chosen and chosen[s.k]
        local mode = id and modeOf(s) or OFF
        if mode == TURN and not hostFree then mode = OFF end
        local text = mod:t("statusOff", "off")
        if mode ~= OFF then
            text = (mode == ATTACK and mod:t("statusAttack", "attack") or mod:t("statusTurn", "turn start"))
                .. " " .. pct(cfg[s.pct]) .. (unitOf(s) == POINTS and (" " .. term) or " %")
            if chanceOf(s) < 100 then text = text .. " " .. mod:t("statusChance", "({1} % chance)", chanceOf(s)) end
        end
        parts[#parts + 1] = term .. " " .. text
    end
    local summary = table.concat(parts, ", ")
    -- attack rows
    local rows, ready = 0, 0
    rowsOf("SKILL_DATA", function(row, rowName)
        if not want[tostring(rowName)] then return end
        rows = rows + 1
        local list = row.effectBundleList
        local okL, n = pcall(function() return #list end)
        local need = 0
        for _, id in ipairs(attack) do
            for i = 1, (okL and n or 0) do if entryId(list, i) == id then need = need + 1; break end end
        end
        if need == #attack then ready = ready + 1 end
    end)
    -- units carrying every passive they should
    local need = {}
    for pid, on in pairs(managedPassives(turn)) do if on then need[#need + 1] = pid end end
    local carrying, total = 0, 0
    if #need > 0 then
        rowsOf("UNIT_PARAMETER", function(row)
            if not ids[row.ID] then return end
            total = total + 1
            local has = {}
            for _, v in ipairs(kit.ue.values(row.passiveSkillList)) do has[v] = true end
            local all = true
            for _, pid in ipairs(need) do if not has[pid] then all = false end end
            if all then carrying = carrying + 1 end
        end)
    end
    local noEffect = (cfg.ModeHP ~= OFF and not (chosen and chosen.hp)) or (cfg.ModeMP ~= OFF and not (chosen and chosen.mp))
    local noHost = (cfg.ModeHP == TURN or cfg.ModeMP == TURN) and not hostFree
    if #attack > 0 and ready < rows then
        mod:notice(mod:t("statusPartly", "Regen partly active: {1} of {2} attacks prepared", ready, rows), "warn", NOTICE_MS)
    elseif #need > 0 and carrying < total then
        mod:notice(mod:t("statusUnits", "Regen partly active: {1} of {2} characters prepared", carrying, total), "warn", NOTICE_MS)
    elseif noEffect then
        mod:notice(mod:t("statusNoEffect", "Regen: no unused effect of the game was found ({1})", summary), "warn", NOTICE_MS)
    elseif noHost then
        mod:notice(mod:t("statusNoHost", "Regen: turn start is not possible ({1})", summary), "warn", NOTICE_MS)
    else
        mod:notice(mod:t("statusActive", "Regen: {1}", summary), (#attack + #need) > 0 and "on" or "off", NOTICE_MS)
    end
    mod:log("status: %s; %d of %d attack rows ready, %d of %d units carry passives %s", summary, ready, rows,
        carrying, total, table.concat(need, ", "))
end

local function undo()
    if kit.events.battle then return false end
    local _, ids = playables()
    syncSlots({}, {})
    if hostOrig then syncHost({}) end
    local none = {}
    for pid in pairs(managedPassives({})) do none[pid] = false end
    syncUnits(ids, none)
    local specs = {}
    for id in pairs(origEffect) do specs[id] = false end
    setEffects(specs)
    return true
end

---------------------------------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------------------------------
mod:on("saveLoaded", function()
    mod:after(2000, function()
        sync()
        report()
    end, "regen apply")
end)
mod:after(3000, function() mod:notice(mod:t("statusLoaded", "Regen loaded"), "on", 5000) end, "regen loaded")
mod:every(3000, sync, "regen check")
cfg:onChange(function(key)
    if key == "UnitHP" or key == "UnitMP" then amountFormats() end
    sync()
end)
mod:onToggle(function(on)
    if on then sync() return end
    -- off: timers stop, so the undo must happen now; in a battle it waits until the battle is over
    if not undo() then
        local function later()
            if not undo() then mod:after(1000, later, "regen undo") end
        end
        mod:after(1000, later, "regen undo")
    end
end)

mod:log("v%s ready: battle HP mode %s %g (unit %s, %g%% chance), MP mode %s %g (unit %s, %g%% chance)", mod.version,
    tostring(cfg.ModeHP), cfg.PercentHP, tostring(cfg.UnitHP), cfg.ChanceHP,
    tostring(cfg.ModeMP), cfg.PercentMP, tostring(cfg.UnitMP), cfg.ChanceMP)
