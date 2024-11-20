if type(_quest_DB) == 'nil' then _quest_DB = {} end
if _quest_DB.database then return _quest_DB.database end

local GuiManager = sdk.get_managed_singleton('app.GuiManager')
local QuestManager = sdk.get_managed_singleton('app.QuestManager')
local QuestLogManager = sdk.get_managed_singleton('app.QuestLogManager')
local SuddenQuestManager = sdk.get_managed_singleton('app.SuddenQuestManager')
local QuestDeliverManager = sdk.get_managed_singleton('app.QuestDeliverManager')
local QuestResourceManager = sdk.get_managed_singleton('app.QuestResourceManager')
local GenerateManager = sdk.get_managed_singleton('app.GenerateManager')
local AISituationManager = sdk.get_managed_singleton('app.AISituationManager')

local enums = require('quest_editor.enums')
local utils = require('content_editor.utils')
local gamedb = require('quest_editor.gamedb')
local importer = require('quest_editor.importer')
local exporter = require('quest_editor.exporter')
local udb = require('content_editor.database')
local helpers = require('content_editor.helpers')
local import_handlers = require('content_editor.import_handlers')
local scripts = require('content_editor.editors.custom_scripts')

require('quest_editor.quest_type_overrides')

local invalidQuests = {} --- @type QuestDataSummary[] Invalid app.SuddenQuestEntity instances with -1 IDs, most of the data is missing since we can't link them properly

local game_catalogs --- @type table<string,REManagedObject|app.QuestCatalogData> Root container for all quest related data

local basegame_sudden_quest_last_select_id = 207
local basegame_sudden_quest_last_context_id = 187

local basegameQuestIds = utils.clone_table(enums.utils.get_enum('app.QuestDefine.ID').valueToLabel)
basegameQuestIds[0] = ''
basegameQuestIds[-1] = ''

local function refresh_game_data()
    local questData = {} --- @type table<integer, QuestDataSummary>
    game_catalogs = gamedb.get_quest_catalogs()
    _quest_DB.catalogs = game_catalogs

    --- @type table<number, QuestDataSummary>
    for catalog_path, catalog in pairs(game_catalogs) do
        for _, ctx in ipairs(catalog.ContextData.ContextDataArray:get_elements()) do
            --- @cast ctx app.QuestContextData.ContextData

            local questlog = QuestLogManager._Catalog:ContainsKey(ctx._IDValue) and QuestLogManager._Catalog:get_MergedCatalog()[ctx._IDValue]._Item or nil
            ---@diagnostic disable-next-line: missing-fields
            local summary = { --- @type QuestDataSummary
                id = ctx._IDValue,
                type = 'quest',
                catalog_path = catalog_path,
                contextData = ctx,
                Log = questlog,
            }
            if summary.id == -1 then
                invalidQuests[#invalidQuests + 1] = summary
            else
                -- summary = u_db.create_entity(summary) --- @type QuestDataSummary
                questData[summary.id] = summary
                udb.create_entity(summary, nil, true)
                udb.mark_entity_dirty(summary, false)
            end
        end

        for _, ctx in ipairs(catalog.ContextData.VariableDataArray:get_elements()) do
            --- @cast ctx app.QuestContextData.VariableData
            local summary = questData[ctx._IDValue]
            if summary then
                summary.Variables = ctx
            elseif ctx._IDValue ~= -1 then
                print('Variables for unknown quest id', ctx._IDValue)
            end
        end

        for _, ctx in ipairs(catalog.ContextData.DeliverDataArray:get_elements()) do
            --- @cast ctx app.QuestContextData.DeliverData
            local summary = questData[ctx._IDValue]
            if summary then
                summary.Deliver = ctx
            elseif ctx._IDValue ~= -1 then
                print('Deliver data for unknown quest id', ctx._IDValue)
            end
        end

        for _, ctx in ipairs(catalog.ContextData.AfterStoryDataArray:get_elements()) do
            --- @cast ctx app.QuestContextData.AfterStoryData
            local summary = questData[ctx._IDValue]
            if summary then
                summary.AfterStoryData = ctx
            elseif ctx._IDValue ~= -1 then
                print('AfterStory data for unknown quest id', ctx._IDValue)
            end
        end

        for _, overrideData in ipairs(catalog._NpcOverrideTableData._Table:get_elements()) do
            --- @cast overrideData app.QuestNpcOverrideData
            local id = overrideData._IDValue
            local summary = questData[id]
            if summary then
                summary.NpcOverrideData = overrideData
            elseif id ~= -1 then
                print('NPC Override data for unknown quest id', id)
            end
        end

        for _, oracle in ipairs(catalog._QuestOracleData._QuestHints:get_elements()) do
            --- @cast oracle app.QuestOracleHintGroup
            local id = oracle._QuestID
            local summary = questData[id]
            if summary then
                summary.OracleHints = oracle
            elseif id ~= -1 then
                print('Oracle hint data for unknown quest id', id)
            end
        end

        -- what's so unique about recommended levels lol?
        for _, recData in ipairs(catalog._QuestUniqueParamData._DataList:ToArray():get_elements()) do
            --- @cast recData app.QuestUniqueParamData.Data
            local id = recData._IDValue
            local summary = questData[id]
            if summary then
                summary.UniqueParam = recData
            elseif id ~= -1 then
                print('NPC Override data for unknown quest id', id)
            end
        end

        for _, treeData in ipairs(catalog.TreeData.NodeDataArray:get_elements()) do
            --- @cast treeData app.QuestTreeData.NodeData
            local id = treeData._QuestID
            local summary = questData[id]
            if summary then
                summary.TreeNode = treeData
            elseif id ~= -1 then
                print('Tree node data for unknown quest id', id)
            end
        end

        for i = 0, catalog._QuestRewardTableData._DataList:get_Count() - 1 do
            local reward = catalog._QuestRewardTableData._DataList[i]
            udb.register_pristine_entity({
                id = reward._NameHash,
                type = 'quest_reward',
                runtime_instance = reward,
                _basegame = reward._NameHash >= 33252694,
            })
        end
    end

    -- NOTE: there's a reference to the array in AISituationManager._RootSituationParamList as well, but the situation master seems to be the source so I'm using that instead
    -- since it's the same reference, both should get updated at the same time
    for _, rootParam in pairs(AISituationManager._SituationMaster.RootSituationParamList) do
        local firstChild = rootParam.ChildSituations:get_size() > 0 and rootParam.ChildSituations[0]
        -- basegame has all quest situations in the one root param entry, therefore if the first one is correct type, all of them should be
        -- this is user file AppSystem/AI/Situation/GenerateParameter/RootQuestSituationParam.user
        if firstChild ~= nil and firstChild:get_type_definition():get_full_name() == 'app.QuestAISituationGenerateParameter' then
            for _, child in pairs(rootParam.ChildSituations) do
                --- @cast child app.QuestAISituationGenerateParameter
                local summary = questData[child.QuestID]
                if summary then
                    summary.AISituation = child
                else
                    print('Quest AI Situation data for unknown quest id', child.QuestID)
                end
            end
        end
    end
end

--#region Hooks for making custom quest additions work

local function override_enum_getter(class, getter_method, field_name, basegame_whitelist)
    sdk.hook(
        sdk.find_type_definition(class):get_method(getter_method),
        function (args)
            thread.get_hook_storage().id = sdk.to_managed_object(args[2])[field_name]
        end,
        function (ret)
            local id = thread.get_hook_storage().id
            -- checking whitelist so we return basegame quests as is without needing to override with to_ptr
            -- though I'm not sure if it makes an actual difference
            if not basegame_whitelist[id] then
                return sdk.to_ptr(id)
            end
            return ret
        end
    )
end

-- these getters seem to cast the integer IDValues to an enum, and return -1 if it's not in the enum
-- so we need to override them to force our real values to return since we can't modify enums
-- these are generally only called once on launch/load so they're not really a perf issue
override_enum_getter('app.QuestContextData.DeliverData', 'get_ID', '_IDValue', basegameQuestIds)
override_enum_getter('app.QuestContextData.ContextData', 'get_ID', '_IDValue', basegameQuestIds)
override_enum_getter('app.QuestContextData.AfterStoryData', 'get_ID', '_IDValue', basegameQuestIds)
override_enum_getter('app.QuestContextData.VariableData', 'get_ID', '_IDValue', basegameQuestIds)
override_enum_getter('app.QuestController', 'get_QuestIDValue', '_QuestID', basegameQuestIds)

-- we need to do this manually because I think the game's implementation does an Enum.Parse on the folder name to get the quest id
-- would be nice to make it automatic, but this workaround works
sdk.hook(
    sdk.find_type_definition('app.QuestSceneCollector'):get_method('start'),
    function (args)
        -- print('QuestSceneCollector start')
        local this = sdk.to_managed_object(args[2]) --[[@as app.QuestSceneCollector]]
        for _, quest in ipairs(udb.get_all_entities('quest')) do
            -- only do this for quests that are actually modified (e.g. in a bundle)
            if udb.get_entity_bundle(quest) and not this:get_QuestSceneFolderDict():ContainsKey(quest.id) then
                local questfolder = this:get_GameObject():get_Folder()
                local ourFolder = questfolder:find('qu' .. quest.id)
                if ourFolder then
                    print('Adding quest scene folder', quest.id, ourFolder:get_Name())
                    this:get_QuestSceneFolderDict()[quest.id] = ourFolder
                else
                    print('Scene folder not found for quest', quest.id)
                end
            end
        end
    end
)

sdk.hook(
    sdk.find_type_definition('app.ProcessorFolderController'):get_method('collectProcessors'),
    function (args)
        thread.get_hook_storage().this = sdk.to_managed_object(args[2])
    end,
    function (ret)
        local this = thread.get_hook_storage().this
        local questId = this._QuestController._QuestID

        --- @type QuestProcessorData[]
        local editedProcessors = udb.get_entities_where('quest_processor', function (proc)
            --- @cast proc QuestProcessorData
            return proc.raw_data.questId == questId
        end)

        for _, proc in ipairs(editedProcessors) do
            if not proc.disabled then
                importer.quest.processor(proc, this)
            end
        end
        return ret
    end
)

-- ensure any runtime changes are stored in the raw_data field
-- also remove cached runtime instance
sdk.hook(
    sdk.find_type_definition('app.QuestProcessor'):get_method('onDestroy'),
    function (args)
        local this = sdk.to_managed_object(args[2])--[[@as app.QuestProcessor]]
        local procEntity = udb.get_entity('quest_processor', this.ProcID)
        --- @cast procEntity QuestProcessorData|nil
        if procEntity and procEntity.runtime_instance then
            procEntity.raw_data = udb.export_entity(procEntity).data
            procEntity.runtime_instance = nil
        end
    end
)

-- ensure we re-create the quest entities whenever data is reset
sdk.hook(
    sdk.find_type_definition('app.QuestManager'):get_method('registerQuestCatalog'),
    nil,
    function ()
        for _, e in ipairs(udb.get_all_entities('quest')) do
            --- @cast e QuestDataSummary
            if udb.get_entity_bundle(e) then
                gamedb.upsert_quest_entity(e)
            end
        end
    end
)

scripts.define_script_hook(
    'app.quest.condition.CheckLocalArea',
    'evaluate',
    function (args)
        local target = sdk.to_managed_object(args[2]) --[[@as app.quest.condition.CheckLocalArea]]
        return target._Param._Type >= 100000 and target._Param._Type or nil
    end
)

scripts.define_script_hook_editor_override(
    'app.quest.condition.CheckLocalAreaParam',
    function (target)
        return target._Type and target._Type >= 100000 and target._Type or nil
    end,
    function (target, isHook)
        target._Type = isHook and 100000 or 0
    end,
    function (target, id)
        target._Type = id
    end,
    'The script should return true or false'
)

--#endregion

--- @type table<integer, string[]>
local perQuestVarHashes = {}

---@param overrideValueToLabels nil|table<string, string>
---@return EnumSummary
local function extract_game_variables_into_enum(overrideValueToLabels)
    -- NOTE: the name hashes aren't globally unique so if we're gonna use them as an enum, we need to handle duplicates properly
    local labelToValue = {}
    local valueToLabel = {}
    utils.clear_table(perQuestVarHashes)

    local knownLabels = overrideValueToLabels or {}

    for _, catalog in pairs(gamedb.get_quest_catalogs()) do
        for _, vars in pairs(catalog.ContextData.VariableDataArray) do
            local qid = vars._IDValue
            for _, var in pairs(vars._Variables) do
                ---@cast var app.QuestVariable

                local label
                if knownLabels and knownLabels[tostring(var._NameHash)] then
                    label = knownLabels[tostring(var._NameHash)]
                else
                    label = string.format('qu%d_%03d', qid, var._SerialNumber)

                    if valueToLabel[var._NameHash] then
                        print('WARNING: duplicate quest variable hash: ' .. var._NameHash)
                    end
                    valueToLabel[var._NameHash] = label
                end
                labelToValue[label] = var._NameHash

                local pq = perQuestVarHashes[qid] or {}
                pq[#pq+1] = label
                perQuestVarHashes[qid] = pq
            end
        end
    end
    return enums.utils.create_enum(labelToValue, 'QuestVariables', true)
end

local function load_quest_variables_enum()
    local overrides = json.load_file('quests/enums/QuestVariables.overrides.json')

    local enum = extract_game_variables_into_enum(overrides)
    enums.QuestVariables = enum
    enums.mark_enum_defaults(enum)

    local enumfile = json.load_file('quests/enums/QuestVariables.json')
    if not enumfile then
        enums.dump_enum('QuestVariables')
        print('Creating initial questvar enum')
        return
    end

    if not overrides then
        json.dump_file('quest/enums/QuestVariables.overrides.json', enum.valueToLabel)
    end
end

local function get_mapped_data_table()
    error('Unimplemented')
    local quest_dump = {}
    for questId, quest in pairs(udb.get_all_entities('quest')) do
        -- local ctg = quest.catalog_path
        -- quest_dump[ctg] = quest_dump[ctg] or {}
        quest_dump[questId] = exporter.raw_dump_object(quest)
    end

    return quest_dump
end

local function get_full_raw_data()
    local _, catalog = next(game_catalogs)
    return exporter.raw_dump_object(catalog)
end

--#region DB Queries

--- @param id integer
--- @return QuestDataSummary|nil
local function quest_get_by_id(id)
    return udb.get_entity('quest', id) --- @type QuestDataSummary|nil
end

--- @return app.QuestVariable|nil
local function quest_get_variable(questId, variableNameHash)
    local quest = quest_get_by_id(questId)
    if not quest then return nil end

    if not quest.cacheData.varLookup then
        quest.cacheData.varLookup = utils.group_by_unique(quest.Variables._Variables:get_elements(), '_NameHash')
    end
    return (quest.cacheData.varLookup or {})[variableNameHash]
end

--- Get a list of all variable names belonging to a quest
--- @param questId integer
--- @return string[] variableNames
local function get_quest_variables(questId)
    return perQuestVarHashes[questId] or {}
end

--- Get a list of all variable names belonging to a quest
--- @param questId integer
--- @return EnumSummary|nil
local function get_quest_variables_enum(questId)
    local names = perQuestVarHashes[questId]
    if not names then return nil end
    local labelToValue = {}
    for _, name in ipairs(names) do
        labelToValue[name] = enums.QuestVariables.labelToValue[name]
    end
    -- print('temp enum', json.dump_string(labelToValue))
    return enums.utils.create_enum(labelToValue, 'QuestVariables_' .. questId, false)
end


---@diagnostic disable: return-type-mismatch
local function is_vanilla_quest(id) return basegameQuestIds[id] end
---@diagnostic enable: return-type-mismatch

--#region DB management utils

local function remove_array_elem_if_exists(element, arrayContainer, arrayField, elementClassname)
    local arr = arrayContainer[arrayField]
    if element and utils.table_contains(arr, element) then
        arrayContainer[arrayField] = helpers.system_array_remove(arr, element, elementClassname)
    end
end
--#endregion

udb.events.on('get_existing_data', function ()
    refresh_game_data()
end)

--- @class QuestDBImportData
--- @field event Event[]|nil
--- @field event_context EventContext[]|nil
--- @field quest QuestDataSummary[]|nil
--- @field quest_processor QuestProcessorData[]|nil

-- import quest data all at once instead of making new arrays one by one for each entity
udb.events.on('data_imported', function (data)
    --- @cast data QuestDBImportData

    if data.quest then
        for _, e in ipairs(data.quest) do
            gamedb.upsert_quest_entity(e)
        end
    end
end)

udb.register_entity_type('quest', {
    import = function (data, instance)
        --- @cast instance QuestDataSummary|nil
        --- @cast data Import.Quest

        -- TODO what's quest progress data?
        instance = instance or {}
        instance = importer.quest.data(data, instance)
        return instance
    end,
    export = function (data)
        --- @cast data QuestDataSummary
        --- @type Import.Quest
        return {
            catalog = data.catalog_path,
            context = import_handlers.export(data.contextData, 'app.QuestContextData.ContextData'),
            npcOverride = data.NpcOverrideData and import_handlers.export(data.NpcOverrideData._Data, 'app.QuestNpcOverride[]') or {},
            afterStory = data.AfterStoryData and import_handlers.export(data.AfterStoryData._AfterStorys, 'app.QuestAfterStoryData[]') or nil,
            deliver = data.Deliver and import_handlers.export(data.Deliver._Delivers, 'app.QuestDeliver[]') or {},
            variables = data.Variables and import_handlers.export(data.Variables._Variables, 'app.QuestVariable[]') or nil,
            recommendedLevel = data.UniqueParam and data.UniqueParam._RecommendedLevel or 0,
            log = data.Log and import_handlers.export(data.Log, 'app.QuestLogResource') or nil,
            oracleHints = data.OracleHints and import_handlers.export(data.OracleHints, 'app.QuestOracleHintGroup'),
            aiSituation = data.AISituation and import_handlers.export(data.AISituation, 'app.QuestAISituationGenerateParameter'),
            treeData = import_handlers.export(data.TreeNode, 'app.QuestTreeData.NodeData')
        }
    end,
    root_types = {'app.QuestCatalogData', 'app.QuestContext', 'app.QuestManager.QuestEntity'},
    delete = function (instance)
        --- @cast instance QuestDataSummary
        if is_vanilla_quest(instance.id) then
            return 'not_deletable'
        end

        local catalog = gamedb.get_first_quest_catalog()
        remove_array_elem_if_exists(instance.AfterStoryData, catalog.ContextData, 'AfterStoryDataArray', 'app.QuestContextData.AfterStoryData')
        remove_array_elem_if_exists(instance.contextData, catalog.ContextData, 'ContextDataArray', 'app.QuestContextData.ContextData')
        remove_array_elem_if_exists(instance.Deliver, catalog.ContextData, 'DeliverDataArray', 'app.QuestContextData.DeliverData')
        remove_array_elem_if_exists(instance.Variables, catalog.ContextData, 'VariableDataArray', 'app.QuestContextData.VariableData')
        remove_array_elem_if_exists(instance.TreeNode, catalog.TreeData, 'NodeDataArray', 'app.QuestTreeData.NodeData')
        remove_array_elem_if_exists(instance.NpcOverrideData, catalog._NpcOverrideTableData, '_Table', 'app.QuestNpcOverrideData')

        if instance.UniqueParam and catalog._QuestUniqueParamData._DataList:Contains(instance.UniqueParam) then
            catalog._QuestUniqueParamData._DataList:Remove(instance.UniqueParam)
        end

        if QuestResourceManager.ResourceControllerDict:ContainsKey(instance.id) then
            QuestResourceManager.ResourceControllerDict:Remove(instance.id)
        end

        if QuestManager.EntityDict:ContainsKey(instance.id) then
            QuestManager.EntityDict:Remove(instance.id)
        end
        if QuestManager.CurrentActiveQuestIDList:Contains(instance.id) then
            QuestManager.CurrentActiveQuestIDList:Remove(instance.id)
        end
        if QuestDeliverManager._ContextDict:ContainsKey(instance.id) then
            QuestDeliverManager._ContextDict:Remove(instance.id)
        end

        local collector = gamedb.get_quest_scene_collector()
        if collector then
            local dict = collector--[[@as any]]:get_QuestSceneFolderDict()
            if dict:ContainsKey(instance.id) then
                dict:Remove(instance.id)
            end
            QuestManager.Tree:setup(catalog, collector, QuestManager.EntityDict)
            if QuestManager.Tree.AllNodeDict:ContainsKey(instance.id) then
                local nodeItem = QuestManager.Tree.AllNodeDict[instance.id]
                QuestManager.Tree.AllNodeDict:Remove(instance.id)
                QuestManager.Tree.ActiveNodeList:Remove(nodeItem)
                QuestManager.Tree.StandbyNodeList:Remove(nodeItem)
                QuestManager.Tree.DisposalNodeList:Remove(nodeItem)
            end
        end
        local procCtrl = gamedb.get_quest_processor_folder_controller(instance.id)
        local processors = procCtrl and procCtrl._ProcessorList._items
        for _, proc in pairs(processors or {}) do
            if proc then
                --- @cast proc app.QuestProcessor
                proc.Process:set_CurrentPhase(enums.QuestProcessorEntityPhase.labelToValue.CancelAction)
            end
        end
        if instance.Log then
            QuestLogManager._Catalog:unregister(instance.id)
            -- any attempt to remove the instance from the concurrent dictionary seems to cause an error
            -- leaving it in should probably be harmless
            -- if QuestLogManager._QuestLogInfoDict:ContainsKey(instance.id) then
            --     local tempinfo = sdk.create_instance('app.QuestLogManager.QuestLogInfo'):add_ref()
            --     -- local tempinfo = QuestLogManager._QuestLogInfoDict[instance.id]
            --     return QuestLogManager._QuestLogInfoDict:TryRemove(instance.id, tempinfo)
            -- end
        end
    end,
    replaced_enum = 'app.QuestDefine.ID',
    generate_label = function (entity)
        --- @cast entity QuestDataSummary
        if entity.Log then
            return tostring(entity.id) .. ' ' .. tostring(entity.label or utils.translate_guid(entity.Log._Title) or '/')
        else
            return tostring(entity.id) .. ' ' .. tostring(entity.label or '/')
        end
    end,
    insert_id_range = {100000, 999000},
})

udb.register_entity_type('quest_processor', {
    import = function (data, instance)
        --- @cast data Import.QuestProcessor
        --- @cast instance QuestProcessorData
        instance = instance or {
            raw_data = data.data,
            id = data.id,
            type = 'quest_processor',
            label = data.label,
            runtime_instance = instance,
            disabled = data.disabled or false
        }
        if data.data.QuestAction == nil then data.data.QuestAction = {} end
        if data.data.PrevProcCondition == nil then data.data.PrevProcCondition = {} end
        return importer.quest.processor(instance)
    end,
    root_types = {'app.QuestProcessor'},
    export = function (data)
        --- @cast data QuestProcessorData
        local action = data.runtime_instance and import_handlers.export(data.runtime_instance.Process.QuestAction, 'app.quest.action.QuestActionBase')
        local prevCond = data.runtime_instance and import_handlers.export(data.runtime_instance.PrevProcCondition, 'app.QuestProcessor.ProcCondition')
        --- @type Import.QuestProcessor
        return {
            data = {
                questId = data.raw_data.questId,
                QuestAction = action or data.raw_data.QuestAction,
                PrevProcCondition = prevCond or data.raw_data.PrevProcCondition,
            },
            disabled = data.disabled or false,
        }
    end,
    delete = function (procdata)
        --- @cast procdata QuestProcessorData
        local proc = procdata and procdata.runtime_instance
        if proc == nil or not proc:get_Valid() then return end
        if proc:get_GameObject():get_Name():sub(1, 4) == '_Mod' then
            -- modded one, we might be able to delete this
            return 'forget'
        else
            return 'forget'
        end
    end,
    generate_label = function (entity)
        --- @cast entity QuestProcessorData
        local label = entity.label
            or entity.runtime_instance and entity.runtime_instance.Process and entity.runtime_instance.Process.QuestAction and helpers.to_string(entity.runtime_instance.Process.QuestAction)
            or '/'
        return 'Processor ' .. entity.raw_data.questId .. '/' .. tostring(entity.id) .. ' ' .. label
    end,
    insert_id_range = {1000000, 9999000}
})

udb.register_entity_type('quest_reward', {
    import = function (data, instance)
        --- @cast instance QuestRewardData
        instance = instance or {}
        instance.runtime_instance = import_handlers.import('app.QuestRewardData', data.data or {}, instance.runtime_instance)
        instance.runtime_instance--[[@as any]]._NameHash = data.id
        local catalog = gamedb.get_first_quest_catalog()
        if not catalog._QuestRewardTableData._DataList:Contains(instance.runtime_instance) then
            catalog._QuestRewardTableData._DataList:Add(instance.runtime_instance)
        end
        return instance
    end,
    export = function (instance)
        --- @cast instance QuestRewardData
        return { data = import_handlers.export(instance.runtime_instance, 'app.QuestRewardData') }
    end,
    root_types = {'app.QuestRewardData'},
    delete = function (instance)
        --- @cast instance QuestRewardData
        local catalog = gamedb.get_first_quest_catalog()
        if instance._basegame then
            return 'forget'
        else
            catalog._QuestRewardTableData._DataList:Remove(instance.runtime_instance)
            return 'ok'
        end
    end,
    insert_id_range = {1000000, 9999000},
})

local event_exports = {
    is_vanilla_event = is_vanilla_event,
    is_vanilla_event_context = is_vanilla_event_context,
}

local quest_exports = {
    get = quest_get_by_id,
    get_variable = quest_get_variable,
    get_quest_variables = get_quest_variables,
    get_quest_variables_enum = get_quest_variables_enum,

    extract_game_variables_into_enums = extract_game_variables_into_enum,
}

_quest_DB.database = {
    catalogs = game_catalogs,

    quests = quest_exports,

    dump = {
        get_full_raw_data_dump = get_full_raw_data,
        dump_mapped_game_data = get_mapped_data_table,
    }
}
return _quest_DB.database
