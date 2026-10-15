# Benchmarks

`bench/bench.jsl` times the package through what it exports: imports over parsed maps and over
files, the command's request with each of its three writers, the command line's parse and what it
prints, a plugin's header, an update of a loaded cfg, and a whole run of the command as a new
process. It writes its own installs below the scratch folder it is given (the game's layout, with
256 content files and 9 archives in `Data Files`, and a modded one, with the plugins spread over
the 8 data folders of an openmw.cfg) and removes them when it is done. Each workload is warmed up,
sized to a batch of about a tenth of a second, and reported as the median of seven batches, with a
full collection before each. Every result is held to what the generator of its input says it must
be, outside the time: the `fallback=` lines by count and length, the load order against one worked
out from the files themselves, the archives, the events, and the text each writer gives.

```sh
jess run --package jpk/openmw-import-morrowind --package-path jpk \
  --capability filesystem.read --capability filesystem.write --capability process.spawn \
  jpk/openmw-import-morrowind/bench/bench.jsl <scratch folder> [filter] \
  [jess] [package folder] [package path]
```

The filter is a part of a workload's name, or several with `|` between them. The last three
arguments are for the whole run of the command, which is left out without them. The first row is
not a batch: it is the one time a process pays for the package's own modules to be read, compiled
and run, measured after everything they require of other packages is loaded. A filter of `load`
prints that row and nothing else, without writing a file, so that many processes can be timed.

It refuses a build without the verified toolchain.

## The move onto l3i 2.0, base against head

- Machine: Intel Core i7-10870H @ 2.20 GHz, 16 threads, shared with other agents' tests while this
  ran (load average 2.5 when it started, 2.6 when it ended).
- Date: 2026-10-12.
- Binary: the verified release build of Jess 0.1.0 on l3i 2.0 (Luau 0.742), the same one for both
  sides, with the same `dream-ini` and `openmw-config` beside it.
- Base: `5d99578`, the package as it was with this bench added, running the bench as it is at
  head. Head: `76915e2`.
- Protocol: the whole bench against base and against head, four times each, back to back inside
  one hold of the machine's bench lock, the order swapped every round. Each cell is the median of
  its four runs. A difference under 5 percent is called no change.

| Workload | Base, µs | Head, µs | Base / head |
| --- | ---: | ---: | ---: |
| load: the package's modules, required for the first time | 15953.6 | 15928.7 | no change |
| importMaps: a retail INI's settings (373 of 608 lines) | 114.8 | 111.6 | no change |
| importMaps: the same over a cfg (100 lines) | 119.1 | 117.2 | no change |
| importMaps: a load order of 256, none of it on disk | 355.0 | 278.3 | 1.28x |
| importPaths: the game's layout (256 content files, 9 archives) | 7915.2 | 2079.5 | 3.81x |
| importPaths: the game's layout, verbose | 8390.1 | 8239.8 | no change |
| importPaths: a modded layout (a cfg of 8 data folders) | 11037.2 | 5250.9 | 2.10x |
| commands.import: a preview with no cfg (the new writer) | 8593.9 | 2808.8 | 3.06x |
| commands.import: a dry run in place (the preserved writer) | 12599.3 | 6853.9 | 1.84x |
| commands.import: a dry run to another folder (the resolved writer) | 13078.1 | 7208.7 | 1.81x |
| cli.parse: every flag that sets a field (20 arguments) | 6.6 | 6.7 | no change |
| cli.transcript: a verbose preview (267 lines of progress) | 136.1 | 135.2 | no change |
| cli.render: a verbose run to a file (267 lines) | 187.4 | 187.3 | no change |
| readPluginHeader: 16 masters | 44.2 | 44.1 | no change |
| renderCfg: an import's settings (641 lines) | 715.8 | 733.2 | no change |
| loadDocument and applyUpdate: 32 data folders the cfg doesn't have | 948.4 | 478.0 | 1.98x |
| the command, as a new process: a preview of the game's layout | 92736.6 | 87697.1 | 1.06x |

The load row alone, over 60 new processes a side in the same hold: a median of 15658 µs for base
and 15784 µs for head, which is no change.

None of what moved is the dialect's doing. An import asked the filesystem for the canonical path
of every content file it found, because that path is the last thing the load order compares, and
that one call cost more than everything else an import did. Only two spellings of one name, found
as two files changed at the same instant, come down to their paths, so the path is now resolved
when a comparison gets that far (or when a verbose import reports the file, which is why that row
stands still). Between the commit before it and the commit that made it, the game's layout went
from 8031 µs to 2439 µs, and it is most of every row that imports files. The sort decides whether
a file is a master when it is found, not twice at every comparison, and on its own that is too
little to tell from noise: between the two commits the same row went from 2439 µs to 2133 µs
(1.14x) when the change was made, and from 2115 µs to 1971 µs (1.07x) and from 2113 µs to 2082 µs
(1.02x) in two later holds of the lock, of four rounds and of eight, against the 5 percent this
table calls no change. The INI's numbered entries (`GameFile0`, `Archive 0`) were collected,
sorted as a whole, and then appended index by index through `table.move`, which fits its
destination to the new length on every call and so copied the list each time; their keys are
grouped by index as they are met and their values appended one by one, which is the load order
row. An update that adds data folders to a loaded cfg copied every entry of the chain, once per
folder added, to read the last one's path; it asks the chain for that path.

What a run of the command spends is mostly not the import. Of the 88 ms the last row takes, 16 ms
is this package's modules loading for the first time, and that row is where three things were
measured and left out. A reader of the numbered entries that took the index from the key's bytes
was faster again on the load order row (235 µs against 268 µs) and cost 0.4 ms more to load, which
one import in a process never earns back. Comprehensions and a slice in three modules of the
payload moved no row and cost 0.68 ms to load, a fifth of a millisecond for a module's first; the
payload went back to its loops and `table.move`, and the record patterns, which cost nothing to
load, stayed. The medians behind those two are of 60 processes a side in one hold of the lock,
on a quieter machine than the table's: 14423 µs for base, 14825 µs with the byte reader, 15500 µs
with the comprehensions on top, 14498 µs for the package as it is. Loading the plugin header's
module on first use, since no import reads a header, took the load from 15586 µs to 15015 µs in
another such hold: 3.7 percent, under the bar this table uses, and not kept.

What is left in an import, roughly, from a niced run with a clock around each phase and each host
call timed on its own: one `stat` for each place a file is looked for (0.9 ms of the 2.1 ms of
the game's layout; the modded layout's row is 3.2 ms longer, most of it a plugin looked for in
four or five folders before the one that has it), `dream-ini`'s parse of the INI (0.35 ms), and
the sort (0.3 ms before the masters were decided ahead of it). The sort stays a comparator sort:
its keys end in two strings, and a stable `data.argsort` over the numeric ones would order two
entries that tie on everything differently from `table.sort`, which the `content=` list would
show. A listing of each folder in place of a `stat` for each file would not find a name the way
the filesystem does where it ignores case. The writers' rows are `openmw-config`'s validation of
every setting, about a microsecond each.

## Which modules are native, and why

Jess compiles to machine code only what is marked (`--!native` on a module, `@native` on one
function), and every load pays for what is marked. A module carries `--!native` when a row below
spends its time there and the module is small (12 KB or less); a larger module carries `@native`
on the functions the row spends its time in, and nothing else.

Measured 2026-10-15 with `jess 0.1.0`, the verified release build of jess `07c38cb` on l3i
2.0.3, on the i7-10870H, the one-minute load 1.11 and 1.16 at the start of the two
sessions. In each session the bench ran alternately on this package and on a copy of it with
every module marked, three fresh runs of `bench/bench.jsl` each, every run's row the median of
its batches; a column is the median of the three, and a ratio is against the all-marked runs of
the same session. Which functions a row spends its time in comes from `jess run --profile` of
that row alone, unmarked. The load cost is a fresh `jess run --package <this package>
--package-path jpk` of a script that only requires `@openmw-import-morrowind`, the two sides alternating, the
median of five each after one warm-up.

| Requiring `@openmw-import-morrowind` | All marked | This state |
| --- | ---: | ---: |
| Unmarked | 0.066 s | 0.058 s |
| Final | 0.064 s | 0.062 s |

| Row | All marked (ms) | Unmarked / all marked | Final (ms) | Final / all marked |
| --- | ---: | ---: | ---: | ---: |
| load: the package's modules, required for the first time | 13.52 | 0.342× | 9.717 | 0.719× |
| importMaps: a retail INI's settings (373 of 608 lines) | 0.09927 | **1.167×** | 0.1039 | 1.047× |
| importMaps: the same over a cfg (100 lines) | 0.1041 | **1.057×** | 0.1092 | 1.050× |
| importMaps: a load order of 256, none of it on disk | 0.2429 | **1.271×** | 0.2594 | **1.068×** |
| importPaths: the game's layout (256 content files, 9 archives) | 1.784 | **1.207×** | 1.859 | 1.042× |
| importPaths: the game's layout, verbose | 6.858 | **1.127×** | 7.184 | 1.048× |
| importPaths: a modded layout (a cfg of 8 data folders) | 4.563 | **1.147×** | 4.695 | 1.029× |
| commands.import: a preview with no cfg (the new writer) | 2.256 | **1.189×** | 2.313 | 1.025× |
| commands.import: a dry run in place (the preserved writer) | 5.525 | **1.224×** | 5.679 | 1.028× |
| commands.import: a dry run to another folder (the resolved writer) | 5.884 | **1.134×** | 6.034 | 1.025× |
| cli.parse: every flag that sets a field (20 arguments) | 0.00639 | **1.814×** | 0.01069 | **1.674×** |
| cli.transcript: a verbose preview (267 lines of progress) | 0.1277 | **1.305×** | 0.1563 | **1.224×** |
| cli.render: a verbose run to a file (267 lines) | 0.1734 | **1.218×** | 0.2074 | **1.196×** |
| readPluginHeader: 16 masters | 0.04059 | **1.143×** | 0.04034 | 0.994× |
| renderCfg: an import's settings (641 lines) | 0.3729 | **1.099×** | 0.3736 | 1.002× |
| loadDocument and applyUpdate: 32 data folders the cfg doesn't have | 0.2559 | 1.024× | 0.2577 | 1.007× |

What carries the directive (every module here is one a row spends its time in, unmarked):

- Whole: `ini/config`, `ini/content_files`, `ini/importer`, `ini/plugin_header`, `ini/storage`.
- Unmarked: `cli`, `commands`, `ini/document`, `ini/fallback_keys`, `ini/tokens`, `ini/types`,
  `ini/writers`, `init`, `main`.

`cli` parses a command line and prints what a run did, once a run, and is never marked, so its
three rows are slower than all marked by rule: parsing every flag (1.67x, of a 6 µs call) and the
verbose transcript and render of a run (1.22x and 1.20x, of 0.13 ms and 0.17 ms). The fourth,
`importMaps` over a load order of 256 (1.068x), is inside this protocol's noise: two
all-marked copies of dream-archive, measured the same way, put 10 of 109 rows more than 5% apart,
the 95th percentile at 1.074x.
