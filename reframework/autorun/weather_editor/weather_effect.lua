local core = require('content_editor.core')
local udb = require('content_editor.database')
local effects = require('content_editor.script_effects')
local weather_utils = require('weather_editor.weather_utils')

local WeatherManager = sdk.get_managed_singleton('app.WeatherManager') ---@type app.WeatherManager
effects.register_effect_type({
    trigger_type = 'weather',
    category = 'world',
    start = function (entity, ctx)
        local id = entity.data.weatherId
        if not id then return nil end
        local weather = udb.get_entity('weather', id)
        --- @cast weather WeatherEntity

        weather_utils.changeWeather(weather, true)
    end,
    stop = function ()
        weather_utils.restoreWeatherSchedule(true)
    end,
})

--- @type WeatherEntity|nil
local lastWeather

--- @param weatherEntity WeatherEntity|nil
local function handleWeatherChanged(weatherEntity)
    if weatherEntity == lastWeather then return end

    if lastWeather and lastWeather.scriptedEffects then
        for _, id in ipairs(lastWeather.scriptedEffects) do
            effects.stop(id, lastWeather.runtime_instance)
        end
    end

    lastWeather = weatherEntity

    if weatherEntity and weatherEntity.scriptedEffects then
        for _, id in ipairs(weatherEntity.scriptedEffects) do
            effects.start(id, weatherEntity.runtime_instance)
        end
    end
end

sdk.hook(
    WeatherManager:get_type_definition():get_method('changeWeatherBackWorld'),
    nil,
    function (ret)
        print('changeWeatherBackWorld')
        handleWeatherChanged(weather_utils.currentWeather())
        return ret
    end
)

sdk.hook(
    -- yes, this gets called every unpaused frame. this method seems to directly update the current weather data
    WeatherManager:get_type_definition():get_method('changeWeather'),
    nil,
    function (ret)
        handleWeatherChanged(weather_utils.currentWeather())
        return ret
    end
)

sdk.hook(
    sdk.find_type_definition('app.SaveDataManager'):get_method('loadGameSaveData'),
    nil,
    function (ret)
        handleWeatherChanged(weather_utils.currentWeather())
        return ret
    end
)

udb.events.on('ready', function ()
    handleWeatherChanged(weather_utils.currentWeather())
end)

if core.editor_enabled then
    local ui = require('content_editor.ui')

    effects.ui.set_ui_hook('weather', function (entity, state)
        ui.editor.show_linked_entity_picker(entity.data, 'weatherId', 'weather', state, 'Weather data')
        return changed
    end)
end
