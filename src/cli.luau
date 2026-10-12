--!strict
--!native
-- SPDX-License-Identifier: MIT OR Apache-2.0
--[[
@openmw-import-morrowind/cli: dream-ini 1.0.1's command line, over
@openmw-import-morrowind/commands.

  Usage: what --help prints
  parse(argv) -> (command, nil) | (nil, message)
  transcript(result) -> { { stream, text } }
  render(result, { stream }?) -> string
  status(result) -> exit status
  run(argv) -> exit status

  openmw-import-morrowind --ini <FILE> [--cfg <FILE>] [--output <FILE>|--in-place] [options]

The flags are dream-ini's, each with its short form, set on the request field it stands for:
`parse` reads an argument list into the request `commands.import` takes without touching a file,
or says what it couldn't read. A value follows its flag or is attached to it (`--ini FILE`,
`--ini=FILE`, `-i FILE`, `-iFILE`, `-i=FILE`); flags that take none can share a dash, and the last
of them may take one (`-gno out.cfg`). As in the original a flag is given once, a value that
starts with a dash has to be attached, and a path is never given by position.

`transcript` is what the original prints for a result, line by line and in its order, each line
with the stream it goes to; `render` is the lines of one stream as text. A preview's standard
output is the cfg and nothing else, so its progress goes to standard error; a run that writes a
file prints its progress to standard output, ending in `write to: <file>`. Warnings and errors go
to standard error either way. `status` is the exit status the original gives that result, and
`run` is the three together: nothing is worked out here that a result doesn't carry.

Where this differs from the original, each on purpose:

- The command is the package's name. `--version` prints it with the release it follows.
- Exit statuses for the command line itself are Jess's: 8 where the original gives 2 for a command
  line it can't use, 9 where it gives 1 for an import that failed. 0 and 253 are the original's.
- A refusal of the command line is one line, `openmw-import-morrowind: <message>`, where the
  original prints clap's error and usage.
- `-C`/`--generate-completion`, `-M`/`--generate-manpage`, `install-launcher`, and the window the
  original opens when given no arguments are not this package's, and are refused by name.
- The original asks the platform what a cfg's path tokens stand for. Nothing here can, so four
  flags the original doesn't have name the roots: `--token-userconfig`, `--token-userdata`,
  `--token-local`, `--token-global`.
- A dry run has no flag, as in the original, whose preview is one; `dryRun` is the request's.
]]

local commands = require '@openmw-import-morrowind/commands'
local importer = require '@openmw-import-morrowind'
local process = require '@dream/process'

export type Command =
  { command: 'import', request: commands.Request }
  | { command: 'help' }
  | { command: 'version' }

export type Stream = 'stdout' | 'stderr'

--- One piece of what a result prints, and where.
export type Line = { stream: Stream, text: string }

export type RenderOptions = { stream: Stream? }

--- What a flag takes: nothing (`switch`), a path, which can't be empty, or text; or what it asks
--- for instead of an import.
type Kind = 'switch' | 'path' | 'text' | 'help' | 'version' | 'absent'

--- A flag: its spellings, and the request field it sets. A `switch` sets `value`, which is true
--- unless given; `list` makes the value the field's one entry; `token` makes the field a root in
--- the request's `tokens`.
type Flag = {
  long: string,
  short: string?,
  kind: Kind,
  sets: string?,
  value: boolean?,
  list: boolean?,
  token: boolean?,
  why: string?,
}

local Name = 'openmw-import-morrowind'

local Exit = table.freeze { ok = 0, invalidInput = 8, runtime = 9, missingIni = 253 }

--- The original's flags in the order its help lists them, then the four this package adds.
local Flags: { Flag } = {
  { long = 'cfg', short = 'c', kind = 'path', sets = 'cfg' },
  { long = 'data', short = 'd', kind = 'path', sets = 'dataDirs', list = true },
  { long = 'encoding', short = 'e', kind = 'text', sets = 'encoding' },
  { long = 'fonts', short = 'f', kind = 'switch', sets = 'fonts' },
  { long = 'game-files', short = 'g', kind = 'switch', sets = 'gameFiles' },
  { long = 'help', short = 'h', kind = 'help' },
  { long = 'ini', short = 'i', kind = 'path', sets = 'ini' },
  { long = 'data-local', short = 'l', kind = 'path', sets = 'dataLocal' },
  { long = 'no-archives', short = 'n', kind = 'switch', sets = 'archives', value = false },
  { long = 'output', short = 'o', kind = 'path', sets = 'output' },
  { long = 'resources', short = 'r', kind = 'path', sets = 'resources' },
  { long = 'user-data', short = 'u', kind = 'path', sets = 'userData' },
  { long = 'verbose', short = 'v', kind = 'switch', sets = 'verbose' },
  { long = 'in-place', short = 'w', kind = 'switch', sets = 'inPlace' },
  {
    long = 'generate-completion',
    short = 'C',
    kind = 'absent',
    why = 'it has no shell completion scripts to generate',
  },
  {
    long = 'generate-manpage',
    short = 'M',
    kind = 'absent',
    why = 'it has no manpage to generate',
  },
  { long = 'version', short = 'V', kind = 'version' },
  { long = 'token-userconfig', kind = 'path', sets = 'userConfig', token = true },
  { long = 'token-userdata', kind = 'path', sets = 'userData', token = true },
  { long = 'token-local', kind = 'path', sets = 'localPath', token = true },
  { long = 'token-global', kind = 'path', sets = 'globalPath', token = true },
}

local Long: { [string]: Flag }, Short: { [string]: Flag } = {}, {}

for _, flag in Flags do
  Long[flag.long] = flag
  if flag.short then Short[flag.short] = flag end
end

--- The flags that take no value.
local Bare: { [Kind]: boolean } = { switch = true, help = true, version = true, absent = true }

local NoArguments =
  'an import needs --ini <FILE>: given no arguments the original opens its window, which is not part of this package'

local Launcher =
  'install-launcher is not part of this package: it adds the original\'s window to the desktop\'s menu, and the window is not here'

local Usage = [[
openmw-import-morrowind: dream-ini 1.0.1 for Jess, under its package's name (the original's
program is dream-ini). Import Morrowind.ini settings into openmw.cfg

Usage: openmw-import-morrowind --ini <FILE> [--cfg <FILE>] [--output <FILE>|--in-place] [options]

Options:
  -c, --cfg <FILE>           openmw.cfg file
  -d, --data <DIR>           Explicit Data Files directory to search
  -e, --encoding <ENCODING>  Character encoding for imported content-file names: win1250,
                             win1251, or win1252
  -f, --fonts                Import bitmap fonts
  -g, --game-files           Import esm and esp files
  -h, --help                 Print help
  -i, --ini <FILE>           Morrowind.ini file
  -l, --data-local <DIR>     Set data-local in the imported cfg, replacing any existing value
  -n, --no-archives          Disable bsa archives import
  -o, --output <FILE>        Output openmw.cfg file
  -r, --resources <DIR>      Set resources in the imported cfg, replacing any existing value
  -u, --user-data <DIR>      Set user-data in the imported cfg, replacing any existing value
  -v, --verbose              Verbose output
  -w, --in-place             Write the imported result back to the --cfg file
  -V, --version              Print version

Import mode requires --ini <FILE>. Optional --cfg <FILE> is read as the base config; without it,
import starts empty. Positional Morrowind.ini/openmw.cfg paths are intentionally unsupported; use
flags. Default output is cfg text on stdout with diagnostics on stderr. Use --output <FILE> to
write a cfg file, or --in-place with --cfg <FILE> to update the base cfg. Relative --data is
resolved from the output cfg directory, from --cfg for stdout preview, or from the current
directory and written absolute when stdout has no cfg context.

The cfg's path tokens. The original asks the platform what each stands for; this package can't,
so a cfg that uses one needs its root named:
      --token-userconfig <DIR>  ?userconfig?: OpenMW's configuration folder for the user
      --token-userdata <DIR>    ?userdata?: OpenMW's data folder for the user
      --token-local <DIR>       ?local?: the folder OpenMW is installed in
      --token-global <DIR>      ?global?: the system's shared data folder

Not part of this package, and refused by name: -C, --generate-completion <SHELL>;
-M, --generate-manpage; install-launcher; and the window the original opens when it is given no
arguments.

Exit status: 0 done, with warnings or without; 253 the --ini file does not exist, as in the
original; 8 the command line can't be used (the original's 2); 9 the import failed and nothing was
written (the original's 1).]]

--- `text` before and after its first `=`, or nil when it has none.
local function pair(text: string): (string?, string?)
  local found = string.find(text, '=', 1, true)
  if not found then return nil, nil end

  return string.sub(text, 1, found - 1), string.sub(text, found + 1)
end

--- Why an argument that isn't a flag can't be taken.
local function stray(argument: string): string
  if argument == 'install-launcher' then return Launcher end

  return `unexpected argument '{argument}': paths are given with --ini and --cfg, never by position`
end

local function parse(argv: { string }): (Command?, string?)
  if #argv == 0 then return nil, NoArguments end

  -- `help` is the command clap adds beside install-launcher.
  if argv[1] == 'help' then
    if argv[2] then return nil, stray(argv[2]) end

    return { command = 'help' :: 'help' }, nil
  end

  local request: { [string]: unknown } = {}
  local tokens: { [string]: string }, given: { [string]: string } = {}, {}
  local index = 1

  --- Takes one flag as `spelling` gave it, with the value attached to it if one was, reading the
  --- next argument when it needs one. A refusal comes back as its message.
  local function take(flag: Flag, spelling: string, attached: string?): string?
    if flag.kind == 'absent' then return `{spelling} is not part of this package: {flag.why}` end
    if given[flag.long] then return `{spelling} can be given only once` end

    given[flag.long] = spelling
    local field = flag.sets :: string

    if flag.kind == 'switch' then
      if attached then return `{spelling} takes no value` end

      request[field] = flag.value ~= false
      return nil
    end

    local value = attached
    if not value then
      local following = argv[index + 1]
      -- A value that starts with a dash is read as a flag, as clap reads it, unless it is attached.
      if following and (following == '-' or string.sub(following, 1, 1) ~= '-') then
        index += 1
        value = following
      end
    end

    if not value or (value == '' and flag.kind == 'path') then
      return `{spelling} requires a value`
    end

    if flag.token then
      tokens[field] = value
    elseif flag.list then
      request[field] = { value }
    else
      request[field] = value
    end

    return nil
  end

  while index <= #argv do
    local argument = argv[index]

    if argument == '--' then
      -- Everything after it is an argument by position, and none is taken.
      if argv[index + 1] then return nil, stray(argv[index + 1]) end
    elseif string.sub(argument, 1, 2) == '--' then
      local name, attached = pair(string.sub(argument, 3))
      local flag = Long[name or string.sub(argument, 3)]
      if not flag then return nil, `unknown option '--{name or string.sub(argument, 3)}'` end

      if flag.kind == 'help' or flag.kind == 'version' then
        return { command = flag.kind :: 'help' | 'version' }, nil
      end

      local refusal = take(flag, `--{flag.long}`, attached)
      if refusal then return nil, refusal end
    elseif string.sub(argument, 1, 1) == '-' and #argument > 1 then
      -- Flags that share a dash, the last of which may take what follows it as its value.
      local position = 2

      while position <= #argument do
        local letter = string.sub(argument, position, position)
        local flag = Short[letter]
        if not flag then return nil, `unknown option '-{letter}'` end

        if flag.kind == 'help' or flag.kind == 'version' then
          return { command = flag.kind :: 'help' | 'version' }, nil
        end

        local attached: string? = nil
        if not Bare[flag.kind] then
          local rest = string.sub(argument, position + 1)
          if string.sub(rest, 1, 1) == '=' then rest = string.sub(rest, 2) end
          if position < #argument then attached = rest end

          position = #argument
        end

        local refusal = take(flag, `-{letter}`, attached)
        if refusal then return nil, refusal end

        position += 1
      end
    else
      return nil, stray(argument)
    end

    index += 1
  end

  if given.output and given['in-place'] then
    return nil, '--output and --in-place are mutually exclusive'
  end

  if not given.ini then return nil, '--ini <FILE> is required for imports' end
  if given['in-place'] and not given.cfg then return nil, '--in-place requires --cfg <FILE>' end

  if next(tokens) then request.tokens = tokens end

  -- Each value was read as the kind its field takes, so the table is the command's request.
  return { command = 'import' :: 'import', request = (request :: unknown) :: commands.Request }, nil
end

--- An event as the original words it (`ImportEvent`'s display).
local function eventText({kind, path, modified}: importer.Event): string
  if kind == 'contentFileResolved' then
    return `content file: {path} timestamp = ({string.format('%d', modified or 0)})`
  end

  if kind == 'archiveResolved' then return `archive: {path}` end

  if kind == 'dataDirAddedForContent' then
    return `adding data directory used to resolve content files: {path}`
  end

  if kind == 'dataDirAddedForArchive' then
    return `adding data directory used to resolve fallback archives: {path}`
  end

  return `{kind}: {path}`
end

local function transcript(result: commands.Result): { Line }
  local lines: { Line } = {}

  local function say(stream: Stream, text: string) table.insert(lines, { stream = stream, text = text }) end

  if result.outcome == 'missingIni' then
    say('stderr', 'ini file does not exist\n')
    return lines
  end

  if result.cfgMissing then say('stderr', 'cfg file does not exist\n') end

  local failure = result.failure
  local stage = if failure then failure.stage else nil
  local problem = if failure then `ERROR: {failure.message}\n` else ''

  if stage == 'options' then
    say('stderr', problem)
    return lines
  end

  -- A preview's standard output is the cfg and nothing else.
  local progress: Stream = if result.target then 'stdout' else 'stderr'

  if result.cfg then say(progress, `load cfg file: {result.cfg}\n`) end

  say(progress, `load ini file: {result.ini}\n`)

  if stage == 'import' then
    say('stderr', problem)
    return lines
  end

  for _, event in result.events do
    say(progress, `{eventText(event)}\n`)
  end

  for _, warning in result.warnings do
    say('stderr', `Warning: {warning.message}\n`)
  end

  -- The original announces the file before it writes it, so a write that failed was announced.
  if result.target and not result.dryRun then say('stdout', `write to: {result.target}\n`) end

  if failure then
    say('stderr', problem)
    return lines
  end

  local text = result.text
  if not result.target and text and text ~= '' then say('stdout', text) end

  return lines
end

local function render(result: commands.Result, options: RenderOptions?): string
  local stream: Stream = if options and options.stream then options.stream else 'stdout'
  return table.concat([for line in transcript(result) if line.stream == stream => line.text])
end

local function status(result: commands.Result): number
  if result.outcome == 'missingIni' then return Exit.missingIni end
  if result.outcome == 'failed' then return Exit.runtime end

  return Exit.ok
end

local function run(argv: { string }): number
  local command, message = parse(argv)

  if not command then
    process.write('stderr', `{Name}: {message}\n`)
    return Exit.invalidInput
  end

  if command.command == 'help' then
    process.write('stdout', `{Usage}\n`)
    return Exit.ok
  end

  if command.command == 'version' then
    process.write('stdout', `{Name} (dream-ini {importer.version})\n`)
    return Exit.ok
  end

  local result = commands.import(command.request)

  for _, line in transcript(result) do
    process.write(line.stream, line.text)
  end

  return status(result)
end

return table.freeze {
  Exit = Exit,
  Usage = Usage,
  parse = parse,
  transcript = transcript,
  render = render,
  status = status,
  run = run,
}
