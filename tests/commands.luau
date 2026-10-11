--!strict
--!native
-- `@openmw-import-morrowind/commands`: the scenarios of dream-ini 1.0.1's own harnesses
-- (`tests/cli.rs` and `src/command/tests.rs`), run as requests and held to the result tables: the
-- outcome, the writer, the text, the file written, and the events and warnings in order. Nothing
-- here reads what a command line would print.
local commands = require '@openmw-import-morrowind/commands'
local fs = require '@dream/fs'
local test = require '@jess/test'

local expect = test.expect
local suite = test.new()
local scratch = assert(rawget(_G, 'scratchRoot') :: string?, 'the suite needs a host-owned scratchRoot')
local root = jess.fs.join(scratch, 'openmw-import-morrowind-commands')

local Stamp = '# OpenMW-Config Serializer Version: 3.0.0\n'
local Audio = '[General]\nDisable Audio=1\n'
local GameFile = '[Game Files]\nGameFile0=Base.esm\n'

--- A path under the case's folder.
local function at(...: string): string return jess.fs.join(root, ...) end

--- A file under the case's folder, its folders made, and its path.
local function file(text: string, ...: string): string
  local path = at(...)
  jess.fs.write(path, text)
  return path
end

--- A folder under the case's folder, as the filesystem names it.
local function folder(...: string): string
  local path = at(...)
  jess.fs.createDir(path)
  return assert(fs.canonicalize(path))
end

--- A TES3 plugin that is only its header, as dream-ini's harness builds one.
local function plugin(): string
  local header = 'HEDR' .. string.pack('<I4', 300) .. string.rep('\0', 300)
  return 'TES3' .. string.pack('<I4', #header) .. string.rep('\0', 8) .. header
end

--- `path`, which is absolute, spelled from the working directory, or nil where the two share no
--- root to climb to.
local function fromWorkingDirectory(path: string): string?
  local separator = string.sub(jess.fs.join('a', 'b'), 2, 2)
  local here = jess.fs.cwd()
  local drive = string.match(here, '^%a:') or ''
  if string.sub(path, 1, #drive) ~= drive then return nil end

  local climb: { string } = {}

  for _ in string.gmatch(string.sub(here, #drive + 1), '[^/\\]+') do
    table.insert(climb, '..')
  end

  return table.concat(climb, separator) .. string.sub(path, #drive + 1)
end

--- The names in a folder under the case's folder, sorted.
local function names(...: string): { string } return assert(fs.list(at(...))) end

local function count(text: string, needle: string): number
  local found, from = 0, 1

  while true do
    local first, last = string.find(text, needle, from, true)
    if not first or not last then return found end

    found += 1
    from = last + 1
  end
end

suite.beforeEach(function()
  fs.remove(root, { recursive = true })
  jess.fs.createDir(root)
end)

suite.describe('a request', function()
  suite.it('raises when it can\'t be read', function()
    local ini = file(Audio, 'Morrowind.ini')
    local import = commands.import :: (unknown) -> commands.Result
    expect(function() import {} end).toThrow 'commands.import: missing required option \'ini\''
    expect(function() import { ini = 1 } end).toThrow 'commands.import.ini: expected string, got number'
    expect(function() import { ini = ini, verbose = 'yes' } end).toThrow 'commands.import.verbose: expected boolean'
    expect(function() import { ini = ini, dataDirs = 'Data Files' } end).toThrow 'commands.import.dataDirs: expected an array of strings'
    expect(function() import { ini = ini, backup = true } end).toThrow 'commands.import: unknown option \'backup\''
    expect(function() import { ini = ini, cfgDir = root } end).toThrow 'unknown option \'cfgDir\''
    expect(function() import { ini = ini, tokens = root } end).toThrow 'commands.import.tokens: expected a table of path roots, got string'
    expect(function() import { ini = ini, tokens = { home = root } } end).toThrow 'commands.import.tokens: unknown path token \'home\''
    expect(function() import { ini = ini, tokens = { userData = true } } end).toThrow 'commands.import.tokens.userData: expected string, got boolean'
  end)

  suite.it('raises for two destinations, and for in place with no cfg', function()
    local ini, cfg = file(Audio, 'Morrowind.ini'), file('encoding=win1252\n', 'openmw.cfg')

    expect(function() commands.import { ini = ini, cfg = cfg, output = cfg, inPlace = true } end).toThrow 'output and inPlace both say where the result goes'
    expect(function() commands.import { ini = ini, inPlace = true } end).toThrow 'inPlace writes the result back to cfg, which wasn\'t given'
    expect(jess.fs.read(cfg)).toBe 'encoding=win1252\n'
  end)
end)

suite.describe('a preview', function()
  suite.it('imports with no cfg and no file, and writes nothing', function()
    local ini = file(Audio, 'Morrowind.ini')
    file('', 'Data Files', 'Morrowind.bsa')
    local result = commands.import { ini = ini }

    expect(result).toEqual {
      outcome = 'previewed',
      ini = ini,
      cfgMissing = false,
      dryRun = false,
      events = { { kind = 'dataDirAddedForArchive', path = folder 'Data Files' } },
      warnings = {},
      changedKeys = { 'data', 'encoding', 'fallback-archive', 'no-sound' },
      imported = {
        data = { folder 'Data Files' },
        encoding = { 'win1252' },
        ['fallback-archive'] = { 'Morrowind.bsa' },
        ['no-sound'] = { '1' },
      },
      writer = 'new',
      text = `data={folder 'Data Files'}\nencoding=win1252\nfallback-archive=Morrowind.bsa\nno-sound=1\n{Stamp}`,
    }
    expect(names()).toEqual { 'Data Files', 'Morrowind.ini' }
  end)

  suite.it('keeps the text clean of everything but the cfg', function()
    local result = commands.import { ini = file(Audio, 'Morrowind.ini'), archives = false }
    expect(result.outcome).toBe 'previewed'
    expect(result.text).toBe(`encoding=win1252\nno-sound=1\n{Stamp}`)
    expect(result.events).toEqual {}
    expect(result.target).toBeNil()
    expect(result.written).toBeNil()
  end)

  suite.it('previews over a cfg without writing it', function()
    local ini, cfg = file(Audio, 'Morrowind.ini'), file('encoding=win1252\n', 'openmw.cfg')
    local result = commands.import { ini = ini, cfg = cfg, archives = false }
    expect(result.outcome).toBe 'previewed'
    expect(result.writer).toBe 'preserved'
    expect(result.cfg).toBe(cfg)
    expect(result.cfgMissing).toBe(false)
    expect(result.text).toBe 'encoding=win1252\nno-sound=1\n'
    expect(result.changedKeys).toEqual { 'no-sound' }
    expect(jess.fs.read(cfg)).toBe 'encoding=win1252\n'
  end)

  suite.it('leaves singletons and fallbacks the INI doesn\'t set where they were', function()
    local ini = file('[General]\n', 'Morrowind.ini')
    local singletons =
      '# keep encoding comment\nencoding=win1252\n# keep no-sound comment\nno-sound=0\n'
    local fallbacks = '# keep fallback comment\nfallback=Old_Setting,old\n'

    expect(
      commands.import({ ini = ini, cfg = file(singletons, 'openmw.cfg'), archives = false }).text
    ).toBe(singletons)
    expect(
      commands.import({ ini = ini, cfg = file(fallbacks, 'openmw.cfg'), archives = false }).text
    ).toBe(`{fallbacks}encoding=win1252\n`)
  end)

  suite.it('writes a relative data folder as it resolved when no cfg anchors it', function()
    local ini = file(GameFile, 'Morrowind.ini')
    file(plugin(), 'relative-data', 'Base.esm')
    local data = folder 'relative-data'
    local relative = fromWorkingDirectory(data)
    if not relative then return end

    local result =
      commands.import { ini = ini, gameFiles = true, archives = false, dataDirs = { relative } }
    expect(result.imported).toEqual {
      content = { 'Base.esm' },
      data = { data },
      encoding = { 'win1252' },
    }
    expect(result.text).toBe(`content=Base.esm\ndata={data}\nencoding=win1252\n{Stamp}`)
  end)

  suite.it('searches a relative data folder from the cfg\'s folder, and writes it as given', function()
    local ini = file(GameFile, 'Morrowind.ini')
    local cfg = file('encoding=win1252\n', 'context', 'openmw.cfg')
    file(plugin(), 'context', 'relative-data', 'Base.esm')
    local result = commands.import {
      ini = ini,
      cfg = cfg,
      gameFiles = true,
      archives = false,
      dataDirs = { 'relative-data' },
    }
    expect(result.text).toBe 'encoding=win1252\ndata=relative-data\ncontent=Base.esm\n'
  end)

  suite.it('reports each file it resolved when verbose, in the order it found them', function()
    local ini = file(
      '[Game Files]\nGameFile0=Plugin.esp\nGameFile1=Base.esm\n[Archives]\nArchive 0=Extra.bsa\n',
      'Morrowind.ini'
    )
    local data = folder 'Data Files'
    file(plugin(), 'Data Files', 'Base.esm')
    file(plugin(), 'Data Files', 'Plugin.esp')
    file('', 'Data Files', 'Morrowind.bsa')
    file('', 'Data Files', 'Extra.bsa')
    local result = commands.import { ini = ini, gameFiles = true, verbose = true }
    local kinds, paths = {}, {}

    for index, event in result.events do
      kinds[index], paths[index] = event.kind, event.path
    end

    expect(kinds).toEqual {
      'contentFileResolved',
      'contentFileResolved',
      'dataDirAddedForContent',
      'archiveResolved',
      'archiveResolved',
    }

    expect(paths).toEqual {
      jess.fs.join(data, 'Plugin.esp'),
      jess.fs.join(data, 'Base.esm'),
      data,
      jess.fs.join(data, 'Morrowind.bsa'),
      jess.fs.join(data, 'Extra.bsa'),
    }
    expect(result.events[1].modified).toBe(jess.fs.stat(at('Data Files', 'Plugin.esp')).modifiedSeconds)
    expect(result.events[3].modified).toBeNil()
    expect(assert(result.imported).content).toEqual { 'Base.esm', 'Plugin.esp' }

    local quiet = commands.import { ini = ini, gameFiles = true }
    expect(quiet.events).toEqual { { kind = 'dataDirAddedForContent', path = data } }
    expect(quiet.text).toBe(result.text)
  end)

  suite.it('carries the INI\'s warnings ahead of the import\'s, in order', function()
    local ini = file(
      '[General]\nDisable Audio=1\n[Broken\nEmpty=\n[Game Files]\nGameFile0=Missing.esp\nGameFile1=Base.esm\n',
      'Morrowind.ini'
    )
    file(plugin(), 'Data Files', 'Base.esm')
    local result = commands.import { ini = ini, gameFiles = true, archives = false }
    expect(result.outcome).toBe 'previewed'
    expect(result.warnings).toEqual {
      {
        kind = 'malformedIniLine',
        line = '[Broken',
        message = 'ini file wrongly formatted ([Broken). Line ignored.',
      },
      {
        kind = 'ignoredEmptyValue',
        key = 'General:Empty',
        message = 'ignored empty value for key \'General:Empty\'.',
      },
      {
        kind = 'missingGameFile',
        file = 'Missing.esp',
        message = 'GameFile entry not found: Missing.esp. Later GameFile entries were not imported.',
      },
    }
    expect(assert(result.imported).content).toEqual {}
  end)
end)

suite.describe('a file with no cfg', function()
  suite.it('starts empty and writes a new openmw.cfg', function()
    local ini = file('[General]\nDisable Audio=1\n[Movies]\nNew Game=intro.bik\n', 'Morrowind.ini')
    local output = at 'out.cfg'
    local result = commands.import { ini = ini, output = output, archives = false }
    local text = `encoding=win1252\nfallback=Movies_New_Game,intro.bik\nno-sound=1\n{Stamp}`
    expect(result.outcome).toBe 'written'
    expect(result.writer).toBe 'new'
    expect(result.target).toBe(output)
    expect(result.written).toBe(fs.canonicalize(output))
    expect(result.text).toBe(text)
    expect(jess.fs.read(output)).toBe(text)
    expect(names()).toEqual { 'Morrowind.ini', 'out.cfg' }
  end)

  suite.it('replaces a file that is already there, keeping no backup of it', function()
    local ini, output = file(Audio, 'Morrowind.ini'), file('stale=1\n', 'out.cfg')
    local result = commands.import { ini = ini, output = output, archives = false }
    expect(result.outcome).toBe 'written'
    expect(jess.fs.read(output)).toBe(`encoding=win1252\nno-sound=1\n{Stamp}`)
    expect(names()).toEqual { 'Morrowind.ini', 'out.cfg' }
  end)

  suite.it('finds content in Data Files beside the INI, and writes the folder', function()
    local ini, output = file(GameFile, 'Morrowind.ini'), at 'openmw.cfg'
    file(plugin(), 'Data Files', 'Base.esm')
    local result = commands.import { ini = ini, output = output, gameFiles = true, archives = false }
    expect(result.outcome).toBe 'written'
    expect(jess.fs.read(output)).toBe(
      `content=Base.esm\ndata={folder 'Data Files'}\nencoding=win1252\n{Stamp}`
    )
  end)

  suite.it('warns of a content file it can\'t find, and writes the rest', function()
    local ini, output = file('[Game Files]\nGameFile0=Missing.esp\n', 'Morrowind.ini'), at 'openmw.cfg'
    local result = commands.import { ini = ini, output = output, gameFiles = true, archives = false }
    expect(result.outcome).toBe 'written'
    expect(result.warnings).toEqual {
      {
        kind = 'missingGameFile',
        file = 'Missing.esp',
        message = 'GameFile entry not found: Missing.esp. Later GameFile entries were not imported.',
      },
    }
    expect(jess.fs.read(output)).toBe(`encoding=win1252\n{Stamp}`)
  end)

  suite.it('searches an explicit data folder first, and writes it', function()
    local ini, output = file(GameFile, 'ini-source', 'Morrowind.ini'), at 'openmw.cfg'
    local data = at('install', 'Data Files')
    file(plugin(), 'install', 'Data Files', 'Base.esm')
    local result = commands.import {
      ini = ini,
      output = output,
      gameFiles = true,
      archives = false,
      dataDirs = { data },
    }
    expect(result.events).toEqual { { kind = 'dataDirAddedForContent', path = fs.canonicalize(data) } }
    expect(jess.fs.read(output)).toBe(`content=Base.esm\ndata={data}\nencoding=win1252\n{Stamp}`)
  end)

  suite.it('searches a relative data folder from the file\'s folder, and writes it as given', function()
    local ini, output = file(GameFile, 'Morrowind.ini'), at('cfg-context', 'openmw.cfg')
    file(plugin(), 'cfg-context', 'relative-data', 'Base.esm')
    local result = commands.import {
      ini = ini,
      output = output,
      gameFiles = true,
      archives = false,
      dataDirs = { 'relative-data' },
    }
    expect(result.outcome).toBe 'written'
    expect(jess.fs.read(output)).toBe(
      `content=Base.esm\ndata=relative-data\nencoding=win1252\n{Stamp}`
    )
  end)
end)

suite.describe('a file beside the cfg', function()
  suite.it('writes the cfg\'s lines with the imported keys, and leaves the cfg alone', function()
    local ini = file('[General]\nDisable Audio=1\n[Movies]\nNew Game=intro.bik\n', 'Morrowind.ini')
    local cfg, output = file('encoding=win1252\n', 'openmw.cfg'), at 'out.cfg'
    file('', 'Data Files', 'Morrowind.bsa')
    local result = commands.import { ini = ini, cfg = cfg, output = output }
    expect(result.outcome).toBe 'written'
    expect(result.writer).toBe 'preserved'
    expect(jess.fs.read(output)).toBe(
      `encoding=win1252\nno-sound=1\nfallback=Movies_New_Game,intro.bik\ndata={folder 'Data Files'}\nfallback-archive=Morrowind.bsa\n`
    )
    expect(jess.fs.read(output)).toBe(result.text)
    expect(jess.fs.read(cfg)).toBe 'encoding=win1252\n'
  end)

  suite.it('doesn\'t create a cfg that was named and isn\'t there', function()
    local ini, cfg, output = file(Audio, 'Morrowind.ini'), at 'missing.cfg', at 'out.cfg'
    local result = commands.import { ini = ini, cfg = cfg, output = output, archives = false }
    expect(result.outcome).toBe 'written'
    expect(result.cfgMissing).toBe(true)
    expect(jess.fs.exists(cfg)).toBe(false)
    expect(jess.fs.read(output)).toBe 'encoding=win1252\nno-sound=1\n'
  end)

  suite.it('keeps comments and the spelling of the paths the cfg has', function()
    local ini, output = file(Audio, 'Morrowind.ini'), at 'out.cfg'
    local authored =
      '# keep this data comment\ndata=mods\n\n# keep this resources comment\nresources=resources\nuser-data=?userdata?\n'
    local cfg = file(authored, 'openmw.cfg')
    folder 'mods'
    local result = commands.import {
      ini = ini,
      cfg = cfg,
      output = output,
      archives = false,
      tokens = { userData = at 'user-data' },
    }
    expect(result.writer).toBe 'preserved'
    expect(jess.fs.read(output)).toBe(`{authored}encoding=win1252\nno-sound=1\n`)
  end)

  suite.it('fails on a path token whose root the request doesn\'t name, saying which', function()
    local ini, output = file(Audio, 'Morrowind.ini'), at 'out.cfg'
    local cfg = file('user-data=?userdata?\n', 'openmw.cfg')
    local result = commands.import { ini = ini, cfg = cfg, output = output, archives = false }
    expect(result.outcome).toBe 'failed'
    expect(result.failure).toEqual {
      stage = 'import',
      message = `openmw-config: {cfg}: token '?userdata?' needs an explicit 'userData' root`,
    }
    expect(jess.fs.exists(output)).toBe(false)
  end)

  suite.it('writes a cfg flattened elsewhere with its tokens as the roots they stand for', function()
    local ini, output = file(Audio, 'Morrowind.ini'), at('output', 'openmw.cfg')
    local cfg = file('data="?userdata?/mods"\nresources=?local?/resources\n', 'source', 'openmw.cfg')
    folder 'output'
    local result = commands.import {
      ini = ini,
      cfg = cfg,
      output = output,
      archives = false,
      tokens = { userData = at 'user', localPath = at 'install' },
    }
    expect(result.writer).toBe 'resolved'
    expect(jess.fs.read(output)).toBe(
      `data={at('user', 'mods')}\nencoding=win1252\nno-sound=1\nresources={at('install', 'resources')}\n`
    )
  end)

  suite.it('adds an explicit data folder as given, beside the cfg\'s own', function()
    local ini, output = file(GameFile, 'work', 'Morrowind.ini'), at('work', 'out.cfg')
    local cfg = file('# existing data stays relative\ndata=mods\n', 'work', 'openmw.cfg')
    file(plugin(), 'work', 'extra-data', 'Base.esm')
    local result = commands.import {
      ini = ini,
      cfg = cfg,
      output = output,
      gameFiles = true,
      archives = false,
      dataDirs = { 'extra-data' },
    }
    expect(result.writer).toBe 'preserved'
    expect(jess.fs.read(output)).toBe '# existing data stays relative\ndata=mods\nencoding=win1252\ndata=extra-data\ncontent=Base.esm\n'
  end)

  suite.it('keeps a config= chain as a chain, not as the settings it brings', function()
    local ini, output = file(Audio, 'Morrowind.ini'), at 'out.cfg'
    file('data=base-data\nno-sound=0\n', 'base', 'openmw.cfg')
    folder 'resources'
    local cfg = file(
      '# keep the chain, not the composed base settings\nconfig=base\nresources=resources\n',
      'openmw.cfg'
    )
    local result = commands.import { ini = ini, cfg = cfg, output = output, archives = false }
    local written = jess.fs.read(output) or ''
    expect(result.writer).toBe 'preserved'
    expect(written).toContain 'config=base\n'
    expect(written).toContain 'resources=resources\n'
    expect(written).toContain 'no-sound=1\n'
    expect(count(written, 'data=base-data\n')).toBe(0)
    expect(count(written, 'no-sound=0\n')).toBe(0)
  end)

  suite.it('replaces each folder setting the request names, wherever the cfg wrote it', function()
    local ini, output = file(Audio, 'Morrowind.ini'), at 'imported.cfg'
    file('installed', 'resources', 'version')
    local cfg = file(
      'data-local=old-local\ndata-local=other-local\nresources=old-resources\nuser-data=old-user-data\n',
      'openmw.cfg'
    )
    local result = commands.import {
      ini = ini,
      cfg = cfg,
      output = output,
      archives = false,
      dataLocal = 'new-local',
      resources = 'resources',
      userData = 'new-user-data',
    }
    local written = jess.fs.read(output) or ''
    expect(result.outcome).toBe 'written'
    expect(count(written, 'data-local=')).toBe(1)
    expect(count(written, 'resources=')).toBe(1)
    expect(count(written, 'user-data=')).toBe(1)
    expect(written).toContain 'data-local=new-local\n'
    expect(written).toContain 'resources=resources\n'
    expect(written).toContain 'user-data=new-user-data\n'
    expect(result.changedKeys).toEqual {
      'data-local',
      'encoding',
      'no-sound',
      'resources',
      'user-data',
    }
  end)

  suite.it('counts a cfg reached through a linked folder as the same folder', function()
    local ini = file(Audio, 'Morrowind.ini')
    local real = file('# preserved through symlink spelling\ndata=mods\n', 'real', 'openmw.cfg')
    local link, output = at('link', 'openmw.cfg'), at('link', 'out.cfg')
    folder 'link'
    assert(fs.symlink(real, link))
    local result = commands.import { ini = ini, cfg = link, output = output, archives = false }
    expect(result.writer).toBe 'preserved'
    expect(jess.fs.read(output)).toBe '# preserved through symlink spelling\ndata=mods\nencoding=win1252\nno-sound=1\n'
  end)
end)

suite.describe('a file in another folder', function()
  suite.it('writes the cfg flattened, its folders as the paths they resolve to', function()
    local ini, output = file(Audio, 'Morrowind.ini'), at('output', 'openmw.cfg')
    local cfg = file('# preserved only in source context\ndata=mods\n', 'source', 'openmw.cfg')
    local mods = folder('source', 'mods')
    folder 'output'
    local result = commands.import { ini = ini, cfg = cfg, output = output, archives = false }
    expect(result.outcome).toBe 'written'
    expect(result.writer).toBe 'resolved'
    expect(jess.fs.read(output)).toBe(`data={mods}\nencoding=win1252\nno-sound=1\n`)
    expect(jess.fs.read(cfg)).toBe '# preserved only in source context\ndata=mods\n'
  end)

  suite.it('doesn\'t write the engine\'s resources/vfs as a data folder', function()
    local ini, output = file(Audio, 'Morrowind.ini'), at('output', 'openmw.cfg')
    local cfg = file('resources=resources\n', 'source', 'openmw.cfg')
    local resources = folder('source', 'resources')
    folder('source', 'resources', 'vfs')
    folder 'output'
    local result = commands.import { ini = ini, cfg = cfg, output = output, archives = false }
    expect(result.writer).toBe 'resolved'
    expect(jess.fs.read(output)).toBe(`encoding=win1252\nno-sound=1\nresources={resources}\n`)
  end)

  suite.it('writes an explicit data folder as it resolved, searched from the file\'s folder', function()
    local ini, output = file(GameFile, 'Morrowind.ini'), at('output', 'openmw.cfg')
    local cfg = file('encoding=win1252\n', 'source', 'openmw.cfg')
    file(plugin(), 'output', 'relative-data', 'Base.esm')
    local data = folder('output', 'relative-data')
    local result = commands.import {
      ini = ini,
      cfg = cfg,
      output = output,
      gameFiles = true,
      archives = false,
      dataDirs = { 'relative-data' },
    }
    expect(result.writer).toBe 'resolved'
    expect(jess.fs.read(output)).toBe(`content=Base.esm\ndata={data}\nencoding=win1252\n`)
  end)
end)

suite.describe('in place', function()
  suite.it('writes the result back to the cfg', function()
    local ini, cfg = file(Audio, 'Morrowind.ini'), file('encoding=win1252\n', 'openmw.cfg')
    local result = commands.import { ini = ini, cfg = cfg, inPlace = true, archives = false }
    expect(result.outcome).toBe 'written'
    expect(result.writer).toBe 'preserved'
    expect(result.target).toBe(cfg)
    expect(result.written).toBe(fs.canonicalize(cfg))
    expect(result.warnings).toEqual {}
    expect(jess.fs.read(cfg)).toBe 'encoding=win1252\nno-sound=1\n'
    expect(names()).toEqual { 'Morrowind.ini', 'openmw.cfg' }
  end)

  suite.it('keeps comments and the spelling of the paths the cfg has', function()
    local ini, cfg = file(Audio, 'Morrowind.ini'), file('# data stays authored\ndata=mods\n', 'openmw.cfg')
    folder 'mods'
    commands.import { ini = ini, cfg = cfg, inPlace = true, archives = false }
    expect(jess.fs.read(cfg)).toBe '# data stays authored\ndata=mods\nencoding=win1252\nno-sound=1\n'
  end)

  suite.it('writes the file a linked cfg points at, and leaves the link a link', function()
    local ini = file(Audio, 'Morrowind.ini')
    local real = file('# update the target, not the link\nencoding=win1252\n', 'real', 'openmw.cfg')
    local link = at('link', 'openmw.cfg')
    folder 'link'
    assert(fs.symlink(real, link))
    local result = commands.import { ini = ini, cfg = link, inPlace = true, archives = false }
    expect(result.target).toBe(link)
    expect(result.written).toBe(fs.canonicalize(real))
    expect(assert(fs.lstat(link)).isSymlink).toBe(true)
    expect(jess.fs.read(real)).toBe '# update the target, not the link\nencoding=win1252\nno-sound=1\n'
  end)

  suite.it('doesn\'t write the engine\'s resources/vfs as a data folder, however often it runs', function()
    local ini = file(Audio, 'Morrowind.ini')
    local cfg = file('# The engine\'s resources\nresources=resources\n', 'openmw.cfg')
    folder('resources', 'vfs')
    local request: commands.Request = { ini = ini, cfg = cfg, archives = false }
    expect(count(commands.import(request).text or '', 'vfs')).toBe(0)

    request.inPlace = true
    expect(commands.import(request).outcome).toBe 'written'
    local first = jess.fs.read(cfg)
    expect(first).toBe '# The engine\'s resources\nresources=resources\nencoding=win1252\nno-sound=1\n'
    expect(commands.import(request).outcome).toBe 'written'
    expect(jess.fs.read(cfg)).toBe(first)
  end)

  suite.it('creates a cfg that was named and isn\'t there', function()
    local ini, cfg = file(Audio, 'Morrowind.ini'), at 'openmw.cfg'
    local result = commands.import { ini = ini, cfg = cfg, inPlace = true, archives = false }
    expect(result.outcome).toBe 'written'
    expect(result.cfgMissing).toBe(true)
    expect(jess.fs.read(cfg)).toBe 'encoding=win1252\nno-sound=1\n'
  end)
end)

suite.describe('a dry run', function()
  suite.it('returns the text each writer would write, and writes nothing', function()
    local ini = file(Audio, 'Morrowind.ini')
    local cfg = file('# kept\ndata=mods\n', 'source', 'openmw.cfg')
    local mods = folder('source', 'mods')
    folder 'output'
    local fresh = commands.import { ini = ini, output = at 'new.cfg', archives = false, dryRun = true }
    local inPlace =
      commands.import { ini = ini, cfg = cfg, inPlace = true, archives = false, dryRun = true }
    local elsewhere = commands.import {
      ini = ini,
      cfg = cfg,
      output = at('output', 'openmw.cfg'),
      archives = false,
      dryRun = true,
    }

    for _, result in { fresh, inPlace, elsewhere } do
      expect(result.outcome).toBe 'previewed'
      expect(result.dryRun).toBe(true)
      expect(result.written).toBeNil()
    end

    expect(fresh.target).toBe(at 'new.cfg')
    expect(fresh.writer).toBe 'new'
    expect(fresh.text).toBe(`encoding=win1252\nno-sound=1\n{Stamp}`)
    expect(inPlace.target).toBe(cfg)
    expect(inPlace.writer).toBe 'preserved'
    expect(inPlace.text).toBe '# kept\ndata=mods\nencoding=win1252\nno-sound=1\n'
    expect(elsewhere.writer).toBe 'resolved'
    expect(elsewhere.text).toBe(`data={mods}\nencoding=win1252\nno-sound=1\n`)
    expect(jess.fs.exists(at 'new.cfg')).toBe(false)
    expect(names 'output').toEqual {}
    expect(jess.fs.read(cfg)).toBe '# kept\ndata=mods\n'
  end)

  suite.it('writes, the next time, exactly the text it returned', function()
    local ini, cfg = file(Audio, 'Morrowind.ini'), file('# kept\nno-sound=0\n', 'openmw.cfg')
    local request: commands.Request = { ini = ini, cfg = cfg, inPlace = true, archives = false, dryRun = true }
    local preview = commands.import(request)
    request.dryRun = false
    local written = commands.import(request)
    expect(written.outcome).toBe 'written'
    expect(written.text).toBe(preview.text)
    expect(jess.fs.read(cfg)).toBe(preview.text)
  end)
end)

suite.describe('a run that can\'t finish', function()
  suite.it('says the INI isn\'t there before anything else, and touches nothing', function()
    local cfg = at 'openmw.cfg'
    local result = commands.import {
      ini = at 'missing.ini',
      cfg = cfg,
      inPlace = true,
      encoding = 'bogus',
    }

    expect(result).toEqual {
      outcome = 'missingIni',
      ini = at 'missing.ini',
      cfg = cfg,
      cfgMissing = false,
      target = cfg,
      dryRun = false,
      events = {},
      warnings = {},
      changedKeys = {},
    }
    expect(names()).toEqual {}
  end)

  suite.it('fails on an encoding it doesn\'t have, before it reads either file', function()
    local ini, cfg = file(Audio, 'Morrowind.ini'), file('', 'openmw.cfg')
    local result = commands.import { ini = ini, cfg = cfg, inPlace = true, encoding = 'bogus' }
    expect(result.outcome).toBe 'failed'
    expect(result.failure).toEqual { stage = 'options', message = 'unsupported encoding: bogus' }
    expect(result.imported).toBeNil()
    expect(result.text).toBeNil()
    expect(jess.fs.read(cfg)).toBe ''
  end)

  suite.it('fails when an archive can\'t be found, naming where it looked', function()
    local ini = file('[Archives]\nArchive 0=Tribunal.bsa\n', 'Morrowind.ini')
    local cfg = file('data=mods\n', 'openmw.cfg')
    file('', 'Data Files', 'Morrowind.bsa')
    local result = commands.import { ini = ini, cfg = cfg, inPlace = true }
    expect(result.outcome).toBe 'failed'
    expect(result.failure).toEqual {
      stage = 'import',
      message = `fallback archives not found: Tribunal.bsa; searched: {at 'mods'}, {folder 'Data Files'}; pass --data or add data=... to the cfg`,
    }
    expect(result.events).toEqual {}
    expect(result.written).toBeNil()
    expect(jess.fs.read(cfg)).toBe 'data=mods\n'
  end)

  suite.it('fails on a content entry that is a path, and on an INI it can\'t read', function()
    local ini = file('[Game Files]\nGameFile0=sub/Base.esm\n', 'Morrowind.ini')
    local entry = commands.import { ini = ini, gameFiles = true, archives = false }
    expect(entry.failure).toEqual {
      stage = 'import',
      message = 'invalid content file name: sub/Base.esm; content entries must be plugin filenames, not paths',
    }

    local unreadable = commands.import { ini = folder 'Folder.ini', archives = false }
    expect(unreadable.outcome).toBe 'failed'
    expect(assert(unreadable.failure).stage).toBe 'import'
    expect(assert(unreadable.failure).message).toContain(`{at 'Folder.ini'}: `)
  end)

  suite.it('fails at the write when the file\'s folder isn\'t there, with the text it had', function()
    local ini, output = file(Audio, 'Morrowind.ini'), at('nowhere', 'out.cfg')
    local result = commands.import { ini = ini, output = output, archives = false }
    expect(result.outcome).toBe 'failed'
    expect(assert(result.failure).stage).toBe 'output'
    expect(assert(result.failure).message).toContain(`{output}: `)
    expect(result.text).toBe(`encoding=win1252\nno-sound=1\n{Stamp}`)
    expect(result.written).toBeNil()
    expect(jess.fs.exists(at 'nowhere')).toBe(false)
  end)
end)

return suite
