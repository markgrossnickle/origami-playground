--!strict
--!native
--[[
	Base64 — encode/decode arbitrary byte strings to a DataStore-safe ASCII
	form.

	Why this exists: we persist voxel data as packed binary buffers. A raw
	`buffer.tostring` result contains bytes >= 0x80, which are not valid UTF-8
	and can be silently corrupted (or rejected) by DataStore SetAsync. Base64
	maps every byte onto the 64-character ASCII-safe alphabet, costing ~33%
	size — still far smaller than a JSON sparse map of the same data.

	Standard RFC 4648 alphabet with '=' padding.
]]

local Base64 = {}

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

-- Precompute encode (index 0..63 -> byte) and decode (byte -> index) tables.
local ENCODE: { [number]: number } = {}
local DECODE: { [number]: number } = {}
for i = 1, #ALPHABET do
	local code = string.byte(ALPHABET, i)
	ENCODE[i - 1] = code
	DECODE[code] = i - 1
end
local PAD = string.byte("=")

function Base64.encode(input: string): string
	local len = #input
	if len == 0 then
		return ""
	end

	-- Output length: 4 chars per 3 input bytes, rounded up.
	local outLen = math.floor((len + 2) / 3) * 4
	local out = buffer.create(outLen)
	local outPos = 0

	local i = 1
	while i <= len do
		local b1 = string.byte(input, i)
		local b2 = if i + 1 <= len then string.byte(input, i + 1) else nil
		local b3 = if i + 2 <= len then string.byte(input, i + 2) else nil

		local n1 = bit32.rshift(b1, 2)
		local n2 = bit32.bor(bit32.lshift(bit32.band(b1, 3), 4), if b2 then bit32.rshift(b2, 4) else 0)
		buffer.writeu8(out, outPos, ENCODE[n1])
		buffer.writeu8(out, outPos + 1, ENCODE[n2])
		outPos += 2

		if b2 then
			local n3 = bit32.bor(bit32.lshift(bit32.band(b2, 15), 2), if b3 then bit32.rshift(b3, 6) else 0)
			buffer.writeu8(out, outPos, ENCODE[n3])
		else
			buffer.writeu8(out, outPos, PAD)
		end
		outPos += 1

		if b3 then
			buffer.writeu8(out, outPos, ENCODE[bit32.band(b3, 63)])
		else
			buffer.writeu8(out, outPos, PAD)
		end
		outPos += 1

		i += 3
	end

	return buffer.tostring(out)
end

function Base64.decode(input: string): string
	local len = #input
	if len == 0 then
		return ""
	end

	-- Each 4 chars -> 3 bytes; strip padding from the count.
	local padCount = 0
	if string.byte(input, len) == PAD then
		padCount += 1
	end
	if len > 1 and string.byte(input, len - 1) == PAD then
		padCount += 1
	end

	local outLen = math.floor(len / 4) * 3 - padCount
	if outLen <= 0 then
		return ""
	end
	local out = buffer.create(outLen)
	local outPos = 0

	local i = 1
	while i <= len do
		local c1 = DECODE[string.byte(input, i)]
		local c2 = DECODE[string.byte(input, i + 1)]
		local rawC3 = string.byte(input, i + 2)
		local rawC4 = string.byte(input, i + 3)
		local c3 = if rawC3 and rawC3 ~= PAD then DECODE[rawC3] else nil
		local c4 = if rawC4 and rawC4 ~= PAD then DECODE[rawC4] else nil

		-- Skip any stray non-alphabet characters defensively.
		if c1 and c2 then
			buffer.writeu8(out, outPos, bit32.bor(bit32.lshift(c1, 2), bit32.rshift(c2, 4)))
			outPos += 1
			if c3 then
				buffer.writeu8(out, outPos, bit32.band(bit32.bor(bit32.lshift(c2, 4), bit32.rshift(c3, 2)), 255))
				outPos += 1
				if c4 then
					buffer.writeu8(out, outPos, bit32.band(bit32.bor(bit32.lshift(c3, 6), c4), 255))
					outPos += 1
				end
			end
		end

		i += 4
	end

	if outPos == outLen then
		return buffer.tostring(out)
	end
	-- Trim if we wrote fewer bytes than the estimate (malformed input).
	local trimmed = buffer.create(outPos)
	buffer.copy(trimmed, 0, out, 0, outPos)
	return buffer.tostring(trimmed)
end

return Base64
