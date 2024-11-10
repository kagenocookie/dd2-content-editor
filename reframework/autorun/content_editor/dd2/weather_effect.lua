local core = require('content_editor.core')
local udb = require('content_editor.database')
local effects = require('content_editor.script_effects')

local WeatherManager = sdk.get_managed_singleton('app.WeatherManager') ---@type app.WeatherManager
effects.register_event_type({
    trigger_type = 'weather',
    category = 'world',
    start = function (entity, ctx)
        local id = entity.data.weatherId
        if not id then return nil end
        local weather = udb.get_entity('weather', id)
        --- @cast weather WeatherEntity

        local lastWeatherArea = WeatherManager._NowArea
        local lastWeatherId = WeatherManager._NowWeatherEnum
        WeatherManager:changeWeatherLookImmediate(weather.weather_type, weather.area)
        return { type = lastWeatherId, area = lastWeatherArea }
    end,
    stop = function (entity, data)
        print('attempting restore weather', data, json.dump_string(data))
        if data then
            WeatherManager:changeWeatherLookImmediate(data.type, data.area)
        end
    end,
})

if core.editor_enabled then
    local ui = require('content_editor.ui')

    effects.ui.set_ui_hook('weather', function (entity, state)
        ui.editor.show_linked_entity_picker(entity.data, 'weatherId', 'weather', state, 'Weather data')
        return changed
    end)
end
