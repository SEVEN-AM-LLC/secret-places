# Nightly place import

`backend/tools/autopilot.py` runs every night on the OVH host and keeps the catalogue growing:
8 cities per run (oldest first) are re-imported from OpenStreetMap — only new places are added — and
the new places get Commons photos, Wikidata awards and non-repeating teasers. Published cities get their
new places live; draft cities stay drafts until their city pass is approved.

Deploy / update:

```bash
rsync -a backend/tools/{autopilot,db,world_import,wikidata_enrich,photos_more,teasers}.py ubuntu@51.195.148.252:/opt/secretplaces-importer/
scp infra/ovh/importer/secretplaces-importer.{service,timer} ubuntu@51.195.148.252:/tmp/
ssh ubuntu@51.195.148.252 'sudo mv /tmp/secretplaces-importer.* /etc/systemd/system/ && sudo systemctl daemon-reload && sudo systemctl enable --now secretplaces-importer.timer'
```

Logs: `journalctl -u secretplaces-importer -n 200`. Run now: `sudo systemctl start secretplaces-importer`.
State (last import per city): `/opt/secretplaces-importer/state.json`.
