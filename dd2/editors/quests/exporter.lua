if type(_quest_DB) == 'nil' then _quest_DB = {} end
if _quest_DB.exporter then return _quest_DB.exporter end

local utils = require('content_editor.utils')
local enums = require('editors.quests.enums')

local type_settings = require('content_editor.definitions')
local data_class_to_table

local game_data_converter_cache = {
    ['System.UInt32'] = function(data) return data.m_value end,
    ['System.Int32'] = function(data) return data.m_value end,
    ['app.CharacterID'] = function(data) return data:ToString() end,
    ['app.ItemIDEnum'] = function(data) return data.value__ end,
    ['app.TalkEventDefine.ID'] = function(data) return data:ToString() end,
    ['System.Guid'] = function(data) return data:ToString() end,
    ['app.AISituationTaskEntity'] = function(data) return data:get_Path() end,
    ['app.GenerateTableData'] = function(data) return data:get_Path() end,
}
local ignore_types = {
    ['via.GameObject'] = true,
    ['via.GameObjectRef'] = true,
    ['via.threading.SimpleReaderWriterLock'] = true,
    ['app.quest.condition.ConditionBase'] = true,
    ['System.Collections.Generic.List`1<app.quest.condition.ConditionBase>'] = true,
    ['app.Character'] = true,
    ['app.Human'] = true,
    ['app.Weapon'] = true,
    ['app.Concierge'] = true,
    ['app.ShellParamBase'] = true,
    ['app.NPCHolder'] = true,
    ['app.Timer'] = true,
    ['app.retarget.RotationFactorSetting'] = true,
    ['System.ValueType'] = true,
    ['System.Object'] = true,
    ['System.Enum'] = true,
    ['app.NPCBehavior'] = true,
    ['app.DecisionPack'] = true,
    ['app.AISituationTask'] = true,
    ['app.AISituationAgent'] = true,
    ['app.AISituationAgentNPC'] = true,
    ['app.AISituationAgentPawn'] = true,
}
local ignore_prefixes = {
    'System.Collections.Generic.Dictionary',
    'System.Collections.Generic.HashSet',
    'System.Action',
}
local include_type_fullname = {}
local ignore_fields = {
    ['app.QuestProcessor'] = {['RefQuestControllerObject'] = true},
    ['app.QuestController'] = {['ProcessorFolderControllerList'] = true, ['AISituation'] = true},
    ['app.quest.action.Trigger'] = {['RefProcessor'] = true},
    ['app.quest.action.QuestActionBase'] = {['RefProcessor'] = true},
    ['app.QuestAISituation'] = {['_ParentSituation'] = true},
    ['app.quest.action.SoundControl.WorkBase'] = {['RefProcessor'] = true},
}

for fn, setting in pairs(type_settings.type_settings) do
    if setting.abstract then
        include_type_fullname[fn] = true
        for _, sub in pairs(setting.abstract) do
            include_type_fullname[sub] = true
        end
        if ignore_types[fn] then
            for _, sub in pairs(setting.abstract) do
                ignore_types[sub] = true
            end
        end
        if ignore_fields[fn] then
            for _, sub in pairs(setting.abstract) do
                ignore_fields[sub] = ignore_fields[fn]
            end
        end
    end
end

local quest_base_param_offset = sdk.find_type_definition('app.quest.action.QuestActionBase'):get_field('_Param'):get_offset_from_base()

local type_hook = {
    ['app.SuddenQuestContextData.ContextData.FailureSettingData'] = function(src, target)
        -- regarding flags: all escort/guard SQs have the flag == 4
        target.BrowsableDistance = src:get_BrowsableDistance()
        target.BrowsableTime = src:get_BrowsableTime()
        target.IsLeaveEndPoint = src:get_IsLeaveEndPoint()
        target.IsLeaveNpcPoint = src:get_IsLeaveNpcPoint()
        target.IsLeaveStartPoint = src:get_IsLeaveStartPoint()
        return target
    end,
    ['app.SuddenQuestSelectData'] = function(src, target)
        target._SelectDataArray = utils.map(target._SelectDataArray, function(keyContainer) return keyContainer._Key end)
        return target
    end,
    ['app.SuddenQuestContextData.EnemySettingData'] = function (src, target)
        target._SpawnType = enums.SpawnPositionType.valueToLabel[src._SpawnType]
        target._RequestID = enums.DomainQueryGenerateRequestID.valueToLabel[src._RequestID]
        target._Location = enums.AIKeyLocation.valueToLabel[src._Location]
        return target
    end,
    ['app.QuestProcessor'] = function (sourceObject, data)
        -- capcom was so nice to use the same _Param name in the base class and subclass, for different types. sigh.
        -- the array in the base class contains the real data whereas the subclass _Param gets assigned dynamically
        -- so then the simplest solution is to only store the full array
        local addr = sourceObject.Process.QuestAction:read_qword(quest_base_param_offset)
        data._Param = data_class_to_table(sdk.to_managed_object(addr))
        return data
    end,
}

--- @param fullname string
--- @return boolean
local function is_ignored_type(fullname)
    if ignore_types[fullname] then return true end

    if utils.table_find_index(ignore_prefixes, function (prefix) return fullname:find(prefix) == 1 end) ~= 0 then
        return true
    end
    return false
end

local function is_ignored_field(parentClass, fieldName)
    -- ignore property backing fields with the < prefix
    return fieldName:sub(1, 1) == '<'
        or (ignore_fields[parentClass] and ignore_fields[parentClass][fieldName])
end

local convCount = 1000000
data_class_to_table = function(game_data)
    convCount = convCount - 1
    if convCount <= 0 then
        error('Oi! Too many iterations! Infinite loop maybe!')
        return nil
    end
    if type(game_data) == 'table' then
        local out_data = {}
        if utils.is_assoc_table(game_data) then
            for k, v in pairs(game_data) do
                out_data[k] = data_class_to_table(v)
            end
        else
            for k, v in ipairs(game_data) do
                out_data[k] = data_class_to_table(v)
            end
        end
        return out_data
    end

    if type(game_data) ~= 'userdata' then return game_data end

    if not game_data.get_type_definition then return nil end
    local t = game_data:get_type_definition() --- @type RETypeDefinition
    local fullname = t:get_full_name() --- @type string
    if is_ignored_type(fullname) then return nil end

    if not game_data_converter_cache[fullname] then
        if fullname:sub(1, 31) == 'System.Collections.Generic.List' then
            game_data_converter_cache[fullname] = function(data)
                local count = data:get_Count()
                local out = {}
                for i = 0, count - 1 do
                    out[#out + 1] = data_class_to_table(data:get_Item(i))
                end
                return out
            end
        elseif game_data.get_elements then
            game_data_converter_cache[fullname] = function(data)
                if not data.get_size then
                    print(fullname, 'not a valid array oi', data, data.get_type_definition and data:get_type_definition():get_full_name())
                    return nil
                end
                if data:get_size() == 0 then return nil end
                return utils.map(data:get_elements(), data_class_to_table)
            end
        else
            local fieldsList = {}

            local fields = t:get_fields()
            local parenttype = t:get_parent_type()
            while parenttype and not ignore_types[parenttype:get_full_name()] do
                for _, pf in ipairs(parenttype:get_fields()) do
                    fields[#fields+1] = pf
                end
                parenttype = parenttype:get_parent_type()
            end

            for _, field in ipairs(fields) do
                if not field:is_static() then
                    local name = field:get_name()
                    if not is_ignored_field(fullname, name) and not is_ignored_type(field:get_type():get_full_name()) then
                        fieldsList[#fieldsList + 1] = { name = name, field = field }
                    end
                end
            end

            local shortname = t:get_name()
            game_data_converter_cache[fullname] = function(data)
                local out = {}

                for _, field in ipairs(fieldsList) do
                    local val = field.field:get_data(data)
                    if type(val) == 'userdata' and sdk.is_managed_object(val) then
                        -- print('Subfield dump', fullname, field.name, val:get_type_definition():get_full_name())
                        out[field.name] = data_class_to_table(val)
                    else
                        out[field.name] = val
                    end
                end
                if include_type_fullname[fullname] then
                    out['$type'] = shortname
                end
                return out
            end
        end
    end

    local converted = game_data_converter_cache[fullname](game_data)
    if type_hook[fullname] then converted = type_hook[fullname](game_data, converted) end
    return converted
end

_quest_DB.exporter = {
    raw_dump_object = data_class_to_table,
}
return _quest_DB.exporter
