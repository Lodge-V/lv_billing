fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Custom Dev'
description 'ESX Rechnungssystem V2 - Society & Personal Billing mit NUI'
version '2.0.0'

shared_scripts {
    '@es_extended/imports.lua',
    'config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js'
}
