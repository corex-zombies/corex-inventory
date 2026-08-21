InventoryStacking = InventoryStacking or {}

local function Integer(value, fallback)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge or number == -math.huge then
        return fallback
    end
    return math.floor(number)
end

local function NamesEqual(left, right)
    return type(left) == 'string'
        and type(right) == 'string'
        and string.upper(left) == string.upper(right)
end

local function DeepCopy(value, seen)
    if type(value) ~= 'table' then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end

    local copy = {}
    seen[value] = copy
    for key, child in pairs(value) do
        copy[DeepCopy(key, seen)] = DeepCopy(child, seen)
    end
    return copy
end

local function DeepEqual(left, right, seen)
    if left == right then return true end
    if type(left) ~= type(right) then return false end
    if type(left) ~= 'table' then return false end

    seen = seen or {}
    if seen[left] == right then return true end
    seen[left] = right

    for key, value in pairs(left) do
        if not DeepEqual(value, right[key], seen) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
end

local function StableSerialize(value, seen)
    local valueType = type(value)
    if valueType ~= 'table' then
        return valueType .. ':' .. tostring(value)
    end

    seen = seen or {}
    if seen[value] then return '<cycle>' end
    seen[value] = true

    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b)
        return type(a) .. ':' .. tostring(a) < type(b) .. ':' .. tostring(b)
    end)

    local parts = {'{'}
    for _, key in ipairs(keys) do
        parts[#parts + 1] = StableSerialize(key, seen)
        parts[#parts + 1] = '='
        parts[#parts + 1] = StableSerialize(value[key], seen)
        parts[#parts + 1] = ';'
    end
    parts[#parts + 1] = '}'
    seen[value] = nil
    return table.concat(parts)
end

function InventoryStacking.GetPolicy(definition, isWeapon)
    definition = definition or {}
    if isWeapon or definition.stackable ~= true then
        return { stackable = false, maxStack = 1 }
    end

    return {
        stackable = true,
        maxStack = math.max(1, Integer(definition.maxStack, 1))
    }
end

function InventoryStacking.MetadataEqual(left, right)
    return DeepEqual(left or {}, right or {})
end

function InventoryStacking.Count(items, itemName)
    local total = 0
    for _, item in ipairs(items or {}) do
        if NamesEqual(item.name, itemName) then
            total = total + math.max(0, Integer(item.count, 0))
        end
    end
    return total
end

function InventoryStacking.HasItem(items, itemName, count)
    count = Integer(count, 1)
    return count >= 1 and InventoryStacking.Count(items, itemName) >= count
end

function InventoryStacking.RequiredNewSlots(items, definition, itemName, count, metadata, isWeapon)
    count = math.max(0, Integer(count, 0))
    local policy = InventoryStacking.GetPolicy(definition, isWeapon)
    local remaining = count

    if policy.stackable then
        for _, item in ipairs(items or {}) do
            if NamesEqual(item.name, itemName)
                and InventoryStacking.MetadataEqual(item.metadata, metadata) then
                local capacity = math.max(0, policy.maxStack - math.max(0, Integer(item.count, 0)))
                remaining = math.max(0, remaining - capacity)
                if remaining == 0 then break end
            end
        end
    end

    if remaining == 0 then return 0 end
    return math.ceil(remaining / policy.maxStack)
end

function InventoryStacking.Remove(items, itemName, count)
    count = Integer(count, 1)
    if count < 1 then return false, 'invalid_count' end
    if InventoryStacking.Count(items, itemName) < count then
        return false, 'not_enough'
    end

    local remaining = count
    for _, item in ipairs(items) do
        if remaining <= 0 then break end
        if NamesEqual(item.name, itemName) then
            local available = math.max(0, Integer(item.count, 0))
            local take = math.min(available, remaining)
            item.count = available - take
            remaining = remaining - take
        end
    end

    for index = #items, 1, -1 do
        if Integer(items[index].count, 0) <= 0 then
            table.remove(items, index)
        end
    end
    return true
end

function InventoryStacking.Add(items, definition, itemName, count, metadata, freePositions, nextSlotId, isWeapon)
    count = Integer(count, 1)
    if type(itemName) ~= 'string' or itemName == '' or count < 1 then
        return false, 'invalid_item'
    end
    if type(nextSlotId) ~= 'function' then return false, 'invalid_slot_factory' end

    local policy = InventoryStacking.GetPolicy(definition, isWeapon)
    local safeMetadata = DeepCopy(metadata or {})
    local remaining = count
    local fills = {}

    if policy.stackable then
        for index, item in ipairs(items or {}) do
            if NamesEqual(item.name, itemName)
                and InventoryStacking.MetadataEqual(item.metadata, safeMetadata) then
                local current = math.max(0, Integer(item.count, 0))
                local capacity = math.max(0, policy.maxStack - current)
                local amount = math.min(capacity, remaining)
                if amount > 0 then
                    fills[#fills + 1] = { index = index, amount = amount }
                    remaining = remaining - amount
                    if remaining == 0 then break end
                end
            end
        end
    end

    local chunks = {}
    while remaining > 0 do
        local amount = math.min(policy.maxStack, remaining)
        chunks[#chunks + 1] = amount
        remaining = remaining - amount
    end

    freePositions = freePositions or {}
    if #freePositions < #chunks then return false, 'no_space' end

    for _, fill in ipairs(fills) do
        local item = items[fill.index]
        item.count = Integer(item.count, 0) + fill.amount
    end

    for index, amount in ipairs(chunks) do
        local position = freePositions[index]
        items[#items + 1] = {
            name = itemName,
            count = amount,
            x = position.x,
            y = position.y,
            slot = nextSlotId(),
            metadata = DeepCopy(safeMetadata)
        }
    end

    return true
end

function InventoryStacking.MergeSlots(items, sourceSlot, targetSlot, definition, isWeapon)
    if tostring(sourceSlot) == tostring(targetSlot) then return false, 'same_slot' end

    local source, target, sourceIndex
    for index, item in ipairs(items or {}) do
        if tostring(item.slot) == tostring(sourceSlot) then
            source, sourceIndex = item, index
        elseif tostring(item.slot) == tostring(targetSlot) then
            target = item
        end
    end
    if not source or not target then return false, 'slot_not_found' end
    if not NamesEqual(source.name, target.name) then return false, 'different_item' end

    local policy = InventoryStacking.GetPolicy(definition, isWeapon)
    if not policy.stackable then return false, 'not_stackable' end
    if not InventoryStacking.MetadataEqual(source.metadata, target.metadata) then
        return false, 'metadata_mismatch'
    end

    local targetCount = math.max(0, Integer(target.count, 0))
    local capacity = math.max(0, policy.maxStack - targetCount)
    if capacity == 0 then return false, 'target_full' end

    local sourceCount = math.max(0, Integer(source.count, 0))
    local moved = math.min(sourceCount, capacity)
    if moved == 0 then return false, 'empty_source' end

    target.count = targetCount + moved
    source.count = sourceCount - moved
    if source.count == 0 then table.remove(items, sourceIndex) end
    return true, moved
end

function InventoryStacking.Serialize(value)
    return StableSerialize(value)
end

return InventoryStacking
