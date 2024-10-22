if type(_quest_DB) == 'nil' then _quest_DB = {} end
if _quest_DB.status then return _quest_DB.status end

local GuiManager = sdk.get_managed_singleton('app.GuiManager')
local QuestManager = sdk.get_managed_singleton('app.QuestManager')
local QuestLogManager = sdk.get_managed_singleton('app.QuestLogManager')
local SuddenQuestManager = sdk.get_managed_singleton('app.SuddenQuestManager')
local QuestDeliverManager = sdk.get_managed_singleton('app.QuestDeliverManager')

local config = require('quest_editor.quests_config')
local db = require('quest_editor.database')
local utils = require('content_editor.utils')
local ui = require('content_editor.ui')
local gamedb = require('quest_editor.gamedb')

-- local function conc_dict_to_table(dict)
--     local tbl = {}
--     local it = dict:call('System.Collections.IDictionary.GetEnumerator()')
--     while it:MoveNext() do
--         local cur = it:get_Current()
--         tbl[cur._key] = cur._value
--     end

--     return tbl
-- end

-- local questLogs = conc_dict_to_table(QuestLogManager._QuestLogInfoDict)

--#region IMGUI

local function draw_imgui_quest_status()
    local targetQuestId = GuiManager._TargetQuestId
    if targetQuestId == -1 then
        imgui.text('Active quest: inactive')
    else
        if imgui.tree_node('Active quest') then
            ui.editor.show_quest(targetQuestId)

            imgui.tree_pop()
        end
    end

    local sudden = SuddenQuestManager._CurrentEntity
    if sudden == nil then
        imgui.text('Event: inactive')
    else
        local event = db.events.get(sudden:get_Key())
        if imgui.tree_node('Event') then
            ui.editor.show_event(event)

            imgui.tree_pop()
        end
    end

    if imgui.button('Dump ALL event positions') then
        local pos_data = {
            locations = {}
        }
        local sq_entities = utils.dictionary_get_values(SuddenQuestManager._EntityDict)
        for id, entity in pairs(sq_entities) do
            local selectId = entity:get_Key()
            local sq = db.events.get(selectId)
            if sq then
                local pos = gamedb.get_AIKeyLocation_uni_position(entity:get_StartLocation())
                if pos then
                    pos_data.locations["pos" .. tostring(id)] = {x = pos.x, y = pos.y, z = pos.z}
                end
            end
        end
        json.dump_file('gibbed_Almanac/escort_quest_starts.json', pos_data)
    end

    if imgui.button('Dump currently possible escort starting positions') then
        local pos_data = {
            locations = {}
        }
        local sq_entities = utils.dictionary_get_values(SuddenQuestManager._EntityDict)
        for id, entity in pairs(sq_entities) do
            local selectId = entity:get_Key()
            local sq = db.events.get(selectId)
            if sq then
                local ctx = db.events.get_first_context(selectId)
                local sq_type = ctx and ctx.context._Type
                if sq_type == 2 or sq_type == 3 then
                    -- local sq_type = entity._CurrentContextData and entity._CurrentContextData._Data._Type
                    -- if sq_type == 2 or sq_type == 3 then
                    if entity:checkStartCondition() then
                        local pos = gamedb.get_AIKeyLocation_uni_position(entity:get_StartLocation())
                        if pos then
                            pos_data.locations["pos" .. tostring(id)] = {x = pos.x, y = pos.y, z = pos.z}
                        end
                    else
                        local cond = entity:get_StartCondition()

                        local subconds = true
                        for _, condition in ipairs(cond._ConditionArray:get_elements()) do
                            local eval = condition:evaluate()
                            if not eval then
                                subconds = false
                                print("Can't do event", entity:get_Key(), condition:get_type_definition():get_name(), eval)
                            end
                        end
                        if subconds then
                            local pos = gamedb.get_AIKeyLocation_uni_position(entity:get_StartLocation())
                            if pos then
                                pos_data.locations["pos" .. tostring(id)] = {x = pos.x, y = pos.y, z = pos.z}
                            end
                        end
                    end
                else
                    -- print('Ignoring battle event', selectId)
                end
            -- else
            --     print('sq type', sq_type)
            -- end
            end
        end
        json.dump_file('gibbed_Almanac/escort_quest_starts.json', pos_data)
    end
end

re.on_frame(function ()
    if reframework:is_drawing_ui() then
        if config.data.draw_status_as_window then
            config.data.draw_status_as_window = imgui.begin_window('Quest status', config.data.draw_status_as_window)
            if config.data.draw_status_as_window then
                draw_imgui_quest_status()
                imgui.end_window()
            else
                config.save()
            end
        end
    end
end)

re.on_draw_ui(function()
    local show = imgui.tree_node('Quest status')
    if show then
        imgui.same_line()
        if imgui.button("Toggle window") then
            config.data.draw_status_as_window = not config.data.draw_status_as_window
            config.save()
        end
        draw_imgui_quest_status()
        imgui.tree_pop()
    end
end)
--#endregion

_quest_DB.status = {}
return _quest_DB.status