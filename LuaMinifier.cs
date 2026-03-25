using System.Text;
using System.Text.RegularExpressions;

namespace IronBrew2.Obfuscator.VM_Generation
{
	// Strips whitespace and line comments from the generated VM Lua output.
	// This is NOT a general-purpose Lua minifier — it handles the clean,
	// known-structure code that GenerateVM produces.
	//
	// Strategy:
	//   Pass 1 — character walk: strip -- comments, copy string literals verbatim
	//   Pass 2 — collapse all whitespace runs (including newlines) to single spaces
	//   Pass 3 — remove spaces around purely symbolic tokens where safe
	//
	// The word-boundary problem: we must NEVER collapse "local x" → "localx".
	// The fix is simple — only strip spaces around tokens that are entirely
	// non-word characters (brackets, semicolons, operators). Word-to-word
	// spaces are left untouched by the regex pass so they survive naturally.
	public static class LuaMinifier
	{
		public static string Minify(string src)
		{
			// ── Pass 1: strip comments, preserve string literals ─────────────────
			var sb = new StringBuilder(src.Length);
			int i = 0;

			while (i < src.Length)
			{
				char c = src[i];

				// Short string literal — copy verbatim until unescaped closing quote
				if (c == '"' || c == '\'')
				{
					char quote = c;
					sb.Append(c); i++;
					while (i < src.Length)
					{
						char sc = src[i];
						sb.Append(sc);
						if (sc == '\\') { i++; if (i < src.Length) { sb.Append(src[i]); i++; } continue; }
						if (sc == quote) { i++; break; }
						i++;
					}
					continue;
				}

				// Long string literal [==[...]==] — copy verbatim
				if (c == '[' && i + 1 < src.Length && (src[i + 1] == '[' || src[i + 1] == '='))
				{
					int eq = 0, j = i + 1;
					while (j < src.Length && src[j] == '=') { eq++; j++; }
					if (j < src.Length && src[j] == '[')
					{
						string closing = "]" + new string('=', eq) + "]";
						int end = src.IndexOf(closing, j + 1);
						if (end >= 0) { sb.Append(src, i, (end + closing.Length) - i); i = end + closing.Length; continue; }
					}
				}

				// Line comment --
				if (c == '-' && i + 1 < src.Length && src[i + 1] == '-')
				{
					// Long comment --[==[...]==]
					if (i + 2 < src.Length && src[i + 2] == '[')
					{
						int eq = 0, j = i + 3;
						while (j < src.Length && src[j] == '=') { eq++; j++; }
						if (j < src.Length && src[j] == '[')
						{
							string closing = "]" + new string('=', eq) + "]";
							int end = src.IndexOf(closing, j + 1);
							if (end >= 0) { i = end + closing.Length; continue; }
						}
					}
					// Regular line comment — skip to end of line
					while (i < src.Length && src[i] != '\n') i++;
					continue;
				}

				sb.Append(c);
				i++;
			}

			string result = sb.ToString();

			// ── Pass 2: collapse whitespace ───────────────────────────────────────
			// Trim each line's leading/trailing whitespace, then collapse newlines to spaces
			result = Regex.Replace(result, @"[ \t]*\r?\n[ \t]*", " ");
			// Collapse remaining multi-space runs to one space
			result = Regex.Replace(result, @"[ \t]+", " ");

			// ── Pass 3: remove spaces around purely symbolic tokens ───────────────
			// Safe: brackets, braces, semicolons, commas — never adjacent to word chars ambiguously
			result = Regex.Replace(result, @" ?([\(\)\[\]{},;]) ?", "$1");

			// String concat / field access — only strip when not between two digits
			result = Regex.Replace(result, @"([^0-9]) \.\. ", "$1..");
			result = Regex.Replace(result, @" \.\. ([^0-9])", "..$1");

			// Arithmetic ops — strip only when flanked by closing paren/bracket or digit
			result = Regex.Replace(result, @"([\)0-9_]) \* ",  "$1*");
			result = Regex.Replace(result, @" \* ([\(0-9])",    "*$1");
			result = Regex.Replace(result, @"([\)0-9_]) / ",   "$1/");
			result = Regex.Replace(result, @" / ([\(0-9])",     "/$1");
			result = Regex.Replace(result, @"([\)0-9_]) % ",   "$1%");
			result = Regex.Replace(result, @" % ([\(0-9])",     "%$1");
			result = Regex.Replace(result, @"([\)0-9_]) \^ ",  "$1^");
			result = Regex.Replace(result, @" \^ ([\(0-9])",    "^$1");

			// Comparison / equality operators — always safe to strip surrounding spaces
			result = Regex.Replace(result, @" (~=|<=|>=|==) ", "$1");

			// Assignment = — only when flanked by non-operator on at least one side
			result = Regex.Replace(result, @"([^!<>=~]) = ", "$1=");
			result = Regex.Replace(result, @" = ([^!<>=])",   "=$1");

			// Colon (method calls)
			result = Regex.Replace(result, @" ?: ?", ":");

			// Length operator #
			result = Regex.Replace(result, @"# ", "#");

			return result.Trim();
		}
	}
}
