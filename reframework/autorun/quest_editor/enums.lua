if type(_quest_DB) == 'nil' then _quest_DB = {} end
if _quest_DB.enums then return _quest_DB.enums end

local usEnums = require('content_editor.enums')
local utils = require('content_editor.utils')
local utils_dd2 = require('content_editor.dd2.utils')

---@diagnostic disable: inject-field

local CharacterID = usEnums.get_enum('app.CharacterID')
CharacterID.set_display_labels(utils.map(CharacterID.values, function (val) return {val, CharacterID.valueToLabel[val] .. ' : ' .. utils_dd2.translate_character_name(val)} end))

--- List of CharacterID enum values, filtered only to NPCs (ch3*)
local NPCIDs = usEnums.create_subset(CharacterID, 'CharacterID_NPC', function (label) return label == 'Invalid' or label:sub(1,3) == 'ch3' and label:len() > 5 end)

local ItemID = usEnums.get_enum('app.ItemIDEnum')
ItemID.set_display_labels(utils.map(ItemID.values, function (val) return { val, ItemID.valueToLabel[val] .. ' : ' .. tostring(utils_dd2.translate_item_name(val)) } end))

local TalkEventDefineID = usEnums.get_enum('app.TalkEventDefine.ID')
local AIKeyLocation = usEnums.get_enum('app.AIKeyLocation')
local DomainQueryGenerateRequestID = usEnums.get_enum('app.DomainQueryGenerateRequestID')
local SuddenContextTimingType = usEnums.get_enum('app.SuddenQuestContextData.ContextData.TaskSettingData.TimingType')
SuddenContextTimingType.BeforeStartTalkEvent = 0
SuddenContextTimingType.AfterStartTalkEvent = 1
local SpawnPositionType = usEnums.get_enum('app.SuddenQuestContextData.ContextData.EnemySettingData.SpawnPositionType')
local SentimentRank = usEnums.get_enum('app.SentimentRank')
local GimmickLockID = usEnums.get_enum('app.GimmickLockID')
local GroupDefine = usEnums.get_enum('app.CharacterData.GroupDefine')
local GenerateDefine = usEnums.get_enum('app.CharacterData.GenerateDefine')
local TimeZoneType = usEnums.get_enum('app.TimeManager.TimeZoneType')
local QuestProcessorPhase = usEnums.get_enum('app.QuestProcessor.Phase')
local QuestProcessorEntityPhase = usEnums.get_enum('app.QuestProcessor.ProcessEntity.Phase')

local SuddenContextSuccessFlags = usEnums.get_virtual_enum('SuddenContextSuccessFlags', {
    IsEnemyDefeat = 4,
    IsEndPosition = 2,
    IsNpcKeepSafe = 1,
})

local SuddenContextFailureFlags = usEnums.get_virtual_enum('SuddenContextFailureFlag', {
    LeaveNpcPoint = 4,
    LeaveEndPoint = 2,
    LeaveStartPoint = 1,
})

local DayOfWeek = usEnums.get_enum('app.DayOfWeek')
local DayOfWeekFlags = usEnums.get_virtual_enum('app.DayOfweek[Flags]', {
	Sunday = 1,
	Monday = 2,
	Tuesday = 4,
	Wednesday = 8,
	Thursday = 16,
	Friday = 32,
	Saturday = 64,
})

local SuddenQuestType = usEnums.get_enum('app.QuestDefine.SuddenQuestType')
SuddenQuestType.Invalid = 0
SuddenQuestType.EnemyBattle = 1
SuddenQuestType.NpcGuard = 2
SuddenQuestType.NpcTravel = 3

local LogicalOperator = usEnums.get_enum('app.AISituation.TaskStateConditionDefine.LogicalOperator')
LogicalOperator.And = 0
LogicalOperator.Or = 1

local LogicalOperatorBool = usEnums.get_enum('app.AISituation.TaskStateConditionDefine.LogicalOperatorBool')
LogicalOperatorBool.Equal = 0
LogicalOperatorBool.NotEqual = 1

local TrueFalseDefine = usEnums.get_enum('app.CharacterData.TrueFalseDefine')
TrueFalseDefine.False = 0
TrueFalseDefine.True = 1

local CompareType = usEnums.get_enum('app.CompareType')

local JobEnum = usEnums.get_enum('app.Character.JobEnum')
local JobDefine = usEnums.get_enum('app.CharacterData.JobDefine')
local MorgueDefine = usEnums.get_enum('app.CharacterData.MorgueDefine')
local WeaponID = usEnums.get_enum('app.WeaponID')
local NPCCombatParamTemplate = usEnums.get_enum('app.HumanEnemyParameterBase.NPCCombatParamTemplate')

local LogicalOperatorInt = usEnums.get_enum('app.AISituation.TaskStateConditionDefine.LogicalOperatorInt')
LogicalOperatorInt.Lessthan = 0
LogicalOperatorInt.Less = 1
LogicalOperatorInt.Equal = 2
LogicalOperatorInt.NotEqual = 3
LogicalOperatorInt.More = 4
LogicalOperatorInt.Morethan = 5

local SuddenQuestPhase = {
    Standby = 0,
    StartTalkEvent = 1,
    Relay = 2,
    RelayTalkEvent = 3,
    Execute = 4,
    EndTalkEvent = 5,
    End = 6,
}

_quest_DB.enums = {
    NPCIDs = NPCIDs,
    ItemID = ItemID,
    JobEnum = JobEnum,
    WeaponID = WeaponID,
    JobDefine = JobDefine,
    DayOfWeek = DayOfWeek,
    CharacterID = CharacterID,
    GroupDefine = GroupDefine,
    CompareType = CompareType,
    MorgueDefine = MorgueDefine,
    TimeZoneType = TimeZoneType,
    AIKeyLocation = AIKeyLocation,
    GimmickLockID = GimmickLockID,
    SentimentRank = SentimentRank,
    DayOfWeekFlags = DayOfWeekFlags,
    GenerateDefine = GenerateDefine,
    SuddenQuestType = SuddenQuestType,
    LogicalOperator = LogicalOperator,
    TrueFalseDefine = TrueFalseDefine,
    SuddenQuestPhase = SuddenQuestPhase,
    TalkEventDefineID = TalkEventDefineID,
    SpawnPositionType = SpawnPositionType,
    LogicalOperatorInt = LogicalOperatorInt,
    LogicalOperatorBool = LogicalOperatorBool,
    QuestProcessorPhase = QuestProcessorPhase,
    NPCCombatParamTemplate = NPCCombatParamTemplate,
    SuddenContextTimingType = SuddenContextTimingType,
    SuddenContextSuccessFlags = SuddenContextSuccessFlags,
    QuestProcessorEntityPhase = QuestProcessorEntityPhase,
    SuddenContextFailureFlags = SuddenContextFailureFlags,
    DomainQueryGenerateRequestID = DomainQueryGenerateRequestID,

    utils = usEnums,
}

return _quest_DB.enums
