Config = {
    --
    DropItem = 'money', -- test drop item
    RandomPrice = { min = 1000, max = 3000 }, -- случайни чисти пари
    DropChance = 30, -- test chance %
    -- 
    victimdrop = 'WEAPON_PISTOL', -- test drop item 
    DropChance2 = 1, -- test chance %
    --
    FinishPrice = 8500, -- test price -- чисти 60% мръсни 40%
    
    PoliceJobs = 0,

    MissionCooldown = 20 * 60 * 1000,
    GlobalStartCooldown = 10 * 60 * 1000,
    MissionDuration = 30 * 60 * 1000,
    WarningBeforeEnd = 5 * 60 * 1000,
    CancelCooldown = 5 * 60 * 1000,
    FailOnPlayerDeath = true,
    PedZOffset = 1.0,
    DealerTargetDistance = 2.0,
    DealerSpawnDistance = 120.0,
    TargetInteractionDistance = 1.8,
    NpcHealthCheckInterval = 5000,
    MissionPedSpawnDistance = 120.0,
    RobDuration = 5000,
    SearchDuration = 10000,
    RobSkillCheck = { 'easy', 'easy', { areaSize = 60, speedMultiplier = 2 }, 'easy' },

    Npcs = {
        Anita = { model = 'csb_anita', scenario = 'WORLD_HUMAN_LEANING' },
        Solomon = { model = 'cs_solomon', scenario = 'WORLD_HUMAN_SMOKING_POT' },
        RobTarget = { model = 'a_m_y_busicas_01', scenario = 'WORLD_HUMAN_SMOKING_POT' },
        KillTarget = { model = 'cs_siemonyetarian', weapon = 'WEAPON_PISTOL', armour = 100 }
    },

    Blips = {
        Anita = { name = 'Анита', sprite = 280, colour = 3 },
        Solomon = { name = 'Соломон', sprite = 280, colour = 81 },
        RobTarget = { name = 'Мишена', sprite = 304, colour = 11 },
        KillTarget = { name = 'Жертва', sprite = 303, colour = 1 }
    },

    Security = {
        DealerDistance = 4.0,
        TargetDistance = 5.0,
        TargetLeashDistance = 100.0,
        RateLimit = 1250,
        MinimumStageSeconds = 5
    },
}

Config.PoliceJob = 'police'
