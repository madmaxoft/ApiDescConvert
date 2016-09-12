-- APIDescConvert.lua

-- Converts the APIDesc files from old-format parameter descriptions (single string) to new format (array-table of tables), using AutoAPI descriptions and heuristics
-- Assumes that the AutoAPI files are in the AutoAPI subfolder ("AutoAPI/cArrowEntity.lua" etc.)
-- Assumes that the APIDesc files are in the Desc subfolder ("Desc/Classes/Projectiles.lua" etc.)





--- Loads the AutoAPI files into a single dictionary-table
local function loadAutoApi()
	print("Loading AutoAPI...")
	local filenames = dofile("AutoAPI/_files.lua")
	local res = {}
	for _, fnam in ipairs(filenames) do
		local api = dofile("AutoAPI/" .. fnam)
		for k, v in pairs(api) do
			assert(not(res[k]))
			res[k] = v
		end
	end
	return res
end





--- Serializes a simple table (no functions, no loops, simple strings as table keys)
-- a_Table is the table to serialize
-- a_Indent is the indenting to use
local function serializeSimpleTable(a_Table, a_Indent, a_KeySortFunction)
	-- Check params:
	assert(type(a_Table) == "table")
	local indent = a_Indent or ""
	assert(type(indent) == "string")

	-- Sort the keys alphabetically:
	local keys = {}
	local allKeysAreNumbers = true
	for k, _ in pairs(a_Table) do
		local kt = type(k)
		assert((kt == "string") or (kt == "number"), "Unsupported key type in table to serialize: " .. kt)
		if (kt ~= "number") then
			allKeysAreNumbers = false
		end
		table.insert(keys, k)
	end
	table.sort(keys, a_KeySortFunction)

	-- Output the keys:
	local lines = {}
	local idx = 1
	for _, key in ipairs(keys) do
		local keyPrefix
		if (allKeysAreNumbers) then
			keyPrefix = indent
		else
			keyPrefix = indent .. key .. " = "
		end
		local v = a_Table[key]
		local vt = type(v)
		if (vt == "table") then
			if not(allKeysAreNumbers) then
				lines[idx] = indent .. key .. " ="
				idx = idx + 1
			end
			lines[idx] = indent .. "{"
			lines[idx + 1] = serializeSimpleTable(v, indent .. "\t", a_KeySortFunction)
			lines[idx + 2] = indent .. "},"
			idx = idx + 3
		elseif (
			(vt == "number") or
			(vt == "boolean")
		) then
			-- Numbers and bools have a safe "tostring" function
			lines[idx] = string.format("%s%s,", keyPrefix, tostring(v))
			idx = idx + 1
		elseif (vt == "string") then
			if (v:find("\t")) then
				-- Tabs are only contained in long descriptions, serialize as no-parse-string:
				if ((v:find("%[%[")) or (v:find("%]%]"))) then
					-- String contains "[[" or "]]", serialize as [==[string]==]:
					lines[idx] = string.format("%s[==[\n%s]==],", keyPrefix, v)
				else
					lines[idx] = string.format("%s[[\n%s]],", keyPrefix, v)
				end
			else
				-- Use a special format for strings: %q includes the quotes and escapes as needed
				lines[idx] = string.format("%s%q,", keyPrefix, v)
			end
			idx = idx + 1
		else
			error("Unsupported value type in table to serialize: " .. type(v))
		end
	end
	return table.concat(lines, "\n")
end





--- Splits the param string into individual params
-- Returns an array-table of the individual params
local function splitParamString(a_ParamString)
	local res = {}
	a_ParamString:gsub("[^,]+",
		function (a_Match)
			-- Trim:
			local trimmedMatch = a_Match:match("^%s*(.-)%s*$")
			if (trimmedMatch and (trimmedMatch ~= "")) then
				table.insert(res, trimmedMatch)
			end
		end
	)
	return res
end





--- Dictionary of known param description to type mapping
local g_KnownTypesMap =
{
	AngleDegrees = "number",
	Biome = "number",
	BlockFace = "eBlockFace",
	BlockLight = "number",
	BlockSkyLight = "number",
	BlockMeta = "number",
	BlockType = "number",
	BLOCKTYPE = "number",
	BlockX = "number",
	BlockY = "number",
	BlockZ = "number",
	bool = "boolean",
	boolean = "boolean",
	CallbackFunction = "function",
	CraftingGrid = "cCraftingGrid",
	DamageType = "eDamageType",
	eBiome = "EMCSBiome",
	eDimension = "eDimension",
	eGameMode = "eGameMode",
	EMCSBiome = "EMCSBiome",
	Eps = "number",
	eWeather = "eWeather",
	IniFile = "cIniFile",
	ItemDamage = "number",
	ItemType = "number",
	max = "number",
	min = "number",
	NIBBLETYPE = "number",
	Number = "number",
	number = "number",
	self = "self",
	short = "number",
	table = "table",
	Vector3i = "Vector3i",
	Vector3f = "Vector3f",
	Vector3d = "Vector3d",
	World = "cWorld",
	x = "number",
	X = "number",
	y = "number",
	Y = "number",
	z = "number",
	Z = "number",
	--[[
	["{{Globals#BlockFaces|eBlockFace}}"] = "eBlockFace",
	["{{Globals#BlockFace|eBlockFace}}"] = "eBlockFace",
	["{{Globals#ClickAction|ClickAction}}"] = "eClickAction",
	["{{Globals#DamageType|DamageType}}"] = "eDamageType",
	["{{Globals#MobType|MobType}}"] = "eMobType",
	--]]
}




--- Array of string match patterns, if a param contains the Pattern string, it will be considered that type
local g_KnownTypesMatchers =
{
	--[[
	Template:
	{ Pattern = "", Type = "" },
	--]]
	{ Pattern = "Add[XYZ]", Type = "number" },
	{ Pattern = "Are[A-Z]", Type = "boolean" },
	{ Pattern = "BlockArea", Type = "cBlockArea" },
	{ Pattern = "Block[XYZ]", Type = "number" },
	{ Pattern = "BoundingBox", Type = "cBoundingBox" },
	{ Pattern = "[Cc]allback$", Type = "function" },
	{ Pattern = "[Cc]allbackFn", Type = "function" },
	{ Pattern = "[Cc]allbacks", Type = "table" },
	{ Pattern = "Can[A-Z]", Type = "boolean" },
	{ Pattern = "Center[XYZ]", Type = "number" },
	{ Pattern = "Chunk[XZ]", Type = "number" },
	{ Pattern = "Coeff", Type = "number" },
	{ Pattern = "Count", Type = "number" },
	{ Pattern = "Cuboid", Type = "cCuboid" },
	{ Pattern = "Data", Type = "string" },
	{ Pattern = "Does[A-Z]", Type = "boolean" },
	{ Pattern = "Enchantments", Type = "cEnchantments" },
	{ Pattern = "End[XYZ]", Type = "number" },
	{ Pattern = "Expand[XYZ]", Type = "number" },
	{ Pattern = "Face", Type = "eBlockFace" },
	{ Pattern = "Height", Type = "number" },
	{ Pattern = "[a-z]ID", Type = "number" },
	{ Pattern = "Index", Type = "number" },
	{ Pattern = "Is[A-Z]", Type = "boolean" },
	{ Pattern = "Length", Type = "number" },
	{ Pattern = "Max", Type = "number" },
	{ Pattern = "Message", Type = "string" },
	{ Pattern = "Min", Type = "number" },
	{ Pattern = "Name", Type = "string" },
	{ Pattern = "Num", Type = "number" },
	{ Pattern = "Offset[XYZ]", Type = "number" },
	{ Pattern = "Origin[XYZ]", Type = "number" },
	{ Pattern = "Path", Type = "string" },
	{ Pattern = "Pixel[XYZ]", Type = "number" },
	{ Pattern = "Pos[XYZ]", Type = "number" },
	{ Pattern = "Point[XYZ]", Type = "number" },
	{ Pattern = "Radius", Type = "number" },
	{ Pattern = "Rel[XYZ]", Type = "number" },
	{ Pattern = "Should[A-Z]", Type = "boolean" },
	{ Pattern = "Size[XYZ]", Type = "number" },
	{ Pattern = "Speed[XYZ]", Type = "number" },
	{ Pattern = "Start[XYZ]", Type = "number" },
	{ Pattern = "Str", Type = "string" },
	{ Pattern = "str", Type = "string" },
	{ Pattern = "Text", Type = "string" },
	{ Pattern = "Tick[A-Zs]", Type = "number" },  -- Allow both styles: TickTimer and AgeInTicks
	{ Pattern = "Use[A-Z]", Type = "boolean" },
	{ Pattern = "UUID", Type = "string" },
	{ Pattern = "Width", Type = "number" },
	{ Pattern = "[XYZ][12]", Type = "number" },
}





--- Tries to guess a parameter type based on the string provided in the APIDesc
-- Returns the param name and the guessed Lua type
-- a_ParamString is the parameter's description from the APIDesc, such as "Command" or "{{cPlayer|Player}}
local function guessParamType(a_ParamString, a_AutoApi)
	-- Check params:
	assert(type(a_ParamString) == "string")
	assert(type(a_AutoApi) == "table")

	-- If the param string has brackets around it, remove those:
	if (a_ParamString:match("%b[]")) then
		a_ParamString = a_ParamString:sub(2, -2)
	end

	-- Try a list of known types:
	local k = g_KnownTypesMap[a_ParamString]
	if (k) then
		return a_ParamString, k
	end

	-- Try a list of known string-matching heuristics:
	for _, matcher in ipairs(g_KnownTypesMatchers) do
		if (a_ParamString:find(matcher.Pattern)) then
			-- Try to extract the param name from {{class|name}}-style params:
			local paramName = a_ParamString:match("%{%{[^|}]+|(.*)%}%}")
			if not(paramName) then
				-- No explicit name given, just use the whole string:
				paramName = a_ParamString
			end
			return paramName, matcher.Type
		end
	end

	-- If the param desc matches a class name in the API desc, use that:
	if (a_AutoApi[a_ParamString]) then
		return a_ParamString, a_ParamString
	end

	-- Try to match "{{ClassName}}" and "{{ClassName|ParamName}}" descriptions:
	local className = a_ParamString:match("%{%{([^|}]+)|?.*%}%}")
	if (className) then
		local paramName = a_ParamString:match("%{%{[^|}]+|(.*)%}%}")
		if not(paramName) then
			-- No name given, extract one from the class name, or enum name
			paramName = className:gsub(".*#", "")
		end
		return paramName, className
	end

	return a_ParamString, "<unknown>"
end





--- Converts the function parameters to the new format
-- Returns the conversion result as a table
local function convertFunctionParams(a_Params, a_AutoApi)
	if not(a_Params) then
		-- No params at all
		return
	end
	if (type(a_Params) == "table") then
		-- Already in new format, return as-is:
		return a_Params
	end

	-- Convert:
	assert(type(a_Params) == "string")
	-- Split the string, try to guess param types:
	local split = splitParamString(a_Params)
	local params = {}
	for idx, v in ipairs(split) do
		local isOptional
		if (v:match("%b[]")) then
			isOptional = true
			v = string.sub(v, 2, -2)  -- Cut away the brackets at the ends
		end
		local n, t = guessParamType(v, a_AutoApi)
		params[idx] = { Name = n, Type = t, IsOptional = isOptional}
	end
	return params
end





--- Converts a single function signature to the new format
-- Converts in-place
local function convertFunctionSignature(a_Signature, a_AutoApi)
	-- Check params:
	assert(type(a_Signature) == "table")
	assert(type(a_AutoApi) == "table")

	-- Convert the signature:
	a_Signature.Params = convertFunctionParams(a_Signature.Params, a_AutoApi)
	a_Signature.Returns = convertFunctionParams(a_Signature.Returns or a_Signature.Return, a_AutoApi)
	a_Signature.Return = nil

	-- Remove names from Returns[], if they are a copy of the type:
	for _, ret in ipairs(a_Signature.Returns or {}) do
		if (ret.Name == ret.Type) then
			ret.Name = nil
		end
	end

	-- Remove empty Params and Returns:
	if (a_Signature.Params and not(a_Signature.Params[1])) then
		a_Signature.Params = nil
	end
	if (a_Signature.Returns and not(a_Signature.Returns[1])) then
		a_Signature.Returns = nil
	end
end





--- Assigns a sorting rank for various keys in the output tables, thus sorting the table in a certain way
-- If a key is not in the table, it is assigned the default rank of 1000
-- The keys are sorted by their rank, then alphabetically
local g_SortRank =
{
	-- Top level:
	Classes         =  100,
	ExtraPages      = 2000,
	IgnoreClasses   = 2100,
	IgnoreFunctions = 2200,
	IgnoreConstants = 2300,
	IgnoreVariables = 2400,

	-- Inside a class:
	Desc           = 100,
	Functions      = 200,
	Constants      = 300,
	ConstantGroups = 400,
	Variables      = 500,
	AdditionalInfo = 600,

	-- Inside a function:
	IsStatic = 100,
	Params   = 200,
	Returns  = 300,
	Notes    = 400,

	-- Inside a function param:
	Name       = 100,
	Type       = 200,
	IsOptional = 300,

	-- Inside an AdditionalInfo element:
	Header   = 100,
	Contents = 200,
}





--- Sorting function for the output files' tables
-- Sorts the keys in a specific order - Globals last, Desc first etc.
local function descSortFunction(a_Key1, a_Key2)
	local rank1 = g_SortRank[a_Key1] or 1000
	local rank2 = g_SortRank[a_Key2] or 1000
	if (rank1 ~= rank2) then
		-- The keys have a different rank, sort them by their rank
		return (rank1 < rank2)
	end

	-- The keys have the same rank, sort alphabetically, case-insensitive:
	return (string.lower(a_Key1) < string.lower(a_Key2))
end





--- Converts a single APIDesc file to the new format
local function convertApiDescFile(a_ApiDescFileName, a_AutoApi)
	-- Check params:
	assert(a_ApiDescFileName)
	assert(type(a_AutoApi) == "table")

	print("Converting file " .. a_ApiDescFileName)
	local apiDesc = dofile(a_ApiDescFileName)
	-- apiDesc either lists the classes directly (Class/*.lua files) or has a Classes member listing the classes (APIDesc.lua)
	for className, classDesc in pairs(apiDesc.Classes or apiDesc) do
		for fnName, fnDesc in pairs(classDesc.Functions or {}) do
			if not(fnDesc[1]) then
				fnDesc = { fnDesc }  -- Unify all descriptions to be array-table of signatures
			end
			for _, signature in ipairs(fnDesc) do
				convertFunctionSignature(signature, a_AutoApi)
			end
		end  -- for fnName, fnDesc
	end  -- for className, classDesc

	-- Output to a new file:
	local newFileName = a_ApiDescFileName .. ".new"
	local f = assert(io.open(newFileName, "w"))
	f:write("return\n{\n", serializeSimpleTable(apiDesc, "\t", descSortFunction), "\n}\n")
	f:close()

	-- Self-test by loading the newly exported file:
	assert(dofile(newFileName))
end





--- Array of filenames of all APIDesc files:
local g_ApiDescFilenames =
{
	"Desc/APIDesc.lua",
	"Desc/Classes/BlockEntities.lua",
	"Desc/Classes/Geometry.lua",
	"Desc/Classes/Network.lua",
	"Desc/Classes/Plugins.lua",
	"Desc/Classes/Projectiles.lua",
	"Desc/Classes/WebAdmin.lua",
}





--- Main entrypoint:
local autoApi = loadAutoApi()
for _, fnam in ipairs(g_ApiDescFilenames) do
	convertApiDescFile(fnam, autoApi)
end
