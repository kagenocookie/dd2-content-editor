local core = require('content_editor.core')
local udb = require('content_editor.database')
local import = require('content_editor.import_handlers')

--- @class ChestEntity : DBEntity
--- @field params table
--- @field position Vector3f
--- @field runtime_instance app.gm80_001|nil

---@param entity ChestEntity
local function update_chest_data(entity)
    if not entity.runtime_instance then return end
    import.import('app.Gm80_001Param', entity.params, entity.runtime_instance:get_GimmickParam())
end

udb.register_entity_type('chest', {
    export = function (entity)
        --- @cast entity ChestEntity
        -- TODO: manually assign position fields?
        return { params = entity.params, position = entity.position }
    end,
    import = function (import_data, entity)
        --- @cast entity ChestEntity
        entity.position = Vector3f.new(import_data.position.x, import_data.position.y, import_data.position.z)
        entity.params = import_data.params
        if entity.runtime_instance then
            update_chest_data(entity)
        end
    end,
    insert_id_range = {0, 0},
    delete = function (entity)
        return 'forget'
    end,
    generate_label = function (entity)
        --- @cast entity ChestEntity
        -- runtime_instance
        return entity.id .. ' Chest (' .. entity.position.x .. ', ' .. entity.position.y .. ', ' .. entity.position.z .. ')'
    end,
    root_types = {'app.gm80_001'},
})

local settings = {
    load_unknown_chests = false,
}

sdk.hook(
    sdk.find_type_definition('app.gm80_001'):get_method('start'),
    function (args)
        local this = sdk.to_managed_object(args[2])--[[@as app.gm80_001]]
        gm80 = this
        local id = this.GimmickParamId
        -- print('chest start()', id, 'param', this:get_GimmickParam())
        local entity = udb.get_entity('chest', id)
        --- @cast entity ChestEntity|nil
        if entity ~= nil then
            entity.runtime_instance = this
            import.import('app.Gm80_001Param', entity.params, this:get_GimmickParam())
        elseif core.editor_enabled and settings.load_unknown_chests then
            -- print('Found new chest', id)
            local pos = this:get_Trans():get_UniversalPosition()
            udb.register_pristine_entity({
                id = id,
                type = 'chest',
                runtime_instance = this,
                position = Vector3f.new(pos.x, pos.y, pos.z),
                params = import.export(this:get_GimmickParam(), 'app.Gm80_001Param'),
            })
        end
    end
)

if core.editor_enabled then
    local ui = require('content_editor.ui')
    local editor = require('content_editor.editor')
    local utils = require('content_editor.utils')
    local devtools = require('devtools')

    settings = editor.persistent_storage.get('chests', settings)

    usercontent.definitions.override('', {
        ['app.gm80_001.ItemParam'] = {
            fields = {
                ItemId = { uiHandler = ui.handlers.common.enum('app.ItemIDEnum') }
            }
        },
        ['app.Gm80_001Param.ItemParam'] = {
            fields = {
                ItemId = { uiHandler = ui.handlers.common.enum('app.ItemIDEnum') }
            }
        }
    })

    ui.editor.set_entity_editor('chest', function (entity, state)
        --- @cast entity ChestEntity
        local changed
        if imgui.button('Warp to chest') then
            devtools.warp_player(Vector3f.new(entity.position.x, entity.position.y + 2, entity.position.z))
        end
        changed = ui.handlers.show_editable(entity, 'params', entity, 'Params', 'app.Gm80_001Param', state)
        if changed and entity.runtime_instance then
            print('updating chest data')
            update_chest_data(entity)
        end
        if entity.runtime_instance then
            ui.handlers.show_readonly(entity.runtime_instance, entity, 'Runtime instance', nil, state)
        end
        return changed
    end)

    editor.define_window('chest', 'Chests', function (state)
        ui.basic.setting_checkbox('Load unknown chests', settings, 'load_unknown_chests', editor.persistent_storage.save,
            'All chests will be saved into the content editor database for editing purposes on load.\nHaving this enabled may affect performance and memory usage when entering new areas, best only enabled when you actually need it.')

        local chest = ui.editor.entity_picker('chest', state)
        if chest then
            ui.editor.show_entity_editor(chest, state)
        end
    end)
    editor.add_editor_tab('chest')
end
