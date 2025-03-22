if type(_quest_DB) == 'nil' then _quest_DB = {} end
if _quest_DB.gamedb then return _quest_DB.gamedb end

local utils = require('content_editor.utils')
local helpers = require('content_editor.helpers')

local QuestManager = sdk.get_managed_singleton('app.QuestManager')
local QuestResourceManager = sdk.get_managed_singleton('app.QuestResourceManager')
local AIAreaManager = sdk.get_managed_singleton("app.AIAreaManager")
local QuestLogManager = sdk.get_managed_singleton('app.QuestLogManager')
local QuestDeliverManager = sdk.get_managed_singleton('app.QuestDeliverManager')
local AISituationManager = sdk.get_managed_singleton('app.AISituationManager')

--- @return table<string,app.QuestCatalogData>
local function get_active_quest_catalogs()
    local list = QuestManager.QuestCatalogDict:getValues()
    local result = {}
    if list then
        local success, res = pcall(list.get_elements, list)
        if success then
            -- print('Found ' .. tostring(#res) .. ' active quest catalogs')
            for _, ctg in pairs(res) do
                result[ctg:get_Path()] = ctg
            end
        else
            print('Failed to get quest catalogs', res)
        end
    end

    return result
end

--- @return app.QuestCatalogData
local function get_first_quest_catalog()
    local _, ctg = next(get_active_quest_catalogs())
    return ctg
end

local scnmgr = sdk.get_native_singleton("via.SceneManager")
local scnmgr_t = sdk.find_type_definition("via.SceneManager")
local function get_scene()
    return sdk.call_native_func(scnmgr, scnmgr_t, "get_CurrentScene()")
end

local func_scene_findcomp = sdk.find_type_definition('via.Scene'):get_method('findComponents(System.Type)')
local function get_gameobjects_by_type(type)
    return func_scene_findcomp:call(get_scene(), sdk.typeof(type))
end

local function get_all_running_quest_processors()
    return get_gameobjects_by_type("app.QuestProcessor")
end

--- @return table<integer, app.QuestProcessor>
local processors = {}
--- @return table<integer, table<integer, app.QuestProcessor>>
local processorsByQuestId = {}

local last_processor_fetch_time = -2
local function fetch_active_quest_processors(force_refetch)
    -- make sure we don't spam findComponents if we have a UI open with several inactive quest processors attempting to display at once
    if not force_refetch and os.clock() - last_processor_fetch_time < 5 then return processors end
    last_processor_fetch_time = os.clock()

    local procs = get_all_running_quest_processors()
    processors = {}
    for _, processor in pairs(procs) do
        --- @cast processor app.QuestProcessor
        if processors[processor.ProcID] and processors[processor.ProcID] ~= processor then
            print('DUPLICATE QUEST PROCESSOR ' .. processor.ProcID)
        end
        processors[processor.ProcID] = processor
        local qid = processor:get_QuestID()
        if qid then
            processorsByQuestId[qid] = processorsByQuestId[qid] or {}
            processorsByQuestId[qid][processor.ProcID] = processor
        else
            print('Missing quest controller for processor', processor.ProcID)
        end
    end
    return processors
end

--- @param questId integer
--- @return app.QuestController|nil
local function get_quest_controller(questId)
    local entity = QuestManager.EntityDict and QuestManager.EntityDict:ContainsKey(questId) and QuestManager.EntityDict[questId]
    return entity and entity.Controller or nil
end

--- @param questId integer
--- @return app.ProcessorFolderController|nil
local function get_quest_processor_folder_controller(questId)
    local ctrl = get_quest_controller(questId)
    return ctrl and ctrl._ProcessorFolderController or nil
end

local qscollector = nil
--- @return REManagedObject|nil app.QuestSceneCollector
local function get_quest_scene_collector()
    if qscollector ~= nil and qscollector:get_Valid() then
        return qscollector
    end

    local collectors = utils.enumerator_to_table(QuestManager.SceneCollectorDict:GetEnumerator())

    if collectors == nil or #collectors == 0 then
        return nil
    end

    return collectors[1].value
end
local function get_quest_root_folder()
    local collector = get_quest_scene_collector()
    if not collector then return nil end
    local enumerator = collector--[[@as any]]:get_QuestSceneFolderDict():GetEnumerator()
    if enumerator:MoveNext() then
        -- return enumerator
        local current = enumerator:get_Current()
        if current.value ~= nil then
            return current.value:get_Parent()
        else
            print('scene folder dict entry is nil wtf', current.key, current.value)
        end
        -- return enumerator:get_Current().value:get_Parent()
    end
    return nil
end

-- local questSceneController = sdk.get_managed_singleton('app.MainFlowManager'):get_MainContentsController():get_OtherFolderControllerList()[0]
-- local MainFlowManager = sdk.get_managed_singleton('app.QuestManager').Tree

--- @return app.QuestManager.QuestEntity|nil
local function get_game_quest_entity(id)
    if QuestManager.EntityDict:call('ContainsKey', id) then
        return QuestManager.EntityDict:get_Item(id)
    end
    return nil
end

--- @param questId integer
--- @return via.Folder|nil
local function get_quest_scene_folder(questId)
    local qc = get_quest_scene_collector() --- @type any
    if qc == nil then return nil end

    local dict = qc:get_QuestSceneFolderDict()
    if dict and dict:ContainsKey(questId) then
        return dict[questId]
    end
    return nil
end

-- NOTE: i'm not yet sure if processor IDs are globally unique or not, this might return wrong results
--- @param processorId integer
--- @param questId integer
--- @return app.QuestProcessor|nil
local function get_quest_processor(processorId, questId)
    local proc = processors[processorId]
    if proc and proc.get_Valid and proc:get_Valid() then return proc end
    proc = nil

    local procFolderCtrl = get_quest_processor_folder_controller(questId)
    if procFolderCtrl then
        local procContainer = procFolderCtrl._ProcessorList
        local procCount = procFolderCtrl._ProcessorList:get_Count()
        if procCount == 0 then
            -- fallback to folder lookup, I hate this
            local procFolder = get_quest_scene_folder(questId)
            procFolder = procFolder and procFolder:find('Resident')
            if procFolder then
                -- we need to fetch the processor root transform and get the children from there instead
                -- I'm assuming the processor root is the only quest folder child that has its own children
                local processorRoot = utils.first_where(utils.folder.get_children(procFolder), function (child) return child:get_Child() ~= nil end)
                local procChildren = processorRoot and utils.map(utils.folder.get_children(processorRoot), function (go) return utils.gameobject.get_component(go:get_GameObject(), 'app.QuestProcessor') end) or {}
                procCount = #procChildren
                procChildren[0] = procChildren[procCount]
                procContainer = procChildren
            end
        end

        for i = 0, procCount - 1 do
            local pp = procContainer[i]
            if pp.ProcID == processorId then
                proc = pp
                break
            end
        end
    end
    processors[processorId] = proc
    return proc
end

local frame_funcs = {}
re.on_application_entry('UpdateBehavior', function()
    for i, f in pairs(frame_funcs) do
        local succ, result = pcall(f)
        if succ and result == true then
            frame_funcs[i] = nil
        end
    end
end)

--- @type table<string, via.Prefab|nil>
local prefab_cache = {}

--- comment
--- @param pfb_path string
--- @param parentFolder via.Folder
--- @param callback fun(gameObject: via.GameObject)
--- @param timeLimit integer|nil
--- @return boolean created, via.GameObject|nil gameObject
local function instantiate_prefab(pfb_path, parentFolder, callback, timeLimit)
    local pfb = prefab_cache[pfb_path]
    if not pfb then
        pfb = sdk.create_instance("via.Prefab"):add_ref()--[[@as via.Prefab]]
        prefab_cache[pfb_path] = pfb
        pfb:set_Path(pfb_path)
        pfb:set_Standby(true)
    end

    if pfb:get_Ready() then
        print('Prefab is ready: ', pfb_path)
        local go = pfb:call('instantiate(via.vec3, via.Folder)', ValueType.new(sdk.find_type_definition('via.vec3')), parentFolder)
        callback(go)
        return true, go
    end

    timeLimit = timeLimit == nil and 5 or timeLimit
    local starttime = os.clock()
    frame_funcs[#frame_funcs+1] = function ()
        if pfb:get_Ready() then
            return instantiate_prefab(pfb_path, parentFolder, callback)
        end

        if os.clock() - starttime > timeLimit then
            print('Prefab instantiation timed out after ' .. timeLimit .. ' seconds:', pfb_path)
            pfb:release()
            prefab_cache[pfb_path] = nil
            return true
        end
        print('Waiting for prefab init', pfb_path)
        return false
    end
    return false, nil
end

--- @param questId integer
--- @param processorId integer
--- @param questSceneFolder REManagedObject|nil
--- @return app.QuestProcessor|nil processor
local function create_processor(questId, processorId, questSceneFolder)
    questSceneFolder = questSceneFolder or get_quest_scene_folder(questId)
    if not questSceneFolder then
        -- TODO try and figure out a way of dynamically creating a dummy quest folder; failing that, at least show some warning somewhere
        -- the only way I see of creating a new folder is via .scn files, and we can't create those through lua either
        -- would probably need some external tool that can automate scn file changes
        print('WARNING: quest '..questId..' does not seem to have have a valid scene folder, this needs to be done manually for now - edit appsystem/scene/quest.scn.20')
        return nil
    end
    if questSceneFolder then
        local ctrl = get_quest_controller(questId)
        -- processor can be null here if it's inactive; the ProcessorFolderController:setupProcessors() hook should handle that
        if ctrl == nil then return nil end

        local go, proc = utils.gameobject.create_with_component("_ModProcessor_" .. processorId, 'app.QuestProcessor', questSceneFolder)
        --- @cast proc app.QuestProcessor
        proc.ProcID = processorId
        proc:set_TimeDetectionKey('qu' .. questId .. "_Processor_" .. processorId)
        proc:set_RefQuestController(ctrl)
        proc.Process = sdk.create_instance('app.QuestProcessor.ProcessEntity')--[[@as any]]
        proc.Process:set_QuestID(questId)

        local procfolder = get_quest_processor_folder_controller(questId)
        if procfolder then procfolder._ProcessorList:Add(proc) end

        -- below 2 lines I think aren't necessary, put them back in if there's issues
        -- ctrl._ProcessorResults[processorId] = -1
        -- sdk.get_managed_singleton('app.QuestManager'):call('registerUpdateProcessor', proc)
        return proc
    else
        print("ERROR: can't create processor, container folder is not active for quest id", questId)
    end
end

local function get_AIKeyLocation_position(locationId)
    local node = AIAreaManager:getKeyLocationNode(locationId)
    if node == nil then return nil end
    return node:get_WorldPos()
end

local function get_AIKeyLocation_uni_position(locationId)
    local node = AIAreaManager:getKeyLocationNode(locationId)
    if node == nil then return nil end
    return node:get_UniversalPosition()
end

local quat_identity = sdk.find_type_definition('via.Quaternion'):get_field('Identity'):get_data()


local function get_single_quest_catalog()
    local _, catalog = next(get_active_quest_catalogs())
    return catalog
end

--- @return app.AISituationGenerateParameter|nil
local function get_quest_ai_situation_root()
    -- NOTE: there's a reference to the array in AISituationManager._RootSituationParamList as well, but the situation master seems to be the source so I'm using that instead
    -- since it's the same reference, both should get updated at the same time
    for _, rootParam in pairs(AISituationManager._SituationMaster.RootSituationParamList) do
        local firstChild = rootParam.ChildSituations:get_size() > 0 and rootParam.ChildSituations[0]
        -- basegame has all quest situations in the one root param entry, therefore if the first one is correct type, all of them should be
        -- this is user file AppSystem/AI/Situation/GenerateParameter/RootQuestSituationParam.user
        if firstChild ~= nil and firstChild:get_type_definition():get_full_name() == 'app.QuestAISituationGenerateParameter' then
            return rootParam
        end
    end
end

--- @param situation app.QuestAISituationGenerateParameter
--- @return app.AISituationEntity
local function upsert_quest_ai_situation_entity(situation)
    local guid = situation.Guid
    local dict = AISituationManager._SituationMaster._SituationDictionary
    if not dict:ContainsKey(guid) then
        local parentSit = get_quest_ai_situation_root()
        print('Creating new AI situation...')
        local newEntity = AISituationManager._SituationMaster:get_Generator():generateSituation(situation, dict, parentSit, true)
        dict[guid] = newEntity
        return newEntity
    end

    return dict[guid]
end

--- @param situationGuid System.Guid
--- @return app.AISituationEntity|nil
local function get_quest_ai_situation_entity(situationGuid)
    local dict = AISituationManager._SituationMaster._SituationDictionary
    if dict:ContainsKey(situationGuid) then
        return dict[situationGuid]
    end

    return nil
end

--- @param quest QuestDataSummary
--- @return app.QuestManager.QuestEntity
local function upsert_quest_entity(quest)
    -- no multi-catalog handling for now
    local catalog = get_first_quest_catalog()

    helpers.ensure_item_in_array(catalog.ContextData, 'AfterStoryDataArray', quest.AfterStoryData, 'app.QuestContextData.AfterStoryData')
    helpers.ensure_item_in_array(catalog.ContextData, 'ContextDataArray', quest.contextData, 'app.QuestContextData.ContextData')
    helpers.ensure_item_in_array(catalog.ContextData, 'DeliverDataArray', quest.Deliver, 'app.QuestContextData.DeliverData')
    helpers.ensure_item_in_array(catalog.ContextData, 'VariableDataArray', quest.Variables, 'app.QuestContextData.VariableData')
    helpers.ensure_item_in_array(catalog.TreeData, 'NodeDataArray', quest.TreeNode, 'app.QuestTreeData.NodeData')

    local rootParam = get_quest_ai_situation_root()
    if rootParam then
        helpers.ensure_item_in_array(rootParam, 'ChildSituations', quest.AISituation, 'AISituation.AISituationGenerateParameterBase')
        upsert_quest_ai_situation_entity(quest.AISituation)
    end

    if quest.NpcOverrideData then
        helpers.ensure_item_in_array(catalog._NpcOverrideTableData, '_Table', quest.NpcOverrideData, 'app.QuestNpcOverrideData')
        for _, ovr in pairs(quest.NpcOverrideData._Data) do ovr._QuestID = quest.id end
    end
    if quest.UniqueParam and not catalog._QuestUniqueParamData._DataList:Contains(quest.UniqueParam) then
        catalog._QuestUniqueParamData._DataList:Add(quest.UniqueParam)
    end

    local entity = get_game_quest_entity(quest.id)
    if not entity then
        print('creating new quest entity', quest.id)
        entity = sdk.create_instance('app.QuestManager.QuestEntity', true)--[[@as app.QuestManager.QuestEntity]]
        QuestManager.EntityDict[quest.id] = entity
        -- NOTE: we can't do this dynamically at the moment, can't create a folder nor load a scene file on demand
        -- MAYBE, we could just force activate it or something here but maybe rather not
        -- upsert_quest_controller(quest.id)
    else
        print('updating quest entity', quest.id)
    end
    -- sdk.create_instance('System.Collections.Generic.List<app.QuestNpcOverrideEntiry>'):add_ref()

    if entity.Context == nil then
        entity.Context = sdk.create_instance('app.QuestContext', true)--[[@as any]]
    end

    --- sdk.get_managed_singleton('app.QuestManager').EntityDict[100008]
    --- sdk.get_managed_singleton('app.QuestManager').Tree

    -- this will replace the existing instances altogether, should we instead manually merge values into the list and only .ctor() once?
    entity.Context:call('.ctor', quest.id, quest.contextData:get_ProcessorIDList(), quest.contextData:get_NPCCastList(), quest.contextData:get_TimeDetectionKeyList())

    if quest.NpcOverrideData and quest.NpcOverrideData._Data then
        if not entity.NpcOverrideEntityList then
            entity.NpcOverrideEntityList = helpers.create_instance('System.Collections.Generic.List`1<app.QuestNpcOverrideEntiry>')
        end
        entity:registerNpcOverrideData(quest.NpcOverrideData)
    end

    -- local questTree = QuestManager.Tree
    -- should create or add a app.QuestManager.QuestTree.Node
    -- alternatively, tree:setup(app.QuestCatalogData, app.QuestSceneCollector, System.Collections.Generic.Dictionary<int, app.QuestManager.QuestEntity>)

    local collector = get_quest_scene_collector()
    if collector then
        -- note: we can't call QuestManager:setupQuestTree() and let that handle it because it doesn't re-setup
        -- we're calling setup() again each time because otherwise we'd need to check if either the node is missing (easy) or is unsynced with the new data (more effort)
        QuestManager.Tree:setup(catalog, collector, QuestManager.EntityDict)
    end

    -- we need to force call this on launch and whenever deliver data changes because it doesn't update automatically
    QuestDeliverManager:registerQuestCatalog(catalog)
    if not QuestResourceManager.ResourceControllerDict:ContainsKey(quest.id) then
        local resCtrl = helpers.create_instance('app.QuestResourceManager.ResourceController')
        resCtrl:call('.ctor', quest.id)
        QuestResourceManager.ResourceControllerDict[quest.id] = resCtrl
    end

    -- TODO This crashes the game as of now
    -- if quest.Log then
    --     if not QuestLogManager._QuestLogInfoDict:ContainsKey(quest.id) then
    --         newLogInfo = sdk.create_instance('app.QuestLogManager.QuestLogInfo', true)
    --         newLogInfo:call('.ctor(app.QuestLogResource)', quest.Log)
    --         QuestLogManager._QuestLogInfoDict[quest.id] = newLogInfo
    --     else
    --         newLogInfo = QuestLogManager._QuestLogInfoDict[quest.id]
    --         newLogInfo._Resource = quest.Log
    --     end
    -- end

    if quest.OracleHints then
        QuestManager._OracleAcceptHintDatabase[quest.id] = quest.OracleHints._QuestAcceptHints
        QuestManager._OracleHintDatabase[quest.id] = quest.OracleHints._QuestHints
    end

    return entity
end

-- glob.add({
--     get_quest_root_folder = get_quest_root_folder,
--     get_quest_processor_folder_controller = get_quest_processor_folder_controller,
--     enumerator_to_table = utils.enumerator_to_table,
--     scene_collector = get_quest_scene_collector,
--     get_quest_scene_folder = get_quest_scene_folder,
--     QuestManager = QuestManager,
--     QuestDeliverManager = QuestDeliverManager,
--     QuestResourceManager = QuestResourceManager,
--     quest_catalog = get_single_quest_catalog,
-- })

_quest_DB.gamedb = {
    get_quest_catalogs = get_active_quest_catalogs,
    get_first_quest_catalog = get_first_quest_catalog,

    get_quest_controller = get_quest_controller,

    get_quest_scene_collector = get_quest_scene_collector,
    get_quest_scene_folder = get_quest_scene_folder,
    fetch_quest_processors = fetch_active_quest_processors,
    get_quest_processor_folder_controller = get_quest_processor_folder_controller,
    get_quest_processor = get_quest_processor,
    create_processor = create_processor,

    get_quest_ai_situation_entity = get_quest_ai_situation_entity,
    get_quest_ai_situation_root = get_quest_ai_situation_root,
    upsert_quest_ai_situation_entity = upsert_quest_ai_situation_entity,

    get_quest_entity = get_game_quest_entity,

    get_AIKeyLocation_position = get_AIKeyLocation_position,
    get_AIKeyLocation_uni_position = get_AIKeyLocation_uni_position,

    upsert_quest_entity = upsert_quest_entity,

    quaternion_identity = quat_identity,
}
return _quest_DB.gamedb
