
local questdb = require('editors.quests.database')
local gamedb = require('editors.quests.gamedb')
local ui = require('content_editor.ui')
local enums = require('editors.quests.enums')

local core = require('content_editor.core')
local editor = require('content_editor.editor')
local udb = require('content_editor.database')
local utils = require('content_editor.utils')
local exporter = require('editors.quests.exporter')
local helpers = require('content_editor.helpers')
local import_handlers = require('content_editor.import_handlers')

local nextframefuncs = {}
re.on_application_entry('UpdateBehavior', function ()
    for _, func in ipairs(nextframefuncs) do
        local succ, err = pcall(func)
        if not succ then
            print('error: ' , err)
        else
            print('no error: ' , err)
        end
    end
    nextframefuncs = {}
end)

local function activate_all_processors()
    local qc = gamedb.get_quest_scene_collector() --- @type any
    local dict = qc:get_QuestSceneFolderDict()
    local enumerator = dict:get_Keys():GetEnumerator()
    while enumerator:MoveNext() do
        local questId = enumerator:get_Current()
        local folder = dict[questId] ---@type via.Folder
        if not folder:get_Active() then
            folder:call('activate(System.Boolean)', true)
        end
        local resident = folder:find('Resident')
        if resident and not resident:get_Active() then
            resident:call('activate(System.Boolean)', true)
        end
    end
end

--- @param processor QuestProcessorData
local function show_quest_processor(processor)
    if processor.runtime_instance then
        ui.handlers.show(processor.runtime_instance, processor, nil, 'app.QuestProcessor')

        if imgui.tree_node('Object explorer') then
            object_explorer:handle_address(processor.runtime_instance)
            imgui.tree_pop()
        end
    else
        local changed
        changed, processor.disabled = imgui.checkbox('Disabled', processor.disabled or false)
        if changed then udb.mark_entity_dirty(processor) end
        ui.basic.tooltip("A disabled processor won't get activated with the quest.\nThis allows you to temporarily disable a processor, maybe as a backup.")
        ui.handlers.show_editable(processor.raw_data, 'QuestAction', processor, 'Raw data', 'app.quest.action.QuestActionBase', 'quest_processor_entity_main')
        ui.handlers.show_editable(processor.raw_data, 'PrevProcCondition', processor, 'PrevProcCondition', 'app.QuestProcessor.ProcCondition', 'quest_processor_conditions_main')
    end
end

--- @param folder via.Folder|via.Transform
--- @param state table
local function process_quest_folder(questId, folder, state)
    local children = utils.folder_get_children(folder)
    for _, child in ipairs(children) do
        local go = child:get_GameObject()
        local proc = utils.get_gameobject_component(go, 'app.QuestProcessor')
            or utils.get_gameobject_component(go, 'app.QuestResourceObject')
            or utils.get_gameobject_component(go, 'app.QuestProcessorRegister')
            or utils.get_gameobject_component(go, 'app.QuestController')
            or utils.get_gameobject_component(go, 'app.QuestResourceCollector')

        local proctype = proc and proc:get_type_definition():get_full_name()
        if not proc then
            process_quest_folder(questId, go:get_Transform(), state)
            return
        end
        local compStatus = 'default'
        local label
        if proctype == 'app.QuestProcessor' then
            compStatus = ({
                [0] = 'disabled', -- uninitialized
                [1] = 'disabled', -- standby
                [3] = 'default', -- waiting
                [4] = 'finished', -- completed
                [5] = 'disabled', -- cancelled
            })[proc:get_CurrentPhase()] or 'default'
            local dbProc = udb.get_entity('quest_processor', proc.ProcID)
            label = (dbProc and (dbProc.label .. ' -- ' .. helpers.to_string(proc, proctype))) or nil
        elseif proctype == 'app.QuestResourceObject' then
            compStatus = proc._IsActive and 'default' or 'disabled'
        end

        imgui.push_style_color(0, editor.get_color(compStatus))

        if (not state.active_processors_only or compStatus == 'default') and ui.basic.treenode_suffix(go:get_Name(), label or helpers.to_string(proc, proctype), core.get_color('info')) then
            imgui.pop_style_color(1)
            if proctype == 'app.QuestProcessor' then
                if imgui.button('Reset processor result') then
                    local qc = proc:get_RefQuestController()
                    if qc then
                        qc:notifyProcessorResult(proc.ProcID, -1)
                    end
                end

                if editor.active_bundle and not udb.get_entity('quest_processor', proc.ProcID) and imgui.button('Add to bundle for editing') then
                    --- @type QuestProcessorData
                    local entity = {
                        id = proc.ProcID,
                        raw_data = {
                            questId = questId,
                            QuestAction = import_handlers.export(proc.Process.QuestAction),
                            PrevProcCondition = import_handlers.export(proc.PrevProcCondition),
                        },
                        disabled = false,
                        type = 'quest_processor',
                        label = nil, --- @as string
                        runtime_instance = proc
                    }
                    udb.create_entity(entity, editor.active_bundle)
                    ui.editor.set_selected_entity_picker_entity(state, 'quest_processor', entity)
                end
            end

            if proc then
                ui.handlers.show(proc, nil, nil, proctype)
            else
                imgui.text_colored('Unhandled quest resource transform type ' .. tostring(proctype), 0xff6666ff)
                quest_debug_go = go
            end

            if proctype == 'app.QuestController' and imgui.tree_node('See proc folders') then
                for fld_i, fld in ipairs(utils.enumerator_to_table(proc.ProcessorFolderControllerList:GetEnumerator())) do
                    imgui.text(tostring(fld_i))
                    imgui.same_line()
                    object_explorer:handle_address(fld)
                end
                imgui.tree_pop()
            end

            if imgui.tree_node('Object explorer') then
                object_explorer:handle_address(child)
                imgui.tree_pop()
            end
            imgui.tree_pop()
        else
            imgui.pop_style_color(1)
        end
    end
end

editor.define_window('quest_processors', 'Quest processors', function (state)
    if imgui.tree_node('Data dump utils') then
        if imgui.button('Activate all quest processors') then
            activate_all_processors()
        end
        ui.basic.tooltip("Useful for editing or data dump purposes to force all processors active.\nMight have to click the button twice to also activate quest subfolders.\nRecommended to turn this on only temporarily, and return to the title screen after desired changes are saved.\nBEWARE: Keeping all processors active during gameplay might break save data or quest behaviour, as well as hurt performance.")

        if imgui.button('Dump all quest processor data: ' .. core.resolve_file('dump', 'processors')) then
            activate_all_processors()
            local qc = gamedb.get_quest_scene_collector() --- @type any
            local dict = qc:get_QuestSceneFolderDict()
            local enumerator = dict:get_Keys():GetEnumerator()
            local dump_output = {}
            while enumerator:MoveNext() do
                local questId = enumerator:get_Current()
                local folder = dict[questId]
                if not folder:get_Active() then
                    folder:call('activate(System.Boolean)', true)
                end
                local children = utils.folder_get_children(folder)

                dump_output[questId] = {}
                for _, child in ipairs(children) do
                    local go = child:get_GameObject()
                    local comp = utils.get_gameobject_component(go, 'app.QuestProcessor')
                        or utils.get_gameobject_component(go, 'app.QuestResourceObject')
                        or utils.get_gameobject_component(go, 'app.QuestController')
                        or nil
                    -- print('Dumping object ', go:get_Name(), 'for quest id ', questId)
                    dump_output[questId][go:get_Name()] = exporter.raw_dump_object(comp)
                end
            end
            local fn = core.resolve_file('dump', 'processors')
            print('Saving dump file: ', fn)
            json.dump_file(fn, dump_output)
        end

        imgui.tree_pop()
    end

    local activeBundle = editor.active_bundle
    local selectedQuest = ui.editor.entity_picker('quest', state, 'processors_quest', 'Quest')
    if selectedQuest then
        local selectedProcessor = ui.editor.entity_picker('quest_processor', state, nil, 'Processor', function (proc)
            --- @cast proc QuestProcessorData
            return proc.raw_data.questId == selectedQuest.id and (not state.processors_bundle_filder or udb.get_entity_bundle(proc) == activeBundle)
        end)
        state.processors_bundle_filder = select(2, imgui.checkbox('Show only current bundle processors', state.processors_bundle_filder or false))
        --- @cast selectedProcessor QuestProcessorData|nil
        if selectedProcessor and selectedProcessor.raw_data.questId ~= selectedQuest.id then
            selectedProcessor = nil
        end

        imgui.spacing()
        if activeBundle then
            local create, newProcPreset = ui.editor.create_button_with_preset(state, 'quest_processor', 'new_proc_picker', 'New processor', nil, selectedProcessor)
            -- local clone = selectedProcessor and imgui.button('Clone selected processor')
            if create then
                --- @type Import.QuestProcessor
                local newdata = ui.editor.preset_instantiate(newProcPreset, {
                    data = utils.table_assign(utils.clone_table(newProcPreset and newProcPreset.data or {}), {
                        questId = selectedQuest.id,
                    }),
                })
                local newEntity = udb.insert_new_entity('quest_processor', activeBundle, newdata)
                ui.editor.set_selected_entity_picker_entity(state, 'quest_processor', newEntity)
                selectedProcessor = newEntity
            end
            imgui.spacing()
        end

        if selectedProcessor then
            --- @cast selectedProcessor QuestProcessorData
            imgui.indent(8)
            imgui.begin_rect()
            ui.editor.show_entity_metadata(selectedProcessor)
            show_quest_processor(selectedProcessor)
            imgui.end_rect(4)
            imgui.unindent(8)
        end
    end

    imgui.spacing()
    if imgui.tree_node('Quest resources overview') then
        _, state.selected_quest_processors_only = imgui.checkbox('Only selected quest', state.selected_quest_processors_only)
        if not state.selected_quest_processors_only then
            imgui.same_line()
            _, state.active_processors_only = imgui.checkbox('Hide inactive', state.active_processors_only)
            _, state.processors_filter = imgui.input_text('Filter', state.processors_filter)
        end

        for _, questId in ipairs(udb.get_entity_enum('quest').values) do
            local quest = udb.get_entity('quest', questId)
            if quest and (
                not state.selected_quest_processors_only and (state.processors_filter == '' or quest.label:find(state.processors_filter))
                or state.selected_quest_processors_only and selectedQuest and selectedQuest.id == quest.id
            ) then
                imgui.push_id(questId)
                local procFolder = gamedb.get_quest_scene_folder(questId)
                -- NOTE: we might be able to use QuestManager:checkActivated(QuestID) to check for activation status
                local isActive = procFolder ~= nil and procFolder:get_Active()
                imgui.push_style_color(0, isActive and 0xffeeffee or 0xffcccccc)
                if (not state.active_processors_only or isActive) and imgui.tree_node(quest.label) then
                    imgui.pop_style_color(1)
                    if procFolder == nil or not procFolder:get_Active() then
                        local virtualProcessors = udb.get_entities_where('quest_processor', function (entity)
                            --- @cast entity QuestProcessorData
                            return entity.raw_data.questId == questId
                        end)
                        --- @cast virtualProcessors QuestProcessorData[]
                        imgui.text_colored(#virtualProcessors == 0 and 'Quest inactive' or 'Quest inactive, processors will be activated when quest activates', core.get_color('info'))
                        if procFolder ~= nil and imgui.button('Force activate') then
                            procFolder:call('activate()')
                        end
                        for _, proc in ipairs(virtualProcessors) do
                            if proc.disabled then imgui.push_style_color(0, 0xffcccccc) end
                            local open = imgui.tree_node(proc.label)
                            if proc.disabled then imgui.pop_style_color(1) end
                            if open then
                                ui.editor.show_entity_metadata(proc)
                                show_quest_processor(proc)
                                imgui.tree_pop()
                            end
                        end
                    else
                        local residentFolder = procFolder:find('Resident')
                        if residentFolder and not residentFolder:get_Active() then
                            if imgui.button('Force activate residents folder') then
                                residentFolder:call('activate()')
                            end
                            ui.basic.tooltip('The residents folder contains the quest processors, it will try to re-trigger all of them on activation')
                        end

                        process_quest_folder(questId, procFolder, state)
                    end

                    imgui.tree_pop()
                else
                    imgui.pop_style_color(1)
                end
                imgui.pop_id()
            end
        end
        imgui.tree_pop()
    end
end)

editor.add_editor_tab('quest_processors')

_quest_DB.quest_processors = {
    show_quest_processor = show_quest_processor,
}