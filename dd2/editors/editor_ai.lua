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

    definitions.override('', {
        ['app.PawnAIGoalActionData'] = {
            uiHandler = function (context)
                local val = context.get() ---@type app.PawnAIGoalActionData
                for i, v in pairs(val.DamageParam) do imgui.text('Damage ' .. i .. ': ' .. helpers.to_string(v, 'app.PawnAIGoalActionData')) end
                for i, v in pairs(val.ReactionParam) do imgui.text('Reaction ' .. i .. ': ' .. helpers.to_string(v, 'app.PawnAIGoalActionData')) end
                for i, v in pairs(val.BreakBalanceParam) do imgui.text('BreakBalance ' .. i .. ': ' .. helpers.to_string(v, 'app.PawnAIGoalActionData')) end
                return false
            end,
            toString = function (value, context)
                return value:ToString()
            end
        },
        ['app.goalplanning.AIGoalParamData'] = {

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
        pawnAiGo = pawnAiGo and pawnAiGo:get_Valid() and pawnAiGo or ce_find('/app.PawnUpdateController:::item:get_GameObject()')
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
