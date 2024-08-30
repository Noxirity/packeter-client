function Base64(data, method: "encode" | "decode"): string | nil
	local b = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	local padding = { "", "==", "=" }

	local function toBinaryString(input, bits)
		local binary = {}
		for i = bits, 1, -1 do
			table.insert(binary, (input % 2 ^ i - input % 2 ^ (i - 1) > 0) and "1" or "0")
		end
		return table.concat(binary)
	end

	local function fromBinaryString(input)
		local number = 0
		for i = 1, #input do
			number = number + (input:sub(i, i) == "1" and 2 ^ (#input - i) or 0)
		end
		return number
	end

	if method == "encode" then
		local binaryData = table.concat({
			data:gsub(".", function(char)
				return toBinaryString(char:byte(), 8)
			end),
		})

		binaryData = binaryData .. "0000"

		local encoded = binaryData:gsub("%d%d%d?%d?%d?%d?", function(bits)
			if #bits < 6 then
				return ""
			end
			return b:sub(fromBinaryString(bits) + 1, fromBinaryString(bits) + 1)
		end)

		return encoded .. padding[#data % 3 + 1]
	elseif method == "decode" then
		data = data:gsub("[^" .. b .. "=]", "")

		local binaryData = table.concat({
			data:gsub(".", function(char)
				if char == "=" then
					return ""
				end
				return toBinaryString(b:find(char) - 1, 6)
			end),
		})

		local decoded = binaryData:gsub("%d%d%d?%d?%d?%d?%d?%d?", function(bits)
			if #bits ~= 8 then
				return ""
			end
			return string.char(fromBinaryString(bits))
		end)

		return decoded
	end

	return nil
end

return Base64
