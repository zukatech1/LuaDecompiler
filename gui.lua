context:Register("SCREENGUI_TO_SCRIPT",{
		Name = "Convert to Script (Deep)",
		IconMap = Explorer.MiscIcons,
		Icon = "Save",
		OnClick = function()
			local node = selection.List[1]
			if not node or not node.Obj:IsA("ScreenGui") then return end
			local gui = node.Obj

			-- ── Serializer ───────────────────────────────────────────────────
			local function serialize(v)
				local t = typeof(v)
				if t == "string" then
					return string.format("%q", v)
				elseif t == "number" then
					-- avoid scientific notation for small/large numbers
					if v == math.floor(v) then return tostring(math.floor(v)) end
					return tostring(v)
				elseif t == "boolean" then
					return tostring(v)
				elseif t == "nil" then
					return "nil"
				elseif t == "Vector3" then
					return ("Vector3.new(%s, %s, %s)"):format(v.X, v.Y, v.Z)
				elseif t == "Vector2" then
					return ("Vector2.new(%s, %s)"):format(v.X, v.Y)
				elseif t == "UDim2" then
					return ("UDim2.new(%s, %s, %s, %s)"):format(
						v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset)
				elseif t == "UDim" then
					return ("UDim.new(%s, %s)"):format(v.Scale, v.Offset)
				elseif t == "CFrame" then
					local c = {v:GetComponents()}
					return "CFrame.new(" .. table.concat(c, ", ") .. ")"
				elseif t == "Color3" then
					return ("Color3.fromRGB(%d, %d, %d)"):format(
						math.floor(v.R*255), math.floor(v.G*255), math.floor(v.B*255))
				elseif t == "BrickColor" then
					return ("BrickColor.new(%q)"):format(v.Name)
				elseif t == "EnumItem" then
					return tostring(v)
				elseif t == "Rect" then
					return ("Rect.new(%s, %s, %s, %s)"):format(
						v.Min.X, v.Min.Y, v.Max.X, v.Max.Y)
				elseif t == "FontFace" then
					return ("Font.new(%q, Enum.FontWeight.%s, Enum.FontStyle.%s)"):format(
						v.Family, v.Weight.Name, v.Style.Name)
				elseif t == "NumberRange" then
					return ("NumberRange.new(%s, %s)"):format(v.Min, v.Max)
				elseif t == "NumberSequence" then
					local kps = {}
					for _, kp in ipairs(v.Keypoints) do
						table.insert(kps, ("NumberSequenceKeypoint.new(%s, %s, %s)"):format(
							kp.Time, kp.Value, kp.Envelope))
					end
					return "NumberSequence.new({" .. table.concat(kps, ", ") .. "})"
				elseif t == "ColorSequence" then
					local kps = {}
					for _, kp in ipairs(v.Keypoints) do
						table.insert(kps, ("ColorSequenceKeypoint.new(%s, Color3.fromRGB(%d,%d,%d))"):format(
							kp.Time,
							math.floor(kp.Value.R*255),
							math.floor(kp.Value.G*255),
							math.floor(kp.Value.B*255)))
					end
					return "ColorSequence.new({" .. table.concat(kps, ", ") .. "})"
				end
				return "nil"
			end

			-- ── Property map ─────────────────────────────────────────────────
			-- Common props shared by most visible objects
			local COMMON = {
				"Name","Size","Position","AnchorPoint","Visible","ZIndex","LayoutOrder",
				"BackgroundColor3","BackgroundTransparency","BorderColor3","BorderSizePixel",
				"ClipsDescendants","Active","Selectable","Rotation","AutomaticSize",
			}
			local function merge(t, extra)
				local r = {}
				for _,v in ipairs(t) do r[#r+1]=v end
				for _,v in ipairs(extra or {}) do r[#r+1]=v end
				return r
			end
			local propertyMap = {
				ScreenGui = {
					"Name","Enabled","ResetOnSpawn","DisplayOrder","IgnoreGuiInset",
					"ZIndexBehavior","ScreenInsets",
				},
				TextLabel = merge(COMMON, {
					"Text","RichText","TextSize","Font","FontFace",
					"TextColor3","TextTransparency","TextWrapped","TextScaled",
					"TextXAlignment","TextYAlignment","TextTruncate",
					"TextStrokeColor3","TextStrokeTransparency","LineHeight",
					"MaxVisibleGraphemes","AutoLocalize",
				}),
				TextButton = merge(COMMON, {
					"Text","RichText","TextSize","Font","FontFace",
					"TextColor3","TextTransparency","TextWrapped","TextScaled",
					"TextXAlignment","TextYAlignment","TextTruncate",
					"TextStrokeColor3","TextStrokeTransparency","LineHeight",
					"AutoButtonColor","Modal","Style",
				}),
				TextBox = merge(COMMON, {
					"Text","RichText","TextSize","Font","FontFace",
					"TextColor3","TextTransparency","TextWrapped","TextScaled",
					"TextXAlignment","TextYAlignment","PlaceholderText","PlaceholderColor3",
					"ClearTextOnFocus","MultiLine","TextEditable",
				}),
				Frame = merge(COMMON, {"Style"}),
				ScrollingFrame = merge(COMMON, {
					"CanvasSize","CanvasPosition","ScrollBarThickness",
					"ScrollBarImageColor3","ScrollBarImageTransparency",
					"ScrollingDirection","ScrollingEnabled",
					"VerticalScrollBarInset","HorizontalScrollBarInset",
					"BottomImage","MidImage","TopImage",
				}),
				ImageLabel = merge(COMMON, {
					"Image","ImageColor3","ImageTransparency","ImageRectOffset",
					"ImageRectSize","ResampleMode","ScaleType","SliceCenter","SliceScale",
					"TileSize",
				}),
				ImageButton = merge(COMMON, {
					"Image","ImageColor3","ImageTransparency","ImageRectOffset",
					"ImageRectSize","ResampleMode","ScaleType","SliceCenter","SliceScale",
					"TileSize","HoverImage","PressedImage","Style","AutoButtonColor","Modal",
				}),
				VideoFrame = merge(COMMON, {"Video","Looped","Playing","TimePosition","Volume"}),
				ViewportFrame = merge(COMMON, {"Ambient","LightColor","LightDirection"}),
				BillboardGui = {
					"Name","Active","AlwaysOnTop","Brightness","ClipsDescendants",
					"Enabled","LightInfluence","MaxDistance","Size","SizeOffset",
					"StudsOffset","StudsOffsetWorldSpace","ZIndexBehavior",
				},
				SurfaceGui = {
					"Name","Active","AlwaysOnTop","Brightness","ClipsDescendants",
					"Enabled","LightInfluence","PixelsPerStud","SizingMode","ZIndexBehavior",
				},
				-- Layout / constraint objects
				UICorner              = {"CornerRadius"},
				UIStroke              = {"Color","Thickness","Transparency","LineJoinMode","ApplyStrokeMode","Enabled"},
				UIGradient            = {"Color","Offset","Rotation","Transparency","Enabled"},
				UIPadding             = {"PaddingLeft","PaddingRight","PaddingTop","PaddingBottom"},
				UIListLayout          = {"Padding","FillDirection","HorizontalAlignment","VerticalAlignment","SortOrder","HorizontalFlex","VerticalFlex","ItemLineAlignment","Wraps"},
				UIGridLayout          = {"CellPadding","CellSize","FillDirectionMaxCells","FillDirection","HorizontalAlignment","VerticalAlignment","SortOrder","StartCorner"},
				UITableLayout         = {"FillEmptySpaceColumns","FillEmptySpaceRows","FillDirection","HorizontalAlignment","VerticalAlignment","MajorAxis","Padding","SortOrder"},
				UIAspectRatioConstraint = {"AspectRatio","AspectType","DominantAxis"},
				UISizeConstraint      = {"MinSize","MaxSize"},
				UITextSizeConstraint  = {"MinTextSize","MaxTextSize"},
				UIScale               = {"Scale"},
				UIFlexItem            = {"FlexMode","GrowRatio","ShrinkRatio"},
				UIPageLayout          = {"Animated","CircularEnabled","EasingDirection","EasingStyle","GamepadInputEnabled","Padding","ScrollWheelInputEnabled","SortOrder","TouchInputEnabled","TweenTime","FillDirection","HorizontalAlignment","VerticalAlignment"},
			}
			local function getProps(obj)
				return propertyMap[obj.ClassName]
					or merge(COMMON, {})
			end

			-- ── Script extraction (uses zukv2 bytecode path) ──────────────
			local extractedScripts = {}
			-- maps instance → variable name so parent refs are correct
			local instanceToVar = {}

			local function extractScript(scriptObj, parentVar)
				local source = ""
				-- Try zukv2 first
				local zuk = env.ZukDecompile or getgenv()._ZUK_DECOMPILE
				local okBC, bytecode = pcall(env.getscriptbytecode, scriptObj)
				if zuk and okBC and bytecode and bytecode ~= "" then
					local opts = {
						DecompilerMode="disasm", DecompilerTimeout=15, CleanMode=true, CleanMode=true,
						ReaderFloatPrecision=7, ShowDebugInformation=false,
						ShowTrivialOperations=false, ShowInstructionLines=true,
						ShowOperationIndex=true, ShowOperationNames=true,
						ListUsedGlobals=true, UseTypeInfo=true,
						EnabledRemarks={ColdRemark=false,InlineRemark=true},
						ReturnElapsedTime=false,
					}
					local okD, result = pcall(zuk, bytecode, opts)
					if okD and result then
						local pp = getgenv()._ZUK_PRETTYPRINT
						source = pp and pp(result) or result
					end
				end
				-- fallback: Source property
				if source == "" then
					local ok2, src = pcall(function() return scriptObj.Source end)
					if ok2 and src and src ~= "" then source = src end
				end
				-- fallback: env.decompile (Konstant)
				if source == "" and env.decompile then
					local ok3, res = pcall(env.decompile, scriptObj)
					if ok3 and res then source = res end
				end
				if source == "" then
					source = "-- [PROTECTED/EMPTY SCRIPT] Could not extract source\n"
				end
				local enabled = true
				pcall(function() enabled = not scriptObj.Disabled end)
				table.insert(extractedScripts, {
					parent    = parentVar,
					parentObj = instanceToVar,   -- unused, kept for debug
					className = scriptObj.ClassName,
					name      = scriptObj.Name,
					source    = source,
					enabled   = enabled,
				})
			end

			-- ── Recursive GUI code generator ──────────────────────────────
			local flatCounter = {n = 0}
			local function newVar(base)
				flatCounter.n += 1
				-- sanitize name: strip non-identifier chars, prefix if needed
				local safe = (base or "obj"):gsub("[^%w_]","_"):gsub("^(%d)","_%1")
				return safe .. "_" .. flatCounter.n
			end

			local codeLines = {}
			local function emit(s) codeLines[#codeLines+1] = s end

			-- Default values we skip to keep output clean
			local SKIP_DEFAULTS = {
				Visible                 = true,
				BackgroundTransparency  = 0,
				TextTransparency        = 0,
				ImageTransparency       = 0,
				TextStrokeTransparency  = 1,
				BorderSizePixel         = 1,
				ZIndex                  = 1,
				LayoutOrder             = 0,
				Rotation                = 0,
				AutomaticSize           = Enum.AutomaticSize.None,
				AnchorPoint             = Vector2.new(0,0),
				ClipsDescendants        = false,
				Active                  = false,
				Selectable              = false,
				RichText                = false,
				TextWrapped             = false,
				TextScaled              = false,
				TextXAlignment          = Enum.TextXAlignment.Center,
				TextYAlignment          = Enum.TextYAlignment.Center,
				AutoButtonColor         = true,
				Enabled                 = true,
				ResetOnSpawn            = true,
				DisplayOrder            = 0,
				IgnoreGuiInset          = false,
			}
			local function shouldSkip(propName, val)
				local def = SKIP_DEFAULTS[propName]
				if def == nil then return false end
				if typeof(def) ~= typeof(val) then return false end
				if typeof(val) == "Vector2" then
					return val.X == def.X and val.Y == def.Y
				end
				return val == def
			end

			local function generateGuiCode(obj, parentVar)
				local cls = obj.ClassName
				-- Scripts handled separately
				if cls == "LocalScript" or cls == "Script" or cls == "ModuleScript" then
					extractScript(obj, parentVar)
					return
				end
				local varName = newVar(obj.Name)
				instanceToVar[obj] = varName
				-- Create + parent immediately so constraints work
				emit(("local %s = Instance.new(%q)"):format(varName, cls))
				emit(("%s.Parent = %s"):format(varName, parentVar))
				-- Properties
				local props = getProps(obj)
				for _, propName in ipairs(props) do
					if propName == "Name" and obj.Name == cls then continue end
					local ok, val = pcall(function() return obj[propName] end)
					if ok and val ~= nil then
						if not shouldSkip(propName, val) then
							local s = serialize(val)
							if s ~= "nil" then
								emit(("%s.%s = %s"):format(varName, propName, s))
							end
						end
					end
				end
				-- Recurse
				for _, child in ipairs(obj:GetChildren()) do
					generateGuiCode(child, varName)
				end
			end

			-- ── Generate ─────────────────────────────────────────────────
			-- Build the GUI structure
			emit("local Players = game:GetService(\"Players\")")
			emit("local player = Players.LocalPlayer")
			emit("local playerGui = player:WaitForChild(\"PlayerGui\")")
			emit("")
			emit("-- ── GUI Structure ──────────────────────────────────────")
			emit("local function createGui()")

			-- Generate the ScreenGui itself
			local sgVar = newVar(gui.Name)
			instanceToVar[gui] = sgVar
			emit(("\tlocal %s = Instance.new(\"ScreenGui\")"):format(sgVar))
			local sgProps = getProps(gui)
			for _, propName in ipairs(sgProps) do
				local ok, val = pcall(function() return gui[propName] end)
				if ok and val ~= nil then
					if not shouldSkip(propName, val) then
						local s = serialize(val)
						if s ~= "nil" then
							emit(("\t%s.%s = %s"):format(sgVar, propName, s))
						end
					end
				end
			end

			-- Temporarily redirect emit to tab-indented
			local savedLines = codeLines
			codeLines = {}
			for _, child in ipairs(gui:GetChildren()) do
				generateGuiCode(child, sgVar)
			end
			local bodyLines = codeLines
			codeLines = savedLines
			for _, l in ipairs(bodyLines) do
				emit("\t" .. l)
			end

			emit(("\t%s.Parent = playerGui"):format(sgVar))
			emit(("\treturn %s"):format(sgVar))
			emit("end")
			emit("")

			-- Scripts section
			if #extractedScripts > 0 then
				emit(("-- ── Extracted Scripts (%d found) ─────────────────────"):format(#extractedScripts))
				for i, sd in ipairs(extractedScripts) do
					emit(("-- Script %d: %s (%s)"):format(i, sd.name, sd.className))
					emit(("local function runScript_%d(script_obj)"):format(i))
					emit("\t-- NOTE: 'script' here refers to script_obj, not the original instance.")
					emit("\tlocal script = script_obj")
					for line in (sd.source .. "\n"):gmatch("[^\n]*\n") do
						emit("\t" .. line:gsub("\n$",""))
					end
					emit("end")
					emit("")
				end
			end

			-- Init
			emit("-- ── Init ────────────────────────────────────────────────")
			emit("local gui = createGui()")
			emit("")
			if #extractedScripts > 0 then
				for i, sd in ipairs(extractedScripts) do
					-- Use the actual instance name for FindFirstChild so it works at runtime
					local parentRef
					if sd.parent == sgVar then
						parentRef = "gui"
					else
						parentRef = ("gui:FindFirstChild(%q, true)"):format(
							-- extract the real name from the varName prefix
							sd.parent:match("^(.+)_%d+$") or sd.parent)
					end
					emit(("-- Run: %s"):format(sd.name))
					emit("task.spawn(function()")
					emit(("\tlocal parent = %s"):format(parentRef))
					emit("\tif parent then")
					emit(("\t\trunScript_%d(parent)"):format(i))
					emit("\telse")
					emit(("\t\twarn('[DeepGUI] Parent not found for script: %s')"):format(sd.name))
					emit("\tend")
					emit("end)")
					emit("")
				end
			end

			-- ── Assemble output ───────────────────────────────────────────
			local header = table.concat({
				"--[[",
				"    ╔═══════════════════════════════════════════════════════╗",
				"    ║         DEEP GUI CONVERTER  (zukv2)                   ║",
				"    ╚═══════════════════════════════════════════════════════╝",
				"    ScreenGui : " .. gui.Name,
				"    Extracted : " .. os.date("%Y-%m-%d %H:%M:%S"),
				"    Scripts   : " .. #extractedScripts,
				"--]]",
				"",
			}, "\n")
			local output = header .. table.concat(codeLines, "\n")

			-- Show in Notepad
			ScriptViewer.ViewRaw(output)

			-- Copy to clipboard
			local copied = false
			if env.setclipboard then
				copied = pcall(env.setclipboard, output)
			end
			if not copied then
				pcall(setclipboard, output)
			end

			if getgenv().DoNotif then
				getgenv().DoNotif(
					("✓ GUI converted — %d element(s), %d script(s)"):format(
						flatCounter.n, #extractedScripts), 4)
			end
		end
		})
