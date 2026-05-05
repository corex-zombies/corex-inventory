--[[
    COREX Inventory - Client Side (v2.0)
    Uses COREX Framework with Player Bridge API
]]

local function DebugPrint(msg)
    if Config and Config.Debug then
        print(msg)
    end
end

DebugPrint('[COREX-INVENTORY] ^5CLIENT SCRIPT LOADING...^0')

local Corex = nil
local isReady = false

local function InitCore()
    local success, core = pcall(function()
        return exports['corex-core']:GetCoreObject()
    end)
    if not success or not core or not core.Functions then return false end
    Corex = core
    return true
end

if not InitCore() then
    AddEventHandler('corex:client:coreReady', function(coreObj)
        if coreObj and coreObj.Functions and not Corex then
            Corex = coreObj
            isReady = true
            DebugPrint('[COREX-INVENTORY] ^2Connected to COREX core^0')
        end
    end)
    CreateThread(function()
        Wait(15000)
        if not Corex then
            DebugPrint('[COREX-INVENTORY] ^1ERROR: Core init timed out^0')
        end
    end)
else
    isReady = true
    DebugPrint('[COREX-INVENTORY] ^2Connected to COREX core^0')
end

local isOpen = false
local isShopOpen = false
local currentShop = nil
local currentShopType = nil
local droppedItems = {}
local spawnedProps = {}
local propVisualData = {}
local PICKUP_DISTANCE = Config.PickupDistance or 3.0
local DEFAULT_PROP = 'prop_med_bag_01b'
local MAX_DROPPED_ITEMS = 500
local activeRentalVehicle = nil

local function GetRarityColor(rarity)
    if not Rarity then return {r = 139, g = 148, b = 158, a = 255} end

    local rarityData = Rarity[rarity or 'common']
    if rarityData and rarityData.rgb then
        return {r = rarityData.rgb[1], g = rarityData.rgb[2], b = rarityData.rgb[3], a = 255}
    end
    return {r = 139, g = 148, b = 158, a = 255}
end

local function GetItemRarity(itemName)
    local itemDef = Items[itemName]
    if itemDef then return itemDef.rarity or 'common' end

    local weaponDef = Weapons[itemName] or Weapons[string.upper(itemName)]
    if weaponDef then return weaponDef.rarity or 'common' end

    local ammoDef = Ammo[itemName]
    if ammoDef then return ammoDef.rarity or 'common' end

    return 'common'
end

local function GetItemDefinition(itemName)
    local itemDef = Items[itemName]
    if itemDef then return itemDef end

    local weaponDef = Weapons[itemName] or Weapons[string.upper(itemName)]
    if weaponDef then return weaponDef end

    local ammoDef = Ammo[itemName]
    if ammoDef then return ammoDef end

    return nil
end

local function IsWeaponItem(itemName)
    if not itemName then return false end
    if Weapons[itemName] or Weapons[string.upper(itemName)] then
        return true
    end
    if string.sub(string.lower(itemName), 1, 7) == 'weapon_' then
        return true
    end
    return false
end

local function GetShopDisplaySize(itemName, itemDef)
    local baseSize = itemDef and itemDef.size or {w = 1, h = 1}
    local width = baseSize.w or 1
    local height = baseSize.h or 1
    local lowerName = string.lower(itemName or '')
    local isAmmo = string.find(lowerName, 'ammo', 1, true) ~= nil

    if isAmmo then
        return {w = math.max(width, 1), h = math.max(height, 2)}
    end

    if IsWeaponItem(itemName) then
        return {w = math.max(width, 2), h = math.max(height, 2)}
    end

    return {w = width, h = height}
end

local function CalculateInventoryWeight(items)
    local totalWeight = 0.0

    for _, item in ipairs(items or {}) do
        local itemDef = GetItemDefinition(item.name)
        if itemDef and itemDef.weight then
            totalWeight = totalWeight + (itemDef.weight * (item.count or 1))
        end
    end

    return totalWeight
end

local function SpawnDropProp(dropId, itemData)
    if not isReady then return end
    if not itemData or not itemData.coords then return end
    if spawnedProps[dropId] then
        if Corex.Functions.DoesEntityExist(spawnedProps[dropId]) then
            return
        end
    end

    local itemDef = GetItemDefinition(itemData.name)
    local propModel = (itemDef and itemDef.prop) or itemData.prop or DEFAULT_PROP
    local coords = vector3(itemData.coords.x, itemData.coords.y, itemData.coords.z)

    local prop = Corex.Functions.SpawnProp(propModel, coords, {
        placeOnGround = true,
        networked = false,
        freeze = true
    })

    if prop then
        spawnedProps[dropId] = prop

        local rarity = GetItemRarity(itemData.name)
        local color = GetRarityColor(rarity)

        propVisualData[dropId] = {
            prop = prop,
            rarity = rarity,
            color = color,
            coords = coords,
            itemName = itemData.name,
            pulsePhase = math.random() * math.pi * 2,
            propCoords = vector3(0, 0, 0)
        }
        local pc = GetEntityCoords(prop)
        if pc then propVisualData[dropId].propCoords = pc end
    end
end

local function DeleteDropProp(dropId)
    if not isReady then return end
    local prop = spawnedProps[dropId]
    if prop then
        Corex.Functions.DeleteProp(prop)
        spawnedProps[dropId] = nil
        propVisualData[dropId] = nil
    end
end

local function DeleteAllProps()
    if not isReady then return end
    for dropId, prop in pairs(spawnedProps) do
        if prop then
            Corex.Functions.DeleteProp(prop)
        end
    end
    spawnedProps = {}
    propVisualData = {}
end

local function SyncAllProps()
    if not isReady then return end
    for dropId, prop in pairs(spawnedProps) do
        if not droppedItems[dropId] then
            Corex.Functions.DeleteProp(prop)
            spawnedProps[dropId] = nil
            propVisualData[dropId] = nil
        end
    end

    local playerCoords = Corex.Functions.GetCoords()
    for dropId, itemData in pairs(droppedItems) do
        if itemData.coords then
            local itemCoords = vector3(itemData.coords.x, itemData.coords.y, itemData.coords.z)
            local dist = #(vector3(playerCoords.x, playerCoords.y, playerCoords.z) - itemCoords)

            if dist < (Config.PropSyncRadius or 50.0) then
                if not spawnedProps[dropId] or not Corex.Functions.DoesEntityExist(spawnedProps[dropId]) then
                    SpawnDropProp(dropId, itemData)
                end
            else
                DeleteDropProp(dropId)
            end
        end
    end
end

local function GetNearbyGroundItems()
    if not isReady then return {} end
    local nearbyItems = {}

    for id, item in pairs(droppedItems) do
        if item.coords then
            local itemCoords = vector3(item.coords.x, item.coords.y, item.coords.z)
            if Corex.Functions.IsNear(itemCoords, PICKUP_DISTANCE) then
                table.insert(nearbyItems, {
                    name = item.name,
                    count = item.count,
                    x = item.gridX or 1,
                    y = item.gridY or 1,
                    slot = id,
                    distance = Corex.Functions.GetDistanceTo(itemCoords)
                })
            end
        end
    end

    return nearbyItems
end

local function OpenInventory(data)
    if isOpen then return end
    isOpen = true

    if not data.isShop and not data.isContainer then
        data.groundItems = GetNearbyGroundItems()
    end

    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'open',
        inventory = data
    })
end

function OpenVehicleShop(shopName)
    if not isReady then
        DebugPrint('^1[COREX-INVENTORY] OpenVehicleShop called but not ready^0')
        return
    end

    local shop = Shops and Shops[shopName]
    if not shop or shop.type ~= 'vehicle' then
        DebugPrint('^1[COREX-INVENTORY] Vehicle shop not found: ' .. tostring(shopName) .. '^0')
        return
    end

    local catalogId = shop.catalogId or 'bike_rental'
    local catalog = Corex.Functions.GetVehicleCatalog and Corex.Functions.GetVehicleCatalog(catalogId)
    if not catalog or type(catalog.vehicles) ~= 'table' or #catalog.vehicles == 0 then
        Corex.Functions.Notify('Vehicle catalog is empty.', 'error', 3000)
        return
    end

    currentShop = shopName
    currentShopType = 'vehicle'
    isShopOpen = true
    isOpen = true

    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'openVehicleShop',
        shopName = shop.label or catalog.label or shopName,
        playerMoney = Corex.Functions.GetMoney('cash'),
        catalog = catalog
    })
end

local function CloseInventory()
    SendNUIMessage({action = 'close'})
    Wait(50)
    SetNuiFocus(false, false)

    isOpen = false
    isShopOpen = false
    currentShop = nil
    currentShopType = nil

    CreateThread(function()
        Wait(100)
        SetNuiFocus(false, false)
        DebugPrint('[COREX-INVENTORY] ^2Inventory fully closed, focus released^0')
    end)
end

local function UpdateGroundItemsUI()
    if not isOpen then return end
    if isShopOpen then return end

    SendNUIMessage({
        action = 'updateGround',
        items = GetNearbyGroundItems()
    })
end

RegisterCommand('inventory', function()
    if not isReady then
        DebugPrint('[COREX-INVENTORY] ^1Please wait for initialization...^0')
        return
    end
    if isOpen then
        CloseInventory()
    else
        TriggerServerEvent('corex-inventory:server:open')
    end
end, false)

RegisterKeyMapping('inventory', 'Open Inventory', 'keyboard', 'TAB')

CreateThread(function()
    while true do
        if isOpen then
            Wait(0)
            DisableControlAction(0, 200, true)
            DisableControlAction(0, 199, true)

            if IsDisabledControlJustPressed(0, 200) or IsDisabledControlJustPressed(0, 199) then
                CloseInventory()
            end
        else
            Wait(200)
        end
    end
end)

-- Previous thread polled SetNuiFocus(false,false) every 500ms forever.
-- Focus is already released in CloseInventory; the constant reassertion
-- was pure overhead and spammed the NUI focus stack. Removed.

RegisterNetEvent('corex-inventory:client:open', function(data)
    OpenInventory(data)
end)

RegisterNetEvent('corex-inventory:client:update', function(data)
    if isOpen then
        if not isShopOpen then
            data.groundItems = GetNearbyGroundItems()
        end
        SendNUIMessage({
            action = 'update',
            inventory = data
        })
    end
end)

RegisterNetEvent('corex-inventory:client:syncDroppedItems', function(items)
    DeleteAllProps()
    droppedItems = items or {}
    SyncAllProps()
    UpdateGroundItemsUI()
end)

local MAX_DROPPED_ITEMS_CLIENT = 500
RegisterNetEvent('corex-inventory:client:itemDropped', function(dropId, itemData)
    local dropCount = 0
    for _ in pairs(droppedItems) do dropCount = dropCount + 1 end

    if dropCount >= MAX_DROPPED_ITEMS_CLIENT then
        local oldestId, oldestAt = nil, nil
        for id, data in pairs(droppedItems) do
            local t = (data and data.droppedAt) or 0
            if not oldestAt or t < oldestAt then
                oldestAt = t
                oldestId = id
            end
        end
        if oldestId then
            DeleteDropProp(oldestId)
            droppedItems[oldestId] = nil
        end
    end

    droppedItems[dropId] = itemData
    SpawnDropProp(dropId, itemData)
    UpdateGroundItemsUI()
end)

RegisterNetEvent('corex-inventory:client:itemPickedUp', function(dropId)
    DeleteDropProp(dropId)
    droppedItems[dropId] = nil
    UpdateGroundItemsUI()
end)

RegisterNetEvent('corex-inventory:client:useItem', function(itemName, itemData)
    if IsWeaponItem(itemName) then
        TriggerEvent('corex-inventory:internal:equipWeapon', itemName, itemData or {})
        return
    end

    if itemName == 'portable_vehicle' or itemName == 'rental_bicycle' then
        pcall(CloseInventory)
        TriggerServerEvent('corex-inventory:server:deployPortableVehicleFromItem', (itemData or {}).slot, itemName)
        return
    end

    local ammoDef = Ammo[itemName]
    if ammoDef then
        TriggerEvent('corex-inventory:internal:addAmmo', itemName, itemData or {})
        return
    end

    -- Item effects handled by corex-survival
end)

-- TEST: Simple callback to verify NUI is working
RegisterNUICallback('test', function(data, cb)
    DebugPrint('[COREX-INVENTORY] ^2TEST CALLBACK RECEIVED!^0')
    cb('ok')
end)

RegisterNUICallback('close', function(data, cb)
    pcall(CloseInventory)
    cb('ok')
end)

RegisterNUICallback('useItem', function(data, cb)
    TriggerServerEvent('corex-inventory:server:use', data.name, data.slot)
    cb('ok')
end)

RegisterNUICallback('moveItem', function(data, cb)
    if data.slotId and data.x and data.y then
        TriggerServerEvent('corex-inventory:server:move', data.slotId, data.x, data.y)
    end
    cb('ok')
end)

RegisterNUICallback('dropItem', function(data, cb)
    if not isReady then cb('not_ready') return end

    local playerCoords = Corex.Functions.GetCoords()
    local gx = tonumber(data.x) or 1
    local gy = tonumber(data.y) or 1
    gx = math.max(1, math.min(8, math.floor(gx)))
    gy = math.max(1, math.min(10, math.floor(gy)))
    local cnt = tonumber(data.count) or 1
    cnt = math.max(1, math.min(9999, math.floor(cnt)))

    TriggerServerEvent('corex-inventory:server:drop', data.name, cnt, data.slot, {
        x = playerCoords.x,
        y = playerCoords.y,
        z = playerCoords.z,
        gridX = gx,
        gridY = gy
    })
    cb('ok')
end)

RegisterNUICallback('pickupItem', function(data, cb)
    if data.groundSlot then
        local x = math.max(1, math.min(8, math.floor(tonumber(data.x) or 1)))
        local y = math.max(1, math.min(10, math.floor(tonumber(data.y) or 1)))
        TriggerServerEvent('corex-inventory:server:pickup', data.groundSlot, x, y)
    end
    cb('ok')
end)

RegisterNetEvent('corex-inventory:client:weaponDropConfirmed', function(weaponName)
    local ped = Corex.Functions.GetPed()
    local hash = GetHashKey(weaponName)
    if HasPedGotWeapon(ped, hash, false) then
        RemoveWeaponFromPed(ped, hash)
        TriggerEvent('corex-inventory:internal:weaponDropped', weaponName)
    end
end)

local GIVE_DISTANCE = Config.GiveDistance or 5.0

local function GetNearbyPlayers()
    if not isReady then return {} end
    local players = Corex.Functions.GetNearbyPlayers and Corex.Functions.GetNearbyPlayers(GIVE_DISTANCE) or {}
    table.sort(players, function(a, b) return a.distance < b.distance end)

    local nearbyPlayers = {}
    for _, player in ipairs(players) do
        nearbyPlayers[#nearbyPlayers + 1] = {
            id = player.serverId,
            name = player.name,
            distance = player.distance
        }
    end

    return nearbyPlayers
end

RegisterNUICallback('getNearbyPlayers', function(_, cb)
    if not isReady then cb('not_ready') return end
    local players = GetNearbyPlayers()

    SendNUIMessage({
        action = 'updateNearbyPlayers',
        players = players
    })

    cb('ok')
end)

RegisterNUICallback('giveItem', function(data, cb)
    if data.targetPlayer and data.name and data.slot then
        TriggerServerEvent('corex-inventory:server:give', data.targetPlayer, data.name, data.count or 1, data.slot)
    end
    cb('ok')
end)

AddEventHandler('playerSpawned', function()
    TriggerServerEvent('corex-inventory:server:load')
    TriggerServerEvent('corex-inventory:server:requestDroppedItems')
end)

CreateThread(function()
    Wait(5000)
    TriggerServerEvent('corex-inventory:server:load')
    TriggerServerEvent('corex-inventory:server:requestDroppedItems')
end)

-- Controls disabled via NUI focus, no constant thread needed
-- ESC key handled via NUI callback

-- NOTE: Removed separate SyncAllProps loop - marker system handles prop syncing
-- This prevents the flickering caused by two loops fighting over prop visibility

-- ==================================================================
-- OPTIMIZED MARKER SYSTEM
-- - Uses direct propVisualData instead of rebuilding nearbyProps array
-- - Lower framerate (30fps) for markers to reduce CPU usage
-- - Immediate cleanup on pickup via event
-- ==================================================================

local markerAnimPhase = 0

CreateThread(function()
    if not Config.EnableMarkers then return end

    -- Wait for Corex to be ready
    while not isReady or not Corex or not Corex.Functions do
        Wait(500)
    end

    local floor = math.floor
    local sin = math.sin
    local GetEntityCoords = GetEntityCoords
    local DoesEntityExist = DoesEntityExist
    local DrawMarker = DrawMarker

    -- Cached values updated less frequently
    local cachedPlayerX, cachedPlayerY, cachedPlayerZ = 0, 0, 0
    local lastCacheUpdate = 0
    local CACHE_INTERVAL = Config.MarkerCacheInterval or 100

    while true do
        -- Quick check: any props at all?
        local hasProps = false
        for _ in pairs(propVisualData) do
            hasProps = true
            break
        end

        if not hasProps then
            Wait(1000) -- Sleep long when no dropped items
            goto continue
        end

        -- Update cached player position periodically (not every frame)
        local now = GetGameTimer()
        if now - lastCacheUpdate > CACHE_INTERVAL then
            local playerCoords = Corex.Functions.GetCoords()
            if playerCoords then
                cachedPlayerX, cachedPlayerY, cachedPlayerZ = playerCoords.x, playerCoords.y, playerCoords.z
            end
            lastCacheUpdate = now
        end

        local hasAnyMarker = false

        -- Update animation phase
        markerAnimPhase = (markerAnimPhase + 0.03)
        if markerAnimPhase > 6.28 then markerAnimPhase = 0 end

        -- Draw markers
        for dropId, data in pairs(propVisualData) do
            local prop = data.prop

            if prop and DoesEntityExist(prop) then
                local c = data.propCoords
                local dx, dy = c.x - cachedPlayerX, c.y - cachedPlayerY
                local distSq = dx*dx + dy*dy -- 2D distance is faster

                if distSq < (Config.MarkerRadius * Config.MarkerRadius) then
                    hasAnyMarker = true
                    local isClose = distSq < (Config.MarkerCloseRange * Config.MarkerCloseRange)
                    local color = data.color or {r=255, g=100, b=100}
                    local rarity = data.rarity

                    local alpha = isClose and 200 or 150
                    local scale = isClose and 0.5 or 0.35

                    if rarity == 'legendary' or rarity == 'mythic' then
                        alpha = alpha + floor(20 * (sin(markerAnimPhase) + 1) * 0.5)
                    end

                    DrawMarker(25, c.x, c.y, c.z + 0.05,
                        0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                        scale, scale, 0.1,
                        color.r, color.g, color.b, alpha,
                        false, false, 0, false, nil, nil, false)

                    if isClose and (rarity == 'rare' or rarity == 'epic' or rarity == 'legendary' or rarity == 'mythic') then
                        DrawMarker(0, c.x, c.y, c.z - 0.5,
                            0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                            0.03, 0.03, 0.8,
                            color.r, color.g, color.b, floor(alpha * 0.2),
                            false, false, 0, false, nil, nil, false)
                    end
                end
            end
        end

        if hasAnyMarker then
            Wait(0) -- Required for smooth markers
        else
            Wait(500) -- No nearby markers
        end

        ::continue::
    end
end)

-- Prop sync thread (runs much less frequently)
CreateThread(function()
    while not isReady do Wait(1000) end

    while true do
        Wait(Config.PropSyncInterval or 10000)
        SyncAllProps()
    end
end)

-- [SECURITY] Client /giveitem removed. The server NetEvent it fed into
-- was exploitable (CRIT-01). Admins should use the server-side /giveitem
-- which is properly ACE-gated (command.giveitem permission required).
-- /cleanprops is a dev helper - gated behind Config.Debug below.

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    DeleteAllProps()
end)

if Config and Config.Debug then
    RegisterCommand('cleanprops', function()
        DeleteAllProps()
        droppedItems = {}
        TriggerServerEvent('corex-inventory:server:requestDroppedItems')
        DebugPrint('[INVENTORY] All props cleaned and resynced')
    end, false)
end

local playerInventory = {}

local function GetAllItemsData()
    local allItems = {}
    for k, v in pairs(Items or {}) do allItems[k] = v end
    for k, v in pairs(Weapons or {}) do allItems[k] = v end
    for k, v in pairs(Ammo or {}) do allItems[k] = v end
    return allItems
end

local function RefreshHotbar()
    SendNUIMessage({
        action = 'updateHotbar',
        inventory = {
            items = playerInventory,
            itemsData = GetAllItemsData()
        }
    })
end

RegisterNetEvent('corex-inventory:client:syncInventory', function(inventory)
    playerInventory = inventory or {}
    RefreshHotbar()
end)

RegisterNetEvent('corex-inventory:client:applyLocalItemMetadata', function(slotId, metadata)
    if slotId == nil or type(metadata) ~= 'table' then return end

    for _, item in ipairs(playerInventory) do
        if tostring(item.slot) == tostring(slotId) then
            item.metadata = item.metadata or {}
            for key, value in pairs(metadata) do
                item.metadata[key] = value
            end
            if metadata.ammo ~= nil then
                item.ammo = metadata.ammo
            end
            break
        end
    end

    RefreshHotbar()
end)

local function UseQuickSlot(slotNum)
    if isOpen then return end
    if slotNum < 1 or slotNum > 6 then return end

    local coveredSlots = {}
    local anchorSlots = {}

    for _, item in ipairs(playerInventory) do
        local itemDef = Items[item.name] or Weapons[item.name] or { size = { w = 1, h = 1 } }
        local w = itemDef.size and itemDef.size.w or 1
        local h = itemDef.size and itemDef.size.h or 1
        local anchorKey = item.x .. ',' .. item.y
        anchorSlots[anchorKey] = item

        for row = item.y, item.y + h - 1 do
            for col = item.x, item.x + w - 1 do
                local key = col .. ',' .. row
                if key ~= anchorKey then
                    coveredSlots[key] = true
                end
            end
        end
    end

    local currentHotkey = 1
    local hotkeyMapping = {}
    local gridCols = Config.GridWidth or 8
    local gridRows = Config.GridHeight or 10

    for row = 1, gridRows do
        if currentHotkey > 6 then break end
        for col = 1, gridCols do
            if currentHotkey > 6 then break end
            local key = col .. ',' .. row

            if coveredSlots[key] then
            elseif anchorSlots[key] then
                hotkeyMapping[currentHotkey] = { x = col, y = row, item = anchorSlots[key] }
                currentHotkey = currentHotkey + 1
            else
                hotkeyMapping[currentHotkey] = { x = col, y = row, item = nil }
                currentHotkey = currentHotkey + 1
            end
        end
    end

    local mapping = hotkeyMapping[slotNum]
    if mapping and mapping.item then
        TriggerEvent('corex-inventory:client:useItem', mapping.item.name, mapping.item)
    end
end

RegisterCommand('+quickslot1', function() UseQuickSlot(1) end, false)
RegisterCommand('+quickslot2', function() UseQuickSlot(2) end, false)
RegisterCommand('+quickslot3', function() UseQuickSlot(3) end, false)
RegisterCommand('+quickslot4', function() UseQuickSlot(4) end, false)
RegisterCommand('+quickslot5', function() UseQuickSlot(5) end, false)
RegisterCommand('+quickslot6', function() UseQuickSlot(6) end, false)

RegisterCommand('-quickslot1', function() end, false)
RegisterCommand('-quickslot2', function() end, false)
RegisterCommand('-quickslot3', function() end, false)
RegisterCommand('-quickslot4', function() end, false)
RegisterCommand('-quickslot5', function() end, false)
RegisterCommand('-quickslot6', function() end, false)

RegisterKeyMapping('+quickslot1', 'Quick Slot 1', 'keyboard', '1')
RegisterKeyMapping('+quickslot2', 'Quick Slot 2', 'keyboard', '2')
RegisterKeyMapping('+quickslot3', 'Quick Slot 3', 'keyboard', '3')
RegisterKeyMapping('+quickslot4', 'Quick Slot 4', 'keyboard', '4')
RegisterKeyMapping('+quickslot5', 'Quick Slot 5', 'keyboard', '5')
RegisterKeyMapping('+quickslot6', 'Quick Slot 6', 'keyboard', '6')

CreateThread(function()
    local weaponWheelControls = { 37, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 261, 262 }
    while true do
        for i = 1, #weaponWheelControls do
            DisableControlAction(0, weaponWheelControls[i], true)
        end
        Wait(0)
    end
end)

function OpenShop(shopName)
    if not isReady then
        DebugPrint('^1[COREX-INVENTORY] OpenShop called but not ready^0')
        return
    end

    if not Shops then
        DebugPrint('^1[COREX-INVENTORY] ERROR: Shops table is nil! Check shared/shops.lua^0')
        return
    end

    if not Shops[shopName] then
        DebugPrint('^1[COREX-INVENTORY] Shop not found: ' .. tostring(shopName) .. '^0')
        return
    end

    local shop = Shops[shopName]
    currentShop = shopName
    currentShopType = 'inventory'
    isShopOpen = true

    local shopItems = {}
    local slotCounter = 1
    local currentX = 1
    local currentY = 1
    local gridCols = 8

    for _, itemConfig in ipairs(shop.items) do
        local itemDef = GetItemDefinition(itemConfig.name)

        if itemDef then
            local size = GetShopDisplaySize(itemConfig.name, itemDef)
            local itemWidth = size.w or 1
            local itemHeight = size.h or 1

            -- Check if item fits in current row, if not move to next row
            if currentX + itemWidth - 1 > gridCols then
                currentX = 1
                currentY = currentY + 1
            end

            table.insert(shopItems, {
                name = itemConfig.name,
                count = itemConfig.amount or 1,
                slot = 'shop_' .. slotCounter,
                x = currentX,
                y = currentY,
                displaySize = size,
                isShopItem = true,
                price = itemConfig.price,
                currency = itemConfig.currency or 'cash'
            })

            currentX = currentX + itemWidth
            if currentX > gridCols then
                currentX = 1
                currentY = currentY + itemHeight
            end

            slotCounter = slotCounter + 1
        end
    end

    local playerMoney = Corex.Functions.GetMoney('cash')
    local currentInventory = playerInventory or {}
    local currentWeight = CalculateInventoryWeight(currentInventory)

    local allItems = GetAllItemsData()

    local inventoryData = {
        items = currentInventory,
        weight = currentWeight,
        maxWeight = Config.MaxWeight or 200,
        grid = {w = 8, h = 10},
        itemsData = allItems,
        groundItems = shopItems,
        isShop = true,
        shopName = shop.label or shopName,
        playerMoney = playerMoney
    }

    OpenInventory(inventoryData)
end

function CloseShop()
    currentShop = nil
    isShopOpen = false
    CloseInventory()
end

RegisterNUICallback('purchaseShopItem', function(data, cb)
    if not currentShop then
        cb({success = false, message = "No shop open"})
        return
    end

    if type(data.itemName) ~= 'string' or #data.itemName == 0 or #data.itemName > 100 then
        cb({success = false, message = "Invalid item"})
        return
    end

    local amount = tonumber(data.amount) or 1
    amount = math.max(1, math.min(999, math.floor(amount)))

    TriggerServerEvent('corex-inventory:server:purchaseShopItem', currentShop, data.itemName, amount)
    cb({success = true})
end)

RegisterNUICallback('purchaseVehicleShopItem', function(data, cb)
    if currentShopType ~= 'vehicle' or not currentShop then
        cb({success = false, message = 'No vehicle shop open'})
        return
    end

    if type(data.model) ~= 'string' or #data.model == 0 or #data.model > 64 then
        cb({success = false, message = 'Invalid vehicle'})
        return
    end

    TriggerServerEvent('corex-inventory:server:purchaseVehicleShopItem', currentShop, data.model)
    cb({success = true})
end)

RegisterNetEvent('corex-inventory:client:shopPurchaseResult', function(success, message, newMoney)
    if success then
        Corex.Functions.Notify(message, 'success', 3000)

        if isShopOpen and currentShop then
            local shopToReopen = currentShop
            CloseShop()
            Wait(100)
            OpenShop(shopToReopen)
        end
    else
        Corex.Functions.Notify(message, 'error', 3000)
    end
end)

RegisterNetEvent('corex-inventory:client:vehiclePurchaseResult', function(success, message, newMoney)
    Corex.Functions.Notify(message, success and 'success' or 'error', 3500)

    if isOpen and isShopOpen and currentShopType == 'vehicle' then
        SendNUIMessage({
            action = 'updateVehicleShopMoney',
            playerMoney = newMoney or Corex.Functions.GetMoney('cash')
        })
    end
end)

local function LoadModelForVehicleShop(model)
    if Corex and Corex.Functions and Corex.Functions.LoadModel then
        return Corex.Functions.LoadModel(model, 5000)
    end

    local hash = type(model) == 'string' and GetHashKey(model) or model
    RequestModel(hash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do
        Wait(50)
    end
    return HasModelLoaded(hash)
end

local function FindVehicleShopSpawnPoint(baseSpawn)
    if not baseSpawn or baseSpawn.x == nil or baseSpawn.y == nil or baseSpawn.z == nil then
        return nil
    end

    local heading = tonumber(baseSpawn.w) or 0.0
    local candidates = {
        vec3(baseSpawn.x, baseSpawn.y, baseSpawn.z + 0.35),
        GetOffsetFromCoordAndHeadingInWorldCoords(baseSpawn.x, baseSpawn.y, baseSpawn.z, heading, 3.0, 0.0, 0.35),
        GetOffsetFromCoordAndHeadingInWorldCoords(baseSpawn.x, baseSpawn.y, baseSpawn.z, heading, 0.0, 2.2, 0.35),
        GetOffsetFromCoordAndHeadingInWorldCoords(baseSpawn.x, baseSpawn.y, baseSpawn.z, heading, 0.0, -2.2, 0.35)
    }

    for _, candidate in ipairs(candidates) do
        if not IsAnyVehicleNearPoint(candidate.x, candidate.y, candidate.z, 1.8) then
            return vector4(candidate.x, candidate.y, candidate.z, heading)
        end
    end

    local first = candidates[1]
    return vector4(first.x, first.y, first.z, heading)
end

RegisterNetEvent('corex-inventory:client:spawnPurchasedVehicle', function(payload)
    if type(payload) ~= 'table' or type(payload.model) ~= 'string' then
        return
    end

    local shopName = payload.shopName
    local vehicleDef = Corex.Functions.GetVehicleDefinition and Corex.Functions.GetVehicleDefinition(payload.catalogId, payload.model)
    local label = (vehicleDef and vehicleDef.label) or payload.model

    if not LoadModelForVehicleShop(payload.model) then
        TriggerServerEvent('corex-inventory:server:vehicleSpawnFailed', shopName, payload.model, 'model_load_failed')
        return
    end

    local spawnPoint = FindVehicleShopSpawnPoint(payload.spawnPoint or {})
    if not spawnPoint then
        TriggerServerEvent('corex-inventory:server:vehicleSpawnFailed', shopName, payload.model, 'spawn_point_invalid')
        return
    end

    local hash = GetHashKey(payload.model)
    local vehicle = CreateVehicle(hash, spawnPoint.x, spawnPoint.y, spawnPoint.z, spawnPoint.w or 0.0, true, false)

    if not vehicle or vehicle == 0 then
        TriggerServerEvent('corex-inventory:server:vehicleSpawnFailed', shopName, payload.model, 'create_vehicle_failed')
        return
    end

    SetVehicleOnGroundProperly(vehicle)
    SetEntityAsMissionEntity(vehicle, true, true)
    SetVehicleHasBeenOwnedByPlayer(vehicle, true)
    SetVehRadioStation(vehicle, 'OFF')
    SetVehicleDirtLevel(vehicle, 0.0)
    SetVehicleEngineOn(vehicle, false, true, false)

    if type(payload.plate) == 'string' then
        SetVehicleNumberPlateText(vehicle, payload.plate)
    end

    local replaceActive = Config.PortableVehicles and Config.PortableVehicles.ReplacePreviousActive == true
    if replaceActive and activeRentalVehicle and DoesEntityExist(activeRentalVehicle) and activeRentalVehicle ~= vehicle then
        SetEntityAsMissionEntity(activeRentalVehicle, true, true)
        DeleteVehicle(activeRentalVehicle)
    end
    activeRentalVehicle = vehicle

    local ped = PlayerPedId()
    if ped and ped ~= 0 and DoesEntityExist(ped) and not IsPedInAnyVehicle(ped, false) then
        TaskWarpPedIntoVehicle(ped, vehicle, -1)
    end

    SetModelAsNoLongerNeeded(hash)
    TriggerServerEvent('corex-inventory:server:vehicleSpawnSucceeded', shopName, payload.model)
    Corex.Functions.Notify(label .. ' is ready.', 'success', 2500)

    TriggerEvent('corex-inventory:internal:registerPortableVehicleNet', vehicle)
end)

exports('OpenShop', OpenShop)
exports('CloseShop', CloseShop)

exports('SetActiveRentalVehicle', function(vehicle)
    local replaceActive = Config.PortableVehicles and Config.PortableVehicles.ReplacePreviousActive == true
    if replaceActive and activeRentalVehicle and activeRentalVehicle ~= vehicle and DoesEntityExist(activeRentalVehicle) then
        SetEntityAsMissionEntity(activeRentalVehicle, true, true)
        DeleteVehicle(activeRentalVehicle)
    end
    activeRentalVehicle = vehicle
end)

exports('ClearActiveRentalVehicleIfMatches', function(entity)
    if not entity or entity == 0 then return end
    if activeRentalVehicle == entity then
        activeRentalVehicle = nil
    end
end)

-- ========== LOOT CONTAINER MODE ==========

local isContainerOpen = false
local currentContainerId = nil

RegisterNetEvent('corex-inventory:client:openLootContainer', function(containerId, items, containerLabel, revealDelay)
    if not isReady then return end
    if isOpen then return end

    local allItems = GetAllItemsData()

    local currentInventory = playerInventory or {}
    local currentWeight = CalculateInventoryWeight(currentInventory)

    local inventoryData = {
        items = currentInventory,
        weight = currentWeight,
        maxWeight = Config.MaxWeight or 200,
        grid = {w = Config.GridWidth or 8, h = Config.GridHeight or 10},
        itemsData = allItems,
        groundItems = {},
        isContainer = true
    }

    OpenInventory(inventoryData)
    isContainerOpen = true
    currentContainerId = containerId

    SendNUIMessage({
        action = 'openLootContainer',
        containerId = containerId,
        containerName = containerLabel or 'Loot Container',
        items = items or {},
        revealDelay = revealDelay or 1800
    })
end)

RegisterNUICallback('takeLootItem', function(data, cb)
    if data.containerId and data.itemIndex ~= nil then
        TriggerServerEvent('corex-loot:server:takeItem', data.containerId, data.itemIndex)
    end
    cb('ok')
end)

RegisterNUICallback('closeLootContainer', function(data, cb)
    if data.containerId then
        TriggerServerEvent('corex-loot:server:closeContainer', data.containerId)
    end
    TriggerEvent('corex-loot:client:containerClosed', data.containerId)
    isContainerOpen = false
    currentContainerId = nil
    cb('ok')
end)

DebugPrint('[COREX-INVENTORY] ^5CLIENT SCRIPT FULLY LOADED^0')
