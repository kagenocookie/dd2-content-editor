local core = require('content_editor.core')
local internal = require('content_editor._internal')
local config = internal.config
local udb = require('content_editor.database')
local imgui_wrappers = require('content_editor.ui.imgui_wrappers')

local forbiddenPathChars = '[/:?<>|*\\]'

return function (state)
    local changed

    if imgui.tree_node('New bundle') then
        imgui.begin_rect()
        _, state.newBundleName = imgui.input_text('Name', state.newBundleName)
        state.newBundleName = state.newBundleName:gsub(forbiddenPathChars, '')
        if imgui.button('Create') then
            if state.newBundleName and state.newBundleName:len() >= 3 then
                udb.create_bundle(state.newBundleName)
                udb.set_active_bundle(state.newBundleName)
                state.bundleRename = state.newBundleName
                currentBundle = state.newBundleName
                state.selectedBundle = state.newBundleName
                state.newBundleName = ''
            end
        end
        imgui.indent(12)
        if state.selectedBundle and udb.get_active_bundle_by_name(state.selectedBundle) then
            imgui.same_line()

            if imgui.button('Clone current bundle') then
                if state.newBundleName and state.newBundleName:len() >= 3 then
                    udb.create_bundle(state.newBundleName)
                    for _, e in ipairs(udb.get_bundle_entities(state.selectedBundle)) do
                        udb.add_entity_to_bundle(e, state.newBundleName)
                    end
                    udb.set_active_bundle(state.newBundleName)
                    udb.save_bundle(state.newBundleName)
                    state.bundleRename = state.newBundleName
                    currentBundle = state.newBundleName
                    state.selectedBundle = state.newBundleName
                    state.newBundleName = ''
                end
            end
        end
        imgui.unindent(12)
        imgui.end_rect(2)
        imgui.tree_pop()
    end

    changed, state.selectedBundle = imgui_wrappers.enum_picker('Bundle', state.selectedBundle, udb.bundles_enum)
    if changed then
        state.bundleRename = state.selectedBundle
        config.save()
    end

    local bundle = udb.get_active_bundle_by_name(state.selectedBundle)
    if bundle then
        imgui.indent(4)
        imgui.begin_rect()

        if bundle.dirty then
            if imgui.button('Save') then
                udb.save_bundle(state.selectedBundle)
            end
            imgui.same_line()
            imgui.text_colored('Bundle has unsaved changes', core.get_color('danger'))
        end

        -- name/rename
        if state.bundleRename == nil then state.bundleRename = state.selectedBundle end
        changed, state.bundleRename = imgui.input_text('Bundle name', state.bundleRename)
        if state.bundleRename ~= bundle.info.name then
            if imgui.button('Cancel rename') then
                state.bundleRename = bundle.info.name
            end
            imgui.same_line()
            if imgui.button('Confirm rename') then
                udb.rename_bundle(state.selectedBundle, state.bundleRename)
                if config.data.editor.active_bundle == state.selectedBundle then
                    config.data.editor.active_bundle = state.bundleRename
                    _userdata_DB.editor.active_bundle = state.bundleRename
                    config.save()
                end
                state.selectedBundle = state.bundleRename
            end
        end
        if config.data.editor.active_bundle ~= state.selectedBundle and imgui.button('Make active') then
            _userdata_DB.editor.active_bundle = state.selectedBundle
            config.data.editor.active_bundle = state.selectedBundle
            config.save()
        end

        imgui.text('Author: ' .. bundle.info.author)
        imgui.text('Created: ' .. bundle.info.created_at)
        imgui.text('Last update: ' .. bundle.info.updated_at)
        if imgui.button('Save') then
            udb.save_bundle(bundle.info.name)
        end
        -- maybe implement this one day
        -- if udb.bundle_has_unsaved_changes(bundle.info.name) then
        --     imgui.same_line()
        --     if imgui.button('Revert changes') then
        --     end
        -- end

        imgui.spacing()
        if imgui.tree_node('Insert IDs') then
            local newval
            for t, et in pairs(udb.get_entity_types()) do
                if bundle.initial_insert_ids[t] then
                    changed, newval = imgui.input_text(t, tostring(bundle.initial_insert_ids[t]), 1)
                    if changed then
                        bundle.initial_insert_ids[t] = tonumber(newval)
                        bundle.dirty = true
                    end
                end
            end
            imgui.tree_pop()
        end

        -- entity overview
        imgui.spacing()
        imgui.begin_rect()
        if imgui.tree_node('Entities in bundle:') then
            local entityTypes = udb.get_bundle_entity_types(state.selectedBundle)
            table.insert(entityTypes, 1, 'All')
            _, state.bundleEntityType = imgui.combo('Entity type', state.bundleEntityType, entityTypes)
            if state.bundleEntityType > 0 then
                imgui.spacing()
                imgui.indent(8)
                local entities = state.bundleEntityType == 1 and udb.get_bundle_entities(state.selectedBundle)
                    or udb.get_bundle_entities(state.selectedBundle, entityTypes[state.bundleEntityType])
                for i, entity in ipairs(entities) do
                    imgui.text(entity.type .. ': ' .. entity.label or entity.id)
                    imgui.same_line()
                    imgui.push_id(i)
                    if imgui.button('Delete') then
                        udb.delete_entity(entity, state.selectedBundle)
                    end

                    local entityActiveBundle = udb.get_entity_bundle(entity)
                    if entityActiveBundle and entityActiveBundle ~= state.selectedBundle then
                        imgui.text('Active in bundle: ' .. entityActiveBundle)
                        imgui_wrappers.tooltip("This entity is currently being actively provided by another bundle, meaning this bundle's changes to it are ignored")
                    end
                    imgui.pop_id()
                end
                imgui.unindent(8)
            end
            imgui.tree_pop()
        end
        imgui.end_rect(2)

        imgui.spacing()
        if imgui.tree_node('Delete') then
            imgui.text_colored('This will delete all data in the bundle and is unrecoverable.', core.get_color('error'))
            imgui.text_colored('If you wish to make a backup first, make a copy of the file:', core.get_color('error'))
            imgui.text_colored('GAMEDIR/reframework/data/' .. udb.get_bundle_save_path(state.selectedBundle), core.get_color('error'))
            imgui.tree_pop()
            if imgui.button('Delete please') then
                udb.delete_bundle(state.selectedBundle)
                state.selectedBundle = ''
                config.data.editor.active_bundle = ''
                _userdata_DB.editor.active_bundle = ''
                config.save()
            end
        end

        imgui.end_rect(2)
        imgui.unindent(4)
    end
end