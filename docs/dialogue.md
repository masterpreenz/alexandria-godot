# Alexandria: story dialogue

Everything the opening says, in the order it plays: the guide cards (title, then the hint and its ticked parts), the spoken scenes, the rumors' words, and the lines that float up. Edit the words here and send it back; each section names where it lives in the game (`data/intro.json`, `data/scenes.json`, `data/rumors.json`). `{miko}` is Sera's name.

## The opening, step by step

### Find your feet  
*`move` · starter guide (card over Sera)*

Parts: W A S D to walk · Shift to run · Space to jump

### Defend yourself  
*`first_slime` · starter guide (card over Sera)*

Something's come out of the mist.  
Parts: Left click to strike

### Clear the road  
*`slimes` · starter guide (card over Sera)*

More slimes along the road. Your skills are on the bar below:  
Parts: Left click to strike · 1 to aim Fireball, click where it lands

### Check your bag  
*`bag` · starter guide (card over Sera)*

I opens your bag and your character.  

### Look over your talents  
*`talents` · starter guide (card over Sera)*

P opens your talents. Spend a point when you have one.  

### Gather wood and stone  
*`gather` · starter guide (card over Sera)*

E by a tree to chop, by a rock to mine.  
Parts: {progress} wood · {progress} stone

### Hunt  
*`hunt` · starter guide (card over Sera)*

A boar in the trees, and slimes. Boar meat can be cooked.  

### Make camp before dark  
*`camp` · starter guide (card over Sera)*

Night's coming. B to build:  
Parts: a Bonfire · a Leaf Bed

### Cook something  
*`cook` · starter guide (card over Sera)*

At the lit bonfire, hold E with raw meat in your bag.  

### Eat, then rest  
*`rest` · starter guide (card over Sera)*

Parts: F to eat · Z by your bed to sleep

### Someone's coming  
*`messenger` · story (card at the right)*


### Scene: `messenger`

*Talk to: (no one: it plays by itself). Plays after: its step begins.*

**Taro:** Hey! You there! Please... you have to help us!  
**Sera:** Slow down. What's happened?  
**Taro:** The village, just up the road. Monsters, out of the mist. Slimes, boars, and... things that used to be people. They came all at once.  
**Taro:** They never come at us like this. They're not acting right. Please, we can't hold them!  
**Sera:** Show me the way. Stay behind me.  

### Get to the village  
*`rush` · story (card at the right)*

Up the road north, then east to the houses. Hurry.  

### Drive the monsters out  
*`fight` · story (card at the right)*

They're everywhere. Protect who you can.  

### Talk to the survivors  
*`aftermath` · story (card at the right)*

The elder is with them. E to talk.  

### Scene: `aftermath`

*Talk to: Genzo. Plays after: village_warded.*

**Genzo:** It's quiet. Is it... is it over?  
**Hana:** For now. Look at the crystal: the mist's pulling back from it.  
**Kenji:** What was that? The mist, the monsters, all of it. Where did it come from?  
**Yui:** And those things that looked like people. They were people, weren't they.  
**Sera:** I don't know all of it. The mist came down from the north. Whatever's in it changes what it touches, and the monsters follow it.  
**Sera:** You're safe while the crystal stands. I came to help, and I'll stay to help. First let's see to your homes.  
**Haruko:** Thank the gods you came when you did.  
**Genzo:** We've lost good people tonight. But we're still here. Tell us what to do.  

### Help them rebuild  
*`materials` · story (card at the right)*

Walls are down all over. Put in a chest, for the villagers to rebuild with:  
Parts: {progress} wood · {progress} stone

### See the houses mended  
*`mend` · story (card at the right)*

The villagers are rebuilding the walls and mending the houses. Lend a hand gathering if they run short.  

### Cook for them  
*`feed` · story (card at the right)*

Three cooked dishes into storage.  

### Talk to the elder  
*`question` · story (card at the right)*

He's been watching you.  

### Scene: `peculiar`

*Talk to: Genzo. Plays after: intro_houses_mended, intro_fed.*

**Genzo:** You knew just what to do with that crystal. As if you'd done it before.  
**Sera:** I have. The mist is already in other places, further off. I go where it goes, and help where I can.  
**Genzo:** A wanderer, then. And a peculiar one, if you'll forgive an old man for saying it.  
**Genzo:** It's not often we see one of your kind, with ears like those, helping folk like us. Not with how your people are treated.  
**Sera:** I suppose I'm a little unique that way.  
**Haruko:** Unique or not, you've a bed here tonight. And a meal, though you cooked it yourself.  

### Rest for the night  
*`night` · story (card at the right)*

There's a bed for you in the village tonight. Z to sleep.  

*Floats up after: "Morning. The elder looks like he hasn't slept."*

### (waiting, unseen: the game runs as usual until Miyu is home)

### Rumor: The elder's granddaughter (`find_miyu`)

*Told by Genzo:*

> Sera... a word, if you'd hear an old man. My granddaughter, Miyu. I sent her to the next village on an errand, two days ago: up the road west, over the bridge, then north. She should have been back by now. If the mist is there as it was here... Please. Go and look for her. I can't ask anyone else.

- **Note (reach):** The elder's granddaughter, Miyu, went to the next village on an errand and hasn't come back: up the road west over the bridge, then north. Go today. The mist has spread everywhere overnight: never mind it and head straight there. Your crystal necklace keeps it off you.
- **Note (carry):** The village is overrun, and Miyu lies in the street, unconscious. Pick her up (E) and carry her home.
- **When it's done:** Miyu is home, asleep. The elders want to speak with you.
- **If it's missed:** Word has come from the next village: nobody was left alive there. Miyu is gone.

### Scene: `elders_thanks`

*Talk to: Genzo. Plays after: miyu_home.*

**Genzo:** Sera. You brought her back. You brought my Miyu back.  
**Haruko:** She's sleeping now. Not a scratch on her that won't heal. I don't know how we'll ever repay you.  
**Sera:** You don't have to. I'm glad I got there in time. The village she was in... there was nobody else.  
**Genzo:** Then it's as we feared. Whatever is coming, it isn't stopping at our fence.  
**Genzo:** I'm an old man, Sera. I can keep the peace at the table, but I can't keep this village alive through what's coming. You can. You've already shown it.  
**Genzo:** Take the village into your keeping. The people will follow you: I've seen how they look at you, ears and all.  
**Sera:** ...All right. I'll look after them. All of them.  
**Haruko:** And Miyu, when she wakes. She'll want to go with you, you know. She's been watching you since the moment you came.  
**Genzo:** Look after her too.  

### Push back the mist  
*`crystal` · starter guide (card over Sera)*

Slimes drop mist crystals; three and some wood make a Cleansing Crystal, which clears the mist round it. B to build:  
Parts: a Cleansing Crystal

## Later

### Rumor: A book for Miyu (`miyu_book`)

*Told by Miyu:*

> {miko}, can I ask you something, and you won't laugh? I want to learn magic. Properly. I know it isn't born in me the way it is in you, but you said most of it is learned. If you ever find a book of it, any book, would you bring it to me? I'd only need the one. I'd never put it down.

- **Note (book):** Miyu wants to learn magic. She asks for a book of it: any one. She will learn only the one, for good.
- **When it's done:** Miyu has her book. She hasn't looked up from it since.

