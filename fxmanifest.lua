fx_version 'cerulean'
game 'gta5'

name 'exec_killfeed'
author 'WickmanCapo'
description 'Counter-Strike style killfeed for exec_framework'

version '1.8.1'
ui_page 'html/index.html'

shared_scripts {
    'shared/config.lua',
    'shared/weapons.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    'server/main.lua'
}

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'html/images/*.png'
}

escrow_ignore {
    '.git',
    '.git/**',
    'shared/config.lua',
}

dependency 'exec_framework'
dependency '/assetpacks'
