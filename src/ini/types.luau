--!strict
--!native
-- SPDX-License-Identifier: MIT OR Apache-2.0
local ini = require '@dream-ini'

export type MultiMap = ini.MultiMap
export type Warning = ini.Warning
export type Event = { kind: string, path: string, modified: number? }

--- The options `importMaps` and `importPaths` share, as `dreamIni` takes them.
export type ImportOptions = {
  game: string?,
  gameFiles: boolean?,
  fonts: boolean?,
  archives: boolean?,
  verbose: boolean?,
  encoding: string?,
  dataDirs: { string }?,
  dataLocal: string?,
  resources: string?,
  userData: string?,
  cfgDir: string?,
}

--- `importMaps`' options: the shared ones and the INI's nominal location, which places the
--- default `Data Files` folder.
export type MapsOptions = ImportOptions & { iniPath: string? }

--- `importPaths`' options: the shared ones, the files to read, and the two dream-ini's command
--- sets on its `ImportOptions` for a result that is going to a file: `dataDirBase`, the folder a
--- relative `dataDirs` entry is searched from instead of the cfg's, and `writeResolvedDataDirs`,
--- which writes each `dataDirs` entry as the folder it resolved to instead of as it was given.
export type PathsOptions = ImportOptions & {
  ini: string,
  cfg: string?,
  dataDirBase: string?,
  writeResolvedDataDirs: boolean?,
}

--- What a preserved openmw.cfg takes from an import besides its changed keys, as dream-ini's
--- `PreservedCfgUpdate` carries it: whether the content and archive lists were imported, and the
--- folder overrides. `archives` is on unless turned off, as in the import options.
export type Update = {
  gameFiles: boolean?,
  archives: boolean?,
  dataLocal: string?,
  resources: string?,
  userData: string?,
}

export type Result = {
  cfg: MultiMap,
  text: string,
  warnings: { Warning },
  events: { Event },
  changedKeys: { string },
}

--- One import, options read and defaults filled: what the content and archive resolution runs on.
export type Request = {
  cfg: MultiMap,
  ini: MultiMap,
  iniPath: string,
  cfgDir: string?,
  dataDirs: { string },
  dataDirBase: string?,
  writeResolvedDataDirs: boolean?,
  verbose: boolean,
}

return table.freeze {}
