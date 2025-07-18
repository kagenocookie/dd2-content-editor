local udb = require('content_editor.database')
local enums = require('content_editor.enums')
local utils = require('content_editor.utils')
local helpers = require('content_editor.helpers')
local import_handlers = require('content_editor.import_handlers')
local gamedb = require('editors.events.events_gamedata')
require('editors.events.scripted_events')

local SuddenQuestManager = sdk.get_managed_singleton('app.SuddenQuestManager') ---@type app.SuddenQuestManager
local GenerateManager = sdk.get_managed_singleton('app.GenerateManager') ---@type app.GenerateManager

--- @class Event : DBEntity
--- @field type 'event'
--- @field selectData app.SuddenQuestSelectData
--- @field scriptEffects integer[]|nil

--- @class EventContext : DBEntity
--- @field type 'event_context'
--- @field context app.SuddenQuestContextData.ContextData
--- @field rootContext app.SuddenQuestContextData

--- @class Import.EventContext : EntityImportData
--- @field data table

--- @class Import.EventData : EntityImportData
--- @field data table
--- @field scriptEffects integer[]|nil

udb.events.on('get_existing_data', function (whitelist)
    local catalogs = gamedb.get_catalogs()
    for _, catalog in ipairs(catalogs) do
        if not whitelist or whitelist.event_context then
            for _, ctx in ipairs(catalog._QuestSuddenTableData._ContextDataArray:get_elements()) do
                --- @cast ctx app.SuddenQuestContextData
                local ignore = whitelist and not whitelist.event_context[ctx._SerialNum] or false
                if not ignore and ctx._SerialNum == 118 and udb.get_entity('event_context', 118) then
                    -- the basegame has a duplicate id for this one SuddenQuestContext...
                    -- I highly doubt they actually have a way to use the second one in any way, so I won't support it either, just pretend it doesn't exist
                    ignore = true
                end

                if not ignore then
                    udb.register_pristine_entity({
                        id = ctx._SerialNum,
                        type = 'event_context',
                        context = ctx._Data,
                        rootContext = ctx,
                    })
                end
            end
        end

        if not whitelist or whitelist.event then
            for _, selectData in ipairs(catalog._QuestSuddenTableData._SelectDataArray:get_elements()) do
                --- @cast selectData app.SuddenQuestSelectData
                if not whitelist or whitelist.event[selectData._SerialNum] then
                    udb.register_pristine_entity({
                        selectData = selectData,
                        type = 'event',
                        id = selectData._SerialNum,
                    })
                end
            end
        end
    end
end)

-- import quest data all at once instead of making new arrays one by one for each entity
udb.events.on('entities_created', function (data)
    --- @cast data QuestDBImportData

    local catalog = gamedb.get_first_catalog()
    if data.event_context then
        catalog._QuestSuddenTableData._ContextDataArray = helpers.expand_system_array(
            catalog._QuestSuddenTableData._ContextDataArray,
            utils.map(data.event_context, function (entity) return entity.rootContext end)
        )
    end
    if data.event then
        catalog._QuestSuddenTableData._SelectDataArray = helpers.expand_system_array(
            catalog._QuestSuddenTableData._SelectDataArray,
            utils.map(data.event, function (entity) return entity.selectData end)
        )
        for _, e in ipairs(data.event) do
            gamedb.refresh_entity(e)
        end
    end
end)

udb.register_entity_type('event_context', {
    import = function (data, entity, shouldImport)
        --- @cast data Import.EventContext
        --- @cast entity EventContext
        if entity.rootContext == nil then
            entity.rootContext = sdk.create_instance('app.SuddenQuestContextData'):add_ref()--[[@as app.SuddenQuestContextData]]
            entity.rootContext._SerialNum = data.id
        end

        if shouldImport or not entity.context then
            entity.context = import_handlers.import('app.SuddenQuestContextData.ContextData', data.data, entity.rootContext._Data)
        end
        entity.rootContext._Data = entity.context
    end,
    export = function (data)
        --- @cast data EventContext
        return {
            data = import_handlers.export(data.context, 'app.SuddenQuestContextData.ContextData')
        }
    end,
    delete = function (ctx)
        --- @cast ctx EventContext
        if not udb.is_custom_entity_id('event_context', ctx.id) then
            return 'not_deletable'
        end

        -- remove ctx from any entity that uses it
        for _, evt in pairs(udb.get_all_entities('event')) do
            -- suboptimal but we don't delete often so it's whatever
            --- @cast evt Event
            local idx = utils.table_index_of(evt.selectData._SelectDataArray:get_elements(), function (ptr) return ptr._Key == ctx.id end)
            while idx ~= 0 do
                evt.selectData._SelectDataArray = helpers.system_array_remove_at(evt.selectData._SelectDataArray, idx - 1)
                idx = utils.table_index_of(evt.selectData._SelectDataArray:get_elements(), function (ptr) return ptr._Key == ctx.id end)
            end
        end

        for _, catalog in ipairs(gamedb.get_catalogs()) do
            catalog._QuestSuddenTableData._ContextDataArray =
                helpers.system_array_remove(catalog._QuestSuddenTableData._ContextDataArray, ctx.rootContext, 'app.SuddenQuestContextData')
        end
    end,
    root_types = {'app.SuddenQuestContextData'},
    insert_id_range = {10000, 999000},
})

udb.register_entity_type('event', {
    import = function (data, instance)
        --- @cast data Import.EventData
        --- @cast instance Event
        instance.selectData = import_handlers.import('app.SuddenQuestSelectData', data.data, instance.selectData)
        instance.selectData._SerialNum = data.id
        instance.scriptEffects = data.scriptEffects
    end,
    root_types = {'app.SuddenQuestSelectData'},
    export = function (data)
        --- @cast data Event
        return {
            data = import_handlers.export(data.selectData, 'app.SuddenQuestSelectData'),
            scriptEffects = data.scriptEffects,
        }
    end,
    delete = function (event)
        --- @cast event Event
        if not udb.is_custom_entity_id('event', event.id) then
            return 'not_deletable'
        end

        SuddenQuestManager._EntityDict--[[@as any]]:Remove(event.id)
        for _, catalog in ipairs(gamedb.get_catalogs()) do
            catalog._QuestSuddenTableData._SelectDataArray =
                helpers.system_array_remove(catalog._QuestSuddenTableData._SelectDataArray, event.selectData, 'app.SuddenQuestSelectData')
        end
    end,
    generate_label = function (entity)
        --- @cast entity Event
        local ctxId = entity.selectData._SelectDataArray
            and entity.selectData._SelectDataArray:get_size() > 0
            and entity.selectData._SelectDataArray:get_element(0)._Key
        local ctx = ctxId and udb.get_entity('event_context', ctxId)
        local type = enums.get_enum('app.QuestDefine.SuddenQuestType').get_label(ctx and ctx.context._Type or 0)
        local label = tostring(enums.get_enum('app.AIKeyLocation').get_label(entity.selectData._StartLocation))
        return tostring(entity.id) .. ' ' .. type .. ' - ' .. label
    end,
    insert_id_range = {10000, 999000},
})
