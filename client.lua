local target = exports.ox_target

local locations = {}
local stage = 'idle'
local missionCoords = {}
local dealers = { anita = nil, solomon = nil }
local missionPed
local missionBlip
local spawning = false
local busy = false
local stopping = false
local timerGeneration = 0
local deathReported = false

local function notify(description, kind)
    local data = {
        success = { icon = 'fa-solid fa-check', color = '#2ECC71' },
        error = { icon = 'fa-solid fa-xmark', color = '#C53030' },
        info = { icon = 'fa-solid fa-question', color = '#1688c6' }
    }
    local style = data[kind] or data.info
    lib.notify({
        description = description,
        position = 'center-left',
        duration = 6000,
        style = { backgroundColor = '#141517', color = '#C1C2C5' },
        icon = style.icon,
        iconColor = style.color,
        iconAnimation = 'fade',
        alignIcon = 'center'
    })
end

local function showTask(text)
    if GetResourceState('jd-task') == 'started' then exports['jd-task']:Show('Задача', text) end
end

local function hideTask()
    if GetResourceState('jd-task') == 'started' then exports['jd-task']:Hide() end
end

local function sendPoliceAlert()
    TriggerServerEvent('SendAlert:police', {
        coords = GetEntityCoords(PlayerPedId()),
        title = 'Ограбен и ранен гражданин',
        type = '215',
        job = 'police'
    })
end

local function removeMissionBlip()
    if missionBlip and DoesBlipExist(missionBlip) then RemoveBlip(missionBlip) end
    missionBlip = nil
end

local function setMissionBlip(coords, name, sprite, colour)
    removeMissionBlip()
    missionBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(missionBlip, sprite)
    SetBlipColour(missionBlip, colour)
    SetBlipScale(missionBlip, 0.8)
    SetBlipRoute(missionBlip, true)
    SetBlipRouteColour(missionBlip, colour)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(name)
    EndTextCommandSetBlipName(missionBlip)
end

local function cleanupMissionPed()
    if missionPed then
        target:removeLocalEntity(missionPed)
        if DoesEntityExist(missionPed) then DeleteEntity(missionPed) end
    end
    missionPed = nil
    spawning = false
end

local function removeDealer(name, targetName)
    local ped = dealers[name]
    if not ped then return end
    target:removeLocalEntity(ped, targetName)
    if DoesEntityExist(ped) then DeleteEntity(ped) end
    dealers[name] = nil
end

local function exchangeAnimation(ped)
    lib.requestAnimDict('mp_common')
    if ped and DoesEntityExist(ped) then TaskPlayAnim(ped, 'mp_common', 'givetake1_b', 8.0, 8.0, 2500, 50, 0.0, false, false, false) end
    TaskPlayAnim(PlayerPedId(), 'mp_common', 'givetake1_b', 8.0, 8.0, 2500, 50, 0.0, false, false, false)
end

local function serverCall(name, ...)
    if busy then return nil end
    busy = true
    local response = lib.callback.await(name, false, ...)
    busy = false
    if not response or not response.ok then
        notify(response and response.error or 'Сървърът не отговори. Опитай отново.', 'error')
        return nil
    end
    return response
end

local function stopMissionTimer()
    timerGeneration = timerGeneration + 1
end

local function startMissionTimer(remainingSeconds)
    stopMissionTimer()
    local generation = timerGeneration
    local remaining = math.max(0, tonumber(remainingSeconds) or 0)
    local warningSeconds = math.floor(Config.WarningBeforeEnd / 1000)

    CreateThread(function()
        local warned = false
        while not stopping and generation == timerGeneration and remaining > 0 do
            if not warned and remaining <= warningSeconds then
                warned = true
                notify(('Остават %d минути за завършване на задачата!'):format(math.ceil(remaining / 60)), 'info')
            end
            Wait(1000)
            remaining = remaining - 1
        end
    end)
end

local function resetClientMission(message)
    stage = 'idle'
    missionCoords = {}
    deathReported = false
    stopMissionTimer()
    cleanupMissionPed()
    removeMissionBlip()
    hideTask()
    removeDealer('solomon', 'jd-killar:solomon')
    if message then notify(message, 'error') end
end

local spawnRobTarget
local spawnKillTarget

local function interactAnita()
    if busy then return end
    local state = lib.callback.await('jd-killar:server:getState', false)
    if not state then return notify('Сървърът не отговори.', 'error') end
    stage = state.stage

    if stage == 'idle' or stage == 'completed' then
        local response = serverCall('jd-killar:server:startMission')
        if not response then return end
        stage, missionCoords.rob = response.stage, response.robCoords
        locations.solomon = response.solomonCoords
        removeDealer('solomon', 'jd-killar:solomon')
        deathReported = false
        startMissionTimer(response.remainingSeconds)
        notify('Имам работа за теб. Намери човека, ограби го и после се върни при мен.', 'info')
        showTask('Намери мишената и вземи телефона, който принадлежи на Анита.')
        setMissionBlip(missionCoords.rob, Config.Blips.RobTarget.name, Config.Blips.RobTarget.sprite, Config.Blips.RobTarget.colour)
        spawnRobTarget()
        return
    end

    if stage == 'return_anita' then
        local response = serverCall('jd-killar:server:returnAnita')
        if not response then return end
        stage = response.stage
        cleanupMissionPed()
        exchangeAnimation(dealers.anita)
        notify('Добра работа. Занеси тези документи на моя приятел Соломон.', 'success')
        setMissionBlip(locations.solomon, Config.Blips.Solomon.name, Config.Blips.Solomon.sprite, Config.Blips.Solomon.colour)
        showTask('Занеси документите на Соломон.')
        return
    end

    if stage == 'rob_target' then
        notify('Първо намери мишената и си свърши работата.', 'error')
    else
        notify('Анита няма какво повече да ти каже в момента.', 'error')
    end
end

local function interactSolomon()
    if busy then return end
    local state = lib.callback.await('jd-killar:server:getState', false)
    if not state then return notify('Сървърът не отговори.', 'error') end
    stage = state.stage

    if stage == 'go_solomon' then
        local response = serverCall('jd-killar:server:startKill')
        if not response then return end
        stage, missionCoords.kill = response.stage, response.killCoords
        exchangeAnimation(dealers.solomon)
        notify('Намери мръсника, убий го и ми донеси черното тефтерче.', 'info')
        showTask('Намери мишената, премахни я и вземи черното тефтерче.')
        setMissionBlip(missionCoords.kill, Config.Blips.KillTarget.name, Config.Blips.KillTarget.sprite, Config.Blips.KillTarget.colour)
        spawnKillTarget()
        return
    end

    if stage == 'return_solomon' then
        local response = serverCall('jd-killar:server:finishMission')
        if not response then return end
        stage = response.stage
        stopMissionTimer()
        exchangeAnimation(dealers.solomon)
        cleanupMissionPed()
        removeMissionBlip()
        hideTask()
        removeDealer('solomon', 'jd-killar:solomon')
        notify('Свърши страхотна работа. Ето ти наградата.', 'success')
        return
    end

    if stage == 'kill_target' then
        notify('Върни се, когато изпълниш задачата.', 'error')
    else
        notify('Соломон няма работа за теб в момента.', 'error')
    end
end

local function openAnitaMenu()
    local state = lib.callback.await('jd-killar:server:getState', false)
    if not state then return notify('Сървърът не отговори.', 'error') end
    local options = {{ title = 'Говори с Анита', icon = 'comments', onSelect = interactAnita }}

    if state.stage ~= 'idle' and state.stage ~= 'completed' then
        options[#options + 1] = {
            title = 'Откажи задачата',
            description = ('Получаваш %d минути cooldown.'):format(math.floor(Config.CancelCooldown / 60000)),
            icon = 'ban',
            iconColor = '#C53030',
            onSelect = function()
                local confirm = lib.alertDialog({
                    header = 'Отказ от задачата',
                    content = 'Прогресът и временните предмети ще бъдат премахнати. Сигурен ли си?',
                    centered = true,
                    cancel = true
                })
                if confirm ~= 'confirm' then return end
                local response = serverCall('jd-killar:server:cancelMission')
                if response then resetClientMission('Отказа задачата.') end
            end
        }
    end

    lib.registerContext({ id = 'jd-killar:anita-menu', title = 'Анита', options = options })
    lib.showContext('jd-killar:anita-menu')
end

local dealerData = {
    anita = { model = Config.Npcs.Anita.model, scenario = Config.Npcs.Anita.scenario, targetName = 'jd-killar:anita', handler = openAnitaMenu },
    solomon = { model = Config.Npcs.Solomon.model, scenario = Config.Npcs.Solomon.scenario, targetName = 'jd-killar:solomon', handler = interactSolomon }
}

local function spawnDealer(name)
    local data, coords = dealerData[name], locations[name]
    if not data or not coords or stopping then return end
    if dealers[name] and DoesEntityExist(dealers[name]) then return end
    if dealers[name] then
        target:removeLocalEntity(dealers[name], data.targetName)
        dealers[name] = nil
    end
    if #(GetEntityCoords(PlayerPedId()) - vector3(coords.x, coords.y, coords.z)) > Config.DealerSpawnDistance then return end

    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    local model = joaat(data.model)
    lib.requestModel(model)
    local ped = CreatePed(4, model, coords.x, coords.y, coords.z - Config.PedZOffset, coords.w, false, false)
    if not ped or ped == 0 then
        SetModelAsNoLongerNeeded(model)
        return
    end

    SetEntityAsMissionEntity(ped, true, true)
    SetEntityInvincible(ped, true)
    SetPedCanRagdoll(ped, false)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    FreezeEntityPosition(ped, true)
    TaskStartScenarioInPlace(ped, data.scenario, 0, true)
    SetModelAsNoLongerNeeded(model)
    dealers[name] = ped

    target:addLocalEntity(ped, {{
        name = data.targetName,
        icon = 'fa-regular fa-comments',
        label = 'Говори',
        distance = Config.DealerTargetDistance,
        canInteract = function() return not busy end,
        onSelect = data.handler
    }})
end

spawnRobTarget = function()
    if spawning or (missionPed and DoesEntityExist(missionPed)) or not missionCoords.rob then return end
    if missionPed then cleanupMissionPed() end
    local coords = missionCoords.rob
    if not missionBlip then setMissionBlip(coords, Config.Blips.RobTarget.name, Config.Blips.RobTarget.sprite, Config.Blips.RobTarget.colour) end
    if #(GetEntityCoords(PlayerPedId()) - vector3(coords.x, coords.y, coords.z)) > Config.MissionPedSpawnDistance then return end

    spawning = true
    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    local model = joaat(Config.Npcs.RobTarget.model)
    lib.requestModel(model)
    missionPed = CreatePed(4, model, coords.x, coords.y, coords.z, coords.w, false, false)
    SetModelAsNoLongerNeeded(model)
    spawning = false
    if not missionPed or missionPed == 0 then missionPed = nil return end

    SetEntityAsMissionEntity(missionPed, true, true)
    SetBlockingOfNonTemporaryEvents(missionPed, true)
    TaskStartScenarioInPlace(missionPed, Config.Npcs.RobTarget.scenario, 0, true)
    target:addLocalEntity(missionPed, {{
        name = 'jd-killar:rob-target',
        icon = 'fa-solid fa-person',
        label = 'Ограби',
        distance = Config.TargetInteractionDistance,
        canInteract = function() return stage == 'rob_target' and not busy end,
        onSelect = function()
            if busy then return end
            sendPoliceAlert()
            if not lib.skillCheck(Config.RobSkillCheck, { 'e' }) then
                TaskWanderStandard(missionPed, 10.0, 20)
                return notify('Усети те. По-добре го настигни, преди да извика полицията!', 'error')
            end
            local completed = lib.progressCircle({
                duration = Config.RobDuration, position = 'bottom', label = 'Ограбване...', canCancel = true,
                disable = { sprint = true, move = true, combat = true },
                anim = { dict = 'clothingtrousers', clip = 'check_out_b' }
            })
            if not completed then return end
            local pedCoords = GetEntityCoords(missionPed)
            local response = serverCall('jd-killar:server:completeRob', { x = pedCoords.x, y = pedCoords.y, z = pedCoords.z })
            if not response then return end
            stage = response.stage
            notify('Взе телефона. Върни се при Анита.', 'success')
            cleanupMissionPed()
            setMissionBlip(locations.anita, Config.Blips.Anita.name, Config.Blips.Anita.sprite, Config.Blips.Anita.colour)
            showTask('Върни откраднатия телефон на Анита.')
        end
    }})
end

spawnKillTarget = function()
    if spawning or (missionPed and DoesEntityExist(missionPed)) or not missionCoords.kill then return end
    if missionPed then cleanupMissionPed() end
    local coords = missionCoords.kill
    if not missionBlip then setMissionBlip(coords, Config.Blips.KillTarget.name, Config.Blips.KillTarget.sprite, Config.Blips.KillTarget.colour) end
    if #(GetEntityCoords(PlayerPedId()) - vector3(coords.x, coords.y, coords.z)) > Config.MissionPedSpawnDistance then return end

    spawning = true
    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    local model = joaat(Config.Npcs.KillTarget.model)
    lib.requestModel(model)
    missionPed = CreatePed(26, model, coords.x, coords.y, coords.z, coords.w, false, false)
    SetModelAsNoLongerNeeded(model)
    spawning = false
    if not missionPed or missionPed == 0 then missionPed = nil return end

    local ped = missionPed
    SetEntityAsMissionEntity(ped, true, true)
    SetPedArmour(ped, Config.Npcs.KillTarget.armour)
    GiveWeaponToPed(ped, joaat(Config.Npcs.KillTarget.weapon), 30, false, true)
    TaskWanderStandard(ped, 0.0, 20)
    CreateThread(function()
        while stage == 'kill_target' and ped == missionPed and DoesEntityExist(ped) and not IsEntityDead(ped) do Wait(500) end
        if stage ~= 'kill_target' or ped ~= missionPed or not DoesEntityExist(ped) then return end
        sendPoliceAlert()
        notify('Претърси мишената, преди да пристигне полицията.', 'info')
        target:addLocalEntity(ped, {{
            name = 'jd-killar:search-target',
            icon = 'fa-solid fa-person',
            label = 'Претърси',
            distance = Config.TargetInteractionDistance,
            canInteract = function() return stage == 'kill_target' and not busy and IsEntityDead(ped) end,
            onSelect = function()
                local completed = lib.progressCircle({
                    duration = Config.SearchDuration, position = 'bottom', label = 'Претърсване...', canCancel = true,
                    disable = { sprint = true, move = true, combat = true },
                    anim = { dict = 'anim@gangops@facility@servers@bodysearch@', clip = 'player_search' }
                })
                if not completed then return end
                local pedCoords = GetEntityCoords(ped)
                local response = serverCall('jd-killar:server:searchVictim', { x = pedCoords.x, y = pedCoords.y, z = pedCoords.z })
                if not response then return end
                stage = response.stage
                notify('Намери черното тефтерче. Занеси го на Соломон.', 'success')
                cleanupMissionPed()
                setMissionBlip(locations.solomon, Config.Blips.Solomon.name, Config.Blips.Solomon.sprite, Config.Blips.Solomon.colour)
                showTask('Занеси черното тефтерче на Соломон.')
            end
        }})
    end)
end

local function restoreMission(mission)
    stage = mission.stage or 'idle'
    missionCoords.rob, missionCoords.kill = mission.robCoords, mission.killCoords
    if mission.solomonCoords then locations.solomon = mission.solomonCoords end
    if stage ~= 'idle' and stage ~= 'completed' then startMissionTimer(mission.remainingSeconds) else stopMissionTimer() end
    if stage == 'rob_target' then
        showTask('Намери мишената и вземи телефона, който принадлежи на Анита.')
        setMissionBlip(missionCoords.rob, Config.Blips.RobTarget.name, Config.Blips.RobTarget.sprite, Config.Blips.RobTarget.colour)
        spawnRobTarget()
    elseif stage == 'return_anita' then
        setMissionBlip(locations.anita, Config.Blips.Anita.name, Config.Blips.Anita.sprite, Config.Blips.Anita.colour)
        showTask('Върни откраднатия телефон на Анита.')
    elseif stage == 'go_solomon' then
        setMissionBlip(locations.solomon, Config.Blips.Solomon.name, Config.Blips.Solomon.sprite, Config.Blips.Solomon.colour)
        showTask('Занеси документите на Соломон.')
    elseif stage == 'kill_target' then
        showTask('Намери мишената, премахни я и вземи черното тефтерче.')
        setMissionBlip(missionCoords.kill, Config.Blips.KillTarget.name, Config.Blips.KillTarget.sprite, Config.Blips.KillTarget.colour)
        spawnKillTarget()
    elseif stage == 'return_solomon' then
        setMissionBlip(locations.solomon, Config.Blips.Solomon.name, Config.Blips.Solomon.sprite, Config.Blips.Solomon.colour)
        showTask('Занеси черното тефтерче на Соломон.')
    else
        removeMissionBlip()
        hideTask()
    end
end

RegisterNetEvent('jd-killar:client:missionExpired', function()
    resetClientMission('Времето за задачата изтече. Работата е прекратена.')
end)

RegisterNetEvent('jd-killar:client:missionReset', function(message)
    resetClientMission(message or 'Задачата беше прекратена.')
end)

CreateThread(function()
    local bootstrap
    while not bootstrap do
        bootstrap = lib.callback.await('jd-killar:server:bootstrap', false)
        if not bootstrap then Wait(1000) end
    end
    locations.anita = bootstrap.anita
    locations.solomon = bootstrap.mission.solomonCoords or bootstrap.solomon
    spawnDealer('anita')
    restoreMission(bootstrap.mission)

    while not stopping do
        Wait(Config.NpcHealthCheckInterval)
        if not dealers.anita or not DoesEntityExist(dealers.anita) then spawnDealer('anita') end
        local needsSolomon = stage == 'go_solomon' or stage == 'kill_target' or stage == 'return_solomon'
        if needsSolomon and (not dealers.solomon or not DoesEntityExist(dealers.solomon)) then spawnDealer('solomon') end
        if not needsSolomon and dealers.solomon then removeDealer('solomon', 'jd-killar:solomon') end
        if stage == 'rob_target' and (not missionPed or not DoesEntityExist(missionPed)) then spawnRobTarget() end
        if stage == 'kill_target' and (not missionPed or not DoesEntityExist(missionPed)) then spawnKillTarget() end
        if Config.FailOnPlayerDeath and stage ~= 'idle' and stage ~= 'completed' and IsEntityDead(PlayerPedId()) and not deathReported then
            deathReported = true
            local response = lib.callback.await('jd-killar:server:failOnDeath', false)
            if response and response.ok then resetClientMission('Умря и задачата беше прекратена.') else deathReported = false end
        elseif not IsEntityDead(PlayerPedId()) then
            deathReported = false
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    stopping = true
    stopMissionTimer()
    cleanupMissionPed()
    removeMissionBlip()
    for name, ped in pairs(dealers) do
        if ped and DoesEntityExist(ped) then
            target:removeLocalEntity(ped, dealerData[name].targetName)
            DeleteEntity(ped)
        end
    end
end)
