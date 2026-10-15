#!/usr/bin/env python3
"""
Rewrite teaser titles/descriptions so they don't repeat within a city.

Teasers never name the place (paid places are sold on them), so they come from per-category pools.
Within one city and category, places get pool entries in turn (offset per city), so a city only repeats
a teaser when it has more places in a category than the pool has lines. Idempotent: rerun after imports.

  python3 backend/tools/teasers.py OUT.sql
"""
import hashlib, sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
import db  # noqa: E402

RECENT_DAYS: int | None = None   # autopilot: only (re)write places added in the last N days, avoiding lines already used

T = {
"bars": (
    ["A drink behind an unmarked door", "The bar regulars keep to themselves", "A low-lit room with no sign outside",
     "Cocktails you only find by asking", "The nightcap spot that isn't on the map", "A bar that trusts you to find it",
     "Ask for the door with no handle", "A back room where the city unwinds", "Where bartenders drink on their night off",
     "A counter of twelve stools and good secrets", "Down a staircase, into another decade", "The password is knowing it exists",
     "A bar hidden in plain sight", "Candles, vinyl and a very short menu", "The quiet room behind the loud one",
     "A drink worth getting lost for", "One door, no name, full every night", "A cocktail list written like a diary",
     "The bar locals send their best friends to", "Behind the curtain, a room full of whispers", "A bar older than its neighbours",
     "Old wood, older stories, a perfect pint", "The kind of bar you keep for yourself", "Last orders come late here"],
    ["No sign shouting for attention — just a door, and people who already know.",
     "Small, unhurried, and better the later it gets.",
     "Ask the right people and they'll send you here.",
     "A short menu, a long memory, and nobody in a hurry to leave.",
     "You have to know it's there — then it's the easiest place in the city to stay too long.",
     "The bartender remembers your drink by the second visit.",
     "Arrive early for a seat, stay late for the stories.",
     "Dim light, good ice, and conversations you'll want to overhear.",
     "It doesn't advertise. It doesn't need to.",
     "Find the door and the rest of the night takes care of itself."]),
"night": (
    ["A night that starts after midnight", "A club you find by asking", "A room that runs till sunrise",
     "Sound, concrete and a crowd who already know", "The dance floor with no Instagram", "Where the city goes after the bars close",
     "A basement with a very good sound system", "The after-hours the locals guard", "Lights low, bass high, no phones",
     "A warehouse that wakes up at 2 a.m.", "The queue is the only clue", "A night you'll describe badly tomorrow"],
    ["No frontage, no list online — just the people who know.",
     "Come late, leave early — in the morning.",
     "The door is the hard part; the rest takes care of itself.",
     "Dress down, go in curious, come out at sunrise.",
     "The kind of night the city doesn't put in brochures.",
     "Follow the low hum down the street."]),
"rooftops": (
    ["A rooftop the city keeps to itself", "Drinks above the skyline", "A terrace most people never find",
     "Golden hour, one floor below the sky", "The lift nobody notices goes all the way up", "A view with a cocktail attached",
     "Sunset seats above the rooftops", "Where the city looks best from above", "A terrace that feels like a secret garden",
     "High up, low key", "The best seat in town is on the roof", "Above the noise, beside the sky"],
    ["Take the lift most people don't notice and the whole city opens up.",
     "Come before sunset and stay for the lights.",
     "Above the noise, with a view worth the climb.",
     "Book a corner table and watch the city change colour.",
     "Warm evenings were invented for places like this."]),
"food_drink": (
    ["A table the locals book for themselves", "A kitchen with a long local story", "The dinner spot friends send friends to",
     "A dining room older than the guidebooks", "Lunch the way the city actually eats", "The plate everyone orders twice",
     "A family kitchen open to strangers", "Where chefs go to eat on Mondays", "Come hungry, leave converted",
     "A counter where you trust the cook", "The food stop locals queue for", "Recipes older than the building",
     "Flavours the city grew up on", "A long lunch waiting to happen"],
    ["Order what the next table is having — they've been coming for years.",
     "Go hungry, and go without a plan.",
     "A place the city has quietly kept for itself.",
     "Loud, fresh and very much alive.",
     "Ask what's good today, then trust the answer."]),
"michelin": (
    ["A table the Michelin inspectors found first", "A tasting menu the city is proud of", "A Michelin-recognised kitchen worth the trip",
     "Dinner the critics still talk about", "A meal to plan a trip around", "A kitchen that earned the city's attention",
     "The reservation worth setting an alarm for", "A dining room with a guidebook reputation"],
    ["Book ahead, arrive hungry, and let the kitchen decide.",
     "One of the few rooms in the city where every plate is an event.",
     "Recognised by the Michelin Guide — the address is the secret.",
     "Dress up a little; the kitchen certainly has."]),
"coffee": (
    ["A specialty coffee spot down a side street", "The pour-over place friends whisper about", "A tiny café that takes coffee seriously",
     "Six seats and a very good roast", "The espresso bar baristas recommend", "A café that smells like Sunday",
     "Coffee worth a detour", "A window seat and the city waking up", "Beans roasted three streets away",
     "Where laptops are welcome and time slows down", "A courtyard café hiding from the street", "The flat white the neighbourhood swears by",
     "A café with a better playlist than yours", "Pastries gone by ten, come early", "A quiet corner for the first cup",
     "The roaster's own little bar"],
    ["A few seats, a good roast, and mornings that stretch.",
     "Tucked away, but the espresso is why people keep coming back.",
     "Blink and you'd miss the door — don't.",
     "Order the filter of the day and ask where it's from.",
     "Come for one cup, stay for a second and a pastry.",
     "The kind of place that makes the rest of the day better."]),
"viewpoints": (
    ["A view over the city most people miss", "The overlook locals save for golden hour", "A quiet ledge with a very loud view",
     "Where the city lays itself out below", "Sunrise is worth the alarm here", "A bench with the best view in town",
     "The climb is short, the view isn't", "Rooftops all the way to the horizon", "The city's best-kept panorama",
     "Where photographers wait for the light", "A lookout at the end of a staircase", "The view postcards wish they had",
     "A hill the tour buses skip", "Watch the lights come on from here"],
    ["Climb a little and the whole district unfolds — if you know where to stand.",
     "Come at dusk and watch the rooftops catch the last light.",
     "Everyone walks past the turn — take it, and look up.",
     "Bring something warm and stay until the city lights up.",
     "It's quiet up here, even when the streets below aren't."]),
"architecture": (
    ["A piece of the city's story, hiding in plain sight", "A landmark the tours rush past",
     "Old stones with a better story than the guidebook", "A corner of history worth slowing down for",
     "A façade most people never look up at", "A courtyard behind a heavy door", "Centuries stacked in one building",
     "The detail everyone walks past", "A ruin with a view of the present", "A building that changed the city's skyline",
     "Look up: the best part is above the doors", "A church quieter than the square outside", "Walls that remember the old city",
     "A gate to a city that's no longer there", "The staircase architects come to see"],
    ["Most people walk straight past — stop, and it starts talking.",
     "Off the main route, and all the better for it.",
     "Small, quiet, and older than everything around it.",
     "Go early, when the light hits the stone just right.",
     "Read the plaque, then look for what it doesn't mention."]),
"culture": (
    ["A local landmark with a better story than the sign", "A corner of the city worth slowing down for",
     "The place locals take visiting friends", "Something the city is quietly proud of", "A detour the guidebooks forgot",
     "A small wonder most visitors miss", "Culture without the crowds", "A story the city tells quietly",
     "Worth ten minutes of anyone's day", "Curious, quiet and worth the find", "The city's memory, in one spot",
     "An odd little gem you'll talk about later", "Art and history off the main route", "A stop the locals are fond of"],
    ["Go early, before the crowds, and it feels like yours.",
     "Most people rush past — give it ten minutes.",
     "Small detail, long history, worth the short detour.",
     "An hour here tells you more than a day of sightseeing.",
     "Find it yourself and it feels like yours."]),
"walks": (
    ["A green pocket to slow down in", "A garden most people rush past", "A quiet loop away from the crowds",
     "A path the joggers keep to themselves", "Trees, water and no traffic", "The city's back garden",
     "A walled garden behind the busy street", "A riverside path for long talks", "Where the city breathes out",
     "Benches, birds and a slower clock"],
    ["Trees, a path, and room to breathe five minutes from the noise.",
     "Come with a coffee and stay longer than you planned.",
     "Enough green to forget you're in the middle of the city.",
     "Best on a weekday morning, when it's all yours."]),
"nature": (
    ["A park bigger than it looks from the gate", "Green space the city breathes through", "A long walk under old trees",
     "Wild corners inside the city limits", "A lake the locals swim in", "A hill of grass and a picnic view",
     "Old trees, long shadows, short queues", "A forest edge at the end of the tram line"],
    ["Paths that wander, benches that wait, and room to think.",
     "Pack a lunch and let the afternoon go.",
     "The city goes quiet the moment you step inside."]),
"beaches": (
    ["A stretch of sand the crowds skip", "A beach for the end of the day", "Where the city meets the water",
     "A cove you reach on foot", "Swim, then lunch with sandy feet", "The beach locals don't post about"],
    ["Bring a towel and lose track of time.",
     "Come at sunset when the day-trippers leave.",
     "Close enough to reach on a whim, far enough to forget the city."]),
"underground": (
    ["A room below the street", "A sound you'll only hear down here", "Under the city, another city",
     "Stairs down into something unexpected", "A cellar with a story"],
    ["Mind the steps — the good part is underground.",
     "Cooler, quieter, and nothing like the street above."]),
}


def h(s: str) -> int:
    return int(hashlib.md5(s.encode()).hexdigest()[:8], 16)


def q(s: str) -> str:
    return "'" + s.replace("'", "''") + "'"


def main(out_path: str):
    recent = f"p.created_at > now() - interval '{int(RECENT_DAYS)} days'" if RECENT_DAYS else "true"
    rows = db.rows("select p.id, p.city_id, case when cardinality(p.awards) > 0 then 'michelin' else cat.slug end cat, "
                   f"p.teaser_title, ({recent}) is_new "
                   "from places p join categories cat on cat.id = p.primary_category_id "
                   "where p.source in ('openstreetmap','wikidata') order by 2, 3, p.id")
    out = ["-- Generated by backend/tools/teasers.py — teasers that don't repeat within a city."]
    groups: dict[tuple[str, str], list[str]] = {}
    used: dict[tuple[str, str], set[str]] = {}
    for r in rows:
        if r["cat"] not in T:
            continue
        key = (r["city_id"], r["cat"])
        if r["is_new"] == "t":
            groups.setdefault(key, []).append(r["id"])
        else:
            used.setdefault(key, set()).add(r["teaser_title"])   # keep existing places' teasers as they are
    repeats = 0
    for (city, cat), ids in groups.items():
        titles, descs = T[cat]
        off = h(city + cat)
        free = [x for x in (titles[(off + i) % len(titles)] for i in range(len(titles))) if x not in used.get((city, cat), set())]
        order = free + [x for x in titles if x not in free]   # unused lines first, then repeats
        repeats += max(0, len(ids) - len(free))
        for i, pid in enumerate(ids):
            t = order[i % len(order)]
            d = descs[(off // 7 + i * 3) % len(descs)]
            out.append(f"update public.places set teaser_title={q(t)}, teaser_description={q(d)} where id='{pid}';")
    open(out_path, "w").write("\n".join(out) + "\n")
    print(f"wrote {out_path}: {len(out) - 1} places, {repeats} unavoidable repeats (category larger than its pool)", file=sys.stderr)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "teasers.sql")
