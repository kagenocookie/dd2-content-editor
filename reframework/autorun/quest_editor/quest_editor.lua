if type(_quest_DB) == 'nil' then _quest_DB = {} end
if _quest_DB.editor then return _quest_DB.editor end

local core = require('content_editor.core')
local config = require('quest_editor.quests_config')
local questdb = require('quest_editor.database')
local gamedb = require('quest_editor.gamedb')
local ui = require('content_editor.ui')
local quests_ui = require('quest_editor.quest_ui')
local enums = require('quest_editor.enums')

local editor = require('content_editor.editor')
local udb = require('content_editor.database')

editor.define_window('quests', 'Quests', function (state)
    imgui.spacing()
    if imgui.tree_node('Dump quest data') then
        local quest_fn = core.resolve_file('dump', 'processors')
        if imgui.button("Dump raw quest catalog data: " .. quest_fn) then
            json.dump_file(quest_fn, questdb.dump.get_full_raw_data_dump())
        end

        if imgui.button('Dump editable enums: data/quests/enums/*.json') then
            enums.dump_all_enums()
        end

        local var_fn = core.resolve_file('dump', 'quest_variables')
        if imgui.button('Dump quest variables: ' .. var_fn) then
            local questVars = questdb.quests.extract_game_variables_into_enums()
            json.dump_file(var_fn, questVars)
        end
        ui.core.tooltip('Export all quest variables with auto generated labels.\nMainly useful so we can update our name list whenever the game updates the data.')

        imgui.tree_pop()
    end

    _, state.entity_subtype = ui.core.tabs({'Quests', 'Rewards'}, state.entity_subtype)
    if state.entity_subtype == 1 then
        if editor.active_bundle and imgui.button('New quest') then
            --- @type Import.Quest
            local newdata = {
                label = nil, ---@type string
                context = {},
                catalog = '',
                data = {},
                deliver = {},
                npcOverride = {},
                recommendedLevel = 0,
                treeData = {}
            }
            local newQuest = udb.insert_new_entity('quest', editor.active_bundle, newdata)
            ui.editor.set_selected_entity_picker_entity(state, 'quest', newQuest)
        end
        ui.core.tooltip("Custom quests need some manual file editing that we can't do through code yet.\nThis button can handle dynamically modifying the quest catalog, but the quest scene files can't be created here.\nNeed to at least modify the stm/appsystem/scene/quest.scn.20 file and create a new stm/appdata/quest/qu###.scn.20 and resident.scn.20 file.\nCheck shadowcookie / Modding haven on discord for more help.", core.get_color('warning'))

        local selectedQuest = ui.editor.entity_picker('quest', state)
        if selectedQuest then
            --- @cast selectedQuest QuestDataSummary
            imgui.spacing()
            imgui.indent(8)
            imgui.begin_rect()
            ui.editor.show_entity_metadata(selectedQuest)
            quests_ui.show_quest(selectedQuest.id)
            imgui.end_rect(4)
            imgui.unindent(8)
        end
    elseif state.entity_subtype == 2 then
        if editor.active_bundle and imgui.button('New quest reward type') then
            local newReward = udb.insert_new_entity('quest_reward', editor.active_bundle, { data = {} })
            ui.editor.set_selected_entity_picker_entity(state, 'quest_reward', newReward)
        end

        local selectedEntity = ui.editor.entity_picker('quest_reward', state)
        if selectedEntity then
            --- @cast selectedEntity QuestRewardData
            imgui.spacing()
            imgui.indent(8)
            imgui.begin_rect()
            ui.editor.show_entity_metadata(selectedEntity)
            ui.handlers.show(selectedEntity.runtime_instance, selectedEntity, nil, 'app.QuestRewardData')
            imgui.end_rect(4)
            imgui.unindent(8)
        end
    end

    imgui.spacing()

    if ui.core.treenode_tooltip('Quest catalogs', 'Raw unsorted quest catalog data') then
        if questdb.catalogs == nil then questdb.catalogs = gamedb.get_quest_catalogs() end
        for path, catalog in pairs(questdb.catalogs) do
            if imgui.tree_node(path) then
                object_explorer:handle_address(catalog)
                if imgui.tree_node('Data explorer') then
                    ui.handlers.show(catalog)
                end
                imgui.tree_pop()
            end
        end
        imgui.tree_pop()
    end
    -- if changed then config.save() end
end)

editor.add_editor_tab('quests')

_quest_DB.editor = {}
return _quest_DB.editor