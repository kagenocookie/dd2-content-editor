if type(_quest_DB) == 'nil' then _quest_DB = {} end
if _quest_DB.__internal and _quest_DB.__internal.quest_handlers then return _quest_DB.__internal.quest_handlers end

local core = require('content_editor.core')
local enums = require('quest_editor.enums')
local helpers = require('content_editor.helpers')
local gamedb = require('quest_editor.gamedb')
local utils = require('content_editor.utils')
local type_definitions = require('content_editor.definitions')
local udb = require('content_editor.database')

if core.editor_enabled then
    local ui = require('content_editor.ui')
    local offset_QuestActionParamBase_Param = sdk.find_type_definition('app.quest.action.QuestActionBase'):get_field('_Param'):get_offset_from_base()

    local varNames = enums.utils.get_enum('QuestVariables')
    local ruleFlags = enums.utils.get_enum('app.quest.action.QuestRuleControlParam.RuleFlag')

    ui.handlers.register_extension('warp_to_location', function (handler, data)
        --- @type UIHandler
        return function (ctx)
            local changed = handler(ctx)
            local pos = gamedb.get_AIKeyLocation_uni_position(ctx.get())
            if pos then
                imgui.indent(8)
                if imgui.button('Warp to ' .. ctx.label .. ': ' .. pos:ToString()) then
                    _userdata_DB.utils_dd2.set_position(_userdata_DB.utils_dd2.get_player(), pos)
                end
                imgui.unindent(8)
            end

            return changed
        end
    end)

    ui.handlers.register_extension('filter_toggle_active', function (handler, data)
        --- @type UIHandler
        return function (ctx)
            ctx.data.filter_active = select(2, imgui.checkbox('Show active only', ctx.data.filter_active or false))
            return handler(ctx)
        end
    end)

    ui.handlers.register_extension('quest_variable_name', function (handler)
        --- @type UIHandler
        return function (ctx)
            local variableHash = ctx.get()
            local varLabel = varNames.get_label(variableHash)
            if varLabel then
                imgui.text('Variable: ' .. varLabel)
            end
            imgui.same_line()
            if imgui.tree_node('Change name') then
                local changedName, newval = imgui.input_text('New name', ctx.data._new_varname or varLabel or tostring(variableHash))
                if changedName then
                    ctx.data._new_varname = newval
                end
                if ctx.data._new_varname and ctx.data._new_varname ~= '' then
                    if imgui.button('Confirm') then
                        if not varNames.labelToValue[ctx.data._new_varname] then
                            varNames.labelToValue[ctx.data._new_varname] = variableHash
                        end
                        if varNames.labelToValue[varLabel] then
                            varNames.labelToValue[varLabel] = nil
                        end
                        if varNames.valueToLabel[variableHash] then
                            varNames.valueToLabel[variableHash] = ctx.data._new_varname
                        end
                        varNames.set_display_label(variableHash, ctx.data._new_varname)
                        varNames.resort()
                        enums.utils.save_enum(varNames.enumName)
                        ctx.data._new_varname = nil
                    end
                    imgui.same_line()
                    if imgui.button('Cancel') then
                        ctx.data._new_varname = nil
                    end
                end
                imgui.tree_pop()
            end
            local changed = handler(ctx)
            return changed
        end
    end)

    local emptyParams = {['app.quest.action.NotifyStartQuest'] = true, ['app.quest.action.NotifyEndQuest'] = true}
    ui.handlers.register_extension('quest_action_param_type_matcher', function (handler)
        --- @type UIHandler
        return function (ctx)
            local val = ctx.get()
            if val == nil then
                return handler(ctx)
            end
            local t = helpers.get_type(val)
            local params = helpers.get_field(val, '_Param')
            local param = utils.first(params)
            local isRawData = type(val) == 'table'
            if emptyParams[t] then
                if param ~= nil then
                    helpers.set_field(val, '_Param', helpers.create_instance('app.quest.action.QuestActionParamBase[]', isRawData))
                end
            elseif t then
                local targetParamType = t .. 'Param'
                if param == nil then
                    param = helpers.create_instance(targetParamType, isRawData)
                    params = isRawData and { param } or utils.create_array('app.quest.action.QuestActionParamBase', { param })
                    helpers.set_field(val, '_Param', params)
                elseif helpers.get_type(param) ~= targetParamType then
                    local index = isRawData and 1 or 0
                    params[index] = helpers.create_instance(targetParamType, isRawData)
                end
            end

            return handler(ctx)
        end
    end)

    --- comment
    --- @param processorId integer
    --- @param questId integer
    local function get_processor_entity(processorId, questId)
        local processor = udb.get_entity('quest_processor', processorId)
        --- @cast processor QuestProcessorData|nil
        if processor then return processor end

        if not processor then
            local runtimeProcessor = _quest_DB.gamedb.get_quest_processor(processorId, questId)
            if runtimeProcessor then
                --- @type QuestProcessorData
                local entity = {
                    id = processorId,
                    type = 'quest_processor',
                    runtime_instance = runtimeProcessor,
                    raw_data = { questId = questId }--[[@as any]],
                    disabled = false,
                }
                entity.label = udb.generate_entity_label(entity)
                return entity
            end
        end
    end

    --- @param ctx UIContainer
    --- @param type string
    --- @return UIContainer|nil
    local function find_parent_of_type(ctx, type)
        while ctx ~= nil do
            if ctx.data.classname == type then
                return ctx
            end
            ctx = ctx.parent
        end
    end

    --- @param ctx UIContainer
    --- @return QuestProcessorData|nil
    local function get_processor_from_condition_element(ctx)
        local procId = ctx.get()._ProcID
        if procId == nil then return nil end
        local processorCtx = find_parent_of_type(ctx, 'app.QuestProcessor')
        local processor = processorCtx and processorCtx.get()
        if not processor then
            processor = ctx.owner and ctx.owner.type == 'quest_processor' and ctx.owner or nil
        end
        if processor then
            --- @cast processor QuestProcessorData|app.QuestProcessor
            if type(processor) == 'userdata' then
                return get_processor_entity(procId, processor:get_QuestID())
            elseif processor.raw_data.questId then
                return get_processor_entity(procId, processor.raw_data.questId)
            end
        else
            return nil
        end
    end

    --- @param ctx UIContainer
    --- @return QuestProcessorData|nil
    local function get_processor_from_variable(ctx)
        local rootQuest = ctx.owner and ctx.owner.type == 'quest' and ctx.owner --- @as QuestDataSummary|nil
        if rootQuest and rootQuest.id then
            local procId = ctx.get()._ProcID
            return procId and get_processor_entity(procId, rootQuest.id)
        else
            return nil
        end
    end

    local function get_variable_from_fields(questIdField, nameHashField)
        questIdField = questIdField or '_QuestID'
        nameHashField = nameHashField or '_NameHash'

        --- @param ctx UIContainer
        return function (ctx)
            local questId = ctx.get()[questIdField]
            local nameHash = ctx.get()[nameHashField]
            local quest
            if questId == -1 then
                quest = ctx.owner and ctx.owner.type == 'quest' and ctx.owner
            else
                quest = udb.get_entity('quest', questId)
            end
            --- @cast quest QuestDataSummary|nil
            if quest then
                ctx.data._variable = utils.first_where(quest.Variables._Variables, function (var)
                    --- @cast var app.QuestVariable
                    return var._NameHash == nameHash
                end)

                if ctx.data._variable then return quest end
            end
        end
    end

    --- @param elementArray SystemArray app.QuestProcessor.ProcCondition.Element[]
    --- @param procIdList nil|integer[]
    local function get_processor_dependency_ids(elementArray, procIdList)
        procIdList = procIdList or {}
        if not elementArray then return procIdList end
        for _, el in pairs(elementArray) do
            for _, param in pairs(el._ParamArray) do
                procIdList[#procIdList+1] = param._ProcID
            end
            if el._ElementArray and el._ElementArray:get_size() > 0 then
                get_processor_dependency_ids(el._ElementArray, procIdList)
            end
        end
        return procIdList
    end

    --- @param processor QuestProcessorData
    local function draw_quest_processor(processor)
        _userdata_DB._ui_ext.show_save_settings(processor)
        _quest_DB.quest_processors.show_quest_processor(processor)
    end
    local function draw_quest_var(quest, ctx)
        ui.handlers.show_readonly(ctx.data._variable, quest, nil, 'app.QuestVariable')
    end
    --- @param quest QuestDataSummary
    --- @param var UIContainer
    local function quest_var_label(quest, var)
        local hash = var.get()._NameHash
        local varname = varNames.get_label(hash) or 'unnamed'
        return 'Linked variable ' .. hash .. ' ('..varname..') of quest ' .. quest.id
    end

    --- @param processor app.QuestProcessor
    local function show_processor_dependents(processor)
        if imgui.tree_node('Dependent processors') then
            local procFolder = gamedb.get_quest_scene_folder(processor:get_QuestID())
            procFolder = procFolder and procFolder:find('Resident')
            if procFolder then
                local procList = utils.folder_get_children(procFolder)
                for _, transform in ipairs(procList) do
                    if transform and transform:get_GameObject() then
                        local proc = utils.get_gameobject_component(transform:get_GameObject(), 'app.QuestProcessor')
                        --- @cast proc app.QuestProcessor|nil
                        if proc then
                            local depIds = get_processor_dependency_ids(proc.PrevProcCondition._ElementArray)
                            if utils.table_contains(depIds, processor.ProcID) then
                                if ui.core.treenode_suffix('Processor ' .. proc.ProcID, helpers.to_string(proc)) then
                                    local ent = udb.get_entity('quest_processor', proc.ProcID)
                                    if ent then
                                        --- @cast ent QuestProcessorData
                                        draw_quest_processor(ent)
                                    else
                                        ui.handlers.show(proc, nil, nil, 'app.QuestProcessor')
                                    end
                                    imgui.tree_pop()
                                end
                            end
                        end
                    else
                        imgui.text('NULL gameobject')
                    end
                end
            else
                imgui.text("Can't fetch dependent processors on raw data, sorry. Try going ingame")
            end
            imgui.tree_pop()
        end
    end

    --#region Helper functions
    local variable_to_quest_id_map = {}
    --- @param var app.QuestVariable
    local function get_quest_id_from_variable_instance(var)
        if variable_to_quest_id_map[var] then
            return variable_to_quest_id_map[var]
        end

        local db = _quest_DB.database
        if not db then return 0 end

        for _, catalog in pairs(gamedb.get_quest_catalogs()) do
            for _, ql in pairs(catalog.ContextData.VariableDataArray) do
                --- @cast ql app.QuestContextData.VariableData
                for _, gamevar in pairs(ql._Variables) do
                    if gamevar == var then
                        variable_to_quest_id_map[var] = ql._IDValue
                        return ql._IDValue
                    end
                end
            end
        end
        -- print('quest not found', var._NameHash)
        return 0
    end

    --- @return string|nil
    local function tryGetEnumLabelForQuestVariable(questId, variableHash)
        if not questId then return nil end
        local container = _quest_DB.database.quests.get_quest_variables_enum(questId) --- @type EnumSummary|nil
        local var_name = container and container.get_label(variableHash)
        return var_name
    end

    --#endregion

    local DayOfWeekFlags = enums.utils.get_virtual_enum('app.DayOfWeek[Flags]', {
        Sunday = 1,
        Monday = 2,
        Tuesday = 4,
        Wednesday = 8,
        Thursday = 16,
        Friday = 32,
        Saturday = 64,
    })

    local intOperatorTostrings = {
        [enums.LogicalOperatorInt.Lessthan] = '<=',
        [enums.LogicalOperatorInt.Less] = '<',
        [enums.LogicalOperatorInt.Equal] = '==',
        [enums.LogicalOperatorInt.NotEqual] = '!=',
        [enums.LogicalOperatorInt.More] = '>=',
        [enums.LogicalOperatorInt.Morethan] = '>',
    }

    local boolOperatorTostrings = {
        [enums.LogicalOperatorBool.Equal] = '==',
        [enums.LogicalOperatorBool.NotEqual] = '!=',
    }

    local int_money = ui.handlers.common.int(1, 0, 1000000)
    local level_int = ui.handlers.common.int(0.25, 1, 999)
    local dayOfWeekFlags = ui.handlers.common.enum_flags(DayOfWeekFlags)

    ui.handlers.register_extension_alias('quest_reward_lookup', 'linked_entity', {
        entity_type = 'quest_reward',
        getter = function (ctx)
            return udb.get_entity('quest_reward', ctx.get()._NameHash)
        end,
        draw = function (reward)
            ui.handlers.show(reward.runtime_instance, reward, nil, 'app.QuestRewardData')
        end
    })

    ui.handlers.register_extension_alias('quest_deliver_select_data', 'linked_entity', {
        entity_type = 'quest',
        getter = function (ctx)
            return udb.get_entity('quest', ctx.get()._QuestID)
        end,
        labeler = function (quest, ctx)
            return 'Deliver ' .. ctx.get()._Key .. ' - ' .. quest.label
        end,
        draw = function (quest, ctx)
            local deliverKey = ctx.get()._Key
            --- @cast quest QuestDataSummary
            local deliverData = utils.first_where(quest.Deliver._Delivers, function (deliver)
                return deliver._SerialNum == deliverKey
            end)
            if deliverData then
                ui.handlers.show(deliverData, quest, nil, 'app.QuestDeliver')
            else
                imgui.text_colored('Deliver data not found', core.get_color('warning'))
            end
        end
    })

    ui.handlers.register_extension('quest_processor_dependents', function (handler, data)
        --- @type UIHandler
        return function (ctx)
            local changed = handler(ctx)
            show_processor_dependents(ctx.get())
            return changed
        end
    end)

    --- @type table<string, UserdataEditorSettings>
    local ui_override_settings = {
        --- Sudden quest / event related objects
        ['app.quest.condition.SuddenQuestCondition.CheckTimeOfDay'] = {
            toString = function (item) return 'CheckTimeOfDay: ' .. enums.TimeZoneType.valueToLabel[item._TimeZone] .. ', ' .. string.format('%02d:%02d', item._StartPointHour, item._StartPointMinute) .. ' - ' .. string.format('%02d:%02d', item._EndPointHour, item._EndPointMinute) end,
            fieldOrder = {'_StartPointHour', '_StartPointMinute', '_EndPointHour', '_EndPointMinute', '_DayOfWeekBits'},
            fields = {
                _StartPointHour = {label = 'Start hour', uiHandler = ui.handlers.common.preset.hour_slider},
                _StartPointMinute = {label = 'Start minute', uiHandler = ui.handlers.common.preset.minute_slider},
                _EndPointHour = {label = 'End hour', uiHandler = ui.handlers.common.preset.hour_slider},
                _EndPointMinute = {label = 'End minute', uiHandler = ui.handlers.common.preset.minute_slider},
                _DayOfWeekBits = {label = 'Days of the week', uiHandler = dayOfWeekFlags },
            },
        },
        ['app.quest.condition.SuddenQuestCondition.CheckSentimentRank'] = {
            toString = function (item) return 'CheckSentimentRank: ' .. enums.NPCIDs.get_label(item._NpcID) .. ' ' .. intOperatorTostrings[item._Logic] .. ' ' .. enums.SentimentRank.valueToLabel[item._Rank] end,
        },
        ['app.quest.condition.SuddenQuestCondition.CheckScenario'] = {
            toString = function (item) return 'CheckScenario: ' .. utils.string_join(' ', item._QuestID, boolOperatorTostrings[item._Logic], item._ResultNo) end,
            fields = {
                _ResultNo = {label = 'ResultNo', uiHandler = ui.handlers.common.int(0.05)},
            },
        },
        ['app.quest.condition.SuddenQuestCondition.CheckPlayerLevel'] = {
            toString = function (item) return 'CheckPlayerLevel: ' .. utils.string_join(' ', intOperatorTostrings[item._Logic] or '~', item._Level) end,
            fields = {
                _Level = { label = 'Level', uiHandler = level_int },
            },
        },
        ['app.quest.condition.SuddenQuestCondition.CheckDoorStateParam'] = {
            toString = function (item) return 'CheckDoorStateParam: ' .. enums.GimmickLockID.valueToLabel[item._GimmickDoorID] .. (item._Logic == enums.LogicalOperatorBool.Equal and ' True' or ' Not true') end,
        },
        ['app.quest.condition.SuddenQuestCondition'] = {
            labels = {
                _ConditionArray = 'Conditions',
            }
        },
        ['app.SuddenQuestContextData.ContextData'] = {
            fieldOrder = { '_NpcID', '_Type' },
            fields = {
                _NpcID = { label = 'Quest NPC', uiHandler = ui.handlers.common.enum_lazy('CharacterID_NPC') },
            }
        },
        ['app.AIKeyLocation'] = {
            extensions = { { type = 'warp_to_location' } }
        },
        ['app.SuddenQuestContextData.ContextData.EnemySettingData'] = {
            fields = {
                _Location = {
                    label = 'Key location',
                    extensions = {
                        { type = 'conditional', condition = function (context)
                            --- @cast context UIContainer
                            return context.parent.get() and context.parent.get()._SpawnType == enums.SpawnPositionType.labelToValue.KeyLocation end
                        }
                    },
                },
                _Distance = { uiHandler = ui.handlers.common.preset.float_0_200 },
                _RequestID = {
                    extensions = {
                        { type = 'linked_entity', entity_type = 'domain_query_generate_table', draw = function (entity) _userdata_DB._ui_handlers.show_readonly(entity.table, entity) end }
                    }
                },
            }
        },
        ['app.GenerateTable.InitialSetData[]'] = {
            toString = function (value)
                return helpers.array_to_string(value, ', ', 'app.GenerateTable.InitialSetData[]')
            end
        },
        ['app.GenerateTable.InitialSetData'] = {
            fields = {
                TimeZoneEnum = { uiHandler = ui.handlers.common.enum_flags(enums.utils.get_enum('app.TimeManager.TimeZone')) },
            },
            toString = function (value)
                return enums.utils.get_enum('app.GenerateTable.ListGroupEnum').get_label(value.GroupEnum) .. ': ' .. value.SetCount .. ' enemies, TimeZoneEnum=' .. value.TimeZoneEnum
            end
        },
        ['app.GenerateRowData'] = {
            toString = function (value)
                local range = value._AppearNum or {x=-1,y=-1}
                local rate = value._AppearRate or 0.0
                return enums.utils.get_enum('app.GenerateTable.ListGroupEnum').get_label(value._Group) .. ': ' .. rate .. '%% [' .. range.x .. '-' .. range.y .. '] ' .. enums.CharacterID.get_label(value._CharaID)
            end
        },
        ['app.SuddenQuestContextData.ContextData.FailureSettingData'] = {
            fields = {
                _Time = { uiHandler = ui.handlers.common.preset.float_0_1000 },
                _Distance = { uiHandler = ui.handlers.common.preset.float_0_1000 },
                _Flags = { uiHandler = ui.handlers.common.enum_flags(enums.SuddenContextFailureFlags) },
            },
        },
        ['app.SuddenQuestContextData.ContextData.SuccessSettingData'] = {
            fields = {
                _Distance = { uiHandler = ui.handlers.common.preset.float_0_1000 },
                _Flags = { uiHandler = ui.handlers.common.enum_flags(enums.SuddenContextSuccessFlags) },
            }
        },
        ['app.SuddenQuestContextData.ContextData.TalkDirectSettingData'] = {
            fields = {
                _Distance = { ui_ignore = true }, -- don't think there's a point in changing these from their defaults
                -- app.NPCData has an NPCConfig that has a _ConfigPresentLetter, and there's a letter enum inside that, might be possible to convert those to a guid
            }
        },
        ['app.SuddenQuestSelectData.TimeSetting'] = {
            fields = {
                _Day = {
                    extensions = {
                        { type = 'tooltip', text = 'Days until this event can re-occur again after getting triggered.' }
                    }
                }
            }
        },
        ['app.SuddenQuestSelectData'] = {
            fields = {
                _RelayLocation = {
                    extensions = {
                        { type = 'tooltip', text = 'An additional "middle position" location for the event.\nCan mark an additional predefined position, not sure if it shows up ingame in a map anywhere but can be used as a position in other logic. Unused in basegame.' }
                    }
                },
                _SelectDataArray = {
                    ui_ignore = true,
                }
            }
        },

        --- Quest related objects

        ['app.QuestDeliver'] = {
            fieldOrder = {'_Money'},
        },
        ['app.quest.condition.NpcOverrideCondition.CheckTimeOfDay'] = {
            toString = function (item) return 'CheckTimeOfDay: ' .. enums.TimeZoneType.valueToLabel[item._TimeZone] .. ', ' .. string.format('%02d:%02d', item._StartPointHour, item._StartPointMinute) .. ' - ' .. string.format('%02d:%02d', item._EndPointHour, item._EndPointMinute) end,
            fields = {
                _StartPointHour = { label = 'Start hour', uiHandler = ui.handlers.common.preset.hour_slider },
                _StartPointMinute = { label = 'Start minute', uiHandler = ui.handlers.common.preset.minute_slider },
                _EndPointHour = { label = 'End hour', uiHandler = ui.handlers.common.preset.hour_slider },
                _EndPointMinute = { label = 'End minute', uiHandler = ui.handlers.common.preset.minute_slider },
                _DayOfWeekBits = { label = 'Days of the week', uiHandler = dayOfWeekFlags },
            },
        },
        ['app.quest.condition.NpcOverrideCondition.CheckVariable'] = {
            fields = {
                _Condition = { force_expander = false },
            },
            toString = function (item)
                local var_name = tryGetEnumLabelForQuestVariable(item._Condition._QuestID, item._Condition._NameHash)
                return 'CheckVariable:  var ' .. (var_name or item._Condition._NameHash)
                    .. ' ' .. enums.CompareType.get_label(item._Condition._CompareType)
                    .. ' ' .. tostring(({item._Condition._BoolValue, item._Condition._IntValue})[item._Condition._ValueType])
            end,
        },
        ['app.QuestNpcOverride'] = {
            toString = function (item) return enums.NPCIDs.get_label(item._NpcID) end,
            fields = {
                -- I think this is some dev editor-only setting, basically has a corresponding value for each of the object fields
                _DisplaySettingFlags = { ui_ignore = true },
                _QuestID = { uiHandler = ui.handlers.common.readonly_label() },
                _Condition = { extensions = { { type = 'rect', size = 2 }, { type = 'indent', indent = 4 } } },
                _Appearance = { force_expander = false, extensions = { { type = 'toggleable', field = '_SkipControl' } } },
                _Coffin = { force_expander = false, extensions = { { type = 'toggleable', field = '_SkipControl' } } },
                _Combat = { force_expander = false, extensions = { { type = 'toggleable', field = '_SkipControl' } } },
                _Costume = { force_expander = false, extensions = { { type = 'toggleable', field = '_SkipControl' } } },
                _Crime = { force_expander = false, extensions = { { type = 'toggleable', field = '_SkipControl' } } },
                _Generate = { force_expander = false, extensions = { { type = 'toggleable', field = '_SkipControl' } } },
                _Job = { force_expander = false, extensions = { { type = 'toggleable', field = '_SkipControl' } } },
                _MorguePlace = { force_expander = false, extensions = { { type = 'toggleable', field = '_SkipControl' } } },
                _Schedule = { force_expander = false, extensions = { { type = 'toggleable', field = '_SkipControl' } } },
            }
        },
        ['app.NPCSchedule'] = {
            toString = function (item) return enums.NPCIDs.get_label(item.ID) end,
            fields = {
                StartHour = { label ='Start hour', uiHandler = ui.handlers.common.preset.hour_slider },
                StartWeek = { label ='Start week', uiHandler = ui.handlers.common.preset.week_slider },
                EndHour = { label ='End hour', uiHandler = ui.handlers.common.preset.hour_slider },
                EndWeek = { label ='End week', uiHandler = ui.handlers.common.preset.week_slider },
            },
        },
        ['app.QuestAfterStoryData.CheckElapsedTimeParam'] = {
            toString = function (item, ctx)
                local questLabel
                if item._QuestID == -1 then
                    questLabel = ctx and ctx.owner and ctx.owner.id or 'Current'
                else
                    questLabel = udb.get_entity_enum('quest').get_label(item._QuestID)
                end
                return 'ElapsedTime:  [' .. (questLabel or 'Invalid') .. ']'
                    .. (item._Operator == 0 and ' >= ' or ' < ')
                    .. string.format('%02d:%02d:%02d', item._Day, item._Hour, item._Minute)
            end
        },
        ['app.quest.condition.CheckElapsedTimeParam'] = {
            toString = function (item)
                return 'ElapsedTime:  ' .. string.format('%02d:%02d', item._ElapsedHour, item._ElapsedMinute)
            end
        },
        ['app.QuestAfterStoryData.CheckVariable'] = {
            toString = function (item)
                local var_name = tryGetEnumLabelForQuestVariable(item._Condition._QuestID, item._Condition._NameHash)
                return 'CheckVariable:  var ' .. (var_name or item._Condition._NameHash)
                    .. ' ' .. enums.CompareType.get_label(item._Condition._CompareType)
                    .. ' ' .. tostring(({item._Condition._BoolValue, item._Condition._IntValue})[item._Condition._ValueType])
            end
        },
        ['app.QuestVariableCondition'] = {
            fieldOrder = {'_QuestID'},
            fields = {
                _IntValue = { extensions = { { type = 'parent_field_conditional', field = '_ValueType', value = 2 } } },
                _BoolValue = { extensions = { { type = 'parent_field_conditional', field = '_ValueType', value = 1 } } },
            },
            extensions = {
                {
                    type = 'linked_entity', entity_type = 'quest',
                    getter = get_variable_from_fields(), draw = draw_quest_var, labeler = quest_var_label
                }
            }
        },
        ['app.te.condition.QuestVariableCondition'] = {
            fieldOrder = {'_QuestID'},
            fields = {
                _IntValue = { extensions = { { type = 'parent_field_conditional', field = '_ValueType', value = 2 } } },
                _IntFact = { extensions = { { type = 'parent_field_conditional', field = '_ValueType', value = 2 } } },
                _BoolValue = { extensions = { { type = 'parent_field_conditional', field = '_ValueType', value = 1 } } },
                _BoolFact = { extensions = { { type = 'parent_field_conditional', field = '_ValueType', value = 1 } } },
            },
            extensions = {
                {
                    type = 'linked_entity', entity_type = 'quest',
                    getter = get_variable_from_fields(), draw = draw_quest_var, labeler = quest_var_label
                }
            }
        },
        ['app.QuestVariableEntity'] = {
            fields = {
                _IntValue = { extensions = { { type = 'parent_field_conditional', field = '_ValueType', value = 2 } } },
                _BoolValue = { extensions = { { type = 'parent_field_conditional', field = '_ValueType', value = 1 } } },
                _RefVariable = { force_expander = true }
            },
        },
        ['app.quest.condition.CheckQuestVariableParam'] = {
            fieldOrder = {'_QuestID'},
            fields = {
                _IntValue = { extensions = { { type = 'parent_field_conditional', field = '_ValueType', value = 2 } } },
                _BoolValue = { extensions = { { type = 'parent_field_conditional', field = '_ValueType', value = 1 } } },
            },
            extensions = {
                {
                    type = 'linked_entity', entity_type = 'quest',
                    getter = get_variable_from_fields(), draw = draw_quest_var, labeler = quest_var_label
                }
            },
            toString = function (value)
                local questId = value and value._QuestID
                local questLabel = tostring(questId)
                if questId == -1 then
                    questLabel = ''
                else
                    local quest = udb.get_entity('quest', questId)
                    questLabel = quest and quest.label or tostring(questId)
                end
                local varhash = tostring(value._NameHash)
                local op = ' ' .. (intOperatorTostrings[value._Logic or 0] or '????') .. ' '
                return 'quest ' .. questLabel .. '[variable '..varhash..']' .. op .. tostring(({value._BoolValue, value._IntValue})[value._ValueType])
            end
        },
        ['app.quest.condition.CheckTalkEventEndNoParam'] = {
            toString = function (value)
                local talkEventId = enums.TalkEventDefineID.get_label(value._TalkEventID)
                local endNo = value._EndNo
                local acceptMinusOne = value._AcceptMinusOne and ' or -1' or ''
                return 'Talk event ' .. talkEventId .. ' == ' .. endNo .. acceptMinusOne
            end
        },
        ['app.QuestVariable'] = {
            fieldOrder = {'_NameHash', '_SerialNumber'},
            fields = {
                _NameHash = {
                    extensions = {
                        { type = 'quest_variable_name' },
                        { type = 'tooltip', text = 'Careful with editing this value, it might break any quest processor linked to the variable' },
                    },
                },
                _SerialNumber = { label = 'Serial', extensions = { { type = 'tooltip', text = 'Careful with editing this value, it might break any quest processor linked to the variable' } } },
            },
            toString = function (item)
                --- @cast item app.QuestVariable
                if item == nil then return '<null>' end
                local str = helpers.to_string(item._Variable, 'app.QuestVariableBase')
                local qid = get_quest_id_from_variable_instance(item)
                local var_name = tryGetEnumLabelForQuestVariable(qid, item._NameHash)
                return ' [' .. tostring(var_name or item._NameHash) .. '] ' .. str
            end,
            force_expander = false,
        },
        ['app.QuestProcessorResultNoVariable'] = {
            extensions = {
                {
                    type = 'linked_entity', entity_type = 'quest_processor',
                    getter = get_processor_from_variable, draw = draw_quest_processor
                }
            },
            toString = function (item) return 'Processor quest result number: ' .. item._ProcID end
        },
        ['app.QuestTalkResultVariable'] = {
            toString = function (item) return 'Talk result: ' .. enums.TalkEventDefineID.get_label(item._TalkEventID) end
        },
        ['app.QuestResultNoVariable'] = {
            toString = function (item) return 'Quest result number' end
        },
        ['app.QuestScriptSetVariable'] = {
            fields = {
                _IntValue = { extensions = { { type = 'parent_field_conditional', field = '_ValueType', value = 2 } } },
                _BoolValue = { extensions = { { type = 'parent_field_conditional', field = '_ValueType', value = 1 } } },
            },
            toString = function (item)
                return 'Script-set variable: ' .. tostring(({item._BoolValue, item._IntValue})[item._ValueType])
            end
        },

        ['app.QuestProcessor'] = {
            fieldOrder = {'<CurrentPhase>k__BackingField', 'Process', 'PrevProcCondition'},
            fields = {
                Process = { force_expander = true },
                ['<CurrentPhase>k__BackingField'] = { extensions = { { type = 'tooltip', text = "The current status of this processor, can be edited to force change its status.\nSet it to Standby to reset its state when changes are made.\nFor cancelling, it may usually be better to set the Process object's phase to CancelAction instead." } } }
            },
            extensions = { { type = 'quest_processor_dependents' } },
            toString = function (value, context)
                --- @cast value app.QuestProcessor
                if not value.Process then return '' end
                return helpers.to_string(value.Process.QuestAction, 'app.quest.action.QuestActionBase')
            end
        },
        ['app.QuestProcessor.ProcCondition'] = {
            force_expander = false,
            fields = {
                _ElementArray = { label = 'PrevProcCondition' },
            },
        },
        ['app.QuestProcessor.ProcCondition.ElementParam'] = {
            fieldOrder = {'_ProcID', '_ResultNo'},
            extensions = {
                {
                    type = 'linked_entity', entity_type = 'quest_processor',
                    getter = get_processor_from_condition_element, draw = draw_quest_processor
                }
            }
        },
        ['app.quest.condition.CheckQuestParam'] = {
            extensions = {
                {
                    type = 'linked_entity', entity_type = 'quest_processor',
                    getter = get_processor_from_condition_element, draw = draw_quest_processor
                }
            },
            toString = function (value, context)
                local questId = value and value._QuestID
                local questLabel = tostring(questId)
                if questId == -1 then
                    questLabel = ''
                else
                    local quest = udb.get_entity('quest', questId)
                    questLabel = quest and quest.label or tostring(questId)
                end
                local eq = value._Logic == enums.LogicalOperatorBool.Equal and ' == ' or ' != '
                local procId = value._ProcID
                return questLabel .. '[processor '..tostring(procId)..']' .. eq .. tostring(value._ResultNo)
            end
        },
        ['app.quest.condition.CheckQuestConditionParam'] = {
            force_expander = true,
            labels = {
                _Condition = 'Params',
            },
        },
        ['app.QuestAISituationGenerateParameter'] = {
            extensions = { { type = 'userdata_picker' } }
        },
        ['app.AISituationTask'] = {
            toString = function (item)
                local flows = item.TaskStateFlow
                if flows and flows:get_size() > 0 then
                    local flowDesc = utils.map(flows:get_elements(), helpers.to_string)
                    return utils.string_join(', ', table.unpack(flowDesc))
                end
                return 'AISituationTask: unhandled type'
            end
        },
        ['app.QuestProcessor.ProcessEntity'] = {
            toString = function (item)
                return enums.utils.get_enum('app.QuestProcessor.ProcessEntity.Phase').valueToLabel[item:get_CurrentPhase()] .. ' Action: ' .. helpers.to_string(item.QuestAction, 'app.quest.action.QuestActionBase')
            end
        },
        ['app.AISituationTaskStateGuide'] = {
            toString = function (item)
                local pointlist = utils.map(utils.generic_list_to_itable(item.DestinationPointList or {}), function (posval) return enums.AIKeyLocation.get_label(posval.KeyLocation) end)
                return 'app.AISituationTaskStateGuide ' .. utils.string_join(', ', table.unpack(pointlist))
            end
        },
        ['app.quest.action.Trigger'] = {
            toString = function (item)
                local param = utils.first(item._Param)
                return 'Trigger -  ' .. (param and helpers.to_string(param) or '<unknown>')
            end
        },
        ['app.quest.action.TriggerParam'] = {
            toString = function (item)
                local op = item._ConditionParam and item._ConditionParam._Operator == 0 and ' && ' or ' || '
                local elems = helpers.array_elements(item._ConditionParam and item._ConditionParam.ConditionParamArray, 'app.quest.condition.ConditionParamBase[]')
                return table.concat(utils.map(elems, helpers.to_string), op)
            end
        },
        ['app.quest.action.GimmickControl'] = { toString = function (value) return helpers.to_string(utils.first(helpers.get_field(value, '_Param')), 'app.quest.action.GimmickControlParam') end },
        ['app.quest.action.GimmickControlParam'] = {
            fields = {
                _Generate = { force_expander = false, extensions = { { type = 'toggleable', field = '_SkipControl' } } },
                _Option = { force_expander = false, extensions = { { type = 'toggleable', field = '_SkipControl' } } },
            },
            toString = function (value)
                local text = ''
                if value._Generate and not value._Generate._SkipControl then
                    text = helpers.to_string(value._Generate) .. ' '
                end
                if value._Option and not value._Option._SkipControl then
                    text = helpers.array_to_string(value._Option.GimmickOptionArray, ', ', 'app.quest.gimmick.GimmickOptionParamBase[]') .. ' '
                end
                return 'Gimmick - ' .. text
            end
        },
        ['app.quest.action.GenerateSetting'] = {
            toString = function (value, context)
                if type(value) == 'userdata' and value._ResourceData and value._ResourceData:get_Path() ~= '' then
                    return 'Generate: ' .. value._ResourceData:get_Path()
                end
                if type(value) == 'string' then return 'Generate setting: ' .. value end
                return 'Generate setting'
            end
        },
        ['app.quest.gimmick.OptionDoorLockParam'] = {
            toString = function (value) return enums.utils.get_enum('app.quest.gimmick.OptionDoorLockParam.LockStatusKind').get_label(value._LockStatus) .. ': ' .. enums.utils.get_enum('app.GimmickLockID').get_label(value._LockID) end
        },
        ['app.quest.gimmick.OptionGimmickFlagParam'] = {
            toString = function (value) return 'Gimmick flag: ' .. enums.utils.get_enum('app.GimmickFlag').get_label(value._FlagID) .. ' = ' .. enums.utils.get_enum('app.quest.gimmick.OptionGimmickFlagParam.FlagStatusKind').get_label(value._FlagStatus) end
        },
        ['app.quest.gimmick.OptionTreasureBoxParam'] = {
            toString = function (value) return enums.utils.get_enum('app.quest.gimmick.OptionDoorLockParam.LockStatusKind').get_label(value._LockStatus) .. ': Unknown treasure box' end
        },
        ['app.quest.condition.CheckHasItemParam'] = {
            toString = function (item)
                return table.concat(utils.map(item._ItemInfoArray:get_elements(), function (value) return enums.utils.get_enum('app.TalkEventDefine.CharaType').valueToLabel[value._CharaType] .. ' has item: ' .. enums.ItemID.get_label(value._ID) end), ' + ')
            end
        },
        ['app.quest.condition.CheckScenarioStatus'] = { toString = function (item) return helpers.to_string(item.Param, 'app.quest.condition.CheckScenarioParam') end },
        ['app.quest.condition.CheckScenarioParam'] = {
            toString = function (item)
                local op = item._Logic == 0 and ' == ' or ' != '
                return 'Scenario ' .. _userdata_DB.database.get_entity_enum('quest').get_label(item._QuestID) .. op .. item._ResultNo
            end
        },
        ['app.quest.condition.CheckNPCHolderType'] = { toString = function (item) return helpers.to_string(item.Param, 'app.quest.condition.CheckNPCHolderTypeParam') end },
        ['app.quest.condition.CheckNPCHolderTypeParam'] = {
            toString = function (item)
                return enums.CharacterID.get_label(item._CharaID) .. ' type ' .. enums.LogicalOperatorBool.get_label(item._Logic) .. ' ' .. enums.utils.get_enum('app.quest.condition.CheckNPCHolderTypeParam.NPCHolderTypeWrapper').get_label(item._NPCHolderType)
            end
        },
        ['app.quest.condition.CheckPlayerJailParam'] = {
            toString = function (item)
                return item._Logic == 0 and 'Player is in jail' or 'Player is not in jail'
            end
        },
        ['app.QuestNpcOverrideEntiry'] = {
            toString = function (value)
                return value:get_type_definition():get_full_name() .. ' [active: ' .. tostring(value.ConditionEntity:evaluate()) .. ']' .. ' : ' .. enums.NPCIDs.get_label(value.CharacterID)
            end,
        },
        ['System.Collections.Generic.List`1<app.QuestNpcOverrideEntiry>'] = {
            extensions = {
                { type = 'filter_toggle_active' }
            },
            fields = {
                __element = {
                    extensions = {
                        { type = 'filter', filter = function (ctx) return not ctx.parent.data.filter_active or ctx.get().ConditionEntity:evaluate() end }
                    }
                }
            }
        },
        ['app.quest.condition.NpcOverrideConditionEntity'] = {
            force_expander = true,
            fieldOrder = {'_IsNoConditonEnable', '_Operator', '_ConditionArray'},
        },
        ['app.AISituationTaskEntity'] = {
            toString = type_definitions.type_settings['via.UserData'].toString,
            extensions = { { type = 'userdata_picker' } }
        },
        ['app.quest.action.NpcControl'] = { toString = function (item)
            if item.get_type_definition then
                --- @cast item REManagedObject
                return helpers.to_string(sdk.to_managed_object(item:read_qword(offset_QuestActionParamBase_Param))[0], 'app.quest.action.NpcControlParam')
            else
                return 'NPC Control'
            end
        end },
        ['app.quest.action.NpcControlParam'] = {
            force_expander = true,
            fields = {
                _Battle = { force_expander = false, extensions = { { type = 'toggleable', field = '_SkipControl' } } },
                _Crime = { force_expander = false, extensions = { { type = 'toggleable', field = '_SkipControl' } } },
                _Generate = { force_expander = false, extensions = { { type = 'toggleable', field = '_SkipControl' } } },
                _Sentiment = { force_expander = false, extensions = { { type = 'toggleable', field = '_SkipControl' } } },
                _StrayPawn = { force_expander = false, extensions = { { type = 'toggleable', field = '_SkipControl' } } },
                _Talk = { force_expander = false, extensions = { { type = 'toggleable', field = '_SkipControl' } } },
                _Task = { force_expander = false, extensions = { { type = 'toggleable', field = '_SkipControl' } } },
                _Vital = { force_expander = false, extensions = { { type = 'toggleable', field = '_SkipControl' } } },
                _Warp = { force_expander = false, extensions = { { type = 'toggleable', field = '_SkipControl' } } },
            },
            toString = function (value)
                return 'NPC Control - ' .. enums.NPCIDs.get_label(value._NpcID)
            end
        },
        ['app.quest.action.ItemControlParam'] = {
            force_expander = true,
            fields = {
                _ItemGet = { force_expander = false, extensions = { { type = 'toggleable', field = '_SkipControl' } } },
                _Generate = { force_expander = false, extensions = { { type = 'toggleable', field = '_SkipControl' } } },
            }
        },
        ['app.quest.action.OxcartControlParam'] = {
            force_expander = true,
            fields = {
                _Control = { force_expander = false, extensions = { { type = 'toggleable', field = '_SkipControl' } } },
                _CustomParam = { force_expander = false, extensions = { { type = 'toggleable', field = '_SkipControl' } } },
            }
        },
        ['app.quest.action.PawnControlParam'] = {
            force_expander = true,
            fields = {
                _Concierge = { force_expander = false, extensions = { { type = 'toggleable', field = '_SkipControl' } } },
                _Respawn = { force_expander = false, extensions = { { type = 'toggleable', field = '_SkipControl' } } },
                _Task = { force_expander = false, extensions = { { type = 'toggleable', field = '_SkipControl' } } },
            }
        },
        ['app.quest.action.PlayerControlParam'] = {
            force_expander = true,
            fields = {
                _DisplaySettingFlags = { ui_ignore = true },
                _Recover = { force_expander = false, extensions = { { type = 'toggleable', field = '_SkipControl' } } },
                _Vital = { force_expander = false, extensions = { { type = 'toggleable', field = '_SkipControl' } } },
                _Warp = { force_expander = false, extensions = { { type = 'toggleable', field = '_SkipControl' } } },
            }
        },
        ['app.quest.action.QuestRuleControlParam.RuleSetting'] = {
            fields = {
                _PlayerRestrictAggressive = { extensions = { { type = 'flag_toggleable', flagKey = '_RuleFlags', flagValue = ruleFlags.labelToValue.PlayerRestrictAggressive } } },
                _PlayerRestrictCatch = { extensions = { { type = 'flag_toggleable', flagKey = '_RuleFlags', flagValue = ruleFlags.labelToValue.PlayerRestrictCatch } } },
                _PlayerRestrictDash = { extensions = { { type = 'flag_toggleable', flagKey = '_RuleFlags', flagValue = ruleFlags.labelToValue.PlayerRestrictDash } } },
                _PlayerRestrictSkill = { extensions = { { type = 'flag_toggleable', flagKey = '_RuleFlags', flagValue = ruleFlags.labelToValue.PlayerRestrictSkill } } },
                _PlayerRestrictJump = { extensions = { { type = 'flag_toggleable', flagKey = '_RuleFlags', flagValue = ruleFlags.labelToValue.PlayerRestrictJump } } },
                _PartyRestrictAggressive = { extensions = { { type = 'flag_toggleable', flagKey = '_RuleFlags', flagValue = ruleFlags.labelToValue.PartyRestrictAggressive } } },
                _PartyRestrictDash = { extensions = { { type = 'flag_toggleable', flagKey = '_RuleFlags', flagValue = ruleFlags.labelToValue.PartyRestrictDash } } },
                _PartyRestrictSkill = { extensions = { { type = 'flag_toggleable', flagKey = '_RuleFlags', flagValue = ruleFlags.labelToValue.PartyRestrictSkill } } },
                _PartyDisableOrder = { extensions = { { type = 'flag_toggleable', flagKey = '_RuleFlags', flagValue = ruleFlags.labelToValue.PartyDisableOrder } } },
                _TimeNotGoes = { extensions = { { type = 'flag_toggleable', flagKey = '_RuleFlags', flagValue = ruleFlags.labelToValue.TimeNotGoes } } },
                _TimeGoesUpToDayEnd = { extensions = { { type = 'flag_toggleable', flagKey = '_RuleFlags', flagValue = ruleFlags.labelToValue.TimeGoesUpToDayEnd } } },
                _UIRestrictPauseMenu = { extensions = { { type = 'flag_toggleable', flagKey = '_RuleFlags', flagValue = ruleFlags.labelToValue.UIRestrictPauseMenu } } },
                _UIRestrictPauseMenuItem = { extensions = { { type = 'flag_toggleable', flagKey = '_RuleFlags', flagValue = ruleFlags.labelToValue.UIRestrictPauseMenuItem } } },
                _UIRestrictPauseMenuMap = { extensions = { { type = 'flag_toggleable', flagKey = '_RuleFlags', flagValue = ruleFlags.labelToValue.UIRestrictPauseMenuMap } } },
                _UIRestrictPauseMenuQuest = { extensions = { { type = 'flag_toggleable', flagKey = '_RuleFlags', flagValue = ruleFlags.labelToValue.UIRestrictPauseMenuQuest } } },
                _UIRestrictPauseMenuEquipment = { extensions = { { type = 'flag_toggleable', flagKey = '_RuleFlags', flagValue = ruleFlags.labelToValue.UIRestrictPauseMenuEquipment } } },
                _UIRestrictPauseMenuStatus = { extensions = { { type = 'flag_toggleable', flagKey = '_RuleFlags', flagValue = ruleFlags.labelToValue.UIRestrictPauseMenuStatus } } },
                _UIRestrictPauseMenuHistory = { extensions = { { type = 'flag_toggleable', flagKey = '_RuleFlags', flagValue = ruleFlags.labelToValue.UIRestrictPauseMenuHistory } } },
                _UIRestrictPauseMenuPhoto = { extensions = { { type = 'flag_toggleable', flagKey = '_RuleFlags', flagValue = ruleFlags.labelToValue.UIRestrictPauseMenuPhoto } } },
                _UIRestrictPauseMenuSave = { extensions = { { type = 'flag_toggleable', flagKey = '_RuleFlags', flagValue = ruleFlags.labelToValue.UIRestrictPauseMenuSave } } },
                _UIRestrictMiniMap = { extensions = { { type = 'flag_toggleable', flagKey = '_RuleFlags', flagValue = ruleFlags.labelToValue.UIRestrictMiniMap } } },
                _PlayerRestrictPresent = { extensions = { { type = 'flag_toggleable', flagKey = '_RuleFlags', flagValue = ruleFlags.labelToValue.PlayerRestrictPresent } } },
                _GenerateOnlyPermitedId = { extensions = { { type = 'flag_toggleable', flagKey = '_RuleFlags', flagValue = ruleFlags.labelToValue.GenerateOnlyPermitedId } } },
                _GenerateStrayPawnLimit = { extensions = { { type = 'flag_toggleable', flagKey = '_RuleFlags', flagValue = ruleFlags.labelToValue.GenerateStrayPawnLimit } } },
            }
        },
        ['app.quest.action.StrayPawnSetting'] = {
            force_expander = true,
        },
        ['app.quest.action.TaskSetting'] = {
            fields = {
                _PlayTaskCondition = { force_expander = true },
                _GenerateResourceData = { force_expander = true },
            },
        },
        ['app.QuestConditionParam'] = {
            force_expander = true,
            toString = function (item)
                local op = item._Operator == 0 and ' && ' or ' || '
                return helpers.array_to_string(item.ConditionParamArray, op, 'app.quest.condition.ConditionParamBase[]')
            end
        },
        ['app.quest.action.QuestActionBase'] = {
            extensions = { { type = 'quest_action_param_type_matcher' } }
        },
        ['AISituation.ConditionCheckGender'] = {
            toString = function (item)
                return 'Gender ' .. (item.IsReverse and '!=' or '==') .. ' ' .. enums.utils.get_enum('app.CharacterData.GenderDefine').get_label(item.Gender)
            end,
        },
        ['AISituation.ConditionCheckCharaID'] = {
            toString = function (value)
                return enums.CharacterID.get_label(value.CharaID)
            end
        },
        ['AISituation.AISituationRole'] = {
            toString = function (item)
                return helpers.array_to_string(item.ConditionGroup, ' || ', 'AISituation.AISituationRole.ANDGroup[]')
            end
        },
        ['AISituation.AISituationPrerequisite[]'] = {
            toString = function (item)
                return helpers.array_to_string(item, ' && ', 'AISituation.AISituationPrerequisite[]')
            end
        },
        ['AISituation.AISituationRole.ANDGroup'] = {
            toString = function (item)
                return helpers.array_to_string(item.RoleConditions, ' && ', 'AISituation.AISituationPrerequisite[]')
            end
        },
        ['AISituation.AISituationRole.ANDGroup[]'] = {
            toString = function (item)
                return helpers.array_to_string(item, ' || ', 'AISituation.AISituationRole.ANDGroup[]')
            end
        },
        ['app.QuestTreeData.TransitionData'] = {
            toString = function (item)
                return helpers.array_to_string(item._ElementArray, ' && ', 'app.QuestTreeData.TransitionData.Element[]')
            end
        },
        ['app.QuestTreeData.TransitionData.Element'] = {
            toString = function (item)
                local op = item._Operator == 0 and ' || ' or ' && '
                return helpers.array_to_string(item._ParamArray, op, 'app.QuestTreeData.TransitionData.ElementParam[]')
            end
        },
        ['app.QuestTreeData.TransitionData.ElementParam'] = {
            toString = function (item) return item._QuestID .. ' == ' .. item._ResultNo end
        },
        ['app.QuestTreeData.NodeData'] = {
            toString = function (item)
                local endOperator = item._EndConditionParam._Operator == 0 and ' AND ' or ' OR '
                local endConditions = helpers.array_to_string(item._EndConditionParam._ConditionArray, endOperator, 'app.quest.condition.ScenarioConditionParam.ConditionBase[]')

                local relationIds = table.concat(utils.map(helpers.array_elements(item._RelationIDs, 'System.Int32[]'), function (a) return a.m_value end), ', ')
                if not relationIds or relationIds == '' then relationIds = '/' end

                local previousTransitions = helpers.array_to_string(item._PrevTransitions, ' && ')

                return item._QuestID .. ' [Previous: ' .. previousTransitions .. '] [End condition: ' .. endConditions .. '] Relations: ' .. relationIds
            end
        },
        ['app.QuestDeliver.MoneyData'] = {
            fields = {
                _Value = { label = 'Money value', uiHandler = int_money }
            },
        },
        ['app.QuestDeliver.ItemData.ValueInfo'] = {
            fields = {
                _Name = ui.handlers.common.helpers.translatable_guid_field,
                _DescriptionText = ui.handlers.common.helpers.translatable_guid_field,
            },
        },
        ['System.Guid'] = {
            force_expander = false,
        },
        ['app.QuestAfterStoryData'] = {
            fields = {
                _TalkEvent = { extensions = { { type = 'parent_field_conditional', field = '_Type', value = 0 } } },
                _NpcOverride = { extensions = { { type = 'parent_field_conditional', field = '_Type', value = 1 } } },
            },
            toString = function (item)
                return item._Type == 0 and 'TalkEvent' or 'NpcOverride'
            end
        },
        ['AISituation.ConditionCheckSpecies'] = {
            toString = function (item)
                return 'Species ' .. (item.IsReverse and '!=' or '==') .. ' ' .. enums.utils.get_enum('app.CharacterData.SpeciesDefine').get_label(item.Species)
            end
        },
        ['app.quest.condition.ScenarioConditionParam.CheckScenario'] = {
            toString = function (item)
                return item._QuestID .. (item._Logic == 0 and ' == ' or ' != ') .. item._ResultNo
            end
        },
        ['app.QuestLogResource.QuestLogTaskDestination'] = {
            fields = {
                _Area = { extensions = { { type = 'parent_field_conditional', field = '_DestType', value = 0 } } },
                _LocalArea = { extensions = { { type = 'parent_field_conditional', field = '_DestType', value = 1 } } },
                _CharaID = { extensions = { { type = 'parent_field_conditional', field = '_DestType', value = 2 } } },
                _HasShowConditions = { ui_ignore = true },
                _HasDisplayConditions = { ui_ignore = true },
                _ShowConditions = { extensions = { { type = 'sibling_field_toggleable', field = '_HasShowConditions' } } },
                _Conditions = { extensions = { { type = 'sibling_field_toggleable', field = '_HasDisplayConditions' } } },
                _MsgId = ui.handlers.common.helpers.translatable_guid_field,
            },
        },
        ['app.DomainQueryGenerateTable.DomainQueryGenetateTableElement'] = {
            fields = {
                _DomainQueryAsset = {
                    force_expander = true,
                    extensions = { { type = 'userdata_dropdown', options = {
                        'LevelDesign/Generate/DomainQueryGenerate/DomainQuery/SuddenQuest.user',
                        'LevelDesign/Generate/DomainQueryGenerate/DomainQuery/CampRaid.user',
                        'LevelDesign/Generate/DomainQueryGenerate/DomainQuery/Ch222CallItemQuery.user',
                        'LevelDesign/Generate/DomainQueryGenerate/DomainQuery/DomainQueryGenerateSample.user',
                        'LevelDesign/Generate/DomainQueryGenerate/DomainQuery/MonsterReinforceQuery.user',
                        'LevelDesign/Generate/DomainQueryGenerate/DomainQuery/OxcartAssult.user',
                        'LevelDesign/Generate/DomainQueryGenerate/DomainQuery/PotdragonSummonQuery.user',
                    } } }
                }
            },
        },
        ['app.dqs.DomainQueryAsset'] = {
            toString = type_definitions.type_settings['via.UserData'].toString,
        },
        ['app.QuestLogResource'] = {
            fields = {
                _Title = ui.handlers.common.helpers.translatable_guid_field,
                _Summary = ui.handlers.common.helpers.translatable_guid_field,
            },
        },
        ['app.QuestLogResource.QuestLogTaskData'] = {
            fields = {
                _BaseMsg = ui.handlers.common.helpers.translatable_guid_field,
                _DetailMsg = ui.handlers.common.helpers.translatable_guid_field,
                _Destinations = { extensions = { { type = 'parent_field_conditional', field = '_HasDestination', value = true } } },
            },
            toString = ui.handlers.common.helpers.tostring_field_translator('_BaseMsg', 'Task: '),
        },
        ['app.QuestLogResource.QuestLogReportData'] = {
            fields = {
                _BaseMsg = ui.handlers.common.helpers.translatable_guid_field,
                _DetailMsg = ui.handlers.common.helpers.translatable_guid_field,
            },
            toString = ui.handlers.common.helpers.tostring_field_translator('_BaseMsg', 'Report: '),
        },
        ['app.QuestLogResource.QuestLogRemindData'] = {
            fields = {
                _BaseMsg = ui.handlers.common.helpers.translatable_guid_field,
                _DetailMsg = ui.handlers.common.helpers.translatable_guid_field,
            },
            toString = ui.handlers.common.helpers.tostring_field_translator('_BaseMsg', 'Reminder: '),
        },
        ['app.QuestLogResource.QuestLogImpossibleData'] = {
            fields = {
                _BaseMsg = ui.handlers.common.helpers.translatable_guid_field,
                _DetailMsg = ui.handlers.common.helpers.translatable_guid_field,
            },
            toString = ui.handlers.common.helpers.tostring_field_translator('_BaseMsg', 'Impossible: '),
        },
        ['app.QuestLogResource.QuestLogCondition[]'] = {
            fields = {
                __element = {
                    extensions = {
                        {
                            type = 'linked_entity', entity_type = 'quest',
                            getter = get_variable_from_fields(), draw = draw_quest_var, labeler = quest_var_label
                        },
                    }
                }
            },
        },
        ['app.QuestOracleHint'] = {
            fields = {
                _HintAreaID = ui.handlers.common.helpers.translatable_guid_field,
                _HintEnemyID = ui.handlers.common.helpers.translatable_guid_field,
                _HintItemID = ui.handlers.common.helpers.translatable_guid_field,
                _HintItemID2 = ui.handlers.common.helpers.translatable_guid_field,
                _HintMsgID = ui.handlers.common.helpers.translatable_guid_field,
                _HintNpcID = ui.handlers.common.helpers.translatable_guid_field,
                _HintTime = ui.handlers.common.helpers.translatable_guid_field,
            }
        },
        ['app.quest.action.EnemyControlParam'] = {
            fields = {
                _DisplaySettingFlags = { ui_ignore = true },
                _Battle = { force_expander = false, extensions = { { type = 'toggleable', field = '_SkipControl' } } },
                _Disable = { force_expander = false, extensions = { { type = 'toggleable', field = '_SkipControl' } } },
                _Generate = { force_expander = false, extensions = { { type = 'toggleable', field = '_SkipControl' } } },
                _Vital = { force_expander = false, extensions = { { type = 'toggleable', field = '_SkipControl' } } },
            }
        },
        ['app.QuestOracleSetting'] = {
            fields = {
                _BaseMsgID = ui.handlers.common.helpers.translatable_guid_field,
            }
        },
        ['app.QuestOracleHintSetting'] = {
            fields = {
                _BaseMsgID = ui.handlers.common.helpers.translatable_guid_field,
            }
        },
        ['app.QuestLogResource.QuestLogCondition'] = {
            fields = {
                _IntValue = { extensions = { { type = 'parent_field_conditional', field = '_ValueType', value = 2 } } },
                _IntFact = { extensions = { { type = 'parent_field_conditional', field = '_ValueType', value = 2 } } },
                _BoolValue = { extensions = { { type = 'parent_field_conditional', field = '_ValueType', value = 1 } } },
                _BoolFact = { extensions = { { type = 'parent_field_conditional', field = '_ValueType', value = 1 } } },
            },
        },
        ['app.QuestLogResource.QuestLogTaskCheckListData'] = {
            fields = {
                _BaseMsg = ui.handlers.common.helpers.translatable_guid_field,
            },
            toString = ui.handlers.common.helpers.tostring_field_translator('_BaseMsg', 'Quest checklist: '),
        },
        ['app.TalkEventCast.SubstituteCastConditionList.SubstitutePawnConditon'] = {
            fields = {
                _Subskill = { extensions = { { type = 'parent_field_conditional', field = '_ConditionType', value = 1 } } },
            },
        },
        ['app.TalkEventCast.SubstituteCastConditionList.SubstituteNPCCondition'] = {
            fields = {
                _VoiceType = { extensions = { { type = 'parent_field_conditional', field = '_ConditionType', value = 0 } } },
                _JobType = { extensions = { { type = 'parent_field_conditional', field = '_ConditionType', value = 1 } } },
                _RoleType = { extensions = { { type = 'parent_field_conditional', field = '_ConditionType', value = 2 } } },
            },
            -- the tostring call for this one fails, so at least override it like this for now
            toString = function (value)
                local type = ({'_VoiceType', '_JobType', '_RoleType'})[value._ConditionType + 1]
                return 'NPC Condition: ' .. type .. ' == ' .. value[type] end
        },
        ['app.AISituationTaskStateTalkEventMoveToPlayer'] = {
            fields = {
                DashDistance = { extensions = { { type = 'parent_field_conditional', field = 'IsDash', value = true } } },
                RunDistance = { extensions = { { type = 'parent_field_conditional', field = 'IsRun', value = true } } },
            },
        },
        ['app.QuestDeliverSelectData'] = {
            extensions = {
                { type = 'quest_deliver_select_data' }
            }
        },
        ['app.quest.action.QuestRewardData.Data'] = {
            extensions = {
                { type = 'quest_reward_lookup' }
            }
        },
        ['app.quest.action.PlayEvent'] = {
            toString = function (value) return value._Param and value._Param[0] and helpers.to_string(value._Param[0], 'app.quest.action.PlayEventParam') or 'PlayEvent' end
        },
        ['app.quest.action.SoundControl'] = { toString = function (value) return helpers.to_string(value._Data or utils.first(value._Param)) end },
        ['app.quest.action.SoundControlParam'] = {
            fields = {
                _PlayBgm = { force_expander = false, extensions = { { type = 'parent_field_conditional', field = '_Type', value = 0 } } },
                _ChangeBgm = { force_expander = false, extensions = { { type = 'parent_field_conditional', field = '_Type', value = 1 } } },
                _PlaySe = { force_expander = false, extensions = { { type = 'parent_field_conditional', field = '_Type', value = 2 } } },
            },
            toString = function (value)
                return enums.utils.get_enum('app.quest.action.SoundControlParam.SoundType').get_label(value and value._Type)
            end
        },
        ['app.quest.action.PlayEventParam'] = {
            fields = {
                _TalkEventParam = { force_expander = false, extensions = { { type = 'parent_field_conditional', field = '_Type', value = 0 } } },
                _TalkGimmickParam = { force_expander = false, extensions = { { type = 'parent_field_conditional', field = '_Type', value = 5 } } },
                _DemoParam = { force_expander = false, extensions = { { type = 'parent_field_conditional', field = '_Type', value = 4 } } },
            },
            toString = function (value, context)
                local type = value and value._Type
                if type == 0 then return helpers.to_string(value._TalkEventParam, 'app.quest.action.PlayEventData.TalkEventSetting') end
                return 'Play ' .. enums.utils.get_enum('app.quest.action.PlayEventData.EventType').get_label(type)
            end
        },
        ['app.quest.action.PlayEventData.TalkEventSetting'] = {
            toString = function (value, context)
                local firstId = utils.first(value._IDs)
                firstId = firstId and firstId.value__ -- because it's an enum array, need to unbox the enum value
                local talk = firstId and udb.get_entity('talk_event', firstId)
                return talk and talk.label or 'Unknown TalkEvent ' .. tostring(firstId)
            end
        },
        ['app.quest.condition.CheckNpcDistanceParam'] = {
            fields = {
                _CharaA = { force_expander = false, extensions = { { type = 'parent_field_conditional', field = '_KindA', value = 1 } } },
                _PawnA = { force_expander = false, extensions = { { type = 'parent_field_conditional', field = '_KindA', value = 2 } } },
                _CharaB = { force_expander = false, extensions = { { type = 'parent_field_conditional', field = '_KindB', value = 1 } } },
                _PawnB = { force_expander = false, extensions = { { type = 'parent_field_conditional', field = '_KindB', value = 2 } } },
            },
        },
        ['app.quest.condition.CheckCharacterEquipmentParam'] = {
            fields = {
                _PawnType = { force_expander = false, extensions = { { type = 'parent_field_conditional', field = '_Kind', value = 1 } } },
                _WeaponID = { force_expander = false, extensions = { { type = 'parent_field_conditional', field = '_EquipType', value = 0 } } },
                _HelmID = { force_expander = false, extensions = { { type = 'parent_field_conditional', field = '_EquipType', value = 1 } } },
                _TopsID = { force_expander = false, extensions = { { type = 'parent_field_conditional', field = '_EquipType', value = 2 } } },
                _PantsID = { force_expander = false, extensions = { { type = 'parent_field_conditional', field = '_EquipType', value = 3 } } },
                _MantleID = { force_expander = false, extensions = { { type = 'parent_field_conditional', field = '_EquipType', value = 4 } } },
                _FacewearID = { force_expander = false, extensions = { { type = 'parent_field_conditional', field = '_EquipType', value = 5 } } },
            },
        },
        ['app.AISituation.IsInTimeCondition'] = {
            fields = {
                StartHour = { uiHandler = ui.handlers.common.preset.hour_slider },
                EndHour = { uiHandler = ui.handlers.common.preset.hour_slider },
            }
        },
        ['app.AISituationTaskStateTalkToPlayer'] = {
            fields = {
                _EffectiveArea = { force_expander = false, extensions = { { type = 'toggleable', field = '_Enable', inverted = true } } },
                ChangeVisionSensorRange = { force_expander = false, extensions = { { type = 'parent_field_conditional', field = 'isChangeVisionSensorRange', value = true } } },
                DashDistance = { extensions = { { type = 'parent_field_conditional', field = 'IsDash', value = true } } },
                RunDistance = { extensions = { { type = 'parent_field_conditional', field = 'IsRun', value = true } } },
            },
        },
        ['app.ActInterNode'] = {
            fields = {
                _Command = { label = 'Command', },
                _SubCommand = { label = 'SubCommand', extensions = { { type = 'parent_field_conditional', field = '_UseSubCommand', value = true } } },
            },
            toString = function (value, context)
                return helpers.to_string(value._Command and value._Command._Process) or (context and context.data.classname) or value:get_type_definition():get_full_name()
            end
        },
        -- NOTE: can't do this atm because REF doesn't detect the type at all
        -- ['System.Collections.Generic.LinkedListNode`1<app.ActInterNode>'] = {
        --     fieldOrder = {'item', 'next', 'prev', 'head'},
        -- }
    }

    type_definitions.override('', ui_override_settings)
end

type_definitions.override('quest1', {
    ['app.QuestProcessor.ProcCondition.ElementParam'] = {
        fields = {
            ProcessorArrayIndex = { import_ignore = true }
        },
    },
    ['app.quest.action.NpcControlParam'] = {
        fields = {
            DisplaySettingFlags = { ui_ignore = true, import_ignore = true }, -- this one seems like a capcom editor UI thing, useless for us
        },
    },
})

type_definitions.override_abstract('app.quest.action.QuestActionBase', {
    fieldOrder = {'<CurrentPhase>k__BackingField', '_Param'},
})

type_definitions.override_abstract('AISituation.AISituationTaskStateBase', function(data)
    --- @type UserdataEditorSettings
    local myovers = {
        fields = {
            _TalkEventID = { extensions = { { type = 'parent_field_conditional', field = '_SetTalkEvent', value = true } } },
            _Talk = { extensions = { { type = 'parent_field_conditional', field = '_SetTalk', value = true } } },
        },
    }
    type_definitions.merge_type_override(myovers, data)
end)

_quest_DB.__internal = _quest_DB.__internal or {}
_quest_DB.__internal.quest_handlers = true
