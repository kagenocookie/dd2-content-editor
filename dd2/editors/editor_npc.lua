local core = require('content_editor.core')
local udb = require('content_editor.database')
local enums = require('content_editor.enums')
local utils = require('content_editor.utils')
local import_handlers = require('content_editor.import_handlers')

local CharacterID = enums.get_enum('app.CharacterID', false)

udb.events.on('get_existing_data', function (whitelist)
    local NPCManager = sdk.get_managed_singleton('app.NPCManager') ---@type app.NPCManager

    if not whitelist or whitelist.npc_data then
        for _, charaData in pairs(NPCManager.CharacterDataList.characterDataList) do
            if charaData and (not whitelist or whitelist.npc_data[charaData.ID]) then
                local id = charaData.ID
                if charaData._SubNPC then
                    local mainNpc = udb.get_entity('npc_data', id)
                    if not udb.get_entity('npc_data', id) then
                        print('WARNING: Main and sub NPC are out of order', id, CharacterID.get_label(id))
                    else
                        mainNpc.sub_instance = charaData
                    end
                else
                    udb.register_pristine_entity({
                        id = id,
                        type = 'npc_data',
                        runtime_instance = charaData,
                    })
                end
            end
        end
    end

    if not whitelist or whitelist.npc_config then
        local config = NPCManager:get_NPCConfig()
        local fields = config:get_type_definition():get_fields()
        for _, field in ipairs(fields) do
            local name = field:get_name()
            local id = utils.string_hash(name)
            if not whitelist or whitelist.npc_config[id] then
                local cleanName = name:gsub('^_', '')
                local typename = field:get_type():get_name()
                udb.register_pristine_entity({
                    id = id,
                    type = 'npc_config',
                    label = cleanName == typename and typename or (typename .. ' ( ' .. cleanName .. ')'),
                    field = name,
                    runtime_instance = config[name]
                })
            end
        end

        if core.editor_enabled then
            udb.get_entity_enum('npc_data').orderByValue = false
            udb.get_entity_enum('npc_data').resort()
        end
    end

    if not whitelist or whitelist.npc_appearance then
        local CharacterEditManager = sdk.get_managed_singleton('app.CharacterEditManager')---@type app.CharacterEditManager
        for pair in utils.enumerate(CharacterEditManager._AppearanceDB) do
            local id = pair.key
            if not whitelist or whitelist[id] then
                local appearanceDict = pair.value
                local e = udb.get_entity('npc_appearance', id)
                if e then
                    e.appearances = appearanceDict
                else
                    udb.register_pristine_entity({
                        id = id,
                        type = 'npc_appearance',
                        appearances = appearanceDict,
                    })
                end
            end
        end

        for pair in utils.enumerate(CharacterEditManager._CostumeDB) do
            local id = pair.key
            if not whitelist or whitelist[id] then
                local costumeDict = pair.value
                local e = udb.get_entity('npc_appearance', id)
                if e then
                    e.costumes = costumeDict
                else
                    udb.register_pristine_entity({
                        id = id,
                        type = 'npc_appearance',
                        costumes = costumeDict,
                    })
                end
            end
        end
    end
end)

udb.register_entity_type('npc_config', {
    export = function (entity)
        return { data = import_handlers.export(entity.runtime_instance, nil, { raw = true }), field = entity.field }
    end,
    import = function (data, entity)
        entity.field = data.field
        local type = sdk.find_type_definition('app.NPCData'):get_field(data.field):get_type():get_full_name()
        entity.runtime_instance = import_handlers.import(type, data.data, entity.runtime_instance)
    end,
    root_types = {'app.NPCData'},
    insert_id_range = {0,0}
})

udb.register_entity_type('npc_data', {
    export = function (entity)
        return { data = import_handlers.export(entity.runtime_instance, 'app.CharacterData') }
    end,
    import = function (data, entity)
        entity.runtime_instance = import_handlers.import('app.CharacterData', data.data, entity.runtime_instance)
    end,
    root_types = {'app.CharacterData'},
    generate_label = function (entity)
        if entity.runtime_instance._SubNPC then
            idstr = (CharacterID.valueToLabel[entity.id - 1] or 'chUnknown') .. ' SUB'
        else
            idstr = CharacterID.valueToLabel[entity.id] or 'chUnknown'
        end
        local name = entity.runtime_instance:get_Name()
        return idstr .. ' : ' .. name .. ' (' .. entity.id .. ')'
    end,
    insert_id_range = {0,0}
})

udb.register_entity_type('npc_appearance', {
    export = function (entity)
        return { appearances = import_handlers.export(entity.appearances), costumes = import_handlers.export(entity.costumes) }
    end,
    import = function (data, entity)
        entity.appearances = import_handlers.import('System.Collections.Generic.Dictionary`2<System.Byte,app.charaedit.ch000.AppearanceData>', data.appearances, entity.appearances)
        entity.costumes = import_handlers.import('System.Collections.Generic.Dictionary`2<System.Byte,app.charaedit.ch000.CostumeData>', data.costumes, entity.costumes)
    end,
    root_types = {'app.charaedit.ch000.AppearanceData', 'app.charaedit.ch000.CostumeData'},
    generate_label = function (entity)
        local idstr = CharacterID.valueToLabel[entity.id] or 'chUnknown'
        local name = utils.dd2.translate_character_name(entity.id)
        return idstr .. ' : ' .. name .. ' (' .. entity.id .. ')'
    end,
    insert_id_range = {0,0}
})

-- udb.register_entity_type('npc_extra_data', {
--     export = function (entity)
--         return { data = import_handlers.export(entity.runtime_instance, 'app.NPCManager.CharacterDataEx') }
--     end,
--     import = function (data, entity)
--         entity.runtime_instance = import_handlers.import('app.NPCManager.CharacterDataEx', data.data, entity.runtime_instance)
--     end,
--     root_types = {'app.NPCManager.CharacterDataEx'},
--     generate_label = function (entity)
--         return (CharacterID.valueToLabel[entity.id] or 'chUnknown') .. ' : ' .. utils.dd2.translate_character_name(entity.id) .. ' (' .. entity.id .. ')'
--     end,
--     insert_id_range = {0,0}
-- })

if core.editor_enabled then
    local ui = require('content_editor.ui')
    local editor = require('content_editor.editor')
    local definitions = require('content_editor.definitions')
    local helpers = require('content_editor.helpers')

    definitions.override('', {
        ['app.SentimentActionData.SentimentActionTable'] = {
            toString = helpers.to_string_concat_fields('app.SentimentActionData.SentimentActionTable', 0, nil, {'_ActionID', '_Value'})
        },
    })

    editor.define_window('npc', 'NPCs', function (state)
        state.tab = select(2, ui.basic.tabs({'Character data', 'Advanced settings'}, state.tab or 1))
        if state.tab == 1 then
            state.characters = state.characters or {}
            editor.embed_window('npc_character_data', 1, state.characters)
        elseif state.tab == 2 then
            state.configs = state.configs or {}
            editor.embed_window('npc_configs', 3, state.configs)
        end
    end)

    editor.define_window('npc_character_data', 'NPC Character data', function (state)
        local selected = ui.editor.entity_picker('npc_data', state, nil, 'NPC')
        if selected then
            local appearance = udb.get_entity('npc_appearance', selected.id)
            imgui.spacing()
            imgui.indent(8)
            imgui.begin_rect()
            if appearance and imgui.tree_node('Appearance') then
                ui.editor.show_entity_editor(appearance, state)
                imgui.tree_pop()
            end
            ui.editor.show_entity_editor(selected, state)
            imgui.end_rect(4)
            imgui.unindent(8)
        end
    end)

    editor.define_window('npc_configs', 'NPC advanced settings', function (state)
        local selected = ui.editor.entity_picker('npc_config', state, nil, 'NPC')
        if selected then
            imgui.spacing()
            imgui.indent(8)
            imgui.begin_rect()
            ui.editor.show_entity_editor(selected, state)
            imgui.end_rect(4)
            imgui.unindent(8)
        end
    end)

    local NPCManager = sdk.get_managed_singleton('app.NPCManager')---@type app.NPCManager
    ui.editor.set_entity_editor('npc_data', function (entity, state)
        local activeData = NPCManager:get_CharacterDataDict()[entity.id]
        if activeData then
            ui.handlers.show_readonly(activeData, nil, 'Active data', 'app.NPCManager.CharacterDataEx', state)
        end

        if entity.sub_instance then
            state.mainSub = select(2, ui.basic.tabs({'Main', 'Sub (' .. entity.sub_instance:get_Name() .. ')'}, state.mainSub or 1))
            if state.mainSub == 2 then
                return ui.handlers.show(entity.sub_instance, entity, nil, 'app.CharacterData', state)
            else
                return ui.handlers.show(entity.runtime_instance, entity, nil, 'app.CharacterData', state)
            end
        else
            return ui.handlers.show(entity.runtime_instance, entity, nil, 'app.CharacterData', state)
        end
    end)

    -- ui.editor.set_entity_editor('npc_extra_data', function (entity, state)
    --     imgui.text_colored('NPC extra data seems to contain the active runtime data ', core.get_color('info'))
    --     return ui.handlers.show(entity.runtime_instance, entity, nil, 'app.NPCManager.CharacterDataEx', state)
    -- end)

    ui.editor.set_entity_editor('npc_config', function (entity, state)
        return ui.handlers.show(entity.runtime_instance, entity, nil, nil, state)
    end)

    ui.editor.set_entity_editor('npc_appearance', function (entity, state)
        local changed = false
        changed = ui.handlers.show(entity.costumes, entity, nil, nil, state)
        changed = ui.handlers.show(entity.appearances, entity, nil, nil, state) or changed
        return changed
    end)

    editor.add_editor_tab('npc')
end