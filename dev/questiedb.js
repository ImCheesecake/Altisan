// questiedb.js: writes the QuestieDBForever library from a git clone of QuestieDB.
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');

const questie = process.argv[2];
if (!questie) {
  console.log('Usage: node questiedb.js <QuestieDB folder>');
  process.exit(1);
}
const root = path.join(__dirname, '..');
const commit = execFileSync('git', ['-C', questie, 'rev-parse', 'HEAD'], { encoding: 'utf8' }).trim();

// Only QuestieDB's GPLv3 Forever layers: its Classic base is "all rights reserved" when in doubt.
const forever = path.join(questie, 'src', 'corrections', 'Forever');
const files = {
  zones: path.join(questie, 'src', 'corrections', 'enum', 'zones.lua'),
  npcGen: path.join(forever, 'generated', 'foreverBaseNpc.lua'),
  npcTrace: path.join(forever, 'traces', 'foreverNpcTraces.lua'),
  itemGen: path.join(forever, 'generated', 'foreverBaseItem.lua'),
  itemTrace: path.join(forever, 'traces', 'foreverItemTraces.lua'),
  recipeItems: path.join(root, 'Libs', 'LibProfessionDB', 'Data', 'Forever', '_core', 'RecipeItems.lua'),
  sources: path.join(root, 'Libs', 'LibProfessionDB', 'Data', 'Forever', '_core', 'Sources.lua'),
  lqText: ['NPCText.lua', 'HarvestNPCText.lua'].map(f => path.join(root, 'Libs', 'LibQuestDB', 'Data', 'Forever', 'enUS', f)),
  lqSpawns: ['NPCSpawns.lua', 'HarvestNPCs.lua'].map(f => path.join(root, 'Libs', 'LibQuestDB', 'Data', 'Forever', '_core', f)),
};

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
lua.lua_newtable(L);
for (const [key, file] of Object.entries(files)) {
  lua.lua_pushstring(L, to_luastring(key));
  // LibQuestDB's harvest files end with trade hub rows keyed like NPCs ([1]=): cut them off.
  const text = [].concat(file).map(f => fs.readFileSync(f, 'utf8').split('lib:LoadTradeHub')[0]).join('\n');
  lua.lua_pushstring(L, to_luastring(text));
  lua.lua_settable(L, -3);
}
lua.lua_setglobal(L, to_luastring('SRC'));
lua.lua_pushstring(L, to_luastring(commit));
lua.lua_setglobal(L, to_luastring('COMMIT'));

const src = fs.readFileSync(path.join(__dirname, 'questiedb.lua'), 'utf8');
if (lauxlib.luaL_loadbuffer(L, to_luastring(src), null, to_luastring('@questiedb.lua')) !== lua.LUA_OK ||
    lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
  console.log('ERROR: ' + to_jsstring(lua.lua_tostring(L, -1)));
  process.exit(1);
}
function global(name) {
  lua.lua_getglobal(L, to_luastring(name));
  const value = to_jsstring(lua.lua_tostring(L, -1));
  lua.lua_pop(L, 1);
  return value;
}

const out = path.join(root, 'Libs', 'QuestieDBForever');
fs.mkdirSync(out, { recursive: true });
fs.writeFileSync(path.join(out, 'QuestieDBForever.lua'), global('OUTPUT'));
fs.copyFileSync(path.join(questie, 'gpl-3.0.md'), path.join(out, 'LICENSE.md'));
const size = fs.statSync(path.join(out, 'QuestieDBForever.lua')).size;
console.log(`QuestieDB ${commit}: ${global('SUMMARY')}, ${(size / 1024).toFixed(0)} KB`);
