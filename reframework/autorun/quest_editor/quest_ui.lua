if type(_quest_DB) == 'nil' then _quest_DB = {} end
if _quest_DB._ui_ext then return _quest_DB._ui_ext end

local enums = require('quest_editor.enums')
local db = require('quest_editor.database')
local ui = require('content_editor.ui')
local gamedb = require('quest_editor.gamedb')
local utils = require('content_editor.utils')
local udb = require('content_editor.database')
local editor = require('content_editor.editor')
local helpers = require('content_editor.helpers')
local import_handlers = require('content_editor.import_handlers')
local utils_dd2 = require('content_editor.dd2.utils')

local TalkEventManager = sdk.get_managed_singleton('app.TalkEventManager')
--#region Quests

local function imgui_show_quest(questId)
    local quest = db.quests.get(questId)
    if not quest then
        imgui.text('Unknown quest id ' .. tostring(questId))
        return
    end

    imgui.text(tostring(questId) .. ' : ' .. (quest.Log and utils.translate_guid(quest.Log._Title) or '<no title>'))
    imgui.text('Catalog: ' .. tostring(quest.catalog_path or '<none>'))
    imgui.text(quest.Log and utils.translate_guid(quest.Log._Summary) or '<no summary>')

    local questEntity = gamedb.get_quest_entity(questId)

    imgui.text('RecommendedLevel:  '.. tostring(quest.UniqueParam and quest.UniqueParam._RecommendedLevel))

    if questEntity and imgui.button('Reset saved quest data') then
        questEntity.Context:set_ResultNo(-1)
        local values = questEntity.Context:get_ProcessorResultsValues()
        for i, _ in pairs(values) do
            values[i] = -1
        end

        local questTalks = udb.get_entities_where('talk_event', function (e)
            return e--[[@as TalkEventData]].questId == questId
        end)
        for _, qt in ipairs(questTalks) do
            TalkEventManager._RecordDict:Remove(qt.id)
        end
    end
    ui.core.tooltip('Resets all data stored in the current game save regarding this quest. All processor results will be reset to -1.\nMight need to save and reload afterwards to apply and reset everything properly.')

    if questEntity and imgui.button('Update runtime entity') then
        gamedb.upsert_quest_entity(quest)
    end
    ui.core.tooltip("Changes to source data only propagate to runtime after a reload or returning to title screen.\nClick this to force update runtime data, though I'm not sure I've handled every single thing yet.")

    imgui.same_line()
    if imgui.button('Update processor / cast NPC IDs') then
        local procs = udb.get_entities_where('quest_processor', function (proc)
            --- @cast proc QuestProcessorData
            return proc.raw_data.questId == questId
        end)
        quest.contextData.ProcessorIDs = helpers.create_array('System.UInt32', nil, utils.pluck(procs, 'id'))

        --- @type TalkEventData[]
        local talks = udb.get_entities_where('talk_event', function (entity)
            --- @cast entity TalkEventData
            return entity.questId == questId
        end)
        local npcIds = {}
        for _, talk in ipairs(talks) do
            for _, npcCast in pairs(talk.data._CastList) do
                if not utils.table_contains(npcIds, npcCast._OriginalCast) then
                    npcIds[#npcIds+1] = npcCast._OriginalCast
                end
            end
        end
        quest.contextData.CastNPCIDs = import_handlers.import('app.CharacterID[]', npcIds)

        udb.mark_entity_dirty(quest)
    end
    ui.core.tooltip("Update the Processor IDs and Cast NPCs lists with the currently active data.\nAny entites that are not currently loaded will be deemed gone and removed from the list.")

    if questEntity and ui.core.treenode_tooltip('Runtime data', 'The active runtime data for this event, generated from the source data objects.') then
        ui.handlers.show_readonly(questEntity, quest, 'Quest entity', 'app.QuestManager.QuestEntity')
        if imgui.tree_node('Quest entity object explorer') then
            object_explorer:handle_address(questEntity)
            imgui.tree_pop()
        end

        local situationEntity = quest.AISituation and gamedb.get_quest_ai_situation_entity(quest.AISituation.Guid)
        if situationEntity then
            ui.handlers.show_readonly(situationEntity, quest, 'AI Situation', 'app.AISituationEntity')
        end
        if imgui.tree_node('AI Situation object explorer') then
            object_explorer:handle_address(situationEntity)
            imgui.tree_pop()
        end

        imgui.tree_pop()
    end

    local changed = false

    changed = ui.handlers.show_editable(quest, 'TreeNode', quest, 'Quest node', 'app.QuestTreeData.NodeData') or changed
    changed = ui.handlers.show_nullable(quest, 'Variables', '_Variables', 'Variables', 'app.QuestContextData.VariableData', 'app.QuestVariable[]') or changed
    changed = ui.handlers.show_editable(quest.NpcOverrideData, '_Data', quest, 'NPC overrides', 'app.QuestNpcOverride[]') or changed
    changed = ui.handlers.show_editable(quest.Deliver, '_Delivers', quest, 'Delivers', 'app.QuestDeliver[]') or changed
    changed = ui.handlers.show_nullable(quest, 'AfterStoryData', '_AfterStorys', 'After stories', 'app.QuestContextData.AfterStoryData', 'app.QuestAfterStoryData[]') or changed
    changed = ui.handlers.show_editable(quest, 'Log', quest, 'Quest log', 'app.QuestLogResource') or changed
    changed = ui.handlers.show_editable(quest, 'OracleHints', quest, 'Oracle hints', 'app.QuestOracleHintGroup') or changed
    ui.core.tooltip('Required at least if any NpcControl processors are expected for this quest', nil, true)
    changed = ui.handlers.show_editable(quest, 'AISituation', quest, 'AI Situation', 'app.QuestAISituationGenerateParameter') or changed

    ui.core.tooltip("I'm not sure if any how these last 3 arrays matter", nil, true)
    changed = ui.handlers.show_editable(quest.contextData, 'TimeDetectionKeys', quest, 'Time detection keys') or changed
    ui.core.tooltip("I'm not sure if any how these last 3 arrays matter", nil, true)
    changed = ui.handlers.show_editable(quest.contextData, 'ProcessorIDs', quest, 'Processor IDs') or changed
    ui.core.tooltip("I'm not sure if any how these last 3 arrays matter", nil, true)
    changed = ui.handlers.show_editable(quest.contextData, 'CastNPCIDs', quest, 'Cast NPCs') or changed

    if changed then
        -- can we make this cleaner somehow?
        -- basically we just need to ensure all the root instances are inserted into their usual spot in the game's db
        udb.reimport_entity(quest)
    end
end
--#endregion

--#region Events

--- @param ctx EventContext
--- @param entity app.SuddenQuestEntity|nil
local function imgui_show_event_context(ctx, entity)
    local changed, newValue

    imgui.begin_rect()

    local npcIdStr = enums.NPCIDs.valueToLabel[ctx.context._NpcID]
    local name = utils_dd2.translate_character_name(ctx.context._NpcID)
    if ui.treenode_suffix(tostring(ctx.id), tostring(npcIdStr) .. ' : ' .. name .. '  ' .. (ctx.label or '')) then
        ui.editor.show_entity_metadata(ctx)

        if entity then
            if not entity._ExecutableList:Contains(ctx.rootContext) then
                imgui.text_colored('Not executable', editor.get_color('warning'))
                if entity._ExecutedDict:ContainsKey(ctx.id) then
                    ui.core.tooltip('This context has already been executed recently and is now locked. entity._ExecutedDict value: ' .. tostring(entity._ExecutedDict:get_Item(ctx.id)))
                    imgui.same_line()
                    if imgui.button('Unlock') then
                        entity._ExecutedDict:Clear()
                    end
                else
                    ui.core.tooltip("This event can't execute at the moment.\nThis generally means that some required data might be missing, conditions are not fulfilled, or the game is in a state where events don't update like the title screen.")
                end
            end
            local timestampLastExecuted = (entity._LastDay * 24 + entity._LastHour) * 3600
            local eventIntervalSeconds = entity:get_IntervalHour() * 3600

            local timeUntilExecutable = timestampLastExecuted + eventIntervalSeconds - gamedb.get_ingame_timestamp()
            if timeUntilExecutable > 0 then
                imgui.text_colored('Event on cooldown interval', editor.get_color('warning'))
                imgui.same_line()
                imgui.text('Can execute again in ' .. gamedb.format_timestamp(timeUntilExecutable))
                imgui.same_line()
                if imgui.button('Reset last execution time') then
                    entity._LastDay = -1
                    entity._LastHour = -1
                end
            end
        end

        imgui.spacing()
        ui.handlers.show(ctx.context, ctx, nil, 'app.SuddenQuestContextData.ContextData', 'event_context_main_' .. ctx.id)

        if imgui.tree_node('Object explorer') then
            object_explorer:handle_address(ctx.context)
            imgui.tree_pop()
        end
        imgui.tree_pop()
    end
    imgui.end_rect(2)
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

---@param event Event
---@param contextData app.SuddenQuestContextData|nil
---@param uiState table|nil
local function imgui_show_event(event, contextData, uiState)
    local changed, newValue
    local id = event.id
    local entity = gamedb.get_event_entity(id)
    imgui.text('Key: ' .. tostring(id) .. '  -  ' .. tostring(entity and entity:get_NpcRegisterKeyName()))

    local chosenCtx = contextData or entity and entity._CurrentContextData

    local typeId = chosenCtx and chosenCtx._Data._Type
    if not typeId then
        local ctx = db.events.get_first_context(id)
        typeId = ctx and ctx.context._Type or 0
    end
    imgui.text('Type: ' .. tostring(enums.SuddenQuestType.valueToLabel[typeId]))

    if entity and not event_entity_is_synced_with_source_data(entity, event) then
        imgui.same_line()
        if imgui.button('Update runtime entity from source/context changes') then
            db.events.refresh_game_entity(id)
        end
        ui.core.tooltip("Some pending changes need to be manually transferred to the game's runtime entity.")
    else
        imgui.spacing()
        imgui.spacing()
    end

    if entity then
        local timestampLastExecuted = (entity._LastDay * 24 + entity._LastHour) * 3600
        local eventIntervalSeconds = entity:get_IntervalHour() * 3600

        local timeUntilExecutable = timestampLastExecuted + eventIntervalSeconds - gamedb.get_ingame_timestamp()
        if timeUntilExecutable > 0 then
            imgui.text_colored('Event on cooldown interval', editor.get_color('warning'))
            imgui.same_line()
            imgui.text('Can execute again in ' .. gamedb.format_timestamp(timeUntilExecutable))
            imgui.same_line()
            if imgui.button('Reset last execution time') then
                entity._LastDay = -1
                entity._LastHour = -1
            end
        end
    end

    if entity and ui.core.treenode_tooltip('Runtime entity', 'The active runtime data for this event, generated from the source data and contexts.') then
        local charaId = entity:get_NpcID()
        if charaId ~= enums.CharacterID.labelToValue.Invalid then
            imgui.text('Currently chosen character: ' .. enums.CharacterID.valueToLabel[charaId])
        end

        ui.handlers.show_readonly(entity, event, 'Data explorer', 'app.SuddenQuestEntity')
        if imgui.tree_node('Object explorer') then
            object_explorer:handle_address(entity)
            imgui.tree_pop()
        end
        imgui.tree_pop()
    end

    if ui.core.treenode_tooltip('Source data', 'This object is used as a base when generating the runtime entity') then
        imgui.begin_rect()
        ui.editor.show_entity_metadata(event)

        ui.handlers.show(event.selectData, event, nil, 'app.SuddenQuestSelectData', 'event_select_main_' .. event.id)

        if imgui.tree_node('Object explorer') then
            object_explorer:handle_address(event.selectData)
            imgui.tree_pop()
        end
        imgui.end_rect(2)
        imgui.tree_pop()
    end

    if ui.core.treenode_tooltip('Contexts', 'List of context objects that can be picked for this quest, generally used to vary NPCs') then
        local contexts = db.events.get_contexts(id)
        for idx, ctx in ipairs(contexts) do
            imgui.push_id(idx)
            if imgui.button('X') then
                event.selectData._SelectDataArray = helpers.system_array_remove_at(event.selectData._SelectDataArray, idx - 1)
            else
                imgui.same_line()
                imgui_show_event_context(ctx, entity)
            end
            imgui.pop_id()
        end

        if editor.active_bundle and editor.active_bundle ~= '' then
            imgui.begin_rect()
            if imgui.button('New context') then
                --- @type Import.EventContext
                local data = {
                    npcID = enums.CharacterID.labelToValue.Invalid,
                    data = {
                        _TaskSetting = {
                            _ResourceData = 'AppSystem/AI/Situation/TaskData/AITask_1_2_059.user',
                        }
                    },
                }
                local newCtx = udb.insert_new_entity('event_context', editor.active_bundle, data)
                if not newCtx then
                    re.msg('ERROR: entity creation failed')
                else
                    local newPtr = sdk.create_instance('app.SuddenQuestSelectData.SelectData'):add_ref()
                    newPtr._Key = newCtx.id
                    event.selectData._SelectDataArray = helpers.expand_system_array(event.selectData._SelectDataArray, { newPtr })
                    udb.mark_entity_dirty(event)
                end
            end

            if uiState then
                imgui.text('Link existing context')
                local linkCtx = ui.editor.entity_picker('event_context', uiState, 'event_context_link', 'Context to link')
                if linkCtx and utils.table_contains(contexts, linkCtx) then
                    imgui.text('Chosen context is already added for this event')
                elseif linkCtx and imgui.button('Link') then
                    local newPtr = sdk.create_instance('app.SuddenQuestSelectData.SelectData'):add_ref()
                    newPtr._Key = linkCtx.id
                    event.selectData._SelectDataArray = helpers.expand_system_array(event.selectData._SelectDataArray, { newPtr })
                    ui.editor.set_selected_entity_picker_entity(uiState, 'event_context_link', nil)
                    udb.mark_entity_dirty(event)
                end
            end
            imgui.end_rect(2)
        end

        imgui.tree_pop()
    end
end

--#endregion

_quest_DB._ui_ext = {
    show_quest = imgui_show_quest,
    show_event = imgui_show_event,
    show_event_context = imgui_show_event_context,
}

return _quest_DB._ui_ext
