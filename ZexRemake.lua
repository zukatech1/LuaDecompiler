--[[ zukv2™  legacy zex - built from scratch ]]


local FLOAT_PRECISION  = 7


local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local localPlayer      = Players.LocalPlayer
local playerGui        = localPlayer:WaitForChild("PlayerGui")


local Reader = {}


function Reader.new(bytecode)
	local stream = buffer.fromstring(bytecode)
	local cursor = 0
	local blen   = buffer.len(stream)
	local self   = {}
	local function guard(n)
		if cursor + n > blen then
			error(string.format("Reader OOB: need %d byte(s) at offset %d (buf len %d)", n, cursor, blen), 2)
		end
	end
	function self:len()       return blen end
	function self:nextByte()
		guard(1); local r = buffer.readu8(stream, cursor); cursor += 1; return r
	end
	function self:nextSignedByte()
		guard(1); local r = buffer.readi8(stream, cursor); cursor += 1; return r
	end
	function self:nextBytes(count)
		local t = {}
		for i = 1, count do t[i] = self:nextByte() end
		return t
	end
	function self:nextChar()     return string.char(self:nextByte()) end
	function self:nextUInt32()
		guard(4); local r = buffer.readu32(stream, cursor); cursor += 4; return r
	end
	function self:nextInt32()
		guard(4); local r = buffer.readi32(stream, cursor); cursor += 4; return r
	end
	function self:nextFloat()
		guard(4); local r = buffer.readf32(stream, cursor); cursor += 4
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
	function self:nextString(slen)
		slen = slen or self:nextVarInt()
		if slen == 0 then return "" end
		guard(slen)
		local r = buffer.readstring(stream, cursor, slen); cursor += slen; return r
	end
	function self:nextDouble()
		guard(8); local r = buffer.readf64(stream, cursor); cursor += 8; return r
	end
	return self
end
function Reader:Set(fp) FLOAT_PRECISION = fp end
local Strings = {
	SUCCESS              = "%s",
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
	ShowInstructionLines = false,
	ShowOperationIndex   = false,
	ShowOperationNames   = false,
	ShowTrivialOperations= true,
	UseTypeInfo          = true,
	ListUsedGlobals      = true,
	ReturnElapsedTime    = true,
	CleanMode            = false,
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
local ROBLOX_GLOBALS_SET = {}
for _, v in ipairs(ROBLOX_GLOBALS) do ROBLOX_GLOBALS_SET[v] = true end
local function isGlobal(key) return ROBLOX_GLOBALS_SET[key] == true end
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
				if type(flags) == "table" then return end
				local rawFlags = type(flags) == "number" and flags or 0
				local df = {}
				if proto.main then
					df.native = toBoolean(bit32.band(rawFlags, LuauProtoFlag.LPF_NATIVE_MODULE))
				else
					df.native = toBoolean(bit32.band(rawFlags, LuauProtoFlag.LPF_NATIVE_FUNCTION))
					df.cold   = toBoolean(bit32.band(rawFlags, LuauProtoFlag.LPF_NATIVE_COLD))
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
		local usedGlobals    = {}
		local usedGlobalsSet = {}
		local function isValidGlobal(key)
			if usedGlobalsSet[key] then return false end
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
			local resultParts = {}
			local function emit(s) resultParts[#resultParts + 1] = s end
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
				if proto.main and pflags and pflags.native then emit("--!native\n") end
				local function buildRegNames(instrIdx)
					local names = {}
					if proto.debugLocals then
						for _, dl in ipairs(proto.debugLocals) do
							if instrIdx >= dl.startPC and instrIdx <= dl.endPC then
								names[dl.register] = dl.name
							end
						end
					end
					return names
				end
				local function fmtUpv(r)
					if r == nil then return "upv_unknown" end
					local du = proto.debugUpvalues
					if du then
						local entry = du[r + 1]
						if entry and entry.name and entry.name ~= "" then
							return entry.name
						end
					end
					local capturedReg = caps[r]
					if capturedReg ~= nil and proto.debugLocals then
						for _, dl in ipairs(proto.debugLocals) do
							if dl.register == capturedReg and dl.name and dl.name ~= "" then
								return dl.name
							end
						end
					end
					return "upv_" .. tostring(r)
				end
				local regNameCache = {}
				local function fmtReg(r, instrIdx)
					if instrIdx and proto.debugLocals then
						local cached = regNameCache[instrIdx]
						if not cached then
							cached = buildRegNames(instrIdx)
							regNameCache[instrIdx] = cached
						end
						if cached[r] and cached[r] ~= "" then
							return cached[r]
						end
					end
					local pr = r+1
					if pr < numParams+1 then
						return "p"..((totalParameters-numParams)+pr)
					end
					return "v"..(r-numParams)
				end
				local function paramName(j)
					if proto.debugLocals then
						for _, dl in ipairs(proto.debugLocals) do
							if dl.startPC == 0 and dl.register == j-1 then
								return dl.name
							end
						end
					end
					return "p"..(totalParameters+j)
				end
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
						local pb=paramName(j)
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
						emit("\n"..body)
						writeActions(registerActions[p.id])
						if not options.CleanMode then
							emit("end\n"..fmtReg(reg).." = "..p.name)
						else
							emit("end")
						end
					else
						emit(fmtReg(reg).." = "..body)
						writeActions(registerActions[p.id])
						emit("end")
					end
				end
				local CLEAN_SUPPRESS = {
					CLOSEUPVALS=true, PREPVARARGS=true, COVERAGE=true,
					CAPTURE=true, FASTCALL=true, FASTCALL1=true,
					FASTCALL2=true, FASTCALL2K=true, FASTCALL3=true,
					JUMPX=true, NOP=true, JUMPBACK=true,
				}
				for i, action in ipairs(actions) do
					if action.hide then continue end
					local ur  = action.usedRegisters
					local ed  = action.extraData
					local oci = action.opCode
					if not oci then continue end
					local opn = oci.name
					if options.CleanMode and CLEAN_SUPPRESS[opn] then continue end
					if options.CleanMode and opn == "RETURN" then
						local b = ed and ed[1] or 0
						if b == 1 then continue end
					end
					if options.CleanMode and opn == "MOVE" and
					   i > 1 and actions[i-1] and
					   (actions[i-1].opCode.name == "NEWCLOSURE" or
					    actions[i-1].opCode.name == "DUPCLOSURE") then
						continue
					end
					local function R(r) return fmtReg(r, i) end
					local function handleJumps()
						local n = jumpMarkers[i]
						if n then
							jumpMarkers[i]=nil
						for _=1,n do emit("end\n") end
						end
					end
					if not options.CleanMode then
						if options.ShowOperationIndex then
							emit("["..padLeft(i,"0",3).."] ")
						end
						if options.ShowInstructionLines and lineInfo and lineInfo[i] then
							emit(":"..padLeft(lineInfo[i],"0",3)..":")
						end
						if options.ShowOperationNames then
							emit(padRight(opn," ",15))
						end
					end
					if opn=="LOADNIL" then emit(R(ur[1]).." = nil")
					elseif opn=="LOADB" then
						emit(R(ur[1]).." = "..toEscapedString(toBoolean(ed[1])))
						if ed[2]~=0 then emit(" +"..ed[2]) end
					elseif opn=="LOADN" then emit(R(ur[1]).." = "..ed[1])
					elseif opn=="LOADK" then emit(R(ur[1]).." = "..fmtConst(consts[ed[1]+1]))
					elseif opn=="MOVE"  then emit(R(ur[1]).." = "..R(ur[2]))
					elseif opn=="GETGLOBAL" then
						local gk=tostring(consts[ed[1]+1] and consts[ed[1]+1].value or "")
						if options.ListUsedGlobals and isValidGlobal(gk) then
							table.insert(usedGlobals,gk); usedGlobalsSet[gk]=true
						end
						emit(R(ur[1]).." = "..gk)
					elseif opn=="SETGLOBAL" then
						local gk=tostring(consts[ed[1]+1] and consts[ed[1]+1].value or "")
						if options.ListUsedGlobals and isValidGlobal(gk) then
							table.insert(usedGlobals,gk); usedGlobalsSet[gk]=true
						end
						emit(gk.." = "..R(ur[1]))
					elseif opn=="GETUPVAL" then
						local slot=ed[1]; local rc=caps[slot]
						emit(R(ur[1]).." = "..fmtUpv(rc))
					elseif opn=="SETUPVAL" then
						local slot=ed[1]; local rc=caps[slot]
						emit(fmtUpv(rc).." = "..R(ur[1]))
					elseif opn=="CLOSEUPVALS" then emit("-- clear captures from back until: "..ur[1])
					elseif opn=="GETIMPORT" then
						local imp=tostring(consts[ed[1]+1] and consts[ed[1]+1].value or "")
						imp=imp:gsub("%.%.+","."):gsub("^%.",""):gsub("%.$","")
						local totalIdx = bit32.rshift(ed[2] or 0, 30)
						if totalIdx==1 and options.ListUsedGlobals and isValidGlobal(imp) then
							table.insert(usedGlobals,imp); usedGlobalsSet[imp]=true
						end
						emit(R(ur[1]).." = "..imp)
					elseif opn=="GETTABLE" then
						emit(R(ur[1]).." = "..R(ur[2]).."["..R(ur[3]).."]")
					elseif opn=="SETTABLE" then
						emit(R(ur[2]).."["..R(ur[3]).."] = "..R(ur[1]))
					elseif opn=="GETTABLEKS" then
						local key = consts[ed[2]+1] and consts[ed[2]+1].value
						emit(R(ur[1]).." = "..R(ur[2])..formatIndexString(key))
					elseif opn=="SETTABLEKS" then
						local key = consts[ed[2]+1] and consts[ed[2]+1].value
						emit(R(ur[2])..formatIndexString(key).." = "..R(ur[1]))
					elseif opn=="GETTABLEN" then
						emit(R(ur[1]).." = "..R(ur[2]).."["..(ed[1]+1).."]")
					elseif opn=="SETTABLEN" then
						emit(R(ur[2]).."["..(ed[1]+1).."] = "..R(ur[1]))
					elseif opn=="NEWCLOSURE" then
						local p2=inner[ed[1]+1]; if p2 then writeProto(ur[1],p2) end
					elseif opn=="DUPCLOSURE" then
						local c=consts[ed[1]+1]
						if c then
							local p2=protoTable[c.value-1]; if p2 then writeProto(ur[1],p2) end
						end
					elseif opn=="NAMECALL" then
						if not options.CleanMode then
							local method=tostring(consts[ed[2]+1] and consts[ed[2]+1].value or "")
							emit("-- :"..method)
						end
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
						if nRes==-1 then
							callBody=""
						elseif nRes>0 then
							local rb=""
							for k=1,nRes do
								rb..=R(baseR+k-1)
								if k~=nRes then rb..=", " end
							end
							callBody=rb.." = "
						end
						callBody ..= R(baseR)..nmMethod.."("
						if nArgs==-1 then callBody..="..."
						elseif nArgs>0 then
							local ab=""
							for k=1,nArgs do
								ab..=R(baseR+k+argOff)
								if k~=nArgs then ab..=", " end
							end
							callBody..=ab
						end
						callBody..=")"
						emit(callBody)
					elseif opn=="RETURN" then
						local baseR=ur[1]; local tot=ed[1]-2
						local rb=""
						if tot==-2 then rb=" "..R(baseR)..", ..."
						elseif tot>-1 then
							rb=" "
							for k=0,tot do
								rb..=R(baseR+k)
								if k~=tot then rb..=", " end
							end
						end
						emit("return"..rb)
					elseif opn=="JUMP" then emit("-- jump to #"..(i+ed[1]))
					elseif opn=="JUMPBACK" then emit("-- jump back to #"..(i+ed[1]+1))
					elseif opn=="JUMPIF" then
						local ei=i+ed[1]; makeJump(ei)
						emit("if not "..R(ur[1]).." then -- goto #"..ei)
					elseif opn=="JUMPIFNOT" then
						local ei=i+ed[1]; makeJump(ei)
						emit("if "..R(ur[1]).." then -- goto #"..ei)
					elseif opn=="JUMPIFEQ" then
						local ei=i+ed[1]; makeJump(ei)
						emit("if "..R(ur[1]).." == "..R(ur[2]).." then -- goto #"..ei)
					elseif opn=="JUMPIFLE" then
						local ei=i+ed[1]; makeJump(ei)
						emit("if "..R(ur[1]).." >= "..R(ur[2]).." then -- goto #"..ei)
					elseif opn=="JUMPIFLT" then
						local ei=i+ed[1]; makeJump(ei)
						emit("if "..R(ur[1]).." > "..R(ur[2]).." then -- goto #"..ei)
					elseif opn=="JUMPIFNOTEQ" then
						local ei=i+ed[1]; makeJump(ei)
						emit("if "..R(ur[1]).." ~= "..R(ur[2]).." then -- goto #"..ei)
					elseif opn=="JUMPIFNOTLE" then
						local ei=i+ed[1]; makeJump(ei)
						emit("if "..R(ur[1]).." <= "..R(ur[2]).." then -- goto #"..ei)
					elseif opn=="JUMPIFNOTLT" then
						local ei=i+ed[1]; makeJump(ei)
						emit("if "..R(ur[1]).." < "..R(ur[2]).." then -- goto #"..ei)
					elseif opn=="ADD"  then emit(R(ur[1]).." = "..R(ur[2]).." + "..R(ur[3]))
					elseif opn=="SUB"  then emit(R(ur[1]).." = "..R(ur[2]).." - "..R(ur[3]))
					elseif opn=="MUL"  then emit(R(ur[1]).." = "..R(ur[2]).." * "..R(ur[3]))
					elseif opn=="DIV"  then emit(R(ur[1]).." = "..R(ur[2]).." / "..R(ur[3]))
					elseif opn=="MOD"  then emit(R(ur[1]).." = "..R(ur[2]).." % "..R(ur[3]))
					elseif opn=="POW"  then emit(R(ur[1]).." = "..R(ur[2]).." ^ "..R(ur[3]))
					elseif opn=="ADDK" then emit(R(ur[1]).." = "..R(ur[2]).." + "..fmtConst(consts[ed[1]+1]))
					elseif opn=="SUBK" then emit(R(ur[1]).." = "..R(ur[2]).." - "..fmtConst(consts[ed[1]+1]))
					elseif opn=="MULK" then emit(R(ur[1]).." = "..R(ur[2]).." * "..fmtConst(consts[ed[1]+1]))
					elseif opn=="DIVK" then emit(R(ur[1]).." = "..R(ur[2]).." / "..fmtConst(consts[ed[1]+1]))
					elseif opn=="MODK" then emit(R(ur[1]).." = "..R(ur[2]).." % "..fmtConst(consts[ed[1]+1]))
					elseif opn=="POWK" then emit(R(ur[1]).." = "..R(ur[2]).." ^ "..fmtConst(consts[ed[1]+1]))
					elseif opn=="AND"  then emit(R(ur[1]).." = "..R(ur[2]).." and "..R(ur[3]))
					elseif opn=="OR"   then emit(R(ur[1]).." = "..R(ur[2]).." or "..R(ur[3]))
					elseif opn=="ANDK" then emit(R(ur[1]).." = "..R(ur[2]).." and "..fmtConst(consts[ed[1]+1]))
					elseif opn=="ORK"  then emit(R(ur[1]).." = "..R(ur[2]).." or "..fmtConst(consts[ed[1]+1]))
					elseif opn=="CONCAT" then
						local tgt=table.remove(ur,1)
						local cb=""
						for k,r in ipairs(ur) do
							cb..=fmtReg(r); if k~=#ur then cb..=" .. " end
						end
						emit(R(tgt).." = "..cb)
					elseif opn=="NOT"    then emit(R(ur[1]).." = not "..R(ur[2]))
					elseif opn=="MINUS"  then emit(R(ur[1]).." = -"..R(ur[2]))
					elseif opn=="LENGTH" then emit(R(ur[1]).." = #"..R(ur[2]))
					elseif opn=="NEWTABLE" then
						emit(R(ur[1]).." = {}")
						if options.ShowDebugInformation and ed[2] and ed[2]>0 then
							emit(" ")
						end
					elseif opn=="DUPTABLE" then
						local cv=consts[ed[1]+1]
						if cv and type(cv.value)=="table" then
							local tb="{"
							for k=1,cv.value.size do
								tb..=fmtConst(consts[cv.value.keys[k]])
								if k~=cv.value.size then tb..=", " end
							end
							emit(R(ur[1]).." = {} -- "..tb.."}")
						else emit(R(ur[1]).." = {}") end
					elseif opn=="SETLIST" then
						local tgt=ur[1]; local src=ur[2]
						local si=ed[1]; local vc=ed[2]
						if vc==0 then
							emit(R(tgt).."["..si.."] = [...]")
						else
							local tot2=#ur-1; local cb=""
							for k=1,tot2 do
								cb..=R(ur[k]).."["..(si+k-1).."] = "..R(src+k-1)
								if k~=tot2 then cb..="\n" end
							end
							emit(cb)
						end
					elseif opn=="FORNPREP" then
						emit("for "..R(ur[3]).." = "..R(ur[3])..", "..R(ur[1])..", "..R(ur[2]).." do -- end at #"..(i+ed[1]))
					elseif opn=="FORNLOOP" then
						emit("end -- iterate + jump to #"..(i+ed[1]))
					elseif opn=="FORGLOOP" then
						emit("end -- iterate + jump to #"..(i+ed[1]))
					elseif opn=="FORGPREP_INEXT" then
						local base=ur[1]
						emit("for "..R(base+3)..", "..R(base+4).." in ipairs("..R(base)..") do")
					elseif opn=="FORGPREP_NEXT" then
						local base=ur[1]
						emit("for "..R(base+3)..", "..R(base+4).." in pairs("..R(base)..") do")
					elseif opn=="FORGPREP" then
						local ei=i+ed[1]+2
						local ea=actions[ei]
						local vb=""
						if ea and ea.usedRegisters and #ea.usedRegisters > 0 then
							for k,r in ipairs(ea.usedRegisters) do
								vb..=fmtReg(r, ei); if k~=#ea.usedRegisters then vb..=", " end
							end
						else
							local baseReg=ur[1]; local nVars=2
							if ea and ea.extraData and ea.extraData[2] then
								nVars=math.max(1, bit32.band(ea.extraData[2], 0xFF))
							end
							local parts={}
							for k=1,nVars do parts[k]=fmtReg(baseReg+2+(k-1), i) end
							vb=table.concat(parts, ", ")
						end
						emit("for "..vb.." in "..R(ur[1]).." do -- end at #"..ei)
					elseif opn=="GETVARARGS" then
						local vc2=ed[1]-1
						local rb=""
						if vc2==-1 then rb=R(ur[1])
						else
							for k=1,vc2 do
								rb..=R(ur[k]); if k~=vc2 then rb..=", " end
							end
						end
						emit(rb.." = ...")
					elseif opn=="PREPVARARGS" then emit("-- ... ; number of fixed args: "..ed[1])
					elseif opn=="LOADKX" then emit(R(ur[1]).." = "..fmtConst(consts[ed[1]+1]))
					elseif opn=="JUMPX"    then emit("-- jump to #"..(i+ed[1]))
					elseif opn=="COVERAGE" then emit("-- coverage ("..ed[1]..")")
					elseif opn=="JUMPXEQKNIL" then
						local rev=bit32.rshift(ed[2] or 0,0x1F)~=1
						local sign=rev and "~=" or "=="
						local ei=i+ed[1]; makeJump(ei)
						emit("if "..R(ur[1]).." "..sign.." nil then -- goto #"..ei)
					elseif opn=="JUMPXEQKB" then
						local val=tostring(toBoolean(bit32.band(ed[2] or 0,1)))
						local rev=bit32.rshift(ed[2] or 0,0x1F)~=1
						local sign=rev and "~=" or "=="
						local ei=i+ed[1]; makeJump(ei)
						emit("if "..R(ur[1]).." "..sign.." "..val.." then -- goto #"..ei)
					elseif opn=="JUMPXEQKN" or opn=="JUMPXEQKS" then
						local cidx=bit32.band(ed[2] or 0,0xFFFFFF)
						local val=fmtConst(consts[cidx+1])
						local rev=bit32.rshift(ed[2] or 0,0x1F)~=1
						local sign=rev and "~=" or "=="
						local ei=i+ed[1]; makeJump(ei)
						emit("if "..R(ur[1]).." "..sign.." "..val.." then -- goto #"..ei)
					elseif opn=="CAPTURE"  then emit("-- upvalue capture")
					elseif opn=="SUBRK"    then emit(R(ur[1]).." = "..fmtConst(consts[ed[1]+1]).." - "..R(ur[2]))
					elseif opn=="DIVRK"    then emit(R(ur[1]).." = "..fmtConst(consts[ed[1]+1]).." / "..R(ur[2]))
					elseif opn=="IDIV"     then emit(R(ur[1]).." = "..R(ur[2]).." // "..R(ur[3]))
					elseif opn=="IDIVK"    then emit(R(ur[1]).." = "..R(ur[2]).." // "..fmtConst(consts[ed[1]+1]))
					elseif opn=="FASTCALL" then emit("-- FASTCALL; "..Luau:GetBuiltinInfo(ed[1]).."()")
					elseif opn=="FASTCALL1" then emit("-- FASTCALL1; "..Luau:GetBuiltinInfo(ed[1]).."("..R(ur[1])..")")
					elseif opn=="FASTCALL2" then emit("-- FASTCALL2; "..Luau:GetBuiltinInfo(ed[1]).."("..R(ur[1])..", "..R(ur[2])..")")
					elseif opn=="FASTCALL2K" then
						emit("-- FASTCALL2K; "..Luau:GetBuiltinInfo(ed[1]).."("..R(ur[1])..", "..fmtConst(consts[(ed[3] or 0)+1])..")")
					elseif opn=="FASTCALL3" then
						emit("-- FASTCALL3; "..Luau:GetBuiltinInfo(ed[1]).."("..R(ur[1])..", "..R(ur[2])..", "..R(ur[3])..")")
					end
					emit("\n")
					handleJumps()
				end
			end
			writeActions(registerActions[mainProtoId])
			finalResult = processResult(table.concat(resultParts))
elseif options.DecompilerMode == "lift" then
    local resultParts = {}
    local function emit(s) resultParts[#resultParts + 1] = s end
    local indent = 0
    local function ind() return string.rep("    ", indent) end
    local function emitLine(s) emit(ind() .. s .. "\n") end
    local BINOP = {
        ADD="+", SUB="-", MUL="*", DIV="/", MOD="%", POW="^",
        ADDK="+", SUBK="-", MULK="*", DIVK="/", MODK="%", POWK="^",
        IDIV="//", IDIVK="//",
        AND="and", OR="or", ANDK="and", ORK="or",
        CONCAT="..",
    }
    local UNOP = { NOT="not ", MINUS="-", LENGTH="#" }
    local CMPOP = {
        JUMPIFEQ="==", JUMPIFLE=">=", JUMPIFLT=">",
        JUMPIFNOTEQ="~=", JUMPIFNOTLE="<=", JUMPIFNOTLT="<",
    }
    local CMPOP_INV = {
        JUMPIFEQ="~=", JUMPIFLE="<", JUMPIFLT="<=",
        JUMPIFNOTEQ="==", JUMPIFNOTLE=">=", JUMPIFNOTLT=">",
    }
    local function analyzeFlow(actions)
        local fwdJumps  = {}
        local backJumps = {}
        local loopHeads = {}
        local loopEnds  = {}
        for i, action in ipairs(actions) do
            if action.hide then continue end
            local opn = action.opCode and action.opCode.name
            if not opn then continue end
            local ed = action.extraData
            if CMPOP[opn] or opn == "JUMPIF" or opn == "JUMPIFNOT"
                or opn == "JUMPXEQKNIL" or opn == "JUMPXEQKB"
                or opn == "JUMPXEQKN"   or opn == "JUMPXEQKS" then
                local offset = ed and ed[1] or 0
                local tgt = i + offset
                if tgt > i then
                    fwdJumps[i] = tgt
                elseif tgt <= i then
                    backJumps[i] = tgt
                    loopHeads[tgt] = true
                    loopEnds[tgt] = i
                end
            elseif opn == "JUMP" or opn == "JUMPX" then
                local offset = ed and ed[1] or 0
                local tgt = i + offset
                if tgt < i then
                    backJumps[i] = tgt
                    loopHeads[tgt] = true
                    loopEnds[tgt] = i
                end
            elseif opn == "FORNPREP" then
                local offset = ed and ed[1] or 0
                local tgt = i + offset
                loopHeads[i] = true
                loopEnds[i]  = tgt
            elseif opn == "FORGPREP" or opn == "FORGPREP_INEXT" or opn == "FORGPREP_NEXT" then
                local offset = (opn == "FORGPREP") and (ed and ed[1] or 0) or 0
                loopHeads[i] = true
                loopEnds[i]  = i + math.abs(offset) + 4
            end
        end
        return fwdJumps, backJumps, loopHeads, loopEnds
    end
    local function emitProto(protoActions, isMain)
        local actions  = protoActions.actions
        local proto    = protoActions.proto
        local consts   = proto.constants
        local caps     = proto.captures
        local inner    = proto.innerProtos
        local regExpr  = {}
        local declared = {}
        local pending  = {}
        local totalParameters = proto.numParams
        local function buildRegNames(instrIdx)
            local names = {}
            if proto.debugLocals then
                for _, dl in ipairs(proto.debugLocals) do
                    if instrIdx >= dl.startPC and instrIdx <= dl.endPC then
                        names[dl.register] = dl.name
                    end
                end
            end
            return names
        end
        local regNameCache = {}
        local function fmtReg(r, instrIdx)
            if instrIdx and proto.debugLocals then
                local cached = regNameCache[instrIdx]
                if not cached then
                    cached = buildRegNames(instrIdx)
                    regNameCache[instrIdx] = cached
                end
                if cached[r] and cached[r] ~= "" then return cached[r] end
            end
            local pr = r + 1
            if pr <= totalParameters then return "p" .. pr end
            return "v" .. (r - totalParameters + 1)
        end
        local function fmtUpv(r)
            if r == nil then return "upv_unknown" end
            local du = proto.debugUpvalues
            if du then
                local entry = du[r + 1]
                if entry and entry.name and entry.name ~= "" then return entry.name end
            end
            local capturedReg = caps[r]
            if capturedReg ~= nil and proto.debugLocals then
                for _, dl in ipairs(proto.debugLocals) do
                    if dl.register == capturedReg and dl.name and dl.name ~= "" then
                        return dl.name
                    end
                end
            end
            return "upv_" .. tostring(r)
        end
        local function fmtConst(k)
            if not k then return "nil" end
            if k.type == LuauBytecodeTag.LBC_CONSTANT_VECTOR then return tostring(k.value) end
            if type(tonumber(k.value)) == "number" then
                return tostring(tonumber(string.format("%0." .. options.ReaderFloatPrecision .. "f", k.value)))
            end
            return toEscapedString(k.value)
        end
        local function getReg(r, instrIdx)
            local e = regExpr[r]
            if e then return e end
            return fmtReg(r, instrIdx)
        end
        local function setReg(r, expr)
            regExpr[r] = expr
            pending[r]  = true
        end
        local function clearReg(r)
            regExpr[r] = nil
            pending[r]  = nil
        end
        local function flushReg(r, instrIdx)
            local expr = regExpr[r]
            if not expr then return end
            local name = fmtReg(r, instrIdx)
            if not declared[r] then
                declared[r] = true
                emitLine("local " .. name .. " = " .. expr)
            else
                emitLine(name .. " = " .. expr)
            end
            clearReg(r)
        end
        local function flushAll(instrIdx)
            for r = 0, proto.maxStackSize - 1 do
                if pending[r] then flushReg(r, instrIdx) end
            end
        end
        local fwdJumps, backJumps, loopHeads, loopEnds = analyzeFlow(actions)
        local scopeStack = {}
        local function pushScope(kind, endIdx, elseIdx)
            table.insert(scopeStack, { kind=kind, endIdx=endIdx, elseIdx=elseIdx })
        end
        local function popScope()
            return table.remove(scopeStack)
        end
        if not isMain then
            local paramParts = {}
            for j = 0, proto.numParams - 1 do
                local name = fmtReg(j, 0)
                if proto.hasTypeInfo and proto.typedParams and proto.typedParams[j+1] then
                    name = name .. ": " .. Luau:GetBaseTypeString(proto.typedParams[j+1], true)
                end
                paramParts[#paramParts + 1] = name
            end
            if proto.isVarArg then paramParts[#paramParts + 1] = "..." end
            for j = 0, proto.numParams - 1 do declared[j] = true end
        end
        local skipNext = false
        for i, action in ipairs(actions) do
            if skipNext then skipNext = false; continue end
            if action.hide then continue end
            local oci = action.opCode
            if not oci then continue end
            local opn = oci.name
            local ur  = action.usedRegisters
            local ed  = action.extraData
            for si = #scopeStack, 1, -1 do
                local sc = scopeStack[si]
                if sc.endIdx and i > sc.endIdx then
                    popScope()
                    indent = math.max(0, indent - 1)
                    if sc.kind ~= "repeat" then
                        emitLine("end")
                    end
                elseif sc.elseIdx and i == sc.elseIdx then
                    indent = math.max(0, indent - 1)
                    emitLine("else")
                    indent = indent + 1
                    sc.elseIdx = nil
                end
            end
            if opn == "LOADNIL" then
                setReg(ur[1], "nil")
            elseif opn == "LOADB" then
                setReg(ur[1], toEscapedString(toBoolean(ed[1])))
            elseif opn == "LOADN" then
                setReg(ur[1], tostring(ed[1]))
            elseif opn == "LOADK" or opn == "LOADKX" then
                local cidx = (opn == "LOADKX") and ed[1] or ed[1]
                setReg(ur[1], fmtConst(consts[cidx + 1]))
            elseif opn == "MOVE" then
                local src = regExpr[ur[2]]
                if src then
                    setReg(ur[1], src)
                    clearReg(ur[2])
                else
                    setReg(ur[1], fmtReg(ur[2], i))
                end
            elseif opn == "GETGLOBAL" then
                local gk = tostring(consts[ed[1] + 1] and consts[ed[1] + 1].value or "")
                if options.ListUsedGlobals and isValidGlobal(gk) then
                    table.insert(usedGlobals, gk); usedGlobalsSet[gk] = true
                end
                setReg(ur[1], gk)
            elseif opn == "SETGLOBAL" then
                flushAll(i)
                local gk = tostring(consts[ed[1] + 1] and consts[ed[1] + 1].value or "")
                emitLine(gk .. " = " .. getReg(ur[1], i))
                clearReg(ur[1])
            elseif opn == "GETUPVAL" then
                setReg(ur[1], fmtUpv(caps[ed[1]]))
            elseif opn == "SETUPVAL" then
                flushAll(i)
                emitLine(fmtUpv(caps[ed[1]]) .. " = " .. getReg(ur[1], i))
                clearReg(ur[1])
            elseif opn == "GETIMPORT" then
                local imp = tostring(consts[ed[1] + 1] and consts[ed[1] + 1].value or "")
                imp = imp:gsub("%.%.+", "."):gsub("^%.", ""):gsub("%.$", "")
                local totalIdx = bit32.rshift(ed[2] or 0, 30)
                if totalIdx == 1 and options.ListUsedGlobals and isValidGlobal(imp) then
                    table.insert(usedGlobals, imp); usedGlobalsSet[imp] = true
                end
                setReg(ur[1], imp)
            elseif opn == "GETTABLE" then
                setReg(ur[1], getReg(ur[2], i) .. "[" .. getReg(ur[3], i) .. "]")
            elseif opn == "SETTABLE" then
                flushAll(i)
                emitLine(getReg(ur[2], i) .. "[" .. getReg(ur[3], i) .. "] = " .. getReg(ur[1], i))
            elseif opn == "GETTABLEKS" then
                local key = consts[ed[2] + 1] and consts[ed[2] + 1].value
                setReg(ur[1], getReg(ur[2], i) .. formatIndexString(key))
            elseif opn == "SETTABLEKS" then
                flushAll(i)
                local key = consts[ed[2] + 1] and consts[ed[2] + 1].value
                emitLine(getReg(ur[2], i) .. formatIndexString(key) .. " = " .. getReg(ur[1], i))
                clearReg(ur[1])
            elseif opn == "GETTABLEN" then
                setReg(ur[1], getReg(ur[2], i) .. "[" .. (ed[1] + 1) .. "]")
            elseif opn == "SETTABLEN" then
                flushAll(i)
                emitLine(getReg(ur[2], i) .. "[" .. (ed[1] + 1) .. "] = " .. getReg(ur[1], i))
            elseif opn == "NEWTABLE" or opn == "DUPTABLE" then
                setReg(ur[1], "{}")
            elseif opn == "SETLIST" then
                local tblReg = ur[1]
                local tblExpr = regExpr[tblReg]
                local parts = {}
                local vc = ed[2]
                if vc and vc > 0 then
                    for k = 2, #ur do
                        parts[#parts + 1] = getReg(ur[k], i)
                    end
                end
                if tblExpr == "{}" and #parts > 0 then
                    setReg(tblReg, "{" .. table.concat(parts, ", ") .. "}")
                else
                    flushAll(i)
                end
            elseif BINOP[opn] then
                local op = BINOP[opn]
                local isK = opn:sub(-1) == "K"
                local lhs, rhs
                if opn == "CONCAT" then
                    local parts = {}
                    for k = 2, #ur do parts[#parts + 1] = getReg(ur[k], i) end
                    setReg(ur[1], table.concat(parts, " .. "))
                elseif opn == "SUBRK" or opn == "DIVRK" then
                    lhs = fmtConst(consts[ed[1] + 1])
                    rhs = getReg(ur[2], i)
                    setReg(ur[1], lhs .. " " .. op .. " " .. rhs)
                elseif isK then
                    lhs = getReg(ur[2], i)
                    rhs = fmtConst(consts[ed[1] + 1])
                    setReg(ur[1], lhs .. " " .. op .. " " .. rhs)
                else
                    lhs = getReg(ur[2], i)
                    rhs = getReg(ur[3], i)
                    setReg(ur[1], lhs .. " " .. op .. " " .. rhs)
                end
            elseif UNOP[opn] then
                local op = UNOP[opn]
                local src = getReg(ur[2], i)
                if src:find("[%s%(]") then src = "(" .. src .. ")" end
                setReg(ur[1], op .. src)
            elseif opn == "NEWCLOSURE" or opn == "DUPCLOSURE" then
                local p2
                if opn == "NEWCLOSURE" then
                    p2 = inner[ed[1] + 1]
                else
                    local c = consts[ed[1] + 1]
                    if c then p2 = protoTable[c.value - 1] end
                end
                if p2 and registerActions[p2.id] then
                    local pActions = registerActions[p2.id]
                    local pProto   = pActions.proto
                    local paramParts = {}
                    for j = 0, pProto.numParams - 1 do
                        local nm
                        if pProto.debugLocals then
                            for _, dl in ipairs(pProto.debugLocals) do
                                if dl.startPC == 0 and dl.register == j then nm = dl.name; break end
                            end
                        end
                        paramParts[#paramParts + 1] = nm or ("p" .. (j + 1))
                    end
                    if pProto.isVarArg then paramParts[#paramParts + 1] = "..." end
                    local header = "function(" .. table.concat(paramParts, ", ") .. ")\n"
                    local savedParts = resultParts
                    local savedIndent = indent
                    resultParts = {}
                    indent = 0
                    emitProto(pActions, false)
                    local innerSrc = table.concat(resultParts)
                    resultParts = savedParts
                    indent = savedIndent
                    local indented = ""
                    for line in (innerSrc .. "\n"):gmatch("[^\n]*\n") do
                        indented = indented .. ind() .. "    " .. line
                    end
                    setReg(ur[1], header .. indented .. ind() .. "end")
                else
                    setReg(ur[1], "function(...)  end")
                end
            elseif opn == "NAMECALL" then
                local method = tostring(consts[ed[2] + 1] and consts[ed[2] + 1].value or "")
                setReg(ur[1], getReg(ur[2], i) .. ":" .. method)
            elseif opn == "CALL" then
                flushAll(i)
                local baseR = ur[1]
                local nArgs = ed[1] - 1
                local nRes  = ed[2] - 1
                local funcExpr = getReg(baseR, i)
                local argParts = {}
                if nArgs == -1 then
                    argParts[1] = "..."
                else
                    for k = 1, nArgs do
                        argParts[k] = getReg(baseR + k, i)
                    end
                end
                local callExpr = funcExpr .. "(" .. table.concat(argParts, ", ") .. ")"
                if nRes == 0 then
                    emitLine(callExpr)
                    clearReg(baseR)
                elseif nRes == 1 then
                    setReg(baseR, callExpr)
                elseif nRes == -1 then
                    emitLine(callExpr)
                    clearReg(baseR)
                else
                    local lhsParts = {}
                    for k = 0, nRes - 1 do
                        local nm = fmtReg(baseR + k, i)
                        if not declared[baseR + k] then
                            declared[baseR + k] = true
                            nm = "local " .. nm
                        end
                        lhsParts[k + 1] = nm
                    end
                    emitLine(table.concat(lhsParts, ", ") .. " = " .. callExpr)
                    for k = 0, nRes - 1 do clearReg(baseR + k) end
                end
            elseif opn == "RETURN" then
                flushAll(i)
                local baseR = ur[1]
                local tot   = ed[1] - 2
                if tot == -2 then
                    emitLine("return " .. getReg(baseR, i) .. ", ...")
                elseif tot >= 0 then
                    local parts = {}
                    for k = 0, tot do parts[k + 1] = getReg(baseR + k, i) end
                    if #parts > 0 then
                        emitLine("return " .. table.concat(parts, ", "))
                    elseif not isMain then
                        emitLine("return")
                    end
                end
                for k = 0, math.max(0, tot) do clearReg(baseR + k) end
            elseif opn == "FORNPREP" then
                flushAll(i)
                local base   = ur[1]
                local limit  = getReg(ur[2], i)
                local step   = getReg(ur[3], i)
                local var    = getReg(ur[3], i)
                local ctr    = fmtReg(base + 2, i)
                local from   = getReg(base, i)
                local to2    = getReg(base + 1, i)
                local step2  = getReg(base + 2, i)
                local forLine = "for " .. ctr .. " = " .. from .. ", " .. to2
                if step2 ~= "1" and step2 ~= "" and step2 ~= ctr then
                    forLine = forLine .. ", " .. step2
                end
                forLine = forLine .. " do"
                emitLine(forLine)
                indent = indent + 1
                pushScope("for", loopEnds[i] and (loopEnds[i] + 1) or (i + 100))
            elseif opn == "FORNLOOP" then
            elseif opn == "FORGPREP_INEXT" then
                flushAll(i)
                local base = ur[1]
                local k    = fmtReg(base + 3, i)
                local v    = fmtReg(base + 4, i)
                emitLine("for " .. k .. ", " .. v .. " in ipairs(" .. getReg(base, i) .. ") do")
                indent = indent + 1
                pushScope("for", loopEnds[i] and (loopEnds[i] + 1) or (i + 50))
            elseif opn == "FORGPREP_NEXT" then
                flushAll(i)
                local base = ur[1]
                local k    = fmtReg(base + 3, i)
                local v    = fmtReg(base + 4, i)
                emitLine("for " .. k .. ", " .. v .. " in pairs(" .. getReg(base, i) .. ") do")
                indent = indent + 1
                pushScope("for", loopEnds[i] and (loopEnds[i] + 1) or (i + 50))
            elseif opn == "FORGPREP" then
                flushAll(i)
                local base   = ur[1]
                local offset = ed and ed[1] or 0
                local endIdx = i + math.abs(offset) + 2
                local vParts = {}
                local flAction = actions[endIdx]
                if flAction and flAction.opCode and flAction.opCode.name == "FORGLOOP" then
                    local nv = bit32.band(flAction.extraData and flAction.extraData[2] or 0, 0xFF)
                    for k = 1, nv do
                        vParts[k] = fmtReg(base + 2 + k, i)
                    end
                end
                if #vParts == 0 then vParts = { fmtReg(base + 3, i), fmtReg(base + 4, i) } end
                emitLine("for " .. table.concat(vParts, ", ") .. " in " .. getReg(base, i) .. " do")
                indent = indent + 1
                pushScope("for", endIdx + 1)
            elseif opn == "FORGLOOP" then
            elseif CMPOP[opn] then
                flushAll(i)
                local op   = CMPOP_INV[opn]
                local lhs  = getReg(ur[1], i)
                local rhs  = getReg(ur[2], i)
                local tgt  = fwdJumps[i]
                local elseIdx = nil
                if tgt then
                    local skipAction = actions[tgt - 1]
                    if skipAction and skipAction.opCode and
                       (skipAction.opCode.name == "JUMP" or skipAction.opCode.name == "JUMPX") then
                        local skipOffset = skipAction.extraData and skipAction.extraData[1] or 0
                        elseIdx = tgt
                        tgt     = tgt + skipOffset
                    end
                end
                emitLine("if " .. lhs .. " " .. op .. " " .. rhs .. " then")
                indent = indent + 1
                pushScope("if", tgt and (tgt - 1) or (i + 20), elseIdx)
            elseif opn == "JUMPIF" then
                flushAll(i)
                local tgt = fwdJumps[i]
                local elseIdx = nil
                if tgt then
                    local skipAction = actions[tgt - 1]
                    if skipAction and skipAction.opCode and
                       (skipAction.opCode.name == "JUMP" or skipAction.opCode.name == "JUMPX") then
                        local skipOffset = skipAction.extraData and skipAction.extraData[1] or 0
                        elseIdx = tgt
                        tgt     = tgt + skipOffset
                    end
                end
                emitLine("if not " .. getReg(ur[1], i) .. " then")
                indent = indent + 1
                pushScope("if", tgt and (tgt - 1) or (i + 10), elseIdx)
            elseif opn == "JUMPIFNOT" then
                flushAll(i)
                local tgt = fwdJumps[i]
                local elseIdx = nil
                if tgt then
                    local skipAction = actions[tgt - 1]
                    if skipAction and skipAction.opCode and
                       (skipAction.opCode.name == "JUMP" or skipAction.opCode.name == "JUMPX") then
                        local skipOffset = skipAction.extraData and skipAction.extraData[1] or 0
                        elseIdx = tgt
                        tgt     = tgt + skipOffset
                    end
                end
                emitLine("if " .. getReg(ur[1], i) .. " then")
                indent = indent + 1
                pushScope("if", tgt and (tgt - 1) or (i + 10), elseIdx)
            elseif opn == "JUMPXEQKNIL" then
                flushAll(i)
                local rev  = bit32.rshift(ed[2] or 0, 0x1F) ~= 1
                local sign = rev and "~=" or "=="
                local tgt  = fwdJumps[i]
                emitLine("if " .. getReg(ur[1], i) .. " " .. sign .. " nil then")
                indent = indent + 1
                pushScope("if", tgt and (tgt - 1) or (i + 10))
            elseif opn == "JUMPXEQKB" then
                flushAll(i)
                local val  = tostring(toBoolean(bit32.band(ed[2] or 0, 1)))
                local rev  = bit32.rshift(ed[2] or 0, 0x1F) ~= 1
                local sign = rev and "~=" or "=="
                local tgt  = fwdJumps[i]
                emitLine("if " .. getReg(ur[1], i) .. " " .. sign .. " " .. val .. " then")
                indent = indent + 1
                pushScope("if", tgt and (tgt - 1) or (i + 10))
            elseif opn == "JUMPXEQKN" or opn == "JUMPXEQKS" then
                flushAll(i)
                local cidx = bit32.band(ed[2] or 0, 0xFFFFFF)
                local val  = fmtConst(consts[cidx + 1])
                local rev  = bit32.rshift(ed[2] or 0, 0x1F) ~= 1
                local sign = rev and "~=" or "=="
                local tgt  = fwdJumps[i]
                emitLine("if " .. getReg(ur[1], i) .. " " .. sign .. " " .. val .. " then")
                indent = indent + 1
                pushScope("if", tgt and (tgt - 1) or (i + 10))
            elseif opn == "JUMP" or opn == "JUMPX" or opn == "JUMPBACK" then
                flushAll(i)
            elseif opn == "GETVARARGS" then
                local vc2 = ed[1] - 1
                if vc2 == -1 then
                    setReg(ur[1], "...")
                else
                    local parts = {}
                    for k = 1, vc2 do parts[k] = fmtReg(ur[k], i) end
                    flushAll(i)
                    local lhsParts = {}
                    for k = 1, vc2 do
                        local r = ur[k]
                        if not declared[r] then declared[r] = true
                            lhsParts[k] = "local " .. fmtReg(r, i)
                        else lhsParts[k] = fmtReg(r, i) end
                    end
                    emitLine(table.concat(lhsParts, ", ") .. " = ...")
                end
            else
            end
        end
        for si = #scopeStack, 1, -1 do
            local sc = scopeStack[si]
            indent = math.max(0, indent - 1)
            if sc.kind ~= "repeat" then emitLine("end") end
        end
        flushAll(0)
    end
    local mainProtoActions = registerActions[mainProtoId]
    if mainProtoActions then
        if mainProtoActions.proto.flags and mainProtoActions.proto.flags.native then
            emit("--!native\n")
        end
        emitProto(mainProtoActions, true)
    end
    finalResult = processResult(table.concat(resultParts))		end
		return finalResult
	end
	local function manager(proceed, issue)
		if proceed then
			local startTime = os.clock()
			local result
			local ok, res = pcall(function() return finalize(organize()) end)
			result = ok and res or ("-- RUNTIME ERROR:\n-- " .. tostring(res))
			if (os.clock() - startTime) >= options.DecompilerTimeout then
				return Strings.TIMEOUT
			end
			return string.format(Strings.SUCCESS, result)
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
	w("_zukatechzukatech_zukatechzukatechhzukatech_")
	w("  code reconstructor — "..(scriptName or "unknown"))
	w("_zukatechzukatech_zukatechzukatechhzukatech_")
	w("  Luau version : "..parsed.version)
	w("  Types version: "..parsed.typesVersion)
	w("  Proto count  : "..#parsed.protos)
	w("  Entry proto  : #"..parsed.entryProto)
	w("  Strings total: "..#parsed.stringTable)
	for i,s in ipairs(parsed.stringTable) do w(string.format("  [%3d] %q",i,s)) end
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
	w("- PROTO TREE -")
	for i,proto in ipairs(parsed.protos) do walkProto(proto,i) end
	return table.concat(lines,"\n")
end
local function _ppImpl(text)
	local result = {}
	local depth  = 0
	local DEDENT_BEFORE      = { ["end"]=true, ["until"]=true }
	local INDENT_AFTER       = { ["then"]=true, ["do"]=true, ["repeat"]=true }
	local DEDENT_THEN_INDENT = { ["else"]=true, ["elseif"]=true }
	local function stripStrings(s)
		s = s:gsub('"[^"\\]*(?:\\.[^"\\]*)*"', '""')
		s = s:gsub("'[^'\\]*(?:\\.[^'\\]*)*'", "''")
		s = s:gsub("%-%-.*$", "")
		return s
	end
	local function firstWord(s)
		return (stripStrings(s):match("^%s*([%a_][%w_]*)")) or ""
	end
	local function containsOpener(s)
		local clean = stripStrings(s)
		local fw = clean:match("^%s*([%a_][%w_]*)")
		if fw == "elseif" or fw == "else" then return false end
		for w in clean:gmatch("[%a_][%w_]*") do
			if INDENT_AFTER[w] then return true end
			if w == "function" then return true end
		end
		return false
	end
	for line in (text .. "\n"):gmatch("[^\n]*\n") do
		local bare = line:gsub("\n$", "")
		if bare == "" then
			result[#result + 1] = "\n"; continue
		end
		local expr = bare:match("^%[%d+%]%s*:?%d*:?%s*%u[%u_]*%s+(.*)") or bare
		local kw = firstWord(expr)
		if DEDENT_THEN_INDENT[kw] then
			depth = math.max(0, depth - 1)
			result[#result + 1] = string.rep("    ", depth) .. bare .. "\n"
			depth += 1
		elseif DEDENT_BEFORE[kw] then
			depth = math.max(0, depth - 1)
			result[#result + 1] = string.rep("    ", depth) .. bare .. "\n"
		else
			result[#result + 1] = string.rep("    ", depth) .. bare .. "\n"
			if containsOpener(expr) then depth += 1 end
		end
	end
	return table.concat(result)
end
local function _coImpl(text)
	local rawLines = {}
	for line in (text .. "\n"):gmatch("[^\n]*\n") do
		rawLines[#rawLines + 1] = line:gsub("\n$", "")
	end
	local function escpat(s)
		return s:gsub("([%(%)%.%%%+%-%*%?%[%^%$])", "%%%1")
	end
	local function nextNonBlank(start)
		local j = start
		while j <= #rawLines and (rawLines[j] == nil or rawLines[j]:match("^%s*$")) do
			j += 1
		end
		return j
	end
	local function tryCollapse(i)
		local line = rawLines[i]
		if line == nil then return false end
		local reg, lit = line:match('^%s*(v%d+) = (".-")%s*$')
		if not reg then reg, lit = line:match('^%s*(v%d+) = (%-?%d+%.?%d*)%s*$') end
		if not reg then reg, lit = line:match('^%s*(v%d+) = (true)%s*$') end
		if not reg then reg, lit = line:match('^%s*(v%d+) = (false)%s*$') end
		if not reg then reg, lit = line:match('^%s*(v%d+) = (nil)%s*$') end
		if not reg then reg, lit = line:match('^%s*(v%d+) = ([%a_][%w_%.]+)%s*$') end
		if not reg then return false end
		local j = nextNonBlank(i + 1)
		if j > #rawLines or rawLines[j] == nil then return false end
		local nextLine = rawLines[j]
		local ep = escpat(reg)
		local count = 0
		for _ in nextLine:gmatch(ep) do count += 1 end
		if count ~= 1 then return false end
		if nextLine:match("^%s*" .. ep .. "%s*=") then return false end
		for k = i + 1, j - 1 do
			local mid = rawLines[k]
			if mid and mid:match("^%s*" .. ep .. "%s*=") then return false end
		end
		rawLines[j] = nextLine:gsub(ep, lit, 1)
		rawLines[i] = nil
		return true
	end
	for _ = 1, 8 do
		for i = 1, #rawLines do tryCollapse(i) end
	end
	local function tryFoldField(i)
		local line = rawLines[i]
		if not line then return false end
		local lreg, src, field = line:match('^%s*(v%d+) = (v%d+)%.([%a_][%w_]*)%s*$')
		if not lreg then
			lreg, src, field = line:match('^%s*(v%d+) = (v%d+)%[(.-)%]%s*$')
			if lreg then field = "[" .. field .. "]" else return false end
		else
			field = "." .. field
		end
		local j = nextNonBlank(i + 1)
		if j > #rawLines then return false end
		local nextLine = rawLines[j]
		local epSrc = escpat(src)
		local epReg = escpat(lreg)
		local count = 0
		for _ in nextLine:gmatch(epReg) do count += 1 end
		if count ~= 1 then return false end
		if nextLine:match("^%s*" .. epReg .. "%s*=") then return false end
		for k = i + 1, j - 1 do
			local mid = rawLines[k]
			if mid and mid:match("^%s*" .. epSrc .. "%s*=") then return false end
		end
		if src:match("^upv_") then return false end
		rawLines[j] = nextLine:gsub(epReg, src .. field, 1)
		rawLines[i] = nil
		return true
	end
	for _ = 1, 6 do
		for i = 1, #rawLines do tryFoldField(i) end
	end
	local pass2 = {}
	for idx = 1, #rawLines do
		local line = rawLines[idx]
		if line == nil then continue end
		local stripped = line:match("^%s*(.-)%s*$")
		if stripped:match("^%-%- goto #%d+$") then continue end
		if stripped:match("^%-%- jump") then continue end
		line = line:gsub("%s*%-%- goto #%d+$", "")
		line = line:gsub("%s*%-%- end at #%d+$", "")
		line = line:gsub("%s*%-%- iterate %+ jump to #%d+$", "")
		pass2[#pass2 + 1] = line
	end
	local pass3 = {}
	local i = 1
	while i <= #pass2 do
		local line = pass2[i]
		local nxt  = pass2[i + 1]
		local s    = line and line:match("^%s*(.-)%s*$") or ""
		local isNilInit = s:match("^v%d+ = nil") ~= nil
		local nextIsFor = nxt and nxt:match("^%s*for%s+v%d+") ~= nil
		if isNilInit and nextIsFor then
			i += 1
		else
			pass3[#pass3 + 1] = line
			i += 1
		end
	end
	local seen = {}
	local pass4 = {}
	for _, line in ipairs(pass3) do
		local reg = line:match("^%s*(v%d+)%s*=")
		if reg and not seen[reg] then
			seen[reg] = true
			line = line:gsub("^(%s*)(v%d+%s*=)", "%1local %2", 1)
		end
		pass4[#pass4 + 1] = line
	end
	local final = {}
	local lastBlank = false
	for _, line in ipairs(pass4) do
		local isBlank = line:match("^%s*$") ~= nil
		if isBlank and lastBlank then continue end
		lastBlank = isBlank
		final[#final + 1] = line
	end
	return table.concat(final, "\n")
end
local ZukDecompile = Decompile
local ZukPretty    = _ppImpl
local ZukClean     = _coImpl
local Syntax = {
    Text=Color3.fromRGB(204,204,204), Operator=Color3.fromRGB(204,204,204),
    Number=Color3.fromRGB(255,198,0), String=Color3.fromRGB(173,241,149),
    Comment=Color3.fromRGB(102,102,102), Keyword=Color3.fromRGB(248,109,124),
    BuiltIn=Color3.fromRGB(132,214,247), LocalMethod=Color3.fromRGB(253,251,172),
    LocalProperty=Color3.fromRGB(97,161,241), Nil=Color3.fromRGB(255,198,0),
    Bool=Color3.fromRGB(255,198,0), Function=Color3.fromRGB(248,109,124),
    Local=Color3.fromRGB(248,109,124), Self=Color3.fromRGB(248,109,124),
    FunctionName=Color3.fromRGB(253,251,172), Bracket=Color3.fromRGB(204,204,204),
}
local function colorToHex(c)
    return string.format("#%02x%02x%02x", math.floor(c.R*255), math.floor(c.G*255), math.floor(c.B*255))
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
        elseif c == "[" and line:sub(i,i+1):match("%[=*%[") then
            local eqCount, k = 0, i+1
            while line:sub(k,k) == "=" do eqCount += 1; k += 1 end
            if line:sub(k,k) == "[" then
                local close  = "]"..string.rep("=",eqCount).."]"
                local endIdx = line:find(close, k+1, true)
                local j      = endIdx and (endIdx + #close - 1) or #line
                table.insert(tokens, {line:sub(i,j), "String"}); i = j
            else table.insert(tokens, {c, "Operator"}) end
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
        else table.insert(tokens, {c, "Operator"}) end
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
    if val == "self" then return "Self" end
    if val == "true" or val == "false" then return "Bool" end
    if val == "nil"  then return "Nil"  end
    if idx > 1 and tokens[idx-1][1] == "function" then return "FunctionName" end
    return "Text"
end
local function hlLine(line)
    local tokens = hlTokenize(line)
    local out = ""
    for i, tok in ipairs(tokens) do
        local col  = Syntax[hlDetect(tokens, i)] or Syntax.Text
        local safe = tok[1]:gsub("&","&amp;"):gsub("<","&lt;"):gsub(">","&gt;")
        out ..= string.format('<font color="%s">%s</font>', colorToHex(col), safe)
    end
    return out
end
local ROW_H      = 17
local INDENT_PER = 14
local MIN_SIZE   = Vector2.new(350, 250)
local CLASS_ICONS = {
    Folder=Vector2.new(96,96), Model=Vector2.new(0,32), Part=Vector2.new(128,32),
    MeshPart=Vector2.new(128,32), UnionOperation=Vector2.new(128,32),
    Humanoid=Vector2.new(0,160), Script=Vector2.new(0,64),
    LocalScript=Vector2.new(32,64), ModuleScript=Vector2.new(64,64),
    RemoteEvent=Vector2.new(192,128), RemoteFunction=Vector2.new(224,128),
    Workspace=Vector2.new(0,0), Players=Vector2.new(96,0),
    Lighting=Vector2.new(64,0), ReplicatedStorage=Vector2.new(160,32),
    StarterGui=Vector2.new(128,0),
}
local QUICK_NAV_SERVICES = {
    "Workspace","Players","Lighting","ReplicatedFirst",
    "ReplicatedStorage","StarterGui","StarterPack",
    "StarterPlayer","Teams","SoundService",
}
local SCRIPT_CLASSES = { Script=true, LocalScript=true, ModuleScript=true }
local treeRoot     = game
local expanded     = {}
local selected     = nil
local rows         = {}
local rowFrames    = {}
local scrollOffset = 0
local filterText   = ""
local ctxMenu      = nil
local function hasChildren(inst)
    local ok, ch = pcall(inst.GetChildren, inst)
    return ok and #ch > 0
end
local function closeCtx()
    if ctxMenu then ctxMenu:Destroy(); ctxMenu = nil end
end
local function buildPath(inst)
    local parts = {}
    local cur = inst
    while cur and cur ~= game do
        local ok, name = pcall(function() return cur.Name end)
        table.insert(parts, 1, ok and name or "???")
        cur = cur.Parent
    end
    if #parts == 0 then return "game" end
    local svcName = parts[1]
    local root = ('game:GetService("%s")'):format(svcName)
    if #parts == 1 then return root end
    return root .. "." .. table.concat(parts, ".", 2)
end
local SCREENGUI_SCRIPT_CLASSES = { Script=true, LocalScript=true, ModuleScript=true }
local function serializeVal(v)
    local t = typeof(v)
    if t == "string"  then return string.format("%q", v)
    elseif t == "number" then
        if v == math.floor(v) then return tostring(math.floor(v)) end
        return tostring(v)
    elseif t == "boolean" then return tostring(v)
    elseif t == "nil"     then return "nil"
    elseif t == "Vector3" then return ("Vector3.new(%s,%s,%s)"):format(v.X,v.Y,v.Z)
    elseif t == "Vector2" then return ("Vector2.new(%s,%s)"):format(v.X,v.Y)
    elseif t == "UDim2"   then return ("UDim2.new(%s,%s,%s,%s)"):format(v.X.Scale,v.X.Offset,v.Y.Scale,v.Y.Offset)
    elseif t == "UDim"    then return ("UDim.new(%s,%s)"):format(v.Scale,v.Offset)
    elseif t == "CFrame"  then local c={v:GetComponents()}; return "CFrame.new("..table.concat(c,",")..")"
    elseif t == "Color3"  then return ("Color3.fromRGB(%d,%d,%d)"):format(math.floor(v.R*255),math.floor(v.G*255),math.floor(v.B*255))
    elseif t == "BrickColor" then return ("BrickColor.new(%q)"):format(v.Name)
    elseif t == "EnumItem"   then return tostring(v)
    elseif t == "Rect" then return ("Rect.new(%s,%s,%s,%s)"):format(v.Min.X,v.Min.Y,v.Max.X,v.Max.Y)
    elseif t == "FontFace" then return ("Font.new(%q,Enum.FontWeight.%s,Enum.FontStyle.%s)"):format(v.Family,v.Weight.Name,v.Style.Name)
    elseif t == "NumberRange" then return ("NumberRange.new(%s,%s)"):format(v.Min,v.Max)
    elseif t == "NumberSequence" then
        local kps={}
        for _,kp in ipairs(v.Keypoints) do
            kps[#kps+1]=("NumberSequenceKeypoint.new(%s,%s,%s)"):format(kp.Time,kp.Value,kp.Envelope)
        end
        return "NumberSequence.new({"..table.concat(kps,",").."})";
    elseif t == "ColorSequence" then
        local kps={}
        for _,kp in ipairs(v.Keypoints) do
            kps[#kps+1]=("ColorSequenceKeypoint.new(%s,Color3.fromRGB(%d,%d,%d))"):format(
                kp.Time,math.floor(kp.Value.R*255),math.floor(kp.Value.G*255),math.floor(kp.Value.B*255))
        end
        return "ColorSequence.new({"..table.concat(kps,",").."})";
    end
    return "nil"
end
local GUI_COMMON = {
    "Name","Size","Position","AnchorPoint","Visible","ZIndex","LayoutOrder",
    "BackgroundColor3","BackgroundTransparency","BorderColor3","BorderSizePixel",
    "ClipsDescendants","Active","Selectable","Rotation","AutomaticSize",
}
local function guiMerge(t,extra)
    local r={}; for _,v in ipairs(t) do r[#r+1]=v end
    for _,v in ipairs(extra or {}) do r[#r+1]=v end; return r
end
local GUI_PROP_MAP = {
    ScreenGui={"Name","Enabled","ResetOnSpawn","DisplayOrder","IgnoreGuiInset","ZIndexBehavior","ScreenInsets"},
    TextLabel=guiMerge(GUI_COMMON,{"Text","RichText","TextSize","Font","FontFace","TextColor3","TextTransparency","TextWrapped","TextScaled","TextXAlignment","TextYAlignment","TextTruncate","TextStrokeColor3","TextStrokeTransparency","LineHeight","MaxVisibleGraphemes","AutoLocalize"}),
    TextButton=guiMerge(GUI_COMMON,{"Text","RichText","TextSize","Font","FontFace","TextColor3","TextTransparency","TextWrapped","TextScaled","TextXAlignment","TextYAlignment","TextTruncate","TextStrokeColor3","TextStrokeTransparency","LineHeight","AutoButtonColor","Modal","Style"}),
    TextBox=guiMerge(GUI_COMMON,{"Text","RichText","TextSize","Font","FontFace","TextColor3","TextTransparency","TextWrapped","TextScaled","TextXAlignment","TextYAlignment","PlaceholderText","PlaceholderColor3","ClearTextOnFocus","MultiLine","TextEditable"}),
    Frame=guiMerge(GUI_COMMON,{"Style"}),
    ScrollingFrame=guiMerge(GUI_COMMON,{"CanvasSize","CanvasPosition","ScrollBarThickness","ScrollBarImageColor3","ScrollBarImageTransparency","ScrollingDirection","ScrollingEnabled","VerticalScrollBarInset","HorizontalScrollBarInset","BottomImage","MidImage","TopImage"}),
    ImageLabel=guiMerge(GUI_COMMON,{"Image","ImageColor3","ImageTransparency","ImageRectOffset","ImageRectSize","ResampleMode","ScaleType","SliceCenter","SliceScale","TileSize"}),
    ImageButton=guiMerge(GUI_COMMON,{"Image","ImageColor3","ImageTransparency","ImageRectOffset","ImageRectSize","ResampleMode","ScaleType","SliceCenter","SliceScale","TileSize","HoverImage","PressedImage","Style","AutoButtonColor","Modal"}),
    VideoFrame=guiMerge(GUI_COMMON,{"Video","Looped","Playing","TimePosition","Volume"}),
    ViewportFrame=guiMerge(GUI_COMMON,{"Ambient","LightColor","LightDirection"}),
    UICorner={"CornerRadius"},
    UIStroke={"Color","Thickness","Transparency","LineJoinMode","ApplyStrokeMode","Enabled"},
    UIGradient={"Color","Offset","Rotation","Transparency","Enabled"},
    UIPadding={"PaddingLeft","PaddingRight","PaddingTop","PaddingBottom"},
    UIListLayout={"Padding","FillDirection","HorizontalAlignment","VerticalAlignment","SortOrder","HorizontalFlex","VerticalFlex","ItemLineAlignment","Wraps"},
    UIGridLayout={"CellPadding","CellSize","FillDirectionMaxCells","FillDirection","HorizontalAlignment","VerticalAlignment","SortOrder","StartCorner"},
    UITableLayout={"FillEmptySpaceColumns","FillEmptySpaceRows","FillDirection","HorizontalAlignment","VerticalAlignment","MajorAxis","Padding","SortOrder"},
    UIAspectRatioConstraint={"AspectRatio","AspectType","DominantAxis"},
    UISizeConstraint={"MinSize","MaxSize"},
    UITextSizeConstraint={"MinTextSize","MaxTextSize"},
    UIScale={"Scale"},
    UIFlexItem={"FlexMode","GrowRatio","ShrinkRatio"},
    UIPageLayout={"Animated","CircularEnabled","EasingDirection","EasingStyle","GamepadInputEnabled","Padding","ScrollWheelInputEnabled","SortOrder","TouchInputEnabled","TweenTime","FillDirection","HorizontalAlignment","VerticalAlignment"},
}
local GUI_SKIP_DEFAULTS = {
    Visible=true, BackgroundTransparency=0, TextTransparency=0, ImageTransparency=0,
    TextStrokeTransparency=1, BorderSizePixel=1, ZIndex=1, LayoutOrder=0, Rotation=0,
    AutomaticSize=Enum.AutomaticSize.None, AnchorPoint=Vector2.new(0,0),
    ClipsDescendants=false, Active=false, Selectable=false, RichText=true,
    TextWrapped=true, TextScaled=false, TextXAlignment=Enum.TextXAlignment.Center,
    TextYAlignment=Enum.TextYAlignment.Center, AutoButtonColor=true,
    Enabled=true, ResetOnSpawn=true, DisplayOrder=0, IgnoreGuiInset=false,
}
local function guiShouldSkip(propName, val)
    local def = GUI_SKIP_DEFAULTS[propName]
    if def == nil then return false end
    if typeof(def) ~= typeof(val) then return false end
    if typeof(val) == "Vector2" then return val.X==def.X and val.Y==def.Y end
    return val == def
end
local function getGuiProps(obj)
    return GUI_PROP_MAP[obj.ClassName] or guiMerge(GUI_COMMON,{})
end
local function convertGuiToScript(gui)
    local extractedScripts = {}
    local instanceToVar    = {}
    local flatCounter      = {n=0}
    local function newVar(base)
        flatCounter.n += 1
        local safe = (base or "obj"):gsub("[^%w_]","_"):gsub("^(%d)","_%1")
        return safe.."_"..flatCounter.n
    end
    local codeLines = {}
    local function emit(s) codeLines[#codeLines+1] = s end
    local function extractScript(scriptObj, parentVar)
        local source = ""
        local zuk = getgenv()._ZUK_DECOMPILE
        local okBC, bytecode = pcall(getscriptbytecode, scriptObj)
        if zuk and okBC and bytecode and bytecode ~= "" then
            local opts = {
                DecompilerMode="disasm", DecompilerTimeout=15, CleanMode=true,
                ReaderFloatPrecision=7, ShowDebugInformation=false,
                ShowTrivialOperations=false, ShowInstructionLines=true,
                ShowOperationIndex=true, ShowOperationNames=true,
                ListUsedGlobals=true, UseTypeInfo=true,
                EnabledRemarks={ColdRemark=false,InlineRemark=true},
                ReturnElapsedTime=true,
            }
            local okD, result = pcall(zuk, bytecode, opts)
            if okD and result then
                local pp = getgenv()._ZUK_PRETTYPRINT
                source = pp and pp(result) or result
            end
        end
        if source == "" then
            local ok2, src = pcall(function() return scriptObj.Source end)
            if ok2 and src and src ~= "" then source = src end
        end
        if source == "" and getgenv().decompile then
            local ok3, res = pcall(getgenv().decompile, scriptObj)
            if ok3 and res then source = res end
        end
        if source == "" then
            source = "-- [PROTECTED/EMPTY SCRIPT] Could not extract source\n"
        end
        local enabled = true
        pcall(function() enabled = not scriptObj.Disabled end)
        table.insert(extractedScripts, {
            parent=parentVar, className=scriptObj.ClassName,
            name=scriptObj.Name, source=source, enabled=enabled,
        })
    end
    local function generateGuiCode(obj, parentVar)
        local cls = obj.ClassName
        if cls == "LocalScript" or cls == "Script" or cls == "ModuleScript" then
            extractScript(obj, parentVar); return
        end
        local varName = newVar(obj.Name)
        instanceToVar[obj] = varName
        emit(("local %s = Instance.new(%q)"):format(varName, cls))
        emit(("%s.Parent = %s"):format(varName, parentVar))
        local props = getGuiProps(obj)
        for _, propName in ipairs(props) do
            if propName == "Name" and obj.Name == cls then continue end
            local ok, val = pcall(function() return obj[propName] end)
            if ok and val ~= nil and not guiShouldSkip(propName, val) then
                local s = serializeVal(val)
                if s ~= "nil" then emit(("%s.%s = %s"):format(varName, propName, s)) end
            end
        end
        for _, child in ipairs(obj:GetChildren()) do
            generateGuiCode(child, varName)
        end
    end
    emit('local Players = game:GetService("Players")')
    emit("local player = Players.LocalPlayer")
    emit('local playerGui = player:WaitForChild("PlayerGui")')
    emit("")
    emit("-- GUI Structure")
    emit("local function createGui()")
    local sgVar = newVar(gui.Name)
    instanceToVar[gui] = sgVar
    emit(('\tlocal %s = Instance.new("ScreenGui")'):format(sgVar))
    local sgProps = getGuiProps(gui)
    for _, propName in ipairs(sgProps) do
        local ok, val = pcall(function() return gui[propName] end)
        if ok and val ~= nil and not guiShouldSkip(propName, val) then
            local s = serializeVal(val)
            if s ~= "nil" then emit(("\t%s.%s = %s"):format(sgVar, propName, s)) end
        end
    end
    local savedLines = codeLines; codeLines = {}
    for _, child in ipairs(gui:GetChildren()) do generateGuiCode(child, sgVar) end
    local bodyLines = codeLines; codeLines = savedLines
    for _, l in ipairs(bodyLines) do emit("\t"..l) end
    emit(("\t%s.Parent = playerGui"):format(sgVar))
    emit(("\treturn %s"):format(sgVar))
    emit("end")
    emit("")
    if #extractedScripts > 0 then
        emit(("-- Extracted Scripts (%d found)"):format(#extractedScripts))
        for i, sd in ipairs(extractedScripts) do
            emit(("-- Script %d: %s (%s)"):format(i, sd.name, sd.className))
            emit(("local function runScript_%d(script_obj)"):format(i))
            emit("\tlocal script = script_obj")
            for line in (sd.source.."\n"):gmatch("[^\n]*\n") do
                emit("\t"..line:gsub("\n$",""))
            end
            emit("end"); emit("")
        end
    end
    emit("-- Init")
    emit("local gui = createGui()")
    emit("")
    if #extractedScripts > 0 then
        for i, sd in ipairs(extractedScripts) do
            local parentRef
            if sd.parent == sgVar then
                parentRef = "gui"
            else
                parentRef = ("gui:FindFirstChild(%q, true)"):format(
                    sd.parent:match("^(.+)_%d+$") or sd.parent)
            end
            emit(("-- Run: %s"):format(sd.name))
            emit("task.spawn(function()")
            emit(("\tlocal parent = %s"):format(parentRef))
            emit("\tif parent then")
            emit(("\t\trunScript_%d(parent)"):format(i))
            emit("\telse")
            emit(("\t\twarn('[DeepGUI] Parent not found for script: %s')"):format(sd.name))
            emit("\tend"); emit("end)"); emit("")
        end
    end
    return table.concat(codeLines, "\n")
end
local function runDecompile(inst)
    local ok, bytecode = pcall(getscriptbytecode, inst)
    if not ok or not bytecode or bytecode == "" then
        return "-- Could not obtain bytecode for: " .. tostring(inst.Name)
            .. "\n-- (getscriptbytecode may be unsupported or the script is empty)"
    end
    local opts = {
        EnabledRemarks       = { ColdRemark=true, InlineRemark=true },
        DecompilerTimeout    = 10,
        DecompilerMode       = "lift",
        ReaderFloatPrecision = 7,
        ShowDebugInformation = false,
        ShowInstructionLines = true,
        ShowOperationIndex   = false,
        ShowOperationNames   = false,
        ShowTrivialOperations= true,
        UseTypeInfo          = true,
        ListUsedGlobals      = true,
        ReturnElapsedTime    = true,
        CleanMode            = true,
    }
    local ok2, raw = pcall(ZukDecompile, bytecode, opts)
    if not ok2 then return "-- Decompile error:\n-- " .. tostring(raw) end
    local ok3, cleaned = pcall(ZukClean,  raw);  if ok3 then raw = cleaned end
    local ok4, pretty  = pcall(ZukPretty, raw);  if ok4 then raw = pretty  end
    return raw
end
local function mk(cls, props, parent)
    local i = Instance.new(cls)
    for k,v in pairs(props) do i[k] = v end
    if parent then i.Parent = parent end
    return i
end
local sg = mk("ScreenGui", {
    Name="Zukv2_AllInOne", DisplayOrder=10,
    ZIndexBehavior=Enum.ZIndexBehavior.Global, ResetOnSpawn=false
})
local main = mk("Frame", {
    Name="Main", Size=UDim2.new(0,760,0,480),
    Position=UDim2.new(0.5,-380,0.5,-240),
    BackgroundColor3=Color3.fromRGB(35,35,35), BorderSizePixel=1
}, sg)
mk("UIStroke",{Color=Color3.fromRGB(60,60,60),Thickness=1}, main)
local topBar = mk("Frame",{
    Name="TopBar", Size=UDim2.new(1,0,0,25),
    BackgroundColor3=Color3.fromRGB(45,45,45), BorderSizePixel=1
}, main)
mk("TextLabel",{
    Name="Title", Size=UDim2.new(1,-60,1,0), Position=UDim2.new(0,10,0,0),
    BackgroundTransparency=1, Text="zukv2 Explorer",
    TextColor3=Color3.fromRGB(220,220,220), TextXAlignment=Enum.TextXAlignment.Left,
    Font=Enum.Font.SourceSansBold, TextSize=14
}, topBar)
local closeBtn = mk("TextButton",{
    Name="Close", Size=UDim2.new(0,25,1,0), Position=UDim2.new(1,-25,0,0),
    BackgroundColor3=Color3.fromRGB(180,50,50), BackgroundTransparency=1,
    Text="X", TextColor3=Color3.fromRGB(255,255,255), BorderSizePixel=1
}, topBar)
local quickNav = mk("ScrollingFrame",{
    Name="QuickNav", Size=UDim2.new(1,0,0,28), Position=UDim2.new(0,0,0,25),
    BackgroundColor3=Color3.fromRGB(40,40,40), BorderSizePixel=0,
    CanvasSize=UDim2.new(0,0,0,0), ScrollBarThickness=1,
    AutomaticCanvasSize=Enum.AutomaticSize.X
}, main)
local qvLayout = mk("UIListLayout",{
    FillDirection=Enum.FillDirection.Horizontal,
    SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(0,2)
}, quickNav)
local qvPad = mk("UIPadding",{PaddingLeft=UDim.new(0,5),PaddingTop=UDim.new(0,4)}, quickNav)
local split = mk("Frame",{
    Name="Split", Size=UDim2.new(1,0,1,-53), Position=UDim2.new(0,0,0,53),
    BackgroundTransparency=1
}, main)
local leftCol = mk("Frame",{
    Name="LeftCol", Size=UDim2.new(0.38,0,1,0), BackgroundTransparency=1
}, split)
local treeToolbar = mk("Frame",{
    Size=UDim2.new(1,0,0,24), BackgroundColor3=Color3.fromRGB(40,40,40),
    BorderSizePixel=0
}, leftCol)
local searchFrame = mk("Frame",{
    Size=UDim2.new(1,-10,0,18), Position=UDim2.new(0,5,0,3),
    BackgroundColor3=Color3.fromRGB(30,30,30), BorderSizePixel=0
}, treeToolbar)
local searchInput = mk("TextBox",{
    Name="Input", Size=UDim2.new(1,-10,1,0), Position=UDim2.new(0,5,0,0),
    BackgroundTransparency=1, TextColor3=Color3.fromRGB(255,255,255),
    TextXAlignment=Enum.TextXAlignment.Left,
    PlaceholderText="Search...", Text="", TextSize=11
}, searchFrame)
local listFrame = mk("Frame",{
    Name="List", Size=UDim2.new(1,0,1,-24), Position=UDim2.new(0,0,0,24),
    BackgroundTransparency=1, ClipsDescendants=true
}, leftCol)
mk("Frame",{
    Size=UDim2.new(0,1,1,0), Position=UDim2.new(0.38,0,0,0),
    BackgroundColor3=Color3.fromRGB(55,55,55), BorderSizePixel=0
}, split)
local rightCol = mk("Frame",{
    Name="RightCol", Size=UDim2.new(0.62,-1,1,0), Position=UDim2.new(0.38,1,0,0),
    BackgroundColor3=Color3.fromRGB(22,22,22), BorderSizePixel=0
}, split)
local decompHeader = mk("Frame",{
    Size=UDim2.new(1,0,0,26), BackgroundColor3=Color3.fromRGB(32,32,32),
    BorderSizePixel=0
}, rightCol)
local decompTitle = mk("TextLabel",{
    Name="DecompTitle",
    Size=UDim2.new(1,-160,1,0), Position=UDim2.new(0,8,0,0),
    BackgroundTransparency=1, Text="Path:",
    TextColor3=Color3.fromRGB(160,160,160),
    TextXAlignment=Enum.TextXAlignment.Left,
    Font=Enum.Font.SourceSansBold, TextSize=12
}, decompHeader)
local decompBtn = mk("TextButton",{
    Name="DecompBtn",
    Size=UDim2.new(0,80,0,20), Position=UDim2.new(1,-85,0,3),
    BackgroundColor3=Color3.fromRGB(50,50,50), BorderSizePixel=0,
    Text="View", TextColor3=Color3.fromRGB(255,255,255),
    Font=Enum.Font.SourceSansBold, TextSize=10
}, decompHeader)
mk("UICorner",{CornerRadius=UDim.new(0,0)}, decompBtn)
local copyBtn = mk("TextButton",{
    Name="CopyBtn",
    Size=UDim2.new(0,60,0,20), Position=UDim2.new(1,-150,0,3),
    BackgroundColor3=Color3.fromRGB(50,50,50), BorderSizePixel=0,
    Text="Copy", TextColor3=Color3.fromRGB(210,210,210),
    Font=Enum.Font.SourceSansBold, TextSize=10
}, decompHeader)
local execBtn = mk("TextButton",{
    Name="ExecBtn",
    Size=UDim2.new(0,60,0,20), Position=UDim2.new(1,-215,0,3),
    BackgroundColor3=Color3.fromRGB(40,70,40), BorderSizePixel=0,
    Text="Execute", TextColor3=Color3.fromRGB(160,255,160),
    Font=Enum.Font.SourceSansBold, TextSize=10
}, decompHeader)
local codeScroll = mk("ScrollingFrame",{
    Name="CodeScroll",
    Size=UDim2.new(1,0,1,-26), Position=UDim2.new(0,0,0,26),
    BackgroundColor3=Color3.fromRGB(22,22,22), BorderSizePixel=1,
    ScrollBarThickness=4,
    ScrollBarImageColor3=Color3.fromRGB(70,70,70),
    CanvasSize=UDim2.new(0,0,0,0),
    AutomaticCanvasSize=Enum.AutomaticSize.Y,
    HorizontalScrollBarInset=Enum.ScrollBarInset.None,
}, rightCol)
mk("UIPadding",{
    PaddingLeft=UDim.new(0,8), PaddingTop=UDim.new(0,5),
    PaddingRight=UDim.new(0,8), PaddingBottom=UDim.new(0,5)
}, codeScroll)
local codeLabel = mk("TextLabel",{
    Name="Code",
    Size=UDim2.new(1,-16,0,0),
    AutomaticSize=Enum.AutomaticSize.Y,
    BackgroundTransparency=1,
    TextColor3=Color3.fromRGB(204,204,204),
    TextXAlignment=Enum.TextXAlignment.Left,
    TextYAlignment=Enum.TextYAlignment.Top,
    Font=Enum.Font.Code, TextSize=12,
    RichText=true, TextWrapped=false,
    Text='<font color="#555555">-- zukv2 decompiler\n-- by @OverZuka</font>'
}, codeScroll)
local resizeHandle = mk("Frame",{
    Name="ResizeHandle",
    Size=UDim2.new(0,12,0,12), Position=UDim2.new(1,-12,1,-12),
    BackgroundTransparency=0.4, ZIndex=15
}, main)
mk("TextLabel",{
    Size=UDim2.new(1,0,1,0), BackgroundTransparency=1,
    Text="◢", TextColor3=Color3.fromRGB(130,130,130),
    TextSize=10, ZIndex=16
}, resizeHandle)
sg.Parent = playerGui
local lastDecompResult = ""
local extraCodeLabels  = {}
local CODE_CHUNK       = 180000
local function setCodeText(raw)
    for _, lbl in ipairs(extraCodeLabels) do lbl:Destroy() end
    table.clear(extraCodeLabels)
    local lines = {}
    for line in (raw.."\n"):gmatch("[^\n]*\n") do
        table.insert(lines, hlLine(line:gsub("\n$","")))
    end
    local chunks, cur, curLen = {}, {}, 0
    for _, hl in ipairs(lines) do
        local addLen = #hl + 1
        if curLen + addLen > CODE_CHUNK and #cur > 0 then
            table.insert(chunks, table.concat(cur, "\n"))
            cur = {}; curLen = 0
        end
        table.insert(cur, hl); curLen += addLen
    end
    if #cur > 0 then table.insert(chunks, table.concat(cur, "\n")) end
    if #chunks == 0 then chunks = {""} end
    codeLabel.Text = chunks[1]
    for i = 2, #chunks do
        local lbl = Instance.new("TextLabel")
        lbl.Size           = UDim2.new(1,-16,0,0)
        lbl.AutomaticSize  = Enum.AutomaticSize.Y
        lbl.BackgroundTransparency = 1
        lbl.TextColor3     = Color3.fromRGB(204,204,204)
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.TextYAlignment = Enum.TextYAlignment.Top
        lbl.Font           = Enum.Font.Code
        lbl.TextSize       = 10
        lbl.RichText       = true
        lbl.TextWrapped    = false
        lbl.Text           = chunks[i]
        lbl.Parent         = codeScroll
        table.insert(extraCodeLabels, lbl)
    end
end
local function openCtxMenu(inst, screenPos)
    closeCtx()
    local isScreenGui = inst.ClassName == "ScreenGui"
    local menuH = isScreenGui and 44 or 22
    local menu = mk("Frame", {
        Name="CtxMenu",
        Size=UDim2.new(0, 160, 0, menuH),
        Position=UDim2.fromOffset(screenPos.X, screenPos.Y),
        BackgroundColor3=Color3.fromRGB(45,45,45),
        BorderSizePixel=1, ZIndex=50,
    }, sg)
    mk("UIStroke",{Color=Color3.fromRGB(70,70,70),Thickness=1}, menu)
    mk("UIListLayout",{SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(0,0)}, menu)
    local function makeItem(label, order, onClick)
        local btn = mk("TextButton",{
            Size=UDim2.new(1,0,0,22),
            BackgroundColor3=Color3.fromRGB(45,45,45),
            BackgroundTransparency=1,
            BorderSizePixel=0,
            Text="  "..label,
            TextColor3=Color3.fromRGB(210,210,210),
            TextXAlignment=Enum.TextXAlignment.Left,
            Font=Enum.Font.SourceSans, TextSize=12,
            ZIndex=51, LayoutOrder=order,
        }, menu)
        btn.MouseEnter:Connect(function()
            btn.BackgroundTransparency=0
            btn.BackgroundColor3=Color3.fromRGB(0,100,200)
        end)
        btn.MouseLeave:Connect(function()
            btn.BackgroundTransparency=1
            btn.BackgroundColor3=Color3.fromRGB(45,45,45)
        end)
        btn.MouseButton1Click:Connect(function()
            closeCtx(); onClick()
        end)
    end
    makeItem("Copy Path", 1, function()
        local path = buildPath(inst)
        pcall(setclipboard, path)
    end)
    if isScreenGui then
        makeItem("Convert to Script (Deep)", 2, function()
            local output = convertGuiToScript(inst)
            lastDecompResult = output
            pcall(setclipboard, output)
            codeLabel.Text = '<font color="#555555">-- Converting '..inst.Name..'…</font>'
            task.defer(function()
                setCodeText(output)
                decompTitle.Text = "ScreenGui › "..inst.Name.."  [Converted]"
            end)
        end)
    end
    ctxMenu = menu
end
local function buildRows(inst, depth, result)
    depth = depth or 0; result = result or {}
    local ok, name = pcall(function() return inst.Name end)
    if not ok then name = "???" end
    if filterText == "" or name:lower():find(filterText:lower(), 1, true) then
        table.insert(result, {inst=inst, depth=depth})
    end
    if expanded[inst] then
        local s, ch = pcall(inst.GetChildren, inst)
        if s then for _, c in ipairs(ch) do buildRows(c, depth+1, result) end end
    end
    return result
end
local function renderRows()
    for _, f in ipairs(rowFrames) do f:Destroy() end
    table.clear(rowFrames)
    local visH   = listFrame.AbsoluteSize.Y
    local startI = math.floor(scrollOffset / ROW_H) + 1
    local endI   = math.min(#rows, startI + math.ceil(visH / ROW_H) + 1)
    for i = startI, endI do
        local row = rows[i]; if not row then break end
        local inst      = row.inst
        local isSel     = inst == selected
        local isScript  = SCRIPT_CLASSES[inst.ClassName] == true
        local entry = mk("TextButton",{
            Size=UDim2.new(1,0,0,ROW_H),
            Position=UDim2.fromOffset(0, (i-1)*ROW_H - scrollOffset),
            BackgroundColor3=isSel and Color3.fromRGB(0,120,215) or Color3.fromRGB(35,35,35),
            BackgroundTransparency=isSel and 0 or 1,
            BorderSizePixel=0, Text=""
        }, listFrame)
        local indent = mk("Frame",{
            Size=UDim2.new(1,-(row.depth*INDENT_PER),1,0),
            Position=UDim2.fromOffset(row.depth*INDENT_PER+4,0),
            BackgroundTransparency=1
        }, entry)
        mk("TextLabel",{
            Size=UDim2.new(1,-20,1,0), Position=UDim2.fromOffset(20,0),
            BackgroundTransparency=1,
            Text=inst.Name,
            TextColor3=isScript and Color3.fromRGB(253,251,172) or Color3.fromRGB(220,220,220),
            TextXAlignment=Enum.TextXAlignment.Left, TextSize=10
        }, indent)
        entry.MouseButton1Click:Connect(function()
            closeCtx(); selected = inst
            if isScript then
                decompTitle.Text = inst.ClassName .. " › " .. inst.Name .. "   (press View)"
            else
                decompTitle.Text = inst.ClassName .. " › " .. inst.Name
            end
            renderRows()
        end)
        entry.MouseButton2Click:Connect(function(x, y)
            selected = inst; renderRows()
            openCtxMenu(inst, Vector2.new(x, y))
        end)
        if hasChildren(inst) then
            local exp = mk("TextButton",{
                Size=UDim2.fromOffset(16,ROW_H), Position=UDim2.fromOffset(-16,0),
                BackgroundTransparency=1,
                Text=expanded[inst] and "▾" or "▸",
                TextColor3=Color3.fromRGB(170,170,170), TextSize=8
            }, indent)
            exp.MouseButton1Click:Connect(function()
                expanded[inst] = not expanded[inst]
                rows = buildRows(treeRoot, 0, {})
                renderRows()
            end)
        end
        table.insert(rowFrames, entry)
    end
end
local function jumpToInstance(inst)
    expanded[game] = true; selected = inst
    rows = buildRows(treeRoot, 0, {})
    local targetI = 1
    for i, row in ipairs(rows) do if row.inst == inst then targetI = i; break end end
    local maxOff = math.max(0, (#rows*ROW_H) - listFrame.AbsoluteSize.Y)
    scrollOffset = math.clamp((targetI-1)*ROW_H, 0, maxOff)
    renderRows()
end
decompBtn.MouseButton1Click:Connect(function()
    if not selected then
        codeLabel.Text = '<font color="#ff6060">-- No instance selected.</font>'
        return
    end
    if not SCRIPT_CLASSES[selected.ClassName] then
        codeLabel.Text = '<font color="#ff9030">-- "'..tostring(selected.Name)..'" is a '
            ..tostring(selected.ClassName)..'.\n-- Pick a Script, LocalScript or ModuleScript.</font>'
        return
    end
    decompBtn.Text = "Working…"
    decompBtn.BackgroundColor3 = Color3.fromRGB(80,60,20)
    codeLabel.Text = '<font color="#555555">-- Decompiling '..selected.Name..'…</font>'
    task.defer(function()
        local raw = runDecompile(selected)
        lastDecompResult = raw
        setCodeText(raw)
        decompTitle.Text = selected.ClassName .. " › " .. selected.Name
        decompBtn.Text   = "View"
        decompBtn.BackgroundColor3 = Color3.fromRGB(50,50,50)
    end)
end)
local copyResetPending = false
copyBtn.MouseButton1Click:Connect(function()
    if lastDecompResult ~= "" then
        pcall(setclipboard, lastDecompResult)
        copyBtn.Text = "✓ Copied"
        if not copyResetPending then
            copyResetPending = true
            task.delay(1.5, function()
                copyBtn.Text = "Copy"
                copyResetPending = false
            end)
        end
    end
end)
execBtn.MouseButton1Click:Connect(function()
    if lastDecompResult ~= "" then
        local fn, err = loadstring(lastDecompResult)
        if fn then
            task.spawn(fn)
            execBtn.Text = "✓ Ran"
            task.delay(1.5, function() execBtn.Text = "Execute" end)
        else
            execBtn.Text = "Error"
            warn("[zukv2] Exec error: " .. tostring(err))
            task.delay(2, function() execBtn.Text = "Execute" end)
        end
    end
end)
for i, svcName in ipairs(QUICK_NAV_SERVICES) do
    local ok, svc = pcall(game.GetService, game, svcName)
    if ok then
        local btn = mk("TextButton",{
            Size=UDim2.new(0,0,0,20), AutomaticSize=Enum.AutomaticSize.X,
            BackgroundColor3=Color3.fromRGB(50,50,50), BorderSizePixel=0,
            Text="  "..svcName.."  ", TextColor3=Color3.fromRGB(200,200,200),
            Font=Enum.Font.SourceSans, TextSize=12, LayoutOrder=i
        }, quickNav)
        mk("UIStroke",{Color=Color3.fromRGB(70,70,70)}, btn)
        btn.MouseButton1Click:Connect(function() jumpToInstance(svc) end)
    end
end
closeBtn.MouseButton1Click:Connect(function() sg:Destroy() end)
local dragging, dragStart, startPos
topBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        closeCtx(); dragging=true
        dragStart=input.Position; startPos=main.Position
    end
end)
local resizing, resStart, resSize
resizeHandle.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        closeCtx(); resizing=true
        resStart=input.Position; resSize=main.Size
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
        local d = input.Position - dragStart
        main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset+d.X,
                                   startPos.Y.Scale, startPos.Y.Offset+d.Y)
    elseif resizing and input.UserInputType == Enum.UserInputType.MouseMovement then
        local d = input.Position - resStart
        main.Size = UDim2.new(0, math.max(MIN_SIZE.X, resSize.X.Offset+d.X),
                               0, math.max(MIN_SIZE.Y, resSize.Y.Offset+d.Y))
        renderRows()
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging=false; resizing=false
    end
end)
listFrame.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseWheel then
        local maxOff = math.max(0, (#rows*ROW_H) - listFrame.AbsoluteSize.Y)
        scrollOffset = math.clamp(scrollOffset - input.Position.Z*ROW_H*3, 0, maxOff)
        renderRows()
    end
end)
listFrame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then closeCtx() end
end)
searchInput:GetPropertyChangedSignal("Text"):Connect(function()
    filterText=searchInput.Text; scrollOffset=0
    rows=buildRows(treeRoot,0,{}); renderRows()
end)
expanded[game] = true


rows = buildRows(treeRoot, 0, {})
renderRows()
  
    
 --[[
            _           ____   ™ 
  _____   _| | ____   _|___ \  
 |_  / | | | |/ /\ \ / / __) | 
  / /| |_| |   <  \ V / / __/  
 /___|\__,_|_|\_\  \_/ |_____| 
                               
--]]
