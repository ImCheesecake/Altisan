# Libraries

Altisan embeds these libraries unchanged. Each belongs to its authors.

| Library | Version | License | Source |
|---|---|---|---|
| LibStub | 1.0 | Public domain | https://www.wowace.com/projects/libstub |
| CallbackHandler-1.0 | minor 8 | Ace3 BSD-style (part of Ace3) | https://www.wowace.com/projects/callbackhandler |
| LibDataBroker-1.1 | minor 4 | None stated by the author | https://github.com/tekkub/libdatabroker-1-1 |
| LibDBIcon-1.0 | minor 57 | Ace3 BSD-style | https://www.curseforge.com/wow/addons/libdbicon-1-0 |
| LibProfessionDB | 1.10.1 (minor 14) | MIT | https://www.curseforge.com/wow/addons/libprofessiondb |
| LibQuestDB | 0.2.0 (minor 26), NPCs and quest givers | MIT | https://www.curseforge.com/wow/addons/questdb (project 1700352, file 9768606) |
| LibItemDB | 1.12.0 (minor 49), where items are sold and their price, Forever's data | MIT | https://www.curseforge.com/wow/addons/libitemdb (project 1558208, file 9780481) |
| ForeverTracker | shortest-path-forever commit 7231cca (2026-11-09), `UI/TrackerQuestie.lua`, `TrackerEqot.lua`, `TrackerLock.lua`, `TrackerOrder.lua`, `TrackerHost.lua` | GPL-3.0-or-later (`LICENSE`) | https://github.com/cjber/shortest-path-forever |
| QuestieDBForever | QuestieDB commit ab2e0fd (after 1.1.5, 2026-11-24), Forever recipe sources, item vendors and their NPCs | GPLv3 (`LICENSE.md`) | https://github.com/Questie/QuestieDB |

All three Lib*DB are by Pimptasty (the name in their licences), https://www.curseforge.com/members/pmptasty on CurseForge.

LibDataBroker-1.1's repository has no license file. It is embedded the way nearly every
addon with a minimap button embeds it.

LibProfessionDB is copied with only its Forever data: an offline recipe database built from the
game's own client files. On Forever, its sources and some skill levels are copied from Vanilla
until Forever data exists; the tooltip marks those as unconfirmed. NPC names are English. It also
lists recipes that were never in the game, which are hidden. To update: replace
`LibProfessionDB/LibProfessionDB-1.0.lua` and `LibProfessionDB/Data/Forever/` with the new
release's, and regenerate the file list in `LibProfessionDB/LibProfessionDB.xml` from the release's
`ProfessionDB_Camelot.toc`. Only Forever data changes matter. If a player has a newer copy from
another addon, LibStub uses that one.

LibQuestDB is cut down to its NPC files (names, titles, factions, spawn points, zones) and
who gives each quest (`Quests.lua`): no quest text, rewards, objects, routes, walk map or `QuestieSource.lua`. Its data is re-expressed from the CMaNGOS world
database (GPL-3.0); the library itself is MIT. Since 0.2.0 it also has 30 of Forever's own NPCs
from its author's in-game capture (`HarvestNPCs.lua`, `HarvestNPCText.lua`; captured on Alliance
only, so their faction is what an Alliance character saw), and files capital-city NPCs under the
city instead of the zone around it. `LibQuestDB.xml` lists the files and how to update.

LibItemDB is cut down to its library file and Forever data files: `ItemPlaces.lua` (which
creatures drop an item and which vendors sell it, at most 8 vendors per item, with their faction
and map points), `ItemPlacesLearned.lua` (places its author's players saw in game, for items
ItemPlaces lacks; no spawn count, vendors without a faction), `VendorPrices.lua` (a vendor's base
price) and `PlaceNames.lua` per language (the vendors' names where they differ from English, for
deDE, esES, esMX, frFR, koKR, ruRU, zhCN and zhTW; each loads only on its own client; no ptBR one).
Forever's ItemPlaces (since 1.9.0, swapped in for 0.13.0) is Vanilla's filtered to Forever's items
plus the gear vendors Forever's client lists (`docs/research/libitemdb-2026-11-12.md`), built from
the same CMaNGOS database as LibQuestDB's Forever NPCs; since 1.11.0 it adds Forever's own items
from AllTheThings (`docs/research/libitemdb-2026-11-21.md`; AllTheThings is MIT).
`LibItemDB.xml` lists the files and how to update.

ForeverTracker is the shared quest tracker column several Forever addons ship as the same files
(cjber's Shortest Path and Field Guide, SkillUp Forever): the first addon loaded builds the column
(`ForeverTrackerHost`, frame `ForeverTrackerCompanion`) and every other one, Altisan included, puts
its section in it. It sits under Blizzard's quests, steps around Questie's and EQ Objective
Tracker's lists, and floats on its own when FlareUI hides Blizzard's tracker. The files are copied
unchanged; the `.toc` loads them after `Core.lua`, which sets the `ns.L` and
`ns.TrackerHostSettings` they read (settings saved in `AltisanDB.tracker`). On 2026-11-10 the
files left that repository for ForeverCore, a standalone addon the other Forever addons now
require (https://github.com/cjber/forever-core), which uses the same global and frame and adopts a
column an older copy built. `Altisan.toc` lists ForeverCore under `OptionalDeps`, so when it's
installed it loads first, draws the column, and Altisan's copy puts its section in that one
(`docs/research/forevercore-tracker-2026-11-16.md`). There's no newer copy to take: ForeverCore's
docs say consumers don't copy its files.

QuestieDBForever isn't a library but data, written by Altisan's `dev/questiedb.js` from
QuestieDB's GPLv3 Forever layers only (the generated delta-base and the player traces, every
commit by BreakBB or Logonz, on its `LICENSE.md` GPLv3 list), never its Classic base. It holds the
vendors, drops and quests for each recipe LibProfessionDB's `Sources.lua` has no source for (its
`VendorSources.lua`, the Alliance Merchant's Favor quartermasters and two Alliance gold vendors, isn't read, so the Horde ones
stay), the vendors of every
item it has them for (Forever's own items, which LibItemDB's lists lack), and the NPCs
those name that LibQuestDB lacks. QuestieDB's rows come from Wowhead's Forever data. To update:
`git clone https://github.com/Questie/QuestieDB`, then `cd dev && node questiedb.js <that folder>`
(it writes the file and copies the licence), and change the commit above.
