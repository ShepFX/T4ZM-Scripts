# "Zombies Left" counter overflow fix (KFC, McDonalds)

The custom maps KFC and McDonalds show a "Zombies Left: N" counter that calls
`settext()` with a new string for every count. Every distinct string takes a
configstring for the rest of the map, and at around 800 different counts the
server dies with:

```
G_FindConfigstringIndex: overflow (381): 'Zombies Left: 797'
```

These scripts replace the map's counter functions (`replaceFunc`) with the same
counter, but the words become the label and the number goes through
`setvalue()`, which uses no configstrings.

## Installation

Per-map scripts go in a folder named after the map, so they only load on that
map:

- `storage/t4/raw/scripts/sp/nazi_zombie_kfc2/fix_kfc_counter.gsc`
- `storage/t4/raw/scripts/sp/nazi_zombie_mcdonalds/fix_mcdonalds_counter.gsc`

Another custom map with the same overflow can use a copy, renamed and with the
map's own function names.
