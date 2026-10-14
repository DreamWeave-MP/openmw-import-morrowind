--!strict
--!native
-- SPDX-License-Identifier: MIT OR Apache-2.0
-- The writers: the imported map as a new openmw.cfg, spelled as given or resolved, and a
-- preserved document written back. Every write goes through a temporary file beside the target
-- and a rename, so a failure leaves whatever was there whole.
local types, options, config, document =
  require './types', require '@dream-ini/options', require './config', require './document'
local configuration = require '@openmw-config'
type MultiMap = types.MultiMap
type Update = types.Update
type Document = document.Document

--- The folder an output's document belongs to: the file's folder, or the working directory for a
--- bare name (`save_cfg_output_to_path`).
local function directoryOf(path: string): string return jess.fs.parent(path) or '' end

--- `cfg` as the text of a new openmw.cfg at `path`, with every value spelled as given, in key
--- order, ending in openmw-config's serializer stamp (`serialize_cfg_output`). `path` is the file
--- the text is for, which only a refusal names; nothing is read or written.
local function renderCfg(cfg: MultiMap, path: string): string
  cfg = options.multimap('ini.renderCfg', cfg)
  return config.renderMap(cfg, directoryOf(path), true)
end

--- `cfg` written to `path` as a new openmw.cfg with every value spelled as given, in key order,
--- ending in openmw-config's serializer stamp (`save_cfg_output_to_path`).
local function saveCfg(cfg: MultiMap, path: string)
  cfg = options.multimap('ini.saveCfg', cfg)
  document.replaceFile(path, config.renderMap(cfg, directoryOf(path), true))
end

--- `cfg` written to `path` with its folders resolved against the file's folder, the way dream-ini
--- writes an import whose output lives elsewhere (`save_resolved_cfg_to_path`).
local function saveResolvedCfg(cfg: MultiMap, path: string, tokens: configuration.Tokens?)
  cfg = options.multimap('ini.saveResolvedCfg', cfg)
  document.replaceFile(path, config.renderMap(cfg, directoryOf(path), false, tokens))
end

local UpdateSpec: options.Spec = {
  gameFiles = 'boolean',
  archives = 'boolean',
  dataLocal = 'string',
  resources = 'string',
  userData = 'string',
}
table.freeze(UpdateSpec)

local function applyUpdate(
  target: Document,
  result: { cfg: MultiMap, changedKeys: { string } },
  update: Update?
)
  local read = options.read('ini.applyUpdate', update, UpdateSpec)
  document.apply(target, {
    cfg = options.multimap('ini.applyUpdate', result.cfg),
    changedKeys = result.changedKeys,
  }, read :: Update)
end

--- A loaded document's resolved text: its whole chain flattened, every folder spelled as the
--- path it resolves to (`serialize_resolved_configuration`).
local function renderResolvedDocument(target: Document): string
  return config.resolvedText(target.config)
end

--- A loaded document's resolved text written to `path`
--- (`save_resolved_configuration_to_path`).
local function saveResolvedDocument(target: Document, path: string)
  document.replaceFile(path, renderResolvedDocument(target))
end

return table.freeze {
  renderCfg = renderCfg,
  saveCfg = saveCfg,
  saveResolvedCfg = saveResolvedCfg,
  loadDocument = document.load,
  applyUpdate = applyUpdate,
  renderResolvedDocument = renderResolvedDocument,
  saveResolvedDocument = saveResolvedDocument,
}
