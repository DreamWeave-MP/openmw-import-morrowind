--!strict
--!native
-- SPDX-License-Identifier: MIT OR Apache-2.0
-- The token roots an options table carries beside its options. dream-ini asks the platform what
-- `?userdata?` and a cfg's other path tokens stand for; here the caller names each root, the way
-- openmw-config takes them, and a root it has no token for is refused in the options reader's
-- words.
local configuration = require '@openmw-config'

local Names: { [string]: boolean } =
  { globalPath = true, localPath = true, userConfig = true, userData = true }
table.freeze(Names)

--- `given` without its `tokens`, for the options reader, and the tokens, checked.
local function take(context: string, given: unknown): (unknown, configuration.Tokens?)
  if type(given) ~= 'table' then return given, nil end

  local options = given :: { [unknown]: unknown }
  local tokens = options.tokens
  if tokens == nil then return given, nil end

  if type(tokens) ~= 'table' then
    error(`{context}.tokens: expected a table of path roots, got {typeof(tokens)}`, 0)
  end

  for name, root in tokens :: { [unknown]: unknown } do
    if type(name) ~= 'string' or not Names[name] then
      error(
        `{context}.tokens: unknown path token '{tostring(name)}'; known tokens are globalPath, localPath, userConfig, userData`,
        0
      )
    end

    if type(root) ~= 'string' then
      error(`{context}.tokens.{name}: expected string, got {typeof(root)}`, 0)
    end
  end

  local rest = table.clone(options)
  rest.tokens = nil
  return rest, tokens :: configuration.Tokens
end

return table.freeze { take = take }
