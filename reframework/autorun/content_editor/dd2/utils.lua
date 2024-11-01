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

_userdata_DB.utils_dd2 = {
    translate_character_name = translate_character_name,
    translate_item_name = translate_item_name,
}

return _userdata_DB.utils_dd2
