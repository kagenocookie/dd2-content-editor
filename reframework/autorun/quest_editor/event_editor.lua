local udb = require('content_editor.database')
local questdb = require('quest_editor.database')
local editor = require('content_editor.editor')
local ui = require('content_editor.ui')
local quests_ui = require('quest_editor.quest_ui')
local enums = require('quest_editor.enums')
local utils = require('content_editor.utils')

--- @type Import.EventData
local newEventPreset = { type = 'event', data = {
    _StartLocation = enums.AIKeyLocation.labelToValue.qu030070_002, -- glyndwr campfire
    _EndLocation = enums.AIKeyLocation.labelToValue.qu030070_001, -- glyndwr Vernworth
    _IntervalTime = { _Day = 30, _Hour = 0 },
    _StartDistanceMin = 30.0,
    _StartDistance = 100.0,
    _SelectDataArray = { }
} }

editor.define_window('events', 'Events', function (state)
    local activeBundle = editor.active_bundle

    local selectedEvent = ui.editor.entity_picker('event', state)
    if activeBundle then
        local create, preset = ui.editor.create_button_with_preset(state, 'event_context', 'new_ctx', 'New event')
        if create then
            local ctx = udb.insert_new_entity('event_context', activeBundle, preset)
            --- @cast ctx EventContext

            local event = udb.insert_new_entity('event', activeBundle, utils.table_assign(newEventPreset, {
                contextType = ctx and ctx.context._Type,
                data = utils.table_assign(utils.clone_table(newEventPreset.data), {
                    _SelectDataArray = { { _Key = ctx and ctx.id } }
                }),
            }))
            if event then
                ui.editor.set_selected_entity_picker_entity(state, 'event', event)
                selectedEvent = event
            end
        end
    end

    if selectedEvent then
        --- @cast selectedEvent Event
        imgui.spacing()
        imgui.indent(8)
        imgui.begin_rect()
        ui.editor.show_entity_metadata(selectedEvent)
        quests_ui.show_event(selectedEvent, nil, state)
        imgui.end_rect(4)
        imgui.unindent(8)
    end

    if imgui.tree_node('All data overview') then
        local eventsEnum = udb.get_entity_enum('event')
        local contextsEnum = udb.get_entity_enum('event_context')
        _, events_filter = imgui.input_text('Filter', events_filter)
        if imgui.tree_node('Events') then
            for idx, id in ipairs(eventsEnum.values) do
                local evt = questdb.events.get(id)
                if evt then
                    imgui.push_id(id)
                    local label = eventsEnum.labels[idx] or tostring(id)
                    if events_filter == '' or not label or label:find(events_filter) ~= nil then
                        if not questdb.events.is_vanilla_event(id) then
                            if imgui.button('Delete') then
                                udb.delete_entity(evt, activeBundle)
                                imgui.pop_id()
                                break
                            end
                            imgui.same_line()
                        end
                        if imgui.tree_node(label) then
                            quests_ui.show_event(evt)
                            imgui.tree_pop()
                        end
                    end
                    imgui.pop_id()
                end
            end
            imgui.tree_pop()
        end

        if imgui.tree_node('Event contexts') then
            for _, id in ipairs(contextsEnum.values) do
                local ctx = questdb.events.get_context(id)
                if ctx then
                    local label = tostring(id) .. '  ' .. enums.NPCIDs.get_label(ctx.context._NpcID) .. ' ' .. (ctx.label or '')
                    if events_filter == '' or not label or label:find(events_filter) ~= nil then
                        imgui.push_id(id)
                        if not questdb.events.is_vanilla_event_context(id) then
                            if imgui.button('Delete') then
                                udb.delete_entity(ctx, activeBundle)
                                imgui.pop_id()
                                break
                            end
                            imgui.same_line()
                        end
                        quests_ui.show_event_context(ctx)
                        imgui.pop_id()
                    end
                end
            end
            imgui.tree_pop()
        end
        imgui.tree_pop()
    end
end)

editor.add_editor_tab('events')

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
