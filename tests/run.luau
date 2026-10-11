--!strict
--!native
-- The package's own cases: the edge semantics dream-ini pins, checked on the port alone.
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
end)

return suite
