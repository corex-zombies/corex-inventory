fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'corex-inventory'
description 'COREX Framework - Inventory System'
author 'ABUGIZA'
version '1.0.0'

shared_scripts {
    'config.lua',
    'shared/items.lua',
    'shared/weapons.lua',
    'shared/shops.lua'
}

server_scripts {
    'server/stacking.lua',
    'server/main.lua'
}

client_scripts {
    'client/main.lua',
    'client/rental_bicycle.lua',
    'client/weapons.lua',
    'client/shops.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'html/vehicle-shop.css',
    'html/vehicle-shop.js',
    'html/images/*.png'
}

dependencies {
    'corex-core',
    'ox_lib',
    'ox_target'
}
