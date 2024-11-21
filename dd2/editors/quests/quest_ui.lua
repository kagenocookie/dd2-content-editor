if type(_quest_DB) == 'nil' then _quest_DB = {} end
if _quest_DB._ui_ext then return _quest_DB._ui_ext end

local enums = require('editors.quests.enums')
local db = require('editors.quests.database')
local ui = require('content_editor.ui')
local gamedb = require('editors.quests.gamedb')
local utils = require('content_editor.utils')
local udb = require('content_editor.database')
local editor = require('content_editor.editor')
local helpers = require('content_editor.helpers')
local import_handlers = require('content_editor.import_handlers')

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

_quest_DB._ui_ext = {
    show_quest = imgui_show_quest,
}

return _quest_DB._ui_ext
