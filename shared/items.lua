--[[
    COREX Inventory - Items Definition

    Template:
    ['item_name'] = {
        label = 'Display Name',
        weight = 0.5,
        size = {w = 1, h = 1},
        stackable = true,
        maxStack = 10,
        usable = true,
        image = 'item_name.png',       -- fallback if dynamic icon not used
        iconMetadataKey = 'variant',   -- optional: PNG = <metadata value>.png in html/images/
        iconFilenamePattern = 'foo_%s.png', -- optional; omit for plain "%s.png"
        prop = 'prop_name',
        rarity = 'common'           -- common/uncommon/rare/epic/legendary/mythic
    }
]]

Rarity = {
    common = {label = 'COMMON', color = '#8b949e', rgb = {139, 148, 158}},
    uncommon = {label = 'UNCOMMON', color = '#3fb950', rgb = {63, 185, 80}},
    rare = {label = 'RARE', color = '#58a6ff', rgb = {88, 166, 255}},
    epic = {label = 'EPIC', color = '#a371f7', rgb = {163, 113, 247}},
    legendary = {label = 'LEGENDARY', color = '#d29922', rgb = {210, 153, 34}},
    mythic = {label = 'MYTHIC', color = '#f85149', rgb = {248, 81, 73}}
}

Items = {
    -- =====================
    -- WEAPONS - Pistols
    -- =====================
    ['weapon_pistol'] = {
        label = 'Pistol',
        weight = 1.2,
        size = {w = 2, h = 1},
        stackable = false,
        usable = true,
        image = 'weapon_pistol.png',
        rarity = 'common'
    },
    ['weapon_pistol_mk2'] = {
        label = 'Pistol MK2',
        weight = 1.3,
        size = {w = 2, h = 1},
        stackable = false,
        usable = true,
        image = 'pistol_mk2.png',
        rarity = 'uncommon'
    },
    ['weapon_ceramicpistol'] = {
        label = 'Ceramic Pistol',
        weight = 1.0,
        size = {w = 2, h = 1},
        stackable = false,
        usable = true,
        image = 'Ceramic_Pistol.png',
        rarity = 'common'
    },
    ['weapon_doubleaction'] = {
        label = 'Double Action',
        weight = 1.5,
        size = {w = 2, h = 1},
        stackable = false,
        usable = true,
        image = 'revolver_7.png',
        rarity = 'uncommon'
    },
    ['weapon_tecpistol'] = {
        label = 'Tec Pistol',
        weight = 1.4,
        size = {w = 2, h = 1},
        stackable = false,
        usable = true,
        image = 'Tactical_SMG.png',
        rarity = 'rare'
    },
    ['weapon_combatpistol'] = {
        label = 'Combat Pistol',
        weight = 1.2,
        size = {w = 2, h = 1},
        stackable = false,
        usable = true,
        image = 'weapon_combatpistol.png',
        rarity = 'common'
    },
    ['weapon_appistol'] = {
        label = 'AP Pistol',
        weight = 1.3,
        size = {w = 2, h = 1},
        stackable = false,
        usable = true,
        image = 'weapon_appistol.png',
        rarity = 'uncommon'
    },
    ['weapon_snspistol'] = {
        label = 'SNS Pistol',
        weight = 0.8,
        size = {w = 1, h = 1},
        stackable = false,
        usable = true,
        image = 'weapon_snspistol.png',
        rarity = 'common'
    },
    ['weapon_heavypistol'] = {
        label = 'Heavy Pistol',
        weight = 1.6,
        size = {w = 2, h = 1},
        stackable = false,
        usable = true,
        image = 'weapon_heavypistol.png',
        rarity = 'uncommon'
    },
    ['weapon_vintagepistol'] = {
        label = 'Vintage Pistol',
        weight = 1.1,
        size = {w = 2, h = 1},
        stackable = false,
        usable = true,
        image = 'weapon_vintagepistol.png',
        rarity = 'rare'
    },

    -- =====================
    -- WEAPONS - SMGs
    -- =====================
    ['weapon_smg'] = {
        label = 'SMG',
        weight = 2.5,
        size = {w = 2, h = 2},
        stackable = false,
        usable = true,
        image = 'weapon_smg.png',
        rarity = 'uncommon'
    },
    ['weapon_smg_mk2'] = {
        label = 'SMG MK2',
        weight = 2.6,
        size = {w = 2, h = 2},
        stackable = false,
        usable = true,
        image = 'weapon_smg_mk2.png',
        rarity = 'rare'
    },
    ['weapon_combatpdw'] = {
        label = 'Combat PDW',
        weight = 2.8,
        size = {w = 2, h = 2},
        stackable = false,
        usable = true,
        image = 'weapon_combatpdw.png',
        rarity = 'epic'
    },
    ['weapon_microsmg'] = {
        label = 'Micro SMG',
        weight = 2.0,
        size = {w = 2, h = 1},
        stackable = false,
        usable = true,
        image = 'weapon_microsmg.png',
        rarity = 'common'
    },
    ['weapon_minismg'] = {
        label = 'Mini SMG',
        weight = 1.8,
        size = {w = 2, h = 1},
        stackable = false,
        usable = true,
        image = 'weapon_minismg.png',
        rarity = 'common'
    },

    -- =====================
    -- WEAPONS - Rifles
    -- =====================
    ['weapon_assaultrifle'] = {
        label = 'Assault Rifle',
        weight = 3.5,
        size = {w = 3, h = 2},
        stackable = false,
        usable = true,
        image = 'weapon_assaultrifle.png',
        rarity = 'rare'
    },
    ['weapon_assaultrifle_mk2'] = {
        label = 'Assault Rifle MK2',
        weight = 3.8,
        size = {w = 3, h = 2},
        stackable = false,
        usable = true,
        image = 'weapon_assaultrifle_mk2.png',
        rarity = 'epic'
    },
    ['weapon_carbinerifle'] = {
        label = 'Carbine Rifle',
        weight = 3.3,
        size = {w = 3, h = 2},
        stackable = false,
        usable = true,
        image = 'weapon_carbinerifle.png',
        rarity = 'rare'
    },
    ['weapon_compactrifle'] = {
        label = 'Compact Rifle',
        weight = 2.8,
        size = {w = 2, h = 2},
        stackable = false,
        usable = true,
        image = 'weapon_compactrifle.png',
        rarity = 'uncommon'
    },
    ['weapon_specialcarbine'] = {
        label = 'Special Carbine',
        weight = 3.6,
        size = {w = 3, h = 2},
        stackable = false,
        usable = true,
        image = 'weapon_specialcarbine.png',
        rarity = 'epic'
    },

    -- =====================
    -- WEAPONS - Shotguns
    -- =====================
    ['weapon_pumpshotgun'] = {
        label = 'Pump Shotgun',
        weight = 3.5,
        size = {w = 3, h = 1},
        stackable = false,
        usable = true,
        image = 'weapon_pumpshotgun.png',
        rarity = 'uncommon'
    },
    ['weapon_sawnoffshotgun'] = {
        label = 'Sawed-Off Shotgun',
        weight = 2.5,
        size = {w = 2, h = 1},
        stackable = false,
        usable = true,
        image = 'weapon_sawnoffshotgun.png',
        rarity = 'common'
    },
    ['weapon_combatshotgun'] = {
        label = 'Combat Shotgun',
        weight = 4.0,
        size = {w = 3, h = 2},
        stackable = false,
        usable = true,
        image = 'weapon_combatshotgun.png',
        rarity = 'rare'
    },

    -- =====================
    -- AMMO
    -- =====================
    ['pistol_ammo'] = {
        label = 'Pistol Ammo',
        weight = 0.1,
        size = {w = 1, h = 1},
        stackable = true,
        maxStack = 250,
        usable = false,
        image = 'pistol_ammopack.png',
        rarity = 'common'
    },
    ['rifle_ammo'] = {
        label = 'Rifle Ammo',
        weight = 0.15,
        size = {w = 1, h = 1},
        stackable = true,
        maxStack = 250,
        usable = false,
        image = 'rifle_ammo.png',
        rarity = 'uncommon'
    },
    ['smg_ammo'] = {
        label = 'SMG Ammo',
        weight = 0.1,
        size = {w = 1, h = 1},
        stackable = true,
        maxStack = 250,
        usable = false,
        image = 'smg_ammopack.png',
        rarity = 'common'
    },
    ['shotgun_ammo'] = {
        label = 'Shotgun Ammo',
        weight = 0.2,
        size = {w = 1, h = 1},
        stackable = true,
        maxStack = 100,
        usable = false,
        image = 'shotgun_ammo.png',
        rarity = 'common'
    },

    -- =====================
    -- CONSUMABLES
    -- =====================
    ['bread'] = {
        label = 'Bread',
        weight = 0.3,
        size = {w = 1, h = 1},
        stackable = true,
        maxStack = 20,
        usable = true,
        image = 'bread.png',
        rarity = 'common',
        survival = {hunger = 25}
    },
    ['bandage'] = {
        label = 'Bandage',
        weight = 0.1,
        size = {w = 1, h = 1},
        stackable = true,
        maxStack = 10,
        usable = true,
        image = 'bandage.png',
        rarity = 'common'
    },
    ['medkit'] = {
        label = 'Medkit',
        weight = 0.8,
        size = {w = 2, h = 1},
        stackable = true,
        maxStack = 5,
        usable = true,
        image = 'medkit.png',
        rarity = 'rare'
    },

    -- =====================
    -- SURVIVAL - Food
    -- =====================
    ['canned_food'] = {
        label = 'Canned Food',
        weight = 0.4,
        size = {w = 1, h = 1},
        stackable = true,
        maxStack = 15,
        usable = true,
        image = 'canned_food.png',
        rarity = 'common',
        survival = { hunger = 35 }
    },
    ['raw_meat'] = {
        label = 'Raw Meat',
        weight = 0.5,
        size = {w = 1, h = 1},
        stackable = true,
        maxStack = 10,
        usable = true,
        image = 'raw_meat.png',
        rarity = 'common',
        survival = { hunger = 15, infectionRisk = 0.10 }
    },
    ['cooked_meat'] = {
        label = 'Cooked Meat',
        weight = 0.4,
        size = {w = 1, h = 1},
        stackable = true,
        maxStack = 10,
        usable = true,
        image = 'cooked_meat.png',
        rarity = 'uncommon',
        survival = { hunger = 50 }
    },

    -- =====================
    -- SURVIVAL - Drinks
    -- =====================
    ['clean_water'] = {
        label = 'Clean Water',
        weight = 0.5,
        size = {w = 1, h = 1},
        stackable = true,
        maxStack = 15,
        usable = true,
        image = 'clean_water.png',
        rarity = 'common',
        survival = { thirst = 40 }
    },
    ['dirty_water'] = {
        label = 'Dirty Water',
        weight = 0.5,
        size = {w = 1, h = 1},
        stackable = true,
        maxStack = 15,
        usable = true,
        image = 'Dirty_water.png',
        rarity = 'common',
        survival = { thirst = 20, infectionRisk = 0.10 }
    },
    ['energy_drink'] = {
        label = 'Energy Drink',
        weight = 0.3,
        size = {w = 1, h = 1},
        stackable = true,
        maxStack = 10,
        usable = true,
        image = 'energy_drink.png',
        rarity = 'uncommon',
        survival = { thirst = 25, speedBoost = 5000 }
    },

    -- =====================
    -- SURVIVAL - Medical
    -- =====================
    ['antidote'] = {
        label = 'Antidote',
        weight = 0.3,
        size = {w = 1, h = 1},
        stackable = true,
        maxStack = 5,
        usable = true,
        image = 'antidote.png',
        rarity = 'rare',
        survival = { cureInfection = true }
    },
    ['painkillers'] = {
        label = 'Painkillers',
        weight = 0.1,
        size = {w = 1, h = 1},
        stackable = true,
        maxStack = 10,
        usable = true,
        image = 'painkillers.png',
        rarity = 'uncommon',
        survival = { pauseInfection = 300000 }
    },
    ['antibiotics'] = {
        label = 'Antibiotics',
        weight = 0.2,
        size = {w = 1, h = 1},
        stackable = true,
        maxStack = 5,
        usable = true,
        image = 'antibiotics.png',
        rarity = 'rare',
        survival = { reduceInfection = 25 }
    },

    -- =====================
    -- CRAFTING MATERIALS
    -- =====================
    ['cloth'] = {
        label = 'Cloth',
        weight = 0.1,
        size = {w = 1, h = 1},
        stackable = true,
        maxStack = 30,
        usable = false,
        image = 'cloth.png',
        rarity = 'common'
    },
    ['herbs'] = {
        label = 'Herbs',
        weight = 0.1,
        size = {w = 1, h = 1},
        stackable = true,
        maxStack = 20,
        usable = false,
        image = 'herbs.png',
        rarity = 'uncommon'
    },
    ['scrap_metal'] = {
        label = 'Scrap Metal',
        weight = 0.6,
        size = {w = 1, h = 1},
        stackable = true,
        maxStack = 15,
        usable = false,
        image = 'scrap_metal.png',
        rarity = 'common'
    },
    ['chemicals'] = {
        label = 'Chemicals',
        weight = 0.3,
        size = {w = 1, h = 1},
        stackable = true,
        maxStack = 10,
        usable = false,
        image = 'chemicals.png',
        rarity = 'rare'
    },
    ['duct_tape'] = {
        label = 'Duct Tape',
        weight = 0.2,
        size = {w = 1, h = 1},
        stackable = true,
        maxStack = 10,
        usable = false,
        image = 'duct_tape.png',
        rarity = 'uncommon'
    },

    ['rental_bicycle'] = {
        label = 'Bicycle',
        weight = 8.0,
        size = {w = 2, h = 2},
        stackable = false,
        usable = true,
        image = 'default.png',
        iconMetadataKey = 'model',
        rarity = 'common'
    },

    ['portable_vehicle'] = {
        label = 'Vehicle',
        weight = 12.0,
        size = {w = 2, h = 2},
        stackable = false,
        usable = true,
        image = 'default.png',
        iconMetadataKey = 'model',
        rarity = 'rare'
    },

    -- =====================
    -- BLUEPRINTS
    -- =====================
    ['blueprint_medkit'] = {
        label = 'Blueprint: Medkit',
        weight = 0.1,
        size = {w = 1, h = 1},
        stackable = false,
        usable = true,
        image = 'default.png',
        rarity = 'epic'
    },
    ['blueprint_antidote'] = {
        label = 'Blueprint: Antidote',
        weight = 0.1,
        size = {w = 1, h = 1},
        stackable = false,
        usable = true,
        image = 'default.png',
        rarity = 'legendary'
    },
    ['blueprint_pistol_ammo'] = {
        label = 'Blueprint: Pistol Ammo',
        weight = 0.1,
        size = {w = 1, h = 1},
        stackable = false,
        usable = true,
        image = 'default.png',
        rarity = 'rare'
    },
    ['blueprint_smg_ammo'] = {
        label = 'Blueprint: SMG Ammo',
        weight = 0.1,
        size = {w = 1, h = 1},
        stackable = false,
        usable = true,
        image = 'default.png',
        rarity = 'rare'
    },

    -- =====================
    -- BAGS
    -- =====================

    -- isBag = true       → triggers the bag sub-inventory when used
    -- bagGrid            → inner grid dimensions {w, h}
    -- bagMaxWeight       → max total weight the bag can hold (independent of player weight)
    ['big_bag'] = {
        label = 'Big Bag',
        weight = 0.5,
        size = {w = 2, h = 2},
        stackable = false,
        usable = true,
        image = 'big_bag.png',
        rarity = 'uncommon',
        isBag = true,
        bagGrid = {w = 7, h = 7},
        bagMaxWeight = 20.0
    },
}
