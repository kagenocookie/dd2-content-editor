local core = require('content_editor.core')
local udb = require('content_editor.database')
local definitions = require('content_editor.definitions')
local utils = require('content_editor.utils')
local helpers = require('content_editor.helpers')
local typecache = require('content_editor.typecache')

definitions.override('ai', {
    ['app.goalplanning.AIGoalCategoryBase'] = {
        abstract = {
            'app.goalplanning.AIGoalCategoryNone',
            'app.goalplanning.AIGoalCategoryCommon',
            'app.goalplanning.AIGoalCategoryJob',
        }
    },
})

if core.editor_enabled then
    local ui = require('content_editor.ui')
    local editor = require('content_editor.editor')
    local enums = require('content_editor.enums')

    local blackboardEnumFieldPairs = {
        ['<BlackBoardActionTargetList>k__BackingField'] = {1, 'ValuesActionTargetList', 'System.Collections.Generic.List`1<app.AITarget>', 'BlackBoardActionTargetList'},
        ['<BlackBoardActionTarget>k__BackingField'] = {2, 'ValuesActionTarget', 'app.AITarget', 'BlackBoardActionTarget'},
        ['<BlackBoardBool>k__BackingField'] = {3, 'ValuesBool', 'System.Boolean', 'BlackBoardBool'},
        ['<BlackBoardBoolTrg>k__BackingField'] = {3, 'ValuesBool', 'System.Boolean', 'BlackBoardBoolTrg'},
        ['<BlackBoardFloat>k__BackingField'] = {4, 'ValuesFloat', 'System.Single', 'BlackBoardFloat'},
        ['<BlackBoardGameObj>k__BackingField'] = {5, 'ValuesGameObject', 'via.GameObject', 'BlackBoardGameObj'},
        ['<BlackBoardGameObjList>k__BackingField'] = {6, 'ValuesGameObjectList', 'System.Collections.Generic.List`1<via.GameObject>', 'BlackBoardGameObjList'},
        ['<BlackBoardInt>k__BackingField'] = {7, 'ValuesInt', 'System.Int32', 'BlackBoardInt'},
        ['<BlackBoardString>k__BackingField'] = {8, 'ValuesString', 'System.Strnig', 'BlackBoardString'},
        ['<BlackBoardVec3>k__BackingField'] = {9, 'ValuesVec3', 'via.vec3', 'BlackBoardVec3'},
        ['<BlackBoardVec3List>k__BackingField'] = {10, 'ValuesVec3List', 'System.Collections.Generic.List`1<via.vec3>', 'BlackBoardVec3List'},
        ['<BlackBoardPosition>k__BackingField'] = {11, 'ValuesPosition', 'via.Position', 'BlackBoardPosition'},
        ['<BlackBoardUlong>k__BackingField'] = {12, 'ValuesUlong', 'System.UInt64', 'BlackBoardUlong'},
    }

    --- @return UIHandler
    local function handle_ai_bb_collection(classname)
        local t_collection = sdk.find_type_definition(classname)
        local collectionEnums = t_collection:get_parent_type():get_generic_argument_types()
        local meta = typecache.get(classname)
        --- @type UIHandler
        return function (ctx)
            local changed = false
            local collection = ctx.get()
            for _, field in ipairs(meta.fields) do
                local fname = field[1]
                local fclass = field[2]
                local fieldpair = blackboardEnumFieldPairs[fname]
                if not fieldpair then
                    if fclass:find('`12.Convert') then
                        -- ignore converters
                    else
                        ui.handlers._internal.create_field_editor(ctx, classname, fname, fclass, ui.handlers._internal.generate_field_label(fname), nil, {}):ui()
                    end
                else
                    local enumType = collectionEnums[fieldpair[1]]:get_full_name()
                    local keysArray = collection[fieldpair[2]] ---@type SystemArray
                    local valueType = fieldpair[3]
                    local categoryLabel = fieldpair[4]
                    local specificCollection = collection[fname] -- AIBlackBoardBase<T>

                    local count = specificCollection.values:get_size()
                    if count > 0 and imgui.tree_node(categoryLabel) then
                        local vargroupchild = ui.context.get_or_create_child(ctx, fname, specificCollection, categoryLabel, nil, specificCollection:get_type_definition():get_full_name())
                        for i = 0, specificCollection.values:get_size() - 1 do
                            local child = ui.context.get_child(ctx, i)
                            if not child then
                                local keyEnum = keysArray[i]

                                vargroupchild.data._has_extra_expander = true
                                child = ui.handlers._internal.create_field_editor(
                                    vargroupchild,
                                    vargroupchild.data.classname,
                                    i,
                                    valueType,
                                    '[' .. i .. '] ' .. (keyEnum and helpers.to_string(keyEnum, enumType) or ''),
                                    { set = function () print('ERROR blackboard array not editable') end, get = function (object, fieldname)
                                        return specificCollection.values[fieldname]._Value
                                    end },
                                    { is_raw_data = false, hide_nonserialized = false },
                                    nil
                                )
                            end
                            changed = child:ui() or changed
                        end
                        imgui.tree_pop()
                    end
                end
            end
            return false
        end
    end

    definitions.override('', {
        ['app.PawnAIGoalActionData'] = {
            toString = function (value, context)
                return value:ToString()
            end
        },
        ['app.goalplanning.AIGoalParamData[]'] = {
            force_expander = true
        },
        ['app.goalplanning.AIGoalParamData'] = {
            force_expander = true,
        },
        ['app.goalplanning.AIGoalCategoryCommon'] = {
            toString = function (value)
                ---@cast value app.goalplanning.AIGoalCategoryCommon
                return value._Decisions._DecisionPacks:ToString()
            end
        },
        ['app.PawnBattleController.SpecialBattleFlags[]'] = {
            toString = function (value)
                return helpers.array_to_string(value, ', ', 'app.PawnBattleController.SpecialBattleFlags[]', '<none>')
            end
        },
        ['app.AIBlackBoardCommonCollection'] = { uiHandler = handle_ai_bb_collection('app.AIBlackBoardCommonCollection'), },
        ['app.AIBlackBoardActionCollection'] = { uiHandler = handle_ai_bb_collection('app.AIBlackBoardActionCollection'), },
        ['app.AIBlackBoardFormationCollection'] = { uiHandler = handle_ai_bb_collection('app.AIBlackBoardFormationCollection'), },
        ['app.AIBlackBoardNpcCollection'] = { uiHandler = handle_ai_bb_collection('app.AIBlackBoardNpcCollection'), },
        ['app.AIBlackBoardSituationCollection'] = { uiHandler = handle_ai_bb_collection('app.AIBlackBoardSituationCollection'), },
        ['app.CatchController.CatchTypeEnum[]'] = {
            toString = function (value)
                return helpers.array_to_string(value, ', ', 'app.CatchController.CatchTypeEnum[]', '<none>')
            end
        },
        ['app.decision.process.PawnTalk.DecisionPawnTalkSelector'] = {
            toString = function (value)
                return helpers.array_to_string(value, ', ', 'app.decision.process.PawnTalk.DecisionPawnTalkSelector', '<none>')
            end
        },
        ['app.goalplanning.AIGoalCategoryJob'] = {
            toString = function (value)
                ---@cast value app.goalplanning.AIGoalCategoryJob
                return helpers.array_to_string(utils.map(value._JobDecisions:get_elements(), function (item)
                    return helpers.array_to_string(utils.pluck((item--[[@as app.goalplanning.AIGoalCategoryJob.JobDecisions]])._Job, 'm_value'), ' || ', 'app.Character.JobEnum[]')
                end), ', ')
            end
        },
        ['app.AIDecisionDefine.OwnerState'] = {
            uiHandler = ui.handlers.common.enum_flags()
        },
        ['app.StatusConditionDef.StatusConditionFlag'] = {
            uiHandler = ui.handlers.common.enum_flags(nil, 6)
        },
        ['app.AISituation.PawnInfoTaskEvaluation.PersonalityType'] = {
            uiHandler = ui.handlers.common.enum_flags()
        },
        ['app.AISituation.PawnInfoTaskEvaluation.JobEnum'] = {
            uiHandler = ui.handlers.common.enum_flags()
        },
        -- ['app.goalplanning.DecisionsBase'] = {
        --     abstract = {
        --         'app.goalplanning.DecisionsBase',
        --         'app.goalplanning.AIGoalCategoryJob.JobDecisions',
        --     }
        -- },
        ['AISituation.PawnJob.JobEnum'] = {
            uiHandler = ui.handlers.common.enum_flags()
        },
        ['app.CorpseController'] = {
            toString = function (value, context)
                return value:get_GameObject():get_Name() .. ' _IsForceDead=' .. tostring(value._CorruptionController._IsForceDead) .. ', enable=' .. tostring(value._CorruptionController:get_IsEnable())
            end
        }
    })

    definitions.override_abstract('app.decision.condition.ConditionBase', function (def, classname)
        def.toString = helpers.to_string_concat_fields(classname, typecache.fieldFlags.ImportEnable)
    end)
    definitions.override_abstract('app.decision.tcondition.ConditionBase', function (def, classname)
        def.toString = helpers.to_string_concat_fields(classname, typecache.fieldFlags.ImportEnable)
    end)
    definitions.override_abstract('app.decision.process.ProcessBase', function (def, classname)
        def.toString = helpers.to_string_concat_fields(classname, typecache.fieldFlags.ImportEnable)
    end)
    definitions.override_abstract('AISituation.AISituationPrerequisite', function (def, classname)
        def.toString = helpers.to_string_concat_fields(classname, typecache.fieldFlags.ImportEnable)
    end)

    local pawnAiGo, pawnAiData
    editor.define_window('ai_overview', 'AI Overview', function (state)
        pawnAiData = pawnAiData or sdk.get_managed_singleton('app.PawnManager'):get_AIData()
        pawnAiGo = pawnAiGo and pawnAiGo:get_Valid() and pawnAiGo or ce_find(':app.PawnUpdateController::item:get_GameObject()', true)
        ui.handlers.show_readonly(pawnAiData, nil, 'Pawn AI data', 'app.PawnAIData')
        ui.handlers.show_readonly(pawnAiGo, nil, 'Pawn AI root controller', 'via.GameObject')
        imgui.spacing()

        imgui.indent(4)
        imgui.begin_rect()
        ui.handlers.show_editable(utils.get_gameobject_component(pawnAiGo, 'app.PawnUpdateController'), 'AIGoalActionData', nil, 'Goal data')
        ui.handlers.show_editable(utils.get_gameobject_component(pawnAiGo, 'app.PawnBattleController'), '_BattleAIData', nil, 'Battle data')
        ui.handlers.show_editable(utils.get_gameobject_component(pawnAiGo, 'app.PawnOrderController'), 'OrderData', nil, 'Order data')
        ui.handlers.show_readonly(utils.get_gameobject_component(pawnAiGo, 'app.PawnOrderTargetController')--[[@as any]], nil, 'Order target controller')
        ui.handlers.show_readonly(utils.get_gameobject_component(pawnAiGo, 'app.AIMetaController')--[[@as any]], nil, 'Meta controller')
        imgui.end_rect(2)
        imgui.unindent(4)
    end)
end
