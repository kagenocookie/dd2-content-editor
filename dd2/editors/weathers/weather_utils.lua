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
        return usercontent.database.get_entity('weather', mgr._NowArea * 100 + WeatherManager._NowWeatherEnum)--[[@as WeatherEntity]]
    else
        return usercontent.database.get_entity('weather', mgr._NowArea)--[[@as WeatherEntity]]
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

--- @param immediate boolean|nil Default true
local function restoreWeatherSchedule(immediate)
    local mgr = manager()
    if mgr._IsBackWorld then
        mgr:changeWeatherBackWorld(mgr._BackWorldPhase)
    else
        -- this method gives us the current WeatherGridAttributeManager.NowArea or if 0, defaults to mWeatherUserData.mWeatherDataList[0].Area
        mgr._WeatherLookData._Area = mgr:getNowAreaInside()
        mgr._WeatherLookData._LookState = 2
        if immediate == true or immediate == nil then
            mgr:setWeatherImmediate()
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