# corex-inventory

> Tetris-grid inventory with weight, slots, drops, shops, and weapon support.

Part of the [COREX Framework](https://github.com/ABUGIZA/COREX-Framework).

## Install

Drop the `corex-inventory` folder into:
```
server-file/resources/[corex]/corex-inventory/
```

### Required dependencies

Before updating or installing this inventory, install **ox_lib** from:

<https://github.com/overextended/ox_lib>

For **ox_target**, use the COREX-compatible build that supports this framework. Join the COREX Discord channel below and download the posted `ox_target` version from there:

<https://discord.com/channels/1450075262749376558/1499425731095167057>

The normal/public `ox_target` may not include the COREX framework adapter, so portable vehicle pickup can fail if the wrong build is used.

Make sure the load order is:

```cfg
ensure ox_lib
ensure corex-core
ensure ox_target
ensure corex-inventory
```

## Update

Download the latest release ZIP from the **Releases** tab and replace the folder.

## Docs
📖 <https://corex-zombies.gitbook.io/corex-docs/resources/systems/corex-inventory>

---

## Portable vehicles (pick up → inventory → deploy)

Players can turn a deployed, owned vehicle from a COREX vehicle catalog into a single inventory item so it survives server restarts and world wipes. This is no longer bicycle-only: cars, bikes, scooters, helicopters, and future vehicle catalogs can use the same flow. **Requires [ox_target](https://github.com/communityox/ox_target)** (`ensure ox_target` before this resource).

### Flow

1. Player buys a vehicle from any `type = "vehicle"` shop backed by a COREX vehicle catalog.
2. After spawn, the client registers the networked vehicle with the server; the server sets portable vehicle state bags on the entity.
3. Player aims at **their** vehicle with **ox_target** → **Pick up vehicle**.
4. The vehicle is removed from the world and a **`portable_vehicle`** item is added with metadata: `owner`, `catalogId`, `plate`, `model`, `label`, `itemName`.
5. From inventory, **Use** closes the bag, spawns the vehicle in front of the player, and auto-enters the driver seat by default.

Pickup does **not** use the global player “busy” lock (`TrySetBusy`), so it still works if another action left `isBusy` stuck; a short cooldown prevents double-submit spam.

### Ownership & persistence

| Where | What is stored |
|--------|----------------|
| **Inventory row** | `metadata.owner` = COREX `player.identifier`; `metadata.catalogId`, `metadata.model`, `metadata.plate` |
| **World entity** (while parked) | State bags set after successful registration (`corexPortableVehicleOwner`, etc.) |

If the item stays in the backpack, **ownership survives reconnect and restart** because it is saved with the inventory payload.

### Relevant files

| Area | File |
|------|------|
| Pickup / spawn-from-item / ox_target | `client/rental_bicycle.lua` (compat filename; portable vehicle implementation) |
| Shop spawn hook + exports (`SetActiveRentalVehicle`, …) | `client/main.lua` |
| Purchase plate, finalize, pickup, deploy events | `server/main.lua` |
| Item definition | `shared/items.lua` → `portable_vehicle` |

### Server events (reference)

- `corex-inventory:server:finalizePortableVehicle` — attaches ownership to a freshly spawned vehicle (catalog + plate + model match).
- `corex-inventory:server:pickupPortableVehicle` — validates owner, adds `portable_vehicle`, deletes entity for all clients.
- `corex-inventory:server:deployPortableVehicleFromItem` — validates metadata, removes item, spawns client-side deploy + finalize.

Server-side validation uses allowed model hashes from the metadata `catalogId`, not client-only vehicle-class checks. `rental_bicycle` events/items are still accepted as compatibility aliases.

---

## Add a new portable vehicle system

You do **not** need to copy `rental_bicycle.lua` or create new pickup/deploy events for every vehicle type. Add a vehicle catalog in `corex-core`, point a vehicle shop at that catalog, and choose which inventory item should represent the vehicle.

### 1. Add a vehicle catalog

File: `server-file/resources/[corex]/corex-core/shared/vehicles.lua`

```lua
Corex.SharedVehicles["car_rental"] = {
    id = "car_rental",
    label = "Car Rental",
    subtitle = "BASIC CARS",
    currency = "cash",
    purchaseLabel = "Deploy Car",

    -- true = vehicles in this catalog can be picked up with ox_target.
    portable = true,

    -- Optional. If omitted, vehicles use Config.PortableVehicles.ItemName
    -- from corex-inventory/config.lua, which defaults to "portable_vehicle".
    inventoryItem = "portable_vehicle",

    vehicles = {
        {
            model = "blista",
            label = "Blista",
            category = "compact",
            price = 1200,
            description = "Small reliable city car.",

            -- Optional per-vehicle override.
            -- portable = false disables pickup for this vehicle only.
            portable = true
        },
        {
            model = "sanchez",
            label = "Sanchez",
            category = "bike",
            price = 900
        }
    }
}
```

### 2. Add a shop that uses the catalog

File: `server-file/resources/[corex]/corex-inventory/shared/shops.lua`

```lua
Shops["Car Rental"] = {
    label = "Car Rental",
    type = "vehicle",
    catalogId = "car_rental",
    npc = {
        model = "s_m_m_autoshop_02",
        coords = vector4(1518.0, 1708.0, 109.0, 90.0),
        scenario = "WORLD_HUMAN_CLIPBOARD",
        icon = "fa-car",
        interactLabel = "[E] Car Rental",
        interactDistance = 2.5
    },
    spawnPoint = vector4(1514.0, 1705.0, 109.0, 90.0),
    items = {}
}
```

### 3. Use a custom item, if needed

Most systems can use the default `portable_vehicle` item. If you want a custom item like `rental_bicycle`, add it to `shared/items.lua` and set `inventoryItem` on the catalog or vehicle.

```lua
['rental_helicopter'] = {
    label = 'Helicopter',
    weight = 20.0,
    size = {w = 3, h = 3},
    stackable = false,
    usable = true,
    image = 'default.png',
    iconMetadataKey = 'model',
    rarity = 'epic'
}
```

Then in the catalog:

```lua
inventoryItem = "rental_helicopter"
```

You can also set it per vehicle:

```lua
{
    model = "buzzard",
    label = "Buzzard",
    price = 25000,
    inventoryItem = "rental_helicopter"
}
```

### Rules

- `portable = true` on a catalog makes the catalog portable.
- `portable = false` on a vehicle blocks only that vehicle.
- `inventoryItem` on a vehicle overrides `inventoryItem` on the catalog.
- If no `inventoryItem` is set, the system uses `Config.PortableVehicles.ItemName`, default `portable_vehicle`.
- `rental_bicycle` is just a custom item for `bike_rental`; the pickup/deploy logic is still the same portable vehicle system.

---

## Dynamic item icons (NUI)

Icons are chosen in **`html/script.js`** via `getItemImageSrc(item, itemDef)`. Item definitions from **`shared/items.lua`** are sent to the UI as `itemsData`.

### Optional fields on any item

```lua
['some_item'] = {
    label = 'Some item',
    image = 'default.png',          -- fallback if dynamic icon cannot be resolved
    iconMetadataKey = 'model',      -- read this key from item.metadata
    -- iconFilenamePattern is OPTIONAL:
    -- if omitted, pattern defaults to "%s.png" → images/<value>.png
    iconFilenamePattern = 'pack_%s.png',  -- optional; must contain one "%s"
    -- ...
}
```

**Examples**

- Same style as bike models: only set `iconMetadataKey = 'model'` → files **`html/images/bmx.png`**, **`cruiser.png`**, etc. (sanitized lowercase).
- Custom prefix: `iconFilenamePattern = 'loot_%s.png'` → **`html/images/loot_gold.png`** when `metadata.tier` would need `iconMetadataKey = 'tier'` — adjust key/pattern to match your metadata.

Invalid or missing metadata falls back to **`image`**, then **`images/<item_name>.png`**, then **`default.png`** (via `onerror`).

---

## Community
💬 <https://discord.gg/G95rtnb9sg>

## License
Released under the [MIT License](LICENSE).
