## Summary of things that need doing for custom quests
- core quest data
    - quest resources
    - possibly custom quest conditions (as in, lua-based conditions)
    - quest concierge settings (though they probably wouldn't sync with rented pawns so might be useless or maybe even bannable)
        - they're stored in a flag enum so uhhh yeah gl with that. we'd need local-only overrides or somehow expand the save data sent online (pawn ban imminent)
        - funniest solution, interop with a custom server for extended data so everyone with the mod installed can sync through that instead, bypassing capcom servers
    - quest logs
- talk events
    - dialog nodes
    - voices
- custom AIKeyLocations (not strictly necessary but would be helpful so we wouldn't need to find locations where there are none)

Other game features that might make use of the userdata editor
- custom lands, adding dungeons, modifying dungeons (new AIKeyLocations, GraphNodes, ...)
- custom items
- custom NPC entries

## Multi-catalog support
Assuming the overal game code architecture doesn't change, what are the things we need to verify / change if a DLC ever adds a second quest catalog?
- check if quest IDs and sudden quest/context IDs are still functionally unique
    - almost surely quest IDs will stay unique, would be too much refactoring
    - if not, refactor everything to support catalog + id or some sort of auto-namespacing ID for mod references (e.g. catalog01 is 1000000 + questId, catalog02 is 2000000 + questId)
    - see if sudden quest 118 is still duped
- app.QuestSceneCollector has a CatalogNameHash property
- any quest-catalog dependent entities need an additional catalog property in their import data; for any stored entities with unspecified catalog we can assume they're catalog1

## Research
What do we do with quest processors?
- in contrast to quest catalog data, these are individual files per quest, therefore they _could_ be edited via direct userfile + pfb manipulation
    - it's kinda messy with any of the existing tools though and prone to messing up on its own soo...
    - we can hook into the register method and modify them there which should work effectively identical to having edited the files directly except cleaner

How do escort quests work for NPCs?
- AISituationTaskStateFollowPlayer might help

How do "lead the way" things work for NPCs?

Ian (looking for his brother in melve)
- NPCNavigationController._hasQuest = true
- listed in NPCManager.TaskGuideFollowIdleNPCDict
- NPCHolder.NPCBehavior.requestAccompany() ?
- NPCHolder.NPCBehavior.Accompany.AccompanyPLPartyController
    - CurrentExecuteRqeuest.RequestNode layer = 0, function = 0
    - CurrentExecuteRqeuest.RequestTask, CurrentRequest Layer = 2 (QuestTask), Function = 510 (all)
- There's some static flag combinations for accompany in NPCAccompanyPLPartyController.Function*
- Quest role guid 667e948a-eb9e-40c7-96c6-af0cfd02f483
- another NPC ch310023 has the role guid 7902a80c-c36a-4a3d-9bb9-c92bbab33a03, probably the brother

app.AISituationTask (accessible from app.AISituationAgentNPC._CurrentTaskList):
- has a TaskStateFlow array (AISituationTaskStateBase[])
    - AISituationTaskStateGuide flow:
        - guard = -1
        - targetIndex = 0
        - has a DestinationPointList - #0: qu020050_003(2253)
        - DestinationPosition: (64.725, 246.974, -2738.616)
    - AISItuationtaskStateCheckCommonFlag flow:
        - flag0(1)
        - TaskStateEactionType = flag00(1)
        - ownerSituation = qu020050
- ExecutableRoleList has one item condition which ends up evalling as `charaId == ch310022`
- TaskData appsystem/AI/Situation/TaskData/AITask_1_18_002.user
-- NOTE: AITask_1_18_002 doesn't work through sdk.create_userdata...
- OwnerSituation qu020050, flags mostly equal to the AISItuationtaskStateCheckCommonFlag flow ones
- AgentList seems to be a mapping of "role guid" and character

called on load while his quest is active:
app.quest.action.NpcControl.issueTask()
-> AISituation.AISituationBase.AISituation.AISituationBase.forceStartTaskToAgent_Quest(app.AISituationTask, AISituation.IAISituationAgent)
-> app.NPCUtil.requestAccompany(app.CharacterID, app.NPCAccompanyPLPartyController.Request)
    - calling just this does nothing, maybe if the NPC is spawned


Glyndwr escort to the Arbor:
- flow is only one AISituationTaskStateGuide item
- Glyndwr gets Original2 status while he's escorting you to the arbor, also _NoDie (`Process.QuestAction._Vital`)
- Gets task resource AISituationTaskEntity AppSystem/AI/Situation/TaskData/AITask_1_32_013.user

Glyndwr in cave to rescuie Doireann
- flow: AISituationTaskStateFOllowPlayer, target: qu030070_012, StateActionType: Flag00
- qu030070_005 Doireann while rescuing her out
- end condition 394

Glyndwr affinity escort:
- NpcRegisterKey hash 3131221329
- changing suddenquest intervanlHour or the context data _IntervalTime._Day on a running quest changes nothing

AISituationTaskStateGuide info:
- IsRun, IsDash work for allowing/disallowing them to do those actions
- can't directly edit State because it gets refreshed per frame
- DestinationPosition seems editable fine

Might be able to disable ferrystoning - QuestManager.FerrystoneDisableDict
Figure out how to force an NPC to stay perma asleep (Doireann during her rescue quest)
    - StatusConditionController has a app.StatusConditionCtrl.StatusNoAutoClearEnum set to DisableRestoration + Sleep
    - though the sleep also gets force-reapplied again from somewhere even if we remove that flag
    - I think she had the Original1 / Original2 status

- app.NPCHolder.Flag.DenySchedule enum flag


- maybe we can fix Sara's schedule during UW so she doesn't wander off all the time

Force set position of despawned NPCs, how?
- NPCHolder has the correct UniversalPosition, but it's read only
- I have no idea where it's getting the value from
- both Containers InitialPosition is set to where they despawned, but editing it does not change anything
- they have a NPC schedule override defined pointing to the despawn position, but changing it also does nothing
    - the schedule however gets reset back next frame, so following the source there might work
    - app.NPCScheduleCurrent constructor isn't getting called per frame so it's being directly edited then
    - schedule does not update if we skip the NPCManager.refreshNPCSchedule method, but that does not fix our issue either
- CharacterManager:updateContextPosition(uniqueId, targetPos) also exists, but also doesn't solve our issue
- the value is correctly updated in the context db as well...
- app.GenerateInfoContext has position = (0,0,0) for the NPC so that's not it either
- maybe: app.CharacterQuestContext

app.GenerateInfo.GenerateInfoContainer.applyGenerateSettingContainer(app.GeneratorCategory, app.GenerateSetting.GenerateSettingContainer, app.GeneratorID, app.UniqueID, app.CharacterID, via.Position, via.Quaternion, via.vec3)

How to define a new quest:
needs processors:
- Process: NotifyStartQuest, QuestID = -1 (means it starts immediately with no prior conditions, I think)
- if we want preconditions, they need to be done through more processors
    - possibly use a ScriptSetVariable and set that whenever we feel like it through lua stuff

## Resource tasks
- NPC escort for sudden quests: AppSystem/AI/Situation/TaskData/AITask_1_2_059.user

## Managing quest processor behavior
- TaskGuide type of processor:
    - can disable guide by changing Process.CurrentPhase = CancelAction
        - this then cleanly resets everything including removing the task guide flag and has the NPC forget this ever happened
        - processor phase changes to canceled
    - can re-enable by setting phase to standby - it gets automatically enabled _somehow_
        - ProcessEntity.setup() called from QuestProcessor.update()

- to add a new NpcControl+TaskGuide processor
    - switching processor state to setup crashes the game
    - switching processor state to standby crashes the game IF we've added it to the ProcessorFolderController; otherwise does nothing
    - switching processor state to waiting does nothing, IsSetupped still false so it probably shouldn't work?
    - we probably need the processor to flip to waiting state automatically after it's set to standby and not set it directly
        - QuestManager.registerUpdateProcessor is not enough -- this is done automatic on quest processor phase change
        - ProcessorFolderController._ProcessorList:Add() makes it crash already on switching to standby;
            - probably because it changes it to waiting and then the same crash happens as if I had set it to waiting on my own
        - a hook on QuestProcessor:set_CurrentPhase does not get triggered and the setter is private, so the change is probably somewhere local
        - TriggerObject maybe?
    - if added to proc folder:
        - errors on setup or standby
        - no error on waiting, completed, canceled
    - if not added:
        - errors on setup
        - no error on waiting, completed, canceled
    - scratch the above, it works now? wha...
        - I guess setting the base QuestActionBase class _Param array fixed it
        - uninitialized -> (manually) standby -> (automatic) setup/waiting/completed
        - to make it not automatically get completed (FollowPlayer task):
            - add _Param._Task.FinishTaskCondition and _Param.FinishConditionParam (are these supposed to be the same object?)

- adding a whole new quest / processor folder
    - we can define the whole quest in the scene file if you're feeling "max performance"-ey but it's hard to edit with all the nesting and clunky tools so...
    - copy the appdata/quest/qu01/qu010010.scn and resident.scn files
    - qu010010.scn contains:
        - 1x folder referencing the Resident.scn file (which then contains all quest processors)
        - 1x QuestResourceCollector:
            - pointer to several "Env_999" folders contained in the Resident scene
            - each "Env" folder can contain 1 or "QuestResourceObject"s
            - these resources seem to then just get merged into the base Resident folder
        - 1x QuestProcessorRegister: points to the Resident folder
        - 1x QuestController: required core object
    - resident.scn contains:
        Nx QuestProcessor:
            - we can dynamically create these so the .scn file can leave these out, ideally we only add a minimum Start and End notify via scn file
            - maybe even just a start and add the end notify via ingame editor instead
            - these represent all actionable quest logic

- manually adding without any scn files?
    - currently impossible because we can't create new folders through REF, however just the rough idea of the folder structure:
    - example quest id 060069
    - folder `qu060069`
        - app.QuestController
            - QuestID: 60069
        - app.QuestProcessorRegister
            - needs a reference to the QuestController GameObject (within start() already?)
        - app.QuestResourceCollector
        - folder `Resident`
            - 1-N app.QuestProcessor instances

- adding custom lua-based conditions and logic
    - add new lua script entity type
    - adding custom Lua-based AI Situation tasks
        - I'm thinking we hook into AISituationTaskStateResetOrderTarget
            - reasoning: seems like a one-frame task for the basegame, resets orders and finishes the task
            - issues: only overrides onUpdate and not the other callbacks; can this be solved by using sdk.hook_vtable?
        - abuse the _TalkEventID to some non-existing value that we can use as a signal
        - abuse the _TaskStateActionType enum to set some sort of ID we can use to find the right lua function

    - for custom quest conditions (app.quest.condition.ConditionParamBase)?
        - CheckTakeOxcartSeatParam; _Type > 50 (use for script ID)

## Creating a completely new quest

Shortest / simplest basegame quest: qu010010
- natives\stm\message\quest\qu010010.msg.22
- natives\stm\appdata\quest\qu01\qu010010\qu010010.scn.20
- natives\stm\sound\scene\quest\qu010010.scn.20
- natives\stm\event\talkevent\talkeventresource\qu010010.user.2
- natives\stm\appsystem\ai\situation\generateparameter\questsituation\questsituationparam_qu010010.user.2
- natives\stm\appsystem\gui\prefab\textureholder\questthumb\questthumb_qu010010.pfb.17
- natives\stm\appdata\quest\qu01\qu010010\resident.scn.20
- natives\stm\gui\ui99\ui0605\tex_ui0605_qu010010_im.tex.760230703

confirmed optional files through vanilla quests (qu010030):
- not all quests have questRoles (roledata/situationrolecategory_quest/*), we should be able to just insert those on runtime anyway
- there's also soundbank files (stm/sound/wwise/*, streaming/sound/wwise/*, stm/sound/resource/quest/*)
- also camera/userdata/shotcamera, I guess cutscene camera timelines?
- npc_voice\npc_quest are optional (confirmed by qu010010 lacking them)
- pawn_voice/pawntalk_quest/* files
- sound/scene/quest/* files: quest.scn.2 contains refs, but it doesn't contain any 11** or 12** quests
    - does contain qu010010 though
- questsituationparam_: 011**, 012** have none
- stm/event/talkevent/talkeventdialoguecatalog.user.2: does not contain anything for qu010010 and it doesn't die on activation
    - qu010010 does have a user file inside the talkeventresource subfolder though, even if unused and empty

modified: stm\appsystem\scene\quest.scn.20
created files (copied from qu010010):
- stm\appdata\quest\qu8000\qu8000.scn.20  (MAYBE i need to put it into the same subfolder structure as basegame quest have?)
- stm\appdata\quest\qu8000\resident.scn.20
- adding these files just because the basegame (qu010010) has them, dunno if they fix anything, dunno if i need to reference them from somewhere; still crashes after:
    - stm\appsystem\ai\situation\generateparameter\questsituation\questsituationparam_qu8000.user.2
    - stm\message\quest\qu1800.msg.22
    - stm\appsystem\gui\prefab\textureholder\questthumb\questthumb_qu010010.pfb.17
    - stm\appsystem\gui\ui99\ui0605\tex_ui0605_qu8000_im.tex.760230703

Sound file references:
- the root sound definition for quests (I think) is in sound/scene/quest/quest.scn.20
- each quest has its own sound scene in that same folder
- these quest sound scenes can then have multiple of its own references
    - app.WwiseContainerApp -> sound/resouce/dialog/*
    - app.QuestCharacterVoiceContainerRegister, app.QuestPawnVoiceContainerRegister components that probably just do `getComponent<WwiseContainerApp>()` and register all of those

Open issues:
- After adding a new folder to the root quest folder in the scene file, it doesn't get collected into the QuestSceneCollector
    - possibly linked to not being in the actual enum but can't tell for sure
    - just from what REF shows, it basically does `foreach(folder:get_Folders()) -> dictionary.TryInsert(questID, folder)`
    - but I can't tell how they're transforming a "qu010010" folder into an integer to do dictionary.TryInsert(10010, folder)
        - my guess would be that they do a `Enum.TryParse(typeof(app.QuestDefine.ID), folder_name)` to get the quest ID number
        - the alternative is that they do some sort of "peek" into the quest folder but that seems unlikely
    - I can remove an _active_ quest from the quest scene and it'll run fine and just not collect it, no crash, quest still active otherwise
    - I can hook into app.QuestSceneCollector:start prehook, add it there, and it will propagate to the quest tree as well
        - If the tree node conditions would make the quest valid, it still crashes after

- As soon as the new quest is activated, the game crashes
    - this happens before any quest's QuestProcessorRegister:start() gets called if we force collect the new folder
    - if we force update the quest tree, QuestProcessorRegister:start() is called and finished before crashing (console log posthook prints fine)
    - quest entity looks identical to a basegame inactive one
    - from this, I would assume the issue happens in some .update() method somewhere

### Hash generation
- there's a StringExtension.hash() method
```lua
local hasher = sdk.find_type_definition('app.StringExtension'):get_method('hash')
local hasher2 = sdk.find_type_definition('via.str'):get_method('makeHash(System.String)') -- both return the same results
local hash = hasher:call(nil, 'a')
```

-2128831035

### Message resolution
- `via.gui.message.get(System.Guid)`
```cs
public string get(System.Guid guid)
{
    wchar_t[]? charBuffer = sub_1404D2E40(guid);
    string? result;
    if (charBuffer != null) {
        var len = strlen(charBuffer);
        result = sub_144A18550(len, charBuffer, 0); // allocates a new System.String from str
    }
    if (!result) {
        // then it does a bunch of bullshit, possibly some error logging
        // and the result is just null
        result = null;
    }
    return result;
}
public wchar_t[] sub_1404D2E40(System.Guid guid) // name suggestion: getTranslationForCurrentLanguage()
{
    struct MessageAccessData // via.gui.MessageAccessData
    {
        System.Guid x10_Guid; // 0x10
        string x20_Msg_Probably; // 0x20
    };

    struct MessageEntry
    {
        MessageEntry* x8_self; // 0x8
        MessageEntry* x10_next; // 0x10
        byte x19_Valid; // 0x19
        System.Guid x20_Guid; // 0x20 Guid (int 0x20, short 0x24, short 0x26, ulong 0x28)
        int x28_PageCount; // 0x28
        int x2c; // 0x2C
        void* x30_ptr_arr; // 0x30 likely string
        int x38; // 0x38    page offset?
    };

    MessageEntry rootMessage = qword_14F84E5B0 + 0x40;
    sub_144F55D00(rootMessage, out MessageEntry message, guid);
    if (message == rootMessage) return wchar_t[0];

    var some_object_array = (message->x30_ptr_arr);
    var langTranslations = some_object_array[message->x38]->x38_other;
    var len = langTranslations.count;
    if (len == 0) return wchar_t[0];
    var curLanguage = *(_DWORD *)(qword_1501C5490 + 20); // not 100% on the name
    while (langTranslations[i] != curLanguage) {
        i++;
        if (i > len) return wchar_t[0];
    }
    if (i == -1) return wchar_t[0];
    return langTranslations[i]->idk;
}
public MessageEntry sub_144F55D00(MessageEntry baseEntry, out MessageEntry resultEntry, System.Guid guid)
{
    // stuff
    MessageEntry v4 = baseEntry;
    var v7 = baseEntry->x8;
    if (!v7->x19_Valid) {
        uint mData1 = a3->mData1;
        do
        {
            var doelse = false;
            var v7guid = v7->x20_Guid;

            // note: yes, the decompiled code looks this ugly
            // seems like it's basically an ordered guid linked list lookup
            if (v7guid->mData1 < mData1) {
                v7 = v7->x10_next;
                continue;
            }
            if (v7guid->mData1 == mData1) {
                a1 = guid->mData2;
                if (v7guid->mData2 < guid->mData2) {
                    v7 = v7->x10_next;
                    continue;
                }
                if (v7guid->mData2 == guid->mData2) {
                    if (v7guid->mData3 < guid->mData3) {
                        v7 = v7->x10_next;
                        continue;
                    }
                    if (v7guid->mData3 == guid->mData3) {
                        if (v7guid->mData4 < guid->mData4) {
                            v7 = v7->x10_next;
                            continue;
                        }
                    }
                }
            }

            // else
            v4 = v7;
            v7 = new MessageEntry(v7); // copy
        } while (!v7->x19_Valid);
    }
    if (!v4->x19_Valid && guid == v4->x20_Guid) {
        resultEntry = v4;
    } else {
        resultEntry = baseEntry;
    }
    return resultEntry;
}
public string sub_144A18550(int len, string str, bool forceSomething) // assumption: does some string arg substitution / interpolation
{
    string result;
    int str_mem_size = 2*len + 22;
    if (forceSomething || str_mem_size > 512) {
        result = sub_144A182B0(str_mem_size); // allocateString() ?
    } else {
        // some magic shit, maybe an interned string lookup
    }
    return result;
}
```

## Variable name-hash mapping:
### Solved
3941677146 - questStarted (not sure what they're OG calling it but it seems to be serving this purpose)
3948363880 - questEnded
2950354061 - acceptedBrantRequest
- all of the variables with this hash seem to be pointing to the big brant conversation tree at the inn - te5010085_000 (295), with varying EndNo parameters. I assume they're separate "has accepted this request" checks.
    30040: talk event = te5010085_000 (295), EndNo = 27
    10090: inactive processor, "qu10090_014"
    10100 Disa's plot: checks variable of 10085: "qu10085_010": 3033540941, which checks the same 295 talk event, EndNo = 12 (?)
    10120: check variable of 10085: "qu10085_012": 1975555422, which checks the same 295 talk event, EndNo = 14

424930563 - questStarted2
    lots of inactive processors
    11030: triggers NotifyStartQuest
    20130: triggers NotifyStartQuest
    20220: triggers NotifyStartQuest

607502282 - questStarted3 probably
    10090: inactive
    12030: triggers NotifyStartQuest
    30080: triggers NotifyStartQuest
    30150: triggers NotifyStartQuest

1846136670 - questStarted4
1356650875 - questStarted5
    20040: inactive processor
    20080: triggers NotifyStartQuest

1792196096 - questEnded2

2466516101 - ? seems to be related to UW evacuation
    20260: PlayEvent, with prereq to a NotifyStartQuest

sdk.get_managed_singleton('app.TalkEventManager')

### Unsolved
538544633 - ?
    10140_003: inactive processor
    10150: checks for QuestTalkResultVariable te5010140_060

704943265 - ?
    30160: PlayEvent
    20040: inactive
    20080: null condition
    20340: inactive

DUPLICATE var hash: 3102449247
    10145: some trigger, missing condition in my current save,
    10190: CheckCollidersParam (resourceID 2), precondition processors 1847169597, 3313707545

298328363, 1102476689 - ?
    10080 seat of the sovran
    10070:

791773390:
    all 3 processors inactive

3893600297:
    20040, 20250: processors inactive

2905303821: qu20120#0 exclusive: PlayEvent action

4273234258
    20270: unset trigger; prereq of prereq of prereq depends on lamond conversation
    20290: unset trigger; PlayEvent prereq, with another PlayEvent preqreq (result -1), with NotifyStart pre-req
    20460: inactive
    30100: unset trigger; with several CheckQuest + 1 checkColliders pre-condition

1u20120_000 -> qu20120_010
process: null trigger (tf does that do?)
qu20120_010 -> 1u20120_004
process: playEvent, null work

processor 356940163
- process trigger condition includesNPCArrivedLocation

## Processor labels
qu030070_Processor_288608521 - Glyndwr is within 15m of qu030070_003 (sacred arbor entrance)
qu030070_Processor_2880639316 - NPC control - Glyndwr escort to qu030070_020 and qu030070_003 (is 003 a fallback for despawn?)
    task: AppSystem/AI/Situation/TaskData/AITask_1_32_013.user

## Quest / Processor ResultNo values:
- 1 - Quests sometimes have resultNo = 1 (20440, 20391); failure / canceled?
- 0 - usually (always?) means "complete / finished / true"
- -1 - means incomplete
- haven't seen other values yet

### Research


```lua
local sdm = sdk.get_managed_singleton('app.SaveDataManager')
-- app.GlobalUserDataManager contains _OpenedLocalAreaBit which is probably a list of areas the player has been to OR has unlocked the door to, would need to verify which areas are in there
local dbms = sdk.get_managed_singleton('app.ContextDBMS')
local cdb = dbms.OfflineDB
local cdb = sdk.get_managed_singleton('app.ContextDBMS').OfflineDB
-- app.ContextDatabase.RecordInfo getRecordInfo(app.ContextDatabaseKey key)
local get_save_context = function (key) return sdk.get_managed_singleton('app.ContextDBMS').OfflineDB:getRecordInfo(key) end
local get_savekey_character = function (charaId)
    return sdk.get_managed_singleton('app.ContextDBMS'):call('getContextDatabaseKey(app.IContextDatabaseIndexCreator, app.CharacterID)', cdb.IndexCreator, charaId)
end
-- used for GenerateController save context data
local get_savekey_uniqueId = function (uniqId)
    return sdk.get_managed_singleton('app.ContextDBMS'):call('getContextDatabaseKey(app.IContextDatabaseIndexCreator, app.UniqueID)', cdb.IndexCreator, uniqId)
end
-- used for network (online pawns) characters (app.PlayerStatusCalculatorHolder->OnlineCalculators)
local get_savekey_uniqueId = function (id)
    return sdk.get_managed_singleton('app.ContextDBMS'):call('getContextDatabaseKey(app.IContextDatabaseIndexCreator, System.Int64)', cdb.IndexCreator, id)
end

-- quest manager dict id: 1777420983
```


Swapping an NPC's weapon/class
```lua
-- 1416 = crimson teeth, wp03_013_00
-- 240278635 = lennart
-- 4284266652 wp03_013_00

-- actual procedure
-- 1. (from title screen) modified a NpcQuestOverrideData to target lennart, change his combat params to job04, left weapon none, right weapon wp03_013_00
-- 1.2. also removed any conditions from it just in case
-- 2. load game
sdk.find_type_definition('app.ItemManager')
    :get_method('getItem(System.Int32, System.Int32, app.CharacterID, System.Boolean, System.Boolean, System.Boolean, app.ItemManager.GetItemEventType)')
    :call(sdk.get_managed_singleton('app.ItemManager'), 1416, 1, 240278635, false, false, false, 1)
sdk.get_managed_singleton('app.ItemManager'):requestRightEquipWeapon(sdk.get_managed_singleton('app.NPCManager').NPCHolderDic[240278635]:get_chara(), 4284266652, false)
sdk.get_managed_singleton('app.ItemManager'):requestLeftEquipWeapon(sdk.get_managed_singleton('app.NPCManager').NPCHolderDic[240278635]:get_chara(), 0, false)

sdk.get_managed_singleton('app.QuestManager').CurrentNpcOverrideDict[240278635]

-- misc stuff
local lennartNpcHolder = sdk.get_managed_singleton('app.NPCManager').NPCHolderDic[240278635]
local lennart = sdk.get_managed_singleton('app.NPCManager').NPCHolderDic[240278635]:get_chara()
local lennartWeapon = sdk.get_managed_singleton('app.NPCManager').NPCHolderDic[240278635]:get_chara().WeaponContext
local lennartHuman = sdk.get_managed_singleton('app.NPCManager').NPCHolderDic[240278635]:get_chara():get_Human()
local lennartContext = sdk.get_managed_singleton('app.NPCManager').NPCHolderDic[240278635]:get_chara():get_Context()
lennartHuman:prepareAdditionalWeaponsAndItems(4284266652)
sdk.get_managed_singleton('app.ItemManager'):requestLeftEquipWeapon(sdk.get_managed_singleton('app.NPCManager').NPCHolderDic[240278635]:get_chara(), 0, false)
sdk.get_managed_singleton('app.ItemManager'):requestRightEquipWeapon(sdk.get_managed_singleton('app.NPCManager').NPCHolderDic[240278635]:get_chara(), 4284266652, false)
sdk.find_type_definition('app.ItemManager'):get_method('getItem(System.Int32, System.Int32, app.CharacterID, System.Boolean, System.Boolean, System.Boolean, app.ItemManager.GetItemEventType)')
    :call(sdk.get_managed_singleton('app.ItemManager'), 1416, 1, 240278635, false, false, false, 1)
sdk.find_type_definition('app.ItemManager'):get_method('getHaveNum(System.Int32, app.CharacterID)')
    :call(sdk.get_managed_singleton('app.ItemManager'), 1416, 240278635)

-- app.HumanEnemyParameterBase.NPCCombatParamTemplate.Job04 = 30
-- note, calling this directly instead of dealing with it through quest npc overrides seems to only break the AI (stops attacking altogether despite equipped weapon)
-- maybe we just need to update the character's active job as well
sdk.get_managed_singleton('app.NPCManager').NPCHolderDic[240278635]:get_chara():get_Human().HumanEnemyController:changeNPCCombatTable(30)
```

### Custom talk event debugging stuff
issues to resolve:
- NPC cyberpsychosis (possibly same issue with non-custom talk events?)
- UI input death and task cancel on custom talk events
    - maybe because requestSpeech() fails? -- look into what this does !!!!!!!!!!!!!!!!!!!!!!!!

call chain:
engine
app.AISituationAgent.update()
app.AISituationTask.onUpdate()
app.AISituationTaskStateTalkToPlayer:onUpdate()

figure out what is changing the task

## Debugging quest behaviour issues
If a scn file provided quest processor isn't initializing on its own (most obviously, if the ProcessorArrayIndex == -1), check if the v0 property in the .scn file is set to 0. If so, set it to 1. This seems to be an IsEnabled flag.

## Debugging crashes
Most straightforwardly, make a dump of the exe for IDA or find someone who has one and ask them nicely.

Else, try requiring the `quest_utils._debugging` lua file, maximize the console on a separate screen, and do a printscreen immediately when it crashes (or record a video). In theory any crashable method should be hooked from there and if one of the last log statements is missing a ` -> ....... [return]` entry, that's likely where it crashed.

Try digging into what else that method calls. Maybe do a full json dump of whatever objects where handled in the crashing method (`object_json_dump(obj)` in _debugging.lua) and see if any referenced fields are null.

*current issues:*
- things to figure out:
    - why does NpcControl.FinishCondition have null fields, and why do the fields get set to not null on a script reset

## Overriding enums

Issue: we don't have a way to modify an out parameter value through lua. would need a c++ plugin to fix it globally.
```lua
local true_ptr = sdk.to_ptr(true)
sdk.hook(
    sdk.find_type_definition('System.Enum'):get_method('TryParseInternal(System.Type, System.String, System.Boolean, System.Object)'),
    function (args)
        local enumString = sdk.to_managed_object(args[3]):ToString()
        local val = tonumber(enumString, 10)
        if val ~= nil then
            -- print('overriding enum return', sdk.to_managed_object(args[2]):ToString(), val)
            args[5] = sdk.to_ptr(sdk.create_int32(val))
            thread.get_hook_storage().arg = args[5]
            thread.get_hook_storage().result = val
            -- return sdk.PreHookResult.SKIP_ORIGINAL
        end
    end,
    function (ret)
        if thread.get_hook_storage().result then
            return true_ptr
        end
        return ret
    end)
```

Alternatively, hook into every method that does enum TryParseInternal. We should be able to find them via IDA by:
1. find a method that calls TryParseInternal with the enum type in question
2. on TryParseInternal: jump to xref (X) -> copy all
3. on the offset given as param 2 of the call (e.g. off_14FCBC1B0): jump to xref (X) -> copy all
4. cross reference which methods appear in both lists, those are the likely culprits
5. possibly need to repeat with any functions that just passthrough the parse call (Enum.Parse, sub_##)

```
System_Enum__TryParseInternal582242 -- this is the main implementation that every enum parse call uses, it's probably inlined to this for most callers
System_Enum__TryParse582237
System_Enum__TryParse582238
System_Enum__Parse582233
```

### Current enum notes (2024-07-12 patch):
off_14FCBC1B0 - QuestDefine.ID (app_QuestSceneCollector__start)
TryParse:
    /probably important
    app_SoundVoiceManager__getQuestIDFromPawnMsg533063
    app_SoundVoiceManager__getQuestIDFromMsgId533123
    app_QuestCharacterVoiceContainerRegister__awake796492
    app_GUIBase__getQuestThumbnail407624
    /we can manually do these changes easily with a hook
    app_QuestSceneCollector__start624804
    app_QuestResourceCollector__registerResource796986
    /probably less important
    app_PLPartyTalkController__getMostRecentQuestCategory336708
    ...

GetValues:
    app_QuestDefine___cctor1234
    ...
GetName:
    app_QuestDeliverData__get_ID796730
other:
    sub_144A188A0(a1, (__int64)off_14FCBC1B0, 0)
        -- it's also called with a different type (off_14FCD1B10) sometimes and passed into a List constructor; i think it returns an array of enum (values/names/somethings)
        0x8 is likely a count, 0x10 an array?
        0x10 is many times (always?) reassigned to some integer value after getting called
        -- maybe some sort of ToArray() helper?
        usages:
            sub_144A188A0(a1, (__int64)off_14FCBC1B0, 0)[4] = v31;
                ???
                app_QuestLogManager__applyLoadSaveData309744
                app_quest_action_PlayEvent_TalkEventWork___ctor825977
        has some virtual method (returning a string):
            v6 = sub_144A188A0(a1, (__int64)off_14FCB82E0, 0);
            v6[4] = *(_DWORD *)(a2 + 0x10);
            v7 = (*(__int64 (__fastcall **)(__int64, _DWORD *))(*(_QWORD *)(*(_QWORD *)v6 - 16LL) + 8LL))(a1, v6);
            System_Text_StringBuilder__Append500(a1, v4, v7);

off_14FCB82E0 - TalkEventDefine.ID (app_actinter_cmd_TalkTo__updateImpl)
TryParse:
    app_TalkEventManager__registerCastListCatalog378027
    app_TalkEventManager__getQuestIdFromTalkEventId378177
    app_actinter_cmd_TalkTo__updateImpl814012
other:
    sub_144A188A0(a2, (__int64)off_14FCB82E0, 0)
        sub_140980D20
        sub_140C04A30
        sub_140C04BC0
        sub_141046FD0
subroutines:
    sub_141DD3EC0
    sub_142DD5680
    sub_14324DF50
    sub_143BEBA70

## Potentially useful game pseudocode snippets
Not necessarily 100% accurate but these snippets should get the gist of that it's doing across...

app.QuestManager:getQuestAISituation()
```cs
foreach (var rootSit in AISituationManager.Instance._SituationMaster.RootSituationParamList) {
    int entryIdx;
    AISituation situation;
    if (rootSit.ChildSituations.Length > 0) {
        foreach (var childParam in rootSit.ChildSituations) {
            if (childParam is not QuestAISituationGenerateParameter questParam) {
                continue;
            }
            if (questParam.QuestId != questId) {
                continue;
            }
            if (AISituationManager.Instance._SituationMaster._SituationDictionary.TryGetValue(questParam.Guid, out situation)) {
                break;
            }
        }
    }
    return situation;
}
```

NpcControl:onSetup()
```cs
var baseParams = base._Param;
CurrentPhase = Uninitialized;
var newParam = baseParams[0];
if (baseParams == null || baseParams._items == null || /* I'm only assuming this is a type check */baseParams is not NpcControlParam) {
    newParam = null;
}
if (IsActive) {
    if (newParam != _Param) {
        if (newParam != null) something(newParam);
        var curParam = _Param;
        // source seems to be doing some sort of a thread-safe / atomic value change
        lock(null) { _Param = newParam; }
        if (curParam) something_else(curParam);
    } else {
        _Param = newParam;
    }

    var newNpcHolder = NPCManager.Instance.getNPCHolder(_Param._NpcID);
    // same pattern including exact same functions as for the _Param reassignment
    _NpcHolder = newNpcHolder;

    var questId = this.QuestID;
    _RegisterNPCLayerKey = string.Format(Enum.GetNames()[questId], something, something);

    if (questId != -1) {
        npcLayer = questId <= 19999 ? 2 : 1;
    }

    NPCManager.Instance.requestAddNPCLayer(_Param._NpcID, _RegisterNPCLayerKey);
    var gameObject = this.GameObject;
    var finishParam = _Param._FinishCondition;
    var newFinishCondition = new QuestCondition(finishParam, gameObject, finishParam.Conditions, finishParam.Operator);
    if (this.Something >= 0 && FinishCondition != newFinishCondition) {
        // note: thread-safe assignment again
        FinishCondition = newFinishCondition;
    } else {
        FinishCondition = newFinishCondition;
    }
    FinishCondition.setup()
    if (!_Param._Generate._SkipControl) {
        GenerateCondition = new QuestCondition(_Param._Generate, ...);
        GenerateCondition.setup();
    }
    // repeat for the other _SkipControl fields
    if (_IsExclusive) {
        _IsExclusive = false;
        CurrentPhase = CheckTrigger;
        if (_TriggerObject == null) {
            TriggerManager.setExecLine(_TriggerObject, app.TriggerManager.ExecLine.Free);
        }
    }
}
```


app.actinter.cmd.TalkTo:updateImpl()
```cs
if (this.Target == null) return ReturnCommand.Break;
var targetCharacter = this.Target.Character;
if (targetCharacter == null || !targetCharacter.Active) return ReturnCommand.Break;
if (CachedSpeechController == null || !CachedSpeechController.Active) return ReturnCommand.Break;
if (RoutineType != Interact) {
    if (RoutineType == End) {
        return TalkingID == (some_constant) ? 1 : 0;
    }
    return ReturnCommand.Break;
}
app.AIBlackBoardAggregate agg = this.AIBBCtrl.BBAggregate;
// app.AIBlackBoardCollection<app.BBKeys.Situation.AT, app.BBKeys.Situation.ATList, app.BBKeys.Situation.Bool, app.BBKeys.Situation.Float, app.BBKeys.Situation.GO, app.BBKeys.Situation.GOList, app.BBKeys.Situation.Int, app.BBKeys.Situation.String, app.BBKeys.Situation.Vec3, app.BBKeys.Situation.Vec3List, app.BBKeys.Situation.BoolTrg, app.BBKeys.Situation.Position, app.BBKeys.Situation.Ulong>
var situation = agg?.Situation;
string paramString = situation.getValue(app.BBKeys.Situation.String.Param01);

// TryParseInternal(System.Type, System.String, System.Boolean, System.Object)
if (!Enum.TryParseInternal(typeof(app.TalkEventDefine.ID), paramString, false, out var talkEventId)) {
    this.TalkingID = 0;
    return ReturnCommand.Break;
}
this.TalkingID = talkEventId;
if (!NPCUtil.canStartTalk(this.Character, this.TalkingID, true)) {
    return ReturnCommand.Break;
}
if (CachedSpeechController.requestSpeech(this.TalkingID, this.Character, this.Target.Character, null, true)) {
    this.Routine = RoutineType.End;
}
// unlock(string user, app.OccupiedManager.LockType locktype)
app.OccupiedManager.Instance.unlock(some_constant2, app.OccupiedManager.LockType.PreTalk);
return ReturnCommand.Continue;
```

```lua
local NPCUtilcanStartTalk = sdk.find_type_definition('app.NPCUtil'):get_method('canStartTalk')
local OccupiedManager = sdk.get_managed_singleton('app.OccupiedManager')
local ReturnCommand = enums.get_enum('app.actinter.Define.ReturnCommand')
local RoutineType = enums.get_enum('app.actinter.cmd.TalkTo.RoutineType')
local pretalk_str = sdk.create_managed_string('PreTalk')
sdk.hook(
    sdk.find_type_definition('app.actinter.cmd.TalkTo'):get_method('updateImpl'),
    function (args)
        local this = sdk.to_managed_object(args[2])
        if this:get_Target() == nil then print('no target') return hook_return(ReturnCommand.labelToValue.Break) end
        local targetCharacter = this:get_Target():get_Character()
        if targetCharacter == nil or not targetCharacter:get_Enabled() then print('no targetchara') return hook_return(ReturnCommand.labelToValue.Break) end
        if this.CachedSpeechController == nil or not this.CachedSpeechController:get_Enabled() then print('no speech ctrl') return hook_return(ReturnCommand.labelToValue.Break) end
        if this:get_Routine() ~= RoutineType.labelToValue.Interact then
            if this:get_Routine() == RoutineType.labelToValue.End then
                --- TODO what are they comparing this against?
                -- *(_DWORD *)(qword_14F84E8D8 + 504)      qword_14F84E8D8 dq 5CD39470h
                -- I'm assuming it's TalkEventDefine.ID.None
                print('end routine')
                return hook_return(this.TalkingID == 0 and ReturnCommand.labelToValue.Next or ReturnCommand.labelToValue.Continue)
            end
            print('non interact')
            return hook_return(ReturnCommand.labelToValue.Break)
        end
        local agg = this:get_AIBBCtrl():get_BBAggregate()
        local situation = agg and agg:get_Situation()
        local paramString = situation:call('getValue(app.BBKeys.Situation.String)', 1)

        local talkEnum = enums.get_enum('app.TalkEventDefine.ID')

        -- replaced instead of Enum.TryParseInternal
        local talkEventId = talkEnum.labelToValue[paramString]
        if not talkEventId then talkEventId = tonumber(paramString, 10) end

        if not talkEventId then
            this.TalkingID = 0
            return hook_return(ReturnCommand.labelToValue.Break)
        end
        this.TalkingID = talkEventId
        if not NPCUtilcanStartTalk:call(nil, this:get_Character(), this.TalkingID, true) then
            print('cannot start')
            return hook_return(ReturnCommand.labelToValue.Break)
        end
        if method_requestSpeech:call(this.CachedSpeechController, this.TalkingID, this:get_Character(), this:get_Target():get_Character(), nil, true) then
            this:set_Routine(RoutineType.labelToValue.End)
        end

        OccupiedManager:unlock(pretalk_str, 11) -- 11 = app.OccupiedManager.LockType.PreTalk
        print('continuing...')
        return hook_return(ReturnCommand.labelToValue.Continue)
    end
)
```

app.SpeechController.requestSpeech(app.TalkEventDefine.ID, app.Character, app.Character, System.Collections.Generic.List`1<app.Character>, System.Boolean)
```cs
if (CachedCharacter == null || !CachedCharacter.IsEnabled) {
    return false;
}
var player = CharacterManager.Instance.Player; // probably player
var ignoreListener = player != null ? (listener == null ? !player.Valid : listener == player) : listener == null || !listener.Valid;
if (!ignoreListener) {
    bool speechValid = false;
    if (speaker.CharacterID != CachedCharacter.CharacterID || !IsPlayerInteractable) {
        speechValid = false;
    }
    var selfChar = this.GameObject.sameComponent<app.Character>();
    if (selfChar == null || !selfChar.Valid) {
        speechValid = false;
    }
    if (audienceList != null) {
        foreach (var aud in audienceList) {
            if (aud == null || !aud.Valid) return false;
            var audienceChar = aud.GameObject.sameComponent<app.Character>();
            if (audienceChar == null || !audienceChar.Valid) return false;
        }
    }
    if (speechValid) {
        this.speechPlay(talkEventId, speaker, listener, audienceList, isPreLocked);
        return true;
    }
}
if (talkEventId != 4 && !IsPlayerInteractable) { // 4 = te0001000_000
    return false;
}
this.speechPlay(talkEventId, speaker, listener, audienceList, isPreLocked);
return true;
```
app.SpeechController.speechPlay(app.TalkEventDefine.ID, app.Character, app.Character, System.Collections.Generic.List`1<app.Character>, System.Boolean)
```cs
var charlist = new List<app.Character>();
charlist.Add(speaker);
charlist.Add(listener);
if (audienceList != null) {
    charList.InsertRange(charlist.Count, audienceList);
}
var count = charList.Count;
if (count > 0) {
    int added = 0;
    for (var i = 0; i < charList.Count && count > 0; i++) {
        if (added >= charList.Count) {
            throw new Exception();
        } else {
            v13 = ch;
        }
        if (!ch.Valid) {
            throw new Exception("Probably");
        }
        var go = ch.GameObject;
        var ch = charList[i];
        var comp = someGameObject.getSameComponent<app.SpeechController>();
        if (comp != null && comp.Something) {
            NpcTalkMediator.cancel(comp.CachedCharacter.CharacterID) // CachedCharacter = [0x58], am not sure if it's really speechController or not
        }
        count--;
    }
}
bool played;
if (talkId != 0) {
    var dict = new Dictionary<app.Character, bool>(); // unused dict lol
    System.Action playAction = ...; // probably either lambdas or some static events cause it passes `this` to it
    System.Action finishAction = ...;
    // requestPlay(System.Object obj, app.TalkEventDefine.ID id, app.Character speaker, app.Character listener, System.Collections.Generic.Dictionary<app.CharacterID, app.Character> castList, System.Action playAction, System.Action finishAction, System.Action changeFirstCameraAction, System.Func<bool> isRequestFadeEndSegmentFunc, bool isUnloadedAllowed, bool isTakeOccupied, bool isPreLocked)
    var eventPlayerCastList = TalkEventManager.createEventPlayerCastList(talkId, speaker, listener); // TODO could be issues in here?
    played = TalkEventManager.requestPlay( // TODO could be issues in here... this returns false
        this,
        talkId,
        speaker,
        listener,
        eventPlayerCastList,
        playAction,
        finishAction,
        changeFirstCameraAction: null,
        isRequestFadeEndSegmentFunc: null,
        isUnloadedAllowed: false,
        isTakeOccupied: true,
        isPreLocked
    );
} else {
    // ... other code ...
    played = ...;
}
if (!played) {
    this.talkEventEnd();
}
v36.SentimentController?.requestUpdateSentiment(v37, SentimentActionIDEnum.Conversation, forceUpdate: false);
v37.SentimentController?.requestUpdateSentiment(v36, SentimentActionIDEnum.Conversation, forceUpdate: false);
```

app.TalkEventManager.createEventPlayerCastList

app.TalkEventManager.requestPlay378104(...)
```cs
TalkEventManager.Instance = this;
if (_PreRequest != null) {
    if (talkId != _preRequest.TalkEventID) {
        app.TalkEventDefine.TalkEventData currentResource = getTalkEventResource(talkId);
        var result = currentResource?._StopTalkEventResult ?? 0;
        recordResult(talkId, result, 0);
        return false;
    }
    _PreRequest = null;
}
var dynamicResource = this._CommandRequester.getDynamicResource(talkId); // TODO this returns null
if (dynamicResource == null) {
    recordResult(talkId, 0, 0);
    return false;
}
int stopTalkResult = 0;
if (_ResourceCatalog.tryGetValue(talkId, out var talkEvent)) {
    stopTalkResult = talkEvent._StopTalkEventResult;
}
if (!canPlay(talkId)) {
    recordResult(talkId, stopTalkResult, 0);
    dynamicResource.FinishAction?.Invoke();
    return false;
}
if (!isUnloadedAllowed) {
    if (speaker == null || listener == null) {
        dynamicResource.FinishAction?.Invoke();
        recordResult(talkId, stopTalkResult, 0);
        return false;
    }
    if (speaker.CharacterId == CharacterID.ch253001_00
        && talkId not 911 or 909 or 2207) {// -925771292 = 3369196004
        var ch253001 = speaker.GameObject.getSamecomponent<app.Ch253001>();
        var doit = (ch253001 != null && (
            ch253001.ForceDisableTalkNormalMessage ||
            ch253001.Ch253001QuestController == null ||
            ch253001.Ch253001SubdueCtrl && ch253001.Ch253001SubdueCtrl.SubdueEnd && !ch253001.Ch253001SubdueCtrl.SubdueFailed ||
            ch253001.Ch253001SubdueCtrl && ch253001.Ch253001SubdueCtrl.SubdueEnd && ch253001.Ch253001SubdueCtrl.SubdueFailed ||
            ch253001.Ch253001QuestController.QuestRoutine <= 2
        ));
        if (doit || castList == null || castList[0] == castList[1]) {
            dynamicResource.FinishAction?.Invoke(talkId, PlayErrorType.CastList);
            recordResult(talkId, stopTalkResult, 0);
            return false;
        }
    }
    // System.Collections.Generic.Dictionary<app.CharacterID, app.Character> castList
    var values = castList.getValues();
    foreach (var it in values) {
        if (chara == null || !chara.Valid) {
            dynamicResource.FinishAction?.Invoke(talkId, PlayErrorType.CastList);
            recordResult(talkId, stopTalkResult, 0);
            return false;
        }
    }
}
if (isTakeOccupied) {
    var v44 = isPreLocked ? 8 : 7;
    if (getType(talkId) == EventType.Type000) {
        // te60xx talk event IDs special handling
        if (talkId in (???)) {
            if (talkId == 1936 || talkId == 1931 || talkId == 1949) {
                unlockId = 9;
            }
            OccupiedManager.unlock(System_Enum__ToString582245_0((app.TalkEventDefine.ID)talkId), 9 or 10);
        }
        // these cases are a mess
        switch (talkId) {
            case 4:
                if (!_ExclusivePlayRequest.isPlaying()) {

                }
                break;
            case 1949:
            case 2162: // te6001900_040
            case 1914:
            case 1939:
            case 1914:
                lockType = 10;
                break;
            case ((talkId - 1920) & 0xFFFFFFFB) == 0:
            case 1920:
                lockType = 9;
                break;
            case 1931, 1936:
                lockType = 9;
                break;
            case -1:
                v43 = isTakeOccupied;
                break;
                // label 64 => lockType = v44
        }
        var talkIdString = System_Enum__ToString582245_0((app.TalkEventDefine.ID)talkId);
        if (!OccupiedManager.Instance.tryLock(talkIdString, lockType, something)) {
            recordResult(talkId, stopTalkResult, 0);
            dynamicResource.FinishAction?.Invoke(talkId, PlayErrorType.CastList);
            return false;
        }
    }
    this.IsTakeOccupied = isTakeOccupied;
    if (getType(talkId) != EventType.Type002) {
        // ?
        playAction = playAction.Combine(() => something);
    }
    if (!_CommandRequest.isLoaded(talkId)) {
        dynamicResource.FinishAction?.Invoke(talkId, PlayErrorType.Unloaded);
        recordResult(talkId, stopTalkResult, 0);
        return false;
    }
    if ((_IsExclusiveTalkingManualPlayer || _IsRequestPlayProcessing) && !_IsTalkingManualPlayer && !_IsRequestPlayProcessing) {
        if (getType(talkId) != Type000 && _PreRequst == null) {
            dynamicResource.FinishAction?.Invoke(talkId, PlayErrorType.Exclusive);
            recordResult(talkId, stopTalkResult, 0);
            return false;
        }
    }
    if (getType(talkId) != EventType.Type002) {
        // ?
        _RequestReadWriteLock.Lock();
        dynamicResource.FinishAction?.Invoke(talkId, PlayErrorType.Exclusive);
        recordResult(talkId, stopTalkResult, 0);
        _RequestReadWriteLock.Release();
        return false;
    }
    if (getType(talkId) == EventType.Type002 && _ExclusivePlayRequest?.isPlaying()) {
        dynamicResource.FinishAction?.Invoke(talkId, PlayErrorType.Exclusive);
        recordResult(talkId, stopTalkResult, 0);
        return false;
    }

    if (_IsRequestPlayProcessing) {
        dynamicResource.FinishAction?.Invoke(talkId, PlayErrorType.Exclusive);
        recordResult(talkId, stopTalkResult, 0);
        // ... some lock shit ...
    }

}
// ... other code ...
```
sdk.get_managed_singleton('app.TalkEventManager')._CommandRequester:getDynamicResource(395800)

app.TalkEventManager.TalkEventCommandRequester.getDynamicResource(app.TalkEventDefine.ID)
```cs
var v7 = something;
v7[0x10] = talkId;
var didLock = false;
if (_LockObjectCommandList != null) {
    _LockObjectCommandList.lock();
    didLock = true;
} else {
    // creates lock probably
}
var talkEventCommands = _CommandList.Cast<List<app.TalkEventManager.TalkEventCommandEntity>>();
var action = Something;
app.AppEventDefine.RequestEntry talkEventCommandEntity;
if (talkEventCommands.Count <= 0) {
    talkEventCommandEntity = null;
} else {
    // ... more code ...
    talkEventCommandEntity = talkEventCommands[v24];
    if (talkEventCommandEntity == null || !sub_144A1AE70(talkEventCommandEntity)) {
        talkEventCommandEntity = null;
    }
}

var resource = talkEventCommandEntity?.DynamicResource; // TODO: i take it this is missing?
if (!didLock) return resource;
if (_LockObjectCommandList.Release()) {
    return resource;
}
// then probably some error thing
return resource;
```



app.actinter.CommandExecutor
```cs
while(_PrimaryCommand != null) {
    if (_State == CommandExecutor.State.Start) {
        if (_Decorators != null) {
            object v90 = qword_14F8560C8; // note: thread safe assignment
            // something with a virtual method
            sub_141064470(a1, _Decorators, v90);
        }
        _PrimaryCommand?.Something();
        _SecondaryCommand?.Something();
        _SubCommandFinished = false;
        HasStarted = true;
        _State = CommandExecutor.State.Execute;
    } else if (_State == CommandExecutor.State.Execute) {
        v13 = sub_144A188A0(a1, (__int64)off_14FCC10F8, 0);
        if (_MainTarget == null || !_MainTarget.Valid || _MainTarget.Character != null && (_MainTarget.Character.TempStatus.Data & DisableTargetByAI) != 0) {
            var owner = this.Owner;
            if (qword_14F8560D0 != null) {
                // note: lots of thread hacking that i don't really understand here
                qword_14F8560D0 = sub_144A183E0(a1, (_DWORD)off_14FCC4158, qword_14F8560C0, (_DWORD)off_14FDD6F38, 1);
                if (didNeedSwap && v88 != null) {
                    _State = State.Break;
                }
            }
        } else {
            if (_Decorators != null && _Decorators.Length > 0) {
                var owner = this.Owner;
                if (qword_14F8560D8 == null) {
                    // NOTE: similar pattern as above in the first if of the execute state, except without a return case
                    qword_14F8560D8 = sub_144A183E0(a1, (_DWORD)off_14FCC4158, qword_14F8560C0, (_DWORD)off_14FDD6F40, 1)
                }
                foreach (var dec in _Decorators) {
                    // some thread safe assignment again
                    var v26 = (__int64)sub_144A188A0(a1, (__int64)off_14FCC1100, 0);
                    v26[0x10] = dec;
                    if (dec.Valid) {
                        dec.SomethingVirtual()
                    }
                    _ = _ActInter?.GameObject;
                }
            }
            // lots of other code
            var CommandAbortsType = ??;
            // lots of other code
            if (_PrimaryCommand) {
                v13.ReturnCommand = _PrimaryCommand.update();
                v13.HasPrimary = true;
            } else {
                v13.ReturnCommand = 0;
                v13.HasPrimary = false;
            }
            // other code, some value assignment
            _ = _ActInter?.GameObject;
            if (!_SubCommandFinished && _SecondaryCommand != null) {
                var subresult = _SecondaryCommand.update(CommandAbortsType);
                if (subresult != 0) {
                    _ = _ActInter?.GameObject;
                    _SubCommandFinished = true;
                }
            }
            if (abortsType is None) {
                // 0x10 should be the ReturnCommand CommandBase.update() return value, but then what's 0x14?
                if (v13.HasPrimary == false) return; // executed status, probably
                var primaryReturnCommand = v13.ReturnCommand;
                if (primaryReturnCommand == ReturnCommand.Next) {
                    _State = State.End;
                } else if (primaryReturnCommand == ReturnCommand.Continue) {
                    return;
                } else { // primaryReturnCommand == ReturnCommand.Break
                    _State = State.Break;
                }
                continue;
            } else if (abortsType is Continue) {
                if (v13.ReturnCommand != ReturnCommand.Break || v13.HasPrimary == false) {
                    return;
                }
                _State = State.Break;
            } else if (abortsType is Finish or Next or Break) {
                _State = End;
                continue;
            } else {
                return;
            }
        }
    } else if (_State == CommandExecutor.State.End) {
        if (!HasStarted) {
            _State = State.HasEnded;
        }
    } else if (_State == CommandExecutor.State.HasEnded) {
        break;
    } else if (_State == CommandExecutor.State.Break) {
        if (_BreakState != BreakStatus.IsExternalBreak) {
            _BreakState = BreakStatus.IsBreak;
        }
        _State = State.End;
    } else {
        return;
    }
}
// note: it does some (*(unsigned int *)(a2 + 8) >= 0) check to decide whether to do a locked assign or not, no idea what that number is; some ManagedObject field I assume
_PrimaryCommand = null;
_SecondaryCommand = null;
```

sub_144A188A0() - some sort of object constructor?
```cs
sub_144A188A0(void *vm, SystemType *type, bool a3)
{
    if (a3 || (type[0x13] & 1) == 0) // a3 || (type.IsNotPublic?)
        return sub_144A182B0(a1, typePtr, *(unsigned int *)(typePtr + 0x14));
    result = {
        object [0] = [typePtr+0x40];
        byte [0xE] = (v6 + 64) >> 4;
        int [0x8] = int.Max;
        short[0x10] += ([typePtr+0x14] + 0xf) & 0xfffffff0;
    };
    return result;
}
```
