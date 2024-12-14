local core = require('content_editor.core')
require('editors.items.armor_catalogs')
require('editors.items.weapons')
require('editors.items.styles')
require('editors.items.item_data')
require('editors.items.item_combinations')

if core.editor_enabled then
    local ui = require('content_editor.ui')
    local editor = require('content_editor.editor')

    editor.define_window('items', 'Items', function (state)
        state.subtab = select(2, ui.basic.tabs({'Item data', 'Styles', 'Armor catalogs', 'Weapon catalogs', 'Item combinations'}, state.subtab))
        if state.subtab == 1 then
            state.item_data = state.item_data or {}
            editor.embed_window('item_data', 1, state.item_data)
        elseif state.subtab == 2 then
            state.styles = state.styles or {}
            editor.embed_window('styles', 2, state.styles)
        elseif state.subtab == 3 then
            state.armor_catalogs = state.armor_catalogs or {}
            editor.embed_window('armor_catalogs', 3, state.armor_catalogs)
        elseif state.subtab == 4 then
            state.weapons = state.weapons or {}
            editor.embed_window('weapons', 4, state.weapons)
        elseif state.subtab == 5 then
            state.item_combination = state.item_combination or {}
            editor.embed_window('item_combinations', 5, state.item_combination)
        end
    end)

    editor.add_editor_tab('items')
end