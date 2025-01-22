local utils = require('content_editor.utils')

local getCharaName = sdk.find_type_definition("app.GUIBase"):get_method("getName(app.CharacterID)")
local function translate_character_name(characterId)
    return getCharaName:call(nil, characterId)
end

local CharacterManager = sdk.get_managed_singleton('app.CharacterManager') ---@type app.CharacterManager
local PawnManager = sdk.get_managed_singleton('app.PawnManager') ---@type app.PawnManager
local ItemManager = sdk.get_managed_singleton('app.ItemManager') ---@type app.ItemManager
local getItemData = sdk.find_type_definition('app.ItemManager'):get_method('getItemData(System.Int32)')
local function translate_item_name(itemId)
    local id = getItemData:call(ItemManager, itemId)
    return id and id:call('get_Name')
end

local TimeSkipManager = sdk.get_managed_singleton("app.TimeSkipManager") ---@type app.TimeSkipManager
local TimeManager = sdk.get_managed_singleton("app.TimeManager") ---@type app.TimeManager
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

--- @return string
local function get_main_pawn_search_id()
    -- the pawn search id is stored in app.PawnDataContext._SearchId, though it doesn't seem to be set on the runtime context on the character directly
    -- we can just use app.GUIBase.CharaData as a proxy instead and let it fetch it from wherever
    local charaData = sdk.create_instance('app.GUIBase.CharaData'):add_ref()--[[@as app.GUIBase.CharaData]]
    local mainPawnId_ch000000_00 = 2283028347
    charaData:call('.ctor(app.CharacterID, System.Boolean)', mainPawnId_ch000000_00, false)
    local pawnId = charaData:get_PawnId()--[[@as string]]
    return pawnId
end

local function get_player()
    return CharacterManager:get_ManualPlayer()
end

local function get_main_pawn()
    local pawn = PawnManager:get_MainPawn()
    return pawn and pawn:get_CachedCharacter()
end

---@return app.Character[]
local function get_player_party()
    local player = CharacterManager:get_ManualPlayer()
    if not player then return {} end

    local list = { player }
---@diagnostic disable-next-line: undefined-field
    local it = PawnManager._PawnCharacterList:GetEnumerator()
    while it:MoveNext() do list[#list+1] = it._current end
    it:Dispose()
    return list
end

local _pos = ValueType.new(sdk.find_type_definition('via.Position'))--[[@as via.Position]]
--- @param chara app.Character
--- @param pos Vector3f|via.vec3|via.Position
local function set_position(chara, pos)
    local tr = chara:get_Transform()
    _pos.x = pos.x
    _pos.y = pos.y
    _pos.z = pos.z
    local now_hr = TimeManager:get_InGameHour()
    local now_min = TimeManager:get_InGameMinute()
    local now_day = TimeManager:get_InGameDay()
    TimeSkipManager:call('requestPlayerWarp', now_hr, now_min, now_day, _pos, tr:get_Rotation(), nil, true, true)
end

local dbms = sdk.get_managed_singleton('app.ContextDBMS') ---@type app.ContextDBMS
local offlineDb = dbms.OfflineDB

local get_key_methods = {
    ['app.UniqueID'] = 'getContextDatabaseKey(app.IContextDatabaseIndexCreator, app.UniqueID)',
    ['app.CharacterID'] = 'getContextDatabaseKey(app.IContextDatabaseIndexCreator, app.CharacterID)',
    ['System.Int64'] = 'getContextDatabaseKey(app.IContextDatabaseIndexCreator, System.Int64)',
}
--- @param id integer|app.UniqueID|app.CharacterID
--- @param type 'app.UniqueID'|'app.CharacterID'|'System.Int64'|nil
--- @return app.ContextDatabaseKey
local db_get_key = function (id, type) return dbms:call(get_key_methods[type or 'app.CharacterID'], offlineDb.IndexCreator, id) end

--- @param recordKey app.ContextDatabaseKey|integer|app.UniqueID|app.CharacterID
--- @param keyType 'app.UniqueID'|'app.CharacterID'|'System.Int64'|nil
--- @return app.ContextDatabase.RecordInfo
local db_get = function (recordKey, keyType) return offlineDb:getRecordInfo(type(recordKey) == 'number' and db_get_key(recordKey, keyType) or recordKey--[[@as any]]) end

local t_go = sdk.find_type_definition('via.GameObject')
local t_holder = sdk.find_type_definition('app.ContextHolder')
local t_chara = sdk.find_type_definition('app.Character')
--- @param character app.CharacterID|app.Character|via.GameObject|app.ContextHolder
--- @param contextType string|RETypeDefinition
local function context_get(character, contextType)
    local typedef = (type(contextType) == 'string' and sdk.find_type_definition(contextType) or contextType)--[[@as RETypeDefinition]]:get_runtime_type()
    if type(character) == 'number' then
        local info = db_get(db_get_key(character, 'app.CharacterID'))
        local record = info and info:get_Record()
        if record and record.ContextDict--[[@as any]]:ContainsKey(typedef) then
            return record.ContextDict[typedef]
        end
        return nil
    end

    local holder
    local t = character--[[@as REManagedObject]]:get_type_definition()
    if t:is_a(t_holder) then
        holder = character
    elseif t:is_a(t_go) then
        holder = utils.gameobject.get_component(character--[[@as via.GameObject]], t_holder)
    elseif t:is_a(t_chara) then
        holder = character:get_Context()
    end
    if not holder then return nil end

    return holder.Contexts--[[@as any]]:ContainsKey(typedef) and holder.Contexts[typedef]:get_CurrentContext() or nil
end

return {
    translate_character_name = translate_character_name,
    translate_item_name = translate_item_name,
    get_ingame_timestamp = get_ingame_timestamp,
    get_main_pawn_search_id = get_main_pawn_search_id,
    get_player = get_player,
    get_main_pawn = get_main_pawn,
    get_player_party = get_player_party,
    set_position = set_position,

    get_context = context_get,

    db = {
        get_key = db_get_key,
        get = db_get,
        dbms = dbms,
        offlineDb = offlineDb,
    },
}
