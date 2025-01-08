local core = require('content_editor.core')
local udb = require('content_editor.database')
local utils = require('content_editor.utils')
local import_handlers = require('content_editor.import_handlers')

--- @param entityType string
--- @param rootClassname string
--- @param fetchBaseEntity fun(): REManagedObject
local function setup_per_field_entity(entityType, rootClassname, fetchBaseEntity)
    local root_entity_id = 4201337
    local root_entity_fieldname = '__root'

    udb.register_entity_type(entityType, {
        export = function (entity)
            if entity.id == root_entity_id then
                local fields = utils.map(entity.values, function (field)
                    return {
                        ['$type'] = field['$type'],
                        field = field.field,
                        value = import_handlers.export(entity.runtime_instance[field.field], field['$type'], { raw = true })
                    }
                end)
                return { fields = fields }
            else
                return { data = import_handlers.export(entity.runtime_instance, nil, { raw = true }), field = entity.field }
            end
        end,
        import = function (data, entity)
            if entity.id == root_entity_id then
                entity.values = utils.map(data.fields, function (value)
                    local val = import_handlers.import(value['$type'], value.value, entity.runtime_instance[value.field])
                    entity.runtime_instance[value.field] = val
                    return {
                        ['$type'] = value['$type'],
                        field = value.field,
                        value = val
                    }
                end)
            else
                entity.field = data.field
                local type = sdk.find_type_definition(rootClassname):get_field(data.field):get_type():get_full_name()
                entity.runtime_instance = import_handlers.import(type, data.data, entity.runtime_instance)
            end
        end,
        root_types = {rootClassname},
        insert_id_range = {0,0}
    })

    udb.events.on('get_existing_data', function (whitelist)
        if not whitelist or whitelist[entityType] then
            local instance = fetchBaseEntity()

            local fields = instance:get_type_definition():get_fields()
            local rootFields = {}
            for _, field in ipairs(fields) do
                local name = field:get_name()
                if field:get_type():is_value_type() then
                    rootFields[#rootFields+1] = { field = name, ['$type'] = field:get_type():get_full_name(), value = instance[name] }
                else
                    local id = utils.string_hash(name)
                    if not whitelist or whitelist[entityType][id] then
                        local cleanName = name:gsub('^_', '')
                        local typename = field:get_type():get_name()
                        udb.register_pristine_entity({
                            id = id,
                            type = entityType,
                            label = cleanName == typename and typename or (typename .. ' ( ' .. cleanName .. ')'),
                            field = name,
                            runtime_instance = instance[name]
                        })
                    end
                end
            end

            if #rootFields > 0 and (not whitelist or whitelist[entityType][root_entity_id]) then
                udb.register_pristine_entity({
                    id = root_entity_id,
                    type = entityType,
                    label = 'Base data',
                    field = root_entity_fieldname,
                    values = rootFields,
                    runtime_instance = instance,
                })
            end
        end
    end)

    if core.editor_enabled then
        local ui = require('content_editor.ui')

        ui.editor.set_entity_editor(entityType, function (entity, state)
            if entity.id == root_entity_id then
                local changed = false
                local ui_ctx = ui.context.get_or_create_child(nil, '_', entity.runtime_instance, '', nil, 'app.HumanActionParameter')
                for _, field in ipairs(entity.values) do
                    changed = ui.handlers._internal.create_field_editor(ui_ctx, 'app.HumanActionParameter', field.field, field['$type'], field.field, nil, {}, true):ui() or changed
                end
                return changed
            else
                return ui.handlers.show(entity.runtime_instance, entity, nil, nil, state)
            end
        end)
    end
end

return {
    create = setup_per_field_entity,
}