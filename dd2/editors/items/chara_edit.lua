local core = require('content_editor.core')
local udb = require('content_editor.database')
local utils = require('content_editor.utils')
local import_handlers = require('content_editor.import_handlers')

--- @class CharaPresetLimit : DBEntity
--- @field humanFemale boolean
--- @field humanMale boolean
--- @field beastFemale boolean
--- @field beastMale boolean

local presetData = {
    { name = 'Hair', entityType = 'charaedit_limit_hair', field = '_HairLimitDB', enum = 'app.HairStyle' },
}

local genders = {
    Female = 1910070090,
    Female_str = '1910070090',
    Male = 2776536455,
    Male_str = '2776536455',
}

local species = {
    Human = 2501532887,
    Beastren = 3666037007,
}

local editCtrl = nil ---@type app.HumanEditController|nil
local function getEditCtrl()
    if editCtrl and editCtrl:get_Valid() then return editCtrl end

    editCtrl = ce_find(':app.HumanEditController', true)
    if not editCtrl then return nil end
end

local hasData = false
local function fetchEditData()
    if hasData then return end
    local ctrl = getEditCtrl()
    if not ctrl then return false end

    hasData = true
    for _, info in ipairs(presetData) do
        local name = info.name
        for styleLimits in utils.enumerate(ctrl._HairLimitDB) do
            local styleId = styleLimits.key
            local limitData = styleLimits.value
            local entityData = { ---@type CharaPresetLimit
                type = info.entityType,
                id = styleId,
                humanFemale = false,
                humanMale = false,
                beastFemale = false,
                beastMale = false,
            }
            if limitData:ContainsKey(species.Human) then
                entityData.humanFemale = limitData[species.Human]:ContainsKey(genders.Female)
                entityData.humanMale = limitData[species.Human]:ContainsKey(genders.Male)
            end
            if limitData:ContainsKey(species.Beastren) then
                entityData.beastFemale = limitData[species.Beastren]:ContainsKey(genders.Female)
                entityData.beastMale = limitData[species.Beastren]:ContainsKey(genders.Male)
            end

            udb.register_pristine_entity(entityData)
        end

    end

    return true
end

sdk.hook(
    sdk.find_type_definition('app.HumanEditController'):get_method('setup'),
    function (args)
        thread.get_hook_storage().this = sdk.to_managed_object(args[2])
    end,
    function (ret)
        local this = thread.get_hook_storage().this ---@type app.HumanEditController
        editCtrl = this
        fetchEditData()

        return ret
    end
)

--- comment
--- @param info { name: string, entityType: string, field: string, enum: string }
--- @param list CharaPresetLimit[]
local function injectData(info, list)
end

udb.events.on('entities_created', function (entities)
    if not getEditCtrl() then return end

    for _, info in ipairs(presetData) do
        if entities[info.entityType] then
            local entlist = entities[info.entityType]
            injectData(info, entlist)
        end
    end
end)

for _, info in ipairs(presetData) do
    udb.register_entity_type(info.entityType, {
        export = function (entity)
            --- @cast entity CharaPresetLimit
            return {
                humanFemale = entity.humanFemale,
                humanMale = entity.humanMale,
                beastFemale = entity.beastFemale,
                beastMale = entity.beastMale,
            }
        end,
        import = function (import, entity)
            entity.humanFemale = import.humanFemale
            entity.humanMale = import.humanMale
            entity.beastFemale = import.beastFemale
            entity.beastMale = import.beastMale
        end,
        insert_id_range = {0, 0},
        delete = function (entity)
            return 'not_deletable'
        end,
        generate_label = function (entity)
            --- @cast entity CharaPresetLimit
            return 'Character edit setting ' .. entity.id
        end,
        root_types = {'app.HumanEditController'},
    })
end

if core.editor_enabled then
    local ui = require('content_editor.ui')
    local editor = require('content_editor.editor')

    usercontent.definitions.override('', {
    })

    ui.editor.set_entity_editor('chara_edit', function (entity, state)
        --- @cast entity CharaPresetLimit
        local changed
        -- changed = ui.handlers.show(entity.data, entity, nil, '_main_classname_', state)
        return changed
    end)

    editor.define_window('chara_edit', 'Character edit settings', function (state)
        local selected = ui.editor.entity_picker('chara_edit', state)
        if selected then
            ui.editor.show_entity_editor(selected, state)
        end
    end)
    editor.add_editor_tab('chara_edit')
end
