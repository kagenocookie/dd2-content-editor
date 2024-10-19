
local config = require('quest_editor.quests_config')
local questdb = require('quest_editor.database')
local gamedb = require('quest_editor.gamedb')
local ui = require('content_editor.ui')
local enums = require('quest_editor.enums')
local utils = require('content_editor.utils')

local presets = require('content_editor.object_presets')
local helpers = require('content_editor.helpers')
local udb = require('content_editor.database')
-- local editor = require('content_editor.editor')

local NPCManager = sdk.get_managed_singleton('app.NPCManager')

local getComponent = sdk.find_type_definition('via.GameObject'):get_method('getComponent(System.Type)')
local getCharaName = sdk.find_type_definition("app.GUIBase"):get_method("getName(app.CharacterID)")

local testConfig = config.data.devtools.quest_test or { window = true }
config.data.devtools.quest_test = testConfig

local lastNpcSpeaker --- @type nil|via.GameObject

local selectedNpcId, selectedNpcFilter

local devQuestId = 8000

-- do we need to also handle app.ui021601 ?
sdk.hook(sdk.find_type_definition("app.ui021301"):get_method("reqDisp(via.GameObject, System.Single, System.Guid)"), function(args)
    local gameObj = sdk.to_managed_object(args[3])
    local charaIdStr = gameObj:call('get_Name()') --- @type string
    if charaIdStr:sub(1, 3) == 'ch3' then
        lastNpcSpeaker = gameObj
    end
end)

local function get_processors_for_quest(questId)
    --- @type QuestProcessorData[]
    return udb.get_entities_where('quest_processor', function (entity)
        --- @cast entity QuestProcessorData
        return entity.raw_data.questId == devQuestId or entity.runtime_instance and entity.runtime_instance.get_QuestID() == devQuestId or false
    end)
end

local function npc_is_follower(charaId)
    local q = udb.get_entity('quest', devQuestId)
    local processors = get_processors_for_quest(devQuestId)
    if q then
        -- god this sucks to write without decent type support
        return utils.first_where(processors, function (value)
            local proc = (value.runtime_instance or value.raw_data)
            local action = proc and proc.Process and proc.Process.QuestAction
            if action and helpers.get_type(action) == 'app.quest.action.NpcControl' then
                local params = helpers.get_field(action, '_Param')
                local param = params[0] or params[1]
                if helpers.get_type(param) == 'app.quest.action.NpcControlParam' then
                    return param._NpcID == charaId
                end
            end
            return false
        end)
    end
    return false
end

local function gameobj_to_chara_id(go)
    return getComponent:call(go, sdk.typeof('app.Character')):get_CharaID()
end


---- Real UI
local followerBundle = 'AUTO_test_bundle'

local function draw_window()
    if lastNpcSpeaker and lastNpcSpeaker.get_Valid and lastNpcSpeaker:get_Valid() then
        imgui.text('Last interacted NPC: ' .. enums.NPCIDs.get_label(gameobj_to_chara_id(lastNpcSpeaker)))
        if imgui.button('Select') then
            selectedNpcId = gameobj_to_chara_id(lastNpcSpeaker)
        end
    else
        imgui.text('Last interacted NPC: N/A')
    end

    _, selectedNpcId, selectedNpcFilter = ui.core.filterable_enum_value_picker('NPC picker', selectedNpcId, enums.NPCIDs, selectedNpcFilter)
    if selectedNpcId ~= nil and selectedNpcId ~= enums.NPCIDs.labelToValue.Invalid and not npc_is_follower(selectedNpcId) then
        if imgui.button('Make follower') then
            local preset = presets.get_preset_data('quest_processor', 'NPC Follower')
            if preset == nil then
                re.msg('ERROR: missing NPC Follower preset for quest_processor, please reinstall the mod')
            else
                --- @type Import.QuestProcessor
                preset = utils.clone_table(preset)
                preset.data.questId = devQuestId
                preset.data.QuestAction._Param[1]._NpcID = selectedNpcId
                preset.label = 'Custom follower ' .. devQuestId .. ' / ' .. enums.NPCIDs.get_label(selectedNpcId)
                if not udb.get_bundle_by_name(followerBundle) then
                    udb.create_bundle(followerBundle)
                end
                if not udb.get_active_bundle_by_name(followerBundle) then
                    udb.set_bundle_enabled(followerBundle, true)
                end
                local entity = udb.insert_new_entity('quest_processor', followerBundle, preset) --- @cast entity QuestProcessorData
                if entity then
                    entity.label = entity.label .. ' ProcID ' .. entity.id
                end
                udb.save_bundle(followerBundle)
            end
        end
    end
    if imgui.tree_node('Follower management') then
        if udb.get_active_bundle_by_name(followerBundle) then
            for _, processor in ipairs(udb.get_bundle_entities(followerBundle, 'quest_processor')) do
                --- @cast processor QuestProcessorData
                local action = processor.runtime_instance and processor.runtime_instance.Process.QuestAction or processor.raw_data.QuestAction
                local param = utils.first(helpers.get_field(action, '_Param'))

                if param and helpers.get_type(param) == 'app.quest.action.NpcControlParam' then
                    imgui.push_id(param._NpcID)
                    if imgui.button('Release') then
                        if processor.runtime_instance then
                            processor.runtime_instance.Process:set_CurrentPhase(enums.QuestProcessorEntityPhase.labelToValue.CancelAction)
                        end
                        udb.delete_entity(processor, followerBundle)
                        udb.save_bundle(followerBundle)
                    end
                    imgui.pop_id()
                    imgui.same_line()
                    imgui.text('NPC follower ' .. enums.NPCIDs.get_label(param._NpcID))
                end
            end

            if imgui.button('Remove all followers') then
                for _, e in ipairs(udb.get_bundle_entities(followerBundle, 'quest_processor')) do
                    --- @cast e QuestProcessorData
                    if e.runtime_instance then
                        e.runtime_instance.Process:set_CurrentPhase(enums.QuestProcessorEntityPhase.labelToValue.CancelAction)
                    end
                    udb.delete_entity(e, followerBundle)
                    udb.save_bundle(followerBundle)
                end
            end
        end

        imgui.tree_pop()
    end
end


---- Bootstrap

re.on_frame(function ()
    if testConfig.window and reframework:is_drawing_ui() then
        local keep_showing = imgui.begin_window('Quest testing', true)
        if keep_showing then
            draw_window()
            imgui.end_window()
        else
            testConfig.window = false
            config.save()
        end
    end
end)

re.on_draw_ui(function ()
    if imgui.tree_node('Quest testing') then
        if not testConfig.window and imgui.button('Show quest test window') then
            testConfig.window = true
            config.save()
        end
        draw_window()
        imgui.tree_pop()
    end
end)