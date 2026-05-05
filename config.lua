--[[
    COREX Inventory - Main Configuration
]]

Config = {}
Config.Debug = false

Config.MaxWeight = 200.0

Config.GridWidth = 8
Config.GridHeight = 10

Config.DefaultSize = {w = 1, h = 1}

-- Dropped items expire time (in seconds)
-- 300 = 5 minutes | 1800 = 30 minutes | 3600 = 1 hour
Config.DropExpireTime = 1800

-- Enable/Disable ground item markers
-- true  = Show markers on dropped items (MORE CPU)
-- false = No markers, items still visible (LESS CPU)
Config.EnableMarkers = true

Config.PropSyncRadius = 50.0
Config.MarkerRadius = 15.0
Config.MarkerCloseRange = 5.0
Config.PickupDistance = 3.0
Config.GiveDistance = 5.0
Config.PropSyncInterval = 10000
Config.MarkerCacheInterval = 100

-- Portable vehicle system (ox_target pickup -> inventory item -> deploy)
Config.PortableVehicles = {
    Enabled = true,
    ItemName = 'portable_vehicle',
    DefaultPortable = true,
    PickupDistance = 4.5,
    RegisterDistance = 18.0,
    DeployTimeout = 16000,
    SpawnDistance = 3.8,
    AutoEnterOnDeploy = true,
    ReplacePreviousActive = false
}


-- WEAPON RECOIL SYSTEM

Config.Recoil = {
    Enabled = true,

    ScreenShake = {
        Enabled = true,
        Intensity = 0.08,
        Duration = 70
    },

    WeaponKick = {
        Enabled = true,
        GlobalMultiplier = 2.0,
        RecoverySpeed = 0.05
    },

    Patterns = {
        pistol = {
            vertical = 0.22,
            horizontal = 0.10,
            kickVariation = 0.22,
            recovery = 0.95
        },
        smg = {
            vertical = 0.18,
            horizontal = 0.12,
            kickVariation = 0.28,
            recovery = 0.94
        },
        rifle = {
            vertical = 0.28,
            horizontal = 0.14,
            kickVariation = 0.20,
            recovery = 0.93
        },
        shotgun = {
            vertical = 0.50,
            horizontal = 0.25,
            kickVariation = 0.25,
            recovery = 0.91
        },
        sniper = {
            vertical = 0.65,
            horizontal = 0.18,
            kickVariation = 0.15,
            recovery = 0.89
        }
    },

    AttachmentModifiers = {
        grip = 0.65,
        suppressor = 0.80,
        compensator = 0.60,
        stock = 0.75,
        heavybarrel = 0.70,
        muzzlebrake = 0.68
    }
}
