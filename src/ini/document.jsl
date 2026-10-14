--!strict
--!native
-- SPDX-License-Identifier: MIT OR Apache-2.0
-- An openmw.cfg kept as its lines, loaded and updated the way dream-ini's `load_cfg_document` and
-- `apply_preserved_cfg_update` load and update one: a replaced list gives up its old lines' places
-- and goes at the end; imported singleton overrides also move to the end. The configuration chain
-- is loaded beside the lines and receives the same edits for resolved output.
local types, lines = require './types', require '@dream-ini/document'
local fs = require '@dream/fs'
local openmw = require '@openmw-config'
type MultiMap = types.MultiMap
type Update = types.Update
type Entry = lines.Entry

-- The lines, their edits, and the write are dream-ini's; `load` and `apply` are written against
-- these names.
local parse, append, replaceList = lines.parse, lines.append, lines.replaceList

export type Document = {
  --- The openmw-config document of the same file, edited in step with the lines.
  config: openmw.Config,
  --- The file the lines came from, or would have come from.
  path: string,
  entries: { Entry },
}

--- The openmw.cfg at `path` (a file, or a folder holding one) as a document: its openmw-config
--- chain and its own lines. A missing file is an empty document at that path.
local function load(path: string, options: openmw.Options?): Document
  local config = openmw.loadOptional(path, options)
  local file = config:rootFile()
  local source, problem, kind = fs.readFileString(file)
  if not source and kind ~= 'notFound' then error(problem, 0) end

  return { config = config, path = file, entries = parse(source or '') }
end

--- `result`'s changed keys applied to `document`, as `apply_preserved_cfg_update` applies them:
--- the encoding, `no-sound`, and the `fallback=` list when they changed; each imported `data=`
--- folder the chain doesn't have; the content and archive lists when they changed and `update`
--- imported them; and the folder overrides, each replacing every line of its key.
local function apply(
  document: Document,
  result: { cfg: MultiMap, changedKeys: { string } },
  update: Update
)
  local cfg, config = result.cfg, document.config
  local changed: { [string]: boolean } = {}

  for _, key in result.changedKeys do
    changed[key] = true
  end

  local encoding = cfg.encoding
  if changed.encoding and encoding and #encoding > 0 then
    local value = encoding[#encoding]
    config:set('encoding', value)
    replaceList(document, 'encoding', { value })
  end

  for _, key in { 'no-sound', 'fallback' } do
    if not changed[key] then continue end

    config:replace(key, cfg[key])
    replaceList(document, key, cfg[key])
  end

  if changed.data then
    -- Compare only explicit data entries, not Context-composed resource or local directories.
    -- The imported spelling is compared to resolved paths, as the importer has always done.
    local directories: { [string]: boolean } = {}
    for _, entry in config:entries() do
      if entry.key == 'data' and entry.resolved then directories[entry.resolved] = true end
    end

    for _, directory in cfg.data or {} do
      if directories[directory] then continue end

      config:append('data', directory)
      append(document, 'data', { directory })
      -- The folder just appended is the chain's last `data`, so the last one's path is its path.
      directories[config:path('data') :: string] = true
    end
  end

  if update.gameFiles and changed.content then
    config:replace('content', cfg.content)
    replaceList(document, 'content', cfg.content)
  end

  if update.archives ~= false and changed['fallback-archive'] then
    config:replace('fallback-archive', cfg['fallback-archive'])
    replaceList(document, 'fallback-archive', cfg['fallback-archive'])
  end

  local overrides: { { key: string, path: string? } } = {
    { key = 'data-local', path = update.dataLocal },
    { key = 'resources', path = update.resources },
    { key = 'user-data', path = update.userData },
  }

  for _, override in overrides do
    local {key, path} = override
    if not path then continue end

    -- One set replaces the effective singleton; clearing repeatedly cannot erase a parent file.
    config:set(key, path)
    replaceList(document, key, { path })
  end
end

return table.freeze {
  load = load,
  apply = apply,
  replaceFile = lines.replaceFile,
}
