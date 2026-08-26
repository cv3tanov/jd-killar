fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'cvetanov'
description 'Скрипт за изпълняване на задачи'
version '3.0.0'

shared_script {
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'client.lua',
}

server_scripts {
    'sv_config.lua',
    'server.lua',
}

dependencies {
    'ox_lib',
    'ox_target',
    'ox_inventory',
    'jd-core'
}
