using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Text;
using System.Text.RegularExpressions;
using IronBrew2.Bytecode_Library.Bytecode;
using IronBrew2.Bytecode_Library.IR;
using IronBrew2.Extensions;
using IronBrew2.Obfuscator.Opcodes;

namespace IronBrew2.Obfuscator.VM_Generation
{
	public class Generator
	{
		private readonly ObfuscationContext _context;

		public Generator(ObfuscationContext context) =>
			_context = context;

		public bool IsUsed(Chunk chunk, VOpcode virt)
		{
			bool isUsed = false;
			foreach (Instruction ins in chunk.Instructions)
				if (virt.IsInstruction(ins))
				{
					if (!_context.InstructionMapping.ContainsKey(ins.OpCode))
						_context.InstructionMapping.Add(ins.OpCode, virt);

					ins.CustomData = new CustomInstructionData { Opcode = virt };
					isUsed = true;
				}

			foreach (Chunk sChunk in chunk.Functions)
				isUsed |= IsUsed(sChunk, virt);

			return isUsed;
		}

		// ── Compression ───────────────────────────────────────────────────────────

		public static List<int> Compress(byte[] uncompressed)
		{
			var dictionary = new Dictionary<string, int>();
			for (int i = 0; i < 256; i++)
				dictionary.Add(((char) i).ToString(), i);

			string    w          = string.Empty;
			var       compressed = new List<int>();

			foreach (byte b in uncompressed)
			{
				string wc = w + (char) b;
				if (dictionary.ContainsKey(wc))
					w = wc;
				else
				{
					compressed.Add(dictionary[w]);
					dictionary.Add(wc, dictionary.Count);
					w = ((char) b).ToString();
				}
			}

			if (!string.IsNullOrEmpty(w))
				compressed.Add(dictionary[w]);

			return compressed;
		}

		public static string ToBase36(ulong value)
		{
			const string base36 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";
			var sb = new StringBuilder(13);
			do
			{
				sb.Insert(0, base36[(byte) (value % 36)]);
				value /= 36;
			} while (value != 0);
			return sb.ToString();
		}

		public static string CompressedToString(List<int> compressed)
		{
			var sb = new StringBuilder();
			foreach (int i in compressed)
			{
				string n = ToBase36((ulong) i);
				sb.Append(ToBase36((ulong) n.Length));
				sb.Append(n);
			}
			return sb.ToString();
		}

		// ── Chunk tree helpers ────────────────────────────────────────────────────

		// Walks the full chunk tree and returns the maximum value of selector across all chunks.
		private static int ComputeMax(Chunk c, Func<Chunk, int> selector)
		{
			int max = selector(c);
			foreach (Chunk child in c.Functions)
				max = Math.Max(max, ComputeMax(child, selector));
			return max;
		}

		// Builds the skip[] array that marks instruction slots that must not be grouped
		// into super operators. Extracted to eliminate the copy-paste between
		// GenerateSuperOperators and FoldAdditionalSuperOperators.
		private static bool[] BuildSkipArray(Chunk chunk)
		{
			bool[] skip = new bool[chunk.Instructions.Count + 1];

			for (int i = 0; i < chunk.Instructions.Count - 1; i++)
			{
				switch (chunk.Instructions[i].OpCode)
				{
					case Opcode.Closure:
					{
						skip[i] = true;
						for (int j = 0; j < ((Chunk) chunk.Instructions[i].RefOperands[0]).UpvalueCount; j++)
							skip[i + j + 1] = true;
						break;
					}
					case Opcode.Eq:
					case Opcode.Lt:
					case Opcode.Le:
					case Opcode.Test:
					case Opcode.TestSet:
					case Opcode.TForLoop:
					case Opcode.SetList:
						skip[i + 1] = true;
						break;
					case Opcode.LoadBool when chunk.Instructions[i].C != 0:
						skip[i + 1] = true;
						break;
					case Opcode.ForLoop:
					case Opcode.ForPrep:
					case Opcode.Jmp:
						chunk.Instructions[i].UpdateRegisters();
						skip[i + 1] = true;
						skip[i + chunk.Instructions[i].B + 1] = true;
						break;
				}

				if (chunk.Instructions[i].CustomData.WrittenOpcode is OpSuperOperator su && su.SubOpcodes != null)
					for (int j = 0; j < su.SubOpcodes.Length; j++)
						skip[i + j] = true;
			}

			return skip;
		}

		// ── Mutations ─────────────────────────────────────────────────────────────

		public List<OpMutated> GenerateMutations(List<VOpcode> opcodes)
		{
			Random r       = new Random();
			var    mutated = new List<OpMutated>();

			foreach (VOpcode opc in opcodes)
			{
				if (opc is OpSuperOperator) continue;

				for (int i = 0; i < r.Next(35, 50); i++)
				{
					int[] rand = { 0, 1, 2 };
					rand.Shuffle();

					mutated.Add(new OpMutated { Registers = rand, Mutated = opc });
				}
			}

			mutated.Shuffle();
			return mutated;
		}

		public void FoldMutations(List<OpMutated> mutations, HashSet<OpMutated> used, Chunk chunk)
		{
			bool[] skip = new bool[chunk.Instructions.Count + 1];
			for (int i = 0; i < chunk.Instructions.Count; i++)
				if (chunk.Instructions[i].OpCode == Opcode.Closure)
					for (int j = 1; j <= ((Chunk) chunk.Instructions[i].RefOperands[0]).UpvalueCount; j++)
						skip[i + j] = true;

			for (int i = 0; i < chunk.Instructions.Count; i++)
			{
				if (skip[i]) continue;

				CustomInstructionData data = chunk.Instructions[i].CustomData;
				foreach (OpMutated mut in mutations)
					if (data.Opcode == mut.Mutated && data.WrittenOpcode == null)
					{
						if (!used.Contains(mut)) used.Add(mut);
						data.Opcode = mut;
						break;
					}
			}

			foreach (Chunk child in chunk.Functions)
				FoldMutations(mutations, used, child);
		}

		// ── Super operators ───────────────────────────────────────────────────────

		public List<OpSuperOperator> GenerateSuperOperators(Chunk chunk, int maxSize, int minSize = 5)
		{
			var    results = new List<OpSuperOperator>();
			Random r       = new Random();
			bool[] skip    = BuildSkipArray(chunk);

			int c = 0;
			while (c < chunk.Instructions.Count)
			{
				int             targetCount   = maxSize;
				OpSuperOperator superOperator = new OpSuperOperator { SubOpcodes = new VOpcode[targetCount] };

				bool d      = true;
				int  cutoff = targetCount;

				for (int j = 0; j < targetCount; j++)
					if (c + j > chunk.Instructions.Count - 1 || skip[c + j])
					{
						cutoff = j;
						d      = false;
						break;
					}

				if (!d)
				{
					if (cutoff < minSize) { c += cutoff + 1; continue; }
					targetCount   = cutoff;
					superOperator = new OpSuperOperator { SubOpcodes = new VOpcode[targetCount] };
				}

				for (int j = 0; j < targetCount; j++)
					superOperator.SubOpcodes[j] = chunk.Instructions[c + j].CustomData.Opcode;

				results.Add(superOperator);
				c += targetCount + 1;
			}

			foreach (Chunk child in chunk.Functions)
				results.AddRange(GenerateSuperOperators(child, maxSize));

			return results;
		}

		public void FoldAdditionalSuperOperators(Chunk chunk, List<OpSuperOperator> operators, ref int folded)
		{
			bool[] skip = BuildSkipArray(chunk);

			int c = 0;
			while (c < chunk.Instructions.Count)
			{
				if (skip[c]) { c++; continue; }

				bool used = false;
				foreach (OpSuperOperator op in operators)
				{
					int  targetCount = op.SubOpcodes.Length;
					bool cu          = true;

					for (int j = 0; j < targetCount; j++)
						if (c + j > chunk.Instructions.Count - 1 || skip[c + j])
						{
							cu = false;
							break;
						}

					if (!cu) continue;

					List<Instruction> taken = chunk.Instructions.Skip(c).Take(targetCount).ToList();
					if (!op.IsInstruction(taken)) continue;

					for (int j = 0; j < targetCount; j++)
					{
						skip[c + j] = true;
						chunk.Instructions[c + j].CustomData.WrittenOpcode = new OpSuperOperator { VIndex = 0 };
					}

					chunk.Instructions[c].CustomData.WrittenOpcode = op;
					used = true;
					break;
				}

				if (!used) c++;
				else folded++;
			}

			foreach (Chunk child in chunk.Functions)
				FoldAdditionalSuperOperators(child, operators, ref folded);
		}

		// ── Dispatch tree ─────────────────────────────────────────────────────────

		// Builds a balanced binary dispatch tree into sb.
		// Every handler string from GetObfuscated() is passed through ApplyNameMap
		// so opcode-level identifiers (Stk, Inst, InstrPoint, etc.) are randomised
		// the same as the surrounding VM frame variables.
		// The branch condition tokens "Enum" and "Inst" are also remapped so the
		// dispatch structure itself uses the randomised names.
		private void BuildDispatchTree(StringBuilder sb, List<VOpcode> virtuals, List<int> opcodes, Random r)
		{
			var map = _context.NameMap;

			// Helper: emit a handler with its identifiers fully remapped
			string Handler(int idx) =>
				ApplyNameMap(virtuals[idx].GetObfuscated(_context), map);

			// "Enum" was pre-translated to VM_ENUM in OpcodeRawToToken, so look up
			// VM_ENUM in the name map — not the raw "Enum" which is no longer a token.
			string enumName = map.TryGetValue("VM_ENUM", out var en) ? en : "VM_ENUM";

			if (opcodes.Count == 1)
			{
				sb.Append(Handler(opcodes[0]));
				return;
			}

			if (opcodes.Count == 2)
			{
				if (r.Next(2) == 0)
				{
					sb.Append($"if {enumName} > {virtuals[opcodes[0]].VIndex} then ");
					sb.Append(Handler(opcodes[1]));
					sb.Append("else ");
					sb.Append(Handler(opcodes[0]));
				}
				else
				{
					sb.Append($"if {enumName} == {virtuals[opcodes[0]].VIndex} then ");
					sb.Append(Handler(opcodes[0]));
					sb.Append("else ");
					sb.Append(Handler(opcodes[1]));
				}
				sb.Append("end;");
				return;
			}

			List<int> ordered = opcodes.OrderBy(o => o).ToList();
			List<int> left    = ordered.Take(ordered.Count / 2).ToList();
			List<int> right   = ordered.Skip(ordered.Count / 2).ToList();

			sb.Append($"if {enumName} <= {left.Last()} then ");
			BuildDispatchTree(sb, virtuals, left,  r);
			sb.Append(" else");
			BuildDispatchTree(sb, virtuals, right, r);
		}

		// ── Main entry point ──────────────────────────────────────────────────────


		// ── Name map ─────────────────────────────────────────────────────────────

		// All placeholder tokens used in VMStrings.cs that need a random name each run.
		// The two-char prefix (GB_, DC_, etc.) is part of the token and is replaced
		// entirely — it never leaks into the output.
		private static readonly string[] VmTokens =
		{
			// gBits helpers
			"GB_BITXOR", "GB_GBIT", "GB_BIT", "GB_START", "GB_END", "GB_RES", "GB_PLC",
			"GB_POS", "GB_BITS32", "GB_W", "GB_X", "GB_Y", "GB_Z", "GB_WORD",
			"GB_BITS8", "GB_F", "GB_SIZET", "GB_INT", "GB_BYTE", "GB_SUB",
			"GB_CHAR", "GB_CONCAT", "GB_SEL", "GB_LDEXP", "GB_FENV", "GB_UNPACK",
			// gFloat helpers
			"GF_FLOAT", "GF_L", "GF_R", "GF_NORM", "GF_MANT", "GF_EXP", "GF_SIGN",
			// gString helpers
			"GS_STR", "GS_LEN", "GS_S", "GS_BUF", "GS_I",
			// Deserializer
			"DC_BSTR", "DC_R", "DC_DESER", "DC_INSTRS", "DC_FUNCS", "DC_LINES", "DC_CHUNK",
			// Wrap / executor
			"WR_WRAP", "WR_UPVALS", "WR_ENV", "WR_INSTR", "WR_CONST", "WR_PROTO", "WR_PARAMS",
			"WR_PCALL",
			// VM interpreter loop frame variables (referenced in VMStrings templates)
			"VM_IP", "VM_TOP", "VM_VARG", "VM_ARGS", "VM_PC", "VM_UPV", "VM_STK",
			"VM_IDX", "VM_VSZ", "VM_INST", "VM_ENUM",
			// Line info variant
			"LI_LOOP", "LI_A", "LI_B", "LI_LINE",
			// Misc deserializer loop vars (inline in generated code)
			"DC_IDX", "DC_TYPE", "DC_CONS", "DC_CNT",
			"DC_D1", "DC_D2", "DC_TP", "DC_OP", "DC_IN",
			"XKEY_LO",
			// ── Opcode handler local temporaries ──────────────────────────────────
			// Identifiers used only inside handler bodies (not shared VM state).
			// Shared VM state names (Stk, Instr, Const, etc.) are NOT listed here —
			// they are pre-translated to their VM token equivalents (VM_STK, WR_INSTR
			// etc.) by ApplyNameMap before the name map is applied, so they resolve
			// to the same random names as the VMStrings template variables.
			"Args", "Edx", "Limit", "Results", "Output",
			"Idx", "Idz",
			"Offset", "Index", "Step",
			"T_local", "K_local", "R_local", "X_local", "C_local",
			"Upv", "NStk", "Cls", "List",
			"NewProto", "NewUvals", "Indexes", "Mvm",
			"VA", "Result",
		};

		// Generates a random valid Lua identifier that doesn't start with a digit.
		// Uses a mix of lower/upper so it looks like natural (bad) code, not hex spam.
		private static string RandomIdent(Random r, int minLen = 4, int maxLen = 9)
		{
			const string startChars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_";
			const string bodyChars  = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_";
			int len = r.Next(minLen, maxLen + 1);
			var sb  = new System.Text.StringBuilder(len);
			sb.Append(startChars[r.Next(startChars.Length)]);
			for (int i = 1; i < len; i++)
				sb.Append(bodyChars[r.Next(bodyChars.Length)]);
			return sb.ToString();
		}

		// Builds a bijective map from every VmToken to a unique random identifier.
		// Longer tokens are sorted first so replacement is safe (no prefix collisions).
		private static Dictionary<string, string> BuildNameMap(Random r)
		{
			var map   = new Dictionary<string, string>();
			var taken = new HashSet<string>();

			// Sort longest-first so e.g. "GB_BITS32" is mapped before "GB_BITS8"
			foreach (string token in VmTokens.OrderByDescending(t => t.Length))
			{
				string name;
				do { name = RandomIdent(r); } while (taken.Contains(name));
				taken.Add(name);
				map[token] = name;
			}
			return map;
		}

		// Raw opcode handler identifiers → their VMStrings token equivalents.
		// Opcode files use readable names ("Stk", "InstrPoint", "Const" etc.) but
		// VMStrings uses token names ("VM_STK", "VM_IP", "WR_CONST" etc.).
		// By pre-translating the raw names to their token equivalents before the
		// name map is applied, both resolve to the same random identifier, so
		// the VM frame and the dispatch handler bodies stay in sync.
		private static readonly (string Raw, string Token)[] OpcodeRawToToken =
		{
			// Sorted longest-first to avoid prefix collisions during replacement
			("InstrPoint", "VM_IP"),
			("Upvalues",   "WR_UPVALS"),
			("Varargsz",   "VM_VSZ"),
			("Lupvals",    "VM_UPV"),
			("Vararg",     "VM_VARG"),
			("Params",     "WR_PARAMS"),
			("PCount",     "VM_PC"),
			("Unpack",     "GB_UNPACK"),
			("Results",    "Results"),   // local-only, keep as token for de-dup
			("Instr",      "WR_INSTR"),
			("Const",      "WR_CONST"),
			("Proto",      "WR_PROTO"),
			("Wrap",       "WR_WRAP"),
			("Inst",       "VM_INST"),
			("Enum",       "VM_ENUM"),
			("Env",        "WR_ENV"),
			("Stk",        "VM_STK"),
			("Top",        "VM_TOP"),
			("_R",         "DC_R"),
		};

		// Applies the name map to a string.
		// Step 1: pre-translate opcode raw names → VM token names so shared
		//   VM state identifiers resolve to the same random name in both the
		//   frame (VMStrings templates) and the handlers (VOpcode.GetObfuscated).
		// Step 2: apply the token → random-name map, longest-first.
		private static string ApplyNameMap(string src, Dictionary<string, string> map)
		{
			// Pre-translation pass: raw opcode names → token equivalents.
			// Uses Regex word-boundary matching to prevent partial-word corruption:
			// e.g. "Stk" must not replace inside "NStk", "_R" must not hit "DC_R",
			// "Proto" must not corrupt "NewProto" (a local var in OpClosure).
			foreach (var (raw, token) in OpcodeRawToToken)
				src = Regex.Replace(src, @"\b" + Regex.Escape(raw) + @"\b", token);

			// Main pass: token → random identifier, longest-first
			foreach (var kv in map.OrderByDescending(kv => kv.Key.Length))
				src = src.Replace(kv.Key, kv.Value);

			return src;
		}

		// Splits an integer key into two random additive parts so the key never
		// appears as a bare literal in the output: emits "A+B" where A+B==key.
		private static string SplitKey(Random r, int key)
		{
			// Keep both parts positive and within int range
			int a = r.Next(1, int.MaxValue - 1);
			int b = key - a;  // may be negative — that's fine in Lua arithmetic
			return $"{a}+({b})";
		}

		public string GenerateVM(ObfuscationSettings settings)
		{
			Random r  = new Random();
			var    sb = new System.Text.StringBuilder();

			// Build per-run name map — every identifier gets a fresh random name.
			// Store in context so BuildDispatchTree and OpSuperOperator can use it.
			var nameMap = BuildNameMap(r);
			_context.NameMap = nameMap;

			// Convenience: look up what the DC_BSTR placeholder became (needed for
			// the bytecode assignment emitted outside the VMStrings templates)
			string bstrName   = nameMap["DC_BSTR"];
			string destrName  = nameMap["DC_DESER"];
			string wrapName   = nameMap["WR_WRAP"];
			string fenvName   = nameMap["GB_FENV"];
			string xkeyLoName = nameMap["XKEY_LO"];

			List<VOpcode> virtuals = System.Reflection.Assembly.GetExecutingAssembly().GetTypes()
			                                 .Where(t => t.IsSubclassOf(typeof(VOpcode)))
			                                 .Select(System.Activator.CreateInstance)
			                                 .Cast<VOpcode>()
			                                 .Where(t => IsUsed(_context.HeadChunk, t))
			                                 .ToList();

			if (settings.Mutate)
			{
				List<OpMutated> muts = GenerateMutations(virtuals).Take(settings.MaxMutations).ToList();
				Console.WriteLine($"Created {muts.Count} mutations.");
				HashSet<OpMutated> usedMuts = new HashSet<OpMutated>();
				FoldMutations(muts, usedMuts, _context.HeadChunk);
				Console.WriteLine($"Used {usedMuts.Count} mutations.");
				virtuals.AddRange(usedMuts);
			}

			if (settings.SuperOperators)
			{
				int folded = 0;
				var megaOperators = GenerateSuperOperators(_context.HeadChunk, 80, 60)
					.OrderBy(_ => r.Next()).Take(settings.MaxMegaSuperOperators).ToList();
				Console.WriteLine($"Created {megaOperators.Count} mega super operators.");
				virtuals.AddRange(megaOperators);
				FoldAdditionalSuperOperators(_context.HeadChunk, megaOperators, ref folded);

				var miniOperators = GenerateSuperOperators(_context.HeadChunk, 10)
					.OrderBy(_ => r.Next()).Take(settings.MaxMiniSuperOperators).ToList();
				Console.WriteLine($"Created {miniOperators.Count} mini super operators.");
				virtuals.AddRange(miniOperators);
				FoldAdditionalSuperOperators(_context.HeadChunk, miniOperators, ref folded);

				Console.WriteLine($"Folded {folded} instructions into super operators.");
			}

			virtuals.Shuffle();
			for (int i = 0; i < virtuals.Count; i++)
				virtuals[i].VIndex = i;

			// ── VM header: localise Lua builtins with randomised names ────────────
			// Wrap entire VM in an IIFE so all locals are scoped and nothing
			// leaks into _G. Also gives a clean single return to the caller.
			sb.Append("return (function()\n");
			sb.Append($"local {nameMap["GB_BYTE"]}=string.byte;");
			sb.Append($"local {nameMap["GB_CHAR"]}=string.char;");
			sb.Append($"local {nameMap["GB_SUB"]}=string.sub;");
			sb.Append($"local {nameMap["GB_CONCAT"]}=table.concat;");
			sb.Append($"local {nameMap["GB_LDEXP"]}=math.ldexp;");
			sb.Append($"local {nameMap["GB_FENV"]}=getfenv or function()return _ENV end;");
			sb.Append($"local {nameMap["GB_SEL"]}=select;");
			sb.Append($"local {nameMap["GB_UNPACK"]}=unpack;");

			// ── Bytecode payload ─────────────────────────────────────────────────
			byte[] bs = new Serializer(_context, settings).SerializeLChunk(_context.HeadChunk);

			if (settings.BytecodeCompress)
			{
				// Decompressor is an anonymous IIFE — no named function to fingerprint
				// Inline ToNumber locally inside the decompressor so it's anonymous
				string tn = RandomIdent(r); while (nameMap.ContainsValue(tn)) tn = RandomIdent(r);
				sb.Append($"local {bstrName}=(function(b)local {tn}=tonumber;");
				sb.Append($"local c,d,e=\"\",\"\",{{}}local f=256;local g={{}}");
				sb.Append($"for h=0,f-1 do g[h]={nameMap["GB_CHAR"]}(h)end;");
				sb.Append($"local i=1;local function k()local l={tn}({nameMap["GB_SUB"]}(b,i,i),36)i=i+1;local m={tn}({nameMap["GB_SUB"]}(b,i,i+l-1),36)i=i+l;return m end;");
				sb.Append($"c={nameMap["GB_CHAR"]}(k())e[1]=c;while i<#b do local n=k()if g[n]then d=g[n]else d=c..{nameMap["GB_SUB"]}(c,1,1)end;");
				sb.Append($"g[f]=c..{nameMap["GB_SUB"]}(d,1,1)e[#e+1],c,f=d,d,f+1 end;return table.concat(e)end)('{CompressedToString(Compress(bs))}');");
			}
			else
			{
				sb.Append($"local {bstrName}='");
				foreach (byte b in bs) { sb.Append('\\'); sb.Append(b); }
				sb.Append("';");
			}

			// ── Deserializer (VMP1) ───────────────────────────────────────────────
			int maxConstants = ComputeMax(_context.HeadChunk, c => c.Constants.Count);

			// XOR_KEY is replaced with split arithmetic — never a bare literal
			string keyExpr   = SplitKey(r, _context.PrimaryXorKey);
			string vmp1      = VMStrings.VMP1.Replace("XOR_KEY", keyExpr);
			sb.Append(ApplyNameMap(vmp1, nameMap));

			for (int i = 0; i < (int)ChunkStep.StepCount; i++)
			{
				string chunk_snippet = "";
				switch (_context.ChunkSteps[i])
				{
					case ChunkStep.ParameterCount:
						chunk_snippet = $"DC_CHUNK[4]=GB_BITS8();";
						break;

					case ChunkStep.Constants:
						chunk_snippet =
							$"local DC_CNT=GB_BITS32() " +
							$"local DC_CONSTS={{{string.Join(",", Enumerable.Repeat("0", maxConstants))}}};" +
							$"for DC_IDX=1,DC_CNT do " +
							$"local DC_TYPE=GB_BITS8();local DC_CONS;" +
							$"if(DC_TYPE=={_context.ConstantMapping[1]})then DC_CONS=(GB_BITS8()~=0);" +
							$"elseif(DC_TYPE=={_context.ConstantMapping[2]})then DC_CONS=GF_FLOAT();" +
							$"elseif(DC_TYPE=={_context.ConstantMapping[3]})then DC_CONS=GS_STR();" +
							$"end;DC_CONSTS[DC_IDX]=DC_CONS;end;DC_CHUNK[2]=DC_CONSTS ";
						break;

					case ChunkStep.Instructions:
						string ixk1 = SplitKey(r, _context.IXorKey1);
						string ixk2 = SplitKey(r, _context.IXorKey2);
						chunk_snippet =
							$"for DC_IDX=1,GB_BITS32()do " +
							$"local DC_D1=GB_BITXOR(GB_BITS32(),{ixk1});" +
							$"local DC_D2=GB_BITXOR(GB_BITS32(),{ixk2});" +
							$"local DC_TP=GB_GBIT(DC_D1,1,2);local DC_OP=GB_GBIT(DC_D2,1,11);" +
							$"local DC_IN={{DC_OP,GB_GBIT(DC_D1,3,11),nil,nil,DC_D2}};" +
							$"if(DC_TP==0)then DC_IN[OP_B]=GB_GBIT(DC_D1,12,20);DC_IN[OP_C]=GB_GBIT(DC_D1,21,29);" +
							$"elseif(DC_TP==1)then DC_IN[OP_B]=GB_GBIT(DC_D2,12,33);" +
							$"elseif(DC_TP==2)then DC_IN[OP_B]=GB_GBIT(DC_D2,12,32)-1048575;" +
							$"elseif(DC_TP==3)then DC_IN[OP_B]=GB_GBIT(DC_D2,12,32)-1048575;DC_IN[OP_C]=GB_GBIT(DC_D1,21,29);" +
							$"end;DC_INSTRS[DC_IDX]=DC_IN;end;";
						break;

					case ChunkStep.Functions:
						chunk_snippet = $"for DC_IDX=1,GB_BITS32()do DC_FUNCS[DC_IDX-1]=DC_DESER();end;";
						break;

					case ChunkStep.LineInfo:
						if (settings.PreserveLineInfo)
							chunk_snippet = $"for DC_IDX=1,GB_BITS32()do DC_LINES[DC_IDX]=GB_BITS32();end;";
						break;
				}
				sb.Append(ApplyNameMap(chunk_snippet, nameMap));
			}

			sb.Append(ApplyNameMap("return DC_CHUNK;end;", nameMap));
			sb.Append(ApplyNameMap(settings.PreserveLineInfo ? VMStrings.VMP2_LI : VMStrings.VMP2, nameMap));

			// ── Dispatch tree ─────────────────────────────────────────────────────
			BuildDispatchTree(sb, virtuals, Enumerable.Range(0, virtuals.Count).ToList(), r);
			sb.Append(ApplyNameMap(settings.PreserveLineInfo ? VMStrings.VMP3_LI : VMStrings.VMP3, nameMap));

			// ── Final slot substitutions ──────────────────────────────────────────
			int maxFuncs  = ComputeMax(_context.HeadChunk, c => c.Functions.Count);
			int maxInstrs = ComputeMax(_context.HeadChunk, c => c.Instructions.Count);

			string vm = sb.ToString()
				.Replace("DC_CONSTS",  /* already in nameMap but emitted inline — fix up any stragglers */
				         nameMap.ContainsKey("DC_CONSTS") ? nameMap["DC_CONSTS"] : "DC_CONSTS")
				.Replace("FUNC_CNT",  string.Join(",", Enumerable.Repeat("0", maxFuncs)))
				.Replace("INSTR_CNT", string.Join(",", Enumerable.Repeat("0", maxInstrs)))
				.Replace("OP_ENUM",   "1")
				.Replace("OP_A",      "2")
				.Replace("OP_BX",     "4")   // must precede OP_B
				.Replace("OP_B",      "3")
				.Replace("OP_C",      "5")
				.Replace("OP_DATA",   "6");

			return LuaMinifier.Minify(vm);
		}
	}
}
