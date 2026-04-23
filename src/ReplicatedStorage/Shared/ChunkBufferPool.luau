--!strict
--!native

--[=[
	@class ChunkBufferPool

	Tiny free-list of `buffer` instances sized for one chunk's block data
	(BLOCKS_PER_CHUNK = 4096 bytes each). Lets WorldService recycle evicted
	chunk buffers instead of letting Lua GC them and forcing WorldGenModule
	to allocate fresh 4 KB buffers on every chunk generation.

	Acquired buffers are zero-cleared (via `buffer.fill`) so callers can
	treat them as freshly created.

	Pool size is capped to keep idle memory bounded — beyond the cap,
	released buffers fall through to GC.
]=]

local ChunkUtil = require(script.Parent.ChunkUtil)

local BLOCKS_PER_CHUNK = ChunkUtil.BLOCKS_PER_CHUNK
local POOL_MAX = 200 -- 200 × 4 KB = 800 KB held idle at peak

local ChunkBufferPool = {}

local _free: { buffer } = {}

function ChunkBufferPool.acquire(): buffer
	local n = #_free
	if n > 0 then
		local buf = _free[n]
		_free[n] = nil
		buffer.fill(buf, 0, 0)
		return buf
	end
	return buffer.create(BLOCKS_PER_CHUNK)
end

function ChunkBufferPool.release(buf: buffer): ()
	-- Defensive: only pool buffers of the expected size. If a caller hands
	-- back a non-chunk buffer, silently drop it rather than poison the pool.
	if buffer.len(buf) ~= BLOCKS_PER_CHUNK then
		return
	end
	if #_free >= POOL_MAX then
		return
	end
	table.insert(_free, buf)
end

function ChunkBufferPool.size(): number
	return #_free
end

return ChunkBufferPool
