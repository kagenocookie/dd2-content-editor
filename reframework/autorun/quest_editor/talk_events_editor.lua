local core = require('content_editor.core')
local TalkEventManager = sdk.get_managed_singleton('app.TalkEventManager')
local TalkManager = sdk.get_managed_singleton('app.TalkManager')

--- @class TalkEventData : DBEntity
--- @field questId integer|nil
--- @field data app.TalkEventDefine.TalkEventData|table

--- @class PawnTalkData : DBEntity
--- @field data app.PawnTalkMonologueData|table

--- @class QuestDialogueEntity : DBEntity
--- @field data app.TalkEventDefine.TalkEventDialoguePack|table

--- @class TalkEventImportData : EntityImportData
--- @field questId integer|nil

--- @class QuestDialogueImportData : EntityImportData
--- @field data table

--- @class PawnTalkImportData : EntityImportData
--- @field data table

local utils = require('content_editor.utils')
local enums = require('content_editor.enums')
local udb = require('content_editor.database')
local import_handlers = require('content_editor.import_handlers')
local helpers = require('content_editor.helpers')

local raw_event_define_enum = utils.clone_table(enums.get_enum('app.TalkEventDefine.ID').valueToLabel)

-- TODO problem with custom talk event: UI freezes up (can't pause) and no talk event happens, NPC returns to his routine
-- TalkTo is fine, returns Continue (with my hook, that is, cause of those pesky enums)
-- isEventPlayable is true with no custom changes
-- but then something dies somewhere
-- TalkTo.updateImpl() is not called again
-- the task keeps shitting itself and making the NPC psychotic even when he's just waiting there, so that's probably what to look into

-- _dbg.hookLog('app.NPCUtil', 'canStartTalk')
-- _dbg.hookLog('app.TalkEventManager', 'requestPlay(System.Object, app.TalkEventDefine.ID, app.Character, app.Character, System.Collections.Generic.Dictionary`2<app.CharacterID,app.Character>, System.Action, System.Action, System.Action, System.Func`1<System.Boolean>, System.Boolean, System.Boolean, System.Boolean)')
-- _dbg.hookLog('app.TalkEventManager.TalkEventCommandRequester', 'getDynamicResource')
-- _dbg.hookLog('app.TalkEventManager.TalkEventCommandRequester', 'load')
-- _dbg.hookLog('app.TalkEventManager.TalkEventCommandRequester', 'play')
-- -- requestPlay(System.Object, app.TalkEventDefine.ID, app.Character, app.Character, System.Collections.Generic.Dictionary`2<app.CharacterID,app.Character>, System.Action, System.Action, System.Action, System.Func`1<System.Boolean>, System.Boolean, System.Boolean, System.Boolean)
-- _dbg.instanceHook('app.actinter.CommandExecutor', 'update','cmd_executors', function (this)
--     return
--         this._ActInter and
--         this._ActInter:get_Character() and
--         this._ActInter:get_Character():get_CharaID() == enums.get_enum('app.CharacterID').labelToValue.ch300316
-- end)
-- _dbg.instanceHook('app.TalkEventManager.TalkEventCommandRequester', 'load','talk_requesters')

--- capcom please why is your code so nasty
--- @param segmentName string
--- @return integer
--- @return string
local function lookup_quest_id_from_segment_name(segmentName)
    local questSegStart = segmentName:find('_qu%d')
    if questSegStart and questSegStart == segmentName:find('_') then
        local questId = segmentName:match('([%d]+)[^a-zA-Z0-9]?.*$', questSegStart + 3)
        if questId then
            questId = tonumber(questId)--[[@as integer]]
            if udb.get_entity('quest', questId) then
                return questId, ''
            else
                return -1, 'Unknown quest id ' .. tostring(questId)
            end
        else
            return -1, 'Invalid quest reference syntax (must be _qu###_)'
        end
    else
        return -1, 'Segment name does not match the expected structure (_qu###)'
    end
end

-- since we can't fix enum parsing with a hook on TryParseInternal or properly inject custom enum entries, re-implement relevant methods in lua, sigh.
-- I don't wanna have to relearn c++ to make a native hook for this

--#region Enum hacks

local NPCUtilcanStartTalk = sdk.find_type_definition('app.NPCUtil'):get_method('canStartTalk')
local OccupiedManager = sdk.get_managed_singleton('app.OccupiedManager')
local ReturnCommand = enums.get_enum('app.actinter.Define.ReturnCommand')
local RoutineType = enums.get_enum('app.actinter.cmd.TalkTo.RoutineType')
local pretalk_str = sdk.create_managed_string('PreTalk')
local method_requestSpeech = sdk.find_type_definition('app.SpeechController'):get_method('requestSpeech(app.TalkEventDefine.ID, app.Character, app.Character, System.Collections.Generic.List`1<app.Character>, System.Boolean)')

local function hook_return(storage, value)
    storage.retval = value
    return sdk.PreHookResult.SKIP_ORIGINAL
end

-- TODO: this hook getting triggered kills the ui input. figure out why and fix please
-- I think it's a 1:1 translation of the actual source aside from replacing the enum lookup, but I may have missed something or made a mistake with my lua return value overrides
-- sdk.hook(
--     sdk.find_type_definition('app.actinter.cmd.TalkTo'):get_method('updateImpl'),
--     function (args)
--         local storage = thread.get_hook_storage()
--         -- full call chain:
--         -- app.ActionInterface:update()
--         -- app.actinter.Executor:update()
--         -- app.actinter.CommandExecutor:update()
--         -- app.actinter.cmd.TalkTo:updateImpl()
--         print('TalkTo updateImpl call')
--         local this = sdk.to_managed_object(args[2])--[[@as app.actinter.cmd.TalkTo]]
--         if this:get_Target() == nil then
--             return hook_return(storage, ReturnCommand.labelToValue.Break) end
--         local targetCharacter = this:get_Target():get_Character()
--         if targetCharacter == nil or not targetCharacter:get_Enabled() then
--             return hook_return(storage, ReturnCommand.labelToValue.Break) end
--         if this.CachedSpeechController == nil or not this.CachedSpeechController:get_Enabled() then
--             return hook_return(storage, ReturnCommand.labelToValue.Break) end
--         if this:get_Routine() ~= RoutineType.labelToValue.Interact then
--             if this:get_Routine() == RoutineType.labelToValue.End then
--                 --- TODO what are they comparing this against?
--                 -- *(_DWORD *)(qword_14F84E8D8 + 504)      qword_14F84E8D8 dq 5CD39470h
--                 -- I'm assuming it's TalkEventDefine.ID.None
--                 print('end routine')
--                 return hook_return(storage, this.TalkingID == 0 and ReturnCommand.labelToValue.Next or ReturnCommand.labelToValue.Continue)
--             end
--             print('non interact')
--             return hook_return(storage, ReturnCommand.labelToValue.Break)
--         end
--         local agg = this:get_AIBBCtrl():get_BBAggregate()
--         local situation = agg and agg:get_Situation()
--         local paramString = situation:call('getValue(app.BBKeys.Situation.String)', 1) -- app.BBKeys.Situation.String.Param01

--         local talkEnum = enums.get_enum('app.TalkEventDefine.ID')

--         -- replaced instead of Enum.TryParseInternal
--         local talkEventId = talkEnum.labelToValue[paramString]
--         if not talkEventId then talkEventId = tonumber(paramString, 10) end

--         if not talkEventId then
--             this.TalkingID = 0
--             return hook_return(storage, ReturnCommand.labelToValue.Break)
--         end
--         this.TalkingID = talkEventId
--         if not NPCUtilcanStartTalk:call(nil, this:get_Character(), this.TalkingID, true) then
--             print('cannot start')
--             return hook_return(storage, ReturnCommand.labelToValue.Break)
--         end

--         if method_requestSpeech:call(this.CachedSpeechController, this.TalkingID, this:get_Character(), this:get_Target():get_Character(), nil, true) then
--             print('requested speech, end routine')
--             this:set_Routine(RoutineType.labelToValue.End)
--         end

--         OccupiedManager:unlock(pretalk_str, 11) -- 11 = app.OccupiedManager.LockType.PreTalk
--         print('continuing...')
--          -- continue means the command is "in progress"
--         return hook_return(storage, ReturnCommand.labelToValue.Continue)
--     end,
--     function ()
--         return sdk.to_ptr(thread.get_hook_storage().retval)
--     end
-- )

sdk.hook(
    sdk.find_type_definition('app.TalkEventManager'):get_method('isQuestNpcTalkEvent'),
    function (args)
        local talkId = sdk.to_int64(args[2]) & 0xffffffff
        -- print('isQuestNpcTalkEvent', talkId)
        local talkEvent = udb.get_entity('talk_event', talkId)
        if talkEvent and talkEvent.questId ~= nil and udb.get_entity_bundle(talkEvent) then
            print('!!! isQuestNpcTalkEvent', talkEvent.id)
        end
        thread.get_hook_storage().result = true
        return sdk.PreHookResult.SKIP_ORIGINAL
    end,
    function (ret)
        local result = thread.get_hook_storage().result
        if result ~= nil then return sdk.to_ptr(result) end
        return ret
    end
)

-- called from NPCUtil.canStartTalk, PawnUtil.canStartTalk
sdk.hook(
    sdk.find_type_definition('app.TalkEventManager'):get_method('isEventPlayable'),
    function (args)
        local talkId = sdk.to_int64(args[3]) & 0xffffffff
        thread.get_hook_storage().talkId = talkId

        -- local talkEvent = udb.get_entity('talk_event', talkId)
        -- if talkEvent and talkEvent.questId ~= nil and udb.get_entity_bundle(talkEvent) then
        --     print('!!! isEventPlayable', talkEvent.id)
        --     thread.get_hook_storage().result = true
        --     return sdk.PreHookResult.SKIP_ORIGINAL
        -- end
    end,
    function (ret)
        local result = thread.get_hook_storage().result
        if result ~= nil then return sdk.to_ptr(result) end
        print('isEventPlayable', thread.get_hook_storage().talkId, sdk.to_int64(ret) & 1)
        return ret
    end
)

sdk.hook(
    sdk.find_type_definition('app.TalkEventDefine'):get_method('getQuestIdFromSegment'),
    function (args)
        local str = sdk.to_managed_object(args[2]):ToString()
        thread.get_hook_storage().qid = lookup_quest_id_from_segment_name(str)
        return sdk.PreHookResult.SKIP_ORIGINAL
    end,
    function ()
        return sdk.to_ptr(thread.get_hook_storage().qid)
    end
)

sdk.hook(
    sdk.find_type_definition('app.TalkEventManager'):get_method('getQuestIdFromTalkEventId'),
    function (args)
        local talkEventId = sdk.to_int64(args[2]) & 0xffffffff
        local talkEvt = udb.get_entity('talk_event', talkEventId)
        print('getQuestIdFromTalkEventId', talkEventId)
        if talkEvt and udb.get_entity_bundle(talkEvt) then
            print('Overriding getQuestIdFromTalkEventId', talkEventId)
        end
        thread.get_hook_storage().qid = talkEvt and talkEvt.questId or 0
        return sdk.PreHookResult.SKIP_ORIGINAL
    end,
    function ()
        return sdk.to_ptr(thread.get_hook_storage().qid)
    end
)

local function get_talk_event_enum_id_to_quest_id(id)
    -- te5 prefix enum labels are for quests, so then we have te5{:6_quest_id}_{:3_talk_subid}
    local enumValue = raw_event_define_enum[id]
    if enumValue and enumValue:sub(1, 3) == 'te5' then
        local qid = math.floor(tonumber(enumValue:sub(4, 9)) or 0)
        local quest = qid and qid > 0 and udb.get_entity('quest', qid)
        return quest and quest.id or 0
    end
    return 0
end

--#endregion

-- fetch current game data
udb.events.on('get_existing_data', function ()
    local enumerator = TalkEventManager._ResourceCatalog:get_MergedCatalog():GetEnumerator()
    while enumerator:MoveNext() do
        local kv = enumerator._current
        --- @type TalkEventData
        local entity = {
            id = kv.key,
            type = 'talk_event',
            data = kv.value._Item,
            questId = get_talk_event_enum_id_to_quest_id(kv.key)
        }
        udb.register_pristine_entity(entity)
    end

    enumerator = TalkEventManager._QuestDialoguePackCatalog:GetEnumerator()
    while enumerator:MoveNext() do
        local kv = enumerator._current
        --- @type QuestDialogueEntity
        local entity = {
            id = kv.key,
            type = 'quest_dialogue_pack',
            data = kv.value,
        }
        udb.register_pristine_entity(entity)
    end

    -- note: both loops are identical, just need different enumerators
    enumerator = TalkManager._PawnCommonTalkMonologueCatalog:get_MergedCatalog():GetEnumerator()
    while enumerator:MoveNext() do
        local kv = enumerator._current
        --- @type PawnTalkData
        local entity = {
            id = kv.key,
            type = 'pawn_talk_monologue',
            data = kv.value._Item,
        }
        udb.register_pristine_entity(entity)
    end

    enumerator = TalkManager._PawnQuestTalkMonologueCatalog:get_MergedCatalog():GetEnumerator()
    while enumerator:MoveNext() do
        local kv = enumerator._current
        --- @type PawnTalkData
        local entity = {
            id = kv.key,
            type = 'pawn_talk_monologue',
            data = kv.value._Item,
        }
        udb.register_pristine_entity(entity)
    end
end)

udb.register_entity_type('talk_event', {
    export = function (instance)
        --- @cast instance TalkEventData
        return {
            data = import_handlers.export(instance.data, 'app.TalkEventDefine.TalkEventData'),
            questId = instance.questId,
        }
    end,
    import = function (data, instance)
        --- @cast data TalkEventImportData
        --- @cast instance TalkEventData
        instance = instance or {}
        instance.data = import_handlers.import('app.TalkEventDefine.TalkEventData', data.data or {}, instance.data)
        instance.questId = data.questId
        if instance.questId == nil then
            instance.questId = get_talk_event_enum_id_to_quest_id(instance.id)
        end
        if not TalkEventManager._ResourceCatalog:ContainsKey(data.id) then
            TalkEventManager._ResourceCatalog:register(data.id, instance.data)
            print('Imported talk event: ', data.id, 'quest', instance.questId)
        end
        return instance
    end,
    delete = function (instance)
        --- @cast instance TalkEventData
        if not raw_event_define_enum[instance.id] then
            TalkEventManager._ResourceCatalog:unregister(instance.data)
            return 'ok'
        end
        return 'forget'
    end,
    generate_label = function (entity)
        --- @cast entity TalkEventData
        local castList = entity.data._CastList
        local enum_label = (raw_event_define_enum[entity.id] or '')
        if not castList or castList:get_size() == 0 then
            return 'Talk ' .. entity.id .. ': ' .. enum_label
        elseif castList:get_size() <= 4 then
            return 'Talk ' .. entity.id .. ': ' .. enum_label .. '; ' .. helpers.array_to_string(entity.data._CastList, ', ', 'app.TalkEventCast[]', 'no participants')
        else
            return 'Talk ' .. entity.id .. ': ' .. enum_label .. ' Many participants'
        end
    end,
    replaced_enum = 'app.TalkEventDefine.ID',
    insert_id_range = {10000, 999000},
    root_types = {'app.TalkEventDefine.TalkEventData'},
})
udb.get_entity_enum('talk_event').orderByValue = true

udb.register_entity_type('quest_dialogue_pack', {
    export = function (instance)
        --- @cast instance QuestDialogueEntity
        return { data = import_handlers.export(instance.data, 'app.TalkEventDefine.TalkEventDialoguePack') }
    end,
    import = function (data, instance)
        --- @cast data QuestDialogueImportData
        --- @cast instance QuestDialogueEntity
        instance = instance or {}

        instance.data = import_handlers.import('app.TalkEventDefine.TalkEventDialoguePack', data.data or {}, instance.data)
        if not TalkEventManager._QuestDialoguePackCatalog:ContainsKey(data.id) then
            TalkEventManager._QuestDialoguePackCatalog[data.id] = instance.data
        end
        return instance
    end,
    delete = function (instance)
        --- @cast instance QuestDialogueEntity
        return 'forget'
    end,
    generate_label = function (entity)
        --- @cast entity QuestDialogueEntity
        local quest = udb.get_entity('quest', entity.id)
        if quest then
            return 'Quest dialogue : ' .. quest.label
        else
            return 'Quest ' .. entity.id .. ' dialogue'
        end
    end,
    insert_id_range = {0, 0},
    root_types = {'app.TalkEventDefine.TalkEventDialoguePack'},
})

udb.register_entity_type('pawn_talk_monologue', {
    export = function (instance)
        --- @cast instance PawnTalkData
        return { data = import_handlers.export(instance.data, 'app.PawnTalkMonologueData') }
    end,
    import = function (data, instance)
        --- @cast data PawnTalkImportData
        --- @cast instance PawnTalkData
        instance = instance or {}

        instance.data = import_handlers.import('app.PawnTalkMonologueData', data.data, instance.data)
        if instance.data._IsQuest then
            if instance.data._QuestId and instance.data._QuestId ~= -1 and not TalkEventManager._PawnQuestTalkMonologueCatalog:ContainsKey(data.id) then
                TalkEventManager._PawnQuestTalkMonologueCatalog[instance.data._QuestId] = instance.data
            end
        else
            if not TalkEventManager._PawnCommonTalkMonologueCatalog:ContainsKey(data.id) then
                TalkEventManager._PawnCommonTalkMonologueCatalog[data.id] = instance.data
            end
        end

        instance.data = import_handlers.import('app.PawnTalkMonologueData', data.data, data)
        return instance
    end,
    delete = function (instance)
        --- @cast instance PawnTalkData
        return 'forget'
    end,
    generate_label = function (entity)
        --- @cast entity PawnTalkData
        if entity.data._IsQuest then
            local quest = udb.get_entity('quest', entity.data._QuestId)
            return 'Pawn monologue ' .. entity.id .. ', quest: ' .. (quest and quest.label or 'Unknown quest')
        else
            return 'Pawn monologue ' .. entity.id
        end
    end,
    insert_id_range = {1000, 20000000},
    root_types = {'app.PawnTalkResourceCatalog.Item'},
})

if core.editor_enabled then
    local editor = require('content_editor.editor')
    local ui = require('content_editor.ui')

    local definitions = require('content_editor.definitions')

    --- @param dlgPack QuestDialogueEntity
    local function draw_dialoge_pack(dlgPack)
        ui.editor.show_entity_metadata(dlgPack)
        ui.handlers.show_editable(dlgPack, 'data', dlgPack, nil, 'app.TalkEventDefine.TalkEventDialoguePack')
    end

    --- @param talkEvent TalkEventData
    --- @param ctx UIContainer
    local function draw_event_entity(talkEvent, ctx)
        ui.editor.show_entity_metadata(talkEvent)
        ctx.data._state = ctx.data._state or {}
        imgui.indent(8)
        imgui.begin_rect()
        local changed
        changed, newval, ctx.data._state.filter = ui.core.filterable_enum_value_picker('Target quest', talkEvent.questId, udb.get_entity_enum('quest'), ctx.data._state.filter)
        if changed then
            talkEvent.questId = newval
            udb.mark_entity_dirty(talkEvent)
        end
        if talkEvent.questId then
            local dlg = udb.get_entity('quest_dialogue_pack', talkEvent.questId)
            if dlg then
                if imgui.tree_node('Quest dialogue segments') then
                    draw_dialoge_pack(dlg)
                    imgui.tree_pop()
                end
            else
                imgui.text_colored('Could not find linked quest dialogue pack', core.get_color('warning'))
                if editor.active_bundle and imgui.button('Create##Quest dlg pack') then
                    udb.insert_new_entity('quest_dialogue_pack', editor.active_bundle, {
                        id = talkEvent.questId,
                        data = {}
                    })
                end
            end
        end
        imgui.end_rect(2)
        imgui.unindent(8)
        imgui.spacing()
        ui.handlers.show_editable(talkEvent, 'data', talkEvent, nil, 'app.TalkEventDefine.TalkEventData')
    end

    editor.define_window('quest_dialogue_pack', 'Quest dialogue packs', function (state)
        imgui.text_colored('You can create a new pack from the talk event editor', core.get_color('info'))

        local selectedEntity = ui.editor.entity_picker('quest_dialogue_pack', state)
        if selectedEntity then
            --- @cast selectedEntity QuestDialogueEntity
            imgui.spacing()
            imgui.indent(8)
            imgui.begin_rect()
            draw_dialoge_pack(selectedEntity)
            imgui.end_rect(4)
            imgui.unindent(8)
        end
    end)

    editor.define_window('talk_events', 'Talk events', function (state)
        if editor.active_bundle then
            local create, preset = ui.editor.create_button_with_preset(state, 'talk_event', nil, 'New talk event')
            if create then
                local newEntity = udb.insert_new_entity('talk_event', editor.active_bundle, preset or {})
                ui.editor.set_selected_entity_picker_entity(state, 'talk_event', newEntity)
                --- @cast newEntity TalkEventData
                newEntity.data._Id = newEntity.id
            end
        end

        local selectedEntity = ui.editor.entity_picker('talk_event', state)
        if selectedEntity then
            --- @cast selectedEntity TalkEventData
            imgui.spacing()
            imgui.indent(8)
            imgui.begin_rect()
            state.talkEvent = state.talkEvent or {}
            state.talkEvent.data = state.talkEvent.data or {}
            draw_event_entity(selectedEntity, state.talkEvent)
            imgui.end_rect(4)
            imgui.unindent(8)
        end
    end)

    editor.add_editor_tab('talk_events')

    ui.handlers.register_extension('next_talk_node_picker', function (handler, data)
        --- @type UIHandler
        return function (ctx)
            local talkEvent = ctx.owner --- @cast talkEvent TalkEventData|nil
            if not talkEvent then return handler(ctx) end

            local w = imgui.calc_item_width()
            if imgui.button('Refresh node list') then
                ctx.data.all_nodes = nil
                ctx.data.all_node_name = nil
            end
            imgui.same_line()
            imgui.set_next_item_width(w - 190)
            local nodes = talkEvent.data._SegmentNodes
            if not ctx.data.all_nodes or not ctx.data.all_node_names then
                ctx.data.all_nodes = {}
                ctx.data.all_node_names = {}
                for i = 0, nodes:get_Count() - 1 do
                    local node = nodes[i]
                    ctx.data.all_nodes[#ctx.data.all_nodes+1] = node
                    ctx.data.all_node_names[#ctx.data.all_node_names+1] = helpers.to_string(node)
                end
            end

            local nodeId = ctx.get()
            local selectedIdx = utils.table_find_index(ctx.data.all_nodes, function (item) return item._NodeId == nodeId end)
            local nextNode = ctx.data.all_nodes[selectedIdx]
            local changed, newNode
            changed, newNode, ctx.data.node_filter = ui.core.combo_filterable('Next node', nextNode, ctx.data.all_node_names, ctx.data.node_filter, ctx.data.all_nodes)
            if changed then
                ctx.set(newNode._NodeId)
                ctx.parent.children._NextNodeName.set(newNode._NodeName)
                ctx.parent.children._NextNodeNameHash.set(newNode._NodeNameHash)
                nextNode = newNode
            end
            if nextNode then
                if imgui.tree_node('Target node') then
                    local nextNodePicker = ctx.parent.get()
                    ui.handlers.show_readonly(nextNode, talkEvent, nil, 'app.TalkEventSegmentNode', nextNodePicker:get_address())
                    imgui.tree_pop()
                end
            end
            return changed
        end
    end)

    local function node_target_quest_lookup(ctx)
        --- @cast ctx UIContainer
        local questId = lookup_quest_id_from_segment_name(ctx.get()._SegmentName)
        if questId > 0 then
            return udb.get_entity('quest_dialogue_pack', questId)
        end

        local ownerTalkEvent = ctx.owner and ctx.owner.type == 'talk_event' and ctx.owner or nil
        --- @cast ownerTalkEvent TalkEventData
        if ownerTalkEvent then
            return udb.get_entity('quest_dialogue_pack', ctx.owner--[[@as TalkEventData]].questId)
        end
    end

    ui.handlers.register_extension('talk_choice_segment_copy', function (handler)
        --- @type UIHandler
        return function (ctx)
            local changed = handler(ctx)
            if ctx.owner and ctx.owner.type == 'talk_event' and imgui.tree_node('Generate from dialogue pack') then
                local dlg = udb.get_entity('quest_dialogue_pack', ctx.owner--[[@as TalkEventData]].questId)
                if dlg then
                    local options = utils.pluck(dlg.data._ChoiceSegmentList:get_elements(), '_SegmentName')
                    ctx.data._segment_copy = select(2, imgui.combo('Source choice segment', ctx.data._segment_copy, options))
                    if ctx.data._segment_copy and dlg.data._ChoiceSegmentList[ctx.data._segment_copy - 1] and imgui.button('Generate') then
                        local newChoices = {}
                        local choices = dlg.data._ChoiceSegmentList[ctx.data._segment_copy - 1]._DialogueList:get_elements() --[[@as app.TalkEventDialogueUserData.Dialogue[] ]]
                        for _, choice in ipairs(choices) do
                            newChoices[#newChoices+1] = import_handlers.import('app.TalkEventChoice', {
                                _ChoiceId = choice._MsgId:ToString(),
                                _Choice = utils.translate_guid(choice._MsgId),
                            })
                        end
                        ctx.set(helpers.create_array('app.TalkEventChoice', nil, newChoices))
                        changed = true
                        ctx.data._segment_copy = nil
                    end
                else
                    re.msg('Quest does not have a dialogue pack. Create one first.')
                end
                imgui.tree_pop()
            end
            return changed
        end
    end)

    local talkTypeEnumLookup = nil
    ui.handlers.register_extension('talk_segment_match_enum_node_type', function (handler)
        --- @type UIHandler
        return function (ctx)
            local typeEnum = ctx.get()
            local parent = ctx.parent.get()
            local classname = helpers.get_type(parent)
            if not talkTypeEnumLookup then
                talkTypeEnumLookup = {}
                local enum = enums.get_enum('app.TalkEventSegmentNodeType')
                for _, label in ipairs(enum.labels) do
                    local subtypename = 'app.' .. label .. 'SegmentNode'
                    if not sdk.find_type_definition(subtypename) then
                        subtypename = 'app.' .. label .. 'Node'
                    end
                    talkTypeEnumLookup[subtypename] = enum.labelToValue[label]
                end
            end
            talkTypeEnumLookup['app.AudienceReactionNode'] = 0 -- no enum entry ¯\_(ツ)_/¯
            local expectedTypeEnum = talkTypeEnumLookup[classname]
            if expectedTypeEnum == nil then
                print('ERROR: null talk segment node type', typeEnum, classname, json.dump_string(talkTypeEnumLookup))
            elseif expectedTypeEnum ~= typeEnum then
                ctx.set(expectedTypeEnum)
                return true
            end
            return false
        end
    end)

    ui.handlers.register_extension_alias('linked_talk_event', 'linked_entity', {
        type = 'linked_entity', entity_type = 'talk_event', draw = draw_event_entity
    })
    ui.handlers.register_extension_alias('talk_node_segment_lookup', 'linked_entity', {
        entity_type = 'quest_dialogue_pack',
        getter = node_target_quest_lookup,
        labeler = function (dlg_pack)
            return 'Talk segment from quest ' .. dlg_pack.id
        end,
        draw = function (dlg_pack, ctx)
            --- @cast dlg_pack QuestDialogueEntity

            local lookupKey = ctx.get()._SegmentNameHash
            local targetSubentity = utils.first_where(dlg_pack.data._TalkSegmentList, function (deliver)
                return deliver._SegmentNameHash == lookupKey
            end)
            if targetSubentity then
                ui.handlers.show(targetSubentity, dlg_pack, nil, 'app.TalkEventDialogueUserData.DefaultSegment')
            else
                imgui.text_colored('Talk segment not found', core.get_color('warning'))
                if imgui.button('Create') then
                    local newSegment = import_handlers.import('app.TalkEventDialogueUserData.DefaultSegment', { _SegmentNameHash = lookupKey })
                    dlg_pack.data._TalkSegmentList = helpers.expand_system_array(dlg_pack.data._TalkSegmentList, {newSegment}, 'app.TalkEventDialogueUserData.DefaultSegment')
                    udb.mark_entity_dirty(dlg_pack)
                end
            end
        end
    })

    ui.handlers.register_extension_alias('talk_choice_segment_lookup', 'linked_entity', {
        entity_type = 'quest_dialogue_pack',
        getter = node_target_quest_lookup,
        labeler = function (dlg_pack)
            return 'Choice segment from quest ' .. dlg_pack.id
        end,
        draw = function (dlg_pack, ctx)
            --- @cast dlg_pack QuestDialogueEntity

            local lookupKey = ctx.get()._SegmentNameHash
            local targetSubentity = utils.first_where(dlg_pack.data._ChoiceSegmentList, function (deliver)
                return deliver._SegmentNameHash == lookupKey
            end)
            if targetSubentity then
                ui.handlers.show(targetSubentity, dlg_pack, nil, 'app.TalkEventDialogueUserData.ChoiceSegment')
            else
                imgui.text_colored('Choice segment not found', core.get_color('warning'))
                if imgui.button('Create') then
                    local newSegment = import_handlers.import('app.TalkEventDialogueUserData.ChoiceSegment', { _SegmentNameHash = lookupKey })
                    dlg_pack.data._ChoiceSegmentList = helpers.expand_system_array(dlg_pack.data._ChoiceSegmentList, {newSegment}, 'app.TalkEventDialogueUserData.ChoiceSegment')
                    udb.mark_entity_dirty(dlg_pack)
                end
            end
        end
    })

    ui.handlers.register_extension('pawn_talk_node_link', function (handler, data)

        --- @type UIHandler
        return function (ctx)
            local changed = handler(ctx)
            local node = ctx.get()
            local talkEvent = ctx.owner
            ---@cast talkEvent TalkEventData|nil

            local monologueContainer = nil
            local monologueIndex = 0
            -- TalkManager has several different methods and dictionaries containing different monologue data
            -- I'm not sure if there might be better solutions for some cases, but at least one case works with below
            -- worst case scenario: foreach (TalkManager._PawnQuestTalkMonologueCatalog[questId]) find where _NameHash == node._categoryNameHash
            if talkEvent and talkEvent.questId and TalkManager._PawnQuestTalkMonologueCatalog:ContainsKey(talkEvent.questId) then
                local monologueData = sdk.get_managed_singleton('app.TalkManager')._PawnQuestTalkMonologueCatalog:get_MergedCatalog()[talkEvent.questId]._Item
                for i, cat in pairs(monologueData._CategoryList) do
                    -- cat: app.PawnTalkMonologueCategoryData
                    if cat._NameHash == node._Selector._CategoryNameHash then
                        -- app.PawnTalkMonologueCategoryData
                        monologueContainer = monologueData._CategoryList
                        monologueIndex = i
                        break
                    end
                end
            end

            if talkEvent and monologueIndex ~= 0 and monologueContainer then
                if ui.core.treenode_tooltip('Pawn talk reference', 'Reference to a pawn_talk_monologue entity, specified by the quest ID and Selector.SegmentNameHash') then
                    local mng = udb.get_entity('pawn_talk_monologue', talkEvent.questId)
                    ui.handlers.show_editable(monologueContainer, monologueIndex, mng)
                    imgui.tree_pop()
                end
            end

            return changed
        end
    end)

    ui.handlers.register_extension('_talk_event_segment_name_warning', function (handler, data)
        --- @type UIHandler
        return function (ctx)
            local changed = handler(ctx)
            local val = ctx.get() --- @type string
            local questId, err = lookup_quest_id_from_segment_name(val)
            if questId == -1 then
                imgui.text_colored(err, core.get_color('danger'))
            else
                imgui.text_colored('Matched quest ID: ' .. questId, core.get_color('success'))
            end
            return changed
        end
    end)

    local newGuid = sdk.find_type_definition('System.Guid'):get_method('NewGuid')
    local randomizable_uuid = { type = 'randomizable', randomizer = function () return newGuid:call(nil):ToString() end }
    local randomizable_int = { type = 'randomizable', randomizer = function () return math.random(0, 4294967295) end }

    local function to_string_expose_single(array, elementClassname)
        if array:get_size() == 1 then
            return helpers.to_string(array[0], elementClassname)
        end
        return array:ToString()
    end

    -- TODO handle: app.CommonNpcTalkNode (app.TalkMonologueSelector)
    -- link choice by guid - ChoiceSegmentList[number].DialogueList[number]._MsgId)

    definitions.override('', {
        ['app.TalkEventDefine.TalkEventData'] = {
            fieldOrder = {'_Id', '_IdHash', '_InitialSpeaker', '_CastList', '_SegmentNodes', '_PlayCondition'},
            extensions = {
                { type = 'object_explorer' }
            }
        },
        ['app.TalkEventCast'] = {
            toString = function (value)
                return enums.get_enum('app.CharacterID').get_label(value._OriginalCast)
            end
        },
        ['app.TalkEventDefine.ID[]'] = {
            fields = {
                __element = { extensions = { { type = 'linked_talk_event' } } }
            }
        },
        ['app.AISituationTaskStateTalkToPlayer'] = {
            fields = {
                TalkID = { extensions = { { type = 'linked_talk_event' } } },
            },
        },
        ['app.TalkMonologueSelector'] = {
            fields = {
                _NpcTiming = { extensions = { { type = 'parent_field_conditional', field = '_NpcIsUseTiming', value = true } } },
                _NpcSituationTalkId = { extensions = { { type = 'parent_field_conditional', field = '_NpcIsSetSituationId', value = true } } },
                _PawnCategoryGroup = { extensions = { { type = 'parent_field_conditional', field = '_UsePawnCategoryGroup', value = true } } },
            }
        },
        ['app.NextNodeCandidate[]'] = {
            toString = function (value) return to_string_expose_single(value, 'app.NextNodeCandidate') end
        },
        ['app.NextNodeCandidate'] = {
            fields = {
                _NextNodeId = {
                    extensions = {
                        { type = 'next_talk_node_picker' }
                    }
                }
            },
            toString = function (value)
                return 'Next node: ' .. value._NextNodeName
            end
        },
        ['app.ChoiceSegmentNode'] = {
            extensions = { { type = 'talk_choice_segment_lookup' } },
            fields = {
                _DialogueList = { force_expander = false },
                _SegmentName = { extensions = { { type = '_talk_event_segment_name_warning' } } }
            }
        },
        ['app.TalkEventDialogueUserData.Segment'] = {
            fields = {['<DialogueList>k__BackingField'] = { import_ignore = true, ui_ignore = true }}
        },
        ['app.TalkEventDialogueUserData.Dialogue[]'] = {
            array_expander_disable = true,
        },
        ['app.TalkSegmentNode'] = {
            extensions = { { type = 'talk_node_segment_lookup' } },
            fields = {
                _SegmentName = { extensions = { { type = '_talk_event_segment_name_warning' } } }
            }
        },
        ['app.CommonNpcTalkNode'] = {
            -- extensions = { { type = 'npc_talk_node_link' } } -- TODO: handle npc app.TalkMonologueSelector
        },
        ['app.PawnTalkNode'] = {
            extensions = { { type = 'pawn_talk_node_link' } }
        },
        ['app.PawnTalkMonologueCategoryData'] = {
            fieldOrder = {'_Name', '_NameHash', '_Segments'},
        },
        ['app.te.condition.TalkEventSelectConditionList.TalkEventSelectCondition'] = {
            fields = {
                _Condition = { force_expander = false } -- TODO: automatically sync enum and _Condition classname, since they probably need to be
            }
        },
        ['app.PawnTalkMonologueSegmentData[]'] = {
            toString = function (value) return to_string_expose_single(value, 'app.PawnTalkMonologueSegmentData') end
        },
        ['app.PawnTalkMonologueSegmentData'] = {
            toString = function (value)
                -- TODO: figure out what the game does with segments that have no candidates (e.g. 30080, pawn talk node 2, PawnTalk_RUB_GuideSpot_01)
                if value._Candidates:get_size() == 1 then
                    return helpers.to_string(value._Candidates, 'app.PawnTalkMonologueMessageData')
                end
                return value:ToString()
            end
        },
        ['app.PawnTalkMonologueMessageData[]'] = {
            toString = function (value) return to_string_expose_single(value, 'app.PawnTalkMonologueMessageData') end,
        },
        ['app.PawnTalkMonologueMessageData'] = {
            fields = {
                _MsgId = ui.handlers.common.helpers.translatable_guid_field
            },
            toString = ui.handlers.common.helpers.tostring_field_translator('_MsgId')
        },
        ['app.TalkEventChoice'] = {
            fields = {
                _ChoiceId = ui.handlers.common.helpers.translatable_guid_field,
            },
            toString = ui.handlers.common.helpers.tostring_field_translator('_ChoiceId', 'Choice: ')
        },
        ['app.TalkEventChoice[]'] = {
            extensions = { { type = 'talk_choice_segment_copy' } }
        },
        ['app.TalkEventDialogueUserData.Dialogue'] = {
            fields = {
                _MsgId = ui.handlers.common.helpers.translatable_guid_field
            },
            toString = function (value)
                local speakerId = value._SpeakerId
                local speaker = speakerId and enums.get_enum('app.CharacterID').get_label(speakerId) or 'Unknown'
                return speaker .. ': ' .. utils.translate_guid(value._MsgId)
            end
        },
        ['app.DecisionPack'] = {
            force_expander = true,
            extensions = { { type = 'userdata_picker' } }
        },
        ['app.TalkEventSegmentNode'] = {
            abstract_default = 'app.TalkSegmentNode',
            fields = {
                _NodeType = { extensions = { { type = 'talk_segment_match_enum_node_type' } } }
            },
        },
    })
    definitions.override_abstract('app.TalkEventSegmentNode', {
        fields = {
            _NodeId = { extensions = { randomizable_uuid } },
            _NodeNameHash = { extensions = { randomizable_int } },
        },
        toString = function (value)
            return tostring(helpers.get_type(value)) .. ' : ' .. (value._NodeName or 'null') .. '   ' .. value._NodeId
        end,
    })

    definitions.override_abstract('AISituation.AISituationTaskStateBase', function(data)
        local extensions = data.fields and data.fields._TalkEventID and data.fields._TalkEventID.extensions or {}
        table.insert(extensions, 1, { type = 'linked_talk_event' }) -- insert at the beginning so the toggleable evaluates afterwards
        local myovers = {
            fields = {
                _TalkEventID = { extensions = extensions }
            },
        }
        definitions.merge_type_override(myovers, data)
    end)

end
