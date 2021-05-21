local log = require('log')
local msgpack = require('msgpack')

local comparators = require('crud.compare.comparators')
local collations = require('crud.common.collations')

local keydef_lib

if pcall(require, 'tuple.keydef') then
    keydef_lib = require('tuple.keydef')
elseif pcall(require, 'keydef') then
    log.info('Impossible to load "tuple-keydef" module. Built-in "keydef" is used')
    keydef_lib = require('key_def')
else
    error(string.format('Seems your Tarantool version (%q' ..
            ') does not support "tuple-keydef" or "keydef" modules', _TARANTOOL))
end

-- As "tuple.key_def" doesn't support collation_id
-- we manually change it to collation
local function normalize_parts(index_parts)
    local result = {}

    for _, part in ipairs(index_parts) do
        if part.collation_id == nil then
            table.insert(result, part)
        else
            local part_copy = table.copy(part)
            part_copy.collation = collations.get(part)
            part_copy.collation_id = nil
            table.insert(result, part_copy)
        end
    end

    return result
end

local keydef_cache = {}
setmetatable(keydef_cache, {__mode = 'k'})

local function new(replicasets, space_name, field_names, index_name)
    -- Get requested and primary index metainfo.
    local conn = select(2, next(replicasets)).master.conn
    local space = conn.space[space_name]
    local index = space.index[index_name]
    local key = msgpack.encode({index_name, field_names})

    if keydef_cache[key] ~= nil then
        return keydef_cache[key]
    end

    -- Create a key def
    local primary_index = space.index[0]
    local space_format = space:format()
    local updated_parts = comparators.update_key_parts_by_field_names(
            space_format, field_names, index.parts
    )

    local keydef = keydef_lib.new(normalize_parts(updated_parts))
    if not index.unique then
        updated_parts = comparators.update_key_parts_by_field_names(
                space_format, field_names, primary_index.parts
        )
        keydef = keydef:merge(keydef_lib.new(normalize_parts(updated_parts)))
    end

    keydef_cache[key] = keydef

    return keydef
end

return {
    new = new,
}
