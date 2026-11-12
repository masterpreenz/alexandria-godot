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

## 4. Check your bag

*`bag`, starter guide: its card over Sera*

**4** I opens your bag and your character.

## 5. Look over your talents

*`talents`, starter guide: its card over Sera*

**5** P opens your talents. Spend a point when you have one.

## 6. Gather wood and stone

*`gather`, starter guide: its card over Sera*

**6** E by a tree to chop, by a rock to mine. {progress} wood · {progress} stone

## 7. Hunt

*`hunt`, starter guide: its card over Sera*

**7** A boar in the trees, and slimes. Boar meat can be cooked.

## 8. Make camp before dark

*`camp`, starter guide: its card over Sera*

**8** Night's coming. B to build: a Bonfire · a Leaf Bed

## 9. Cook something

*`cook`, starter guide: its card over Sera*

**9** At the lit bonfire, hold E with raw meat in your bag.

## 10. Eat, then rest

*`rest`, starter guide: its card over Sera*

**10** F to eat · Z by your bed to sleep

## 11. Someone's coming

*`messenger`, story: its card at the right*

*Scene `messenger` (plays by itself)*

- **11.1** Taro: Hey! You there! Please... you have to help us!
- **11.2** Sera: Slow down. What's happened?
- **11.3** Taro: Our village is being attacked by monsters. Please help! You look like an adventurer.
- **11.4** Taro: The mist suddenly came, and the beasts started acting strange!
- **11.5** Taro: They never come at us like this. They're not acting right. Please, we can't hold them!
- **11.6** Sera: Lead the way. Be careful.

## 12. Get to the village

*`rush`, story: its card at the right*

**12** Up the road north, then east to the houses. Hurry.

## 13. Drive the monsters out

*`fight`, story: its card at the right*

**13** They're everywhere. Protect who you can.

- **13.1** (floats up as it ends) Something answers her inside: she can call Shikigami now, to fight and to heal.

## 14. They're coming again

*`second_wave`, story: its card at the right*

**14** Hold the middle with the others. Your Shikigami fight and heal beside you; when they fade, call them again from the bar: the Attack Shikigami · the Healing Shikigami

## 15. Talk to the survivors

*`aftermath`, story: its card at the right*

**15** The elder is with them. E to talk.

*Scene `aftermath` (talk to Genzo)*

- **15.1** Genzo: It's quiet. Is it... is it over?
- **15.2** Kenji: What was that? The mist, the monsters, all of it. Where did it come from?
- **15.3** Yui: And those things that looked like people. They were people, weren't they.
- **15.4** Sera: I can't believe it's already spread this fast. The mist was already happening everywhere else; I came to help spread the news of how to defend against it.
- **15.5** Sera: We can make makeshift pillars using these crystals. You're safe from the mist when you're around one.
- **15.6** Haruko: Thank you for saving us. It's nice that you were just around.
- **15.7** Sera: I was resting near the river when your friend alerted me.
- **15.8** Genzo: We've lost good people tonight. But we're still here. For now, help us repair the village.

## 16. Cook for them

*`feed`, story: its card at the right*

**16** They've had nothing since the attack. They bring out the meat they saved: cook it at a fire, then take the dishes to the elder. {progress} cooked · give them to the elder

## 17. Talk to the elder

*`question`, story: its card at the right*

**17** He's been watching you.

*Scene `peculiar` (talk to Genzo)*

- **17.1** Genzo: You knew just what to do with that crystal. As if you'd done it before.
- **17.2** Sera: I have. The mist is already in other places, further off. I go where it goes, and help where I can.
- **17.3** Genzo: A wanderer, then. And a peculiar one, if you'll forgive an old man for saying it.
- **17.4** Genzo: It's not often we see one of your kind, with ears like those, helping folk like us. Not with how your people are treated.
- **17.5** Sera: I suppose I'm a little unique that way.
- **17.6** Haruko: Unique or not, you've a bed here tonight. And a meal, though you cooked it yourself.
- **17.7** Genzo: Now go and rest, Sera. You've done more than enough for one night.

## 18. Rest for the night

*`night`, story: its card at the right*

**18** There's a bed for you in the village tonight. Z to sleep.

## 19. (waiting, unseen: the game runs as usual till Miyu is home)

*Rumor `find_miyu`: The elder's granddaughter (told by Genzo)*

- **19.1** Genzo: Sera... a word, if you'd hear an old man. My granddaughter, Miyu. I sent her to the next village on an errand, two days ago: up the road west, over the bridge, then north. She should have been back by now. If the mist is there as it was here... Please. Go and look for her. I can't ask anyone else.
- **19.2** (note, reach) The elder's granddaughter, Miyu, went to the next village on an errand and hasn't come back: up the road west over the bridge, then north. Go today. The mist has spread everywhere overnight: never mind it and head straight there. Your crystal necklace keeps it off you.
- **19.3** (note, carry) The village is overrun, and Miyu lies in the street, unconscious. Pick her up (E) and carry her home.
- **19.4** (when it's done) Miyu is home, asleep. The elders want to speak with you.
- **19.5** (if it's missed) Word has come from the next village: nobody was left alive there. Miyu is gone.

*Scene `elders_thanks` (talk to Genzo)*

- **19.6** Genzo: Sera. You brought her back. You brought my Miyu back.
- **19.7** Haruko: She's sleeping now. Not a scratch on her that won't heal. I don't know how we'll ever repay you.
- **19.8** Sera: You don't have to. I'm glad I got there in time. The village she was in... there was nobody else.
- **19.9** Genzo: Then it's as we feared. Whatever is coming, it isn't stopping at our fence.
- **19.10** Genzo: I'm an old man, Sera. I can keep the peace at the table, but I can't keep this village alive through what's coming. You can. You've already shown it.
- **19.11** Genzo: Take the village into your keeping. The people will follow you: I've seen how they look at you, ears and all.
- **19.12** Sera: ...All right. I'll look after them. All of them.
- **19.13** Haruko: And Miyu, when she wakes. She'll want to go with you, you know. She's been watching you since the moment you came.
- **19.14** Genzo: Look after her too.

## 20. Push back the mist

*`crystal`, starter guide: its card over Sera*

**20** Slimes drop mist crystals; three and some wood make a Cleansing Crystal, which clears the mist round it. B to build: a Cleansing Crystal

## 21. Later

*Rumor `miyu_book`: A book for Miyu (told by Miyu)*

- **21.1** Miyu: {miko}, can I ask you something, and you won't laugh? I want to learn magic. Properly. I know it isn't born in me the way it is in you, but you said most of it is learned. If you ever find a book of it, any book, would you bring it to me? I'd only need the one. I'd never put it down.
- **21.2** (note, book) Miyu wants to learn magic. She asks for a book of it: any one. She will learn only the one, for good.
- **21.3** (when it's done) Miyu has her book. She hasn't looked up from it since.

