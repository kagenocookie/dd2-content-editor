local udb = require('content_editor.database')
local ui = require('content_editor.ui')
local editor = require('content_editor.editor')
local main = require('content_editor.script_effects.effects_main')

--- @type table<string, fun(entity: ScriptEffectEntity, state: table)>
local ui_hooks = {}

--- @param type string
--- @param func fun(entity: ScriptEffectEntity, state: table): boolean changed
local function set_ui_hook(type, func)
    ui_hooks[type] = func
end

local states = {}

ui.editor.set_entity_editor('script_effect', function (effect, state)
    --- @cast effect ScriptEffectEntity
    local changed = false

    local eventTypes = main.get_event_types()
    local typeChanged, newType
    typeChanged, newType, state.type_filter = ui.core.combo_filterable('Event type', effect.trigger_type, eventTypes, state.type_filter or '')
    if typeChanged then
        effect.trigger_type = newType
        effect.data = {}
        state.children = {}
        changed = true
    end

    local hook_callback = ui_hooks[effect.trigger_type]
    if not hook_callback then
        imgui.text('Script effect has no UI')
    else
        state.children = state.children or {}
        state.children[effect.id] = state.children[effect.id] or {}
        local triggerState = state.children[effect.id]
        changed = hook_callback(effect, triggerState) or changed
        if changed then udb.mark_entity_dirty(effect) end
    end
    return changed
end)

--- @param entity DBEntity
--- @param list_property string
--- @param label string
local function show_list(entity, list_property, label)
    return ui.editor.show_linked_entity_list(entity, entity, list_property, 'script_effect', label, states)
end

editor.define_window('script_effects', 'Script Effects', function (state)
    if editor.active_bundle and imgui.button('Create new') then
        local newScript = udb.insert_new_entity('script_effect', editor.active_bundle, { trigger_type = 'script' })
        ui.editor.set_selected_entity_picker_entity(state, 'script_effect', newScript)
    end

    local selectedItem = ui.editor.entity_picker('script_effect', state)
    if selectedItem then
        imgui.spacing()
        imgui.indent(8)
        imgui.begin_rect()
        ui.editor.show_entity_editor(selectedItem, state)
        imgui.end_rect(4)
        imgui.unindent(8)
        imgui.spacing()
    end
end)

editor.add_editor_tab('script_effects')

set_ui_hook('script', function (effect, state)
    local changed = false

    if imgui.button('New start script') then
        effect.data.start_script_id = udb.insert_new_entity('custom_script', editor.active_bundle).id
        changed = true
    end

    imgui.same_line()
    if imgui.button('New stop script') then
        effect.data.stop_script_id = udb.insert_new_entity('custom_script', editor.active_bundle).id
        changed = true
    end

    changed = ui.editor.show_linked_entity_picker(effect.data, 'start_script_id', 'custom_script', state, 'Start script') or changed
    changed = ui.editor.show_linked_entity_picker(effect.data, 'stop_script_id', 'custom_script', state, 'Stop script') or changed

    return changed
end)

return {
    show_list = show_list,
    set_ui_hook = set_ui_hook,
}
