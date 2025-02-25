local udb = require('content_editor.database')
local import_handlers = require('content_editor.import_handlers')

local core = require('content_editor.core')
local utils = require('content_editor.utils')
local enums = require('content_editor.enums')

local definitions = require('content_editor.definitions')
local per_field = require('content_editor.helpers.per_field_singleton')

local jobEnum = enums.get_enum('app.Character.JobEnum')
local CharacterManager = sdk.get_managed_singleton('app.CharacterManager') ---@type app.CharacterManager

--- @class HumanParamsEntity : DBEntity
--- @field runtime_instance REManagedObject|table

local function register_entity(id, type, runtime_instance, extra_data)
    --- @type HumanParamsEntity
    local entity = {
        id = id,
        type = type,
        runtime_instance = runtime_instance,
    }
    if extra_data then entity = utils.table_assign(entity, extra_data) end
    return udb.register_pristine_entity(entity)
end

-- fetch current game data
udb.events.on('get_existing_data', function ()
    -- always fetch everything, don't re-fetch if we've already fetched
    if next(udb.get_all_entities_map('job_param')) then return end

    local paramData = CharacterManager:get_HumanParam()
    for i = 1, 10 do
        local field = string.format('Job%02dParameter', i)
        register_entity(i, 'job_param', paramData.JobParam[field])
    end

    for jobId, abilityParam in ipairs(paramData.AbilityParam.JobAbilityParameters:get_elements()) do
        --- @cast abilityParam app.AbilityParameter.JobAbilityParameter
        for _, ability in ipairs(abilityParam.Abilities:get_elements()) do
            --- @cast ability app.AbilityParameter.Ability
            register_entity(ability.AbilityID, 'ability_param', ability, { jobId = jobId })
        end
    end

    for _, e in ipairs(paramData.SpecialBuffParam.BrothelParams:get_elements()) do register_entity(e.CharaID, 'brothel_param', e) end
    for _, e in ipairs(paramData.SpecialBuffParam.CampParams:get_elements()) do register_entity(e.Type, 'camp_param', e) end
    for _, e in ipairs(paramData.SpecialBuffParam.DrinkingParams:get_elements()) do register_entity(e.ID, 'drink_param', e) end
    for _, e in ipairs(paramData.SpecialBuffParam.HotSpringParams:get_elements()) do register_entity(e.Type, 'hotspring_param', e) end
    for _, e in ipairs(paramData.SpecialBuffParam.ItemParams:get_elements()) do register_entity(e.ID, 'item_param', e) end
    for _, e in ipairs(paramData.QuestParam.Job04SnatchItemParam._CharacterItemDatas) do register_entity(e._CharacterID, 'snatch_item_param', e) end
    register_entity(1, 'dragon_hermit_param', paramData.SpecialBuffParam.DragonHermitParam)
    register_entity(1, 'interact_param', paramData.InteractData)
    register_entity(1, 'stamina_param', paramData.StaminaParam)
    register_entity(1, 'speed_param', paramData.SpeedParam)
    register_entity(1, 'item_shortcut_param', paramData.ItemShortcutParam)
    register_entity(1, 'possession_param', paramData.PossessionParam)
end)

udb.register_entity_type('job_param', {
    export = function (instance)
        --- @cast instance HumanParamsEntity
        return { data = import_handlers.export(instance.runtime_instance, 'app.JobUniqueParameter', { raw = true }) }
    end,
    import = function (data, instance)
        --- @cast instance HumanParamsEntity
        instance.runtime_instance = import_handlers.import('app.JobUniqueParameter', data.data, instance.runtime_instance)
        -- putting the data back in shouldn't be needed since we always fetch the existing data beforehand and custom job params aren't supported
        -- local field = string.format('Job%02dParameter', instance.id)
        -- CharacterManager:get_HumanParam().JobParam[field] = instance.runtime_instance
    end,
    generate_label = function (entity)
        return 'Job params ' .. jobEnum.get_label(entity.id)
    end,
    insert_id_range = {0, 0},
    root_types = {'app.JobParameter'},
})

local getAbilityName = sdk.find_type_definition('app.GUIBase'):get_method('getAbilityName')

udb.register_entity_type('ability_param', {
    export = function (instance)
        return {
            data = import_handlers.export(instance.runtime_instance, 'app.AbilityParameter.Ability', { raw = true }),
            jobId = instance.jobId,
        }
    end,
    import = function (data, instance)
        instance.runtime_instance = import_handlers.import('app.AbilityParameter.Ability', data.data, instance.runtime_instance)
        instance.jobId = data.jobId
    end,
    generate_label = function (entity)
        local jobName = jobEnum.get_label(entity.jobId)
        local abilityEnum = enums.get_enum('app.HumanAbilityID')
        local enumLabel = abilityEnum.get_label(entity.id)
        local name = getAbilityName:call(nil, entity.id)
        return jobName .. ' - ' .. enumLabel .. ' ' .. name
    end,
    insert_id_range = {0, 0},
    root_types = {'app.AbilityParameter.Ability'},
})

local entity_classmap = {
    job_param = 'app.JobUniqueParameter',
    ability_param = 'app.AbilityParameter.Ability',
    human_action_param = 'app.HumanActionParameter'
}

--- @param entity_type string
--- @param classname string
--- @param labeler nil|fun(ent: HumanParamsEntity): string
local function define_param_entity(entity_type, classname, labeler)
    entity_classmap[entity_type] = classname
    udb.register_entity_type(entity_type, {
        export = function (instance)
            --- @cast instance HumanParamsEntity
            return { data = import_handlers.export(instance.runtime_instance, classname, { raw = true }) }
        end,
        import = function (data, instance)
            --- @cast instance HumanParamsEntity
            instance.runtime_instance = import_handlers.import(classname, data.data, instance.runtime_instance)
            -- no need to inject anything into game data since we're only editing existing records for now
        end,
        generate_label = labeler or function (entity)
            return entity_type .. ' ' .. entity.id
        end,
        insert_id_range = {0, 0},
        root_types = {},
    })
end

define_param_entity('brothel_param', 'app.HumanSpecialBuffParameter.BrothelParameter', function (ent)
    return 'Brothel params ' .. enums.get_enum('app.CharacterID').get_label(ent.runtime_instance.CharaID)
end)
define_param_entity('camp_param', 'app.HumanSpecialBuffParameter.CampParameter', function (ent)
    return 'Camp params ' .. ent.runtime_instance.Type .. ' ' .. enums.get_enum('app.HumanSpecialBuffDefine.Camp').get_label(ent.runtime_instance.Type)
end)
define_param_entity('drink_param', 'app.HumanSpecialBuffParameter.DrinkingParameter', function (ent)
    return 'Drink params ' .. enums.get_enum('app.ItemIDEnum').get_label(ent.runtime_instance.ID)
end)
define_param_entity('hotspring_param', 'app.HumanSpecialBuffParameter.HotSpringParameter', function (ent)
    return 'Hot spring params ' .. ent.runtime_instance.Type .. ' ' .. enums.get_enum('app.HumanSpecialBuffDefine.HotSpring').get_label(ent.runtime_instance.Type)
end)
define_param_entity('item_param', 'app.HumanSpecialBuffParameter.ItemParameter', function (ent)
    return 'Item params ' .. enums.get_enum('app.ItemIDEnum').get_label(ent.runtime_instance.ID)
end)
define_param_entity('dragon_hermit_param', 'app.HumanSpecialBuffParameter.DragonHermitParameter')

define_param_entity('snatch_item_param', 'app.Job04SnatchItemParameter.CharacterItemData', function (ent)
    return 'Snatch params ' .. enums.get_enum('app.CharacterID').get_label(ent.runtime_instance._CharacterID) .. ' item ' .. enums.get_enum('app.ItemIDEnum').get_label(ent.runtime_instance._ItemID)
end)

define_param_entity('stamina_param', 'app.HumanStaminaParameter')
define_param_entity('speed_param', 'app.HumanSpeedParameter')
define_param_entity('interact_param', 'app.HumanInteractiveObjectData')

per_field.create('human_action_param', 'app.HumanActionParameter', function () return CharacterManager:get_HumanParam().ActionParam end)

definitions.override('human_params', {
    ['app.JobUniqueParameter'] = {
        abstract = {
	        'app.Job01Parameter',
	        'app.Job02Parameter',
	        'app.Job03Parameter',
	        'app.Job04Parameter',
	        'app.Job05Parameter',
	        'app.Job06Parameter',
	        'app.Job07Parameter',
	        'app.Job08Parameter',
	        'app.Job09Parameter',
	        'app.Job10Parameter',
        }
    },
    ['app.StaminaParameterBase'] = {
        abstract = {
            'app.StaminaParameter',
            'app.MonsterStaminaParameterData',
            'app.HumanStaminaParameterAdditionalData',
        }
    },
    ['app.HumanSpeedParameter.SpeedData'] = {
        toString = function (value)
            return enums.get_enum('app.HumanSpeedParameter.ActionTypeEnum').get_label(value.ActionType) .. ' ' .. enums.get_enum('app.HumanSpeedParameter.SubActionTypeEnum').get_label(value.SubActionType)
        end
    },
    ['app.HumanStaminaParameter.RecoverData'] = {
        toString = function (value)
            return enums.get_enum('app.HumanStaminaParameter.RecoverData.ActionTypeEnum').get_label(value.ActionType) .. ' ' .. enums.get_enum('app.HumanStaminaParameter.RecoverData.SubActionTypeEnum').get_label(value.SubActionType)
        end
    },
    ['app.HumanStaminaParameter.ConsumeData'] = {
        toString = function (value)
            return enums.get_enum('app.HumanStaminaParameter.ConsumeData.ActionTypeEnum').get_label(value.ActionType) .. ' ' .. enums.get_enum('app.HumanStaminaParameter.ConsumeData.SubActionTypeEnum').get_label(value.SubActionType)
        end
    },
    ['app.AbilityParameter.Ability'] = {
        fields = {
            Comment = { extensions = { { type = 'autotranslate' } } }
        },
    },
})

if core.editor_enabled then
    local editor = require('content_editor.editor')
    local ui = require('content_editor.ui')

    local param_types = {}
    local param_names = {}
    for _, k in ipairs(utils.get_sorted_table_keys(entity_classmap)) do
        param_types[#param_types+1] = k
        param_names[#param_names+1] = entity_classmap[k]
    end

    editor.define_window('human_params', 'Human params', function (state)
        _, state.param_type_id = imgui.combo('Param type', state.param_type_id or 1, param_names)
        local param_type = param_types[state.param_type_id]
        local selectedParams = ui.editor.entity_picker(param_type, state)
        if selectedParams then
            --- @cast selectedParams HumanParamsEntity
            imgui.spacing()
            imgui.indent(8)
            imgui.begin_rect()
            ui.editor.show_entity_metadata(selectedParams)
            if param_type == 'job_param' then
                local displayType = string.format('app.Job%02dParameter', selectedParams.id)
                ui.handlers.show_editable(selectedParams, 'runtime_instance', selectedParams, nil, displayType)
            elseif param_type == 'human_action_param' then
                imgui.end_rect(4)
                imgui.unindent(8)
                imgui.spacing()
                state.human_action_param = state.human_action_param or {}
                ui.editor.show_entity_editor(selectedParams, state.human_action_param)
            else
                local displayType = entity_classmap[param_type]
                ui.handlers.show_editable(selectedParams, 'runtime_instance', selectedParams, nil, displayType)
            end
            imgui.end_rect(4)
            imgui.unindent(8)
            imgui.spacing()
        end

        if imgui.tree_node('Full human parameter data') then
            object_explorer:handle_address(CharacterManager:get_HumanParam())
            imgui.tree_pop()
        end
    end)

    editor.add_editor_tab('human_params')
end
