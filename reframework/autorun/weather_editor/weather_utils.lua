local WeatherManager = sdk.get_managed_singleton('app.WeatherManager') ---@type app.WeatherManager
local function manager()
    WeatherManager = WeatherManager or sdk.get_managed_singleton('app.WeatherManager')
    return WeatherManager
end

local function isBasegameWeather(weatherId)
    return weatherId < 10000
end

--- Change the current weather, gradually or immediately. This disrupts the normal weather schedule and will keep the weather as is permanently until game reload or restoreWeatherSchedule() is called.
--- @param weather WeatherEntity
--- @param immediate boolean
local function changeWeather(weather, immediate)
    if immediate then
        manager():changeWeatherLookImmediate(weather.weather_type, weather.area)
    else
        manager():changeWeatherLook(weather.weather_type, weather.area)
    end
end

--- @return WeatherEntity|nil
local function currentWeather()
    local mgr = manager()

    if isBasegameWeather(mgr._NowArea) then
        return _userdata_DB.database.get_entity('weather', mgr._NowArea * 100 + WeatherManager._NowWeatherEnum)--[[@as WeatherEntity]]
    else
        return _userdata_DB.database.get_entity('weather', mgr._NowArea)--[[@as WeatherEntity]]
    end
end

--- @param weather WeatherEntity
local function isCurrentWeather(weather)
    local mgr = manager()
    return mgr._NowArea == weather.area and mgr._NowWeatherEnum == weather.weather_type
end

local function isWeatherScheduleActive()
    return manager()._WeatherLookData._LookState == 2
end

--- @param immediate boolean|nil
local function restoreWeatherSchedule(immediate)
    local mgr = manager()
    if mgr._IsBackWorld then
        mgr:changeWeatherBackWorld(mgr._BackWorldPhase)
    else
        -- TODO verify, does getNowAreaInside give us "the weather area we're in" or "which weather should be used in interiors"?
        mgr._WeatherLookData._Area = mgr:getNowAreaInside()
        mgr._WeatherLookData._LookState = 2
        if immediate == true or immediate == nil then
            mgr:changeWeather(true)
            mgr:changeWeatherLookImmediate(mgr._NowWeatherEnum, mgr._WeatherLookData._Area)
            mgr._WeatherLookData._LookState = 2
        end
    end
end

return {
    currentWeather = currentWeather,
    isCurrentWeather = isCurrentWeather,
    isBasegameWeather = isBasegameWeather,
    isWeatherScheduleActive = isWeatherScheduleActive,
    changeWeather = changeWeather,
    restoreWeatherSchedule = restoreWeatherSchedule,
}