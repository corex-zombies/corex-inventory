--[[
    Portable vehicle persistence:
    ox_target pickup -> inventory item -> deploy in front of player.

    The filename is kept for upgrade compatibility; the implementation is no
    longer bicycle-specific.
]]

local Corex

local function EnsureCore()
    if Corex then return true end
    local ok, core = pcall(function()
        return exports['corex-core']:GetCoreObject()
    end)
    Corex = ok and core or nil
    return Corex ~= nil
end

CreateThread(function()
    repeat
        Wait(200)
        EnsureCore()
    until Corex
end)

local function Notify(msg, typ, duration)
    if EnsureCore() and Corex.Functions and Corex.Functions.Notify then
        Corex.Functions.Notify(msg, typ or 'inform', duration or 4500)
    end
end

RegisterNetEvent('corex-inventory:client:portableVehicleNotify', function(message, typ)
    Notify(message, typ)
end)

RegisterNetEvent('corex-inventory:client:rentalBikeNotify', function(message, typ)
    Notify(message, typ)
end)

local function LoadVehicleModel(model)
    if Corex and Corex.Functions and Corex.Functions.LoadModel then
        return Corex.Functions.LoadModel(model, 5000)
    end

    local hash = GetHashKey(model)
    RequestModel(hash)

    local deadline = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < deadline do
        Wait(50)
    end

    return HasModelLoaded(hash)
end

local function RegisterPortableVehicleNetworked(vehicle)
    CreateThread(function()
        local tries = 0
        while tries < 100 do
            if DoesEntityExist(vehicle) and NetworkGetEntityIsNetworked(vehicle) then
                local netId = NetworkGetNetworkIdFromEntity(vehicle)
                if netId and netId ~= 0 then
                    TriggerServerEvent('corex-inventory:server:finalizePortableVehicle', netId)
                    return
                end
            end

            tries = tries + 1
            Wait(50)
        end

        TriggerServerEvent('corex-inventory:server:portableVehicleDeployAborted')
    end)
end

AddEventHandler('corex-inventory:internal:registerPortableVehicleNet', function(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end
    RegisterPortableVehicleNetworked(vehicle)
end)

AddEventHandler('corex-inventory:internal:registerRentalBikeNet', function(vehicle)
    TriggerEvent('corex-inventory:internal:registerPortableVehicleNet', vehicle)
end)

RegisterNetEvent('corex-inventory:client:deleteVehicleByNetId', function(netId)
    netId = tonumber(netId)
    if not netId then return end

    local veh = NetToVeh(netId)
    if veh and veh ~= 0 and DoesEntityExist(veh) then
        pcall(function()
            exports['corex-inventory']:ClearActiveRentalVehicleIfMatches(veh)
        end)
        SetEntityAsMissionEntity(veh, true, true)
        DeleteVehicle(veh)
    end
end)

local function BuildSpawnPoint(distance)
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    local rad = math.rad(heading)
    local forwardX = -math.sin(rad)
    local forwardY = math.cos(rad)
    local dist = tonumber(distance) or (Config.PortableVehicles and Config.PortableVehicles.SpawnDistance) or 3.8

    return vector4(coords.x + forwardX * dist, coords.y + forwardY * dist, coords.z + 0.35, heading)
end

RegisterNetEvent('corex-inventory:client:spawnPortableVehicleFromItem', function(payload)
    if type(payload) ~= 'table' or type(payload.model) ~= 'string' then
        TriggerServerEvent('corex-inventory:server:portableVehicleDeployAborted')
        return
    end

    local deadline = GetGameTimer() + 10000
    while not EnsureCore() and GetGameTimer() < deadline do
        Wait(100)
    end

    if not Corex then
        TriggerServerEvent('corex-inventory:server:portableVehicleDeployAborted')
        return
    end

    local model = payload.model
    local plate = type(payload.plate) == 'string' and payload.plate or ''

    if not LoadVehicleModel(model) then
        TriggerServerEvent('corex-inventory:server:portableVehicleDeployAborted')
        SetModelAsNoLongerNeeded(GetHashKey(model))
        return
    end

    local spawnPoint = BuildSpawnPoint(payload.spawnDistance)
    local hash = GetHashKey(model)
    local vehicle = CreateVehicle(hash, spawnPoint.x, spawnPoint.y, spawnPoint.z, spawnPoint.w or 0.0, true, false)

    if not vehicle or vehicle == 0 then
        TriggerServerEvent('corex-inventory:server:portableVehicleDeployAborted')
        SetModelAsNoLongerNeeded(hash)
        return
    end

    SetVehicleOnGroundProperly(vehicle)
    SetEntityAsMissionEntity(vehicle, true, true)
    SetVehicleHasBeenOwnedByPlayer(vehicle, true)
    SetVehRadioStation(vehicle, 'OFF')
    SetVehicleDirtLevel(vehicle, 0.0)
    SetVehicleEngineOn(vehicle, false, true, false)

    if plate ~= '' then
        SetVehicleNumberPlateText(vehicle, plate)
    end

    pcall(function()
        exports['corex-inventory']:SetActiveRentalVehicle(vehicle)
    end)

    if Config.PortableVehicles == nil or Config.PortableVehicles.AutoEnterOnDeploy ~= false then
        local ped = PlayerPedId()
        if ped and ped ~= 0 and DoesEntityExist(ped) and not IsPedInAnyVehicle(ped, false) then
            TaskWarpPedIntoVehicle(ped, vehicle, -1)
        end
    end

    SetModelAsNoLongerNeeded(hash)
    Notify((payload.label or 'Vehicle') .. ' deployed.', 'success', 2500)

    TriggerEvent('corex-inventory:internal:registerPortableVehicleNet', vehicle)
end)

RegisterNetEvent('corex-inventory:client:spawnRentalBikeFromItem', function(payload)
    TriggerEvent('corex-inventory:client:spawnPortableVehicleFromItem', payload)
end)

CreateThread(function()
    while GetResourceState('ox_target') ~= 'started' do
        Wait(500)
    end

    exports.ox_target:addGlobalVehicle({
        {
            name = 'corex_pickup_portable_vehicle',
            icon = 'fa-solid fa-box-open',
            label = 'Pick up vehicle',
            distance = 3.0,
            canInteract = function(entity)
                if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
                local ped = PlayerPedId()
                if GetVehiclePedIsIn(ped, false) ~= 0 then return false end
                local st = Entity(entity).state
                return st.corexPortableVehicleOwner ~= nil or st.corexRentalBikeOwner ~= nil
            end,
            onSelect = function(data)
                local netId = NetworkGetNetworkIdFromEntity(data.entity)
                TriggerServerEvent('corex-inventory:server:pickupPortableVehicle', netId)
            end,
        },
    })
end)
