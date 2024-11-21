-- DB types
--- @alias EntityType 'event'|'event_context'

--- @class UserdataDatabase

--- @class QuestDataSummary : DBEntity
--- @field catalog_path string
--- @field contextData app.QuestContextData.ContextData
--- @field Variables app.QuestContextData.VariableData|nil
--- @field Deliver app.QuestContextData.DeliverData
--- @field NpcOverrideData app.QuestNpcOverrideData
--- @field AfterStoryData app.QuestContextData.AfterStoryData|nil
--- @field TreeNode app.QuestTreeData.NodeData|nil
--- @field AISituation app.QuestAISituationGenerateParameter|nil
--- @field Log app.QuestLogResource|nil
--- @field UniqueParam app.QuestUniqueParamData.Data
--- @field OracleHints app.QuestOracleHintGroup
--- @field cacheData table

--- @class QuestProcessorData : DBEntity
--- @field raw_data Import.QuestProcessor.Data
--- @field runtime_instance app.QuestProcessor|nil
--- @field disabled boolean

--- @class QuestRewardData : DBEntity
--- @field runtime_instance REManagedObject|nil
--- @field _basegame true|nil

--- @class QuestContainer : DBEntity
--- @field quest_data_filepath string
--- @field resident_filepath string
--- @field controller app.QuestController

-- Data exchange formats

--- @class Import.Quest : EntityImportData
--- @field context table
--- @field catalog string
--- @field npcOverride table[]
--- @field afterStory table[]|nil
--- @field deliver table[]
--- @field variables table[]|nil
--- @field treeData table
--- @field aiSituation table|nil
--- @field log table|nil
--- @field oracleHints table|nil
--- @field recommendedLevel integer

--- @class Import.QuestProcessor : EntityImportData
--- @field data Import.QuestProcessor.Data
--- @field disabled boolean

--- @class Import.QuestProcessor.Data
--- @field questId integer
--- @field PrevProcCondition table|nil
--- @field QuestAction table
