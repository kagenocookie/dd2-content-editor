local core = require('content_editor.core')
local udb = require('content_editor.database')
local import_handlers = require('content_editor.import_handlers')
local enums = require('content_editor.enums')

local weathers = enums.get_enum('app.WeatherManager.WeatherEnum').valueToLabel
local areas = enums.get_enum('app.WeatherArea').valueToLabel

udb.events.on('get_existing_data', function ()
    local WeatherManager = sdk.get_managed_singleton('app.WeatherManager') ---@type app.WeatherManager
    local data = WeatherManager.mWeatherUserData.mWeatherDataList
    local it = data:GetEnumerator()
    while it:MoveNext() do
        local item = it._current ---@type app.WeatherUserData.WeatherData
        local typeId = item.Weather
        local areaId = item.Area
        local id = areaId * 1000 + typeId
        udb.register_pristine_entity({
            type = 'weather',
            id = id,
            weather_type = typeId,
            area = areaId,
            runtime_instance = item,
            label = (areas[item.Area] or tostring(item.Area)) .. ' ' .. (weathers[item.Weather] or tostring(item.Weather)),
        })
    end
end)

udb.register_entity_type('weather', {
    export = function (instance)
        return { data = import_handlers.export(instance.runtime_instance, 'app.WeatherUserData.WeatherData') }
    end,
    import = function (data, instance)
        instance = instance or {}
        instance.runtime_instance = import_handlers.import('app.WeatherUserData.WeatherData', data.data, instance.runtime_instance)
        return instance
    end,
    insert_id_range = {0, 0},
    root_types = {'app.WeatherUserData'},
})

if core.editor_enabled then
    local editor = require('content_editor.editor')
    local ui = require('content_editor.ui')
    local type_definitions = require('content_editor.definitions')

    type_definitions.override('', {
        ['app.WeatherUserData.WeatherData'] = {
            fields = {
                Area = { extensions = { { type = 'readonly' } } },
                Weather = { extensions = { { type = 'readonly' } } },
            },
        },
        ['app.WeatherManager.VolumetricFogData'] = {
            fields = {
                Density = { uiHandler = ui.handlers.common.float(0.001) },
                DensityAttenuationByHeight = { uiHandler = ui.handlers.common.float(0.001) },
                ScatteringDistribution = { uiHandler = ui.handlers.common.float(0.05) },
            }
        }
    })

    local WeatherManager = sdk.get_managed_singleton('app.WeatherManager') ---@type app.WeatherManager
    editor.define_window('weathers', 'Weathers', function (state)
        WeatherManager = WeatherManager or sdk.get_managed_singleton('app.WeatherManager') ---@type app.WeatherManager
        local nowArea = WeatherManager._NowArea
        local nowWeather = WeatherManager._NowWeatherEnum

        imgui.begin_rect()
        imgui.text('Current weather area: ' .. enums.get_enum('app.WeatherArea').get_label(nowArea))
        imgui.text('Current weather: ' .. enums.get_enum('app.WeatherManager.WeatherEnum').get_label(nowWeather))
        imgui.end_rect(2)
        imgui.spacing()

        local weather = ui.editor.entity_picker('weather', state)
        if weather then
            if imgui.button('Change weather') then
                WeatherManager:changeWeatherLookImmediate(weather.weather_type, weather.area)
            end
            if nowArea == weather.area and nowWeather == weather.weather_type then
                state.autorefresh = select(2, imgui.checkbox('Auto-refresh changes', state.autorefresh))
                imgui.same_line()
                state.refresh_immediate = select(2, imgui.checkbox('Refresh immediately', state.refresh_immediate))
                if not state.autorefresh then
                    imgui.same_line()
                    if imgui.button('Refresh') then
                        if state.refresh_immediate then
                            WeatherManager:changeWeatherLookImmediate(weather.weather_type, weather.area)
                        else
                            WeatherManager:changeWeather(true)
                        end
                    end
                end
            end
            imgui.spacing()
            imgui.indent(8)
            imgui.begin_rect()
            ui.editor.show_entity_metadata(weather)
            local changed = ui.handlers.show(weather.runtime_instance, weather, nil, 'app.WeatherUserData.WeatherData')
            imgui.end_rect(4)
            imgui.unindent(8)
            imgui.spacing()
            if changed and state.autorefresh then
                if state.refresh_immediate then
                    WeatherManager:changeWeatherLookImmediate(weather.weather_type, weather.area)
                else
                    WeatherManager:changeWeather(true)
                end
            end
        end
    end)

    editor.add_editor_tab('weathers')
end
