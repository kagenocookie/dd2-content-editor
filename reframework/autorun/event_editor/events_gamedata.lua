local udb = require('content_editor.database')
local utils = require('content_editor.utils')
local enums = require('content_editor.enums')
local utils_dd2 = require('content_editor.dd2.utils')

local SuddenQuestManager = sdk.get_managed_singleton('app.SuddenQuestManager') ---@type app.SuddenQuestManager
local QuestManager = sdk.get_managed_singleton('app.QuestManager') ---@type app.QuestManager

--- @return app.QuestCatalogData[]
local function get_catalogs()
    QuestManager = QuestManager or sdk.get_managed_singleton('app.QuestManager')
    return QuestManager.QuestCatalogDict--[[@as any]]:getValues():get_elements()
end

local function get_first_catalog()
    local vals = QuestManager.QuestCatalogDict--[[@as any]]:getValues()
    return vals[0]
end

--- @return app.SuddenQuestEntity|nil
local function get_game_entity(id)
    if SuddenQuestManager._EntityDict:call('ContainsKey', id) then
        return SuddenQuestManager._EntityDict:get_Item(id)
    end
    return nil
end

---@param selectData app.SuddenQuestSelectData
---@param contextDataLookup table<integer,app.SuddenQuestContextData|EventContext>
local function upsert_entity(selectData, contextDataLookup)
    local id = selectData._SerialNum

    local entity = get_game_entity(id)
    if entity == nil then
        entity = sdk.create_instance('app.SuddenQuestEntity'):add_ref()--[[@as app.SuddenQuestEntity]]
    end

    entity:set_Key(id)
    entity:set_StartLocation(selectData._StartLocation)
    entity:set_EndLocation(selectData._EndLocation)
    entity:set_RelayLocation(selectData._RelayLocation)
    entity:set_StartCondition(selectData._StartCondition)
    entity:set_StartDistanceMin(selectData._StartDistanceMin)
    entity:set_StartDistanceMax(selectData._StartDistance)
    entity:set_IntervalHour(selectData._IntervalTime._Day * 24.0 + selectData._IntervalTime._Hour)
    entity:set_TimeLimitHour(12.0) -- I think this is the time you have to accept before it auto-cancels

    local dataList = entity:get_ContextDataList()
    ---@diagnostic disable: undefined-field
    dataList:Clear()
    for _, ptr in ipairs(selectData._SelectDataArray:get_elements()) do
        --- @cast ptr app.SuddenQuestSelectData.SelectData
        local ctx = ptr and contextDataLookup[ptr._Key]
        if ctx then
            dataList:Add(ctx.rootContext or ctx)
        end
    end

    if entity._CurrentContextData then
        local ctx = entity._CurrentContextData._Data

        local enemyList = entity._EnemyGenerateList
        --- @type (REManagedObject|table)[]
        local enemyListTable = enemyList:ToArray():get_elements()
        enemyList:Clear()
        for _, enemyInfo in pairs(ctx._EnemySettingList) do
            local inst = utils.first_where(enemyListTable, function (i) return i.ContextData == enemyInfo end)
            if not inst then
                inst = sdk.create_instance('app.SuddenQuestEntity.GenerateEnemyInfo'):add_ref()--[[@as app.SuddenQuestEntity.GenerateEnemyInfo]]
                inst.ContextData = enemyInfo
            end
            enemyList:Add(inst)
        end
    end
    ---@diagnostic enable: undefined-field

    if SuddenQuestManager._EntityDict:ContainsKey(id) then
        SuddenQuestManager._EntityDict[id] = entity
    else
        SuddenQuestManager._EntityDict:Add(id, entity)
    end

    return entity
end

--- @param event Event
local function refresh_game_event_entity(event)
    if event then
        upsert_entity(event.selectData, udb.get_all_entities('event_context'))
    end
end

local function event_get_first_context(id)
    local data = udb.get_entity('event', id)
    if not data or not data.selectData._SelectDataArray or data.selectData._SelectDataArray:get_size() == 0 then return nil end
    local ctxId = data.selectData._SelectDataArray:get_element(0)._Key
    return udb.get_entity('event_context', ctxId)
end

local function event_get_contexts(id)
    local data = udb.get_entity('event', id)
    if not data or not data.selectData._SelectDataArray then return {} end
    return utils.map(data.selectData._SelectDataArray:get_elements(), function (sda) return udb.get_entity('event_context', sda._Key) end)
end

--- @param entity app.SuddenQuestEntity
--- @param data Event
local function event_entity_is_synced_with_source_data(entity, data)
    return entity:get_StartLocation() == data.selectData._StartLocation
        and entity:get_EndLocation() == data.selectData._EndLocation
        and entity:get_RelayLocation() == data.selectData._RelayLocation
        and entity:get_StartCondition() == data.selectData._StartCondition
        and entity:get_StartDistanceMin() == data.selectData._StartDistanceMin
        and entity:get_StartDistanceMax() == data.selectData._StartDistance
        and entity:get_IntervalHour() == data.selectData._IntervalTime._Day * 24.0 + data.selectData._IntervalTime._Hour
end

local function event_get_possible_character_ids(id)
    local evt = udb.get_entity('event', id)
    if not evt then return {} end
    local list = {}
    for _, selectable in ipairs(evt.selectData._SelectDataArray:get_elements()) do
        --- @cast selectable app.SuddenQuestSelectData.SelectData
        local ctx = udb.get_entity('event_context', selectable._Key)
        if not ctx then
            print('Huuhhh??? why is this pointing to an unknown context?', id, selectable._Key)
        else
            list[#list + 1] = ctx.context._NpcID
        end
    end

    return list
end

local function event_get_possible_character_names(id)
    local npcIds = event_get_possible_character_ids(id)
    return utils.map(npcIds, function (npcId) return enums.CharacterID.valueToLabel[npcId] .. ': ' .. tostring(utils_dd2.translate_character_name(npcId)) end)
end

return {
    get_catalogs = get_catalogs,
    get_first_catalog = get_first_catalog,

    get_game_entity = get_game_entity,
    upsert_entity = upsert_entity,
    refresh_entity = refresh_game_event_entity,
    get_first_context = event_get_first_context,
    get_contexts = event_get_contexts,

    event_entity_is_synced_with_source_data = event_entity_is_synced_with_source_data,
    event_get_possible_character_ids = event_get_possible_character_ids,
    event_get_possible_character_names = event_get_possible_character_names,
}
