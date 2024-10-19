_dbg = _dbg
-- things that might be useful to check if the game crashes

local importers = require('content_editor.import_handlers')
local quest_export = require('quest_editor.exporter')

local function object_json_dump(obj)
    return json.dump_string(importers.export(obj)) .. '\n\n' .. json.dump_string(quest_export.raw_dump_object(obj)) .. '\n\n'
end

local function collector_foldercount(coll) return 'folderCount=' .. coll:get_QuestSceneFolderDict():get_Count() end
_dbg.hookLog('app.QuestSceneCollector', 'start', collector_foldercount)

local function questCtrlId(qc) return 'QuestID='..qc._QuestID .. ', proc len=' .. qc._ProcessorLength end
_dbg.hookLog('app.QuestController', 'start', questCtrlId)
_dbg.hookLog('app.QuestController', 'registerProcessorFolder', questCtrlId)
_dbg.hookLog('app.QuestController', 'requestActivePrcessorFolder', questCtrlId)
-- _dbg.hookLog('app.QuestController', 'update', questCtrlId)

local function procId(qp) return 'QuestID=' .. qp:get_QuestID() .. ', ProcID=' .. qp.ProcID .. ', ref quest ctrl: ' .. tostring(qp:get_RefQuestController()) end
_dbg.hookLog('app.QuestProcessor', 'start', procId)
_dbg.hookLog('app.QuestProcessor', 'setup', procId)
_dbg.hookLog('app.QuestProcessor', 'checkActiveSituation', procId)
_dbg.hookLog('app.QuestProcessor', 'requestStart', procId)
_dbg.hookLog('app.QuestProcessor', 'checkProcCondition', procId)

-- local function regName(reg) return reg._ProcessorsFolder:get_Path() end
_dbg.hookLog('app.QuestProcessorRegister', 'start')

local function procFolderIdDebug(pf)
    if pf._QuestController._QuestID == 8000 then
        log.info('QuestID=' .. pf._QuestController._QuestID .. ' dump: ' .. object_json_dump(pf))
        return 'QuestID=' .. pf._QuestController._QuestID .. ' dump: ' .. object_json_dump(pf)
    end
    return 'QuestID='..pf._QuestController._QuestID
end

local function procFolderId(pf) return 'QuestID='..pf._QuestController._QuestID end
_dbg.hookLog('app.ProcessorFolderController', 'collectProcessors', procFolderId)
_dbg.hookLog('app.ProcessorFolderController', 'setupProcessors', procFolderId)
-- _dbg.hookLog('app.ProcessorFolderController', 'setupProcessors', procFolderIdDebug)
-- _dbg.hookLog('app.ProcessorFolderController', 'update', procFolderId)

-- crash: somewhere inside / after setupProcessors() for our quest 8000;


-- _dbg.hookLog('app.QuestManager', 'updateNpcOverride')
-- _dbg.hookLog('app.QuestManager', 'onUpdate')
-- _dbg.hookLog('app.QuestResourceManager', 'onUpdate')


--- expected flow:

-- app.QuestSceneCollector start()
    --[[
        QuestManager.Instance.registerQuestSceneCollector(this)  // this adds the collector to SceneCollectorDict and RegisterCatalogHashSet
        foreach (var questFolder in this.GameObject.Folder.Folders) {
            if (Enum.TryParse<app.QuestDefine.ID>(questFolder.Name, out var questId))
                QuestSceneFolderDict.TryInsert((int)questId, questFolder)
        }
    ]]


--- for all active quests:
-- app.QuestController start() -- _ProcessorLength updates here
-- app.QuestProcessorRegister start()
    --> app.QuestController registerProcessorFolder()
        --> creates new app.ProcessorFolderController()

-- app.QuestController update()
    --> app.QuestController.updateProcessorFolderController()
        --> app.ProcessorFolderController.updatePhase()
            --> app.ProcessorFolderController collectProcessors()

-- app.QuestController update()
    --> app.QuestController.updateProcessorFolderController()
        --> app.ProcessorFolderController.updatePhase()
            --> app.ProcessorFolderController setupProcessors()

-- app.QuestProcessor start()  -- QuestID is updated inside here

-- app.ProcessorFolderController setupProcessors()
    --[[
        // some other stuff that I can't see via REF, would need to decompile the exe
        GameObject.UpdateSelf = ??;
    ]]
