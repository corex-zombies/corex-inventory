--[[
    COREX Inventory - Server Side (v2.0)
    Tetris Grid System with Ground Items Support
    Functional Lua | No OOP | Zombie Survival Optimized
]]

local Inventories = {}
local DroppedItems = {}
local PendingVehiclePurchases = {}
--- Deployed rental bikes: finalize plate/model before ox_target pickup works
local PendingBikeRegistration = {}
--- If folding back to item fails mid-deploy, restore this metadata to inventory
local PendingBikeRefund = {}
local DeployRefundToken = {}
local dropIdCounter = 0
--- Anti-spam for bicycle pickup (no TrySetBusy: players often stay "busy" from other flows).
local LastRentalBikePickupAttempt = {}
local slotCounter = 0
local BagInventories = {}  -- [bagId] = {items, weight, maxWeight, gridW, gridH, isDirty}
local BagViewers     = {}  -- [bagId] = src (who is currently viewing this bag)

local function ShallowCopy(tbl)
    if type(tbl) ~= 'table' then
        return {}
    end

    local copy = {}
    for key, value in pairs(tbl) do
        copy[key] = value
    end
    return copy
end

local function NextSlotId()
    slotCounter = slotCounter + 1
    return tostring(GetGameTimer()) .. '-' .. slotCounter
end

local function NormalizeVehicleKey(value)
    if type(value) ~= 'string' then return nil end
    return string.lower(value)
end

local function GenerateRentalPlate()
    return ('CX%04d'):format(math.random(0, 9999))
end

local function NormalizePlate(plate)
    if type(plate) ~= 'string' then return '' end
    return (plate:gsub('^%s+', ''):gsub('%s+$', ''))
end

local function PlatesMatch(a, b)
    return NormalizePlate(a):upper() == NormalizePlate(b):upper()
end

local function GetVehicleCatalog(catalogId)
    local ok, catalog = pcall(function()
        return exports['corex-core']:GetVehicleCatalog(catalogId)
    end)
    return ok and catalog or nil
end

local function GetVehicleDefinition(catalogId, model)
    local ok, vehicle = pcall(function()
        return exports['corex-core']:GetVehicleDefinition(catalogId, model)
    end)
    return ok and vehicle or nil
end

local function IsBikeRentalModel(modelKey)
    local key = NormalizeVehicleKey(modelKey)
    if not key then return false end
    return GetVehicleDefinition('bike_rental', key) ~= nil
end

---Server-safe: GetVehicleClass is client-only; whitelist hashes from bike_rental catalog.
local function IsBikeRentalModelHash(modelHash)
    if type(modelHash) ~= 'number' then return false end
    local catalog = GetVehicleCatalog('bike_rental')
    if not catalog or type(catalog.vehicles) ~= 'table' then return false end
    for _, vehicle in ipairs(catalog.vehicles) do
        local m = vehicle.model
        if type(m) == 'string' and GetHashKey(m) == modelHash then
            return true
        end
    end
    return false
end

local function GetPortableVehicleItemName(catalog, vehicleDef)
    if vehicleDef and type(vehicleDef.inventoryItem) == 'string' and vehicleDef.inventoryItem ~= '' then
        return vehicleDef.inventoryItem
    end

    if catalog and type(catalog.inventoryItem) == 'string' and catalog.inventoryItem ~= '' then
        return catalog.inventoryItem
    end

    return (Config.PortableVehicles and Config.PortableVehicles.ItemName) or 'portable_vehicle'
end

local function IsPortableVehicleDefinition(catalog, vehicleDef)
    if not vehicleDef then return false end
    if Config.PortableVehicles and Config.PortableVehicles.Enabled == false then return false end
    if vehicleDef.portable == false then return false end
    if catalog and catalog.portable == false then return false end

    local defaultPortable = true
    if Config.PortableVehicles and Config.PortableVehicles.DefaultPortable ~= nil then
        defaultPortable = Config.PortableVehicles.DefaultPortable == true
    end

    return vehicleDef.portable == true or (catalog and catalog.portable == true) or defaultPortable
end

local function GetPortableVehicleDefinition(catalogId, model)
    local catalogKey = NormalizeVehicleKey(catalogId or 'bike_rental')
    local modelKey = NormalizeVehicleKey(model)
    if not catalogKey or not modelKey then return nil, nil, nil end

    local catalog = GetVehicleCatalog(catalogKey)
    local vehicleDef = GetVehicleDefinition(catalogKey, modelKey)
    if not IsPortableVehicleDefinition(catalog, vehicleDef) then
        return nil, nil, nil
    end

    return catalog, vehicleDef, catalogKey
end

local function IsPortableVehicleModel(catalogId, model)
    local catalog, vehicleDef = GetPortableVehicleDefinition(catalogId, model)
    return catalog ~= nil and vehicleDef ~= nil
end

local function IsPortableVehicleModelHash(catalogId, modelHash)
    if type(modelHash) ~= 'number' then return false end

    local catalog = GetVehicleCatalog(catalogId or 'bike_rental')
    if not catalog or type(catalog.vehicles) ~= 'table' then return false end

    for _, vehicle in ipairs(catalog.vehicles) do
        local m = vehicle.model
        if type(m) == 'string' and GetHashKey(m) == modelHash and IsPortableVehicleDefinition(catalog, vehicle) then
            return true, NormalizeVehicleKey(m), vehicle, catalog
        end
    end

    return false
end

Items = Items or {}
Weapons = Weapons or {}
Ammo = Ammo or {}

-- -------------------------------------------------
-- INTERNAL HELPERS (No COREX wrapper caching)
-- -------------------------------------------------

---Get player using corex-core export
---@param src number
---@return table|nil
local function GetPlayer(src)
    local success, player = pcall(function()
        return exports['corex-core']:GetPlayer(src)
    end)
    return success and player or nil
end

---Check if player is busy (Action Lock)
---@param src number
---@return boolean
local function IsBusy(src)
    local success, busy = pcall(function()
        return exports['corex-core']:IsBusy(src)
    end)
    return success and busy or false
end

---Set player busy state (Action Lock)
---@param src number
---@param state boolean
local function SetBusy(src, state)
    pcall(function()
        exports['corex-core']:SetBusy(src, state)
    end)
end

---Try to lock player action state in one step
---@param src number
---@return boolean
local function TrySetBusy(src)
    local success, locked = pcall(function()
        return exports['corex-core']:TrySetBusy(src)
    end)

    if success then
        return locked
    end

    if IsBusy(src) then
        return false
    end

    SetBusy(src, true)
    return true
end

---Clear player busy state
---@param src number
local function ClearBusy(src)
    pcall(function()
        exports['corex-core']:ClearBusy(src)
    end)
end

---Check whether two players are close enough for direct interaction
---@param src number
---@param targetSrc number
---@param maxDistance number|nil
---@return boolean
local function IsNearbyPlayer(src, targetSrc, maxDistance)
    local success, nearby = pcall(function()
        return exports['corex-core']:GetNearbyPlayers(src, maxDistance or 5.0)
    end)

    return success and type(nearby) == 'table' and nearby[targetSrc] ~= nil
end

local function IsPlayerNearCoords(src, coords, maxDistance)
    if not coords or coords.x == nil or coords.y == nil or coords.z == nil then
        return false
    end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end

    local playerCoords = GetEntityCoords(ped)
    if not playerCoords then return false end

    local cx, cy, cz = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z)
    if not cx or not cy or not cz then return false end

    local maxDist = tonumber(maxDistance) or 3.0
    local dx = playerCoords.x - cx
    local dy = playerCoords.y - cy
    local dz = playerCoords.z - cz

    return (dx * dx + dy * dy + dz * dz) <= (maxDist * maxDist)
end

local function IsPlayerNearShop(src, shop)
    if type(shop) ~= 'table' then return false end

    local npc = shop.npc or {}
    local coords = npc.coords or shop.coords or shop.location
    if not coords then return false end

    local interactDistance = tonumber(npc.interactDistance or shop.interactDistance) or 2.5
    return IsPlayerNearCoords(src, coords, interactDistance + 2.0)
end

---Debug logging
---@param level string
---@param msg string
local function GetAllItemsData()
    local all = {}
    for k, v in pairs(Items or {}) do all[k] = v end
    for k, v in pairs(Weapons or {}) do all[k] = v end
    for k, v in pairs(Ammo or {}) do all[k] = v end
    return all
end

local function Debug(level, msg)
    if not Config.Debug and level ~= 'Error' then return end
    local colors = { Error = '^1', Warn = '^3', Info = '^2', Verbose = '^5' }
    print((colors[level] or '^7') .. '[COREX-INVENTORY] ' .. msg .. '^0')
end

-- Initialize DB table on resource start
CreateThread(function()
    Wait(2000) -- Wait for oxmysql

    exports.oxmysql:execute([[
        CREATE TABLE IF NOT EXISTS `inventories` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `identifier` VARCHAR(60) NOT NULL,
            `inventory_type` VARCHAR(50) NOT NULL DEFAULT 'player',
            `inventory_id` VARCHAR(60) NOT NULL,
            `items` LONGTEXT DEFAULT '[]',
            `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            `hotbar` LONGTEXT DEFAULT '{}',
            UNIQUE KEY `unique_inventory` (`identifier`, `inventory_type`, `inventory_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {}, function(result)
        Debug('Info', 'Database table initialized')

        local itemCount = 0
        if Items then for _ in pairs(Items) do itemCount = itemCount + 1 end end
        Debug('Verbose', 'Items loaded: ' .. itemCount)
    end)
end)

local function GetItemData(itemName)
    return Items[itemName] or Weapons[itemName] or Ammo[itemName]
end

local function GetWeaponDefinition(itemName)
    if type(itemName) ~= 'string' then
        return nil, nil
    end

    local upperName = string.upper(itemName)
    if not string.find(upperName, 'WEAPON_', 1, true) then
        upperName = 'WEAPON_' .. upperName
    end

    return Weapons[upperName], upperName
end

local function EnsureItemMetadata(itemName, metadata)
    local safeMetadata = ShallowCopy(metadata)
    local weaponDef = GetWeaponDefinition(itemName)

    if weaponDef and weaponDef.ammoType and safeMetadata.ammo == nil then
        safeMetadata.ammo = 0
    end

    return safeMetadata
end

local function FindInventoryItem(inv, itemName, slotId)
    if not inv or not inv.items then
        return nil
    end

    local wantedSlot = slotId ~= nil and tostring(slotId) or nil
    local wantedName = type(itemName) == 'string' and itemName or nil
    local wantedUpper = wantedName and string.upper(wantedName) or nil

    for index, item in ipairs(inv.items) do
        local itemSlot = item.slot ~= nil and tostring(item.slot) or nil
        local itemUpper = type(item.name) == 'string' and string.upper(item.name) or nil
        local slotMatches = (not wantedSlot) or (itemSlot == wantedSlot)
        local nameMatches = (not wantedName) or item.name == wantedName or itemUpper == wantedUpper

        if slotMatches and nameMatches then
            return item, index
        end
    end

    return nil
end

local function GetInventoryItemCount(inv, itemName)
    if not inv or not inv.items then return 0 end
    return InventoryStacking.Count(inv.items, itemName)
end

local function CalculateWeight(items)
    local weight = 0.0
    for _, item in ipairs(items) do
        local data = GetItemData(item.name)
        if data then
            weight = weight + (data.weight * item.count)
        end
    end
    return weight
end

local function IsSpotFree(inventory, x, y, w, h, ignoreSlot)
    if x < 1 or y < 1 or (x + w - 1) > Config.GridWidth or (y + h - 1) > Config.GridHeight then
        return false
    end

    for _, item in ipairs(inventory.items) do
        if item.slot ~= ignoreSlot then
            local data = GetItemData(item.name)
            local iW = data and data.size and data.size.w or 1
            local iH = data and data.size and data.size.h or 1

            local itemRight = item.x + iW - 1
            local itemBottom = item.y + iH - 1
            local newRight = x + w - 1
            local newBottom = y + h - 1

            local overlapsX = not (newRight < item.x or x > itemRight)
            local overlapsY = not (newBottom < item.y or y > itemBottom)

            if overlapsX and overlapsY then
                return false
            end
        end
    end

    return true
end

local function FindFreeSpot(inventory, itemName)
    local data = GetItemData(itemName)
    if not data then return nil end

    local w = data.size and data.size.w or 1
    local h = data.size and data.size.h or 1

    for y = 1, Config.GridHeight do
        for x = 1, Config.GridWidth do
            if IsSpotFree(inventory, x, y, w, h) then
                return {x = x, y = y}
            end
        end
    end

    return nil
end

local function CollectFreePositions(inventory, itemName, required, preferredX, preferredY)
    if required <= 0 then return {} end

    local data = GetItemData(itemName)
    if not data then return nil end
    local w = data.size and data.size.w or 1
    local h = data.size and data.size.h or 1
    local shadow = { items = {} }
    for _, item in ipairs(inventory.items or {}) do
        shadow.items[#shadow.items + 1] = item
    end

    local positions = {}
    local function Reserve(position)
        positions[#positions + 1] = { x = position.x, y = position.y }
        shadow.items[#shadow.items + 1] = {
            name = itemName,
            x = position.x,
            y = position.y,
            slot = ('reserved-%d'):format(#positions)
        }
    end

    preferredX, preferredY = tonumber(preferredX), tonumber(preferredY)
    if preferredX and preferredY and IsSpotFree(shadow, preferredX, preferredY, w, h) then
        Reserve({ x = preferredX, y = preferredY })
    end

    while #positions < required do
        local free = FindFreeSpot(shadow, itemName)
        if not free then return nil end
        Reserve(free)
    end

    return positions
end

local function AddToInventory(inv, itemName, count, metadata, preferredX, preferredY)
    count = math.floor(tonumber(count) or 0)
    if count < 1 then return false, 'Invalid count' end

    local data = GetItemData(itemName)
    if not data then return false, 'Item not found' end
    metadata = EnsureItemMetadata(itemName, metadata)

    local addWeight = (tonumber(data.weight) or 0) * count
    if inv.weight + addWeight > inv.maxWeight then return false, 'Too heavy' end

    local weaponDef = GetWeaponDefinition(itemName)
    local required = InventoryStacking.RequiredNewSlots(
        inv.items, data, itemName, count, metadata, weaponDef ~= nil
    )
    local positions = CollectFreePositions(inv, itemName, required, preferredX, preferredY)
    if not positions then return false, 'No space' end

    local ok, reason = InventoryStacking.Add(
        inv.items,
        data,
        itemName,
        count,
        metadata,
        positions,
        NextSlotId,
        weaponDef ~= nil
    )
    if not ok then return false, reason end

    inv.weight = inv.weight + addWeight
    return true
end

local function GetIdentifier(src)
    local player = GetPlayer(src)
    if player then
        return player.identifier
    end
    local ok, id = pcall(function()
        return exports['corex-core']:GetCoreObject()
    end)
    if ok and id and id.Functions then
        return id.Functions.GetIdentifier(src, 'license')
    end
    return nil
end

local function Notify(src, message, type)
    TriggerClientEvent('corex:notify', src, message, type or 'info')
end

local function LoadInventory(src)
    local id = GetIdentifier(src)
    if not id then return end

    exports.oxmysql:query(
        'SELECT * FROM inventories WHERE identifier = ? AND inventory_type = ? LIMIT 1',
        {id, 'player'},
        function(results)
            local result = results and results[1]
            if result and result.items then
                local items = json.decode(result.items) or {}
                local hotbar = result.hotbar and json.decode(result.hotbar) or {}

                Inventories[src] = {
                    items = items,
                    hotbar = hotbar,
                    weight = CalculateWeight(items),
                    maxWeight = Config.MaxWeight
                }

                Debug('Info', 'Loaded ' .. #items .. ' items for player ' .. src)
            else
                Inventories[src] = {
                    items = {},
                    hotbar = {},
                    weight = 0.0,
                    maxWeight = Config.MaxWeight
                }
                exports.oxmysql:insert(
                    'INSERT INTO inventories (identifier, inventory_type, inventory_id, items, hotbar) VALUES (?, ?, ?, ?, ?)',
                    {id, 'player', id, '[]', '{}'}
                )

                Debug('Info', 'Created new inventory for player ' .. src)
            end

            SetTimeout(1000, function()
                TriggerClientEvent('corex-inventory:client:syncInventory', src, Inventories[src].items)
            end)
        end
    )
end

---Persist inventory to DB immediately (used for forced flushes and drop/disconnect paths).
---@param src number
local function FlushInventory(src)
    local id = GetIdentifier(src)
    local inv = Inventories[src]
    if not id or not inv then return end

    local itemsJson = json.encode(inv.items)
    local hotbarJson = json.encode(inv.hotbar or {})

    exports.oxmysql:execute(
        'UPDATE inventories SET items = ?, hotbar = ? WHERE identifier = ? AND inventory_type = ?',
        {itemsJson, hotbarJson, id, 'player'},
        function(result)
            local rows = 0
            if type(result) == 'number' then
                rows = result
            elseif type(result) == 'table' then
                rows = tonumber(result.affectedRows) or tonumber(result.rowsAffected) or 0
            end

            if rows > 0 then
                inv.isDirty = false
            else
                Debug('Warn', 'Flush reported 0 rows affected for source ' .. tostring(src))
                inv.isDirty = false
            end
        end
    )
end

---Mark inventory dirty and push a fresh sync to the owning client.
---Actual DB write is deferred to the batched auto-save loop (every 30s),
---reducing query count from dozens-per-minute-per-player to at most 2/min.
---@param src number
---@param pushSync boolean|nil
local function SaveInventory(src, pushSync)
    local inv = Inventories[src]
    if not inv then return end

    inv.isDirty = true
    if pushSync ~= false then
        TriggerClientEvent('corex-inventory:client:syncInventory', src, inv.items)
    end
end

local function SyncInventoryToClient(src)
    if not Inventories[src] then return end
    TriggerClientEvent('corex-inventory:client:syncInventory', src, Inventories[src].items)
end

local function BroadcastNearby(eventName, coords, radius, ...)
    local players = GetPlayers()
    for _, srcStr in ipairs(players) do
        local src = tonumber(srcStr)
        local ped = GetPlayerPed(src)
        if ped and ped ~= 0 then
            local pc = GetEntityCoords(ped)
            if #(pc - coords) <= radius then
                TriggerClientEvent(eventName, src, ...)
            end
        end
    end
end

local function BroadcastDroppedItems()
    TriggerClientEvent('corex-inventory:client:syncDroppedItems', -1, DroppedItems)
end

local function DropItem(src, itemName, count, slot, coords)
    if not TrySetBusy(src) then
        Debug('Warn', 'DropItem blocked: Player ' .. src .. ' is busy')
        return false
    end

    local inv = Inventories[src]
    if not inv then
        ClearBusy(src)
        return false
    end

    if coords and coords.x then
        local ped = GetPlayerPed(src)
        if ped and ped ~= 0 then
            local pc = GetEntityCoords(ped)
            local dx, dy, dz = pc.x - coords.x, pc.y - coords.y, pc.z - (coords.z or pc.z)
            if (dx * dx + dy * dy + dz * dz) > 100.0 then
                Debug('Warn', ('DropItem rejected: drop coords too far from ped (src=%d)'):format(src))
                ClearBusy(src)
                return false
            end
        end
    end

    local itemIndex = nil
    local item = nil

    if slot then
        for i, it in ipairs(inv.items) do
            if tostring(it.slot) == tostring(slot) and it.name == itemName then
                itemIndex = i
                item = it
                break
            end
        end
    end

    if not item and itemName then
        for i, it in ipairs(inv.items) do
            if it.name == itemName then
                itemIndex = i
                item = it
                break
            end
        end
    end

    if not item then
        ClearBusy(src)
        Debug('Warn', ('DropItem rejected: item not found (src=%d name=%s)'):format(src, tostring(itemName)))
        return false
    end

    if type(count) == 'number' and (count < 1 or count > item.count) then
        ClearBusy(src)
        Debug('Warn', ('DropItem rejected: invalid count (src=%d req=%d have=%d)'):format(src, count, item.count))
        return false
    end

    local data = GetItemData(item.name)
    local dropCount = math.min(count or item.count, item.count)

    if item.count > dropCount then
        item.count = item.count - dropCount
    else
        table.remove(inv.items, itemIndex)
    end

    if data then
        inv.weight = inv.weight - (data.weight * dropCount)
    end

    dropIdCounter = dropIdCounter + 1
    local dropId = 'drop_' .. dropIdCounter .. '_' .. os.time()

    DroppedItems[dropId] = {
        name = itemName,
        count = dropCount,
        coords = coords or vector3(0, 0, 0),
        gridX = coords and coords.gridX or 1,
        gridY = coords and coords.gridY or 1,
        prop = data and data.prop or 'prop_med_bag_01b',
        metadata = ShallowCopy(item.metadata),
        droppedBy = src,
        droppedAt = os.time()
    }

    SaveInventory(src)
    TriggerClientEvent('corex-inventory:client:update', src, inv)
    exports['corex-core']:BroadcastNearby(coords or vector3(0,0,0), 500.0, 'corex-inventory:client:itemDropped', dropId, DroppedItems[dropId])

    local upperName = string.upper(itemName)
    if not string.find(upperName, 'WEAPON_') then
        upperName = 'WEAPON_' .. upperName
    end
    if Weapons and Weapons[upperName] then
        TriggerClientEvent('corex-inventory:client:weaponDropConfirmed', src, upperName)
    end

    Debug('Info', 'Item dropped: ' .. itemName .. ' x' .. dropCount .. ' by player ' .. src)

    ClearBusy(src)
    return true
end

local function PickupItem(src, dropId, gridX, gridY)
    -- ACTION LOCK: Prevent duping
    if not TrySetBusy(src) then
        Debug('Warn', 'PickupItem blocked: Player ' .. src .. ' is busy')
        return false
    end

    local dropData = DroppedItems[dropId]
    if not dropData then
        ClearBusy(src)
        return false
    end

    local pickupDistance = (Config.PickupDistance or 3.0) + 1.0
    if not IsPlayerNearCoords(src, dropData.coords, pickupDistance) then
        Debug('Warn', ('Pickup rejected: player %d too far from %s'):format(src, tostring(dropId)))
        ClearBusy(src)
        return false
    end

    local inv = Inventories[src]
    if not inv then
        ClearBusy(src)
        return false
    end

    local added, addError = AddToInventory(
        inv,
        dropData.name,
        dropData.count,
        dropData.metadata,
        gridX,
        gridY
    )
    if not added then
        Debug('Warn', 'Pickup failed: ' .. tostring(addError))
        ClearBusy(src)
        return false
    end

    DroppedItems[dropId] = nil

    SaveInventory(src)
    TriggerClientEvent('corex-inventory:client:update', src, inv)
    local dropCoords = dropData.coords or vector3(0,0,0)
    exports['corex-core']:BroadcastNearby(dropCoords, 500.0, 'corex-inventory:client:itemPickedUp', dropId)

    Debug('Info', 'Item picked up: ' .. dropData.name .. ' x' .. dropData.count .. ' by player ' .. src)

    ClearBusy(src)
    return true
end

local function AddItem(src, itemName, count, metadata, x, y)
    local inv = Inventories[src]
    if not inv then return false, 'No inventory' end

    local added, addError = AddToInventory(inv, itemName, count or 1, metadata, x, y)
    if not added then return false, addError end
    SaveInventory(src)
    TriggerClientEvent('corex-inventory:client:update', src, inv)

    return true
end

local function RemoveItem(src, itemName, count)
    count = math.floor(tonumber(count) or 1)
    if count < 1 then return false end
    local inv = Inventories[src]
    if not inv then return false end

    local removed = InventoryStacking.Remove(inv.items, itemName, count)
    if not removed then return false end

    local data = GetItemData(itemName)
    if data then
        inv.weight = math.max(0.0, inv.weight - ((tonumber(data.weight) or 0) * count))
    end
    SaveInventory(src)
    TriggerClientEvent('corex-inventory:client:update', src, inv)
    return true
end

---Remove a single inventory stack by slot id (for unique metadata items).
---@return boolean success
---@return table|nil removedItem
local function RemoveInventoryItemAtSlot(src, slotId)
    if slotId == nil then return false end
    local wanted = tostring(slotId)
    local inv = Inventories[src]
    if not inv then return false end

    for index, item in ipairs(inv.items) do
        local itemSlot = item.slot ~= nil and tostring(item.slot) or nil
        if itemSlot == wanted then
            local data = GetItemData(item.name)
            if data then inv.weight = inv.weight - (data.weight * (item.count or 1)) end
            table.remove(inv.items, index)
            SaveInventory(src)
            TriggerClientEvent('corex-inventory:client:update', src, inv)
            return true, item
        end
    end

    return false
end

local function RefundPendingBikeDeploy(src, message)
    local refund = PendingBikeRefund[src]
    if not refund then return end

    local itemName = 'rental_bicycle'
    local meta = refund
    if type(refund) == 'table' and type(refund.itemName) == 'string' and type(refund.metadata) == 'table' then
        itemName = refund.itemName
        meta = refund.metadata
    end

    AddItem(src, itemName, 1, ShallowCopy(meta))
    PendingBikeRefund[src] = nil
    DeployRefundToken[src] = nil
    if message and type(message) == 'string' then
        TriggerClientEvent('corex-inventory:client:portableVehicleNotify', src, message, 'error')
    end
end

AddEventHandler('playerDropped', function()
    local src = source
    PendingBikeRegistration[src] = nil
    PendingBikeRefund[src] = nil
    DeployRefundToken[src] = nil
    LastRentalBikePickupAttempt[src] = nil
end)

RegisterNetEvent('corex-inventory:server:load', function()
    LoadInventory(source)
end)

RegisterNetEvent('corex-inventory:server:requestDroppedItems', function()
    TriggerClientEvent('corex-inventory:client:syncDroppedItems', source, DroppedItems)
end)

RegisterNetEvent('corex-inventory:server:open', function()
    local src = source
    local inv = Inventories[src]

    if inv then
        local allItems = GetAllItemsData()

        TriggerClientEvent('corex-inventory:client:open', src, {
            items = inv.items,
            weight = inv.weight,
            maxWeight = inv.maxWeight,
            grid = {w = Config.GridWidth, h = Config.GridHeight},
            itemsData = allItems
        })
    end
end)

RegisterNetEvent('corex-inventory:server:move', function(slotId, newX, newY, targetSlotId)
    local src = source
    if type(slotId) ~= 'string' and type(slotId) ~= 'number' then return end
    if type(newX) ~= 'number' or type(newY) ~= 'number' then return end
    local inv = Inventories[src]
    if not inv then return end

    local item = nil
    for _, i in ipairs(inv.items) do
        if tostring(i.slot) == tostring(slotId) then
            item = i
            break
        end
    end

    if not item then return end

    local data = GetItemData(item.name)
    if targetSlotId ~= nil then
        local weaponDef = GetWeaponDefinition(item.name)
        local merged = InventoryStacking.MergeSlots(
            inv.items,
            slotId,
            targetSlotId,
            data,
            weaponDef ~= nil
        )
        if merged then
            SaveInventory(src)
            Debug('Verbose', 'Merged item stack ' .. item.name)
        end
        TriggerClientEvent('corex-inventory:client:update', src, inv)
        return
    end

    local w = data and data.size and data.size.w or 1
    local h = data and data.size and data.size.h or 1

    if IsSpotFree(inv, newX, newY, w, h, slotId) then
        item.x = newX
        item.y = newY
        SaveInventory(src)
        Debug('Verbose', 'Moved item ' .. item.name .. ' to ' .. newX .. ',' .. newY)
    else
        Debug('Warn', 'Move blocked: Collision detected')
    end

    TriggerClientEvent('corex-inventory:client:update', src, inv)
end)

RegisterNetEvent('corex-inventory:server:use', function(itemName, slotId)
    local src = source
    if type(itemName) ~= 'string' then return end
    local inv = Inventories[src]
    if not inv then return end

    local itemData = {}
    local item = FindInventoryItem(inv, itemName, slotId)
    if not item then
        Debug('Warn', ('Use rejected: player %d does not have %s'):format(src, tostring(itemName)))
        return
    end

    itemData = {
        slot = item.slot,
        count = item.count,
        x = item.x,
        y = item.y,
        metadata = EnsureItemMetadata(item.name, item.metadata)
    }
    itemData.ammo = itemData.metadata.ammo
    itemName = item.name

    TriggerClientEvent('corex-inventory:client:useItem', src, itemName, itemData)
end)

RegisterNetEvent('corex-inventory:server:removeUsedAmmo', function(ammoName, count)
    local src = source
    if type(ammoName) ~= 'string' then return end
    RemoveItem(src, ammoName, count or 1)
end)

RegisterNetEvent('corex-inventory:server:drop', function(itemName, count, slot, coords)
    if type(itemName) ~= 'string' then return end
    DropItem(source, itemName, count, slot, coords)
end)

RegisterNetEvent('corex-inventory:server:pickup', function(dropId, x, y)
    if type(dropId) ~= 'string' then return end
    PickupItem(source, dropId, x or 1, y or 1)
end)

-- Find next available ground slot for loot
local function FindNextGroundSlot(itemWidth, itemHeight)
    local gridCols = 8
    local gridRows = 10
    local occupied = {}

    -- Mark ALL slots that are occupied (including multi-slot items)
    for _, item in pairs(DroppedItems) do
        if item.gridX and item.gridY then
            local itemData = GetItemData(item.name)
            local size = itemData and itemData.size or {w = 1, h = 1}
            local w = size.w or 1
            local h = size.h or 1

            -- Mark all cells this item occupies
            for dy = 0, h - 1 do
                for dx = 0, w - 1 do
                    local key = (item.gridX + dx) .. ',' .. (item.gridY + dy)
                    occupied[key] = true
                end
            end
        end
    end

    -- Find first free slot that can fit this item
    for row = 1, gridRows do
        for col = 1, gridCols do
            -- Check if item fits starting from this position
            local canFit = true

            -- Check if item goes beyond grid boundaries
            if col + itemWidth - 1 > gridCols or row + itemHeight - 1 > gridRows then
                canFit = false
            else
                -- Check all cells the item would occupy
                for dy = 0, itemHeight - 1 do
                    for dx = 0, itemWidth - 1 do
                        local key = (col + dx) .. ',' .. (row + dy)
                        if occupied[key] then
                            canFit = false
                            break
                        end
                    end
                    if not canFit then break end
                end
            end

            if canFit then
                return col, row
            end
        end
    end

    -- If all slots full, start from beginning (will overlap)
    return 1, 1
end

-- Add loot item directly to ground (for zombie drops, etc.)
AddEventHandler('corex-inventory:server:addLootItem', function(src, itemName, amount, coords)
    local itemData = GetItemData(itemName)
    if not itemData then
        Debug('Error', 'Cannot drop loot: Unknown item ' .. itemName)
        return
    end

    local size = itemData.size or {w = 1, h = 1}
    local itemWidth = size.w or 1
    local itemHeight = size.h or 1
    local gridX, gridY = FindNextGroundSlot(itemWidth, itemHeight)

    local dropId = 'loot_' .. math.random(100000, 999999)
    DroppedItems[dropId] = {
        name = itemName,
        count = amount or 1,
        coords = coords or {x = 0, y = 0, z = 0},
        gridX = gridX,
        gridY = gridY,
        prop = itemData.prop or 'prop_med_bag_01b',
        droppedAt = os.time()
    }

    local lootCoords = coords and vector3(coords.x or 0, coords.y or 0, coords.z or 0) or vector3(0,0,0)
    exports['corex-core']:BroadcastNearby(lootCoords, 500.0, 'corex-inventory:client:itemDropped', dropId, DroppedItems[dropId])
    Debug('Info', 'Loot dropped: ' .. itemName .. ' x' .. (amount or 1))
end)

RegisterNetEvent('corex-inventory:server:give', function(targetPlayer, itemName, count, slot)
    local src = source
    local targetSrc = tonumber(targetPlayer)

    if not targetSrc or targetSrc == src then
        Debug('Warn', 'Give failed: Invalid target')
        return
    end

    if type(itemName) ~= 'string' or #itemName == 0 or #itemName > 100 then return end
    count = tonumber(count) or 1
    if count ~= count or count == math.huge then return end
    count = math.floor(count)
    if count < 1 or count > 9999 then return end

    if slot == nil then return end
    local slotStr = tostring(slot)
    if #slotStr == 0 or #slotStr > 64 then return end

    local srcInvCheck = Inventories[src]
    if not srcInvCheck then return end

    local slotOwned = false
    for _, it in ipairs(srcInvCheck.items) do
        if tostring(it.slot) == slotStr and it.name == itemName then
            slotOwned = true
            break
        end
    end
    if not slotOwned then
        Debug('Warn', ('Give rejected: slot %s not owned by %d'):format(slotStr, src))
        return
    end

    if not IsNearbyPlayer(src, targetSrc, 5.0) then
        Debug('Warn', 'Give failed: Target too far away')
        Notify(src, 'Target is too far away', 'error')
        return
    end

    -- ACTION LOCK: Prevent duping on both players
    if not TrySetBusy(src) then
        Debug('Warn', 'Give blocked: Source player is busy')
        return
    end

    if not TrySetBusy(targetSrc) then
        Debug('Warn', 'Give blocked: Target player is busy')
        ClearBusy(src)
        return
    end

    local srcInv = Inventories[src]
    local targetInv = Inventories[targetSrc]

    if not srcInv or not targetInv then
        Debug('Warn', 'Give failed: Missing inventory')
        ClearBusy(src)
        ClearBusy(targetSrc)
        return
    end

    local itemIndex = nil
    local item = nil

    for i, it in ipairs(srcInv.items) do
        if tostring(it.slot) == tostring(slot) and it.name == itemName then
            itemIndex = i
            item = it
            break
        end
    end

    if not item then
        Debug('Warn', 'Give failed: Item not found')
        ClearBusy(src)
        ClearBusy(targetSrc)
        return
    end

    local data = GetItemData(item.name)
    if not data then
        Debug('Warn', 'Give failed: Item data not found')
        ClearBusy(src)
        ClearBusy(targetSrc)
        return
    end

    local giveCount = math.min(count or item.count, item.count)
    local added, addError = AddToInventory(
        targetInv,
        item.name,
        giveCount,
        item.metadata
    )
    if not added then
        Debug('Warn', 'Give failed: ' .. tostring(addError))
        Notify(src, addError == 'Too heavy' and 'Target inventory is full' or 'Target has no space', 'error')
        ClearBusy(src)
        ClearBusy(targetSrc)
        return
    end

    if item.count > giveCount then
        item.count = item.count - giveCount
    else
        table.remove(srcInv.items, itemIndex)
    end
    srcInv.weight = srcInv.weight - (data.weight * giveCount)

    SaveInventory(src)
    SaveInventory(targetSrc)

    TriggerClientEvent('corex-inventory:client:update', src, srcInv)
    TriggerClientEvent('corex-inventory:client:update', targetSrc, targetInv)

    local srcPlayer = GetPlayer(src)
    local tgtPlayer = GetPlayer(targetSrc)
    local srcName = srcPlayer and srcPlayer.name or (function()
        local ok, n = pcall(function() return exports['corex-core']:GetCoreObject().Functions.GetPlayerName(src) end)
        return ok and n or 'Unknown'
    end)()
    local targetName = tgtPlayer and tgtPlayer.name or (function()
        local ok, n = pcall(function() return exports['corex-core']:GetCoreObject().Functions.GetPlayerName(targetSrc) end)
        return ok and n or 'Unknown'
    end)()

    Debug('Info', srcName .. ' gave ' .. giveCount .. 'x ' .. itemName .. ' to ' .. targetName)

    Notify(targetSrc, 'Received ' .. giveCount .. 'x ' .. (data.label or itemName), 'success')

    ClearBusy(src)
    ClearBusy(targetSrc)
end)

AddEventHandler('corex:server:playerReady', function(src, player)
    if not player then return end

    CreateThread(function()
        Wait(1500) -- Wait for corex-core to finish
        LoadInventory(src)
        Debug('Info', 'Auto-loaded inventory for ' .. (player.name or 'Unknown'))
    end)
end)

AddEventHandler('playerDropped', function(reason)
    local src = source
    if Inventories[src] then
        FlushInventory(src)
        Debug('Info', 'Saved inventory on disconnect for source ' .. src)
        Inventories[src] = nil
    end
end)

-- Batched persistence loop — writes only dirty inventories, every 30s.
-- Previously each AddItem/RemoveItem/Move/Drop/Pickup/Give triggered an
-- oxmysql UPDATE; under active play this produced dozens of writes per
-- player per minute. Now writes coalesce and are flushed on a cadence.
CreateThread(function()
    Wait(5000)

    while true do
        Wait(30000)

        local flushed = 0
        for src, inv in pairs(Inventories) do
            if inv and inv.isDirty then
                FlushInventory(src)
                flushed = flushed + 1
            end
        end

        if flushed > 0 then
            Debug('Verbose', 'Flushed ' .. flushed .. ' dirty inventories to DB')
        end
    end
end)

-- Flush on resource stop so we don't lose in-memory changes
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    for src, inv in pairs(Inventories) do
        if inv and inv.isDirty then
            FlushInventory(src)
        end
    end
end)

-- Drop expiration cleanup — skips the pass when no drops exist.
CreateThread(function()
    while true do
        Wait(60000)

        if next(DroppedItems) == nil then
            goto continue
        end

        local now = os.time()
        local expireTime = Config.DropExpireTime or 1800

        for dropId, item in pairs(DroppedItems) do
            if now - item.droppedAt > expireTime then
                local expCoords = item.coords or vector3(0,0,0)
                DroppedItems[dropId] = nil
                exports['corex-core']:BroadcastNearby(expCoords, 500.0, 'corex-inventory:client:itemPickedUp', dropId)
                Debug('Verbose', 'Expired dropped item: ' .. item.name)
            end
        end

        ::continue::
    end
end)

local function UpdateItemMeta(src, itemName, metadata, slotId, syncClient)
    local inv = Inventories[src]
    if not inv or type(metadata) ~= 'table' then return false end

    local item = FindInventoryItem(inv, itemName, slotId)
    if item then
        item.metadata = EnsureItemMetadata(item.name, item.metadata)
        for k, v in pairs(metadata) do
            item.metadata[k] = v
        end

        SaveInventory(src, syncClient ~= false)
        if syncClient ~= false then
            TriggerClientEvent('corex-inventory:client:update', src, inv)
        end
        return true
    end

    return false
end

local function GetItemMeta(src, itemName, slotId)
    local inv = Inventories[src]
    if not inv then return nil end

    local item = FindInventoryItem(inv, itemName, slotId)
    if item then
        return EnsureItemMetadata(item.name, item.metadata)
    end

    return nil
end

RegisterNetEvent('corex-inventory:server:updateWeaponMeta', function(weaponName, metadata, slotId, syncClient)
    local src = source
    UpdateItemMeta(src, weaponName, metadata, slotId, syncClient)
end)

RegisterNetEvent('corex-inventory:server:updateWeaponAmmo', function(slotId, weaponName, ammo)
    local src = source
    local safeAmmo = math.max(0, math.floor(tonumber(ammo) or 0))
    UpdateItemMeta(src, weaponName, { ammo = safeAmmo }, slotId, false)
end)

RegisterNetEvent('corex-inventory:server:requestAmmoReload', function(slotId, weaponName)
    local src = source
    local inv = Inventories[src]

    if not inv then
        TriggerClientEvent('corex-inventory:client:ammoReloadResult', src, false, slotId, weaponName, 0, 0, 'Inventory not ready')
        return
    end

    local weaponItem = FindInventoryItem(inv, weaponName, slotId)
    if not weaponItem then
        TriggerClientEvent('corex-inventory:client:ammoReloadResult', src, false, slotId, weaponName, 0, 0, 'Weapon not found')
        return
    end

    local weaponDef, canonicalName = GetWeaponDefinition(weaponItem.name)
    if not weaponDef or not weaponDef.ammoType then
        TriggerClientEvent('corex-inventory:client:ammoReloadResult', src, false, slotId, canonicalName or weaponItem.name, 0, 0, 'This weapon cannot be reloaded')
        return
    end

    if GetInventoryItemCount(inv, weaponDef.ammoType) < 1 then
        TriggerClientEvent('corex-inventory:client:ammoReloadResult', src, false, slotId, canonicalName, 0, 0, 'No ammo item available')
        return
    end

    weaponItem.metadata = EnsureItemMetadata(weaponItem.name, weaponItem.metadata)
    local newAmmo = math.max(0, math.floor(tonumber(weaponItem.metadata.ammo) or 0)) + 10
    weaponItem.metadata.ammo = newAmmo

    if not RemoveItem(src, weaponDef.ammoType, 1) then
        TriggerClientEvent('corex-inventory:client:ammoReloadResult', src, false, slotId, canonicalName, 0, 0, 'Failed to consume ammo item')
        return
    end

    TriggerClientEvent('corex-inventory:client:ammoReloadResult', src, true, slotId, canonicalName, newAmmo, 10, weaponDef.ammoType)
end)

exports('GetItemsCatalog', function() return Items or {} end)
exports('GetWeaponsCatalog', function() return Weapons or {} end)
exports('GetAmmoCatalog', function() return Ammo or {} end)
exports('GetFullCatalog', GetAllItemsData)
-- Grid dimensions live in Config; expose them so sibling resources (e.g.
-- corex-admin's inventory editor) can render the correct slot count
-- without duplicating the constant.
exports('GetGridWidth',  function() return Config and Config.GridWidth  or 8  end)
exports('GetGridHeight', function() return Config and Config.GridHeight or 10 end)
exports('AddItem', AddItem)
exports('RemoveItem', RemoveItem)
exports('GetInventory', function(src) return Inventories[src] end)
exports('DropItem', DropItem)
exports('PickupItem', PickupItem)
exports('UpdateItemMeta', UpdateItemMeta)
exports('GetItemMeta', GetItemMeta)
exports('HasItem', function(src, itemName, count)
    local inv = Inventories[src]
    if not inv then return false end
    return InventoryStacking.HasItem(inv.items, itemName, count or 1)
end)
exports('GetItemCount', function(src, itemName)
    local inv = Inventories[src]
    if not inv then return 0 end
    return InventoryStacking.Count(inv.items, itemName)
end)

-- [SECURITY] NetEvent 'corex-inventory:server:giveitem' removed (was CRIT-01).
-- Previously any client could trigger it to self-grant any item.
-- Admins use the restricted server command /giveitem below (requires
-- ACE permission `command.giveitem`). The client wrapper at
-- corex-inventory/client/main.lua is also gated behind Config.Debug.

RegisterCommand('giveitem', function(src, args)
    local item = args[1]
    local count = tonumber(args[2]) or 1

    if not item then return end

    local ok, err = AddItem(src, item, count)
    if ok then
        Debug('Info', 'Added ' .. item)
    else
        Debug('Warn', 'Failed: ' .. (err or 'Unknown'))
    end
end, true)

RegisterCommand('removeitem', function(src, args)
    local item = args[1]
    local count = tonumber(args[2]) or 1
    if item then RemoveItem(src, item, count) end
end, true)

-- =============================================================
-- BAG SYSTEM
-- =============================================================

local function GenerateBagId()
    return ('bag_%d_%d'):format(GetGameTimer(), math.random(100000, 999999))
end

local function IsSpotFreeInBag(bagInv, x, y, w, h, ignoreSlot)
    if x < 1 or y < 1 or (x + w - 1) > bagInv.gridW or (y + h - 1) > bagInv.gridH then
        return false
    end

    for _, item in ipairs(bagInv.items) do
        if item.slot ~= ignoreSlot then
            local data = GetItemData(item.name)
            local iW = data and data.size and data.size.w or 1
            local iH = data and data.size and data.size.h or 1

            local overlapsX = not ((x + w - 1) < item.x or x > (item.x + iW - 1))
            local overlapsY = not ((y + h - 1) < item.y or y > (item.y + iH - 1))

            if overlapsX and overlapsY then
                return false
            end
        end
    end

    return true
end

local function FindFreeSpotInBag(bagInv, itemName)
    local data = GetItemData(itemName)
    if not data then return nil end

    local w = data.size and data.size.w or 1
    local h = data.size and data.size.h or 1

    for y = 1, bagInv.gridH do
        for x = 1, bagInv.gridW do
            if IsSpotFreeInBag(bagInv, x, y, w, h) then
                return {x = x, y = y}
            end
        end
    end

    return nil
end

local function CollectFreePositionsInBag(bagInv, itemName, required, preferredX, preferredY)
    if required <= 0 then return {} end

    local data = GetItemData(itemName)
    if not data then return nil end
    local w = data.size and data.size.w or 1
    local h = data.size and data.size.h or 1
    local shadow = {
        items = {},
        gridW = bagInv.gridW,
        gridH = bagInv.gridH
    }
    for _, item in ipairs(bagInv.items or {}) do shadow.items[#shadow.items + 1] = item end

    local positions = {}
    local function Reserve(position)
        positions[#positions + 1] = { x = position.x, y = position.y }
        shadow.items[#shadow.items + 1] = {
            name = itemName,
            x = position.x,
            y = position.y,
            slot = ('bag-reserved-%d'):format(#positions)
        }
    end

    preferredX, preferredY = tonumber(preferredX), tonumber(preferredY)
    if preferredX and preferredY and IsSpotFreeInBag(shadow, preferredX, preferredY, w, h) then
        Reserve({ x = preferredX, y = preferredY })
    end

    while #positions < required do
        local free = FindFreeSpotInBag(shadow, itemName)
        if not free then return nil end
        Reserve(free)
    end
    return positions
end

local function AddToBag(bagInv, itemName, count, metadata, preferredX, preferredY)
    local data = GetItemData(itemName)
    if not data then return false, 'Item not found' end
    count = math.floor(tonumber(count) or 0)
    if count < 1 then return false, 'Invalid count' end

    local addWeight = (tonumber(data.weight) or 0) * count
    if bagInv.weight + addWeight > bagInv.maxWeight then return false, 'Bag is too heavy' end

    local weaponDef = GetWeaponDefinition(itemName)
    local safeMetadata = EnsureItemMetadata(itemName, metadata)
    local required = InventoryStacking.RequiredNewSlots(
        bagInv.items, data, itemName, count, safeMetadata, weaponDef ~= nil
    )
    local positions = CollectFreePositionsInBag(
        bagInv, itemName, required, preferredX, preferredY
    )
    if not positions then return false, 'No space in bag' end

    local added, reason = InventoryStacking.Add(
        bagInv.items,
        data,
        itemName,
        count,
        safeMetadata,
        positions,
        NextSlotId,
        weaponDef ~= nil
    )
    if not added then return false, reason end
    bagInv.weight = bagInv.weight + addWeight
    return true
end

local function FlushBag(bagId)
    local bagInv = BagInventories[bagId]
    if not bagInv then return end

    local itemsJson = json.encode(bagInv.items)

    exports.oxmysql:execute(
        'INSERT INTO inventories (identifier, inventory_type, inventory_id, items, hotbar) VALUES (?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE items = VALUES(items)',
        {bagId, 'bag', bagId, itemsJson, '{}'},
        function()
            bagInv.isDirty = false
        end
    )
end

local function SaveBag(bagId)
    local bagInv = BagInventories[bagId]
    if not bagInv then return end

    bagInv.isDirty = true

    local viewer = BagViewers[bagId]
    if viewer then
        TriggerClientEvent('corex-inventory:client:syncBag', viewer, bagId,
            bagInv.items, bagInv.weight, bagInv.maxWeight)
    end
end

local function LoadBag(bagId, gridW, gridH, maxWeight, callback)
    if BagInventories[bagId] then
        if callback then callback(BagInventories[bagId]) end
        return
    end

    exports.oxmysql:query(
        'SELECT items FROM inventories WHERE identifier = ? AND inventory_type = ? LIMIT 1',
        {bagId, 'bag'},
        function(results)
            local result = results and results[1]
            local items = (result and result.items and json.decode(result.items)) or {}

            BagInventories[bagId] = {
                items     = items,
                weight    = CalculateWeight(items),
                maxWeight = maxWeight or 20.0,
                gridW     = gridW or 4,
                gridH     = gridH or 3,
                isDirty   = false
            }

            if callback then callback(BagInventories[bagId]) end
        end
    )
end

-- Player uses a bag item → open bag panel
RegisterNetEvent('corex-inventory:server:openBag', function(slotId)
    local src = source
    local inv  = Inventories[src]
    if not inv then return end

    local bagItem = nil
    for _, item in ipairs(inv.items) do
        if tostring(item.slot) == tostring(slotId) then
            bagItem = item
            break
        end
    end

    if not bagItem then
        Debug('Warn', ('openBag: item not found (src=%d slot=%s)'):format(src, tostring(slotId)))
        return
    end

    local itemDef = GetItemData(bagItem.name)
    if not itemDef or not itemDef.isBag then
        Debug('Warn', ('openBag: not a bag (src=%d name=%s)'):format(src, bagItem.name))
        return
    end

    -- Generate unique ID the first time this bag is opened
    bagItem.metadata = bagItem.metadata or {}
    if not bagItem.metadata.bagId then
        bagItem.metadata.bagId = GenerateBagId()
        SaveInventory(src, false)
    end

    local bagId     = bagItem.metadata.bagId
    local gridW     = itemDef.bagGrid and itemDef.bagGrid.w or 4
    local gridH     = itemDef.bagGrid and itemDef.bagGrid.h or 3
    local maxWeight = itemDef.bagMaxWeight or 20.0

    BagViewers[bagId] = src

    LoadBag(bagId, gridW, gridH, maxWeight, function(bagInv)
        TriggerClientEvent('corex-inventory:client:openBag', src, {
            bagId     = bagId,
            bagSlot   = slotId,
            items     = bagInv.items,
            weight    = bagInv.weight,
            maxWeight = bagInv.maxWeight,
            gridW     = bagInv.gridW,
            gridH     = bagInv.gridH,
            itemsData = GetAllItemsData()
        })
    end)
end)

-- Player closes bag UI
RegisterNetEvent('corex-inventory:server:closeBag', function(bagId)
    local src = source
    if type(bagId) ~= 'string' then return end

    if BagViewers[bagId] == src then
        BagViewers[bagId] = nil
    end

    if BagInventories[bagId] and BagInventories[bagId].isDirty then
        FlushBag(bagId)
    end
end)

-- Move item: player inventory → bag
RegisterNetEvent('corex-inventory:server:moveToBag', function(bagId, playerSlotId, bagX, bagY, targetSlotId)
    local src = source
    if type(bagId) ~= 'string' then return end
    if not TrySetBusy(src) then return end

    local inv    = Inventories[src]
    local bagInv = BagInventories[bagId]

    if not inv or not bagInv or BagViewers[bagId] ~= src then
        ClearBusy(src)
        return
    end

    local itemIndex, item = nil, nil
    for i, it in ipairs(inv.items) do
        if tostring(it.slot) == tostring(playerSlotId) then
            itemIndex, item = i, it
            break
        end
    end

    if not item then
        ClearBusy(src)
        return
    end

    local data = GetItemData(item.name)
    if not data then
        ClearBusy(src)
        return
    end

    -- Bags cannot go inside bags
    if data.isBag then
        Notify(src, 'You cannot put a bag inside a bag', 'error')
        ClearBusy(src)
        return
    end

    local transferCount = math.max(0, math.floor(tonumber(item.count) or 0))
    local added, reason = AddToBag(
        bagInv, item.name, transferCount, item.metadata, tonumber(bagX), tonumber(bagY)
    )
    if not added then
        Notify(src, reason or 'Unable to move item to bag', 'error')
        ClearBusy(src)
        return
    end

    table.remove(inv.items, itemIndex)
    inv.weight = math.max(0, inv.weight - ((tonumber(data.weight) or 0) * transferCount))

    SaveInventory(src)
    SaveBag(bagId)
    TriggerClientEvent('corex-inventory:client:update', src, inv)

    ClearBusy(src)
end)

-- Move item: bag → player inventory
RegisterNetEvent('corex-inventory:server:moveFromBag', function(bagId, bagSlotId, playerX, playerY, targetSlotId)
    local src = source
    if type(bagId) ~= 'string' then return end
    if not TrySetBusy(src) then return end

    local inv    = Inventories[src]
    local bagInv = BagInventories[bagId]

    if not inv or not bagInv or BagViewers[bagId] ~= src then
        ClearBusy(src)
        return
    end

    local itemIndex, item = nil, nil
    for i, it in ipairs(bagInv.items) do
        if tostring(it.slot) == tostring(bagSlotId) then
            itemIndex, item = i, it
            break
        end
    end

    if not item then
        ClearBusy(src)
        return
    end

    local data = GetItemData(item.name)
    if not data then
        ClearBusy(src)
        return
    end

    local transferCount = math.max(0, math.floor(tonumber(item.count) or 0))
    local added, reason = AddToInventory(
        inv, item.name, transferCount, item.metadata, tonumber(playerX), tonumber(playerY)
    )
    if not added then
        Notify(src, reason or 'Unable to move item to inventory', 'error')
        ClearBusy(src)
        return
    end

    table.remove(bagInv.items, itemIndex)
    bagInv.weight = math.max(0, bagInv.weight - ((tonumber(data.weight) or 0) * transferCount))

    SaveBag(bagId)
    SaveInventory(src)
    TriggerClientEvent('corex-inventory:client:update', src, inv)

    ClearBusy(src)
end)

-- Reposition item within bag grid
RegisterNetEvent('corex-inventory:server:moveBagItem', function(bagId, bagSlotId, newX, newY, targetSlotId)
    local src = source
    if type(bagId) ~= 'string' then return end
    if not TrySetBusy(src) then return end

    local bagInv = BagInventories[bagId]
    if not bagInv or BagViewers[bagId] ~= src then
        ClearBusy(src)
        return
    end

    local item = nil
    for _, it in ipairs(bagInv.items) do
        if tostring(it.slot) == tostring(bagSlotId) then
            item = it
            break
        end
    end

    if not item then
        ClearBusy(src)
        return
    end

    local data = GetItemData(item.name)
    local w = data and data.size and data.size.w or 1
    local h = data and data.size and data.size.h or 1

    local changed = false
    if targetSlotId ~= nil then
        local weaponDef = GetWeaponDefinition(item.name)
        changed = InventoryStacking.MergeSlots(
            bagInv.items, bagSlotId, targetSlotId, data, weaponDef ~= nil
        ) == true
    else
        newX, newY = tonumber(newX), tonumber(newY)
        if not newX or not newY then
            ClearBusy(src)
            return
        end
    end

    if targetSlotId == nil and IsSpotFreeInBag(bagInv, newX, newY, w, h, bagSlotId) then
        item.x = newX
        item.y = newY
        changed = true
    end

    if changed then
        SaveBag(bagId)
    end

    TriggerClientEvent('corex-inventory:client:syncBag', src, bagId,
        bagInv.items, bagInv.weight, bagInv.maxWeight)
    ClearBusy(src)
end)

-- Flush bag when its viewer disconnects
AddEventHandler('playerDropped', function()
    local src = source
    for bagId, viewer in pairs(BagViewers) do
        if viewer == src then
            BagViewers[bagId] = nil
            if BagInventories[bagId] and BagInventories[bagId].isDirty then
                FlushBag(bagId)
            end
        end
    end
end)

-- Flush all dirty bags on resource stop
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    for bagId, bagInv in pairs(BagInventories) do
        if bagInv.isDirty then
            FlushBag(bagId)
        end
    end
end)

-- Batched bag persistence — same cadence as player inventories (30s)
CreateThread(function()
    Wait(5000)
    while true do
        Wait(30000)
        for bagId, bagInv in pairs(BagInventories) do
            if bagInv.isDirty then
                FlushBag(bagId)
            end
        end
    end
end)

exports('GetBagContents', function(bagId)
    local bagInv = BagInventories[bagId]
    return bagInv and bagInv.items or nil
end)

RegisterCommand('cleardrops', function()
    DroppedItems = {}
    BroadcastDroppedItems()
    Debug('Info', 'All dropped items cleared')
end, true)

RegisterNetEvent('corex-inventory:server:purchaseShopItem', function(shopName, itemName, amount)
    local src = source

    if type(shopName) ~= 'string' or type(itemName) ~= 'string' then return end
    amount = tonumber(amount) or 1
    if amount < 1 or amount > 100 then return end

    local player = GetPlayer(src)
    if not player then
        Debug('Error', 'Player not found for shop purchase')
        return
    end

    if not Shops then
        Debug('Error', 'Shops table is nil on server')
        TriggerClientEvent('corex-inventory:client:shopPurchaseResult', src, false, 'Shop system error', 0)
        return
    end

    if not Shops[shopName] then
        Debug('Warn', 'Shop not found: ' .. shopName)
        TriggerClientEvent('corex-inventory:client:shopPurchaseResult', src, false, 'Shop not found', 0)
        return
    end

    local shop = Shops[shopName]
    if not IsPlayerNearShop(src, shop) then
        Debug('Warn', ('Shop purchase rejected: player %d too far from %s'):format(src, shopName))
        TriggerClientEvent('corex-inventory:client:shopPurchaseResult', src, false, 'Too far from shop', player.money and player.money.cash or 0)
        return
    end

    local itemConfig = nil

    local lowerTarget = string.lower(itemName)
    for _, config in ipairs(shop.items) do
        if string.lower(config.name) == lowerTarget then
            itemConfig = config
            break
        end
    end

    if not itemConfig then
        Debug('Warn', 'Item not found in shop: ' .. itemName)
        TriggerClientEvent('corex-inventory:client:shopPurchaseResult', src, false, 'Item not available', 0)
        return
    end

    local totalPrice = itemConfig.price * amount
    local currency = itemConfig.currency or 'cash'

    local playerMoney = player.money and player.money[currency] or 0

    if playerMoney < totalPrice then
        TriggerClientEvent('corex-inventory:client:shopPurchaseResult', src, false, 'Not enough money! You have $' .. playerMoney .. ', need $' .. totalPrice, playerMoney)
        return
    end

    local itemAmount = (itemConfig.amount or 1) * amount

    local addSuccess, err = AddItem(src, itemName, itemAmount)
    if not addSuccess then
        TriggerClientEvent('corex-inventory:client:shopPurchaseResult', src, false, 'Inventory full or error: ' .. (err or 'Unknown'), playerMoney)
        return
    end

    local removeOk, removeSuccess = pcall(function()
        return exports['corex-core']:RemoveMoney(src, currency, totalPrice)
    end)

    if not removeOk or not removeSuccess then
        RemoveItem(src, itemName, itemAmount)
        TriggerClientEvent('corex-inventory:client:shopPurchaseResult', src, false, 'Transaction failed - could not remove money', playerMoney)
        return
    end

    local updatedPlayer = GetPlayer(src)
    local newMoney = updatedPlayer and updatedPlayer.money and updatedPlayer.money[currency] or 0

    local itemDef = Items[itemName] or Weapons[itemName] or Weapons[string.upper(itemName)] or Ammo[itemName]
    local itemLabel = itemDef and itemDef.label or itemName

    Debug('Info', 'Player ' .. src .. ' purchased ' .. itemAmount .. 'x ' .. itemLabel .. ' for $' .. totalPrice)

    TriggerClientEvent('corex-inventory:client:shopPurchaseResult', src, true, 'Purchased ' .. itemAmount .. 'x ' .. itemLabel .. ' for $' .. totalPrice, newMoney)
end)

RegisterNetEvent('corex-inventory:server:purchaseVehicleShopItem', function(shopName, model)
    local src = source
    if type(shopName) ~= 'string' or type(model) ~= 'string' then return end

    if PendingVehiclePurchases[src] then
        local player = GetPlayer(src)
        local cash = player and player.money and player.money.cash or 0
        TriggerClientEvent('corex-inventory:client:vehiclePurchaseResult', src, false, 'Wait for the current vehicle to finish deploying.', cash)
        return
    end

    local player = GetPlayer(src)
    if not player then
        TriggerClientEvent('corex-inventory:client:vehiclePurchaseResult', src, false, 'Player not found.', 0)
        return
    end

    local shop = Shops and Shops[shopName]
    if not shop or shop.type ~= 'vehicle' then
        TriggerClientEvent('corex-inventory:client:vehiclePurchaseResult', src, false, 'Vehicle shop not found.', player.money and player.money.cash or 0)
        return
    end

    if not IsPlayerNearShop(src, shop) then
        Debug('Warn', ('Vehicle purchase rejected: player %d too far from %s'):format(src, shopName))
        TriggerClientEvent('corex-inventory:client:vehiclePurchaseResult', src, false, 'Too far from shop.', player.money and player.money.cash or 0)
        return
    end

    local catalogId = shop.catalogId or 'bike_rental'
    local catalog = GetVehicleCatalog(catalogId)
    local vehicleDef = GetVehicleDefinition(catalogId, model)
    if not catalog or not vehicleDef then
        TriggerClientEvent('corex-inventory:client:vehiclePurchaseResult', src, false, 'Vehicle is not available.', player.money and player.money.cash or 0)
        return
    end

    local currency = catalog.currency or 'cash'
    local price = tonumber(vehicleDef.price) or 0
    local balance = player.money and player.money[currency] or 0
    if balance < price then
        TriggerClientEvent('corex-inventory:client:vehiclePurchaseResult', src, false, 'Not enough money.', balance)
        return
    end

    local removed = false
    local removeOk = pcall(function()
        removed = exports['corex-core']:RemoveMoney(src, currency, price)
    end)

    if not removeOk or not removed then
        TriggerClientEvent('corex-inventory:client:vehiclePurchaseResult', src, false, 'Transaction failed.', balance)
        return
    end

    local plate = GenerateRentalPlate()
    PendingVehiclePurchases[src] = {
        shopName = shopName,
        catalogId = NormalizeVehicleKey(catalogId),
        model = NormalizeVehicleKey(model),
        label = vehicleDef.label or model,
        price = price,
        currency = currency,
        itemName = GetPortableVehicleItemName(catalog, vehicleDef),
        plate = plate,
        expiresAt = GetGameTimer() + 15000
    }

    TriggerClientEvent('corex-inventory:client:spawnPurchasedVehicle', src, {
        shopName = shopName,
        catalogId = catalogId,
        model = vehicleDef.model or model,
        plate = plate,
        spawnPoint = shop.spawnPoint or (shop.npc and shop.npc.coords)
    })
end)

RegisterNetEvent('corex-inventory:server:vehicleSpawnSucceeded', function(shopName, model)
    local src = source
    local pending = PendingVehiclePurchases[src]
    if not pending then return end

    if pending.shopName ~= shopName or pending.model ~= NormalizeVehicleKey(model) then
        return
    end

    PendingBikeRegistration[src] = {
        plate = pending.plate,
        catalogId = pending.catalogId or 'bike_rental',
        model = pending.model,
        label = pending.label,
        itemName = pending.itemName or ((Config.PortableVehicles and Config.PortableVehicles.ItemName) or 'portable_vehicle')
    }

    PendingVehiclePurchases[src] = nil

    local player = GetPlayer(src)
    local newMoney = player and player.money and player.money[pending.currency] or 0
    TriggerClientEvent('corex-inventory:client:vehiclePurchaseResult', src, true, pending.label .. ' deployed for $' .. pending.price, newMoney)
end)

RegisterNetEvent('corex-inventory:server:vehicleSpawnFailed', function(shopName, model, reason)
    local src = source
    local pending = PendingVehiclePurchases[src]
    if not pending then return end

    if pending.shopName ~= shopName or pending.model ~= NormalizeVehicleKey(model) then
        return
    end

    PendingVehiclePurchases[src] = nil

    local addOk, addSuccess = pcall(function()
        return exports['corex-core']:AddMoney(src, pending.currency, pending.price)
    end)

    local player = GetPlayer(src)
    local newMoney = player and player.money and player.money[pending.currency] or 0
    local refundMessage = 'Vehicle spawn failed, money refunded.'
    if Config and Config.Debug then
        Debug('Warn', ('Vehicle spawn failed for %s (%s): %s'):format(src, pending.model, tostring(reason)))
    end

    if not addOk or not addSuccess then
        refundMessage = 'Vehicle spawn failed and refund could not be completed.'
    end

    TriggerClientEvent('corex-inventory:client:vehiclePurchaseResult', src, false, refundMessage, newMoney)
end)

RegisterNetEvent('corex-inventory:server:finalizePortableVehicle', function(netId)
    local src = source
    netId = tonumber(netId)
    if not netId or netId == 0 then return end

    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return end
    if GetEntityType(entity) ~= 2 then return end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end

    local pcoords = GetEntityCoords(ped)
    local vcoords = GetEntityCoords(entity)
    if not pcoords or not vcoords then return end

    local maxDistance = (Config.PortableVehicles and Config.PortableVehicles.RegisterDistance) or 18.0
    if #(pcoords - vcoords) > maxDistance then return end

    local player = GetPlayer(src)
    if not player then return end

    local pending = PendingBikeRegistration[src]
    if not pending then return end

    local catalogId = NormalizeVehicleKey(pending.catalogId or 'bike_rental')
    local isAllowed, modelFromHash = IsPortableVehicleModelHash(catalogId, GetEntityModel(entity))
    if not isAllowed then return end

    local plateText = NormalizePlate(GetVehicleNumberPlateText(entity))
    if not PlatesMatch(pending.plate, plateText) then return end

    local modelKey = NormalizeVehicleKey(pending.model or modelFromHash)
    if not modelKey or GetEntityModel(entity) ~= GetHashKey(modelKey) then return end

    local ent = Entity(entity)
    local state = ent.state
    if state.corexPortableVehicleOwner then return end

    state:set('corexPortableVehicleOwner', player.identifier, true)
    state:set('corexPortableVehiclePlate', plateText, true)
    state:set('corexPortableVehicleCatalog', catalogId, true)
    state:set('corexPortableVehicleModel', modelKey, true)
    state:set('corexPortableVehicleLabel', pending.label or modelKey, true)
    state:set('corexPortableVehicleItem', pending.itemName or ((Config.PortableVehicles and Config.PortableVehicles.ItemName) or 'portable_vehicle'), true)

    if catalogId == 'bike_rental' then
        state:set('corexRentalBikeOwner', player.identifier, true)
        state:set('corexRentalBikePlate', plateText, true)
        state:set('corexRentalBikeModel', modelKey, true)
    end

    PendingBikeRegistration[src] = nil
    PendingBikeRefund[src] = nil
    DeployRefundToken[src] = nil
end)

RegisterNetEvent('corex-inventory:server:pickupPortableVehicle', function(netId)
    local src = source

    local now = GetGameTimer()
    local lastAttempt = LastRentalBikePickupAttempt[src]
    if lastAttempt and (now - lastAttempt) < 400 then
        return
    end
    LastRentalBikePickupAttempt[src] = now

    netId = tonumber(netId)
    if not netId or netId == 0 then return end

    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return end
    if GetEntityType(entity) ~= 2 then return end

    local ped = GetPlayerPed(src)
    local pcoords = GetEntityCoords(ped)
    local vcoords = GetEntityCoords(entity)
    if not pcoords or not vcoords then return end

    local pickupDistance = (Config.PortableVehicles and Config.PortableVehicles.PickupDistance) or 4.5
    if #(pcoords - vcoords) > pickupDistance then
        TriggerClientEvent('corex-inventory:client:portableVehicleNotify', src, 'You are too far from the vehicle.', 'error')
        return
    end

    local player = GetPlayer(src)
    if not player then return end

    local state = Entity(entity).state
    local owner = state.corexPortableVehicleOwner or state.corexRentalBikeOwner
    local plate = state.corexPortableVehiclePlate or state.corexRentalBikePlate or NormalizePlate(GetVehicleNumberPlateText(entity))
    local catalogId = NormalizeVehicleKey(state.corexPortableVehicleCatalog or 'bike_rental')
    local model = NormalizeVehicleKey(state.corexPortableVehicleModel or state.corexRentalBikeModel)
    local label = state.corexPortableVehicleLabel or model
    local itemName = state.corexPortableVehicleItem or ((catalogId == 'bike_rental') and 'rental_bicycle' or ((Config.PortableVehicles and Config.PortableVehicles.ItemName) or 'portable_vehicle'))

    if type(owner) ~= 'string' or owner == '' then
        TriggerClientEvent('corex-inventory:client:portableVehicleNotify', src, 'This vehicle cannot be picked up.', 'error')
        return
    end

    if owner ~= player.identifier then
        TriggerClientEvent('corex-inventory:client:portableVehicleNotify', src, 'You can only pick up your own vehicle.', 'error')
        return
    end

    if not model or not IsPortableVehicleModel(catalogId, model) then
        TriggerClientEvent('corex-inventory:client:portableVehicleNotify', src, 'This vehicle cannot be picked up.', 'error')
        return
    end

    local meta = {
        owner = owner,
        catalogId = catalogId,
        plate = NormalizePlate(plate),
        model = model,
        label = label,
        itemName = itemName
    }

    local ok, err = AddItem(src, itemName, 1, meta)
    if not ok then
        TriggerClientEvent('corex-inventory:client:portableVehicleNotify', src, type(err) == 'string' and err or 'Not enough inventory space.', 'error')
        return
    end

    TriggerClientEvent('corex-inventory:client:deleteVehicleByNetId', -1, netId)
end)

local function DeployPortableVehicleFromItem(src, slotId, requestedItemName)
    local inv = Inventories[src]
    if not inv then return end

    local itemName = requestedItemName
    if type(itemName) ~= 'string' or itemName == '' then
        itemName = (Config.PortableVehicles and Config.PortableVehicles.ItemName) or 'portable_vehicle'
    end

    local item = FindInventoryItem(inv, itemName, slotId)
    if not item and itemName ~= 'rental_bicycle' then
        item = FindInventoryItem(inv, 'rental_bicycle', slotId)
    end
    if not item then return end

    itemName = item.name
    local meta = EnsureItemMetadata(item.name, item.metadata)
    local owner = meta.owner
    local catalogId = NormalizeVehicleKey(meta.catalogId or ((itemName == 'rental_bicycle') and 'bike_rental' or 'bike_rental'))
    local plate = NormalizePlate(meta.plate)
    local model = NormalizeVehicleKey(meta.model)
    local label = meta.label or model

    local player = GetPlayer(src)
    if not player then return end

    if type(owner) ~= 'string' or owner ~= player.identifier then
        TriggerClientEvent('corex-inventory:client:portableVehicleNotify', src, 'You cannot use this vehicle.', 'error')
        return
    end

    if not model or not IsPortableVehicleModel(catalogId, model) or plate == '' then
        TriggerClientEvent('corex-inventory:client:portableVehicleNotify', src, 'This vehicle item is invalid.', 'error')
        return
    end

    local removed = RemoveInventoryItemAtSlot(src, item.slot)
    if not removed then return end

    PendingBikeRegistration[src] = {
        plate = plate,
        catalogId = catalogId,
        model = model,
        label = label,
        itemName = itemName
    }
    PendingBikeRefund[src] = {
        itemName = itemName,
        metadata = {
            owner = owner,
            catalogId = catalogId,
            plate = plate,
            model = model,
            label = label,
            itemName = itemName
        }
    }

    local token = math.random(1, 2147483647)
    DeployRefundToken[src] = token

    CreateThread(function()
        Wait((Config.PortableVehicles and Config.PortableVehicles.DeployTimeout) or 16000)
        if DeployRefundToken[src] == token then
            RefundPendingBikeDeploy(src, 'Vehicle deployment timed out; item was returned to your inventory.')
        end
    end)

    TriggerClientEvent('corex-inventory:client:spawnPortableVehicleFromItem', src, {
        catalogId = catalogId,
        model = model,
        plate = plate,
        label = label,
        spawnDistance = Config.PortableVehicles and Config.PortableVehicles.SpawnDistance
    })
end

RegisterNetEvent('corex-inventory:server:deployPortableVehicleFromItem', function(slotId, requestedItemName)
    DeployPortableVehicleFromItem(source, slotId, requestedItemName)
end)

RegisterNetEvent('corex-inventory:server:portableVehicleDeployAborted', function()
    RefundPendingBikeDeploy(source, 'Could not deploy vehicle.')
end)

RegisterNetEvent('corex-inventory:server:finalizeRentalBike', function(netId)
    local src = source
    netId = tonumber(netId)
    if not netId or netId == 0 then return end

    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return end
    if GetEntityType(entity) ~= 2 then return end
    if not IsBikeRentalModelHash(GetEntityModel(entity)) then return end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end

    local pcoords = GetEntityCoords(ped)
    local vcoords = GetEntityCoords(entity)
    if not pcoords or not vcoords then return end
    if #(pcoords - vcoords) > 14.0 then return end

    local player = GetPlayer(src)
    if not player then return end

    local pending = PendingBikeRegistration[src]
    if not pending then return end

    local plateText = NormalizePlate(GetVehicleNumberPlateText(entity))
    if not PlatesMatch(pending.plate, plateText) then return end

    local modelHash = GetEntityModel(entity)
    if modelHash ~= GetHashKey(pending.model) then return end

    local ent = Entity(entity)
    local state = ent.state
    if state.corexRentalBikeOwner then return end

    state:set('corexRentalBikeOwner', player.identifier, true)
    state:set('corexRentalBikePlate', plateText, true)
    state:set('corexRentalBikeModel', pending.model, true)

    PendingBikeRegistration[src] = nil
    PendingBikeRefund[src] = nil
    DeployRefundToken[src] = nil
end)

RegisterNetEvent('corex-inventory:server:pickupRentalBike', function(netId)
    local src = source

    local now = GetGameTimer()
    local lastAttempt = LastRentalBikePickupAttempt[src]
    if lastAttempt and (now - lastAttempt) < 400 then
        return
    end
    LastRentalBikePickupAttempt[src] = now

    netId = tonumber(netId)
    if not netId or netId == 0 then
        return
    end

    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 or not DoesEntityExist(entity) then
        return
    end

    if GetEntityType(entity) ~= 2 or not IsBikeRentalModelHash(GetEntityModel(entity)) then
        return
    end

    local ped = GetPlayerPed(src)
    local pcoords = GetEntityCoords(ped)
    local vcoords = GetEntityCoords(entity)
    if not pcoords or not vcoords then
        return
    end

    if #(pcoords - vcoords) > 4.5 then
        TriggerClientEvent('corex-inventory:client:rentalBikeNotify', src, 'You are too far from the bicycle.', 'error')
        return
    end

    local player = GetPlayer(src)
    if not player then
        return
    end

    local state = Entity(entity).state
    local owner = state.corexRentalBikeOwner
    local plate = state.corexRentalBikePlate or NormalizePlate(GetVehicleNumberPlateText(entity))
    local model = state.corexRentalBikeModel

    if type(owner) ~= 'string' or owner == '' then
        TriggerClientEvent('corex-inventory:client:rentalBikeNotify', src, 'This bicycle cannot be picked up.', 'error')
        return
    end

    if type(model) ~= 'string' or not IsBikeRentalModel(model) then
        TriggerClientEvent('corex-inventory:client:rentalBikeNotify', src, 'This bicycle cannot be picked up.', 'error')
        return
    end

    if owner ~= player.identifier then
        TriggerClientEvent('corex-inventory:client:rentalBikeNotify', src, 'You can only pick up your own bicycle.', 'error')
        return
    end

    local meta = {
        owner = owner,
        plate = NormalizePlate(plate),
        model = NormalizeVehicleKey(model),
    }

    local ok, err = AddItem(src, 'rental_bicycle', 1, meta)
    if not ok then
        TriggerClientEvent('corex-inventory:client:rentalBikeNotify', src, type(err) == 'string' and err or 'Not enough inventory space.', 'error')
        return
    end

    TriggerClientEvent('corex-inventory:client:deleteVehicleByNetId', -1, netId)
end)

RegisterNetEvent('corex-inventory:server:deployRentalBikeFromItem', function(slotId)
    DeployPortableVehicleFromItem(source, slotId, 'rental_bicycle')
end)

RegisterNetEvent('corex-inventory:server:rentalBikeDeployAborted', function()
    RefundPendingBikeDeploy(source, 'Could not deploy vehicle.')
end)

CreateThread(function()
    while true do
        Wait(5000)
        local now = GetGameTimer()
        for src, pending in pairs(PendingVehiclePurchases) do
            if now >= pending.expiresAt then
                local refundSuccess = false
                local addOk = pcall(function()
                    refundSuccess = exports['corex-core']:AddMoney(src, pending.currency, pending.price)
                end)
                PendingVehiclePurchases[src] = nil

                local player = GetPlayer(src)
                local newMoney = player and player.money and player.money[pending.currency] or 0
                TriggerClientEvent('corex-inventory:client:vehiclePurchaseResult', src, false, (addOk and refundSuccess) and 'Vehicle spawn timed out, money refunded.' or 'Vehicle spawn timed out.', newMoney)
            end
        end
    end
end)

exports('GetItemData', function(itemName)
    if type(itemName) ~= 'string' then return nil end
    local lo, up = string.lower(itemName), string.upper(itemName)
    return Items[itemName] or Items[lo] or Items[up]
        or Weapons[itemName] or Weapons[lo] or Weapons[up]
        or Ammo[itemName] or Ammo[lo] or Ammo[up]
end)

exports('GetAllItemsData', function()
    local all = {}
    for k, v in pairs(Items or {}) do all[k] = v end
    for k, v in pairs(Weapons or {}) do all[k] = v end
    for k, v in pairs(Ammo or {}) do all[k] = v end
    return all
end)

exports('GetRarity', function()
    return Rarity
end)
