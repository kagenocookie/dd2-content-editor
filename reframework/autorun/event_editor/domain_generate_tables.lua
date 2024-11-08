local core = require('content_editor.core')
local udb = require('content_editor.database')
local enums = require('content_editor.enums')
local utils = require('content_editor.utils')
local helpers = require('content_editor.helpers')
local import_handlers = require('content_editor.import_handlers')

local GenerateManager = sdk.get_managed_singleton('app.GenerateManager') ---@type app.GenerateManager

--- @class DQGenerateTable : DBEntity
--- @field type 'domain_query_generate_table'
--- @field table app.DomainQueryGenerateTable.DomainQueryGenetateTableElement

--- @class Import.DQGenerateTable : EntityImportData
--- @field table table

udb.events.on('get_existing_data', function ()
    for _, elem in pairs(GenerateManager:get_DomainQueryGenerateTable()._Elements) do
        udb.register_pristine_entity({
            id = elem._RequestID,
            type = 'domain_query_generate_table',
            table = elem,
        })
    end
end)

udb.register_entity_type('domain_query_generate_table', {
    import = function (import_data, instance)
        --- @cast import_data Import.DQGenerateTable
        --- @cast instance DQGenerateTable
        local genTable = GenerateManager:get_DomainQueryGenerateTable()
        local storedInstance = utils.first_where(genTable._Elements, function (value) return value._RequestID == import_data.id end)
        instance = instance or {}

        instance.label = import_data.label
        if storedInstance ~= nil then
            instance.table = storedInstance
        end
        if import_data.table then
            import_data.table._RequestID = import_data.id
            instance.table = import_handlers.import('app.DomainQueryGenerateTable.DomainQueryGenetateTableElement', import_data.table, instance.table)
        end
        if storedInstance == nil and instance.table then
            genTable._Elements = helpers.expand_system_array(genTable._Elements, { instance.table }, 'app.DomainQueryGenerateTable.DomainQueryGenetateTableElement')
        end

        return instance
    end,
    export = function (instance)
        --- @cast instance DQGenerateTable
        --- @type Import.DQGenerateTable
        return {
            id = instance.id,
            table = import_handlers.export(instance.table),
            label = instance.label,
            type = instance.type,
        }
    end,
    delete = function (instance)
        --- @cast instance DQGenerateTable
        local genTable = GenerateManager:get_DomainQueryGenerateTable()
        genTable._Elements = helpers.system_array_remove(genTable._Elements, instance.table, 'app.DomainQueryGenerateTable.DomainQueryGenetateTableElement')
    end,
    generate_label = function (entity)
        --- @cast entity DQGenerateTable
        return 'DomainQueryGenerate ' .. entity.id .. ' - ' .. enums.get_enum('app.DomainQueryGenerateRequestID').get_label(entity.table._RequestID)
    end,
    root_types = {'app.DomainQueryGenerateTable'},
    replaced_enum = 'app.DomainQueryGenerateRequestID',
    insert_id_range = {1000, 99999},
})

if core.editor_enabled then
    local ui = require('content_editor.ui')
    local editor = require('content_editor.editor')

    editor.define_window('dq_generate_tables', 'Spawn tables', function (state)
        local activeBundle = editor.active_bundle
        if activeBundle then
            if imgui.button('New table') then
                local tbl = udb.insert_new_entity('domain_query_generate_table', activeBundle, {
                    table = {
                        _DomainQueryAsset = 'LevelDesign/Generate/DomainQueryGenerate/DomainQuery/SuddenQuest.user',
                    }
                })
                if tbl then
                    ui.editor.set_selected_entity_picker_entity(state, 'domain_query_generate_table', tbl)
                end
            end
        end

        local selectedTable = ui.editor.entity_picker('domain_query_generate_table', state)
        if selectedTable then
            --- @cast selectedTable DQGenerateTable
            imgui.spacing()
            imgui.indent(8)
            imgui.begin_rect()
            ui.editor.show_entity_metadata(selectedTable)
            ui.handlers.show(selectedTable.table, selectedTable, 'Table Data')
            imgui.end_rect(4)
            imgui.unindent(8)
        end
    end)

    editor.add_editor_tab('dq_generate_tables')
end