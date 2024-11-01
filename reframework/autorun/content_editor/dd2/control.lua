-- fallback case for the few people whose REF loads up way too early for whatever reason
-- in theory, if one of these dynamic dictionaries are set, they should probably all be
local QuestManager = sdk.get_managed_singleton('app.QuestManager')
local function game_data_is_ready()
    return QuestManager.QuestCatalogDict and QuestManager.QuestCatalogDict:getCount() > 0
end

local version = sdk.find_type_definition('via.version'):get_method('getMainRevisionString'):call(nil)
return {
    game_data_is_ready = game_data_is_ready,
    version = version,
}
