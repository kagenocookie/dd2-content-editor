if type(usercontent) == 'nil' then usercontent = {} end
if usercontent._ui_ext then return usercontent._ui_ext end

local udb = require('content_editor.database')
local editor = require('content_editor.editor')
local ui = require('content_editor.ui.imgui_wrappers')
local config = require('content_editor._internal').config
local utils = require('content_editor.utils')

local inputs = {}

--- @type table<string, fun(entity: DBEntity, state: table): changed: boolean>
local entity_editors = {}

local tempNewBundle = ''
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
            imgui.same_line()
            if imgui.tree_node('Create new bundle') then
                tempNewBundle = select(2, imgui.input_text('Name', tempNewBundle))
                if tempNewBundle and tempNewBundle ~= '' then
                    if imgui.button('Create & save') then
                        local newB = udb.create_bundle(tempNewBundle)
                        if newB then
                            udb.set_entity_bundle(obj, newB.info.name)
                            udb.set_active_bundle(newB.info.name)
                            udb.save_bundle(newB.info.name)
                            tempNewBundle = ''
                        end
                    end
                end
                imgui.tree_pop()
            end
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
--- @param storage_key string|integer The key under which to store the new selection ID
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
--- @param storage_key string|integer|nil The key under which to store the selected entity, will use the type as key if unset
--- @param label string|nil
--- @param filter nil|fun(entity: DBEntity): boolean
--- @return DBEntity|nil selected, boolean changed
local function entity_picker(type, state, storage_key, label, filter)
    local enum = udb.get_entity_enum(type)
    if not enum then
        imgui.text_colored('Invalid entity type: ' .. tostring(type), editor.get_color('disabled'))
        return nil, false
    end

    local stateFilters = filters[state]
    if not stateFilters then
        stateFilters = {}
        filters[state] = stateFilters
    end

    storage_key = storage_key or type
    local current_selected_id = state._selected_entity and state._selected_entity[storage_key] or 0
    local activeEntityOnly = state._active_only and state._active_only[storage_key]
    local changed, newVal
    if activeEntityOnly then
        if filter then
            local org_filter = filter
            filter = (function (entity) return udb.get_entity_bundle(entity) == editor.active_bundle and org_filter(entity) end)
        else
            filter = function (entity) return udb.get_entity_bundle(entity) == editor.active_bundle end
        end
    end
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
    local activeChanged, newActive = imgui.checkbox('Only from active bundle', activeEntityOnly)
    if activeChanged then
        if newActive then
            state._active_only = state._active_only or {}
            state._active_only[storage_key] = true
        else
            state._active_only[storage_key] = nil
        end
    end
    if changed then
        set_selected_entity_picker_entity(state, storage_key, udb.get_entity(type, newVal))
    end
    return udb.get_entity(type, newVal), changed
end

--- @param state EditorState
--- @param type string
--- @param storage_key string|nil The key under which to store the selected entity, will use the type as key if unset
--- @param label string|nil
--- @param disallow_no_preset boolean|nil
--- @return table|nil selectedPreset
local function preset_picker(state, type, storage_key, label, disallow_no_preset)
    local options = editor.presets.get_names(type)
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

    if imgui.calc_item_width() > 300 then imgui.set_next_item_width(300) end

    local changed, newVal
    changed, newVal, stateFilters[storage_key] = ui.combo_filterable(label or 'Preset', current_selected_preset, options, stateFilters[storage_key] or '')
    if changed then
        state._selected_preset[storage_key] = newVal
        config.save()
    end
    return newVal and editor.presets.get_preset_data(type, newVal) or nil
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
    local canCreate = editor.active_bundle ~= nil
    local preset = preset_picker(state, preset_type, storage_key, nil, disallow_no_preset)
    imgui.spacing()
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

--- Clone a preset and apply some override values to it
--- @param preset table|nil
--- @param overrideData table
--- @return table
local function preset_instantiate(preset, overrideData)
    return utils.table_assign(preset and utils.clone_table(preset) or {}, overrideData)
end

--- @param type string
--- @param func fun(entity: DBEntity, state: table): changed: boolean
local function set_entity_editor(type, func)
    entity_editors[type] = func
end

--- @param entity DBEntity
--- @param state table
--- @param expandTreeLabel string|nil Label to display for a tree view. Will be shown plainly without a tree if nil.
--- @param noMetadata boolean|nil Whether to also show the entity's metadata (save/bundle settings); default false
--- @return boolean changed
local function show_entity_editor(entity, state, expandTreeLabel, noMetadata)
    local editorFunc = entity_editors[entity.type]
    if not editorFunc then
        imgui.text_colored('No editor defined for entity type ' .. entity.type, editor.get_color('warning'))
        return false
    end

    if expandTreeLabel then
        if not imgui.tree_node(expandTreeLabel) then return false end
    else
        imgui.push_id(entity.type .. entity.id)
    end

    if not noMetadata then
        show_entity_metadata(entity)
    end
    local success, changed
    if config.data.editor.devmode then
        success, changed = true, editorFunc(entity, state)
    else
        success, changed = pcall(editorFunc, entity, state)
    end

    if expandTreeLabel then
        imgui.tree_pop()
    else
        imgui.pop_id()
    end

    if success then
        if changed then udb.mark_entity_dirty(entity) end
        return changed
    else
        imgui.text_colored('ERROR: ' .. tostring(changed), editor.get_color('error'))
        print('Entity '..entity.type..' editor error: ' .. tostring(changed))
        return false
    end
end

--- @param entityType string
--- @return fun(entity: DBEntity, state: table):(changed: boolean)
local function get_entity_editor_func(entityType)
    return entity_editors[entityType]
end

--- @param container table The object that should contain the ID of the referenced entity
--- @param idField string|integer
--- @param linkedEntityType string
--- @param state table
--- @param label string|nil
--- @return boolean changed
local function show_linked_entity_picker(container, idField, linkedEntityType, state, label)
    local initialSelected = container[idField] and udb.get_entity(linkedEntityType, container[idField]) or nil
    if initialSelected then
        usercontent.ui.editor.set_selected_entity_picker_entity(state, idField, initialSelected)
    end
    local selectedEntity, changed = usercontent.ui.editor.entity_picker(linkedEntityType, state, idField, label)
    if changed then
        container[idField] = selectedEntity and selectedEntity.id or nil
    end

    changed = changed or initialSelected ~= selectedEntity

    if selectedEntity then
        return show_entity_editor(selectedEntity, state, label) or changed
    end
    return changed
end

--- @param entity DBEntity
--- @param list_property string
--- @param linked_type string
--- @param label string
--- @param stateContainer table
local function show_linked_entity_list(entity, list_container, list_property, linked_type, label, stateContainer)
    local changed = false
    local list = list_container[list_property] ---@type integer[]|nil
    if imgui.tree_node(label) then
        if list then
            local state = stateContainer[entity] or usercontent.ui.context.create_root(entity, nil, label, label .. entity.type .. entity.id)
            stateContainer[entity] = state

            for linkedIndex, linkedId in ipairs(list) do
                imgui.push_id(linkedIndex)
                state[linkedIndex] = state[linkedIndex] or {}
                if imgui.button('X') then
                    table.remove(list, linkedIndex)
                    imgui.pop_id()
                    changed = true
                    break
                end
                imgui.same_line()
                local linked = udb.get_entity(linked_type, linkedId)--[[@as ScriptEffectEntity|nil]]
                if linked then
                    if imgui.tree_node(linkedIndex .. '. ' .. linked.label) then
                        changed = usercontent.ui.editor.show_linked_entity_picker(list, linkedIndex, linked_type, state) or changed
                        imgui.tree_pop()
                    end
                else
                    changed = usercontent.ui.editor.show_linked_entity_picker(list, linkedIndex, linked_type, state) or changed
                end
                imgui.pop_id()
            end
        end
        if imgui.button('Add') then
            list_container[list_property] = list_container[list_property] or {}
            list_container[list_property][#list_container[list_property]+1] = 0
            changed = true
        end
        imgui.tree_pop()
    else
        stateContainer[entity] = nil
    end
    if changed then udb.mark_entity_dirty(entity) end
    return changed
end

usercontent._ui_ext = {
    show_entity_metadata = show_entity_metadata,
    show_save_settings = show_save_settings,
    entity_picker = entity_picker,
    preset_picker = preset_picker,
    preset_instantiate = preset_instantiate,
    set_selected_entity_picker_entity = set_selected_entity_picker_entity,
    create_button_with_preset = create_button_with_preset,

    set_entity_editor = set_entity_editor,
    show_entity_editor = show_entity_editor,
    get_entity_editor_func = get_entity_editor_func,
    show_linked_entity_picker = show_linked_entity_picker,
    show_linked_entity_list = show_linked_entity_list,
}

return usercontent._ui_ext
