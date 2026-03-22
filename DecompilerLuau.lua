local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ReplicatedFirst   = game:GetService("ReplicatedFirst")
local Workspace         = game:GetService("Workspace")
local LocalPlayer       = Players.LocalPlayer
local FLOAT_PRECISION = 7
local Reader = {}
function Reader.new(bytecode)
	local stream = buffer.fromstring(bytecode)
	local cursor = 0
	local self   = {}
	function self:len()       return buffer.len(stream) end
	function self:nextByte()
		local r = buffer.readu8(stream, cursor); cursor += 1; return r
	end
	function self:nextSignedByte()
		local r = buffer.readi8(stream, cursor);  cursor += 1; return r
	end
	function self:nextBytes(count)
		local t = {}
		for i = 1, count do t[i] = self:nextByte() end
		return t
	end
	function self:nextChar()     return string.char(self:nextByte()) end
	function self:nextUInt32()
		local r = buffer.readu32(stream, cursor); cursor += 4; return r
	end
	function self:nextInt32()
		local r = buffer.readi32(stream, cursor); cursor += 4; return r
	end
	function self:nextFloat()
		local r = buffer.readf32(stream, cursor); cursor += 4
		return tonumber(string.format("%0."..FLOAT_PRECISION.."f", r))
	end
	function self:nextVarInt()
		local result = 0
		for i = 0, 4 do
			local b = self:nextByte()
			result = bit32.bor(result, bit32.lshift(bit32.band(b, 0x7F), i * 7))
			if not bit32.btest(b, 0x80) then break end
		end
		return result
	end
	function self:nextString(len)
		len = len or self:nextVarInt()
		if len == 0 then return "" end
		local r = buffer.readstring(stream, cursor, len); cursor += len; return r
	end
	function self:nextDouble()
		local r = buffer.readf64(stream, cursor); cursor += 8; return r
	end
	return self
end
function Reader:Set(fp) FLOAT_PRECISION = fp end
local MemeStrings = {
	" we lit",
	" decompiled with zukas ez decompiler",
	" DISASSEMBLED...",
	" Decompile these nuts",
	" params : ...",
	" " .. os.date(),
	" your gay advert could be here"
}
local Strings = {
	SUCCESS              = "--" .. MemeStrings[math.random(#MemeStrings)] .. "\n%s",
	TIMEOUT              = "-- DECOMPILER TIMEOUT",
	COMPILATION_FAILURE  = "-- SCRIPT FAILED TO COMPILE, ERROR:\n%s",
	UNSUPPORTED_LBC_VERSION = "-- PASSED BYTECODE IS TOO OLD AND IS NOT SUPPORTED",
	USED_GLOBALS         = "-- USED GLOBALS: %s.\n",
	DECOMPILER_REMARK    = "-- DECOMPILER REMARK: %s\n",
}
local CASE_MULTIPLIER = 227
local Luau = {
	OpCode = {
		{name="NOP",type="none"},{name="BREAK",type="none"},
		{name="LOADNIL",type="A"},{name="LOADB",type="ABC"},
		{name="LOADN",type="AsD"},{name="LOADK",type="AD"},
		{name="MOVE",type="AB"},
		{name="GETGLOBAL",type="AC",aux=true},{name="SETGLOBAL",type="AC",aux=true},
		{name="GETUPVAL",type="AB"},{name="SETUPVAL",type="AB"},
		{name="CLOSEUPVALS",type="A"},
		{name="GETIMPORT",type="AD",aux=true},
		{name="GETTABLE",type="ABC"},{name="SETTABLE",type="ABC"},
		{name="GETTABLEKS",type="ABC",aux=true},{name="SETTABLEKS",type="ABC",aux=true},
		{name="GETTABLEN",type="ABC"},{name="SETTABLEN",type="ABC"},
		{name="NEWCLOSURE",type="AD"},{name="NAMECALL",type="ABC",aux=true},
		{name="CALL",type="ABC"},{name="RETURN",type="AB"},
		{name="JUMP",type="sD"},{name="JUMPBACK",type="sD"},
		{name="JUMPIF",type="AsD"},{name="JUMPIFNOT",type="AsD"},
		{name="JUMPIFEQ",type="AsD",aux=true},{name="JUMPIFLE",type="AsD",aux=true},
		{name="JUMPIFLT",type="AsD",aux=true},{name="JUMPIFNOTEQ",type="AsD",aux=true},
		{name="JUMPIFNOTLE",type="AsD",aux=true},{name="JUMPIFNOTLT",type="AsD",aux=true},
		{name="ADD",type="ABC"},{name="SUB",type="ABC"},{name="MUL",type="ABC"},
		{name="DIV",type="ABC"},{name="MOD",type="ABC"},{name="POW",type="ABC"},
		{name="ADDK",type="ABC"},{name="SUBK",type="ABC"},{name="MULK",type="ABC"},
		{name="DIVK",type="ABC"},{name="MODK",type="ABC"},{name="POWK",type="ABC"},
		{name="AND",type="ABC"},{name="OR",type="ABC"},
		{name="ANDK",type="ABC"},{name="ORK",type="ABC"},
		{name="CONCAT",type="ABC"},
		{name="NOT",type="AB"},{name="MINUS",type="AB"},{name="LENGTH",type="AB"},
		{name="NEWTABLE",type="AB",aux=true},{name="DUPTABLE",type="AD"},
		{name="SETLIST",type="ABC",aux=true},
		{name="FORNPREP",type="AsD"},{name="FORNLOOP",type="AsD"},
		{name="FORGLOOP",type="AsD",aux=true},
		{name="FORGPREP_INEXT",type="A"},
		{name="FASTCALL3",type="ABC",aux=true},
		{name="FORGPREP_NEXT",type="A"},{name="NATIVECALL",type="none"},
		{name="GETVARARGS",type="AB"},{name="DUPCLOSURE",type="AD"},
		{name="PREPVARARGS",type="A"},{name="LOADKX",type="A",aux=true},
		{name="JUMPX",type="E"},{name="FASTCALL",type="AC"},
		{name="COVERAGE",type="E"},{name="CAPTURE",type="AB"},
		{name="SUBRK",type="ABC"},{name="DIVRK",type="ABC"},
		{name="FASTCALL1",type="ABC"},
		{name="FASTCALL2",type="ABC",aux=true},{name="FASTCALL2K",type="ABC",aux=true},
		{name="FORGPREP",type="AsD"},
		{name="JUMPXEQKNIL",type="AsD",aux=true},{name="JUMPXEQKB",type="AsD",aux=true},
		{name="JUMPXEQKN",type="AsD",aux=true},{name="JUMPXEQKS",type="AsD",aux=true},
		{name="IDIV",type="ABC"},{name="IDIVK",type="ABC"},
		{name="_COUNT",type="none"},
	},
	BytecodeTag = {
		LBC_VERSION_MIN=3, LBC_VERSION_MAX=6,
		LBC_TYPE_VERSION_MIN=1, LBC_TYPE_VERSION_MAX=3,
		LBC_CONSTANT_NIL=0, LBC_CONSTANT_BOOLEAN=1, LBC_CONSTANT_NUMBER=2,
		LBC_CONSTANT_STRING=3, LBC_CONSTANT_IMPORT=4, LBC_CONSTANT_TABLE=5,
		LBC_CONSTANT_CLOSURE=6, LBC_CONSTANT_VECTOR=7,
	},
	BytecodeType = {
		LBC_TYPE_NIL=0,LBC_TYPE_BOOLEAN=1,LBC_TYPE_NUMBER=2,LBC_TYPE_STRING=3,
		LBC_TYPE_TABLE=4,LBC_TYPE_FUNCTION=5,LBC_TYPE_THREAD=6,LBC_TYPE_USERDATA=7,
		LBC_TYPE_VECTOR=8,LBC_TYPE_BUFFER=9,LBC_TYPE_ANY=15,
		LBC_TYPE_TAGGED_USERDATA_BASE=64,LBC_TYPE_TAGGED_USERDATA_END=64+32,
		LBC_TYPE_OPTIONAL_BIT=bit32.lshift(1,7),LBC_TYPE_INVALID=256,
	},
	CaptureType  = {LCT_VAL=0,LCT_REF=1,LCT_UPVAL=2},
	BuiltinFunction = {
		LBF_NONE=0,LBF_ASSERT=1,LBF_MATH_ABS=2,LBF_MATH_ACOS=3,LBF_MATH_ASIN=4,
		LBF_MATH_ATAN2=5,LBF_MATH_ATAN=6,LBF_MATH_CEIL=7,LBF_MATH_COSH=8,
		LBF_MATH_COS=9,LBF_MATH_DEG=10,LBF_MATH_EXP=11,LBF_MATH_FLOOR=12,
		LBF_MATH_FMOD=13,LBF_MATH_FREXP=14,LBF_MATH_LDEXP=15,LBF_MATH_LOG10=16,
		LBF_MATH_LOG=17,LBF_MATH_MAX=18,LBF_MATH_MIN=19,LBF_MATH_MODF=20,
		LBF_MATH_POW=21,LBF_MATH_RAD=22,LBF_MATH_SINH=23,LBF_MATH_SIN=24,
		LBF_MATH_SQRT=25,LBF_MATH_TANH=26,LBF_MATH_TAN=27,
		LBF_BIT32_ARSHIFT=28,LBF_BIT32_BAND=29,LBF_BIT32_BNOT=30,LBF_BIT32_BOR=31,
		LBF_BIT32_BXOR=32,LBF_BIT32_BTEST=33,LBF_BIT32_EXTRACT=34,
		LBF_BIT32_LROTATE=35,LBF_BIT32_LSHIFT=36,LBF_BIT32_REPLACE=37,
		LBF_BIT32_RROTATE=38,LBF_BIT32_RSHIFT=39,LBF_TYPE=40,
		LBF_STRING_BYTE=41,LBF_STRING_CHAR=42,LBF_STRING_LEN=43,LBF_TYPEOF=44,
		LBF_STRING_SUB=45,LBF_MATH_CLAMP=46,LBF_MATH_SIGN=47,LBF_MATH_ROUND=48,
		LBF_RAWSET=49,LBF_RAWGET=50,LBF_RAWEQUAL=51,LBF_TABLE_INSERT=52,
		LBF_TABLE_UNPACK=53,LBF_VECTOR=54,LBF_BIT32_COUNTLZ=55,LBF_BIT32_COUNTRZ=56,
		LBF_SELECT_VARARG=57,LBF_RAWLEN=58,LBF_BIT32_EXTRACTK=59,
		LBF_GETMETATABLE=60,LBF_SETMETATABLE=61,LBF_TONUMBER=62,LBF_TOSTRING=63,
		LBF_BIT32_BYTESWAP=64,
		LBF_BUFFER_READI8=65,LBF_BUFFER_READU8=66,LBF_BUFFER_WRITEU8=67,
		LBF_BUFFER_READI16=68,LBF_BUFFER_READU16=69,LBF_BUFFER_WRITEU16=70,
		LBF_BUFFER_READI32=71,LBF_BUFFER_READU32=72,LBF_BUFFER_WRITEU32=73,
		LBF_BUFFER_READF32=74,LBF_BUFFER_WRITEF32=75,LBF_BUFFER_READF64=76,
		LBF_BUFFER_WRITEF64=77,
		LBF_VECTOR_MAGNITUDE=78,LBF_VECTOR_NORMALIZE=79,LBF_VECTOR_CROSS=80,
		LBF_VECTOR_DOT=81,LBF_VECTOR_FLOOR=82,LBF_VECTOR_CEIL=83,
		LBF_VECTOR_ABS=84,LBF_VECTOR_SIGN=85,LBF_VECTOR_CLAMP=86,
		LBF_VECTOR_MIN=87,LBF_VECTOR_MAX=88,
	},
	ProtoFlag = {
		LPF_NATIVE_MODULE  = bit32.lshift(1,0),
		LPF_NATIVE_COLD    = bit32.lshift(1,1),
		LPF_NATIVE_FUNCTION= bit32.lshift(1,2),
	},
}
function Luau:INSN_OP(i)  return bit32.band(i,0xFF) end
function Luau:INSN_A(i)   return bit32.band(bit32.rshift(i,8),0xFF) end
function Luau:INSN_B(i)   return bit32.band(bit32.rshift(i,16),0xFF) end
function Luau:INSN_C(i)   return bit32.band(bit32.rshift(i,24),0xFF) end
function Luau:INSN_D(i)   return bit32.rshift(i,16) end
function Luau:INSN_sD(i)
	local D=self:INSN_D(i); return (D>0x7FFF and D<=0xFFFF) and (-(0xFFFF-D)-1) or D
end
function Luau:INSN_E(i)   return bit32.rshift(i,8) end
function Luau:GetBaseTypeString(t, checkOpt)
	local BT=self.BytecodeType
	local tag=bit32.band(t,bit32.bnot(BT.LBC_TYPE_OPTIONAL_BIT))
	local names={[BT.LBC_TYPE_NIL]="nil",[BT.LBC_TYPE_BOOLEAN]="boolean",
		[BT.LBC_TYPE_NUMBER]="number",[BT.LBC_TYPE_STRING]="string",
		[BT.LBC_TYPE_TABLE]="table",[BT.LBC_TYPE_FUNCTION]="function",
		[BT.LBC_TYPE_THREAD]="thread",[BT.LBC_TYPE_USERDATA]="userdata",
		[BT.LBC_TYPE_VECTOR]="Vector3",[BT.LBC_TYPE_BUFFER]="buffer",
		[BT.LBC_TYPE_ANY]="any"}
	local r=names[tag] or "unknown"
	if checkOpt then
		r ..= (bit32.band(t,BT.LBC_TYPE_OPTIONAL_BIT)==0) and "" or "?"
	end
	return r
end
function Luau:GetBuiltinInfo(bfid)
	local BF=self.BuiltinFunction
	local map={
		[BF.LBF_NONE]="none",[BF.LBF_ASSERT]="assert",
		[BF.LBF_TYPE]="type",[BF.LBF_TYPEOF]="typeof",
		[BF.LBF_RAWSET]="rawset",[BF.LBF_RAWGET]="rawget",
		[BF.LBF_RAWEQUAL]="rawequal",[BF.LBF_RAWLEN]="rawlen",
		[BF.LBF_TABLE_UNPACK]="unpack",[BF.LBF_SELECT_VARARG]="select",
		[BF.LBF_GETMETATABLE]="getmetatable",[BF.LBF_SETMETATABLE]="setmetatable",
		[BF.LBF_TONUMBER]="tonumber",[BF.LBF_TOSTRING]="tostring",
		[BF.LBF_MATH_ABS]="math.abs",[BF.LBF_MATH_ACOS]="math.acos",
		[BF.LBF_MATH_ASIN]="math.asin",[BF.LBF_MATH_ATAN2]="math.atan2",
		[BF.LBF_MATH_ATAN]="math.atan",[BF.LBF_MATH_CEIL]="math.ceil",
		[BF.LBF_MATH_COSH]="math.cosh",[BF.LBF_MATH_COS]="math.cos",
		[BF.LBF_MATH_DEG]="math.deg",[BF.LBF_MATH_EXP]="math.exp",
		[BF.LBF_MATH_FLOOR]="math.floor",[BF.LBF_MATH_FMOD]="math.fmod",
		[BF.LBF_MATH_FREXP]="math.frexp",[BF.LBF_MATH_LDEXP]="math.ldexp",
		[BF.LBF_MATH_LOG10]="math.log10",[BF.LBF_MATH_LOG]="math.log",
		[BF.LBF_MATH_MAX]="math.max",[BF.LBF_MATH_MIN]="math.min",
		[BF.LBF_MATH_MODF]="math.modf",[BF.LBF_MATH_POW]="math.pow",
		[BF.LBF_MATH_RAD]="math.rad",[BF.LBF_MATH_SINH]="math.sinh",
		[BF.LBF_MATH_SIN]="math.sin",[BF.LBF_MATH_SQRT]="math.sqrt",
		[BF.LBF_MATH_TANH]="math.tanh",[BF.LBF_MATH_TAN]="math.tan",
		[BF.LBF_MATH_CLAMP]="math.clamp",[BF.LBF_MATH_SIGN]="math.sign",
		[BF.LBF_MATH_ROUND]="math.round",
		[BF.LBF_BIT32_ARSHIFT]="bit32.arshift",[BF.LBF_BIT32_BAND]="bit32.band",
		[BF.LBF_BIT32_BNOT]="bit32.bnot",[BF.LBF_BIT32_BOR]="bit32.bor",
		[BF.LBF_BIT32_BXOR]="bit32.bxor",[BF.LBF_BIT32_BTEST]="bit32.btest",
		[BF.LBF_BIT32_EXTRACT]="bit32.extract",[BF.LBF_BIT32_EXTRACTK]="bit32.extract",
		[BF.LBF_BIT32_LROTATE]="bit32.lrotate",[BF.LBF_BIT32_LSHIFT]="bit32.lshift",
		[BF.LBF_BIT32_REPLACE]="bit32.replace",[BF.LBF_BIT32_RROTATE]="bit32.rrotate",
		[BF.LBF_BIT32_RSHIFT]="bit32.rshift",[BF.LBF_BIT32_COUNTLZ]="bit32.countlz",
		[BF.LBF_BIT32_COUNTRZ]="bit32.countrz",[BF.LBF_BIT32_BYTESWAP]="bit32.byteswap",
		[BF.LBF_STRING_BYTE]="string.byte",[BF.LBF_STRING_CHAR]="string.char",
		[BF.LBF_STRING_LEN]="string.len",[BF.LBF_STRING_SUB]="string.sub",
		[BF.LBF_TABLE_INSERT]="table.insert",[BF.LBF_VECTOR]="Vector3.new",
		[BF.LBF_BUFFER_READI8]="buffer.readi8",[BF.LBF_BUFFER_READU8]="buffer.readu8",
		[BF.LBF_BUFFER_WRITEU8]="buffer.writeu8",[BF.LBF_BUFFER_READI16]="buffer.readi16",
		[BF.LBF_BUFFER_READU16]="buffer.readu16",[BF.LBF_BUFFER_WRITEU16]="buffer.writeu16",
		[BF.LBF_BUFFER_READI32]="buffer.readi32",[BF.LBF_BUFFER_READU32]="buffer.readu32",
		[BF.LBF_BUFFER_WRITEU32]="buffer.writeu32",[BF.LBF_BUFFER_READF32]="buffer.readf32",
		[BF.LBF_BUFFER_WRITEF32]="buffer.writef32",[BF.LBF_BUFFER_READF64]="buffer.readf64",
		[BF.LBF_BUFFER_WRITEF64]="buffer.writef64",
		[BF.LBF_VECTOR_MAGNITUDE]="vector.magnitude",[BF.LBF_VECTOR_NORMALIZE]="vector.normalize",
		[BF.LBF_VECTOR_CROSS]="vector.cross",[BF.LBF_VECTOR_DOT]="vector.dot",
		[BF.LBF_VECTOR_FLOOR]="vector.floor",[BF.LBF_VECTOR_CEIL]="vector.ceil",
		[BF.LBF_VECTOR_ABS]="vector.abs",[BF.LBF_VECTOR_SIGN]="vector.sign",
		[BF.LBF_VECTOR_CLAMP]="vector.clamp",[BF.LBF_VECTOR_MIN]="vector.min",
		[BF.LBF_VECTOR_MAX]="vector.max",
	}
	return map[bfid] or ("builtin#"..tostring(bfid))
end
do
	local raw = Luau.OpCode
	local encoded = {}
	for i, v in raw do
		local case = bit32.band((i-1)*CASE_MULTIPLIER, 0xFF)
		encoded[case] = v
	end
	Luau.OpCode = encoded
end
local DEFAULT_OPTIONS = {
	EnabledRemarks       = {ColdRemark=false, InlineRemark=true},
	DecompilerTimeout    = 10,
	DecompilerMode       = "disasm",
	ReaderFloatPrecision = 7,
	ShowDebugInformation = true,
	ShowInstructionLines = true,
	ShowOperationIndex   = true,
	ShowOperationNames   = true,
	ShowTrivialOperations= false,
	UseTypeInfo          = true,
	ListUsedGlobals      = true,
	ReturnElapsedTime    = false,
}
local LuauCompileUserdataInfo = true
pcall(function()
	local ok, r = pcall(function() return game:GetFastFlag("LuauCompileUserdataInfo") end)
	if ok then LuauCompileUserdataInfo = r end
end)
local LuauOpCode        = Luau.OpCode
local LuauBytecodeTag   = Luau.BytecodeTag
local LuauBytecodeType  = Luau.BytecodeType
local LuauCaptureType   = Luau.CaptureType
local LuauProtoFlag     = Luau.ProtoFlag
local function toBoolean(v)      return v ~= 0 end
local function toEscapedString(v)
	if type(v) == "string" then
		return string.format("%q", v)
	end
	return tostring(v)
end
local function formatIndexString(key)
	if type(key) == "string" and key:match("^[%a_][%w_]*$") then
		return "." .. key
	end
	return "[" .. toEscapedString(key) .. "]"
end
local function padLeft(v, ch, n)
	local s = tostring(v); return string.rep(ch, math.max(0, n-#s)) .. s
end
local function padRight(v, ch, n)
	local s = tostring(v); return s .. string.rep(ch, math.max(0, n-#s))
end
local ROBLOX_GLOBALS = {
	"game","workspace","script","plugin","settings","shared","UserSettings",
	"print","warn","error","assert","pcall","xpcall","require","select",
	"pairs","ipairs","next","unpack","type","typeof","tostring","tonumber",
	"setmetatable","getmetatable","rawset","rawget","rawequal","rawlen",
	"math","table","string","bit32","coroutine","os","utf8","task","buffer",
	"Instance","Enum","Vector3","Vector2","CFrame","Color3","BrickColor",
	"UDim","UDim2","Ray","Axes","Faces","NumberRange","NumberSequence",
	"ColorSequence","TweenInfo","RaycastParams","OverlapParams",
	"tick","time","wait","delay","spawn","_G","_VERSION",
}
local function isGlobal(key)
	for _, v in ipairs(ROBLOX_GLOBALS) do if v == key then return true end end
	return false
end
local function Decompile(bytecode, options)
	local bytecodeVersion, typeEncodingVersion
	Reader:Set(options.ReaderFloatPrecision)
	local reader = Reader.new(bytecode)
	local function disassemble()
		if bytecodeVersion >= 4 then
			typeEncodingVersion = reader:nextByte()
		end
		local stringTable = {}
		local function readStringTable()
			local n = reader:nextVarInt()
			for i = 1, n do stringTable[i] = reader:nextString() end
		end
		local userdataTypes = {}
		local function readUserdataTypes()
			if LuauCompileUserdataInfo then
				while true do
					local idx = reader:nextByte()
					if idx == 0 then break end
					userdataTypes[idx] = reader:nextVarInt()
				end
			end
		end
		local protoTable = {}
		local function readProtoTable()
			local n = reader:nextVarInt()
			for i = 1, n do
				local protoId = i - 1
				local proto = {
					id=protoId, instructions={}, constants={},
					captures={}, innerProtos={}, instructionLineInfo={},
				}
				protoTable[protoId] = proto
				proto.maxStackSize  = reader:nextByte()
				proto.numParams     = reader:nextByte()
				proto.numUpvalues   = reader:nextByte()
				proto.isVarArg      = toBoolean(reader:nextByte())
				if bytecodeVersion >= 4 then
					proto.flags = reader:nextByte()
					local resultTypedParams, resultTypedUpvalues, resultTypedLocals = {}, {}, {}
					local allTypeInfoSize = reader:nextVarInt()
					local hasTypeInfo = allTypeInfoSize > 0
					proto.hasTypeInfo = hasTypeInfo
					if hasTypeInfo then
						local totalTypedParams   = allTypeInfoSize
						local totalTypedUpvalues = 0
						local totalTypedLocals   = 0
						if typeEncodingVersion and typeEncodingVersion > 1 then
							totalTypedParams   = reader:nextVarInt()
							totalTypedUpvalues = reader:nextVarInt()
							totalTypedLocals   = reader:nextVarInt()
						end
						if totalTypedParams > 0 then
							resultTypedParams = reader:nextBytes(totalTypedParams)
							table.remove(resultTypedParams, 1)
							table.remove(resultTypedParams, 1)
						end
						for j = 1, totalTypedUpvalues do
							resultTypedUpvalues[j] = {type=reader:nextByte()}
						end
						for j = 1, totalTypedLocals do
							local lt  = reader:nextByte()
							local lr  = reader:nextByte()
							local lsp = reader:nextVarInt() + 1
							local lep = reader:nextVarInt() + lsp - 1
							resultTypedLocals[j] = {type=lt, register=lr, startPC=lsp}
						end
					end
					proto.typedParams   = resultTypedParams
					proto.typedUpvalues = resultTypedUpvalues
					proto.typedLocals   = resultTypedLocals
				end
				proto.sizeInstructions = reader:nextVarInt()
				for j = 1, proto.sizeInstructions do
					proto.instructions[j] = reader:nextUInt32()
				end
				proto.sizeConstants = reader:nextVarInt()
				for j = 1, proto.sizeConstants do
					local constType  = reader:nextByte()
					local constValue
					local BT = LuauBytecodeTag
					if constType == BT.LBC_CONSTANT_BOOLEAN then
						constValue = toBoolean(reader:nextByte())
					elseif constType == BT.LBC_CONSTANT_NUMBER then
						constValue = reader:nextDouble()
					elseif constType == BT.LBC_CONSTANT_STRING then
						constValue = stringTable[reader:nextVarInt()]
					elseif constType == BT.LBC_CONSTANT_IMPORT then
						local id = reader:nextUInt32()
						local idxCount = bit32.rshift(id, 30)
						local ci1 = bit32.band(bit32.rshift(id,20), 0x3FF)
						local ci2 = bit32.band(bit32.rshift(id,10), 0x3FF)
						local ci3 = bit32.band(id, 0x3FF)
						local tag = ""
						local function kv(idx) return proto.constants[idx+1] end
						if     idxCount == 1 then tag = tostring(kv(ci1) and kv(ci1).value or "")
						elseif idxCount == 2 then tag = tostring(kv(ci1) and kv(ci1).value or "")
							.."."..tostring(kv(ci2) and kv(ci2).value or "")
						elseif idxCount == 3 then tag = tostring(kv(ci1) and kv(ci1).value or "")
							.."."..tostring(kv(ci2) and kv(ci2).value or "")
							.."."..tostring(kv(ci3) and kv(ci3).value or "")
						end
						constValue = tag
					elseif constType == BT.LBC_CONSTANT_TABLE then
						local sz = reader:nextVarInt()
						local keys = {}
						for k = 1, sz do keys[k] = reader:nextVarInt()+1 end
						constValue = {size=sz, keys=keys}
					elseif constType == BT.LBC_CONSTANT_CLOSURE then
						constValue = reader:nextVarInt() + 1
					elseif constType == BT.LBC_CONSTANT_VECTOR then
						local x,y,z,w = reader:nextFloat(),reader:nextFloat(),reader:nextFloat(),reader:nextFloat()
						constValue = w == 0 and ("Vector3.new("..x..","..y..","..z..")")
							or ("vector.create("..x..","..y..","..z..","..w..")")
					end
					proto.constants[j] = {type=constType, value=constValue}
				end
				proto.sizeInnerProtos = reader:nextVarInt()
				for j = 1, proto.sizeInnerProtos do
					proto.innerProtos[j] = protoTable[reader:nextVarInt()]
				end
				proto.lineDefined = reader:nextVarInt()
				local nameId = reader:nextVarInt()
				proto.name = stringTable[nameId]
				local hasLineInfo = toBoolean(reader:nextByte())
				proto.hasLineInfo = hasLineInfo
				if hasLineInfo then
					local lgap = reader:nextByte()
					local baselineSize = bit32.rshift(proto.sizeInstructions-1, lgap)+1
					local smallLineInfo, absLineInfo = {}, {}
					local lastOffset, lastLine = 0, 0
					for j = 1, proto.sizeInstructions do
						local b = reader:nextSignedByte()
						lastOffset += b
						smallLineInfo[j] = lastOffset
					end
					for j = 1, baselineSize do
						local lc = lastLine + reader:nextInt32()
						absLineInfo[j-1] = lc
						lastLine = lc
					end
					local resultLineInfo = {}
					for j, line in ipairs(smallLineInfo) do
						local absIdx = bit32.rshift(j-1, lgap)
						local absLine = absLineInfo[absIdx]
						local rl = line + absLine
						if lgap <= 1 and (-line == absLine) then
							rl += absLineInfo[absIdx+1] or 0
						end
						if rl <= 0 then rl += 0x100 end
						resultLineInfo[j] = rl
					end
					proto.lineInfoSize = lgap
					proto.instructionLineInfo = resultLineInfo
				end
				local hasDebugInfo = toBoolean(reader:nextByte())
				proto.hasDebugInfo = hasDebugInfo
				if hasDebugInfo then
					local totalLocals = reader:nextVarInt()
					local debugLocals = {}
					for j = 1, totalLocals do
						debugLocals[j] = {
							name     = stringTable[reader:nextVarInt()],
							startPC  = reader:nextVarInt(),
							endPC    = reader:nextVarInt(),
							register = reader:nextByte(),
						}
					end
					proto.debugLocals = debugLocals
					local totalUpvals = reader:nextVarInt()
					local debugUpvalues = {}
					for j = 1, totalUpvals do
						debugUpvalues[j] = {name=stringTable[reader:nextVarInt()]}
					end
					proto.debugUpvalues = debugUpvalues
				end
			end
		end
		readStringTable()
		if bytecodeVersion and bytecodeVersion > 5 then readUserdataTypes() end
		readProtoTable()
		local mainProtoId = reader:nextVarInt()
		return mainProtoId, protoTable
	end
	local function organize()
		local mainProtoId, protoTable = disassemble()
		local mainProto = protoTable[mainProtoId]
		mainProto.main = true
		local registerActions = {}
		local function baseProto(proto)
			local protoRegisterActions = {}
			registerActions[proto.id] = {proto=proto, actions=protoRegisterActions}
			local instructions = proto.instructions
			local innerProtos  = proto.innerProtos
			local constants    = proto.constants
			local captures     = proto.captures
			local flags        = proto.flags
			local function collectCaptures(baseIdx, p)
				local nup = p.numUpvalues
				if nup > 0 then
					local _c = p.captures
					for j = 1, nup do
						local cap = instructions[baseIdx + j]
						local ctype = Luau:INSN_A(cap)
						local sreg  = Luau:INSN_B(cap)
						if ctype == LuauCaptureType.LCT_VAL or ctype == LuauCaptureType.LCT_REF then
							_c[j-1] = sreg
						elseif ctype == LuauCaptureType.LCT_UPVAL then
							_c[j-1] = captures[sreg]
						end
					end
				end
			end
			local function writeFlags()
				local df = {}
				if proto.main then
					df.native = toBoolean(bit32.band(flags or 0, LuauProtoFlag.LPF_NATIVE_MODULE))
				else
					df.native = toBoolean(bit32.band(flags or 0, LuauProtoFlag.LPF_NATIVE_FUNCTION))
					df.cold   = toBoolean(bit32.band(flags or 0, LuauProtoFlag.LPF_NATIVE_COLD))
				end
				flags = df; proto.flags = df
			end
			local function writeInstructions()
				local auxSkip = false
				local function reg(act, regs, extra, hide)
					table.insert(protoRegisterActions, {
						usedRegisters=regs or {}, extraData=extra,
						opCode=act, hide=hide
					})
				end
				for idx, instruction in ipairs(instructions) do
					if auxSkip then auxSkip=false; continue end
					local oci = LuauOpCode[Luau:INSN_OP(instruction)]
					if not oci then continue end
					local opn  = oci.name
					local opt  = oci.type
					local isAux= oci.aux == true
					local A,B,C,sD,D,E,aux
					if     opt=="A"   then A=Luau:INSN_A(instruction)
					elseif opt=="E"   then E=Luau:INSN_E(instruction)
					elseif opt=="AB"  then A=Luau:INSN_A(instruction); B=Luau:INSN_B(instruction)
					elseif opt=="AC"  then A=Luau:INSN_A(instruction); C=Luau:INSN_C(instruction)
					elseif opt=="ABC" then A=Luau:INSN_A(instruction); B=Luau:INSN_B(instruction); C=Luau:INSN_C(instruction)
					elseif opt=="AD"  then A=Luau:INSN_A(instruction); D=Luau:INSN_D(instruction)
					elseif opt=="AsD" then A=Luau:INSN_A(instruction); sD=Luau:INSN_sD(instruction)
					elseif opt=="sD"  then sD=Luau:INSN_sD(instruction)
					end
					if isAux then
						auxSkip=true; reg(oci,nil,nil,true)
						aux=instructions[idx+1]
					end
					local st = not options.ShowTrivialOperations
					if opn=="NOP" or opn=="BREAK" or opn=="NATIVECALL" then reg(oci,nil,nil,st)
					elseif opn=="LOADNIL" then reg(oci,{A})
					elseif opn=="LOADB"   then reg(oci,{A},{B,C})
					elseif opn=="LOADN"   then reg(oci,{A},{sD})
					elseif opn=="LOADK"   then reg(oci,{A},{D})
					elseif opn=="MOVE"    then reg(oci,{A,B})
					elseif opn=="GETGLOBAL" or opn=="SETGLOBAL" then reg(oci,{A},{aux})
					elseif opn=="GETUPVAL" or opn=="SETUPVAL"  then reg(oci,{A},{B})
					elseif opn=="CLOSEUPVALS" then reg(oci,{A},nil,st)
					elseif opn=="GETIMPORT" then reg(oci,{A},{D,aux})
					elseif opn=="GETTABLE" or opn=="SETTABLE" then reg(oci,{A,B,C})
					elseif opn=="GETTABLEKS" or opn=="SETTABLEKS" then reg(oci,{A,B},{C,aux})
					elseif opn=="GETTABLEN" or opn=="SETTABLEN" then reg(oci,{A,B},{C})
					elseif opn=="NEWCLOSURE" then
						reg(oci,{A},{D})
						local p2=innerProtos[D+1]
						if p2 then collectCaptures(idx,p2); baseProto(p2) end
					elseif opn=="DUPCLOSURE" then
						reg(oci,{A},{D})
						local c=constants[D+1]
						if c then local p2=protoTable[c.value-1]; if p2 then collectCaptures(idx,p2); baseProto(p2) end end
					elseif opn=="NAMECALL"  then reg(oci,{A,B},{C,aux},st)
					elseif opn=="CALL"      then reg(oci,{A},{B,C})
					elseif opn=="RETURN"    then reg(oci,{A},{B})
					elseif opn=="JUMP" or opn=="JUMPBACK" then reg(oci,{},{sD})
					elseif opn=="JUMPIF" or opn=="JUMPIFNOT" then reg(oci,{A},{sD})
					elseif opn=="JUMPIFEQ" or opn=="JUMPIFLE" or opn=="JUMPIFLT"
					    or opn=="JUMPIFNOTEQ" or opn=="JUMPIFNOTLE" or opn=="JUMPIFNOTLT" then
						reg(oci,{A,aux},{sD})
					elseif opn=="ADD" or opn=="SUB" or opn=="MUL" or opn=="DIV"
					    or opn=="MOD" or opn=="POW" then reg(oci,{A,B,C})
					elseif opn=="ADDK" or opn=="SUBK" or opn=="MULK" or opn=="DIVK"
					    or opn=="MODK" or opn=="POWK" then reg(oci,{A,B},{C})
					elseif opn=="AND" or opn=="OR" then reg(oci,{A,B,C})
					elseif opn=="ANDK" or opn=="ORK" then reg(oci,{A,B},{C})
					elseif opn=="CONCAT" then
						local regs={A}
						for r=B,C do table.insert(regs,r) end
						reg(oci,regs)
					elseif opn=="NOT" or opn=="MINUS" or opn=="LENGTH" then reg(oci,{A,B})
					elseif opn=="NEWTABLE" then reg(oci,{A},{B,aux})
					elseif opn=="DUPTABLE" then reg(oci,{A},{D})
					elseif opn=="SETLIST"  then
						if C~=0 then
							local regs={A,B}
							for k=1,C-2 do table.insert(regs,A+k) end
							reg(oci,regs,{aux,C})
						else reg(oci,{A,B},{aux,C}) end
					elseif opn=="FORNPREP" then reg(oci,{A,A+1,A+2},{sD})
					elseif opn=="FORNLOOP" then reg(oci,{A},{sD})
					elseif opn=="FORGLOOP" then
						local nv=bit32.band(aux or 0,0xFF)
						local regs={}
						for k=1,nv do table.insert(regs,A+k) end
						reg(oci,regs,{sD,aux})
					elseif opn=="FORGPREP_INEXT" or opn=="FORGPREP_NEXT" then reg(oci,{A,A+1})
					elseif opn=="FORGPREP"  then reg(oci,{A},{sD})
					elseif opn=="GETVARARGS" then
						if B~=0 then
							local regs={A}
							for k=0,B-1 do table.insert(regs,A+k) end
							reg(oci,regs,{B})
						else reg(oci,{A},{B}) end
					elseif opn=="PREPVARARGS" then reg(oci,{},{A},st)
					elseif opn=="LOADKX"  then reg(oci,{A},{aux})
					elseif opn=="JUMPX"   then reg(oci,{},{E})
					elseif opn=="COVERAGE" then reg(oci,{},{E},st)
					elseif opn=="JUMPXEQKNIL" or opn=="JUMPXEQKB"
					    or opn=="JUMPXEQKN"   or opn=="JUMPXEQKS" then
						reg(oci,{A},{sD,aux})
					elseif opn=="CAPTURE" then reg(oci,nil,nil,st)
					elseif opn=="SUBRK" or opn=="DIVRK" then reg(oci,{A,C},{B})
					elseif opn=="IDIV"  then reg(oci,{A,B,C})
					elseif opn=="IDIVK" then reg(oci,{A,B},{C})
					elseif opn=="FASTCALL"  then reg(oci,{},{A,C},st)
					elseif opn=="FASTCALL1" then reg(oci,{B},{A,C},st)
					elseif opn=="FASTCALL2" then
						local r2=bit32.band(aux or 0,0xFF)
						reg(oci,{B,r2},{A,C},st)
					elseif opn=="FASTCALL2K" then reg(oci,{B},{A,C,aux},st)
					elseif opn=="FASTCALL3" then
						local r2=bit32.band(aux or 0,0xFF)
						local r3=bit32.rshift(r2,8)
						reg(oci,{B,r2,r3},{A,C},st)
					end
				end
			end
			writeFlags()
			writeInstructions()
		end
		baseProto(mainProto)
		return mainProtoId, registerActions, protoTable
	end
	local function finalize(mainProtoId, registerActions, protoTable)
		local finalResult = ""
		local totalParameters = 0
		local usedGlobals = {}
		local function isValidGlobal(key)
			for _, v in ipairs(usedGlobals) do if v==key then return false end end
			return not isGlobal(key)
		end
		local function processResult(res)
			local embed = ""
			if options.ListUsedGlobals and #usedGlobals > 0 then
				embed = string.format(Strings.USED_GLOBALS, table.concat(usedGlobals, ", "))
			end
			return embed .. res
		end
		if options.DecompilerMode == "disasm" then
			local result = ""
			local function writeActions(protoActions)
				local actions  = protoActions.actions
				local proto    = protoActions.proto
				local lineInfo = proto.instructionLineInfo
				local inner    = proto.innerProtos
				local consts   = proto.constants
				local caps     = proto.captures
				local pflags   = proto.flags
				local numParams= proto.numParams
				local jumpMarkers = {}
				local function makeJump(idx) idx-=1; jumpMarkers[idx]=(jumpMarkers[idx] or 0)+1 end
				totalParameters += numParams
				if proto.main and pflags and pflags.native then result ..= "--!native\n" end
				local function fmtReg(r)
					local pr = r+1
					if pr < numParams+1 then
						return "p"..((totalParameters-numParams)+pr)
					end
					return "v"..(r-numParams)
				end
				local function fmtUpv(r) return "u_v"..r end
				local function fmtConst(k)
					if not k then return "nil" end
					if k.type == LuauBytecodeTag.LBC_CONSTANT_VECTOR then
						return tostring(k.value)
					end
					if type(tonumber(k.value))=="number" then
						return tostring(tonumber(string.format("%0."..options.ReaderFloatPrecision.."f", k.value)))
					end
					return toEscapedString(k.value)
				end
				local function fmtProto(p)
					local body=""
					if p.flags and p.flags.native then
						if p.flags.cold and options.EnabledRemarks.ColdRemark then
							body ..= string.format(Strings.DECOMPILER_REMARK,
								"This function is marked cold and is not compiled natively")
						end
						body ..= "@native "
					end
					if p.name then body="local function "..p.name
					else body="function" end
					body ..= "("
					for j=1,p.numParams do
						local pb="p"..(totalParameters+j)
						if p.hasTypeInfo and options.UseTypeInfo and p.typedParams and p.typedParams[j] then
							pb ..= ": "..Luau:GetBaseTypeString(p.typedParams[j],true)
						end
						if j~=p.numParams then pb ..= ", " end
						body ..= pb
					end
					if p.isVarArg then
						body ..= (p.numParams>0) and ", ..." or "..."
					end
					body ..= ")\n"
					if options.ShowDebugInformation then
						body ..= "-- proto pool id: "..p.id.."\n"
						body ..= "-- num upvalues: "..p.numUpvalues.."\n"
						body ..= "-- num inner protos: "..(p.sizeInnerProtos or 0).."\n"
						body ..= "-- size instructions: "..(p.sizeInstructions or 0).."\n"
						body ..= "-- size constants: "..(p.sizeConstants or 0).."\n"
						body ..= "-- lineinfo gap: "..(p.lineInfoSize or "n/a").."\n"
						body ..= "-- max stack size: "..p.maxStackSize.."\n"
						body ..= "-- is typed: "..tostring(p.hasTypeInfo).."\n"
					end
					return body
				end
				local function writeProto(reg, p)
					local body=fmtProto(p)
					if p.name then
						result ..= "\n"..body
						writeActions(registerActions[p.id])
						result ..= "end\n"..fmtReg(reg).." = "..p.name
					else
						result ..= fmtReg(reg).." = "..body
						writeActions(registerActions[p.id])
						result ..= "end"
					end
				end
				for i, action in ipairs(actions) do
					if action.hide then continue end
					local ur  = action.usedRegisters
					local ed  = action.extraData
					local oci = action.opCode
					if not oci then continue end
					local opn = oci.name
					local function handleJumps()
						local n = jumpMarkers[i]
						if n then
							jumpMarkers[i]=nil
							for _=1,n do result ..= "end\n" end
						end
					end
					if options.ShowOperationIndex then
						result ..= "["..padLeft(i,"0",3).."] "
					end
					if options.ShowInstructionLines and lineInfo and lineInfo[i] then
						result ..= ":"..padLeft(lineInfo[i],"0",3)..":"
					end
					if options.ShowOperationNames then
						result ..= padRight(opn," ",15)
					end
					if opn=="LOADNIL" then result ..= fmtReg(ur[1]).." = nil"
					elseif opn=="LOADB" then
						result ..= fmtReg(ur[1]).." = "..toEscapedString(toBoolean(ed[1]))
						if ed[2]~=0 then result ..= " +"..ed[2] end
					elseif opn=="LOADN" then result ..= fmtReg(ur[1]).." = "..ed[1]
					elseif opn=="LOADK" then result ..= fmtReg(ur[1]).." = "..fmtConst(consts[ed[1]+1])
					elseif opn=="MOVE"  then result ..= fmtReg(ur[1]).." = "..fmtReg(ur[2])
					elseif opn=="GETGLOBAL" then
						local gk=tostring(consts[ed[1]+1] and consts[ed[1]+1].value or "")
						if options.ListUsedGlobals and isValidGlobal(gk) then
							table.insert(usedGlobals,gk)
						end
						result ..= fmtReg(ur[1]).." = "..gk
					elseif opn=="SETGLOBAL" then
						local gk=tostring(consts[ed[1]+1] and consts[ed[1]+1].value or "")
						if options.ListUsedGlobals and isValidGlobal(gk) then
							table.insert(usedGlobals,gk)
						end
						result ..= gk.." = "..fmtReg(ur[1])
					elseif opn=="GETUPVAL" then result ..= fmtReg(ur[1]).." = "..fmtUpv(caps[ed[1]])
					elseif opn=="SETUPVAL" then result ..= fmtUpv(caps[ed[1]]).." = "..fmtReg(ur[1])
					elseif opn=="CLOSEUPVALS" then result ..= "-- clear captures from back until: "..ur[1]
					elseif opn=="GETIMPORT" then
						local imp=tostring(consts[ed[1]+1] and consts[ed[1]+1].value or "")
						local totalIdx = bit32.rshift(ed[2] or 0, 30)
						if totalIdx==1 and options.ListUsedGlobals and isValidGlobal(imp) then
							table.insert(usedGlobals,imp)
						end
						result ..= fmtReg(ur[1]).." = "..imp
					elseif opn=="GETTABLE" then
						result ..= fmtReg(ur[1]).." = "..fmtReg(ur[2]).."["..fmtReg(ur[3]).."]"
					elseif opn=="SETTABLE" then
						result ..= fmtReg(ur[2]).."["..fmtReg(ur[3]).."] = "..fmtReg(ur[1])
					elseif opn=="GETTABLEKS" then
						local key = consts[ed[2]+1] and consts[ed[2]+1].value
						result ..= fmtReg(ur[1]).." = "..fmtReg(ur[2])..formatIndexString(key)
					elseif opn=="SETTABLEKS" then
						local key = consts[ed[2]+1] and consts[ed[2]+1].value
						result ..= fmtReg(ur[2])..formatIndexString(key).." = "..fmtReg(ur[1])
					elseif opn=="GETTABLEN" then
						result ..= fmtReg(ur[1]).." = "..fmtReg(ur[2]).."["..(ed[1]+1).."]"
					elseif opn=="SETTABLEN" then
						result ..= fmtReg(ur[2]).."["..(ed[1]+1).."] = "..fmtReg(ur[1])
					elseif opn=="NEWCLOSURE" then
						local p2=inner[ed[1]+1]; if p2 then writeProto(ur[1],p2) end
					elseif opn=="DUPCLOSURE" then
						local c=consts[ed[1]+1]
						if c then
							local p2=protoTable[c.value-1]; if p2 then writeProto(ur[1],p2) end
						end
					elseif opn=="NAMECALL" then
						local method=tostring(consts[ed[2]+1] and consts[ed[2]+1].value or "")
						result ..= "-- :"..method
					elseif opn=="CALL" then
						local baseR=ur[1]
						local nArgs=ed[1]-1; local nRes=ed[2]-1
						local nmMethod=""; local argOff=0
						local prev=actions[i-1]
						if prev and prev.opCode and prev.opCode.name=="NAMECALL" then
							nmMethod=":"..tostring(consts[prev.extraData[2]+1] and consts[prev.extraData[2]+1].value or "")
							nArgs-=1; argOff+=1
						end
						local callBody=""
						if nRes==-1 then callBody="... = "
						elseif nRes>0 then
							local rb=""
							for k=1,nRes do
								rb..=fmtReg(baseR+k-1)
								if k~=nRes then rb..=", " end
							end
							callBody=rb.." = "
						end
						callBody ..= fmtReg(baseR)..nmMethod.."("
						if nArgs==-1 then callBody..="..."
						elseif nArgs>0 then
							local ab=""
							for k=1,nArgs do
								ab..=fmtReg(baseR+k+argOff)
								if k~=nArgs then ab..=", " end
							end
							callBody..=ab
						end
						callBody..=")"
						result..=callBody
					elseif opn=="RETURN" then
						local baseR=ur[1]; local tot=ed[1]-2
						local rb=""
						if tot==-2 then rb=" "..fmtReg(baseR)..", ..."
						elseif tot>-1 then
							rb=" "
							for k=0,tot do
								rb..=fmtReg(baseR+k)
								if k~=tot then rb..=", " end
							end
						end
						result..="return"..rb
					elseif opn=="JUMP" then result..="-- jump to #"..(i+ed[1])
					elseif opn=="JUMPBACK" then result..="-- jump back to #"..(i+ed[1]+1)
					elseif opn=="JUMPIF" then
						local ei=i+ed[1]; makeJump(ei)
						result..="if not "..fmtReg(ur[1]).." then -- goto #"..ei
					elseif opn=="JUMPIFNOT" then
						local ei=i+ed[1]; makeJump(ei)
						result..="if "..fmtReg(ur[1]).." then -- goto #"..ei
					elseif opn=="JUMPIFEQ" then
						local ei=i+ed[1]; makeJump(ei)
						result..="if "..fmtReg(ur[1]).." == "..fmtReg(ur[2]).." then -- goto #"..ei
					elseif opn=="JUMPIFLE" then
						local ei=i+ed[1]; makeJump(ei)
						result..="if "..fmtReg(ur[1]).." >= "..fmtReg(ur[2]).." then -- goto #"..ei
					elseif opn=="JUMPIFLT" then
						local ei=i+ed[1]; makeJump(ei)
						result..="if "..fmtReg(ur[1]).." > "..fmtReg(ur[2]).." then -- goto #"..ei
					elseif opn=="JUMPIFNOTEQ" then
						local ei=i+ed[1]; makeJump(ei)
						result..="if "..fmtReg(ur[1]).." ~= "..fmtReg(ur[2]).." then -- goto #"..ei
					elseif opn=="JUMPIFNOTLE" then
						local ei=i+ed[1]; makeJump(ei)
						result..="if "..fmtReg(ur[1]).." <= "..fmtReg(ur[2]).." then -- goto #"..ei
					elseif opn=="JUMPIFNOTLT" then
						local ei=i+ed[1]; makeJump(ei)
						result..="if "..fmtReg(ur[1]).." < "..fmtReg(ur[2]).." then -- goto #"..ei
					elseif opn=="ADD"  then result..=fmtReg(ur[1]).." = "..fmtReg(ur[2]).." + "..fmtReg(ur[3])
					elseif opn=="SUB"  then result..=fmtReg(ur[1]).." = "..fmtReg(ur[2]).." - "..fmtReg(ur[3])
					elseif opn=="MUL"  then result..=fmtReg(ur[1]).." = "..fmtReg(ur[2]).." * "..fmtReg(ur[3])
					elseif opn=="DIV"  then result..=fmtReg(ur[1]).." = "..fmtReg(ur[2]).." / "..fmtReg(ur[3])
					elseif opn=="MOD"  then result..=fmtReg(ur[1]).." = "..fmtReg(ur[2]).." % "..fmtReg(ur[3])
					elseif opn=="POW"  then result..=fmtReg(ur[1]).." = "..fmtReg(ur[2]).." ^ "..fmtReg(ur[3])
					elseif opn=="ADDK" then result..=fmtReg(ur[1]).." = "..fmtReg(ur[2]).." + "..fmtConst(consts[ed[1]+1])
					elseif opn=="SUBK" then result..=fmtReg(ur[1]).." = "..fmtReg(ur[2]).." - "..fmtConst(consts[ed[1]+1])
					elseif opn=="MULK" then result..=fmtReg(ur[1]).." = "..fmtReg(ur[2]).." * "..fmtConst(consts[ed[1]+1])
					elseif opn=="DIVK" then result..=fmtReg(ur[1]).." = "..fmtReg(ur[2]).." / "..fmtConst(consts[ed[1]+1])
					elseif opn=="MODK" then result..=fmtReg(ur[1]).." = "..fmtReg(ur[2]).." % "..fmtConst(consts[ed[1]+1])
					elseif opn=="POWK" then result..=fmtReg(ur[1]).." = "..fmtReg(ur[2]).." ^ "..fmtConst(consts[ed[1]+1])
					elseif opn=="AND"  then result..=fmtReg(ur[1]).." = "..fmtReg(ur[2]).." and "..fmtReg(ur[3])
					elseif opn=="OR"   then result..=fmtReg(ur[1]).." = "..fmtReg(ur[2]).." or "..fmtReg(ur[3])
					elseif opn=="ANDK" then result..=fmtReg(ur[1]).." = "..fmtReg(ur[2]).." and "..fmtConst(consts[ed[1]+1])
					elseif opn=="ORK"  then result..=fmtReg(ur[1]).." = "..fmtReg(ur[2]).." or "..fmtConst(consts[ed[1]+1])
					elseif opn=="CONCAT" then
						local tgt=table.remove(ur,1)
						local cb=""
						for k,r in ipairs(ur) do
							cb..=fmtReg(r); if k~=#ur then cb..=" .. " end
						end
						result..=fmtReg(tgt).." = "..cb
					elseif opn=="NOT"    then result..=fmtReg(ur[1]).." = not "..fmtReg(ur[2])
					elseif opn=="MINUS"  then result..=fmtReg(ur[1]).." = -"..fmtReg(ur[2])
					elseif opn=="LENGTH" then result..=fmtReg(ur[1]).." = #"..fmtReg(ur[2])
					elseif opn=="NEWTABLE" then
						result..=fmtReg(ur[1]).." = {}"
						if options.ShowDebugInformation and ed[2] and ed[2]>0 then
							result..=" "
						end
					elseif opn=="DUPTABLE" then
						local cv=consts[ed[1]+1]
						if cv and type(cv.value)=="table" then
							local tb="{"
							for k=1,cv.value.size do
								tb..=fmtConst(consts[cv.value.keys[k]])
								if k~=cv.value.size then tb..=", " end
							end
							result..=fmtReg(ur[1]).." = {} -- "..tb.."}"
						else result..=fmtReg(ur[1]).." = {}" end
					elseif opn=="SETLIST" then
						local tgt=ur[1]; local src=ur[2]
						local si=ed[1]; local vc=ed[2]
						if vc==0 then
							result..=fmtReg(tgt).."["..si.."] = [...]"
						else
							local tot2=#ur-1; local cb=""
							for k=1,tot2 do
								cb..=fmtReg(ur[k]).."["..(si+k-1).."] = "..fmtReg(src+k-1)
								if k~=tot2 then cb..="\n" end
							end
							result..=cb
						end
					elseif opn=="FORNPREP" then
						result..="for "..fmtReg(ur[3]).." = "..fmtReg(ur[3])..", "
							..fmtReg(ur[1])..", "..fmtReg(ur[2]).." do -- end at #"..(i+ed[1])
					elseif opn=="FORNLOOP" then
						result..="end -- iterate + jump to #"..(i+ed[1])
					elseif opn=="FORGLOOP" then
						result..="end -- iterate + jump to #"..(i+ed[1])
					elseif opn=="FORGPREP_INEXT" then
						local tr=ur[1]+1
						result..="for "..fmtReg(tr+2)..", "..fmtReg(tr+3).." in ipairs("..fmtReg(tr)..") do"
					elseif opn=="FORGPREP_NEXT" then
						local tr=ur[1]+1
						result..="for "..fmtReg(tr+2)..", "..fmtReg(tr+3).." in pairs("..fmtReg(tr)..") do"
					elseif opn=="FORGPREP" then
						local ei=i+ed[1]+2
						local ea=actions[ei]
						local vb=""
						if ea then
							for k,r in ipairs(ea.usedRegisters) do
								vb..=fmtReg(r); if k~=#ea.usedRegisters then vb..=", " end
							end
						end
						result..="for "..vb.." in "..fmtReg(ur[1]).." do -- end at #"..ei
					elseif opn=="GETVARARGS" then
						local vc2=ed[1]-1
						local rb=""
						if vc2==-1 then rb=fmtReg(ur[1])
						else
							for k=1,vc2 do
								rb..=fmtReg(ur[k]); if k~=vc2 then rb..=", " end
							end
						end
						result..=rb.." = ..."
					elseif opn=="PREPVARARGS" then result..="-- ... ; number of fixed args: "..ed[1]
					elseif opn=="LOADKX" then result..=fmtReg(ur[1]).." = "..fmtConst(consts[ed[1]+1])
					elseif opn=="JUMPX"    then result..="-- jump to #"..(i+ed[1])
					elseif opn=="COVERAGE" then result..="-- coverage ("..ed[1]..")"
					elseif opn=="JUMPXEQKNIL" then
						local rev=bit32.rshift(ed[2] or 0,0x1F)~=1
						local sign=rev and "~=" or "=="
						local ei=i+ed[1]; makeJump(ei)
						result..="if "..fmtReg(ur[1]).." "..sign.." nil then -- goto #"..ei
					elseif opn=="JUMPXEQKB" then
						local val=tostring(toBoolean(bit32.band(ed[2] or 0,1)))
						local rev=bit32.rshift(ed[2] or 0,0x1F)~=1
						local sign=rev and "~=" or "=="
						local ei=i+ed[1]; makeJump(ei)
						result..="if "..fmtReg(ur[1]).." "..sign.." "..val.." then -- goto #"..ei
					elseif opn=="JUMPXEQKN" or opn=="JUMPXEQKS" then
						local cidx=bit32.band(ed[2] or 0,0xFFFFFF)
						local val=fmtConst(consts[cidx+1])
						local rev=bit32.rshift(ed[2] or 0,0x1F)~=1
						local sign=rev and "~=" or "=="
						local ei=i+ed[1]; makeJump(ei)
						result..="if "..fmtReg(ur[1]).." "..sign.." "..val.." then -- goto #"..ei
					elseif opn=="CAPTURE"  then result..="-- upvalue capture"
					elseif opn=="SUBRK"    then result..=fmtReg(ur[1]).." = "..fmtConst(consts[ed[1]+1]).." - "..fmtReg(ur[2])
					elseif opn=="DIVRK"    then result..=fmtReg(ur[1]).." = "..fmtConst(consts[ed[1]+1]).." / "..fmtReg(ur[2])
					elseif opn=="IDIV"     then result..=fmtReg(ur[1]).." = "..fmtReg(ur[2]).." // "..fmtReg(ur[3])
					elseif opn=="IDIVK"    then result..=fmtReg(ur[1]).." = "..fmtReg(ur[2]).." // "..fmtConst(consts[ed[1]+1])
					elseif opn=="FASTCALL" then result..="-- FASTCALL; "..Luau:GetBuiltinInfo(ed[1]).."()"
					elseif opn=="FASTCALL1" then result..="-- FASTCALL1; "..Luau:GetBuiltinInfo(ed[1]).."("..fmtReg(ur[1])..")"
					elseif opn=="FASTCALL2" then result..="-- FASTCALL2; "..Luau:GetBuiltinInfo(ed[1]).."("..fmtReg(ur[1])..", "..fmtReg(ur[2])..")"
					elseif opn=="FASTCALL2K" then
						result..="-- FASTCALL2K; "..Luau:GetBuiltinInfo(ed[1]).."("..fmtReg(ur[1])..", "..fmtConst(consts[(ed[3] or 0)+1])..")"
					elseif opn=="FASTCALL3" then
						result..="-- FASTCALL3; "..Luau:GetBuiltinInfo(ed[1]).."("..fmtReg(ur[1])..", "..fmtReg(ur[2])..", "..fmtReg(ur[3])..")"
					end
					result..="\n"
					handleJumps()
				end
			end
			writeActions(registerActions[mainProtoId])
			finalResult = processResult(result)
		else
			finalResult = processResult("-- one day..")
		end
		return finalResult
	end
	local function manager(proceed, issue)
		if proceed then
			local startTime = os.clock()
			local result
			task.spawn(function()
				result = finalize(organize())
			end)
			while not result and (os.clock()-startTime) < options.DecompilerTimeout do
				task.wait()
			end
			if result then
				return string.format(Strings.SUCCESS, result)
			end
			return Strings.TIMEOUT
		else
			if issue == "COMPILATION_FAILURE" then
				local len = reader:len()-1
				return string.format(Strings.COMPILATION_FAILURE, reader:nextString(len))
			elseif issue == "UNSUPPORTED_LBC_VERSION" then
				return Strings.UNSUPPORTED_LBC_VERSION
			end
		end
	end
	bytecodeVersion = reader:nextByte()
	if bytecodeVersion == 0 then
		return manager(false, "COMPILATION_FAILURE")
	elseif bytecodeVersion >= LuauBytecodeTag.LBC_VERSION_MIN
	   and bytecodeVersion <= LuauBytecodeTag.LBC_VERSION_MAX then
		return manager(true)
	else
		return manager(false, "UNSUPPORTED_LBC_VERSION")
	end
end
local CONST_TYPE = {
	[0]="nil",[1]="boolean",[2]="number(f64)",[3]="string",
	[4]="import",[5]="table",[6]="closure",[7]="number(f32)",[8]="number(i16)"
}
local function parseProto(p, stringTable, depth)
	local result = {
		depth=depth or 0, maxStack=p:nextByte(), numParams=p:nextByte(),
		numUpvals=p:nextByte(), isVararg=p:nextByte()~=0, flags=p:nextByte(),
		constants={}, protos={}, upvalues={}, debugName="", strings={}, imports={},
	}
	local typeSize = p:nextVarInt()
	if typeSize>0 then for _=1,typeSize do p:nextByte() end end
	local instrCount = p:nextVarInt()
	for _=1,instrCount do p:nextUInt32() end
	local constCount = p:nextVarInt()
	for i=1,constCount do
		local kind=p:nextByte()
		local name=CONST_TYPE[kind] or ("unknown("..kind..")")
		local value
		if     kind==0 then value="nil"
		elseif kind==1 then value=p:nextByte()~=0 and "true" or "false"
		elseif kind==2 then value=tostring(p:nextDouble())
		elseif kind==7 then value=tostring(p:nextFloat())
		elseif kind==8 then
			local lo,hi=p:nextByte(),p:nextByte()
			local n=lo+hi*256; if n>=32768 then n=n-65536 end; value=tostring(n)
		elseif kind==3 then
			local idx=p:nextVarInt()
			value=stringTable[idx] or ("<string #"..idx..">")
			table.insert(result.strings,value)
		elseif kind==4 then
			local id=p:nextUInt32()
			local k0=bit32.band(bit32.rshift(id,20),0x3FF)
			local k1=bit32.band(bit32.rshift(id,10),0x3FF)
			local k2=bit32.band(id,0x3FF)
			local parts={}
			for _,k in ipairs({k0,k1,k2}) do
				if stringTable[k] then table.insert(parts,stringTable[k]) end
			end
			value=table.concat(parts,"."); table.insert(result.imports,value)
		elseif kind==5 then
			local keys,ks=p:nextVarInt(),{}
			for _=1,keys do
				local kidx=p:nextVarInt(); table.insert(ks,stringTable[kidx] or "?")
			end
			value="{"..table.concat(ks,", ").."}"
		elseif kind==6 then value="<proto #"..p:nextVarInt()..">"
		else value="?" end
		table.insert(result.constants,{kind=name,value=value,index=i-1})
	end
	local protoCount=p:nextVarInt()
	for i=1,protoCount do
		local ok,inner=pcall(parseProto,p,stringTable,depth+1)
		table.insert(result.protos,ok and inner or {error=tostring(inner),depth=depth+1})
	end
	local hasLines=p:nextByte()
	if hasLines~=0 then
		local lgap=p:nextByte()
		local intervalCount=bit32.rshift(instrCount-1,lgap)+1
		for _=1,intervalCount do p:nextByte() end
		for _=1,instrCount do p:nextByte() end
	end
	local hasDebug=p:nextByte()
	if hasDebug~=0 then
		local nameIdx=p:nextVarInt()
		result.debugName=stringTable[nameIdx] or ""
		local lc=p:nextVarInt()
		for _=1,lc do p:nextVarInt();p:nextVarInt();p:nextVarInt();p:nextByte() end
		local uc=p:nextVarInt()
		for j=1,uc do
			local ui=p:nextVarInt()
			table.insert(result.upvalues,stringTable[ui] or ("upval_"..j))
		end
	end
	return result
end
local function parseBytecode(bytes)
	local reader2=Reader.new(bytes)
	local ver=reader2:nextByte()
	if ver==0 then return nil,"Compile error: "..reader2:nextString(reader2:len()-1) end
	local typesVer=reader2:nextByte()
	local stringCount=reader2:nextVarInt()
	local stringTable={}
	for i=1,stringCount do
		local len=reader2:nextVarInt(); stringTable[i]=reader2:nextString(len)
	end
	local protoCount=reader2:nextVarInt()
	local protos={}
	for i=1,protoCount do
		local ok,proto=pcall(parseProto,reader2,stringTable,0)
		table.insert(protos,ok and proto or {error=tostring(proto),depth=0})
	end
	local entryProto=reader2:nextVarInt()
	return {version=ver,typesVersion=typesVer,
		stringTable=stringTable,protos=protos,entryProto=entryProto}
end
local function buildReport(parsed, scriptName)
	local lines={}
	local function w(s) table.insert(lines,s or "") end
	w("════════════════════════════════════════════════════")
	w("  BYTECODE INSPECTOR — "..(scriptName or "unknown"))
	w("════════════════════════════════════════════════════")
	w("  Luau version : "..parsed.version)
	w("  Types version: "..parsed.typesVersion)
	w("  Proto count  : "..#parsed.protos)
	w("  Entry proto  : #"..parsed.entryProto)
	w("  Strings total: "..#parsed.stringTable)
	w("")
	w("── STRING TABLE ─────────────────────────────────────")
	for i,s in ipairs(parsed.stringTable) do w(string.format("  [%3d] %q",i,s)) end
	w("")
	local function walkProto(proto,idx)
		if proto.error then w("  [Proto #"..idx.."] PARSE ERROR: "..proto.error); return end
		local ind=string.rep("  ",proto.depth+1)
		local dn=proto.debugName~="" and (" '"..proto.debugName.."'") or ""
		w(string.format("%s── Proto #%d%s",ind,idx,dn))
		w(string.format("%s   params=%d  upvals=%d  maxStack=%d  vararg=%s",
			ind,proto.numParams,proto.numUpvals,proto.maxStack,tostring(proto.isVararg)))
		if #proto.upvalues>0 then w(ind.."   Upvalues: "..table.concat(proto.upvalues,", ")) end
		if #proto.imports>0  then
			w(ind.."   Imports:")
			for _,imp in ipairs(proto.imports) do w(ind.."     "..imp) end
		end
		if #proto.strings>0  then
			w(ind.."   String literals:")
			for _,s in ipairs(proto.strings) do w(ind..'     "'..s..'"') end
		end
		if #proto.constants>0 then
			w(ind.."   All constants:")
			for _,c in ipairs(proto.constants) do
				w(string.format("%s     [%2d] %-14s %s",ind,c.index,c.kind,tostring(c.value)))
			end
		end
		w("")
		for i2,inner in ipairs(proto.protos) do walkProto(inner,i2) end
	end
	w("── PROTO TREE ───────────────────────────────────────")
	for i,proto in ipairs(parsed.protos) do walkProto(proto,i) end
	return table.concat(lines,"\n")
end
local COL_BG       = Color3.fromRGB(52, 52, 52)
local COL_CONTENT  = Color3.fromRGB(45, 45, 45)
local COL_EDITOR   = Color3.fromRGB(36, 36, 36)
local COL_SEP      = Color3.fromRGB(33, 33, 33)
local COL_BTN      = Color3.fromRGB(42, 42, 42)
local COL_BTN_HOV  = Color3.fromRGB(58, 58, 58)
local COL_SEL      = Color3.fromRGB(55, 70, 100)
local COL_WHITE    = Color3.fromRGB(255, 255, 255)
local COL_TEXT     = Color3.fromRGB(204, 204, 204)
local COL_DIM      = Color3.fromRGB(140, 140, 140)
local COL_GREEN    = Color3.fromRGB(120, 200, 120)
local COL_YELLOW   = Color3.fromRGB(255, 200, 80)
local COL_RED      = Color3.fromRGB(255, 90, 90)
local TITLE_H  = 20
local TOOL_H   = 20
local STATUS_H = 18
local LEFT_W   = 270
local SCROLL_T = 6
local function makeFlatBtn(parent, text, size, pos)
	local b = Instance.new("TextButton", parent)
	b.Size = size; b.Position = pos
	b.BackgroundColor3 = COL_BTN; b.BorderSizePixel = 0
	b.Text = text; b.Font = Enum.Font.SourceSans; b.TextSize = 8
	b.TextColor3 = COL_WHITE; b.AutoButtonColor = false
	b.MouseEnter:Connect(function() b.BackgroundColor3 = COL_BTN_HOV end)
	b.MouseLeave:Connect(function() b.BackgroundColor3 = COL_BTN end)
	return b
end
local existing = LocalPlayer:WaitForChild("PlayerGui"):FindFirstChild("ModuleScanner")
if existing then existing:Destroy() end
local gui = Instance.new("ScreenGui")
gui.Name = "ModuleScanner"; gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = true
gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
local main = Instance.new("Frame", gui)
main.Name = "Main"
main.Size = UDim2.new(0, 900, 0, 520)
main.Position = UDim2.new(0.5, -450, 0.5, -260)
main.BackgroundColor3 = COL_BG
main.BorderSizePixel = 0
main.Active = true; main.Draggable = true
local titleBar = Instance.new("Frame", main)
titleBar.Size = UDim2.new(1, 0, 0, TITLE_H)
titleBar.BackgroundTransparency = 1; titleBar.BorderSizePixel = 0
local titleLbl = Instance.new("TextLabel", titleBar)
titleLbl.Size = UDim2.new(1, -42, 1, 0); titleLbl.Position = UDim2.new(0, 5, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Text = "poor mans decompiler"
titleLbl.Font = Enum.Font.SourceSans; titleLbl.TextSize = 14
titleLbl.TextColor3 = COL_WHITE
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.TextYAlignment = Enum.TextYAlignment.Center
local closeBtn = Instance.new("TextButton", titleBar)
closeBtn.Size = UDim2.new(0, 16, 0, 16); closeBtn.Position = UDim2.new(1, -18, 0, 2)
closeBtn.BackgroundTransparency = 1; closeBtn.Text = ""
local closeImg = Instance.new("ImageLabel", closeBtn)
closeImg.Size = UDim2.new(0, 10, 0, 10); closeImg.Position = UDim2.new(0, 3, 0, 3)
closeImg.BackgroundTransparency = 1; closeImg.Image = "rbxassetid://5054663650"
closeBtn.MouseButton1Click:Connect(function() gui:Destroy() end)
local minimized = false
local minimizeBtn = Instance.new("TextButton", titleBar)
minimizeBtn.Size = UDim2.new(0, 16, 0, 16); minimizeBtn.Position = UDim2.new(1, -36, 0, 2)
minimizeBtn.BackgroundTransparency = 1; minimizeBtn.Text = ""
local minimizeImg = Instance.new("ImageLabel", minimizeBtn)
minimizeImg.Size = UDim2.new(0, 10, 0, 10); minimizeImg.Position = UDim2.new(0, 3, 0, 3)
minimizeImg.BackgroundTransparency = 1; minimizeImg.Image = "rbxassetid://5034768003"
minimizeBtn.MouseButton1Click:Connect(function()
	if not minimized then
		for _, c in ipairs(main:GetChildren()) do
			if c ~= titleBar then c.Visible = false end
		end
		main:TweenSize(UDim2.new(0, 900, 0, TITLE_H + 4),
			Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.18, true)
		minimized = true
	else
		for _, c in ipairs(main:GetChildren()) do c.Visible = true end
		main:TweenSize(UDim2.new(0, 900, 0, 520),
			Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.18, true)
		minimized = false
	end
end)
local content = Instance.new("Frame", main)
content.Name = "Content"
content.Size = UDim2.new(1, 0, 1, -TITLE_H)
content.Position = UDim2.new(0, 0, 0, TITLE_H)
content.BackgroundColor3 = COL_CONTENT; content.BorderSizePixel = 0
local toolSep = Instance.new("Frame", content)
toolSep.Size = UDim2.new(1, 0, 0, 1); toolSep.Position = UDim2.new(0, 0, 0, TOOL_H)
toolSep.BackgroundColor3 = COL_SEP; toolSep.BorderSizePixel = 0
local scanBtn = makeFlatBtn(content, "Scan",
	UDim2.new(0, 55, 0, TOOL_H), UDim2.new(0, 0, 0, 0))
local clearListBtn = makeFlatBtn(content, "Clear",
	UDim2.new(0, 45, 0, TOOL_H), UDim2.new(0, 56, 0, 0))
local toolMidSep = Instance.new("Frame", content)
toolMidSep.Size = UDim2.new(0, 1, 0, TOOL_H); toolMidSep.Position = UDim2.new(0, LEFT_W, 0, 0)
toolMidSep.BackgroundColor3 = COL_SEP; toolMidSep.BorderSizePixel = 0
local inspectBtn = makeFlatBtn(content, "Inspect",
	UDim2.new(0, 65, 0, TOOL_H), UDim2.new(0, LEFT_W + 2, 0, 0))
local disasmBtn = makeFlatBtn(content, "Disassemble",
	UDim2.new(0, 82, 0, TOOL_H), UDim2.new(0, LEFT_W + 69, 0, 0))
local copyBtn = makeFlatBtn(content, "Copy Output",
	UDim2.new(0, 72, 0, TOOL_H), UDim2.new(0, LEFT_W + 153, 0, 0))
local selectedLbl = Instance.new("TextLabel", content)
selectedLbl.Size = UDim2.new(1, -(LEFT_W + 234), 0, TOOL_H)
selectedLbl.Position = UDim2.new(0, LEFT_W + 228, 0, 0)
selectedLbl.BackgroundTransparency = 1
selectedLbl.Text = "Select a module →"
selectedLbl.Font = Enum.Font.SourceSans; selectedLbl.TextSize = 8
selectedLbl.TextColor3 = COL_DIM
selectedLbl.TextXAlignment = Enum.TextXAlignment.Left
selectedLbl.TextYAlignment = Enum.TextYAlignment.Center
selectedLbl.TextTruncate = Enum.TextTruncate.AtEnd
local BODY_Y  = TOOL_H + 1
local BODY_H  = -(TOOL_H + 1 + STATUS_H)
local leftPanel = Instance.new("Frame", content)
leftPanel.Size = UDim2.new(0, LEFT_W, 1, BODY_H)
leftPanel.Position = UDim2.new(0, 0, 0, BODY_Y)
leftPanel.BackgroundColor3 = COL_EDITOR; leftPanel.BorderSizePixel = 0
local vSep = Instance.new("Frame", content)
vSep.Size = UDim2.new(0, 1, 1, BODY_H)
vSep.Position = UDim2.new(0, LEFT_W, 0, BODY_Y)
vSep.BackgroundColor3 = COL_SEP; vSep.BorderSizePixel = 0
local searchBox = Instance.new("TextBox", leftPanel)
searchBox.Size = UDim2.new(1, 0, 0, 18); searchBox.Position = UDim2.new(0, 0, 0, 0)
searchBox.BackgroundColor3 = COL_BTN; searchBox.BorderSizePixel = 0
searchBox.PlaceholderText = "Filter modules..."; searchBox.Text = ""
searchBox.Font = Enum.Font.SourceSans; searchBox.TextSize = 8
searchBox.TextColor3 = COL_WHITE; searchBox.ClearTextOnFocus = false
searchBox.PlaceholderColor3 = COL_DIM
local searchSep = Instance.new("Frame", leftPanel)
searchSep.Size = UDim2.new(1, 0, 0, 1); searchSep.Position = UDim2.new(0, 0, 0, 18)
searchSep.BackgroundColor3 = COL_SEP; searchSep.BorderSizePixel = 0
local countLbl = Instance.new("TextLabel", leftPanel)
countLbl.Size = UDim2.new(1, -4, 0, 14); countLbl.Position = UDim2.new(0, 4, 0, 20)
countLbl.BackgroundTransparency = 1; countLbl.Text = "No scan yet."
countLbl.Font = Enum.Font.SourceSans; countLbl.TextSize = 8
countLbl.TextColor3 = COL_DIM; countLbl.TextXAlignment = Enum.TextXAlignment.Left
local listScroll = Instance.new("ScrollingFrame", leftPanel)
listScroll.Size = UDim2.new(1, 0, 1, -34); listScroll.Position = UDim2.new(0, 0, 0, 34)
listScroll.BackgroundTransparency = 1; listScroll.BorderSizePixel = 0
listScroll.ScrollBarThickness = SCROLL_T
listScroll.ScrollBarImageColor3 = Color3.fromRGB(70, 70, 70)
listScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
listScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
local listLayout = Instance.new("UIListLayout", listScroll)
listLayout.Padding = UDim.new(0, 0)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
local Syntax = {
	Text          = Color3.fromRGB(204,204,204),
	Operator      = Color3.fromRGB(204,204,204),
	Number        = Color3.fromRGB(255,198,0),
	String        = Color3.fromRGB(173,241,149),
	Comment       = Color3.fromRGB(102,102,102),
	Keyword       = Color3.fromRGB(248,109,124),
	BuiltIn       = Color3.fromRGB(132,214,247),
	LocalMethod   = Color3.fromRGB(253,251,172),
	LocalProperty = Color3.fromRGB(97,161,241),
	Nil           = Color3.fromRGB(255,198,0),
	Bool          = Color3.fromRGB(255,198,0),
	Function      = Color3.fromRGB(248,109,124),
	Local         = Color3.fromRGB(248,109,124),
	Self          = Color3.fromRGB(248,109,124),
	FunctionName  = Color3.fromRGB(253,251,172),
	Bracket       = Color3.fromRGB(204,204,204),
}
local function colorToHex(c)
	return string.format("#%02x%02x%02x",
		math.floor(c.R*255), math.floor(c.G*255), math.floor(c.B*255))
end
local HL_KEYWORDS = {
	["and"]=true,["break"]=true,["do"]=true,["else"]=true,["elseif"]=true,
	["end"]=true,["false"]=true,["for"]=true,["function"]=true,["if"]=true,
	["in"]=true,["local"]=true,["nil"]=true,["not"]=true,["or"]=true,
	["repeat"]=true,["return"]=true,["then"]=true,["true"]=true,
	["until"]=true,["while"]=true,
}
local HL_BUILTINS = {
	["game"]=true,["Players"]=true,["TweenService"]=true,["ScreenGui"]=true,
	["Instance"]=true,["UDim2"]=true,["Vector2"]=true,["Vector3"]=true,
	["Color3"]=true,["Enum"]=true,["loadstring"]=true,["warn"]=true,
	["pcall"]=true,["print"]=true,["UDim"]=true,["delay"]=true,
	["require"]=true,["spawn"]=true,["tick"]=true,["getfenv"]=true,
	["workspace"]=true,["setfenv"]=true,["getgenv"]=true,["script"]=true,
	["string"]=true,["pairs"]=true,["type"]=true,["math"]=true,
	["tonumber"]=true,["tostring"]=true,["CFrame"]=true,["BrickColor"]=true,
	["table"]=true,["Random"]=true,["Ray"]=true,["xpcall"]=true,
	["coroutine"]=true,["_G"]=true,["_VERSION"]=true,["debug"]=true,
	["Axes"]=true,["assert"]=true,["error"]=true,["ipairs"]=true,
	["rawequal"]=true,["rawget"]=true,["rawset"]=true,["select"]=true,
	["bit32"]=true,["buffer"]=true,["task"]=true,["os"]=true,
}
local HL_METHODS = {
	["WaitForChild"]=true,["FindFirstChild"]=true,["GetService"]=true,
	["Destroy"]=true,["Clone"]=true,["IsA"]=true,["ClearAllChildren"]=true,
	["GetChildren"]=true,["GetDescendants"]=true,["Connect"]=true,
	["Disconnect"]=true,["Fire"]=true,["Invoke"]=true,["rgb"]=true,
	["FireServer"]=true,["request"]=true,["call"]=true,
}
local function hlTokenize(line)
	local tokens, i = {}, 1
	while i <= #line do
		local c = line:sub(i,i)
		if c == "-" and line:sub(i,i+1) == "--" then
			table.insert(tokens, {line:sub(i), "Comment"}); break
		elseif c == '"' or c == "'" then
			local q, j = c, i+1
			while j <= #line do
				if line:sub(j,j) == q and line:sub(j-1,j-1) ~= "\\" then break end
				j += 1
			end
			table.insert(tokens, {line:sub(i,j), "String"}); i = j
		elseif c:match("%d") then
			local j = i
			while j <= #line and line:sub(j,j):match("[%d%.]") do j += 1 end
			table.insert(tokens, {line:sub(i,j-1), "Number"}); i = j-1
		elseif c:match("[%a_]") then
			local j = i
			while j <= #line and line:sub(j,j):match("[%w_]") do j += 1 end
			table.insert(tokens, {line:sub(i,j-1), "Word"}); i = j-1
		else
			table.insert(tokens, {c, "Operator"})
		end
		i += 1
	end
	return tokens
end
local function hlDetect(tokens, idx)
	local val, typ = tokens[idx][1], tokens[idx][2]
	if typ ~= "Word" then return typ end
	if HL_KEYWORDS[val]  then return "Keyword"  end
	if HL_BUILTINS[val]  then return "BuiltIn"  end
	if HL_METHODS[val]   then return "LocalMethod" end
	if idx > 1 and tokens[idx-1][1] == "." then return "LocalProperty" end
	if idx > 1 and tokens[idx-1][1] == ":" then return "LocalMethod" end
	if val == "self"  then return "Self" end
	if val == "true" or val == "false" then return "Bool" end
	if val == "nil"   then return "Nil"  end
	if idx > 1 and tokens[idx-1][1] == "function" then return "FunctionName" end
	return "Text"
end
local function hlLine(line)
	local tokens = hlTokenize(line)
	local out = ""
	for i, tok in ipairs(tokens) do
		local col = Syntax[hlDetect(tokens, i)] or Syntax.Text
		local safe = tok[1]:gsub("&","&amp;"):gsub("<","&lt;"):gsub(">","&gt;")
		out ..= string.format('<font color="%s">%s</font>', colorToHex(col), safe)
	end
	return out
end
local HL_LINE_H  = 18
local HL_GUTTER  = 46
local HL_FONT    = Enum.Font.Code
local HL_TS      = 13
local _outputRaw = ""
local rightPanel = Instance.new("Frame", content)
rightPanel.Size = UDim2.new(1, -(LEFT_W + 1), 1, BODY_H)
rightPanel.Position = UDim2.new(0, LEFT_W + 1, 0, BODY_Y)
rightPanel.BackgroundColor3 = COL_EDITOR; rightPanel.BorderSizePixel = 0
local outputPlaceholder = Instance.new("TextLabel", rightPanel)
outputPlaceholder.Size = UDim2.new(1, -10, 0, 20)
outputPlaceholder.Position = UDim2.new(0, 10, 0, 6)
outputPlaceholder.BackgroundTransparency = 1
outputPlaceholder.Text = " --Inspect or Disassemble a module"
outputPlaceholder.Font = HL_FONT; outputPlaceholder.TextSize = HL_TS
outputPlaceholder.TextColor3 = COL_DIM
outputPlaceholder.TextXAlignment = Enum.TextXAlignment.Left
outputPlaceholder.TextYAlignment = Enum.TextYAlignment.Top
local outputScroll = Instance.new("ScrollingFrame", rightPanel)
outputScroll.Size = UDim2.new(1, 0, 1, 0); outputScroll.Position = UDim2.new(0, 0, 0, 0)
outputScroll.BackgroundTransparency = 1; outputScroll.BorderSizePixel = 0
outputScroll.ScrollBarThickness = SCROLL_T
outputScroll.ScrollBarImageColor3 = Color3.fromRGB(70, 70, 70)
outputScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
outputScroll.ScrollingDirection = Enum.ScrollingDirection.XY
outputScroll.Visible = false
local gutterFrame = Instance.new("Frame", outputScroll)
gutterFrame.Name = "Gutter"
gutterFrame.Size = UDim2.new(0, HL_GUTTER, 1, 0)
gutterFrame.Position = UDim2.new(0, 0, 0, 0)
gutterFrame.BackgroundColor3 = Color3.fromRGB(32, 32, 32)
gutterFrame.BorderSizePixel = 0
gutterFrame.ZIndex = 2
local gutterSep = Instance.new("Frame", gutterFrame)
gutterSep.Size = UDim2.new(0, 1, 1, 0); gutterSep.Position = UDim2.new(1, -1, 0, 0)
gutterSep.BackgroundColor3 = COL_SEP; gutterSep.BorderSizePixel = 0
local codeFrame = Instance.new("Frame", outputScroll)
codeFrame.Name = "CodeLines"
codeFrame.Position = UDim2.new(0, HL_GUTTER + 2, 0, 0)
codeFrame.Size = UDim2.new(1, -(HL_GUTTER + 2), 0, 0)
codeFrame.BackgroundTransparency = 1
codeFrame.BorderSizePixel = 0
local function renderOutput(text)
	for _, c in ipairs(gutterFrame:GetChildren()) do
		if c:IsA("TextLabel") then c:Destroy() end
	end
	for _, c in ipairs(codeFrame:GetChildren()) do c:Destroy() end
	local linesTbl = text:split("\n")
	if linesTbl[#linesTbl] == "" then table.remove(linesTbl) end
	local longestPx = 0
	local charW = math.floor(HL_TS * 0.6)
	for i, line in ipairs(linesTbl) do
		local yOff = (i - 1) * HL_LINE_H
		local numLbl = Instance.new("TextLabel", gutterFrame)
		numLbl.Size = UDim2.new(1, -4, 0, HL_LINE_H)
		numLbl.Position = UDim2.new(0, 0, 0, yOff)
		numLbl.BackgroundTransparency = 1
		numLbl.Text = tostring(i)
		numLbl.Font = HL_FONT; numLbl.TextSize = HL_TS
		numLbl.TextColor3 = Color3.fromRGB(90, 90, 90)
		numLbl.TextXAlignment = Enum.TextXAlignment.Right
		numLbl.TextYAlignment = Enum.TextYAlignment.Top
		numLbl.ZIndex = 2
		local codeLbl = Instance.new("TextLabel", codeFrame)
		codeLbl.Size = UDim2.new(0, math.max(400, #line * charW + 20), 0, HL_LINE_H)
		codeLbl.Position = UDim2.new(0, 4, 0, yOff)
		codeLbl.BackgroundTransparency = 1
		codeLbl.RichText = true; codeLbl.TextWrapped = false
		codeLbl.Font = HL_FONT; codeLbl.TextSize = HL_TS
		codeLbl.TextColor3 = COL_TEXT
		codeLbl.TextXAlignment = Enum.TextXAlignment.Left
		codeLbl.TextYAlignment = Enum.TextYAlignment.Top
		codeLbl.Text = hlLine(line)
		if #line * charW > longestPx then longestPx = #line * charW end
	end
	local totalH = #linesTbl * HL_LINE_H + 8
	codeFrame.Size = UDim2.new(0, longestPx + 60, 0, totalH)
	gutterFrame.Size = UDim2.new(0, HL_GUTTER, 0, totalH)
	outputScroll.CanvasSize = UDim2.new(0, HL_GUTTER + longestPx + 80, 0, totalH)
end
local statusBar = Instance.new("Frame", content)
statusBar.Size = UDim2.new(1, 0, 0, STATUS_H)
statusBar.Position = UDim2.new(0, 0, 1, -STATUS_H)
statusBar.BackgroundColor3 = COL_BTN; statusBar.BorderSizePixel = 0
local statusTopLine = Instance.new("Frame", statusBar)
statusTopLine.Size = UDim2.new(1, 0, 0, 1)
statusTopLine.BackgroundColor3 = COL_SEP; statusTopLine.BorderSizePixel = 0
local statusLbl = Instance.new("TextLabel", statusBar)
statusLbl.Size = UDim2.new(1, -8, 1, 0); statusLbl.Position = UDim2.new(0, 4, 0, 0)
statusLbl.BackgroundTransparency = 1; statusLbl.Text = "Ready."
statusLbl.Font = Enum.Font.SourceSans; statusLbl.TextSize = 8
statusLbl.TextColor3 = COL_GREEN
statusLbl.TextXAlignment = Enum.TextXAlignment.Left
statusLbl.TextYAlignment = Enum.TextYAlignment.Center
local ModuleList     = {}
local selectedModule = nil
local allButtons     = {}
local function setStatus(msg, color)
	statusLbl.Text = msg
	statusLbl.TextColor3 = color or COL_GREEN
end
local function setOutput(text)
	_outputRaw = text or ""
	if _outputRaw == "" then
		outputScroll.Visible = false
		outputPlaceholder.Visible = true
	else
		outputPlaceholder.Visible = false
		outputScroll.Visible = true
		outputScroll.CanvasPosition = Vector2.zero
		renderOutput(_outputRaw)
	end
end
local function clearList()
	ModuleList = {}; allButtons = {}
	for _, child in ipairs(listScroll:GetChildren()) do
		if not child:IsA("UIListLayout") then child:Destroy() end
	end
	selectedModule = nil; countLbl.Text = "Cleared."
	selectedLbl.Text = "Select a module →"
	setOutput(""); setStatus("Ready.")
end
local function addModuleToList(obj)
	for _, m in ipairs(ModuleList) do if m == obj then return end end
	table.insert(ModuleList, obj)
	local btn = Instance.new("TextButton", listScroll)
	btn.Size = UDim2.new(1, 0, 0, 26)
	btn.BackgroundColor3 = COL_EDITOR
	btn.BorderSizePixel = 0; btn.Text = ""; btn.AutoButtonColor = false
	local rowSep = Instance.new("Frame", btn)
	rowSep.Size = UDim2.new(1, 0, 0, 1); rowSep.Position = UDim2.new(0, 0, 1, -1)
	rowSep.BackgroundColor3 = COL_SEP; rowSep.BorderSizePixel = 0
	local nameLbl2 = Instance.new("TextLabel", btn)
	nameLbl2.Size = UDim2.new(1, -8, 0, 15); nameLbl2.Position = UDim2.new(0, 6, 0, 2)
	nameLbl2.BackgroundTransparency = 1; nameLbl2.Text = obj.Name
	nameLbl2.Font = Enum.Font.SourceSansBold; nameLbl2.TextSize = 8
	nameLbl2.TextColor3 = COL_WHITE; nameLbl2.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl2.TextTruncate = Enum.TextTruncate.AtEnd
	local pathLbl2 = Instance.new("TextLabel", btn)
	pathLbl2.Size = UDim2.new(1, -8, 0, 10); pathLbl2.Position = UDim2.new(0, 6, 0, 16)
	pathLbl2.BackgroundTransparency = 1; pathLbl2.Text = obj:GetFullName()
	pathLbl2.Font = Enum.Font.SourceSans; pathLbl2.TextSize = 8
	pathLbl2.TextColor3 = COL_DIM; pathLbl2.TextXAlignment = Enum.TextXAlignment.Left
	pathLbl2.TextTruncate = Enum.TextTruncate.AtEnd
	table.insert(allButtons, {
		btn  = btn, obj = obj,
		name = obj.Name:lower(), path = obj:GetFullName():lower()
	})
	btn.MouseEnter:Connect(function()
		if selectedModule ~= obj then btn.BackgroundColor3 = COL_BTN end
	end)
	btn.MouseLeave:Connect(function()
		if selectedModule ~= obj then btn.BackgroundColor3 = COL_EDITOR end
	end)
	btn.MouseButton1Click:Connect(function()
		for _, d in ipairs(allButtons) do d.btn.BackgroundColor3 = COL_EDITOR end
		btn.BackgroundColor3 = COL_SEL
		selectedModule = obj
		selectedLbl.Text = obj:GetFullName()
		setStatus("Selected: " .. obj.Name .. " — Inspect or Disassemble", COL_DIM)
	end)
end
searchBox:GetPropertyChangedSignal("Text"):Connect(function()
	local f = searchBox.Text:lower()
	for _, d in ipairs(allButtons) do
		d.btn.Visible = f == "" or d.name:find(f, 1, true) or d.path:find(f, 1, true)
	end
end)
local SCAN_PATHS = {ReplicatedStorage, ReplicatedFirst, Workspace, Players.LocalPlayer}
scanBtn.MouseButton1Click:Connect(function()
	clearList()
	setStatus("Scanning...", COL_YELLOW)
	countLbl.Text = "Scanning..."
	task.spawn(function()
		local found = 0
		for _, parent in ipairs(SCAN_PATHS) do
			if parent then
				local ok, desc = pcall(function() return parent:GetDescendants() end)
				if ok then
					for _, obj in ipairs(desc) do
						if obj:IsA("ModuleScript") then addModuleToList(obj); found += 1 end
					end
				end
				task.wait()
			end
		end
		pcall(function()
			for _, obj in ipairs(Players.LocalPlayer:WaitForChild("PlayerScripts", 2):GetDescendants()) do
				if obj:IsA("ModuleScript") then addModuleToList(obj); found += 1 end
			end
		end)
		countLbl.Text = found .. " module(s) found"
		setStatus("Scan complete — " .. found .. " module(s) found.")
	end)
end)
clearListBtn.MouseButton1Click:Connect(clearList)
local function fetchBytecode()
	if not selectedModule then
		setStatus("No module selected.", COL_YELLOW); return nil
	end
	local ok, bytes = pcall(getscriptbytecode, selectedModule)
	if not ok or not bytes or bytes == "" then
		setStatus("getscriptbytecode() failed — protected or unloaded.", COL_RED)
		setOutput("-- Could not read bytecode for:\n-- " .. selectedModule:GetFullName()
			.. "\n--\n-- Script may be:\n--   Protected (MoonSec, Luraph, etc)\n"
			.. "--   Not yet loaded\n--   Server-side only\n")
		return nil
	end
	return bytes
end
inspectBtn.MouseButton1Click:Connect(function()
	setStatus("Reading bytecode...", COL_YELLOW); setOutput(""); task.wait()
	local bytes = fetchBytecode(); if not bytes then return end
	local parsed, err = parseBytecode(bytes)
	if not parsed then
		setStatus("Parse error: " .. tostring(err), COL_RED)
		setOutput("-- Parse failed: " .. tostring(err)); return
	end
	local report = buildReport(parsed, selectedModule:GetFullName())
	setOutput(report)
	setStatus(string.format("Inspect done — %d strings, %d protos, %d bytes",
		#parsed.stringTable, #parsed.protos, #bytes))
end)
disasmBtn.MouseButton1Click:Connect(function()
	setStatus("Disassembling...", COL_YELLOW); setOutput(""); task.wait()
	local bytes = fetchBytecode(); if not bytes then return end
	local opts = table.clone(DEFAULT_OPTIONS)
	opts.DecompilerMode = "disasm"
	local ok, result = pcall(Decompile, bytes, opts)
	if not ok then
		setStatus("Decompiler error: " .. tostring(result), COL_RED)
		setOutput("-- Decompiler threw:\n-- " .. tostring(result)); return
	end
	setOutput(result or "-- (empty output)")
	setStatus(string.format("Disassembly done — %d bytes.", #bytes))
end)
copyBtn.MouseButton1Click:Connect(function()
	if _outputRaw == "" then setStatus("Nothing to copy.", COL_YELLOW); return end
	pcall(setclipboard, _outputRaw)
	setStatus("Copied to clipboard!")
end)
setStatus("made by zuka")
