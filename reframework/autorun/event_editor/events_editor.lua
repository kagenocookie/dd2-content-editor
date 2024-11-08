local udb = require('content_editor.database')
local enums = require('content_editor.enums')
local utils = require('content_editor.utils')
local helpers = require('content_editor.helpers')
local gamedb = require('event_editor.events_gamedata')

local minimum_custom_event_id = 100000

local ui = require('content_editor.ui')
local editor = require('content_editor.editor')
local utils_dd2 = require('content_editor.dd2.utils')

--- @param ctx EventContext
--- @param entity app.SuddenQuestEntity|nil
local function show_event_context(ctx, entity)
    imgui.begin_rect()

    local npcIdStr = enums.get_enum('CharacterID_NPC').valueToLabel[ctx.context._NpcID]
    local name = utils_dd2.translate_character_name(ctx.context._NpcID)
    if ui.core.treenode_suffix(tostring(ctx.id), tostring(npcIdStr) .. ' : ' .. name .. '  ' .. (ctx.label or '')) then
        ui.editor.show_entity_metadata(ctx)

        if entity then
            if not entity._ExecutableList:Contains(ctx.rootContext) then
                imgui.text_colored('Not executable', editor.get_color('warning'))
                if entity._ExecutedDict:ContainsKey(ctx.id) then
                    ui.core.tooltip('This context has already been executed recently and is now locked. entity._ExecutedDict value: ' .. tostring(entity._ExecutedDict:get_Item(ctx.id)))
                    imgui.same_line()
                    if imgui.button('Unlock') then
                        entity._ExecutedDict:Clear()
                    end
                else
                    ui.core.tooltip("This event can't execute at the moment.\nThis generally means that some required data might be missing, conditions are not fulfilled, or the game is in a state where events don't update like the title screen.")
                end
            end
            local timestampLastExecuted = (entity._LastDay * 24 + entity._LastHour) * 3600
            local eventIntervalSeconds = entity:get_IntervalHour() * 3600

            local timeUntilExecutable = timestampLastExecuted + eventIntervalSeconds - utils_dd2.get_ingame_timestamp()
            if timeUntilExecutable > 0 then
                imgui.text_colored('Event on cooldown interval', editor.get_color('warning'))
                imgui.same_line()
                imgui.text('Can execute again in ' .. utils.format_timestamp(timeUntilExecutable))
                imgui.same_line()
                if imgui.button('Reset last execution time') then
                    entity._LastDay = -1
                    entity._LastHour = -1
                end
            end
        end

        imgui.spacing()
        ui.handlers.show(ctx.context, ctx, nil, 'app.SuddenQuestContextData.ContextData', 'event_context_main_' .. ctx.id)

        if imgui.tree_node('Object explorer') then
            object_explorer:handle_address(ctx.context)
            imgui.tree_pop()
        end
        imgui.tree_pop()
    end
    imgui.end_rect(2)
end

---@param event Event
---@param contextData app.SuddenQuestContextData|nil
---@param uiState table|nil
local function show_event(event, contextData, uiState)
    local id = event.id
    local runtimeEntity = event.runtimeEntity
    imgui.text('Key: ' .. tostring(id) .. '  -  ' .. tostring(runtimeEntity and runtimeEntity:get_NpcRegisterKeyName()))

    local chosenCtx = contextData or runtimeEntity and runtimeEntity._CurrentContextData

    local typeId = chosenCtx and chosenCtx._Data._Type
    if not typeId then
        local ctx = gamedb.get_first_context(id)
        typeId = ctx and ctx.context._Type or 0
    end
    imgui.text('Type: ' .. tostring(enums.get_enum('app.QuestDefine.SuddenQuestType').get_label(typeId)))

    if runtimeEntity and not gamedb.event_entity_is_synced_with_source_data(runtimeEntity, event) then
        imgui.same_line()
        if imgui.button('Update runtime entity from source/context changes') then
            gamedb.upsert_entity(data.selectData, udb.get_all_entities('event_context'))
        end
        ui.core.tooltip("Some pending changes need to be manually transferred to the game's runtime entity.")
    else
        imgui.spacing()
        imgui.spacing()
    end

    if runtimeEntity then
        local timestampLastExecuted = (runtimeEntity._LastDay * 24 + runtimeEntity._LastHour) * 3600
        local eventIntervalSeconds = runtimeEntity:get_IntervalHour() * 3600

        local timeUntilExecutable = timestampLastExecuted + eventIntervalSeconds - gamedb.get_ingame_timestamp()
        if timestampLastExecuted > 0 and timeUntilExecutable > 0 then
            imgui.text_colored('Event on cooldown interval', editor.get_color('warning'))
            imgui.same_line()
            imgui.text('Can execute again in ' .. gamedb.format_timestamp(timeUntilExecutable))
            imgui.same_line()
            if imgui.button('Reset last execution time') then
                runtimeEntity._LastDay = -1
                runtimeEntity._LastHour = -1
            end
        end
    end

    if runtimeEntity and ui.core.treenode_tooltip('Runtime entity', 'The active runtime data for this event, generated from the source data and contexts.') then
        local charaId = runtimeEntity:get_NpcID()
        if charaId ~= enums.get_enum('app.CharacterID').labelToValue.Invalid then
            imgui.text('Currently chosen character: ' .. enums.get_enum('app.CharacterID').valueToLabel[charaId])
        end

        ui.handlers.show_readonly(runtimeEntity, event, 'Data explorer', 'app.SuddenQuestEntity')
        if imgui.tree_node('Object explorer') then
            object_explorer:handle_address(runtimeEntity)
            imgui.tree_pop()
        end
        imgui.tree_pop()
    end

    if ui.core.treenode_tooltip('Source data', 'This object is used as a base when generating the runtime entity') then
        imgui.begin_rect()
        ui.editor.show_entity_metadata(event)

        ui.handlers.show(event.selectData, event, nil, 'app.SuddenQuestSelectData', 'event_select_main_' .. event.id)

        if imgui.tree_node('Object explorer') then
            object_explorer:handle_address(event.selectData)
            imgui.tree_pop()
        end
        imgui.end_rect(2)
        imgui.tree_pop()
    end

    if ui.core.treenode_tooltip('Contexts', 'List of context objects that can be picked for this quest, generally used to vary NPCs') then
        local contexts = gamedb.get_contexts(id)
        for idx, ctx in ipairs(contexts) do
            imgui.push_id(idx)
            if imgui.button('X') then
                event.selectData._SelectDataArray = helpers.system_array_remove_at(event.selectData._SelectDataArray, idx - 1)
            else
                imgui.same_line()
                show_event_context(ctx, runtimeEntity)
            end
            imgui.pop_id()
        end

        if editor.active_bundle and editor.active_bundle ~= '' then
            imgui.begin_rect()
            if imgui.button('New context') then
                --- @type Import.EventContext
                local data = {
                    npcID = enums.get_enum('app.CharacterID').labelToValue.Invalid,
                    data = {
                        _TaskSetting = {
                            _ResourceData = 'AppSystem/AI/Situation/TaskData/AITask_1_2_059.user',
                        }
                    },
                }
                local newCtx = udb.insert_new_entity('event_context', editor.active_bundle, data)
                if newCtx then
                    local newPtr = sdk.create_instance('app.SuddenQuestSelectData.SelectData'):add_ref()--[[@as app.SuddenQuestSelectData.SelectData]]
                    newPtr._Key = newCtx.id
                    event.selectData._SelectDataArray = helpers.expand_system_array(event.selectData._SelectDataArray, { newPtr })
                    udb.mark_entity_dirty(event)
                end
            end

            if uiState then
                imgui.text('Link existing context')
                local linkCtx = ui.editor.entity_picker('event_context', uiState, 'event_context_link', 'Context to link')
                if linkCtx and utils.table_contains(contexts, linkCtx) then
                    imgui.text('Chosen context is already added for this event')
                elseif linkCtx and imgui.button('Link') then
                    local newPtr = sdk.create_instance('app.SuddenQuestSelectData.SelectData'):add_ref()--[[@as app.SuddenQuestSelectData.SelectData]]
                    newPtr._Key = linkCtx.id
                    event.selectData._SelectDataArray = helpers.expand_system_array(event.selectData._SelectDataArray, { newPtr })
                    ui.editor.set_selected_entity_picker_entity(uiState, 'event_context_link', nil)
                    udb.mark_entity_dirty(event)
                end
            end
            imgui.end_rect(2)
        end

        imgui.tree_pop()
    end
end

local function dump_sudden_quests()
    local sq_dump = {}
    for questId, quest in pairs(udb.get_all_entities('event')) do
        sq_dump.SuddenQuestSelectData = sq_dump.SuddenQuestSelectData or {}
        local sq = exporter.raw_dump_object(quest) ---@cast sq -nil
        sq.SelectDataOptions = utils.map(sq._SelectDataArray, function (i) return exporter.raw_dump_object(udb.get_entity('event_context', i)) end)
        sq_dump.SuddenQuestSelectData[questId] = sq
    end

    return sq_dump
end


editor.define_window('events', 'Events', function (state)
    if editor.active_bundle then
        local create, preset = ui.editor.create_button_with_preset(state, 'event_context', 'new_ctx', 'New event')
        if create then
            print('preset', preset and preset.id)
            local ctx = udb.insert_new_entity('event_context', editor.active_bundle, preset)
            --- @cast ctx EventContext
            local newEventPreset = editor.presets.get_preset_data('event', 'default') or {}
            newEventPreset = ui.editor.preset_instantiate(newEventPreset, {
                contextType = ctx and ctx.context._Type,
                data = utils.table_assign(utils.clone_table(newEventPreset.data), {
                    _SelectDataArray = { { _Key = ctx and ctx.id } }
                }),
            })

            local event = udb.insert_new_entity('event', editor.active_bundle, newEventPreset)
            ui.editor.set_selected_entity_picker_entity(state, 'event', event)
        end
    end

    local selectedEvent = ui.editor.entity_picker('event', state)
    if selectedEvent then
        --- @cast selectedEvent Event
        imgui.spacing()
        imgui.indent(8)
        imgui.begin_rect()
        ui.editor.show_entity_metadata(selectedEvent)
        show_event(selectedEvent, nil, state)
        imgui.end_rect(4)
        imgui.unindent(8)
    end

    if imgui.tree_node('All data overview') then
        local eventsEnum = udb.get_entity_enum('event')
        local contextsEnum = udb.get_entity_enum('event_context')
        _, events_filter = imgui.input_text('Filter', events_filter)
        if imgui.tree_node('Events') then
            for idx, id in ipairs(eventsEnum.values) do
                local evt = udb.get_entity('event', id)
                if evt then
                    imgui.push_id(id)
                    local label = eventsEnum.labels[idx] or tostring(id)
                    if events_filter == '' or not label or label:find(events_filter) ~= nil then
                        if id >= minimum_custom_event_id then
                            if imgui.button('Delete') then
                                udb.delete_entity(evt, editor.active_bundle)
                                imgui.pop_id()
                                break
                            end
                            imgui.same_line()
                        end
                        if imgui.tree_node(label) then
                            show_event(evt)
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
                local ctx = udb.get_entity('event_context', id)
                if ctx then
                    local label = tostring(id) .. '  ' .. enums.get_enum('CharacterID_NPC').get_label(ctx.context._NpcID) .. ' ' .. (ctx.label or '')
                    if events_filter == '' or not label or label:find(events_filter) ~= nil then
                        imgui.push_id(id)
                        if id >= minimum_custom_event_id then
                            if imgui.button('Delete') then
                                udb.delete_entity(ctx, editor.active_bundle)
                                imgui.pop_id()
                                break
                            end
                            imgui.same_line()
                        end
                        show_event_context(ctx)
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
