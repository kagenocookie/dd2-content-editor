local core = require('content_editor.core')
local udb = require('content_editor.database')
local import = require('content_editor.import_handlers')
local enums = require('content_editor.enums')
local utils = require('content_editor.utils')

--- @class EnemyDataEntity : DBEntity
--- @field params table
--- @field position Vector3f
--- @field runtime_instance app.gm80_001|nil

local CharacterID = enums.get_enum('app.CharacterID')

---@param entity EnemyDataEntity
---@param instance REManagedObject
local function update_enemy_data(entity, instance)
    -- TODO import modifications
    -- import.import('app.Ch200000Parameter', entity.params, entity.runtime_instance:get_GimmickParam())
end

---@param entity EnemyDataEntity
local function update_all_enemy_data(entity)
    local idStr = CharacterID.valueToLabel[entity.id]
    local enemyInstances = ce_find(idStr .. ':app.Monster')
    for _, instance in ipairs(enemyInstances or {}) do
        update_enemy_data(entity, instance)
    end
end


udb.register_entity_type('enemy_data', {
    export = function (entity)
        --- @cast entity EnemyDataEntity
        return { params = entity.params }
    end,
    import = function (import_data, entity)
        --- @cast entity EnemyDataEntity
        entity.params = import_data.params
    end,
    insert_id_range = {0, 0},
    delete = function (entity)
        return 'forget'
    end,
    generate_label = function (entity)
        --- @cast entity EnemyDataEntity
        -- runtime_instance
        return 'Enemy ' .. CharacterID.get_label(entity.id)
    end,
    root_types = {'app.Ch200000Parameter'},
})

local settings = {
    load_unknown_entities = false,
}

--- @param monster app.Monster
local function create_enemy_entity_if_unregistered(monster)
    local charaId = monster._Chara:get_CharaID()
    local entity = udb.get_entity('enemy_data', charaId)--[[@as EnemyDataEntity|nil]]
    if entity ~= nil then
        update_enemy_data(entity, monster)
    elseif core.editor_enabled and settings.load_unknown_entities then
        print('storing new enemy data', monster._Chara:get_CharaIDString())
        local ch2 = monster._Ch200000
        local params = ch2.Ch200000Parameter
        local statusHolder = ch2._StatusHolder
        udb.register_pristine_entity({
            id = charaId,
            type = 'enemy_data',
            params = import.export(params, 'app.Ch200000Parameter', { raw = true }),
            statusHolder = import.export(statusHolder, 'app.CharacterStatusHolder', { raw = true }),
            aiDecisionMaker = import.export(ch2._AIDecisionMaker, 'app.AIDecisionMaker', { raw = true }),
        })
    end
end

sdk.hook(
    sdk.find_type_definition('app.Monster'):get_method('start'),
    function (args)
        local monster = sdk.to_managed_object(args[2])--[[@as app.Monster]]
        create_enemy_entity_if_unregistered(monster)
    end
)

if core.editor_enabled then
    local ui = require('content_editor.ui')
    local editor = require('content_editor.editor')

    settings = editor.persistent_storage.get('enemies', settings)

    usercontent.definitions.override('', {
        ['app.IntermediateRegionParam'] = {
            fields = {
                _Attr = {
                    uiHandler = ui.handlers.common.enum_flags(enums.get_enum('app.IntermediateRegionParam.AttributeFlags'))
                }
            }
        },
        ['app.HitController.RegionStatus'] = {
            fields = {
                Attribute = {
                    uiHandler = ui.handlers.common.enum_flags(enums.get_enum('app.HitController.RegionStatus.AttrFlags'))
                }
            }
        },
        ['app.DefaultCharacterStatusParameter'] = {
            fields = {
                _WeakPointSettings = {
                    uiHandler = ui.handlers.common.enum_flags()
                },
                _ResistSettings = {
                    uiHandler = ui.handlers.common.enum_flags()
                },
            }
        },
    })

    ui.editor.set_entity_editor('enemy_data', function (entity, state)
        --- @cast entity EnemyDataEntity
        local changed
        changed = ui.handlers.show_editable(entity, 'params', entity, 'Params', 'app.Ch200000Parameter', state) or changed
        changed = ui.handlers.show_editable(entity, 'statusHolder', entity, 'Status Holder', 'app.CharacterStatusHolder', state) or changed
        changed = ui.handlers.show_editable(entity, 'aiDecisionMaker', entity, 'AI Decision Maker', 'app.AIDecisionMaker', state) or changed
        return changed
    end)

    editor.define_window('enemy_data', 'Enemies', function (state)
        ui.basic.setting_checkbox('Load unknown entities', settings, 'load_unknown_entities', editor.persistent_storage.save,
            'All enemies will be saved into the content editor database for editing purposes when they load.\nHaving this enabled may affect performance when enemies are spawned, best only enabled when you actually need it.')

        if imgui.button('Find all currently active enemies') then
            for _, m in ipairs(ce_find(':app.Monster') or {}) do
                create_enemy_entity_if_unregistered(m)
            end
        end

        local chest = ui.editor.entity_picker('enemy_data', state)
        if chest then
            ui.editor.show_entity_editor(chest, state)
        end
    end)
    editor.add_editor_tab('enemy_data')
end
