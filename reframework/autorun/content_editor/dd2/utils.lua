if type(_userdata_DB) == 'nil' then _userdata_DB = {} end
if _userdata_DB.utils_dd2 then return _userdata_DB.utils_dd2 end

local getCharaName = sdk.find_type_definition("app.GUIBase"):get_method("getName(app.CharacterID)")
local function translate_character_name(characterId)
    return getCharaName:call(nil, characterId)
end

local ItemManager = sdk.get_managed_singleton('app.ItemManager')
local getItemData = sdk.find_type_definition('app.ItemManager'):get_method('getItemData(System.Int32)')
local function translate_item_name(itemId)
    local id = getItemData:call(ItemManager, itemId)
    return id and id:call('get_Name')
end

local TimeManager = sdk.get_managed_singleton("app.TimeManager")
local field_time_getTimeData = sdk.find_type_definition('app.TimeManager'):get_field('_TimeData')
local method_timeData_day = sdk.find_type_definition('app.TimeManager.TimeData'):get_method('get_InGameDay')
local method_timeData_seconds = sdk.find_type_definition('app.TimeManager.TimeData'):get_method('get_InGameElapsedDaySeconds')

--- Returns the number of ingame seconds elapsed since the game was started
--- @return integer
local function get_ingame_timestamp()
    -- TODO how does this behave in unmoored world?
    local td = field_time_getTimeData:get_data(TimeManager)
    local day = method_timeData_day:call(td)
    local dayTime = method_timeData_seconds:call(td) -- number goes up to 2880
    return day * 86400 + math.floor(dayTime * 30)
end

_userdata_DB.utils_dd2 = {
    translate_character_name = translate_character_name,
    translate_item_name = translate_item_name,
    get_ingame_timestamp = get_ingame_timestamp,
}

return _userdata_DB.utils_dd2
