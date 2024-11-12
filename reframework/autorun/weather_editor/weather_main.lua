local core = require('content_editor.core')
local udb = require('content_editor.database')
local import_handlers = require('content_editor.import_handlers')
local enums = require('content_editor.enums')
local effects = require('content_editor.script_effects')

local weather_utils = require('weather_editor.weather_utils')

local weathers = enums.get_enum('app.WeatherManager.WeatherEnum').valueToLabel
local areas = enums.get_enum('app.WeatherArea').valueToLabel

local WeatherManager = sdk.get_managed_singleton('app.WeatherManager') ---@type app.WeatherManager

--- @class WeatherEntity : DBEntity
--- @field area integer
--- @field weather_type integer
--- @field runtime_instance app.WeatherUserData.WeatherData
--- @field scriptedEffects integer[]|nil

udb.events.on('get_existing_data', function ()
    WeatherManager = WeatherManager or sdk.get_managed_singleton('app.WeatherManager')
    local data = WeatherManager.mWeatherUserData.mWeatherDataList
    local it = data:GetEnumerator()
    while it:MoveNext() do
        local item = it._current ---@type app.WeatherUserData.WeatherData
        local typeId = item.Weather
        local areaId = item.Area
        local id
        if areas[areaId] and weathers[typeId] then
            id = areaId * 100 + typeId
        else
            id = areaId
        end
        udb.register_pristine_entity({
            type = 'weather',
            id = id,
            weather_type = typeId,
            area = areaId,
            runtime_instance = item,
            label = (areas[areaId] or tostring(areaId)) .. ' ' .. (weathers[typeId] or tostring(typeId)),
        })
    end
end)

udb.register_entity_type('weather', {
    export = function (instance)
        --- @cast instance WeatherEntity
        return {
            data = import_handlers.export(instance.runtime_instance, 'app.WeatherUserData.WeatherData'),
            scriptedEffects = instance.scriptedEffects,
        }
    end,
    import = function (data, instance)
        --- @cast instance WeatherEntity|nil
        instance = instance or {}
        instance.runtime_instance = import_handlers.import('app.WeatherUserData.WeatherData', data.data, instance.runtime_instance)
        instance.area = instance.runtime_instance.Area
        instance.weather_type = instance.runtime_instance.Weather
        if not (areas[instance.area] and weathers[instance.weather_type]) then
            instance.runtime_instance.Area = data.id
        end
        if not WeatherManager.mWeatherUserData.mWeatherDataList:Contains(instance.runtime_instance) then
            WeatherManager.mWeatherUserData.mWeatherDataList:Add(instance.runtime_instance)
        end
        instance.scriptedEffects = data.scriptedEffects or {}
        return instance
    end,
    delete = function (instance)
        if instance.id < 10000 then return 'not_deletable' end
        WeatherManager.mWeatherUserData.mWeatherDataList:Remove(instance.runtime_instance)
        return 'ok'
    end,
    insert_id_range = {10000, 9999000},
    root_types = {'app.WeatherUserData'},
})

if core.editor_enabled then
    local editor = require('content_editor.editor')
    local ui = require('content_editor.ui')
    local type_definitions = require('content_editor.definitions')

    type_definitions.override('', {
        ['app.WeatherUserData.WeatherData'] = {
            fields = {
                Area = { extensions = { { type = 'readonly', text = 'Field is read only. It will show None for all custom weathers' } } },
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

    ui.editor.set_entity_editor('weather', function (weather, state)
        --- @cast weather WeatherEntity

        if editor.active_bundle and imgui.button('Clone selected as new weather') then
            local newEntity = udb.clone_as_new_entity(weather, editor.active_bundle) --[[@as WeatherEntity|nil]]
            if newEntity then
                ui.editor.set_selected_entity_picker_entity(state, 'weather', newEntity)
                weather = newEntity
            end
        end

        if imgui.button('Change weather') then
            weather_utils.changeWeather(weather, state.refresh_immediate)
        end
        imgui.same_line()
        state.refresh_immediate = select(2, imgui.checkbox('Immediate weather changes', state.refresh_immediate))
        if not weather_utils.isWeatherScheduleActive() then
            imgui.same_line()
            if imgui.button('Restore normal weather schedule') then
                weather_utils.restoreWeatherSchedule(state.refresh_immediate)
            end
        end
        local changedEffects = effects.ui.show_list(weather, 'scriptedEffects', 'Effects')
        if weather_utils.isCurrentWeather(weather) then
            state.autorefresh = select(2, imgui.checkbox('Auto-refresh changes', state.autorefresh))
            if not state.autorefresh then
                imgui.same_line()
                if imgui.button('Refresh') then
                    weather_utils.changeWeather(weather, state.refresh_immediate)
                end
            end
        end
        imgui.spacing()
        imgui.begin_rect()
        local changed = ui.handlers.show(weather.runtime_instance, weather, nil, 'app.WeatherUserData.WeatherData')
        imgui.end_rect(4)
        imgui.spacing()
        if changed and state.autorefresh then
            weather_utils.changeWeather(weather, state.refresh_immediate)
        end
        return changed or changedEffects
    end)

    editor.define_window('weathers', 'Weathers', function (state)
        local current = weather_utils.currentWeather()

        imgui.begin_rect()
        if current then
            imgui.text('Current weather area: ' .. enums.get_enum('app.WeatherArea').get_label(current.area))
            imgui.text('Current weather: ' .. tostring(weathers[current.weather_type]))
        else
            imgui.text('Active weather not found')
        end
        imgui.end_rect(2)
        imgui.spacing()

        local weather = ui.editor.entity_picker('weather', state)
        if weather then
            ui.editor.show_entity_editor(weather, state)
        end
    end)

    editor.add_editor_tab('weathers')
end
