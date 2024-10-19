# 8000 Ogres in the hills
node conditions:
- trigger: cleared monster culling, level >= 30 OR 14 days passed since clearing monster culling
- end: unmoored world (qu11040?)

locations:
- NPC waiting spot override while quest is available - qu020240_004 (396,32,-1046)
- patrol start (if joining) TWN_00_080
- patrol end (ask arisen to find the way), also initial destination if going alone: TWN_00_068
- ogre hiding spot: AILocalAreaDefinition: Situation_EditField_71_0001 = 358, KeyLocation_Vermund_14_001

processors:

- NotifyStart
- if Started: NPCControl - task with talk event 8000_intro
- if Started: Processor 8000/6754702 Time limit: Time elapsed >= 72h
- if Started: Processor 8000/6754701 Spawn ogre trio
    -> end if defeated
- if Joined (8000_intro == 2)
    - processor: spawn 3-4 guard NPCs, one is lead, others follow the leader
    - processor: if inside report area: task - patrol and monologue
        "The reports are most frequently around this area. Let us take a look around, there aught to be some clues on the ogre's location hereabouts."
    - processor: if reached patrol goal, initiate talk event 8000_joined_post_patrol
        "Ser Arisen, as the most experienced in fighting monsters, would you be able to find where the ogres might've gone?"
    - processor: if 8000_joined_post_patrol == 0, NPCs Follow player
    - pawn: monologue "I sense a presence nearby, let us check in the southwest."
    - processor: if player reached [ogre spawn localarea] and ogres are nearby, NPC monologue: "Today shall be your reckoning, filthy ogres!"
    - if ogres defeated: "Thank you, ser Arisen. Thank you very much. Let us speak about your reward after we return to Vernworth."
    - TODO: what if player just leaves in the middle of this? some sort of a 24h time limit maybe?
- if not joined (accepted or refused):
    - time limit: 72h
    - Quest log: if (time limit + ogres not defeated) processor 6754702 == 0 && 6754701 != 0 and player LocalArea = Vernworth NW entrance
        "You seem to have been too late. The member of the Vernworth guard seems to have disappeared, a bouquet of flowers left in his place."
    - if ogres defeated before time limit:
        - "Ohh, thank ye kindly, Arisen! I'm sure that was a tough battle."
    - if ogres not defeated before time limit:
        - NPCControl ch300316 James Generate = false
        - ItemControl: flowers next to Vernworth NW archway
- if ogres defeated and talked to guard back in Vernworth:
    - affinity with all Vernworth guards +100
    - quest reward (60k gold, maybe an armor set)

talk events:
- 8000_intro
    - player choices:
        - accept
            => result = 0
        - refused
            => result = 1
        - accept & join
            => result = 2
            => (PlayerControl?) timeskip + teleport player to destination

- 8000_accepted_reminder
    - if 8000_intro == 0 && not defeated ogres yet
    - "The ogres are reported to be frequenting the oxcart road toward the checkpoint town. I pray for your success, Arisen."

- 8000_nearing_time_limit_reminder
    - if elapsed time >= 48h (max limit - 1d)
    "Arisen, if you've changed your mind, there is yet time."

variables:
- 80005 - intro talk event result number
- 80002 - dealt with ogres
- 80003 - success talk event result number (finished quest)
