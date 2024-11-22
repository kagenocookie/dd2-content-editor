if type(_quest_DB) == 'nil' then _quest_DB = {} end
if _quest_DB.__config then return _quest_DB.__config end

local utils = require('content_editor.utils')

local config = {
    draw_status_as_window = false,
    devtools = {
        show_locations = false,
        events = {
            overrides = {
                ignore_fail = false,
                ignore_time = false,
                ignore_level = false,
                ignore_scenario = false,
                ignore_sentiment = false,
            },
        },
    },
}

local function load_config()
    local f = json.load_file('quests/settings.json')
    if f then
        config.draw_status_as_window = f.draw_status_as_window or false

        utils.merge_into_table(f.devtools, config.devtools)
        usercontent.__internal.emit('_quests_loadconfig')
    end
end

local function save_config()
    json.dump_file('quests/settings.json', config)
end

load_config()
_quest_DB.__config = {
    data = config,
    save = save_config,
    load = load_config,
}
return _quest_DB.__config
