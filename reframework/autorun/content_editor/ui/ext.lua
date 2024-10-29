if type(_userdata_DB) == 'nil' then _userdata_DB = {} end
if _userdata_DB._ui_ext then return _userdata_DB._ui_ext end

local udb = require('content_editor.database')
local editor = require('content_editor.editor')
local ui = require('content_editor.ui.imgui_wrappers')
local config = require('content_editor._internal').config
local presets = require('content_editor.object_presets')
local utils = require('content_editor.utils')

local inputs = {}

---@param obj DBEntity
local function show_save_settings(obj)
    local curBundle = udb.get_entity_bundle(obj)
    local changed, newBundle = ui.enum_picker('Data bundle', curBundle or '', udb.bundles_enum)

    if changed then
        udb.set_entity_bundle(obj, newBundle)
        curBundle = newBundle
    end

    if editor.active_bundle and curBundle ~= editor.active_bundle then
        if editor.active_bundle == '' then
            if imgui.button('Create new bundle') then
                local name = 'New bundle ' .. math.random(10000, 99999)
                udb.create_bundle(name)
                udb.set_active_bundle(name)
            end
            imgui.same_line()
            imgui.text_colored("Any changes must be persisted in a data bundle", editor.get_color('warning'))
        else
            if imgui.button('Move into active bundle') then
                if not udb.get_entity(obj.type, obj.id) then
                    udb.create_entity(obj, editor.active_bundle)
                else
                    udb.set_entity_bundle(obj, editor.active_bundle)
                end
            end
        end
        imgui.same_line()
    end

    if curBundle and curBundle ~= '' then
        if curBundle ~= editor.active_bundle then
            imgui.text_colored("Entity is not a part of the active bundle, changes will be stored into this entity's current bundle.", editor.get_color('warning'))
        end
        if imgui.button('Save') then
            udb.save_bundle(curBundle)
        end
    end

    if udb.entity_has_unsaved_changes(obj) then
        if curBundle and curBundle ~= '' then
            imgui.same_line()
            imgui.text_colored('This object has unsaved changes', editor.get_color('danger'))
            imgui.same_line()
            if imgui.button('Revert unsaved changes') then
                udb.reload_entity(obj.type, obj.id)
            end
        else
            imgui.text_colored('This object has unsaved changes. Please select a bundle to persist changes', editor.get_color('danger'))
        end
    end
    imgui.spacing()
end

---@param obj DBEntity
local function show_entity_label_edit(obj)
    if not inputs[obj] then inputs[obj] = obj.label end
    _, inputs[obj] = imgui.input_text('Label', inputs[obj])
    if inputs[obj] ~= obj.label then
        if imgui.button('Confirm change') then
            obj.label = inputs[obj]
            udb.mark_entity_dirty(obj)
            udb.get_entity_enum(obj.type).set_display_label(obj.id, obj.label)
        end
        imgui.same_line()
        if imgui.button('Revert') then
            inputs[obj] = obj.label
        end
    end
end

---@param obj DBEntity
local function show_entity_metadata(obj)
    show_entity_label_edit(obj)
    show_save_settings(obj)
end

--- @param state EditorState
--- @param storage_key string The key under which to store the new selection ID
--- @param entity DBEntity|integer|nil The entity or its ID to select, or nil to deselect
local function set_selected_entity_picker_entity(state, storage_key, entity)
    local entityId = type(entity) == 'nil' and -1 or type(entity) == 'table' and entity.id or entity
    if state._selected_entity == nil then
        state._selected_entity = { [storage_key] = entityId }
    else
        state._selected_entity[storage_key] = entityId
    end
    config.save()
end

local filters = {}
--- @param type string
--- @param state EditorState
--- @param storage_key string|nil The key under which to store the selected entity, will use the type as key if unset
--- @param label string|nil
--- @param filter nil|fun(entity: DBEntity): boolean
local function entity_picker(type, state, storage_key, label, filter)
    local enum = udb.get_entity_enum(type)
    if not enum then
        imgui.text_colored('Invalid entity type: ' .. tostring(type), editor.get_color('disabled'))
        return nil
    end

    local stateFilters = filters[state]
    if not stateFilters then
        stateFilters = {}
        filters[state] = stateFilters
    end

    storage_key = storage_key or type
    local current_selected_id = state._selected_entity and state._selected_entity[storage_key] or 0
    local changed, newVal
    if filter then
        local values = {}
        local options = {}
        local count = 1
        -- there has to be a better way of keeping the order consistent... surely?
        for _, id in ipairs(enum.values) do
            local val = udb.get_entity(type, id)
            if val ~= nil and filter(val) then
                values[count] = id
                options[count] = enum.get_label(id)
                count = count + 1
            end
        end

        changed, newVal, stateFilters[storage_key] = ui.combo_filterable(label or 'Data entity', current_selected_id, options, stateFilters[storage_key] or '', values)
    else
        changed, newVal, stateFilters[storage_key] = ui.filterable_enum_value_picker(label or 'Data entity', current_selected_id, enum, stateFilters[storage_key] or '')
    end
    if changed then
        set_selected_entity_picker_entity(state, storage_key, udb.get_entity(type, newVal))
    end
    return udb.get_entity(type, newVal)
end

--- @param state EditorState
--- @param type string
--- @param storage_key string|nil The key under which to store the selected entity, will use the type as key if unset
--- @param label string|nil
--- @param disallow_no_preset boolean|nil
local function preset_picker(state, type, storage_key, label, disallow_no_preset)
    local options = presets.get_names(type)
    if not options or #options == 0 then
        imgui.text_colored('No presets defined for type: ' .. tostring(type), editor.get_color('disabled'))
        imgui.spacing()
        return nil
    end

    local stateFilters = filters[state]
    if not stateFilters then
        stateFilters = {}
        filters[state] = stateFilters
    end

    if state._selected_preset == nil then state._selected_preset = {} end

    storage_key = storage_key or type
    local current_selected_preset = state._selected_preset[storage_key] or nil

    if disallow_no_preset then
        if not current_selected_preset then
            current_selected_preset = select(2, next(options))
        end
    else
        table.insert(options, 1, '<default>')
    end

    local changed, newVal
    changed, newVal, stateFilters[storage_key] = ui.combo_filterable(label or 'Preset', current_selected_preset, options, stateFilters[storage_key] or '')
    if changed then
        state._selected_preset[storage_key] = newVal
        config.save()
    end
    imgui.spacing()
    return newVal and presets.get_preset_data(type, newVal) or nil
end

---@param state EditorState
---@param preset_type string
---@param storage_key string|nil The key under which to store the selected entity, will use the type as key if unset
---@param headerLabel string|nil
---@param buttonLabel string|nil
---@param cloneSource DBEntity|nil
---@param disallow_no_preset boolean|nil
---@return boolean create, table|nil preset
local function create_button_with_preset(state, preset_type, storage_key, headerLabel, buttonLabel, cloneSource, disallow_no_preset)
    imgui.indent(12)
    imgui.begin_rect()
    imgui.text(headerLabel or ('New ' .. preset_type))
    imgui.spacing()
    if imgui.calc_item_width() > 300 then
        imgui.set_next_item_width(300)
    end
    local canCreate = editor.active_bundle ~= nil
    local preset = preset_picker(state, preset_type, storage_key, nil, disallow_no_preset)
    local btnPress = canCreate and (preset or not disallow_no_preset) and imgui.button(buttonLabel or 'Create')
    if cloneSource then
        imgui.same_line()
        imgui.text('        ')
        imgui.same_line()
        local clonePress = canCreate and imgui.button('Clone current')
        if clonePress then
            preset = udb.export_entity(cloneSource)
            preset.id = nil
            preset.label = nil
            btnPress = true
        end
    end
    imgui.end_rect(4)
    imgui.unindent(12)
    imgui.spacing()
    imgui.spacing()
    if btnPress then
        if preset then
            return true, utils.table_assign({}, preset) or {}
        else
            return true, nil
        end
    end
    return false, nil
end

local function preset_instantiate(preset, overrideData)
    return utils.table_assign(preset and utils.clone_table(preset) or {}, overrideData)
end

_userdata_DB._ui_ext = {
    show_entity_metadata = show_entity_metadata,
    show_save_settings = show_save_settings,
    entity_picker = entity_picker,
    preset_picker = preset_picker,
    preset_instantiate = preset_instantiate,
    set_selected_entity_picker_entity = set_selected_entity_picker_entity,
    create_button_with_preset = create_button_with_preset,
}

return _userdata_DB._ui_ext
