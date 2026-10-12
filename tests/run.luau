--!strict
--!native
-- The package's own cases: the edge semantics dream-ini pins, checked on the port alone.
local fs = require '@dream/fs'
local ini = require '@openmw-import-morrowind'
local text = require '@dream-ini'
local test = require '@jess/test'
local expect = test.expect
local suite = test.new()
local scratch = assert(rawget(_G, 'scratchRoot') :: string?, 'the suite needs a host-owned scratchRoot')

suite.describe('importMaps', function()
  suite.it('takes the last audio value, replaces fallback, and gates fonts', function()
    local parsed = text.parseIni(
      '[General]\nDisable Audio=1\nDisable Audio=0\n[Fonts]\nFont 0=magic\n[Movies]\nNew Game=intro.bik\n'
    ).entries
    local cfg = { fallback = { 'old' }, ['no-sound'] = { '1' } }
    local result = ini.importMaps(cfg, parsed, { archives = false })
    expect(result.cfg.fallback).toEqual { 'Movies_New_Game,intro.bik' }
    expect(result.cfg['no-sound']).toEqual { '0' }
    expect(cfg).toEqual { fallback = { 'old' }, ['no-sound'] = { '1' } }
    expect(ini.importMaps({}, parsed, { archives = false, fonts = true }).cfg.fallback).toEqual {
      'Fonts_Font_0,magic',
      'Movies_New_Game,intro.bik',
    }
  end)

  suite.it('leaves fallback alone when the INI has none', function()
    local parsed = text.parseIni '[Movies]\nNew Game=\n'
    expect(
      ini.importMaps({ fallback = { 'old' } }, parsed.entries, { archives = false }).cfg.fallback
    ).toEqual {
      'old',
    }
    expect(#parsed.warnings).toBe(1)
  end)

  suite.it('resolves the encoding and writes the singleton overrides', function()
    local result = ini.importMaps({ encoding = { 'win1250' } }, {}, {
      archives = false,
      encoding = 'WINDOWS-1251',
      dataLocal = 'local',
      resources = 'resources',
      userData = 'user',
    })

    expect(result.cfg).toEqual {
      encoding = { 'win1251' },
      ['data-local'] = { 'local' },
      resources = { 'resources' },
      ['user-data'] = { 'user' },
    }
    expect(result.changedKeys).toEqual { 'data-local', 'encoding', 'resources', 'user-data' }
    expect(result.text).toBe 'data-local=local\nencoding=win1251\nresources=resources\nuser-data=user\n'
  end)

  suite.it('keeps the cfg encoding when nothing overrides it', function()
    local result = ini.importMaps({ encoding = { 'win1250' } }, {}, { archives = false })
    expect(result.cfg.encoding).toEqual { 'win1250' }
    expect(result.changedKeys).toEqual {}
  end)

  suite.it('rejects bad options and malformed multimaps', function()
    expect(function() ini.importMaps({}, {}, { encoding = 'utf-8' }) end).toThrow 'unsupported encoding'
    expect(function() ini.importMaps({}, {}, { game = 'Oblivion' }) end).toThrow 'unsupported game'
    expect(function() ini.importMaps({}, {}, { verbose = 'yes' } :: any) end).toThrow 'expected boolean'
    expect(function() ini.importMaps({ data = 'not a list' } :: any, {}, {}) end).toThrow 'ini.importMaps: expected array of strings for key \'data\', got string'
    expect(function() ini.importMaps({}, {}, { writeResolvedDataDirs = true } :: any) end).toThrow 'unknown option \'writeResolvedDataDirs\''
  end)
end)

suite.describe('importPaths', function()
  local root = jess.fs.join(scratch, 'openmw-import-morrowind-paths')
  local iniPath = jess.fs.join(root, 'Morrowind.ini')
  local context = jess.fs.join(root, 'context')
  local dataFiles = jess.fs.join(context, 'relative-data')

  suite.beforeEach(function()
    fs.remove(root, { recursive = true })
    jess.fs.write(iniPath, '[Game Files]\nGameFile0=Base.esm\n')
    jess.fs.write(jess.fs.join(dataFiles, 'Base.esm'), 'TES3')
  end)

  local function import(extra: { [string]: unknown }): ini.Result
    local given: { [string]: unknown } =
      { ini = iniPath, gameFiles = true, archives = false, dataDirs = { 'relative-data' } }

    for key, value in extra do
      given[key] = value
    end

    return ini.importPaths((given :: unknown) :: ini.PathsOptions)
  end

  suite.it('searches a relative data folder from dataDirBase, and writes it as given', function()
    local result = import { dataDirBase = context }
    expect(result.cfg.content).toEqual { 'Base.esm' }
    expect(result.cfg.data).toEqual { 'relative-data' }
    expect(result.events).toEqual {
      { kind = 'dataDirAddedForContent', path = fs.canonicalize(dataFiles) },
    }
  end)

  suite.it('takes dataDirBase over the cfg\'s folder', function()
    local cfgPath = jess.fs.join(root, 'elsewhere', 'openmw.cfg')
    jess.fs.write(cfgPath, 'encoding=win1252\n')
    expect(import({ cfg = cfgPath }).warnings[1].kind).toBe 'missingGameFile'
    expect(import({ cfg = cfgPath, dataDirBase = context }).cfg.content).toEqual { 'Base.esm' }
  end)

  suite.it('writes a data folder as it resolved with writeResolvedDataDirs', function()
    local result = import { dataDirBase = context, writeResolvedDataDirs = true }
    expect(result.cfg.content).toEqual { 'Base.esm' }
    expect(result.cfg.data).toEqual { fs.canonicalize(dataFiles) }
    expect(import({ dataDirBase = context, writeResolvedDataDirs = false }).cfg.data).toEqual {
      'relative-data',
    }
  end)

  suite.it('reads a cfg\'s path tokens from the roots it is given, and refuses one without', function()
    local cfgPath = jess.fs.join(root, 'openmw.cfg')
    jess.fs.write(cfgPath, 'data="?userdata?/relative-data"\n')
    local result = import { cfg = cfgPath, dataDirs = {}, tokens = { userData = context } }
    expect(result.cfg.content).toEqual { 'Base.esm' }
    expect(result.cfg.data).toEqual { dataFiles }
    expect(result.events).toEqual {}

    expect(function() import { cfg = cfgPath, dataDirs = {} } end).toThrow 'token \'?userdata?\' needs an explicit \'userData\' root'
    expect(function() import { cfg = cfgPath, tokens = { userConfig = context } } end).toThrow 'token \'?userdata?\' needs an explicit \'userData\' root'
    expect(function() import { tokens = { home = context } } end).toThrow 'ini.importPaths.tokens: unknown path token \'home\'; known tokens are globalPath, localPath, userConfig, userData'
    expect(function() import { tokens = { userData = 1 } } end).toThrow 'ini.importPaths.tokens.userData: expected string, got number'
    expect(function() import { tokens = context } end).toThrow 'ini.importPaths.tokens: expected a table of path roots, got string'
  end)
end)

suite.describe('the INI\'s numbered entries', function()
  local root = jess.fs.join(scratch, 'openmw-import-morrowind-entries')
  local iniPath = jess.fs.join(root, 'Morrowind.ini')

  suite.beforeEach(function()
    fs.remove(root, { recursive = true })
    jess.fs.createDir(jess.fs.join(root, 'Data Files'))
  end)

  --- The archives an import of `entries` looks for, in the order it looks: none is there, so the
  --- import names every one.
  local function sought(entries: ini.MultiMap): string
    -- `importMaps` raises for the archives it can't find, which is how the list is read here.
    local found, problem = pcall(ini.importMaps, {}, entries, { iniPath = iniPath })
    expect(found).toBe(false)
    return string.match(tostring(problem), 'not found: (.-); searched: ') or tostring(problem)
  end

  suite.it('reads them by index, not in the order of their keys, up to the first index missing', function()
    local entries: ini.MultiMap = { ['Archives:Archive 13'] = { 'After.bsa' } }
    local expected = { 'Morrowind.bsa' }

    for index = 0, 11 do
      entries[`Archives:Archive {index}`] = { `Archive{index}.bsa` }
      table.insert(expected, `Archive{index}.bsa`)
    end

    expect(sought(entries)).toBe(table.concat(expected, ', '))
  end)

  suite.it('takes a key in any case, and the spellings of one index in the order of their bytes', function()
    expect(sought {
      ['archives:archive 0'] = { 'lower.bsa' },
      ['ARCHIVES:ARCHIVE 0'] = { 'UPPER.bsa' },
      ['Archives:Archive 0'] = { 'Mixed.bsa', 'Second.bsa' },
      ['aRCHIVES:aRCHIVE 1'] = { 'Next.bsa' },
      ['Brchives:Archive 2'] = { 'Other.bsa' },
    }).toBe 'Morrowind.bsa, UPPER.bsa, Mixed.bsa, Second.bsa, lower.bsa, Next.bsa'
  end)

  suite.it('takes only a plain decimal for an index', function()
    expect(sought {
      ['Archives:Archive 0'] = { 'Zero.bsa' },
      ['Archives:Archive 00'] = { 'Doubled.bsa' },
      ['Archives:Archive 01'] = { 'Padded.bsa' },
      ['Archives:Archive +1'] = { 'Signed.bsa' },
      ['Archives:Archive 1 '] = { 'Trailing.bsa' },
      ['Archives:Archive  1'] = { 'Leading.bsa' },
      ['Archives:Archive 1.0'] = { 'Fraction.bsa' },
      ['Archives:Archive 0x1'] = { 'Hex.bsa' },
      ['Archives:Archive 1e0'] = { 'Exponent.bsa' },
      ['Archives:Archive '] = { 'Unnumbered.bsa' },
    }).toBe 'Morrowind.bsa, Zero.bsa'
  end)

  suite.it('passes over an entry that isn\'t an archive, and stops at an index with no values', function()
    expect(sought {
      ['Archives:Archive 0'] = { 'First.bsa' },
      ['Archives:Archive 1'] = { 'Notes.txt' },
      ['Archives:Archive 2'] = { ' Spaced.BSA\t' },
      ['Archives:Archive 3'] = {},
      ['Archives:Archive 4'] = { 'Never.bsa' },
    }).toBe 'Morrowind.bsa, First.bsa, Spaced.BSA'
  end)
end)

suite.describe('the load order', function()
  local root = jess.fs.join(scratch, 'openmw-import-morrowind-order')
  local iniPath = jess.fs.join(root, 'Morrowind.ini')
  local dataFiles = jess.fs.join(root, 'Data Files')

  suite.beforeEach(function()
    fs.remove(root, { recursive = true })
    jess.fs.createDir(dataFiles)
  end)

  local function path(name: string): string return jess.fs.join(dataFiles, name) end

  --- Files that are one file under several names, so the filesystem gives every name one time.
  local function together(first: string, ...: string)
    jess.fs.write(path(first), 'TES3')

    for _, name in { ... } do
      assert(fs.hardLink(path(first), path(name)))
    end
  end

  --- A file the filesystem's clock puts after `earlier`, however coarse that clock is.
  local function after(earlier: string, name: string)
    local first = assert(jess.fs.stat(path(earlier)))
    local deadline, later = os.clock() + 10, false

    repeat
      jess.fs.write(path(name), 'TES3')
      local metadata = assert(jess.fs.stat(path(name)))
      local seconds, was = metadata.modifiedSeconds or 0, first.modifiedSeconds or 0
      later = seconds > was
        or (seconds == was and (metadata.modifiedNanoseconds or 0) > (first.modifiedNanoseconds or 0))
    until later or os.clock() > deadline

    expect(later).toBe(true)
  end

  --- The `content=` list an import gives the INI's `names`, in the order the INI lists them.
  local function order(names: { string }): { string }
    local entries: ini.MultiMap = {}

    for index, name in names do
      entries[`Game Files:GameFile{index - 1}`] = { name }
    end

    local options = { gameFiles = true, archives = false, iniPath = iniPath }
    return ini.importMaps({}, entries, options).cfg.content
  end

  suite.it('puts masters first, then the later name first, whatever its case, among files of one time', function()
    together('alpha.esp', 'Zeta.esp', 'Base.esm', 'BETA.ESP', 'Addon.ESM', 'gamma.Esp')
    expect(order { 'alpha.esp', 'Zeta.esp', 'Base.esm', 'BETA.ESP', 'Addon.ESM', 'gamma.Esp' }).toEqual {
      'Base.esm',
      'Addon.ESM',
      'Zeta.esp',
      'gamma.Esp',
      'BETA.ESP',
      'alpha.esp',
    }
  end)

  suite.it('puts a file changed earlier before one changed later, whatever their names', function()
    together('Alpha.esp', 'Early.esm')
    after('Alpha.esp', 'Zeta.esp')
    after('Zeta.esp', 'Late.esm')
    after('Late.esm', 'Middle.esp')
    expect(order { 'Middle.esp', 'Zeta.esp', 'Late.esm', 'Alpha.esp', 'Early.esm' }).toEqual {
      'Early.esm',
      'Late.esm',
      'Alpha.esp',
      'Zeta.esp',
      'Middle.esp',
    }
  end)

  suite.it('keeps an entry the INI gives twice, twice', function()
    together('Base.esm', 'Plugin.esp')
    expect(order { 'Plugin.esp', 'Base.esm', 'Plugin.esp' }).toEqual {
      'Base.esm',
      'Plugin.esp',
      'Plugin.esp',
    }
  end)

  suite.it('puts two files whose names differ only in case in the order of their paths', function()
    together('Twin.esp', 'Base.esm')
    -- A filesystem that doesn't tell the two names apart has one file here, and nothing to order.
    if jess.fs.exists(path 'twin.esp') then return end

    assert(fs.hardLink(path 'Twin.esp', path 'twin.esp'))
    expect(order { 'twin.esp', 'Base.esm', 'Twin.esp' }).toEqual { 'Base.esm', 'Twin.esp', 'twin.esp' }
    expect(order { 'Twin.esp', 'twin.esp', 'Base.esm' }).toEqual { 'Base.esm', 'Twin.esp', 'twin.esp' }
  end)
end)

suite.describe('documents and writers', function()
  local root = jess.fs.join(scratch, 'openmw-import-morrowind-writers')
  jess.fs.createDir(root)
  local cfgPath = jess.fs.join(root, 'openmw.cfg')

  suite.afterEach(function() jess.fs.remove(cfgPath) end)

  suite.it('keeps comments, blank lines, and untouched lines where they were', function()
    jess.fs.write(
      cfgPath,
      '# top\r\n\r\nno-sound=0\r\n# audio\r\nno-sound=0\r\nkey = value # kept\r\nencoding=win1250\r\nencoding=win1251\r\nconfig=sub\r\ndata=Configured\r\n\r\n# tail\r\n# OpenMW-Config Serializer Version: 3.0.0\r\n'
    )
    local document = ini.loadDocument(cfgPath)
    ini.applyUpdate(document, {
      cfg = {
        ['no-sound'] = { '1' },
        encoding = { 'win1252' },
        data = { 'Configured', 'Explicit' },
      },
      changedKeys = { 'data', 'encoding', 'no-sound' },
    }, {})
    -- A removed line takes the comment above it along; a replaced encoding goes to the end; a
    -- folder the chain has only under its resolved path is added again, as dream-ini adds it.
    expect(text.renderDocument(document)).toBe 'key=value # kept\ndata=Configured\nconfig=sub\n\n# tail\nencoding=win1252\nno-sound=1\ndata=Configured\ndata=Explicit\n'
  end)

  suite.it('replaces a singleton in every place it was written, and gates the lists', function()
    jess.fs.write(
      cfgPath,
      'data-local=a\ncontent=Old.esp\nfallback-archive=Old.bsa\ndata-local=b\nfallback=Old,1\n'
    )
    local document = ini.loadDocument(cfgPath)
    local result = {
      cfg = {
        content = { 'New.esp' },
        ['fallback-archive'] = { 'New.bsa' },
        fallback = { 'New,2' },
      },
      changedKeys = { 'content', 'fallback', 'fallback-archive' },
    }
    ini.applyUpdate(document, result, { dataLocal = 'c', archives = false })
    expect(text.renderDocument(document)).toBe 'content=Old.esp\nfallback-archive=Old.bsa\nfallback=New,2\ndata-local=c\n'
    ini.applyUpdate(document, result, { gameFiles = true })
    expect(text.renderDocument(document)).toBe 'data-local=c\nfallback=New,2\ncontent=New.esp\nfallback-archive=New.bsa\n'
  end)

  suite.it('writes through a temporary file and reports the failure with the path', function()
    ini.saveCfg({ content = { 'A.esp' }, data = { 'Data Files' } }, cfgPath)
    local written = jess.fs.read(cfgPath) or ''
    expect(written).toContain 'content=A.esp\n'
    expect(written).toContain '# OpenMW-Config Serializer Version:'
    ini.saveResolvedCfg({ content = { 'A.esp' } }, cfgPath)
    expect(jess.fs.read(cfgPath)).toBe 'content=A.esp\n'
    local missing = jess.fs.join(root, 'nowhere', 'openmw.cfg')
    expect(function() ini.saveCfg({}, missing) end).toThrow(`dream.ini: {missing}: `)
    expect(
      function()
        ini.applyUpdate(
          ini.loadDocument(cfgPath),
          { cfg = {}, changedKeys = {} },
          { archive = true } :: any
        )
      end
    ).toThrow 'unknown option \'archive\''
  end)

  suite.it('renders the text each writer writes, without writing it', function()
    local cfg = { content = { 'A.esp' }, data = { 'Data Files' } }
    local rendered = ini.renderCfg(cfg, cfgPath)
    expect(jess.fs.exists(cfgPath)).toBe(false)
    expect(rendered).toBe 'content=A.esp\ndata=Data Files\n# OpenMW-Config Serializer Version: 3.0.0\n'
    ini.saveCfg(cfg, cfgPath)
    expect(jess.fs.read(cfgPath)).toBe(rendered)
    expect(function() ini.renderCfg({ fallback = { 'no comma' } }, cfgPath) end).toThrow 'fallback needs Key,Value'

    jess.fs.write(cfgPath, '# kept only where it was written\ndata=mods\n')
    local document = ini.loadDocument(cfgPath)
    ini.applyUpdate(
      document,
      { cfg = { ['no-sound'] = { '1' } }, changedKeys = { 'no-sound' } },
      {}
    )
    local resolved = ini.renderResolvedDocument(document)
    local mods = jess.fs.join(assert(fs.canonicalize(root)), 'mods')
    expect(resolved).toBe(`data={mods}\nno-sound=1\n`)
    expect(jess.fs.read(cfgPath)).toBe '# kept only where it was written\ndata=mods\n'
    ini.saveResolvedDocument(document, cfgPath)
    expect(jess.fs.read(cfgPath)).toBe(resolved)
  end)
end)

return suite
