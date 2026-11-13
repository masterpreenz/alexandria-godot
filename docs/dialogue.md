# Alexandria: story dialogue

Everything the opening says, in the order it plays, numbered: a story step is a number, the lines spoken in it are that number and a dot. Say which to keep, which to change (and to what), which to drop. `{miko}` is Sera's name. Made by `tools/export_dialogue.py` from `data/intro.json`, `data/scenes.json` and `data/rumors.json`.

## 1. Find your feet

*`move`, starter guide: its card over Sera*

**1** W A S D to walk · Shift to run · Space to jump

## 2. Defend yourself

*`first_slime`, starter guide: its card over Sera*

**2** Something's come out of the mist. Left click to strike

## 3. Clear the road

*`slimes`, starter guide: its card over Sera*

**3** More slimes along the road. Try your skill from the bar below: 1 to aim Fireball, click where it lands

## 4. Gather wood and stone

*`gather`, starter guide: its card over Sera*

**4** E by a tree to chop, by a rock to mine. {progress} wood · {progress} stone

## 5. Hunt

*`hunt`, starter guide: its card over Sera*

**5** A boar in the trees, and slimes. Boar meat can be cooked.

## 6. Make camp before dark

*`camp`, starter guide: its card over Sera*

**6** Night's coming. B to build: a Bonfire · a Leaf Bed

## 7. Cook something

*`cook`, starter guide: its card over Sera*

**7** At the lit bonfire, hold E with raw meat in your bag.

## 8. Eat, then rest

*`rest`, starter guide: its card over Sera*

**8** F to eat · Z by your bed to sleep

## 9. Someone's coming

*`messenger`, story: its card at the right*

*Scene `messenger` (plays by itself)*

- **9.1** Taro: Hey! You there! Please... you have to help us!
- **9.2** Sera: Slow down. What's happened?
- **9.3** Taro: Our village is being attacked by monsters. Please help! You look like an adventurer.
- **9.4** Taro: The mist suddenly came, and the beasts started acting strange!
- **9.5** Taro: They never come at us like this. They're not acting right. Please, we can't hold them!
- **9.6** Sera: Lead the way. Be careful.

## 10. Get to the village

*`rush`, story: its card at the right*

**10** Up the road north, then east to the houses. Hurry.

## 11. Drive the monsters out

*`fight`, story: its card at the right*

**11** They're everywhere. Protect who you can.

- **11.1** (floats up as it ends) Something answers her inside: she can call an Attack Shikigami now.

## 12. Talk to the survivors

*`aftermath`, story: its card at the right*

**12** The elder is with them. E to talk.

*Scene `aftermath` (talk to Genzo)*

- **12.1** Genzo: It's quiet. Is it... is it over?
- **12.2** Kenji: What was that? The mist, the monsters, all of it. Where did it come from?
- **12.3** Yui: And those things that looked like people. They were people, weren't they.
- **12.4** Sera: I can't believe it's already spread this fast. The mist was already happening everywhere else; I came to help spread the news of how to defend against it.
- **12.5** Sera: We can make makeshift pillars using these crystals. You're safe from the mist when you're around one.
- **12.6** Haruko: Thank you for saving us. It's nice that you were just around.
- **12.7** Sera: I was resting near the river when your friend alerted me.
- **12.8** Genzo: We've lost good people tonight. But we're still here. For now, help us repair the village.

## 13. Cook for them

*`feed`, story: its card at the right*

**13** They've had nothing since the attack. They bring out the meat they saved: cook it at a fire, then take the dishes to the elder. {progress} cooked · give them to the elder

## 14. Talk to the elder

*`question`, story: its card at the right*

**14** He's been watching you.

*Scene `peculiar` (talk to Genzo)*

- **14.1** Genzo: You knew just what to do with that crystal. As if you'd done it before.
- **14.2** Sera: I have. The mist is already in other places, further off. I go where it goes, and help where I can.
- **14.3** Genzo: A wanderer, then. And a peculiar one, if you'll forgive an old man for saying it.
- **14.4** Genzo: It's not often we see one of your kind, with ears like those, helping folk like us. Not with how your people are treated.
- **14.5** Sera: I suppose I'm a little unique that way.
- **14.6** Haruko: Unique or not, you've a bed here tonight. And a meal, though you cooked it yourself.
- **14.7** Genzo: Now go and rest, Sera. You've done more than enough for one night.

## 15. Rest for the night

*`night`, story: its card at the right*

**15** There's a bed for you in the village tonight. Z to sleep.

## 16. (waiting, unseen: the game runs as usual till Miyu is home)

*Rumor `find_miyu`: The elder's granddaughter (told by Genzo)*

- **16.1** Genzo: Sera... a word, if you'd hear an old man. My granddaughter, Miyu. I sent her to the next village on an errand, two days ago: up the road west, over the bridge, then north. She should have been back by now. If the mist is there as it was here... Please. Go and look for her. I can't ask anyone else.
- **16.2** (note, reach) The elder's granddaughter, Miyu, went to the next village on an errand and hasn't come back: up the road west over the bridge, then north. Go today. The mist has spread everywhere overnight: never mind it and head straight there. Your crystal necklace keeps it off you.
- **16.3** (note, carry) The village is overrun, and Miyu lies in the street, unconscious. Pick her up (E) and carry her home to the elder, then lay her in a bed in the elders' house.
- **16.4** (when it's done) Miyu is home, asleep. The elders want to speak with you.
- **16.5** (if it's missed) Word has come from the next village: nobody was left alive there. Miyu is gone.

*Scene `elders_thanks` (talk to Genzo)*

- **16.6** Genzo: Sera. You brought her back. You brought my Miyu back.
- **16.7** Haruko: She's sleeping now. Not a scratch on her that won't heal. I don't know how we'll ever repay you.
- **16.8** Sera: You don't have to. I'm glad I got there in time. The village she was in... there was nobody else.
- **16.9** Genzo: Then it's as we feared. Whatever is coming, it isn't stopping at our fence.
- **16.10** Genzo: I'm an old man, Sera. I can keep the peace at the table, but I can't keep this village alive through what's coming. You can. You've already shown it.
- **16.11** Genzo: Take the village into your keeping. The people will follow you: I've seen how they look at you, ears and all.
- **16.12** Sera: ...All right. I'll look after them. All of them.
- **16.13** Haruko: And Miyu, when she wakes. She'll want to go with you, you know. She's been watching you since the moment you came.
- **16.14** Genzo: Look after her too.

## 17. Push back the mist

*`crystal`, starter guide: its card over Sera*

**17** Slimes drop mist crystals; three and some wood make a Cleansing Crystal, which clears the mist round it. B to build: a Cleansing Crystal

## 18. Later

*Rumor `miyu_book`: A book for Miyu (told by Miyu)*

- **18.1** Miyu: {miko}, can I ask you something, and you won't laugh? I want to learn magic. Properly. I know it isn't born in me the way it is in you, but you said most of it is learned. If you ever find a book of it, any book, would you bring it to me? I'd only need the one. I'd never put it down.
- **18.2** (note, book) Miyu wants to learn magic. She asks for a book of it: any one. She will learn only the one, for good.
- **18.3** (when it's done) Miyu has her book. She hasn't looked up from it since.

