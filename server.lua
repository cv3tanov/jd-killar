local QBCore = exports['jd-core']:GetCoreObject()
local inventory = exports.ox_inventory

local missions = {}
local cooldowns = {}
local rateLimits = {}
local globalCooldownUntil = 0
local missionSequence = 0
local anitaCoords = Anitalocation[math.random(1, #Anitalocation)]
local solomonCoords = Solomonlocation[math.random(1, #Solomonlocation)]

local function now()
    return os.time()
end

local function coordsTable(coords)
    return { x = coords.x + 0.0, y = coords.y + 0.0, z = coords.z + 0.0, w = coords.w + 0.0 }
end

local function limited(src, action, milliseconds)
    local key = ('%d:%s'):format(src, action)
    local current = GetGameTimer()
    if rateLimits[key] and current - rateLimits[key] < milliseconds then return true end
    rateLimits[key] = current
    return false
end

local function near(src, coords, distance)
    local ped = GetPlayerPed(src)
    if ped <= 0 or not DoesEntityExist(ped) then return false end
    return #(GetEntityCoords(ped) - vector3(coords.x, coords.y, coords.z)) <= distance
end

local function nearMissionTarget(src, origin, reported)
    if type(reported) ~= 'table' or type(reported.x) ~= 'number' or type(reported.y) ~= 'number' or type(reported.z) ~= 'number' then
        return false
    end
    local actual = vector3(reported.x, reported.y, reported.z)
    if #(actual - vector3(origin.x, origin.y, origin.z)) > Config.Security.TargetLeashDistance then return false end
    return near(src, actual, Config.Security.TargetDistance)
end

local function policeCount()
    local count = 0
    for _, playerId in ipairs(QBCore.Functions.GetPlayers()) do
        local player = QBCore.Functions.GetPlayer(playerId)
        if player and player.PlayerData.job.name == Config.PoliceJob then count = count + 1 end
    end
    return count
end

local function playerKey(src)
    local player = QBCore.Functions.GetPlayer(src)
    if player and player.PlayerData.citizenid then return player.PlayerData.citizenid end
    return GetPlayerIdentifierByType(src, 'license') or ('source:%d'):format(src)
end

local function sendLog(title, description, colour)
    print(('[jd-killar] %s: %s'):format(title, description))
    if not KillarServerConfig.DiscordWebhook or KillarServerConfig.DiscordWebhook == '' then return end
    PerformHttpRequest(KillarServerConfig.DiscordWebhook, function() end, 'POST', json.encode({
        username = KillarServerConfig.LogName or 'jd-killar',
        embeds = {{ title = title, description = description, color = colour or 3447003, footer = { text = os.date('%Y-%m-%d %H:%M:%S') } }}
    }), { ['Content-Type'] = 'application/json' })
end

local function validMissionBucket(src, mission)
    return mission and GetPlayerRoutingBucket(src) == mission.routingBucket
end

local function cleanupMissionItems(src)
    for _, itemName in ipairs({ 'orderphone', 'mysterydocuments', 'blacknotepad' }) do
        local count = inventory:GetItemCount(src, itemName)
        if count and count > 0 then inventory:RemoveItem(src, itemName, count) end
    end
end

local function expireMission(key, missionId)
    local mission = missions[key]
    if not mission or mission.id ~= missionId or mission.stage == 'completed' or mission.stage == 'expired' then return end

    mission.stage = 'expired'
    mission.busy = false
    local src = mission.ownerSource
    if src and GetPlayerName(src) and playerKey(src) == key then
        cleanupMissionItems(src)
        missions[key] = nil
        TriggerClientEvent('jd-killar:client:missionExpired', src)
    end
    sendLog('Mission timeout', ('Mission #%d expired for %s.'):format(missionId, key), 15158332)
end

local function resolveMission(source)
    local key = playerKey(source)
    local mission = missions[key]
    if mission and mission.stage == 'expired' then
        cleanupMissionItems(source)
        missions[key] = nil
        mission = nil
    elseif mission and mission.expiresAt and now() >= mission.expiresAt then
        expireMission(key, mission.id)
        mission = missions[key]
    end
    if mission then mission.ownerSource = source end
    return key, mission
end

local function publicMission(mission)
    if not mission then return { stage = 'idle' } end
    return {
        stage = mission.stage,
        robCoords = mission.robCoords and coordsTable(mission.robCoords) or nil,
        killCoords = mission.killCoords and coordsTable(mission.killCoords) or nil,
        solomonCoords = mission.solomonCoords and coordsTable(mission.solomonCoords) or nil,
        remainingSeconds = mission.expiresAt and math.max(0, mission.expiresAt - now()) or 0
    }
end

local function responseError(message)
    return { ok = false, error = message }
end

lib.callback.register('jd-killar:server:bootstrap', function(source)
    local key, mission = resolveMission(source)
    return {
        anita = coordsTable(anitaCoords),
        solomon = coordsTable(solomonCoords),
        mission = publicMission(mission),
        cooldown = math.max(0, (cooldowns[key] or 0) - now()),
        globalCooldown = math.max(0, globalCooldownUntil - now())
    }
end)

lib.callback.register('jd-killar:server:getState', function(source)
    local _, mission = resolveMission(source)
    return publicMission(mission)
end)

lib.callback.register('jd-killar:server:startMission', function(source)
    if limited(source, 'start', Config.Security.RateLimit) then return responseError('Изчакай малко и опитай пак.') end
    if not near(source, anitaCoords, Config.Security.DealerDistance) then return responseError('Трябва да си до Анита.') end

    local key, mission = resolveMission(source)
    if mission and mission.stage ~= 'completed' then return responseError('Вече имаш активна задача.') end

    local remaining = (cooldowns[key] or 0) - now()
    if remaining > 0 then return responseError(('Анита няма работа за теб. Върни се след %d мин.'):format(math.ceil(remaining / 60))) end
    local globalRemaining = globalCooldownUntil - now()
    if globalRemaining > 0 then return responseError(('Някой наскоро взе работа. Изчакай още %d мин.'):format(math.ceil(globalRemaining / 60))) end
    if policeCount() < Config.PoliceJobs then return responseError('Няма достатъчно полицаи на смяна.') end

    local robCoords = Roblocations[math.random(1, #Roblocations)]
    local solomonIndex = math.random(1, #Solomonlocation)
    if mission and mission.solomonIndex == solomonIndex and #Solomonlocation > 1 then
        solomonIndex = (solomonIndex % #Solomonlocation) + 1
    end
    local taskSolomonCoords = Solomonlocation[solomonIndex]
    missionSequence = missionSequence + 1
    local expiresAt = now() + math.floor(Config.MissionDuration / 1000)
    missions[key] = {
        id = missionSequence,
        stage = 'rob_target',
        robCoords = robCoords,
        solomonCoords = taskSolomonCoords,
        solomonIndex = solomonIndex,
        startedAt = now(),
        expiresAt = expiresAt,
        ownerSource = source,
        routingBucket = GetPlayerRoutingBucket(source),
        busy = false
    }
    globalCooldownUntil = now() + math.floor(Config.GlobalStartCooldown / 1000)
    local currentMissionId = missionSequence
    SetTimeout(Config.MissionDuration, function() expireMission(key, currentMissionId) end)
    sendLog('Mission started', ('%s (%d) started mission #%d.'):format(GetPlayerName(source) or 'unknown', source, missionSequence), 3447003)
    return {
        ok = true,
        stage = 'rob_target',
        robCoords = coordsTable(robCoords),
        solomonCoords = coordsTable(taskSolomonCoords),
        remainingSeconds = math.floor(Config.MissionDuration / 1000)
    }
end)

lib.callback.register('jd-killar:server:completeRob', function(source, targetCoords)
    if limited(source, 'rob', Config.Security.RateLimit) then return responseError('Изчакай малко и опитай пак.') end
    local _, mission = resolveMission(source)
    if not mission or mission.stage ~= 'rob_target' or mission.busy then return responseError('Тази част от задачата не е активна.') end
    if not validMissionBucket(source, mission) then return responseError('Върни се в света, в който започна задачата.') end
    if not nearMissionTarget(source, mission.robCoords, targetCoords) then return responseError('Трябва да си до валидната мишена.') end
    if now() - mission.startedAt < Config.Security.MinimumStageSeconds then return responseError('Твърде бързо действаш.') end
    if not inventory:CanCarryItem(source, 'orderphone', 1) then return responseError('Нямаш място за телефона.') end

    mission.busy = true
    if not inventory:AddItem(source, 'orderphone', 1) then
        mission.busy = false
        return responseError('Телефонът не можа да бъде добавен.')
    end
    if math.random(1, 100) <= Config.DropChance then
        local amount = math.random(Config.RandomPrice.min, Config.RandomPrice.max)
        if inventory:CanCarryItem(source, Config.DropItem, amount) then inventory:AddItem(source, Config.DropItem, amount) end
    end

    mission.stage, mission.busy = 'return_anita', false
    sendLog('Stage completed', ('%s completed the robbery stage.'):format(playerKey(source)), 15844367)
    return { ok = true, stage = mission.stage }
end)

lib.callback.register('jd-killar:server:returnAnita', function(source)
    if limited(source, 'anita', Config.Security.RateLimit) then return responseError('Изчакай малко и опитай пак.') end
    local _, mission = resolveMission(source)
    if not mission or mission.stage ~= 'return_anita' or mission.busy then return responseError('Анита не очаква нищо от теб.') end
    if not validMissionBucket(source, mission) then return responseError('Върни се в света, в който започна задачата.') end
    if not near(source, anitaCoords, Config.Security.DealerDistance) then return responseError('Трябва да си до Анита.') end
    if inventory:GetItemCount(source, 'orderphone') < 1 then return responseError('Липсва ти откраднатият телефон.') end
    if not inventory:CanCarryItem(source, 'mysterydocuments', 1) then return responseError('Нямаш място за документите.') end

    mission.busy = true
    if not inventory:RemoveItem(source, 'orderphone', 1) then mission.busy = false return responseError('Телефонът не можа да бъде предаден.') end
    if not inventory:AddItem(source, 'mysterydocuments', 1) then
        inventory:AddItem(source, 'orderphone', 1)
        mission.busy = false
        return responseError('Документите не можаха да бъдат добавени.')
    end
    mission.stage, mission.busy = 'go_solomon', false
    sendLog('Stage completed', ('%s delivered the phone to Anita.'):format(playerKey(source)), 15844367)
    return { ok = true, stage = mission.stage }
end)

lib.callback.register('jd-killar:server:startKill', function(source)
    if limited(source, 'kill', Config.Security.RateLimit) then return responseError('Изчакай малко и опитай пак.') end
    local _, mission = resolveMission(source)
    if not mission or mission.stage ~= 'go_solomon' or mission.busy then return responseError('Соломон още няма задача за теб.') end
    if not validMissionBucket(source, mission) then return responseError('Върни се в света, в който започна задачата.') end
    if not near(source, mission.solomonCoords, Config.Security.DealerDistance) then return responseError('Трябва да си до Соломон.') end
    if inventory:GetItemCount(source, 'mysterydocuments') < 1 then return responseError('Липсват документите от Анита.') end

    mission.busy = true
    if not inventory:RemoveItem(source, 'mysterydocuments', 1) then mission.busy = false return responseError('Документите не можаха да бъдат предадени.') end
    mission.killCoords = Killlocation[math.random(1, #Killlocation)]
    mission.stage, mission.startedAt, mission.busy = 'kill_target', now(), false
    sendLog('Stage started', ('%s received the kill target.'):format(playerKey(source)), 15844367)
    return { ok = true, stage = mission.stage, killCoords = coordsTable(mission.killCoords) }
end)

lib.callback.register('jd-killar:server:searchVictim', function(source, targetCoords)
    if limited(source, 'search', Config.Security.RateLimit) then return responseError('Изчакай малко и опитай пак.') end
    local _, mission = resolveMission(source)
    if not mission or mission.stage ~= 'kill_target' or mission.busy then return responseError('Тази мишена не е част от задачата.') end
    if not validMissionBucket(source, mission) then return responseError('Върни се в света, в който започна задачата.') end
    if not nearMissionTarget(source, mission.killCoords, targetCoords) then return responseError('Трябва да си до валидната мишена.') end
    if now() - mission.startedAt < Config.Security.MinimumStageSeconds then return responseError('Твърде бързо действаш.') end
    if not inventory:CanCarryItem(source, 'blacknotepad', 1) then return responseError('Нямаш място за тефтерчето.') end

    mission.busy = true
    if not inventory:AddItem(source, 'blacknotepad', 1) then mission.busy = false return responseError('Тефтерчето не можа да бъде добавено.') end
    if math.random(1, 1000000) <= Config.DropChance2 and inventory:CanCarryItem(source, Config.victimdrop, 1) then
        inventory:AddItem(source, Config.victimdrop, 1)
    end
    mission.stage, mission.busy = 'return_solomon', false
    sendLog('Stage completed', ('%s searched the final target.'):format(playerKey(source)), 15844367)
    return { ok = true, stage = mission.stage }
end)

lib.callback.register('jd-killar:server:finishMission', function(source)
    if limited(source, 'finish', Config.Security.RateLimit) then return responseError('Изчакай малко и опитай пак.') end
    local key, mission = resolveMission(source)
    if not mission or mission.stage ~= 'return_solomon' or mission.busy then return responseError('Задачата още не е завършена.') end
    if not validMissionBucket(source, mission) then return responseError('Върни се в света, в който започна задачата.') end
    if not near(source, mission.solomonCoords, Config.Security.DealerDistance) then return responseError('Трябва да си до Соломон.') end
    if inventory:GetItemCount(source, 'blacknotepad') < 1 then return responseError('Липсва черното тефтерче.') end

    local cleanAmount = math.floor(Config.FinishPrice * 0.6)
    local dirtyAmount = Config.FinishPrice - cleanAmount
    if not inventory:CanCarryItem(source, 'money', cleanAmount) or not inventory:CanCarryItem(source, 'markedmoney', dirtyAmount) then
        return responseError('Нямаш достатъчно място за наградата.')
    end

    mission.busy = true
    if not inventory:RemoveItem(source, 'blacknotepad', 1) then mission.busy = false return responseError('Тефтерчето не можа да бъде предадено.') end
    local cleanOk = inventory:AddItem(source, 'money', cleanAmount)
    local dirtyOk = inventory:AddItem(source, 'markedmoney', dirtyAmount)
    if not cleanOk or not dirtyOk then
        if cleanOk then inventory:RemoveItem(source, 'money', cleanAmount) end
        if dirtyOk then inventory:RemoveItem(source, 'markedmoney', dirtyAmount) end
        inventory:AddItem(source, 'blacknotepad', 1)
        mission.busy = false
        return responseError('Наградата не можа да бъде добавена. Тефтерчето е върнато.')
    end

    mission.stage, mission.busy = 'completed', false
    cooldowns[key] = now() + math.floor(Config.MissionCooldown / 1000)
    sendLog('Mission completed', ('%s (%d) completed the mission and received $%d.'):format(GetPlayerName(source) or 'unknown', source, Config.FinishPrice), 3066993)
    return { ok = true, stage = mission.stage }
end)

local function cancelMission(source, reason, requireDeath)
    local key, mission = resolveMission(source)
    if not mission or mission.stage == 'completed' then return responseError('Нямаш активна задача.') end
    if requireDeath and not IsEntityDead(GetPlayerPed(source)) then return responseError('Играчът не е мъртъв.') end
    cleanupMissionItems(source)
    missions[key] = nil
    cooldowns[key] = now() + math.floor(Config.CancelCooldown / 1000)
    sendLog(reason == 'death' and 'Mission failed' or 'Mission cancelled', ('%s (%d), mission #%d.'):format(GetPlayerName(source) or key, source, mission.id), 15158332)
    return { ok = true, stage = 'idle' }
end

lib.callback.register('jd-killar:server:cancelMission', function(source)
    if limited(source, 'cancel', Config.Security.RateLimit) then return responseError('Изчакай малко и опитай пак.') end
    return cancelMission(source, 'cancel', false)
end)

lib.callback.register('jd-killar:server:failOnDeath', function(source)
    if not Config.FailOnPlayerDeath then return responseError('Задачата не се прекратява при смърт.') end
    return cancelMission(source, 'death', true)
end)

QBCore.Commands.Add('killarstatus', 'Показва състоянието на jd-killar за player ID', {{ name = 'id', help = 'Server ID' }}, true, function(source, args)
    local targetId = tonumber(args[1])
    if not targetId or not GetPlayerName(targetId) then return TriggerClientEvent('ox_lib:notify', source, { type = 'error', description = 'Невалиден player ID.' }) end
    local key, mission = resolveMission(targetId)
    local text = mission and ('Citizen: %s | Stage: %s | Remaining: %d sec | Bucket: %d'):format(key, mission.stage, math.max(0, mission.expiresAt - now()), mission.routingBucket) or ('Citizen: %s | Няма активна задача.'):format(key)
    TriggerClientEvent('ox_lib:notify', source, { type = 'inform', duration = 10000, description = text })
end, 'admin')

QBCore.Commands.Add('killarreset', 'Прекратява jd-killar задачата на player ID', {{ name = 'id', help = 'Server ID' }}, true, function(source, args)
    local targetId = tonumber(args[1])
    if not targetId or not GetPlayerName(targetId) then return TriggerClientEvent('ox_lib:notify', source, { type = 'error', description = 'Невалиден player ID.' }) end
    local key = playerKey(targetId)
    cleanupMissionItems(targetId)
    missions[key], cooldowns[key] = nil, nil
    TriggerClientEvent('jd-killar:client:missionReset', targetId, 'Администратор прекрати задачата ти.')
    TriggerClientEvent('ox_lib:notify', source, { type = 'success', description = ('Задачата на ID %d е прекратена.'):format(targetId) })
    sendLog('Admin reset', ('Admin %s reset mission for %s.'):format(source, targetId), 15105570)
end, 'admin')

CreateThread(function()
    Wait(1000)
    local errors = {}
    if #Anitalocation == 0 then errors[#errors + 1] = 'Anitalocation е празна' end
    if #Solomonlocation < 2 then errors[#errors + 1] = 'Solomonlocation има по-малко от 2 позиции' end
    if #Roblocations == 0 then errors[#errors + 1] = 'Roblocations е празна' end
    if #Killlocation == 0 then errors[#errors + 1] = 'Killlocation е празна' end
    for _, itemName in ipairs({ 'orderphone', 'mysterydocuments', 'blacknotepad', 'money', 'markedmoney', Config.DropItem, Config.victimdrop }) do
        if not inventory:Items(itemName) then errors[#errors + 1] = ('Липсва ox_inventory item: %s'):format(itemName) end
    end
    if Config.WarningBeforeEnd >= Config.MissionDuration then errors[#errors + 1] = 'WarningBeforeEnd трябва да е по-малко от MissionDuration' end
    if #errors == 0 then
        print('[jd-killar] Startup validation passed.')
    else
        for _, message in ipairs(errors) do print(('[jd-killar] CONFIG ERROR: %s'):format(message)) end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    for key in pairs(rateLimits) do
        if key:sub(1, #tostring(src) + 1) == tostring(src) .. ':' then rateLimits[key] = nil end
    end
end)
