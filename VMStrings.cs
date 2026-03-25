namespace IronBrew2.Obfuscator.VM_Generation
{
	// All VM-specific identifiers use placeholder tokens in ALL_CAPS_UNDERSCORED form.
	// Generator.ApplyNameMap() replaces every placeholder with a fresh random name
	// each obfuscation run, so no two outputs share symbol names.
	//
	// Placeholder naming convention:
	//   VM_*   — VM interpreter variables (Stk, Const, InstrPoint, etc.)
	//   DC_*   — Deserializer / decoder variables
	//   GB_*   — gBits helper variables
	//   GF_*   — gFloat variables
	//   GS_*   — gString variables
	//   WR_*   — Wrap / executor variables
	//
	// XOR_KEY       — replaced with split arithmetic expression (not a bare literal)
	// XKEY_LO       — replaced with XOR_KEY % 256 expression (distinct from XOR_KEY
	//                 so the key literal substitution doesn't corrupt the var name)
	// DECOMP_FN     — the LZW decompressor function name (randomised per run)

	public static class VMStrings
	{
		public static string VMP1 = @"
local GB_BITXOR=bit and bit.bxor or function(a,b)local p,c=1,0 while a>0 and b>0 do local ra,rb=a%2,b%2 if ra~=rb then c=c+p end a,b,p=(a-ra)/2,(b-rb)/2,p*2 end if a<b then a=b end while a>0 do local ra=a%2 if ra>0 then c=c+p end a,p=(a-ra)/2,p*2 end return c end
local function GB_GBIT(GB_BIT,GB_START,GB_END)if GB_END then local GB_RES=(GB_BIT/2^(GB_START-1))%2^((GB_END-1)-(GB_START-1)+1);return GB_RES-GB_RES%1;else local GB_PLC=2^(GB_START-1);return(GB_BIT%(GB_PLC+GB_PLC)>=GB_PLC)and 1 or 0;end;end;
local GB_POS=1;
local function GB_BITS32()local GB_W,GB_X,GB_Y,GB_Z=GB_BYTE(DC_BSTR,GB_POS,GB_POS+3);GB_POS=GB_POS+4;local GB_WORD=(GB_Z*16777216)+(GB_Y*65536)+(GB_X*256)+GB_W;return GB_BITXOR(GB_WORD,XOR_KEY);end;
local XKEY_LO=XOR_KEY%256;
local function GB_BITS8()local GB_F=GB_BITXOR(GB_BYTE(DC_BSTR,GB_POS,GB_POS),XKEY_LO);GB_POS=GB_POS+1;return GB_F;end;
local function GF_FLOAT()local GF_L=GB_BITS32();local GF_R=GB_BITS32();local GF_NORM=1;local GF_MANT=(GB_GBIT(GF_R,1,20)*(2^32))+GF_L;local GF_EXP=GB_GBIT(GF_R,21,31);local GF_SIGN=((-1)^GB_GBIT(GF_R,32));if(GF_EXP==0)then if(GF_MANT==0)then return GF_SIGN*0;else GF_EXP=1;GF_NORM=0;end;elseif(GF_EXP==2047)then return(GF_MANT==0)and(GF_SIGN*(1/0))or(GF_SIGN*(0/0));end;return GB_LDEXP(GF_SIGN,GF_EXP-1023)*(GF_NORM+(GF_MANT/(2^52)));end;
local GB_SIZET=GB_BITS32;
local function GS_STR(GS_LEN)local GS_S;if(not GS_LEN)then GS_LEN=GB_SIZET();if(GS_LEN==0)then return'';end;end;GS_S=GB_SUB(DC_BSTR,GB_POS,GB_POS+GS_LEN-1);GB_POS=GB_POS+GS_LEN;local GS_BUF={}for GS_I=1,#GS_S do GS_BUF[GS_I]=GB_CHAR(GB_BITXOR(GB_BYTE(GB_SUB(GS_S,GS_I,GS_I)),XKEY_LO))end return GB_CONCAT(GS_BUF);end;
local GB_INT=GB_BITS32;
local function DC_R(...)return{...},GB_SEL('#',...)end
local function DC_DESER()local DC_INSTRS={INSTR_CNT};local DC_FUNCS={FUNC_CNT};local DC_LINES={};local DC_CHUNK={DC_INSTRS,nil,DC_FUNCS,nil,DC_LINES};";

		public static string VMP2 = @"
local function WR_WRAP(DC_CHUNK,WR_UPVALS,WR_ENV)
local WR_INSTR=DC_CHUNK[1];local WR_CONST=DC_CHUNK[2];local WR_PROTO=DC_CHUNK[3];local WR_PARAMS=DC_CHUNK[4];
return function(...)
local WR_INSTR=WR_INSTR;local WR_CONST=WR_CONST;local WR_PROTO=WR_PROTO;local WR_PARAMS=WR_PARAMS;
local DC_R=DC_R local VM_IP=1;local VM_TOP=-1;
local VM_VARG={};local VM_ARGS={...};
local VM_PC=GB_SEL('#',...)-1;
local VM_UPV={};local VM_STK={};
for VM_IDX=0,VM_PC do if(VM_IDX>=WR_PARAMS)then VM_VARG[VM_IDX-WR_PARAMS]=VM_ARGS[VM_IDX+1];else VM_STK[VM_IDX]=VM_ARGS[VM_IDX+1];end;end;
local VM_VSZ=VM_PC-WR_PARAMS+1
local VM_INST;local VM_ENUM;
while true do
VM_INST=WR_INSTR[VM_IP];VM_ENUM=VM_INST[OP_ENUM];";

		public static string VMP3 = @"
VM_IP=VM_IP+1;end;end;end;
return WR_WRAP(DC_DESER(),{},GB_FENV())();
end)();
";

		public static string VMP2_LI = @"
local WR_PCALL=pcall
local function WR_WRAP(DC_CHUNK,WR_UPVALS,WR_ENV)
local WR_INSTR=DC_CHUNK[1];local WR_CONST=DC_CHUNK[2];local WR_PROTO=DC_CHUNK[3];local WR_PARAMS=DC_CHUNK[4];
return function(...)
local VM_IP=1;local VM_TOP=-1;
local VM_ARGS={...};local VM_PC=GB_SEL('#',...)-1;
local function LI_LOOP()
local WR_INSTR=WR_INSTR;local WR_CONST=WR_CONST;local WR_PROTO=WR_PROTO;local WR_PARAMS=WR_PARAMS;
local DC_R=DC_R local VM_VARG={};
local VM_UPV={};local VM_STK={};
for VM_IDX=0,VM_PC do if(VM_IDX>=WR_PARAMS)then VM_VARG[VM_IDX-WR_PARAMS]=VM_ARGS[VM_IDX+1];else VM_STK[VM_IDX]=VM_ARGS[VM_IDX+1];end;end;
local VM_VSZ=VM_PC-WR_PARAMS+1
local VM_INST;local VM_ENUM;
while true do VM_INST=WR_INSTR[VM_IP];VM_ENUM=VM_INST[OP_ENUM];";

		public static string VMP3_LI = @"
VM_IP=VM_IP+1;end;end;
local LI_A,LI_B=DC_R(WR_PCALL(LI_LOOP))
if not LI_A[1] then local LI_LINE=DC_CHUNK[7][VM_IP]or'?'
error('[IB] error at line '..LI_LINE..': '..LI_A[2],0)
else return GB_UNPACK(LI_A,2,LI_B)end;end;end;
return WR_WRAP(DC_DESER(),{},GB_FENV())();
end)();
";
	}
}
