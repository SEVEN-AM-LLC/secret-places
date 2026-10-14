#!/usr/bin/env python3
# Reusable OSM importer: turns (city, center) into curated Secret Places SQL.
import json, urllib.request, urllib.parse, time, hashlib, re, sys

# Overpass mirrors — EU only. Never use Russian-hosted services.
MIRRORS=["https://overpass-api.de/api/interpreter",
         "https://overpass.kumi.systems/api/interpreter",
         "https://overpass.private.coffee/api/interpreter",
         "https://overpass.osm.ch/api/interpreter"]
UA="SecretPlaces/1.0 (world seed)"

CATID={'viewpoints':'53563598-2466-4347-981e-004b31a9efba','bars':'07912007-6a3f-4034-b067-e3438649de72',
       'coffee':'b4933bc8-24fa-49f3-9ca1-00214956e248','walks':'14632edb-43ee-4bf8-95bd-afe4598c49b4',
       'culture':'545c90c8-75ac-4b25-8115-ef6e6d6fc947'}
SEL={'viewpoints':'node["tourism"="viewpoint"]',
     'bars':'node["amenity"="bar"]["name"]',
     'coffee':'node["amenity"="cafe"]["cuisine"="coffee_shop"]["name"]',
     'walks':'node["leisure"="park"]["name"]',
     'culture':'node["tourism"="artwork"]["name"]'}
CAP={'viewpoints':10,'bars':12,'coffee':10,'walks':6,'culture':10}

TEASERS={
 'viewpoints':(['A view over the city most people miss','A rooftop-height panorama without the crowd','The overlook locals save for golden hour','A quiet ledge with a very loud view','A skyline moment hiding in plain sight','Where the city lays itself out below'],
   ['Climb a little and the whole district unfolds — if you know where to stand.','No queue, no ticket booth — just the skyline and whoever already knows.','Come at dusk and watch the rooftops catch the last light.','Tucked off the main path, it opens onto more of the city than you would expect.','Everyone walks past the turn — take it, and look up.','A short climb, a wide horizon, and almost nobody else.']),
 'bars':(['A bar the regulars keep quiet about','A drink behind an unmarked door','A low-lit room that does not advertise','A hidden pour worth the detour','The nightcap spot that is not on the map','A bar that trusts you to find it'],
   ['No queue, no sign shouting for attention — just a door, and people who already know.','You have to know it is there — then it is the easiest place in the city to stay too long.','Small, unhurried, and better the later it gets.','Off the main strip, with a short menu and a long memory.','Ask the right people and they will send you here.','No frontage, no fuss — just good drinks and people in on the secret.']),
 'coffee':(['A specialty coffee spot down a side street','The quiet cup locals do not post about','A hidden roastery-cafe worth the walk','A slow-morning coffee corner','The pour-over place friends whisper about','A tiny cafe that takes coffee seriously'],
   ['Small, unhurried, and serious about the pour — the kind of place you keep to yourself.','A few seats, a good roast, and mornings that stretch.','Tucked away, but the espresso is the reason people keep coming back.','No rush, no crowd — just a proper flat white and a window seat.','Off the tourist track, and all the better for it.','Blink and you would miss the door — do not.']),
 'walks':(['A green pocket to slow down in','A patch of calm most people rush past','The park bench locals keep for themselves','A quiet loop away from the crowds','A slow walk the guidebooks skip','A hidden bit of green worth finding'],
   ['A quiet corner of the city to walk off a morning — away from the main flow.','Trees, a path, and room to breathe five minutes from the noise.','Come with a coffee and stay longer than you planned.','Enough green to forget you are in the middle of the city.','Nothing to tick off — just somewhere good to wander.','Off the main avenue, and calmer for it.']),
 'culture':(['A piece of the city worth finding','Street art you will only spot if you look up','A small monument with a big story','A detail of the city hiding in plain sight','The mural locals point friends to','A quiet landmark the tours miss'],
   ['A small landmark most guides skip — go look before everyone else does.','A wall most people walk straight past — turn the corner and there it is.','Off the main square, but it stops you when you find it.','No plaque, no crowd — just something worth the short detour.','Tucked into a courtyard, and better in person.','Find it yourself and it feels like yours.']),
}
# basic transliteration for slugs (cyrillic/greek left to regex fallback)
def slugify(s):
    s=s.lower()
    out=re.sub(r'[^a-z0-9]+','-', s.encode('ascii','ignore').decode()).strip('-')
    return out[:36]
def esc(s): return s.replace("'","''") if s else s

def overpass(sel, lat, lng, radius, cap):
    q=f'[out:json][timeout:20];{sel}(around:{radius},{lat},{lng});out body {cap};'
    data=urllib.parse.urlencode({'data':q}).encode()
    for m in MIRRORS:
        for _ in range(1):
            try:
                req=urllib.request.Request(m, data=data, headers={'User-Agent':UA})
                with urllib.request.urlopen(req, timeout=18) as r:
                    j=json.loads(r.read())
                els=[e for e in j.get('elements',[]) if e.get('tags',{}).get('name') and e.get('lat') and e.get('lon')]
                if els: return els
            except Exception:
                time.sleep(1)
    return []

CITIES=[
 ('portugal','Portugal','🇵🇹','lisbon','Lisbon',38.7223,-9.1393),
 ('spain','Spain','🇪🇸','barcelona','Barcelona',41.3874,2.1686),
 ('france','France','🇫🇷','paris','Paris',48.8566,2.3522),
 ('germany','Germany','🇩🇪','berlin','Berlin',52.52,13.405),
 ('netherlands','Netherlands','🇳🇱','amsterdam','Amsterdam',52.3676,4.9041),
 ('czechia','Czechia','🇨🇿','prague','Prague',50.0755,14.4378),
 ('italy','Italy','🇮🇹','rome','Rome',41.9028,12.4964),
 ('turkiye','Türkiye','🇹🇷','istanbul','Istanbul',41.0082,28.9784),
 ('united-kingdom','United Kingdom','🇬🇧','london','London',51.5074,-0.1278),
 ('georgia','Georgia','🇬🇪','tbilisi','Tbilisi',41.7151,44.8271),
]

def variant(cat, slug, arr):
    i=int(hashlib.md5(slug.encode()).hexdigest(),16)%len(arr)
    return arr[i]

out=[]
out.append("-- World seed: real places from OpenStreetMap (ODbL). (c) OpenStreetMap contributors.")
summary={}
for country_slug,country_name,emoji,cslug,ctitle,clat,clng in CITIES:
    rows=[]
    used=set()
    for cat,sel in SEL.items():
        els=overpass(sel,clat,clng,5000,CAP[cat])
        for i,e in enumerate(els):
            t=e['tags']; name=t['name']; lat=e['lat']; lng=e['lon']
            base=slugify(name) or cat
            slug=f"{cslug}-{base}-{hashlib.md5(str(e['id']).encode()).hexdigest()[:6]}"
            if slug in used: continue
            used.add(slug)
            tt=variant(cat,slug,TEASERS[cat][0]); td=variant(cat,slug,TEASERS[cat][1])
            paid = cat in ('bars','coffee','viewpoints') and (int(hashlib.md5((slug+'p').encode()).hexdigest(),16)%4==0)
            access='paid' if paid else 'free'; price=99 if paid else 0
            addr=None
            if t.get('addr:street'): addr=t['addr:street']+(' '+t['addr:housenumber'] if t.get('addr:housenumber') else '')+f", {ctitle}"
            website=t.get('website') or t.get('contact:website'); oh=t.get('opening_hours')
            fd=f"{name}. "+(f"Find it at {addr}. " if addr else f"In {ctitle}. ")+(f"Hours: {oh}. " if oh else "")+"Data (c) OpenStreetMap contributors."
            featured='true' if (cat=='viewpoints' and i<2) else 'false'
            editors='true' if int(hashlib.md5((slug+'e').encode()).hexdigest(),16)%9==0 else 'false'
            rows.append((slug,tt,td,name,fd,lat,lng,round(lat,2),round(lng,2),addr or f"{ctitle}",name,
                         website,oh,CATID[cat],access,price,(f"com.secretplaces.place.{slug.replace('-', '_')}" if paid else None),
                         featured,editors,str(e['id'])))
    summary[cslug]=len(rows)
    if not rows: continue
    out.append(f"insert into public.countries (slug,name,emoji_flag) values ('{country_slug}','{esc(country_name)}','{emoji}') on conflict (slug) do nothing;")
    out.append(f"insert into public.cities (country_id,slug,title,lat,lng,is_outside_city) select (select id from public.countries where slug='{country_slug}'),'{cslug}','{esc(ctitle)}',{clat},{clng},false on conflict (country_id,slug) do nothing;")
    vals=[]
    for r in rows:
        slug,tt,td,ft,fd,lat,lng,alat,alng,addr,biz,website,oh,cat,access,price,product,featured,editors,sref=r
        ws=f"'{esc(website)}'" if website else 'null'
        ohv=f"'{esc(oh)}'" if oh else 'null'
        prod=f"'{product}'" if product else 'null'
        vals.append(f"('{slug}','{esc(tt)}','{esc(td)}','{esc(ft)}','{esc(fd)}',{lat},{lng},{alat},{alng},'{esc(addr)}','{esc(biz)}',{ws},{ohv},'{cat}','{access}',{price},{prod},{featured},{editors},'{sref}')")
    out.append(
      f"with c as (select (select id from public.countries where slug='{country_slug}') country,(select id from public.cities where slug='{cslug}') city)\n"
      "insert into public.places (slug,teaser_title,teaser_description,full_title,full_description,exact_lat,exact_lng,approx_lat,approx_lng,exact_address,business_name,website,opening_hours,walking_instructions,apple_maps_url,google_maps_url,country_id,city_id,primary_category_id,access_type,price_cents,product_id,status,featured,editors_choice,travel_time_min,recommended_transport,best_time,best_season,expected_duration_min,crowd_level,price_level,mobile_signal,source,source_ref)\n"
      "select v.slug,v.tt,v.td,v.ft,v.fd,v.lat,v.lng,v.alat,v.alng,v.addr,v.biz,v.ws,(case when v.ohv is null then null else jsonb_build_object('raw',v.ohv) end),"
      "'From the nearest metro or stop, it is a short walk — look for the entrance, not a sign.',"
      "'https://maps.apple.com/?ll='||v.lat||','||v.lng,'https://www.google.com/maps/search/?api=1&query='||v.lat||','||v.lng,"
      "c.country,c.city,v.cat::uuid,v.access,v.price,v.product,'published',v.featured,v.editors,12,'walk','evening','all year',60,'medium',2,'good','openstreetmap',v.sref\n"
      "from c, (values\n"+",\n".join(vals)+
      "\n) v(slug,tt,td,ft,fd,lat,lng,alat,alng,addr,biz,ws,ohv,cat,access,price,product,featured,editors,sref)\n"
      "on conflict (slug) do nothing;")
    print(f"{cslug}: {len(rows)} rows", flush=True)

open('/private/tmp/claude-501/-Users-serhiirohachov-Projects-in-progress-Hidden-Ukraine/59a55dca-2ff1-4d0b-85da-ca2d1825c398/scratchpad/world_seed.sql','w').write("\n".join(out))
print("TOTAL", sum(summary.values()), summary, flush=True)
print("DONE", flush=True)
