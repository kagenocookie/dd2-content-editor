if type(_quest_DB) == 'nil' then _quest_DB = {} end
if _quest_DB.importer then return _quest_DB.importer end

local enums = require('editors.quests.enums')
local utils = require('content_editor.utils')
local gamedb = require('editors.quests.gamedb')
local helpers = require('content_editor.helpers')
local import_handlers = require('content_editor.import_handlers')

--- @param instance QuestProcessorData
--- @param procFolderController REManagedObject|nil app.ProcessorFolderController instance for the given quest, will be fetched from game data if unset
--- @return QuestProcessorData
local function import_quest_processor(instance, procFolderController)
    local data = instance.raw_data
    procFolderController = procFolderController or gamedb.get_quest_processor_folder_controller(data.questId)
    if procFolderController == nil then
        -- print("Can't import quest processor, quest or processor folder is inactive")
        instance.runtime_instance = nil
        return instance
    end
    if procFolderController._ProcessorFolder == nil then
        print("Can't import quest processor, processor folder is inactive")
        instance.runtime_instance = nil
        return instance
    end

    local proc = instance.runtime_instance or gamedb.get_quest_processor(instance.id, data.questId)
    if proc == nil then
        print('creating new quest processor', data.questId, instance.id, proc, proc and proc:get_RefQuestController())
        proc = gamedb.create_processor(data.questId, instance.id)
        if proc == nil then return instance end
    else
        print('Updating quest processor', data.questId, instance.id)
    end

    instance.runtime_instance = proc

    if proc then
        if not proc.Process then
            proc.Process = sdk.create_instance('app.QuestProcessor.ProcessEntity'):add_ref()
            proc.Process:set_QuestID(data.questId)
        end
        proc.Process.QuestAction = import_handlers.import('app.quest.action.QuestActionBase', data.QuestAction, proc.Process.QuestAction)
        proc.PrevProcCondition = import_handlers.import('app.QuestProcessor.ProcCondition', data.PrevProcCondition, proc.PrevProcCondition)

        -- activate the processor immediately just to simplify things for mid-game editing
        -- just make sure we don't activate the processor before it's ready
        if proc.Process.QuestAction
            and proc.PrevProcCondition
            and proc:get_CurrentPhase() == enums.QuestProcessorPhase.labelToValue.Uninitialized
            and utils.first(helpers.get_field(proc.Process.QuestAction, '_Param')) ~= nil
        then
            proc:set_CurrentPhase(enums.QuestProcessorPhase.labelToValue.Standby)
        end
    end

    return instance
end

--- @param data Import.Quest
--- @param instance QuestDataSummary|nil
--- @return QuestDataSummary
local function import_quest_data(data, instance)
    if not instance then instance = {}--[[@as any]] end

    instance.cacheData = instance.cacheData or {}
    local questId = instance.id or data.id

    -- could the _IDValue assignments be automated on import?
    instance.contextData = import_handlers.import('app.QuestContextData.ContextData', data.context or {}, instance.contextData)
    instance.contextData._IDValue = questId
    if data.npcOverride then
        instance.NpcOverrideData = instance.NpcOverrideData or sdk.create_instance('app.QuestNpcOverrideData'):add_ref()
        instance.NpcOverrideData._Data = import_handlers.import('app.QuestNpcOverride[]', data.npcOverride, instance.NpcOverrideData._Data)
        instance.NpcOverrideData._IDValue = questId
    end
    if data.afterStory then
        instance.AfterStoryData = instance.AfterStoryData or sdk.create_instance('app.QuestContextData.AfterStoryData'):add_ref()
        instance.AfterStoryData._AfterStorys = import_handlers.import('app.QuestAfterStoryData[]', data.afterStory, instance.AfterStoryData._AfterStorys)
        instance.AfterStoryData._IDValue = questId
    end
    -- deliver data must not be null, game crashes if there's no entry in QuestDeliverManager (some basegame hidden quests don't have it though, no idea why they're fine)
    instance.Deliver = instance.Deliver or sdk.create_instance('app.QuestContextData.DeliverData'):add_ref()
    instance.Deliver._IDValue = questId
    if data.deliver then
        instance.Deliver._Delivers = import_handlers.import('app.QuestDeliver[]', data.deliver, instance.Deliver._Delivers)
    end
    if data.variables then
        instance.Variables = instance.Variables or sdk.create_instance('app.QuestContextData.VariableData'):add_ref()
        instance.Variables._Variables = import_handlers.import('app.QuestVariable[]', data.variables, instance.Variables._Variables)
        instance.Variables._IDValue = questId
    end
    if data.treeData then
        instance.TreeNode = import_handlers.import('app.QuestTreeData.NodeData', data.treeData, instance.TreeNode)
        instance.TreeNode._QuestID = questId
    end
    instance.UniqueParam = import_handlers.import('app.QuestUniqueParamData.Data', {_RecommendedLevel = data.recommendedLevel}, instance.UniqueParam)
    if instance.UniqueParam then
        instance.UniqueParam._IDValue = questId
    end
    if data.aiSituation then
        instance.AISituation = instance.AISituation or sdk.create_instance('app.QuestAISituationGenerateParameter'):add_ref()
        instance.AISituation = import_handlers.import('app.QuestAISituationGenerateParameter', data.aiSituation, instance.AISituation)
        instance.AISituation.QuestID = questId
    end
    if data.log then
        instance.Log = instance.Log or sdk.create_instance('app.QuestLogResource'):add_ref()
        instance.Log = import_handlers.import('app.QuestLogResource', data.log, instance.Log)
        instance.Log._QuestId = questId
    end
    if data.oracleHints then
        instance.OracleHints = instance.OracleHints or sdk.create_instance('app.QuestOracleHintGroup'):add_ref()
        instance.OracleHints = import_handlers.import('app.QuestOracleHintGroup', data.oracleHints, instance.OracleHints)
        instance.OracleHints._QuestID = questId
    end

    return instance
end

_quest_DB.importer = {
    quest = {
        processor = import_quest_processor,
        data = import_quest_data,
    },
}
return _quest_DB.importer
