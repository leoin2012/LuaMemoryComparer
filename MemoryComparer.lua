local MemoryComparer = {}

MemoryComparer.snapshot = 
{
	before = nil,
	after = nil,
}

local OutputFileDir = Application.persistentDataPath.."/"

local CollectTypeMap = {
	["table"] = true,
	["function"] = true,
	["thread"] = true,
	["userdata"] = true,
}

-- Get the format string of date time.
local function FormatDateTimeNow()
	local dateTime = os.date("*t")
	local strDateTime = string.format("%04d%02d%02d-%02d%02d%02d", tostring(dateTime.year), tostring(dateTime.month), tostring(dateTime.day),
		tostring(dateTime.hour), tostring(dateTime.min), tostring(dateTime.sec))
	return strDateTime
end

local function CreateObjectReferenceInfoContainer()
	local container = {}
	setmetatable(container, {__mode = "k"})

	return container
end

local function __GetTableName(object)
	if object.Class and not string.IsNilOrEmpty(object.name) then
		return "[" .. object.name .. "]"
	end
	return ""
end

local function GetTableName(object)
	local tableName = ""
	if type(object) == "table" then
		local status, stackInfo = pcall(__GetTableName, object)
		if status then
			tableName = stackInfo
		end
	end
	return tableName
end

local function ObjectToString(object)
	if not object then return "" end

	local mt = getmetatable(object)
	if not mt then
		return tostring(object)
	end

	-- override tostring
	local objectName = ""
	local __tostring = rawget(mt, "__tostring")
	if __tostring then
		rawset(mt, "__tostring", nil)
		objectName = tostring(object)
		rawset(mt, "__tostring", __tostring)
	else
		objectName = tostring(object)
	end

	return objectName
end

local function MarkObject(object, container, referenceBy, parent)

	container[object] = container[object] or {referenceCount=0,parent=parent,referenceBys=nil}
	local objectReferenceSample = container[object]

	objectReferenceSample.referenceCount = objectReferenceSample.referenceCount + 1

	local referenceBys = objectReferenceSample.referenceBys
	if not referenceBys then
		referenceBys = {}
		objectReferenceSample.referenceBys = referenceBys
		table.insert(referenceBys, referenceBy)
		return true
	else
		table.insert(referenceBys, referenceBy)
		return false
	end
end

local function CollectObjectReference(objectName, object, container, parent)
	if not object then
		return 
	end
	-- eliminate self
	if object == MemoryComparer then
		return
	end

	objectName = objectName or ""
	container = container or CreateObjectReferenceInfoContainer()

	local objectType = type(object)
	if objectType == "table" then
		if object == _G then
			objectName = objectName .. "[_G]"
		end

		if MarkObject(object, container, objectName, parent) then
			local isWeakK = false
			local isWeakV = false
			local mt = getmetatable(object)
			if mt then
				local strMode = rawget(mt, "__mode")
				if strMode then
					if strMode == "k" then
						isWeakK = true
					elseif strMode == "v" then
						isWeakV = true
					elseif strMode == "kv" then
						isWeakK = true
						isWeakV = true
					end
				end
			end

			for k,v in pairs(object) do
				local strKeyType = type(k)
				local router = CollectTypeMap[strKeyType]
				if router then
					if not isWeakK then
						CollectObjectReference(objectName .. ".[table:key." .. strKeyType .. "]", k, container, object)
					end
					if not isWeakV then
						CollectObjectReference(objectName .. ".[table:value]", v, container, object)
					end
				else
					CollectObjectReference(objectName .. "." .. k, v, container, object)
				end
			end

			if mt then
				CollectObjectReference(objectName .. ".[metatable]", mt, container, object)
			end
		end
	elseif objectType == "function" then
		local stackInfo = debug.getinfo(object, "Su")

		objectName = objectName .. "[line:" .. tostring(stackInfo.linedefined) .. "@file:" .. stackInfo.short_src .. "]"

		if MarkObject(object, container, objectName, parent) then
			local nUpsNum = stackInfo.nups
			for i=1, nUpsNum do
				local strUpName, upValue = debug.getupvalue(object, i)
				local strUpValueType = type(upValue)

				local router = CollectTypeMap[strUpValueType]
				if router then

					CollectObjectReference(objectName .. ".[ups:" .. strUpValueType .. ":" .. strUpName .. "]" , upValue, container, object)
				end
			end

			-- local getfenv = debug.getfenv
			-- if getfenv then
			-- 	local env = getfenv(object)
			-- 	if env then
			-- 		CollectObjectReference(objectName .. ".[function:environment]", env, container, object)
			-- 	end
			-- end
		end
	elseif objectType == "thread" then
		if MarkObject(object, container, objectName, parent) then
			-- local getfenv = debug.getfenv
			-- if getfenv then
			-- 	local env = getfenv(object)
			-- 	if env then
			-- 		CollectObjectReference(objectName .. ".[function:environment]", env, container, object)
			-- 	end
			-- end

			local mt = getmetatable(object)
			if mt then

				CollectObjectReference(objectName .. ".[thread:metatable]", mt, container, object)
			end
		end
	elseif objectType == "userdata" then
		if MarkObject(object, container, objectName, parent) then
			-- local getfenv = debug.getfenv
			-- if getfenv then
			-- 	local env = getfenv(object)
			-- 	if env then
			-- 		CollectObjectReference(objectName .. ".[userdata:environment]", env, container, object)
			-- 	end
			-- end

			local mt = getmetatable(object)
			if mt then
				CollectObjectReference(objectName .. ".[userdata:metatable]", mt, container, object)
			end
		end
	elseif objectType == "string" then
		MarkObject(object, container, objectName .. ".[string]", parent)
	end
end

local function Snapshot(rootObject, rootObjectName)
	local t1 = os.time()

	collectgarbage("collect")

	if rootObject then
		rootObjectName = rootObjectName or tostring(rootObject)
	else
		rootObject = debug.getregistry()
		rootObjectName = "registry"
	end

	local container = CreateObjectReferenceInfoContainer()

	CollectObjectReference(rootObjectName, rootObject, container)

	MemoryComparer.snapshot.before = MemoryComparer.snapshot.after
	MemoryComparer.snapshot.after = container

	local t2 = os.time()
	print("MemoryComparer-Snapshot TimeCost:" .. (t2-t1) .. "s")
end

local function OutputSnapshotComparedFile(snapshot1, snapshot2)
	if not MemoryComparer.snapshot.before or not MemoryComparer.snapshot.after then
		return
	end

	local t1 = os.time()

	local snapshotBefore = MemoryComparer.snapshot.before
	local snapshotAfter = MemoryComparer.snapshot.after

	local snapshotAfterByOrder = {}
	for k in pairs(snapshotAfter) do
		table.insert(snapshotAfterByOrder, k)
	end

	table.sort(snapshotAfterByOrder, function(l, r)
		return snapshotAfter[l].referenceCount > snapshotAfter[r].referenceCount
	end)

	local strDateTime = FormatDateTimeNow()
	local filePath = string.format("%s/MemoryCompareReport-[%s].csv", OutputFileDir, strDateTime)
	local file = assert(io.open(filePath, "w"))

	if not file then return end

	local write = function(content)
		file:write(content)
	end

	-- increase class instance count
	local increaseClass = {}

	-- Write header
	write("Object,ObjectType,ReferenceCount,ReferenceBy\n")
	write("--------------------------------------------------------\n")

	for _,reference in ipairs(snapshotAfterByOrder) do
		if not snapshotBefore[reference] then
			local referenceType = type(reference)
			local referenceCount = snapshotAfter[reference].referenceCount
			local referenceBys = table.concat(snapshotAfter[reference].referenceBys,"/") 

			if referenceType == "string" then

				write(reference .. ","
					.. referenceType .. "," 
					.. referenceCount .. "," 
					.. referenceBys .. "\n")
			elseif referenceType == "table" then

				local tableName = GetTableName(reference)

				write(ObjectToString(reference) .. tableName .. ","
					.. referenceType .. "," 
					.. referenceCount .. "," 
					.. referenceBys .. "\n")

				if not string.IsNilOrEmpty(tableName) then
					increaseClass[tableName] = increaseClass[tableName] and (increaseClass[tableName]+1) or 1
				end
			else
				write(ObjectToString(reference) .. "," 
					.. referenceType .. "," 
					.. referenceCount .. "," 
					.. referenceBys .. "\n")
			end
		end
	end

	local content = ""
	local totalCount = 0
	for tableName,count in pairs(increaseClass) do
		totalCount = totalCount + count
		content = content .. tableName .. "," .. count .. "\n"
	end

	write("--------------------------------------------------------\n")
	write("Increase class instance count: " .. totalCount .. "\n")
	write("Class,ReferenceCount\n")
	write("--------------------------------------------------------\n")
	
	write(content)

	file:close()

	local t2 = os.time()
	print("MemoryComparer-Compare TimeCost:" .. (t2-t1) .. "s")
end

local function Compare()
	assert(MemoryComparer.snapshot.before and MemoryComparer.snapshot.after, "2 snapshot is needed for compare")
	OutputSnapshotComparedFile(MemoryComparer.snapshot.before, MemoryComparer.snapshot.after)
end

MemoryComparer.Snapshot = Snapshot
MemoryComparer.Compare = Compare

return MemoryComparer