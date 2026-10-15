#!/usr/bin/env python3
"""World importer: turns (country, city, centre) into Secret Places SQL from OpenStreetMap.

Hybrid curation — OSM supplies real, verifiable venues; the importer keeps only the kinds of
place the app is about and ranks them by quality signals (website, opening hours, Wikidata):

  paid (sold through the CITY PASS, no per-place App Store product):
    speakeasy / cocktail bars, rooftop bars, night clubs, and every third viewpoint
  free:
    the other viewpoints, notable historic sites (Wikidata), murals, gardens, specialty coffee

Categories are looked up by slug and cities by (country, slug), so the SQL is portable
between databases. Each city with paid places gets a pass product id
com.secretplaces.city.<slug>.

Usage:
  python3 backend/tools/world_import.py OUT.sql [city-slug ...]          # default: all CITIES
  python3 backend/tools/world_import.py --draft OUT.sql [city-slug ...]  # EUROPE_2 as drafts
  python3 backend/tools/world_import.py --deepen OUT.sql [city-slug ...] # every city again: only new places are added,
                                                                         # each keeps its city's status (published/draft)
Data © OpenStreetMap contributors (ODbL).
"""
import hashlib, json, re, sys, time, unicodedata, urllib.parse, urllib.request

# Overpass mirrors — EU only. Never use Russian-hosted services.
MIRRORS = ["https://overpass-api.de/api/interpreter",
           "https://overpass.private.coffee/api/interpreter",
           "https://overpass.kumi.systems/api/interpreter"]
UA = "SecretPlaces/1.0 (city import; hello@7am.agency)"
RADIUS = 6000
PASS_PRICE_CENTS = 499

# (country slug, country name, flag, city slug, city title, lat, lng)
CITIES = [
    ("ukraine", "Ukraine", "🇺🇦", "lviv", "Lviv", 49.8397, 24.0297),
    ("ukraine", "Ukraine", "🇺🇦", "odesa", "Odesa", 46.4825, 30.7233),
    ("ukraine", "Ukraine", "🇺🇦", "kharkiv", "Kharkiv", 49.9935, 36.2304),
    ("ukraine", "Ukraine", "🇺🇦", "dnipro", "Dnipro", 48.4647, 35.0462),
    ("ukraine", "Ukraine", "🇺🇦", "vinnytsia", "Vinnytsia", 49.2331, 28.4682),
    ("ukraine", "Ukraine", "🇺🇦", "ivano-frankivsk", "Ivano-Frankivsk", 48.9226, 24.7111),
    ("portugal", "Portugal", "🇵🇹", "lisbon", "Lisbon", 38.7223, -9.1393),
    ("spain", "Spain", "🇪🇸", "barcelona", "Barcelona", 41.3874, 2.1686),
    ("france", "France", "🇫🇷", "paris", "Paris", 48.8566, 2.3522),
    ("germany", "Germany", "🇩🇪", "berlin", "Berlin", 52.5200, 13.4050),
    ("netherlands", "Netherlands", "🇳🇱", "amsterdam", "Amsterdam", 52.3676, 4.9041),
    ("czechia", "Czechia", "🇨🇿", "prague", "Prague", 50.0755, 14.4378),
    ("italy", "Italy", "🇮🇹", "rome", "Rome", 41.9028, 12.4964),
    ("turkiye", "Türkiye", "🇹🇷", "istanbul", "Istanbul", 41.0082, 28.9784),
    ("united-kingdom", "United Kingdom", "🇬🇧", "london", "London", 51.5074, -0.1278),
    ("georgia", "Georgia", "🇬🇪", "tbilisi", "Tbilisi", 41.7151, 44.8271),
]

# Later waves are imported as drafts until their city passes are approved:
#   --draft            EUROPE_2
#   --draft=world3     WORLD_3 (Asia + Americas)
#   --draft=world4     WORLD_4 (Africa + Australia/Oceania)
#   --draft=world5     WORLD_5 (more Ukraine, Europe, Caucasus, Asia, Americas)
EUROPE_2 = [
    ("austria", "Austria", "🇦🇹", "vienna", "Vienna", 48.2082, 16.3738),
    ("hungary", "Hungary", "🇭🇺", "budapest", "Budapest", 47.4979, 19.0402),
    ("poland", "Poland", "🇵🇱", "warsaw", "Warsaw", 52.2297, 21.0122),
    ("poland", "Poland", "🇵🇱", "krakow", "Kraków", 50.0647, 19.9450),
    ("denmark", "Denmark", "🇩🇰", "copenhagen", "Copenhagen", 55.6761, 12.5683),
    ("sweden", "Sweden", "🇸🇪", "stockholm", "Stockholm", 59.3293, 18.0686),
    ("spain", "Spain", "🇪🇸", "madrid", "Madrid", 40.4168, -3.7038),
    ("germany", "Germany", "🇩🇪", "munich", "Munich", 48.1351, 11.5820),
    ("italy", "Italy", "🇮🇹", "milan", "Milan", 45.4642, 9.1900),
    ("greece", "Greece", "🇬🇷", "athens", "Athens", 37.9838, 23.7275),
    ("ireland", "Ireland", "🇮🇪", "dublin", "Dublin", 53.3498, -6.2603),
    ("united-kingdom", "United Kingdom", "🇬🇧", "edinburgh", "Edinburgh", 55.9533, -3.1883),
    ("belgium", "Belgium", "🇧🇪", "brussels", "Brussels", 50.8503, 4.3517),
    ("portugal", "Portugal", "🇵🇹", "porto", "Porto", 41.1579, -8.6291),
    ("switzerland", "Switzerland", "🇨🇭", "zurich", "Zürich", 47.3769, 8.5417),
    ("norway", "Norway", "🇳🇴", "oslo", "Oslo", 59.9139, 10.7522),
    ("estonia", "Estonia", "🇪🇪", "tallinn", "Tallinn", 59.4370, 24.7536),
    ("latvia", "Latvia", "🇱🇻", "riga", "Riga", 56.9496, 24.1052),
    ("lithuania", "Lithuania", "🇱🇹", "vilnius", "Vilnius", 54.6872, 25.2797),
    ("italy", "Italy", "🇮🇹", "naples", "Naples", 40.8518, 14.2681),
    ("italy", "Italy", "🇮🇹", "florence", "Florence", 43.7696, 11.2558),
    ("spain", "Spain", "🇪🇸", "seville", "Seville", 37.3891, -5.9845),
    ("spain", "Spain", "🇪🇸", "valencia", "Valencia", 39.4699, -0.3763),
    ("germany", "Germany", "🇩🇪", "hamburg", "Hamburg", 53.5511, 9.9937),
]

WORLD_3 = [
    ("japan", "Japan", "🇯🇵", "tokyo", "Tokyo", 35.6762, 139.6503),
    ("japan", "Japan", "🇯🇵", "kyoto", "Kyoto", 35.0116, 135.7681),
    ("japan", "Japan", "🇯🇵", "osaka", "Osaka", 34.6937, 135.5023),
    ("south-korea", "South Korea", "🇰🇷", "seoul", "Seoul", 37.5665, 126.9780),
    ("taiwan", "Taiwan", "🇹🇼", "taipei", "Taipei", 25.0330, 121.5654),
    ("hong-kong", "Hong Kong", "🇭🇰", "hong-kong", "Hong Kong", 22.2819, 114.1580),
    ("singapore", "Singapore", "🇸🇬", "singapore", "Singapore", 1.2903, 103.8520),
    ("thailand", "Thailand", "🇹🇭", "bangkok", "Bangkok", 13.7563, 100.5018),
    ("malaysia", "Malaysia", "🇲🇾", "kuala-lumpur", "Kuala Lumpur", 3.1390, 101.6869),
    ("vietnam", "Vietnam", "🇻🇳", "hanoi", "Hanoi", 21.0285, 105.8542),
    ("vietnam", "Vietnam", "🇻🇳", "ho-chi-minh-city", "Ho Chi Minh City", 10.7769, 106.7009),
    ("india", "India", "🇮🇳", "mumbai", "Mumbai", 18.9388, 72.8354),
    ("united-arab-emirates", "United Arab Emirates", "🇦🇪", "dubai", "Dubai", 25.2048, 55.2708),
    ("united-states", "United States", "🇺🇸", "new-york", "New York", 40.7306, -73.9866),
    ("united-states", "United States", "🇺🇸", "los-angeles", "Los Angeles", 34.0522, -118.2437),
    ("united-states", "United States", "🇺🇸", "san-francisco", "San Francisco", 37.7749, -122.4194),
    ("united-states", "United States", "🇺🇸", "chicago", "Chicago", 41.8781, -87.6298),
    ("united-states", "United States", "🇺🇸", "miami", "Miami", 25.7617, -80.1918),
    ("united-states", "United States", "🇺🇸", "new-orleans", "New Orleans", 29.9511, -90.0715),
    ("united-states", "United States", "🇺🇸", "austin", "Austin", 30.2672, -97.7431),
    ("canada", "Canada", "🇨🇦", "toronto", "Toronto", 43.6532, -79.3832),
    ("canada", "Canada", "🇨🇦", "montreal", "Montréal", 45.5019, -73.5674),
    ("canada", "Canada", "🇨🇦", "vancouver", "Vancouver", 49.2827, -123.1207),
    ("mexico", "Mexico", "🇲🇽", "mexico-city", "Mexico City", 19.4326, -99.1332),
    ("argentina", "Argentina", "🇦🇷", "buenos-aires", "Buenos Aires", -34.6037, -58.3816),
    ("brazil", "Brazil", "🇧🇷", "sao-paulo", "São Paulo", -23.5505, -46.6333),
    ("brazil", "Brazil", "🇧🇷", "rio-de-janeiro", "Rio de Janeiro", -22.9068, -43.1729),
    ("colombia", "Colombia", "🇨🇴", "bogota", "Bogotá", 4.7110, -74.0721),
    ("peru", "Peru", "🇵🇪", "lima", "Lima", -12.0464, -77.0428),
    ("chile", "Chile", "🇨🇱", "santiago", "Santiago", -33.4489, -70.6693),
]
WORLD_4 = [
    ("morocco", "Morocco", "🇲🇦", "marrakesh", "Marrakesh", 31.6295, -7.9811),
    ("morocco", "Morocco", "🇲🇦", "casablanca", "Casablanca", 33.5731, -7.5898),
    ("morocco", "Morocco", "🇲🇦", "fes", "Fes", 34.0644, -4.9733),
    ("egypt", "Egypt", "🇪🇬", "cairo", "Cairo", 30.0444, 31.2357),
    ("tunisia", "Tunisia", "🇹🇳", "tunis", "Tunis", 36.8065, 10.1815),
    ("south-africa", "South Africa", "🇿🇦", "cape-town", "Cape Town", -33.9249, 18.4241),
    ("south-africa", "South Africa", "🇿🇦", "johannesburg", "Johannesburg", -26.2041, 28.0473),
    ("south-africa", "South Africa", "🇿🇦", "durban", "Durban", -29.8587, 31.0218),
    ("kenya", "Kenya", "🇰🇪", "nairobi", "Nairobi", -1.2864, 36.8172),
    ("tanzania", "Tanzania", "🇹🇿", "zanzibar", "Zanzibar City", -6.1659, 39.2026),
    ("nigeria", "Nigeria", "🇳🇬", "lagos", "Lagos", 6.4541, 3.3947),
    ("ghana", "Ghana", "🇬🇭", "accra", "Accra", 5.6037, -0.1870),
    ("senegal", "Senegal", "🇸🇳", "dakar", "Dakar", 14.7167, -17.4677),
    ("rwanda", "Rwanda", "🇷🇼", "kigali", "Kigali", -1.9441, 30.0619),
    ("australia", "Australia", "🇦🇺", "sydney", "Sydney", -33.8688, 151.2093),
    ("australia", "Australia", "🇦🇺", "melbourne", "Melbourne", -37.8136, 144.9631),
    ("australia", "Australia", "🇦🇺", "brisbane", "Brisbane", -27.4698, 153.0251),
    ("australia", "Australia", "🇦🇺", "perth", "Perth", -31.9523, 115.8613),
    ("australia", "Australia", "🇦🇺", "adelaide", "Adelaide", -34.9285, 138.6007),
    ("australia", "Australia", "🇦🇺", "hobart", "Hobart", -42.8821, 147.3272),
    ("new-zealand", "New Zealand", "🇳🇿", "auckland", "Auckland", -36.8485, 174.7633),
    ("new-zealand", "New Zealand", "🇳🇿", "wellington", "Wellington", -41.2865, 174.7762),
    ("new-zealand", "New Zealand", "🇳🇿", "queenstown", "Queenstown", -45.0312, 168.6626),
]
WORLD_5 = [
    ("ukraine", "Ukraine", "🇺🇦", "chernivtsi", "Chernivtsi", 48.2921, 25.9358),
    ("ukraine", "Ukraine", "🇺🇦", "uzhhorod", "Uzhhorod", 48.6208, 22.2879),
    ("ukraine", "Ukraine", "🇺🇦", "ternopil", "Ternopil", 49.5535, 25.5948),
    ("ukraine", "Ukraine", "🇺🇦", "lutsk", "Lutsk", 50.7472, 25.3254),
    ("ukraine", "Ukraine", "🇺🇦", "kamianets-podilskyi", "Kamianets-Podilskyi", 48.6789, 26.5853),
    ("ukraine", "Ukraine", "🇺🇦", "poltava", "Poltava", 49.5883, 34.5514),
    ("ukraine", "Ukraine", "🇺🇦", "zaporizhzhia", "Zaporizhzhia", 47.8388, 35.1396),
    ("spain", "Spain", "🇪🇸", "malaga", "Málaga", 36.7213, -4.4214),
    ("spain", "Spain", "🇪🇸", "san-sebastian", "San Sebastián", 43.3183, -1.9812),
    ("italy", "Italy", "🇮🇹", "venice", "Venice", 45.4408, 12.3155),
    ("italy", "Italy", "🇮🇹", "bologna", "Bologna", 44.4949, 11.3426),
    ("italy", "Italy", "🇮🇹", "turin", "Turin", 45.0703, 7.6869),
    ("france", "France", "🇫🇷", "lyon", "Lyon", 45.7640, 4.8357),
    ("france", "France", "🇫🇷", "marseille", "Marseille", 43.2965, 5.3698),
    ("france", "France", "🇫🇷", "nice", "Nice", 43.7102, 7.2620),
    ("france", "France", "🇫🇷", "bordeaux", "Bordeaux", 44.8378, -0.5792),
    ("germany", "Germany", "🇩🇪", "cologne", "Cologne", 50.9375, 6.9603),
    ("germany", "Germany", "🇩🇪", "leipzig", "Leipzig", 51.3397, 12.3731),
    ("netherlands", "Netherlands", "🇳🇱", "rotterdam", "Rotterdam", 51.9244, 4.4777),
    ("belgium", "Belgium", "🇧🇪", "antwerp", "Antwerp", 51.2194, 4.4025),
    ("belgium", "Belgium", "🇧🇪", "ghent", "Ghent", 51.0543, 3.7174),
    ("austria", "Austria", "🇦🇹", "salzburg", "Salzburg", 47.8095, 13.0550),
    ("slovenia", "Slovenia", "🇸🇮", "ljubljana", "Ljubljana", 46.0569, 14.5058),
    ("croatia", "Croatia", "🇭🇷", "zagreb", "Zagreb", 45.8150, 15.9819),
    ("croatia", "Croatia", "🇭🇷", "split", "Split", 43.5081, 16.4402),
    ("croatia", "Croatia", "🇭🇷", "dubrovnik", "Dubrovnik", 42.6507, 18.0944),
    ("serbia", "Serbia", "🇷🇸", "belgrade", "Belgrade", 44.8125, 20.4612),
    ("bulgaria", "Bulgaria", "🇧🇬", "sofia", "Sofia", 42.6977, 23.3219),
    ("romania", "Romania", "🇷🇴", "bucharest", "Bucharest", 44.4268, 26.1025),
    ("moldova", "Moldova", "🇲🇩", "chisinau", "Chișinău", 47.0105, 28.8638),
    ("finland", "Finland", "🇫🇮", "helsinki", "Helsinki", 60.1699, 24.9384),
    ("norway", "Norway", "🇳🇴", "bergen", "Bergen", 60.3913, 5.3221),
    ("malta", "Malta", "🇲🇹", "valletta", "Valletta", 35.8989, 14.5146),
    ("iceland", "Iceland", "🇮🇸", "reykjavik", "Reykjavík", 64.1466, -21.9426),
    ("united-kingdom", "United Kingdom", "🇬🇧", "manchester", "Manchester", 53.4808, -2.2426),
    ("united-kingdom", "United Kingdom", "🇬🇧", "glasgow", "Glasgow", 55.8642, -4.2518),
    ("georgia", "Georgia", "🇬🇪", "batumi", "Batumi", 41.6168, 41.6367),
    ("armenia", "Armenia", "🇦🇲", "yerevan", "Yerevan", 40.1792, 44.4991),
    ("azerbaijan", "Azerbaijan", "🇦🇿", "baku", "Baku", 40.4093, 49.8671),
    ("kazakhstan", "Kazakhstan", "🇰🇿", "almaty", "Almaty", 43.2380, 76.9450),
    ("uzbekistan", "Uzbekistan", "🇺🇿", "samarkand", "Samarkand", 39.6542, 66.9597),
    ("thailand", "Thailand", "🇹🇭", "chiang-mai", "Chiang Mai", 18.7883, 98.9853),
    ("indonesia", "Indonesia", "🇮🇩", "ubud", "Ubud", -8.5069, 115.2625),
    ("indonesia", "Indonesia", "🇮🇩", "jakarta", "Jakarta", -6.1754, 106.8272),
    ("philippines", "Philippines", "🇵🇭", "manila", "Manila", 14.5995, 120.9842),
    ("india", "India", "🇮🇳", "jaipur", "Jaipur", 26.9124, 75.7873),
    ("india", "India", "🇮🇳", "delhi", "Delhi", 28.6139, 77.2090),
    ("nepal", "Nepal", "🇳🇵", "kathmandu", "Kathmandu", 27.7172, 85.3240),
    ("united-states", "United States", "🇺🇸", "boston", "Boston", 42.3601, -71.0589),
    ("united-states", "United States", "🇺🇸", "seattle", "Seattle", 47.6062, -122.3321),
    ("united-states", "United States", "🇺🇸", "portland", "Portland", 45.5152, -122.6784),
    ("united-states", "United States", "🇺🇸", "washington", "Washington, D.C.", 38.9072, -77.0369),
    ("united-states", "United States", "🇺🇸", "philadelphia", "Philadelphia", 39.9526, -75.1652),
    ("united-states", "United States", "🇺🇸", "nashville", "Nashville", 36.1627, -86.7816),
    ("united-states", "United States", "🇺🇸", "las-vegas", "Las Vegas", 36.1699, -115.1398),
    ("canada", "Canada", "🇨🇦", "quebec-city", "Québec City", 46.8139, -71.2080),
    ("mexico", "Mexico", "🇲🇽", "oaxaca", "Oaxaca", 17.0732, -96.7266),
    ("mexico", "Mexico", "🇲🇽", "guadalajara", "Guadalajara", 20.6597, -103.3496),
    ("cuba", "Cuba", "🇨🇺", "havana", "Havana", 23.1136, -82.3666),
    ("colombia", "Colombia", "🇨🇴", "medellin", "Medellín", 6.2442, -75.5812),
    ("colombia", "Colombia", "🇨🇴", "cartagena", "Cartagena", 10.3910, -75.4794),
    ("peru", "Peru", "🇵🇪", "cusco", "Cusco", -13.5320, -71.9675),
    ("ecuador", "Ecuador", "🇪🇨", "quito", "Quito", -0.1807, -78.4678),
    ("uruguay", "Uruguay", "🇺🇾", "montevideo", "Montevideo", -34.9011, -56.1645),
    ("chile", "Chile", "🇨🇱", "valparaiso", "Valparaíso", -33.0472, -71.6127),
    ("panama", "Panama", "🇵🇦", "panama-city", "Panama City", 8.9824, -79.5199),
]



# kind -> (category slug, cap per city)
KINDS = {
    "speakeasy": ("bars", 20), "rooftop": ("rooftops", 10), "night": ("night", 10), "viewpoint": ("viewpoints", 12),
    "historic": ("architecture", 15), "landmark": ("culture", 10), "mural": ("culture", 10), "garden": ("walks", 8),
    "coffee": ("coffee", 15), "food": ("food_drink", 10), "pub": ("bars", 6), "museum": ("culture", 8),
    "market": ("food_drink", 5), "books": ("culture", 5), "beach": ("beaches", 6), "park": ("nature", 6),
}
PAID_KINDS = {"speakeasy", "rooftop", "night", "food", "pub"}

TEASERS = {
    "speakeasy": (["A drink behind an unmarked door", "A bar the regulars keep quiet about", "A low-lit room that doesn't advertise",
                   "A cocktail bar you only find by asking", "The nightcap spot that isn't on the map", "A bar that trusts you to find it"],
                  ["No sign shouting for attention — just a door, and people who already know.",
                   "Small, unhurried, and better the later it gets.",
                   "Ask the right people and they'll send you here.",
                   "A short menu, a long memory, and nobody in a hurry to leave.",
                   "You have to know it's there — then it's the easiest place in the city to stay too long."]),
    "rooftop": (["A rooftop the city keeps to itself", "Drinks above the skyline", "A terrace most people never find",
                 "Golden hour, one floor below the sky"],
                ["Take the lift most people don't notice and the whole city opens up.",
                 "Come before sunset and stay for the lights.",
                 "Above the noise, with a view worth the climb."]),
    "night": (["A night that starts after midnight", "A club you find by asking", "A room that runs till sunrise",
               "Sound, concrete and a crowd who already know"],
              ["No frontage, no list online — just the people who know.",
               "Come late, leave early — in the morning.",
               "The door is the hard part; the rest takes care of itself."]),
    "viewpoint": (["A view over the city most people miss", "The overlook locals save for golden hour",
                   "A quiet ledge with a very loud view", "Where the city lays itself out below"],
                  ["Climb a little and the whole district unfolds — if you know where to stand.",
                   "Come at dusk and watch the rooftops catch the last light.",
                   "Everyone walks past the turn — take it, and look up."]),
    "historic": (["A piece of the city's story, hiding in plain sight", "A landmark the tours rush past",
                  "Old stones with a better story than the guidebook", "A corner of history worth slowing down for"],
                 ["Most people walk straight past — stop, and it starts talking.",
                  "Off the main route, and all the better for it.",
                  "Small, quiet, and older than everything around it."]),
    "landmark": (["A local landmark with a better story than the sign", "A corner of the city worth slowing down for",
                  "The place locals take visiting friends", "Something the city is quietly proud of"],
                 ["Go early, before the crowds, and it feels like yours.",
                  "Most people rush past — give it ten minutes.",
                  "Small detail, long history, worth the short detour."]),
    "mural": (["A wall worth the detour", "Street art you'll only spot if you look up", "The mural locals point friends to"],
              ["Turn the corner and there it is — bigger than you expected.",
               "A wall most people walk straight past.",
               "Find it yourself and it feels like yours."]),
    "garden": (["A green pocket to slow down in", "A garden most people rush past", "A quiet loop away from the crowds"],
               ["Trees, a path, and room to breathe five minutes from the noise.",
                "Come with a coffee and stay longer than you planned.",
                "Enough green to forget you're in the middle of the city."]),
    "food": (["A table the locals book for themselves", "A kitchen with a long local story", "The dinner spot friends send friends to",
              "A dining room older than the guidebooks"],
             ["Order what the next table is having — they've been coming for years.",
              "Go hungry, and go without a plan.",
              "A place the city has quietly kept for itself."]),
    "pub": (["A pub with more history than its sign", "A bar the city grew up around", "A local that has outlived its rivals"],
            ["Worn wood, old stories and a regular in every corner.",
             "Come for one, stay for the stories.",
             "The kind of room that remembers everyone who's been."]),
    "museum": (["A small museum most visitors skip", "A collection the city keeps quiet about", "A museum for the curious, not the crowds"],
               ["Room after room of things you didn't know you wanted to see.",
                "Quiet halls, odd treasures, and almost nobody else.",
                "An hour here tells you more than a day of sightseeing."]),
    "market": (["A market where the city shops", "Stalls, smells and a morning well spent", "The market locals actually use"],
               ["Come early, bring cash, and follow the longest queue.",
                "Eat as you go — it's the point.",
                "Loud, fresh and very much alive."]),
    "books": (["A bookshop to lose an afternoon in", "Shelves worth the detour", "A bookshop with a personality"],
              ["Narrow aisles, good taste, and nobody rushing you out.",
               "Browse slowly — the best finds are on the bottom shelf.",
               "A quiet corner of the city made of paper."]),
    "beach": (["A stretch of sand the crowds skip", "A beach for the end of the day", "Where the city meets the water"],
              ["Bring a towel and lose track of time.",
               "Come at sunset when the day-trippers leave.",
               "Close enough to reach on a whim, far enough to forget the city."]),
    "park": (["A park bigger than it looks from the gate", "Green space the city breathes through", "A long walk under old trees"],
             ["Paths that wander, benches that wait, and room to think.",
              "Pack a lunch and let the afternoon go.",
              "The city goes quiet the moment you step inside."]),
    "coffee": (["A specialty coffee spot down a side street", "The pour-over place friends whisper about",
                "A tiny café that takes coffee seriously"],
               ["A few seats, a good roast, and mornings that stretch.",
                "Tucked away, but the espresso is why people keep coming back.",
                "Blink and you'd miss the door — don't."]),
}
SPEAKEASY_RX = re.compile(r"speak ?easy|secret|hidden|clandestin|unmarked|backroom|apothe|alchem|cocktail", re.I)
HISTORIC_OK = {"building", "castle", "monument", "ruins", "city_gate", "fort", "manor", "archaeological_site",
               "tower", "palace", "citywalls", "church", "monastery", "aqueduct", "bridge"}
GENERIC_WORDS = {"bar", "speakeasy", "cocktail", "cocktails", "the", "club", "rooftop", "cafe", "coffee", "lounge", "and", "wine"}
ROOFTOP_RX = re.compile(r"roof|rooftop|terrace|terraza|terrasse|sky|360|panoram", re.I)


def h(s: str) -> int:
    return int(hashlib.md5(s.encode()).hexdigest(), 16)


def slugify(s: str) -> str:
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode().lower()
    return re.sub(r"[^a-z0-9]+", "-", s).strip("-")[:36]


def esc(s):
    return s.replace("'", "''") if s else s


SELECTORS = [  # one light query each; a single combined query times out on big cities
    'node["tourism"="viewpoint"]["name"]', 'node["amenity"="bar"]["name"]', 'node["amenity"="nightclub"]["name"]',
    'node["rooftop"="yes"]["name"]', 'node["amenity"="cafe"]["cuisine"~"coffee"]["name"]',
    'node["tourism"="artwork"]["artwork_type"="mural"]["name"]', 'node["historic"]["name"]["wikidata"]',
    'node["leisure"="garden"]["name"]', 'node["tourism"="attraction"]["name"]["wikidata"]',
    'node["amenity"="restaurant"]["name"]["wikidata"]', 'node["amenity"="pub"]["name"]["wikidata"]',
    'nwr["tourism"="museum"]["name"]', 'nwr["amenity"="marketplace"]["name"]', 'node["shop"="books"]["name"]',
    'nwr["natural"="beach"]["name"]', 'way["leisure"="park"]["name"]["wikidata"]',
]


def overpass_one(sel: str, lat: float, lng: float) -> list[dict] | None:
    q = f"[out:json][timeout:60];{sel}(around:{RADIUS},{lat},{lng});out center 400;"
    data = urllib.parse.urlencode({"data": q}).encode()
    for attempt in range(4):
        for m in MIRRORS:
            try:
                req = urllib.request.Request(m, data=data, headers={"User-Agent": UA})
                with urllib.request.urlopen(req, timeout=75) as resp:
                    return json.loads(resp.read()).get("elements", [])
            except Exception as ex:
                print(f"  {m.split('/')[2]}: {str(ex)[:60]}", file=sys.stderr)
                time.sleep(2)
        time.sleep(10 * (attempt + 1))
    return None


def overpass(lat: float, lng: float) -> list[dict]:
    out, failed = [], 0
    for i, sel in enumerate(SELECTORS):
        els = overpass_one(sel, lat, lng)
        if els is None:
            if i == 0:   # every mirror down: don't spend half an hour retrying the rest
                return []
            failed += 1
            continue
        for e in els:   # ways/relations come back with a centre point
            if "lat" not in e and "center" in e:
                e["lat"], e["lon"] = e["center"]["lat"], e["center"]["lon"]
        out += [e for e in els if e.get("tags", {}).get("name") and "lat" in e]
        time.sleep(1)
    if failed > len(SELECTORS) // 2:   # mostly failed: report nothing rather than a lopsided city
        return []
    return out


def kind_of(t: dict) -> str | None:
    name = t.get("name", "")
    blob = " ".join([name, t.get("description", ""), t.get("bar", "")])
    if t.get("amenity") == "nightclub":
        return "night"
    if t.get("rooftop") == "yes" or (t.get("amenity") in ("bar", "restaurant") and ROOFTOP_RX.search(name)):
        return "rooftop"
    if t.get("amenity") == "bar" and (SPEAKEASY_RX.search(blob) or t.get("cocktails") == "yes" or t.get("drink:cocktail") in ("yes", "served")):
        return "speakeasy"
    if t.get("amenity") == "pub" and t.get("wikidata"):
        return "pub"
    if t.get("amenity") == "restaurant" and t.get("wikidata"):
        return "food"
    if t.get("tourism") == "viewpoint":
        return "viewpoint"
    if t.get("tourism") == "artwork":
        return "mural"
    if t.get("historic") in HISTORIC_OK and t.get("wikidata"):
        return "historic"
    if t.get("tourism") == "attraction" and t.get("wikidata"):
        return "landmark"
    if t.get("tourism") == "museum":
        return "museum"
    if t.get("amenity") == "marketplace":
        return "market"
    if t.get("shop") == "books":
        return "books"
    if t.get("natural") == "beach":
        return "beach"
    if t.get("leisure") == "park":
        return "park"
    if t.get("leisure") == "garden":
        return "garden"
    if t.get("amenity") == "cafe":
        return "coffee"
    return None


def quality(t: dict) -> int:
    return (3 if t.get("wikidata") else 0) + (2 if (t.get("website") or t.get("contact:website")) else 0) \
        + (1 if t.get("opening_hours") else 0) + (1 if t.get("addr:street") else 0)


def pick(elements: list[dict], city_slug: str) -> list[tuple[str, dict]]:
    by_kind: dict[str, list[dict]] = {k: [] for k in KINDS}
    seen: list[tuple[str, float, float]] = []
    for e in sorted(elements, key=lambda e: -quality(e["tags"])):
        k = kind_of(e["tags"])
        if not k:
            continue
        # "Red Frog - Speakeasy Bar" and "Red Frog Speakeasy" 50 m apart are one place
        core = "-".join(w for w in slugify(e["tags"]["name"]).split("-") if w not in GENERIC_WORDS) or slugify(e["tags"]["name"])
        if any(core == c and abs(e["lat"] - la) < 0.004 and abs(e["lon"] - lo) < 0.004 for c, la, lo in seen):
            continue
        seen.append((core, e["lat"], e["lon"]))
        by_kind[k].append(e)
    out = []
    for k, (_, cap) in KINDS.items():
        ranked = sorted(by_kind[k], key=lambda e: (-quality(e["tags"]), h(f"{city_slug}{e['id']}")))
        out += [(k, e) for e in ranked[:cap]]
    return out


STATUS = "published"
DEEPEN = False
KYIV = ("ukraine", "Ukraine", "🇺🇦", "kyiv", "Kyiv", 50.4501, 30.5234)


def city_sql(c) -> tuple[list[str], int, int]:
    country_slug, country_name, flag, cslug, ctitle, clat, clng = c
    els = overpass(clat, clng)
    if not els:   # public Overpass mirrors down — fall back to a BBBike extract (server venv has pyosmium)
        import extract
        els = extract.elements(cslug, ctitle, clat, clng, RADIUS) or []
    picked = pick(els, cslug)
    if not picked:
        return [], 0, 0
    country = f"(select id from public.countries where slug='{country_slug}')"
    city = f"(select id from public.cities where slug='{cslug}' and country_id={country})"
    sql = [f"\n-- {ctitle}, {country_name}",
           f"insert into public.countries (slug,name,emoji_flag) values ('{country_slug}','{esc(country_name)}','{flag}') on conflict (slug) do nothing;",
           f"insert into public.cities (country_id,slug,title,lat,lng,is_outside_city) values ({country},'{cslug}','{esc(ctitle)}',{clat},{clng},false) "
           f"on conflict (country_id,slug) do nothing;"]
    status_sql = (f"(select case when exists (select 1 from public.places where city_id={city} and status='published') "
                  f"then 'published' else 'draft' end)") if DEEPEN else f"'{STATUS}'"
    vals, paid_n = [], 0
    for i, (k, e) in enumerate(picked):
        t = e["tags"]; lat, lng = e["lat"], e["lon"]
        # Prefer the English name where the local one isn't Latin script (Tokyo, Seoul, Bangkok…).
        local, en = t["name"], t.get("name:en")
        name = f"{en} ({local})" if en and en != local and not local.isascii() and not slugify(local) else local
        slug = f"{cslug}-{slugify(en or local) or k}-{hashlib.md5(str(e['id']).encode()).hexdigest()[:6]}"
        titles, descs = TEASERS[k]
        tt, td = titles[h(slug) % len(titles)], descs[h(slug + 'd') % len(descs)]
        paid = k in PAID_KINDS or (k == "viewpoint" and h(slug + "p") % 3 == 0)
        paid_n += paid
        addr = (t["addr:street"] + (" " + t["addr:housenumber"] if t.get("addr:housenumber") else "") + f", {ctitle}") if t.get("addr:street") else ctitle
        website = t.get("website") or t.get("contact:website")
        oh = t.get("opening_hours")
        fd = f"{name}. " + (f"Find it at {addr}. " if t.get("addr:street") else f"In {ctitle}. ") + (f"Hours: {oh}. " if oh else "") + "Data © OpenStreetMap contributors."
        featured = "true" if (k in ("speakeasy", "viewpoint", "rooftop") and h(slug + "f") % 6 == 0) else "false"
        editors = "true" if quality(t) >= 4 and h(slug + "e") % 3 == 0 else "false"
        best_time = {"night": "night", "speakeasy": "evening", "rooftop": "sunset", "viewpoint": "sunset", "coffee": "morning", "landmark": "morning",
                     "food": "evening", "pub": "evening", "market": "morning", "beach": "sunset"}.get(k, "afternoon")
        duration = {"night": 240, "speakeasy": 90, "rooftop": 90, "coffee": 45, "food": 90, "pub": 90, "beach": 120, "books": 45}.get(k, 60)
        q = lambda v: f"'{esc(v)}'" if v else "null"
        vals.append(f"('{slug}','{esc(tt)}','{esc(td)}','{esc(name)}','{esc(fd)}',{lat},{lng},{round(lat, 2)},{round(lng, 2)},"
                    f"'{esc(addr)}','{esc(name)}',{q(website)},{q(oh)},'{KINDS[k][0]}','{'paid' if paid else 'free'}',"
                    f"{PASS_PRICE_CENTS if paid else 0},{featured},{editors},'{best_time}',{duration},'{e['id']}',{q(t.get('wikidata', '').split(';')[0].strip())})")
    sql.append(
        "insert into public.places (slug,teaser_title,teaser_description,full_title,full_description,exact_lat,exact_lng,approx_lat,approx_lng,"
        "exact_address,business_name,website,opening_hours,walking_instructions,apple_maps_url,google_maps_url,country_id,city_id,primary_category_id,"
        "access_type,price_cents,product_id,status,featured,editors_choice,travel_time_min,recommended_transport,best_time,best_season,"
        "expected_duration_min,crowd_level,price_level,mobile_signal,source,source_ref,wikidata)\n"
        "select v.slug,v.tt,v.td,v.ft,v.fd,v.lat,v.lng,v.alat,v.alng,v.addr,v.biz,v.ws,"
        "(case when v.oh is null then null else jsonb_build_object('raw',v.oh) end),"
        "'From the nearest stop it''s a short walk — look for the entrance, not a sign.',"
        "'https://maps.apple.com/?ll='||v.lat||','||v.lng,'https://www.google.com/maps/search/?api=1&query='||v.lat||','||v.lng,"
        f"{country},{city},(select id from public.categories where slug=v.cat),v.access,v.price,null,{status_sql},v.featured,v.editors,"
        "15,'walk',v.best,'all year',v.dur,'medium',2,'good','openstreetmap',v.sref,v.wd\nfrom (values\n" + ",\n".join(vals) +
        "\n) v(slug,tt,td,ft,fd,lat,lng,alat,alng,addr,biz,ws,oh,cat,access,price,featured,editors,best,dur,sref,wd)\n"
        # a restaurant already added from Wikidata (wikidata_enrich.py) under another slug is the same place
        "where v.wd is null or not exists (select 1 from public.places x where x.wikidata = v.wd)\non conflict (slug) do nothing;")
    if paid_n:
        sql.append(f"update public.cities set pass_product_id='com.secretplaces.city.{cslug.replace('-', '_')}', pass_price_cents={PASS_PRICE_CENTS} "
                   f"where slug='{cslug}' and country_id={country};")
    return sql, len(picked), paid_n


if __name__ == "__main__":
    args = sys.argv[1:]
    waves = {"--draft": EUROPE_2, "--draft=world3": WORLD_3, "--draft=world4": WORLD_4, "--draft=world5": WORLD_5}   # later waves stay hidden until their passes are approved
    for flag, wave in waves.items():
        if flag in args:
            args.remove(flag); STATUS = "draft"; CITIES = wave
    if "--deepen" in args:      # all cities again; on conflict (slug) keeps what's there
        args.remove("--deepen"); DEEPEN = True; CITIES = [KYIV] + CITIES + EUROPE_2 + WORLD_3 + WORLD_4 + WORLD_5
    out_path = args[0] if args else "world_seed.sql"
    only = set(args[1:])
    lines = ["-- Generated by backend/tools/world_import.py — real places from OpenStreetMap (ODbL), © OpenStreetMap contributors."]
    for c in CITIES:
        if only and c[3] not in only:
            continue
        sql, n, paid = city_sql(c)
        print(f"{c[4]:16s} {n:3d} places ({paid} paid via city pass)", flush=True)
        lines += sql
        time.sleep(5)  # be polite to the public Overpass mirrors
    open(out_path, "w").write("\n".join(lines) + "\n")
    print("wrote", out_path)
