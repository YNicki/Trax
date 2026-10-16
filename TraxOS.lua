--!strict
--[[
	TraxOS — Dynamic Island com bolinha de atividades
	LocalScript em StarterPlayer > StarterPlayerScripts (ou direto no executor).
	(em StarterGui a UI seria duplicada a cada respawn)

	Ilha: toque na pílula para expandir; toque no cabeçalho para recolher.
	Recolhe sozinha após CONFIG.idleCollapseSeconds sem interação (0 desliga).

	Bolinha: só existe com a ilha FECHADA e uma atividade em andamento. Ao
	fechar a ilha ela desgruda (estica, afina o pescoço e solta); ao abrir a
	ilha ela é reabsorvida. Tocar na bolinha abre a ilha.

	Vidro líquido: toggle e slider usam o módulo LiquidGlass quando ele é achado
	(ModuleScript "LiquidGlass" filho deste script ou em ReplicatedStorage; no
	executor: getgenv().LiquidGlass = loadstring(<código do módulo>)() antes de
	rodar este arquivo). Sem o módulo a ilha usa o switch plano e sem o slider.

	Ícones: Lucide (padrão) ou Craft, pela biblioteca Footagesus/Icons — nomes
	"zap", "lucide:zap", "craft:nome" — ou "rbxassetid://123". A biblioteca é
	baixada por HttpGet (executor); no Studio puro isso não existe e os ícones
	por nome ficam de fora (use rbxassetid://).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer or Players.PlayerAdded:Wait()
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

---------------------------------------------------------------- config
type IconNames = { logo: string, toggle: string, slider: string, dropdown: string, active: string }

type Config = {
	name: string,
	iconSet: string,
	icons: IconNames,
	toggleLabel: string,
	sliderLabel: string,
	dropdownLabel: string,
	options: { string },
	defaultOption: number,
	defaultToggle: boolean,
	defaultSlider: number,
	glass: { [string]: any },
	onSlide: ((value: number) -> ())?,
	idleCollapseSeconds: number,
	topOffset: number,
	accent: Color3,
	onToggle: ((on: boolean) -> ())?,
	onSelect: ((option: string, index: number) -> ())?,
}

local CONFIG: Config = {
	name = "TraxOS",
	iconSet = "lucide", -- "lucide" ou "craft": conjunto usado pelos nomes sem prefixo
	icons = {
		logo = "zap",
		toggle = "power",
		dropdown = "gauge",
		slider = "sun",
		active = "activity", -- ícone da bolinha no modo "active"
	},
	toggleLabel = "Modo ativo",
	sliderLabel = "Brilho",
	dropdownLabel = "Qualidade",
	options = { "Baixa", "Média", "Alta" },
	defaultOption = 3,
	defaultToggle = true,
	defaultSlider = 0.7, -- 0..1
	-- repassado ao LiquidGlass (toggle e slider): distortion, elasticity, reflection,
	-- transparency, speed, dispersion, stretch, pressScale, shadow, layers, tint
	glass = {
		distortion = 0.6,
		elasticity = 0.6,
		reflection = 0.7,
		dispersion = 0.5,
	},
	onSlide = function(value: number)
		print("[TraxOS] slider:", value) -- troque pela sua lógica
	end,
	idleCollapseSeconds = 5,
	topOffset = 10,
	accent = Color3.fromRGB(10, 132, 255),
	onToggle = function(on: boolean)
		print("[TraxOS] toggle:", on) -- troque pela sua lógica
	end,
	onSelect = function(option: string, index: number)
		print("[TraxOS] opção:", option, index) -- troque pela sua lógica
	end,
}

-- sem opções não existe dropdown: falha cedo em vez de montar uma UI quebrada
assert(#CONFIG.options > 0, "TraxOS: CONFIG.options precisa de ao menos 1 item")

---------------------------------------------------------------- LiquidGlass (opcional)
-- Procura o módulo em três lugares, nesta ordem: ModuleScript "LiquidGlass" filho
-- deste script, ModuleScript em ReplicatedStorage, ou getgenv().LiquidGlass (executor:
-- getgenv().LiquidGlass = loadstring(<código do módulo>)()). Sem módulo, a ilha usa o
-- switch e o slider planos, sem vidro.
local function loadLiquidGlass(): any
	local env: any = getfenv()
	local genv: any = env.getgenv
	if type(genv) == "function" then
		local ok, shared = pcall(genv)
		if ok and type(shared) == "table" and type((shared :: any).LiquidGlass) == "table" then
			return (shared :: any).LiquidGlass
		end
	end
	local candidates: { Instance? } = {}
	local okScript, selfScript = pcall(function()
		return (script :: any)
	end)
	if okScript and typeof(selfScript) == "Instance" then
		table.insert(candidates, selfScript:FindFirstChild("LiquidGlass"))
	end
	table.insert(candidates, game:GetService("ReplicatedStorage"):FindFirstChild("LiquidGlass"))
	for _, candidate in candidates do
		if candidate and candidate:IsA("ModuleScript") then
			local ok, lib = pcall(require, candidate)
			if ok and type(lib) == "table" then
				return lib
			end
		end
	end
	return nil
end

local LiquidGlass: any = loadLiquidGlass()

---------------------------------------------------------------- tema e geometria
local COLOR = {
	bg = Color3.new(0, 0, 0),
	text = Color3.new(1, 1, 1),
	subtext = Color3.fromRGB(152, 152, 157),
	track = Color3.fromRGB(58, 58, 60),
	control = Color3.fromRGB(44, 44, 46),
	controlActive = Color3.fromRGB(72, 72, 74),
	panel = Color3.fromRGB(28, 28, 30),
	accent = CONFIG.accent,
	on = Color3.fromRGB(48, 209, 88),
}

local FAMILY = "rbxasset://fonts/families/GothamSSm.json"
local FONT = {
	medium = Font.new(FAMILY, Enum.FontWeight.Medium),
	semibold = Font.new(FAMILY, Enum.FontWeight.SemiBold),
	bold = Font.new(FAMILY, Enum.FontWeight.Bold),
}

-- ilha
local W, PAD = 276, 16
local COLLAPSED = Vector2.new(120, 34)
local TILE_L, TILE_S = 32, 26 -- ícone do cabeçalho / das linhas
local ROW_H, OPT_H = 30, 30
local Y_HEADER, Y_BAR, Y_TOGGLE, Y_SLIDER = 14, 58, 78, 116
-- com vidro entra a linha do slider e o dropdown desce; sem módulo o layout é o antigo
local Y_DROP = if LiquidGlass ~= nil then 154 else 116
local SWITCH_W, SWITCH_H, KNOB, DROP_W, DROP_H = 58, 28, 24, 112, 28
local SLIDER_LEN, SLIDER_THUMB = 124, 30
local EXPANDED_RADIUS = 30
local TEXT_X = PAD + TILE_S + 10 -- onde começam os rótulos das linhas

local OPTIONS_Y = Y_DROP + ROW_H + 6
local BASE_H = Y_DROP + ROW_H + PAD
local OPEN_H = OPTIONS_Y + #CONFIG.options * OPT_H + PAD

local SIZE_COLLAPSED = UDim2.fromOffset(COLLAPSED.X, COLLAPSED.Y)
local SIZE_EXPANDED = UDim2.fromOffset(W, BASE_H)
local SIZE_OPEN = UDim2.fromOffset(W, OPEN_H)
local PILL = UDim.new(1, 0)

-- bolinha (coordenadas do "palco": mesmo centro da ilha, X a partir da esquerda do palco)
local BUBBLE, GAP = 34, 8 -- diâmetro e distância final até a ilha
local RING_D, RING_T, RING_INSET = 28, 3, 4
local STAGE_W = COLLAPSED.X + (GAP + BUBBLE + 6) * 2
local TRAVEL = GAP + BUBBLE
local XR = (STAGE_W + COLLAPSED.X) / 2 -- borda direita da ilha recolhida
local DETACH_TIME, ABSORB_TIME, DETACH_DELAY, DONE_HOLD = 0.72, 0.4, 0.2, 1.6
local LEAD_BACK, TRAIL_BACK, TRAIL_DELAY = 0.9, 0.55, 0.12 -- borda da frente x borda de trás
local STROKE_T = 0.88 -- contorno discreto da ilha e da bolinha

-- Back só na abertura: o overshoot dá o "pulo" característico da ilha
local EXPAND = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local COLLAPSE = TweenInfo.new(0.36, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)
local RESIZE = TweenInfo.new(0.34, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local FAST = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FADE_IN = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0.1)
local SNAP = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local POP = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

-- anel de progresso: dois semicírculos recortados + UIGradient com degrau em 0.5.
-- Girar o gradiente de 0 a 180 (direita) e de 180 a 360 (esquerda) varre o anel.
local STEP = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.5, 0),
	NumberSequenceKeypoint.new(0.501, 1),
	NumberSequenceKeypoint.new(1, 1),
})
-- arco com cauda suave para o modo "loading" (gira o gradiente, não o frame:
-- ClipsDescendants não funciona em frames rotacionados)
local SWEEP = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.22, 0),
	NumberSequenceKeypoint.new(0.5, 1),
	NumberSequenceKeypoint.new(1, 1),
})

---------------------------------------------------------------- helpers
type OptionRow = { button: TextButton, label: TextLabel, dot: Frame }
type IconRef = { image: ImageLabel, name: string, fallback: Frame? }
type ActivityKind = "progress" | "active" | "loading" | "done"
type ActivityOptions = { icon: string?, label: string? }
type Activity = { kind: ActivityKind, icon: string?, label: string? }

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

-- easeOutBack com overshoot ajustável (t em 0..1; em t = 1 vale exatamente 1)
local function outBack(t: number, overshoot: number): number
	local u = t - 1
	return 1 + (overshoot + 1) * u * u * u + overshoot * u * u
end

-- Devolve a instância tipada; as props vêm de uma tabela dinâmica
local function apply<T>(inst: T, props: { [string]: any }, parent: Instance?): T
	local target: any = inst
	for key, value in props do
		target[key] = value
	end
	target.Parent = parent -- por último: um único reflow em vez de um por propriedade
	return inst
end

local function makeLabel(parent: Instance, props: { [string]: any }): TextLabel
	local merged: { [string]: any } = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		FontFace = FONT.medium,
		TextSize = 13,
		TextColor3 = COLOR.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}
	for key, value in props do
		merged[key] = value
	end
	return apply(Instance.new("TextLabel"), merged, parent)
end

local function round(parent: Instance, radius: UDim): UICorner
	return apply(Instance.new("UICorner"), { CornerRadius = radius }, parent)
end

-- Um tween ativo por instância: religar o mesmo alvo cancela o anterior
-- em vez de brigar com ele (cliques rápidos não deixam estado pela metade)
local running: { [Instance]: Tween } = setmetatable({}, { __mode = "k" }) :: any

local function play(inst: Instance, info: TweenInfo, goal: { [string]: any })
	local previous = running[inst]
	if previous then
		previous:Cancel()
	end
	local tween = TweenService:Create(inst, info, goal)
	running[inst] = tween
	tween:Play()
end

---------------------------------------------------------------- ícones (Lucide / Craft)
local ICONS_URL = "https://raw.githubusercontent.com/Footagesus/Icons/main/Main-v2.lua"

local iconRefs: { IconRef } = {}
local iconLib: any = nil
local iconsTried = false

-- nome -> imagem. Aceita "zap", "lucide:zap", "craft:nome", "rbxassetid://1" ou 1
local function resolveIcon(name: string): string?
	if name == "" then
		return nil
	end
	if string.find(name, "rbxasset", 1, true) or string.find(name, "^https?://") then
		return name
	end
	if tonumber(name) then
		return "rbxassetid://" .. name
	end
	local lib = iconLib
	if lib == nil then
		return nil
	end
	local ok, result = pcall(function()
		return lib.GetIcon(name)
	end)
	if ok and type(result) == "string" and result ~= "" then
		return result
	end
	return nil
end

local function refreshIcon(ref: IconRef)
	local image = resolveIcon(ref.name)
	if image then
		ref.image.Image = image
		ref.image.Visible = true
		play(ref.image, FAST, { ImageTransparency = 0 })
		if ref.fallback then
			ref.fallback.Visible = false
		end
	elseif iconsTried then
		ref.image.Visible = false
		if ref.fallback then
			ref.fallback.Visible = ref.name ~= ""
		end
	end
end

-- fallbackColor: se o ícone não carregar, mostra um pontinho dessa cor no lugar
local function makeIcon(parent: Instance, name: string, props: { [string]: any }, fallbackColor: Color3?): IconRef
	local merged: { [string]: any } = {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ImageTransparency = 1, -- entra com fade quando o ícone resolve
		ScaleType = Enum.ScaleType.Fit,
	}
	for key, value in props do
		merged[key] = value
	end
	local image = apply(Instance.new("ImageLabel"), merged, parent)
	local fallback: Frame? = nil
	if fallbackColor then
		local dot = apply(Instance.new("Frame"), {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(6, 6),
			BackgroundColor3 = fallbackColor,
			BorderSizePixel = 0,
			Visible = false,
		}, parent)
		round(dot, PILL)
		fallback = dot
	end
	local ref: IconRef = { image = image, name = name, fallback = fallback }
	table.insert(iconRefs, ref)
	refreshIcon(ref)
	return ref
end

-- quadradinho arredondado com ícone (cabeçalho e linhas)
local function makeTile(
	parent: Instance,
	position: UDim2,
	size: number,
	iconName: string,
	tint: Color3,
	fill: Color3,
	fillTransparency: number
): Frame
	local tile = apply(Instance.new("Frame"), {
		Position = position,
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = fill,
		BackgroundTransparency = fillTransparency,
		BorderSizePixel = 0,
	}, parent)
	round(tile, UDim.new(0, math.floor(size * 0.32)))
	local inner = math.floor(size * 0.58)
	makeIcon(tile, iconName, { Size = UDim2.fromOffset(inner, inner), ImageColor3 = tint }, tint)
	return tile
end

local function fetchSource(url: string): string?
	local http: any = game
	local ok, body = pcall(function()
		return http:HttpGetAsync(url)
	end)
	if ok and type(body) == "string" then
		return body
	end
	ok, body = pcall(function()
		return http:HttpGet(url)
	end)
	if ok and type(body) == "string" then
		return body
	end
	return nil
end

---------------------------------------------------------------- UI
local function resolveGuiParent(): Instance
	local env: any = getfenv()
	local getHui: any = env.gethui
	if type(getHui) == "function" then
		local ok, container = pcall(getHui)
		if ok and typeof(container) == "Instance" then
			return container
		end
	end
	return playerGui
end

local guiParent = resolveGuiParent()
for _, root in { guiParent, playerGui } do
	local old = root:FindFirstChild("TraxOS")
	if old then
		old:Destroy() -- reexecutar não empilha ilhas
	end
end

local gui = apply(Instance.new("ScreenGui"), {
	Name = "TraxOS",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 100,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, nil)

-- bolinha ---------------------------------------------------------------
-- Palco com o mesmo centro da ilha, ATRÁS dela (ZIndex 1 < 2). Os filhos usam
-- ESCALA: Offset é inteiro e faria a animação andar de 1 em 1 px.
local stage = apply(Instance.new("Frame"), {
	Name = "Stage",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, CONFIG.topOffset),
	Size = UDim2.fromOffset(STAGE_W, COLLAPSED.Y),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ZIndex = 1,
}, gui)

-- "pescoço" que liga a ilha à bolinha enquanto ela se solta
local neck = apply(Instance.new("Frame"), {
	Name = "Neck",
	BackgroundColor3 = COLOR.bg,
	BorderSizePixel = 0,
	Visible = false,
}, stage)
round(neck, PILL)

-- cápsula: vira círculo quando termina de se soltar
local bubble = apply(Instance.new("Frame"), {
	Name = "Bubble",
	BackgroundColor3 = COLOR.bg,
	BorderSizePixel = 0,
	Visible = false,
}, stage)
round(bubble, PILL)
local bubbleStroke = apply(Instance.new("UIStroke"), {
	Color = COLOR.text,
	Transparency = STROKE_T,
	Thickness = 1,
	ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
}, bubble)

local bubbleHit = apply(Instance.new("TextButton"), {
	Name = "Hit",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	AutoButtonColor = false,
	Text = "",
	ZIndex = 5,
	Visible = false,
}, bubble)

local bubbleContent = apply(Instance.new("CanvasGroup"), {
	Name = "Content",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(BUBBLE, BUBBLE),
	BackgroundTransparency = 1,
	GroupTransparency = 1,
}, bubble)

-- anel (progress / loading)
local ringHolder = apply(Instance.new("Frame"), {
	Name = "Ring",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(RING_D, RING_D),
	BackgroundTransparency = 1,
	Visible = false,
}, bubbleContent)

-- círculo só com contorno; o UIStroke fica por fora do frame, então o círculo
-- é menor que o anel (RING_INSET) para o traço nunca encostar na borda do recorte
local function ringCircle(parent: Instance, name: string, position: UDim2, size: UDim2, color: Color3): (Frame, UIStroke)
	local circle = apply(Instance.new("Frame"), {
		Name = name,
		Position = position,
		Size = size,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, parent)
	round(circle, PILL)
	local stroke = apply(Instance.new("UIStroke"), {
		Color = color,
		Thickness = RING_T,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, circle)
	return circle, stroke
end

local FULL = UDim2.new(1, -RING_INSET * 2, 1, -RING_INSET * 2)
local HALF = UDim2.new(2, -RING_INSET * 2, 1, -RING_INSET * 2)
ringCircle(ringHolder, "Track", UDim2.fromOffset(RING_INSET, RING_INSET), FULL, COLOR.track)

local rightClip = apply(Instance.new("Frame"), {
	Name = "RightClip",
	Position = UDim2.fromScale(0.5, 0),
	Size = UDim2.fromScale(0.5, 1),
	BackgroundTransparency = 1,
	ClipsDescendants = true,
}, ringHolder)
local _, rightStroke = ringCircle(rightClip, "Arc", UDim2.new(-1, RING_INSET, 0, RING_INSET), HALF, COLOR.accent)
local rightGradient = apply(Instance.new("UIGradient"), { Transparency = STEP, Rotation = 0 }, rightStroke)

local leftClip = apply(Instance.new("Frame"), {
	Name = "LeftClip",
	Position = UDim2.fromScale(0, 0),
	Size = UDim2.fromScale(0.5, 1),
	BackgroundTransparency = 1,
	ClipsDescendants = true,
}, ringHolder)
local _, leftStroke = ringCircle(leftClip, "Arc", UDim2.fromOffset(RING_INSET, RING_INSET), HALF, COLOR.accent)
local leftGradient = apply(Instance.new("UIGradient"), { Transparency = STEP, Rotation = 180 }, leftStroke)

local spinCircle, spinStroke =
	ringCircle(ringHolder, "Spinner", UDim2.fromOffset(RING_INSET, RING_INSET), FULL, COLOR.accent)
spinCircle.Visible = false
local spinGradient = apply(Instance.new("UIGradient"), { Transparency = SWEEP, Rotation = 0 }, spinStroke)

-- modo "active": disco suave + pontinho + onda que se espalha
local activeGroup = apply(Instance.new("Frame"), {
	Name = "Active",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Visible = false,
}, bubbleContent)
local activeDisc = apply(Instance.new("Frame"), {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(24, 24),
	BackgroundColor3 = COLOR.on,
	BackgroundTransparency = 0.82,
	BorderSizePixel = 0,
}, activeGroup)
round(activeDisc, PILL)
local pulseRing = apply(Instance.new("Frame"), {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.62, 0.62),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
}, activeGroup)
round(pulseRing, PILL)
local pulseStroke = apply(Instance.new("UIStroke"), {
	Color = COLOR.on,
	Transparency = 1,
	Thickness = 2,
	ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
}, pulseRing)
local activeDot = apply(Instance.new("Frame"), {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(8, 8),
	BackgroundColor3 = COLOR.on,
	BorderSizePixel = 0,
}, activeGroup)
round(activeDot, PILL)

-- modo "done": disco verde com check desenhado (sem depender de ícone)
local doneGroup = apply(Instance.new("Frame"), {
	Name = "Done",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Visible = false,
}, bubbleContent)
local doneDisc = apply(Instance.new("Frame"), {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(26, 26),
	BackgroundColor3 = COLOR.on,
	BorderSizePixel = 0,
}, doneGroup)
round(doneDisc, PILL)
local doneCheck = apply(Instance.new("Frame"), {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.54, 0.54),
	BackgroundTransparency = 1,
}, doneDisc)
-- dois traços num quadro 14x14: { centroX, centroY, comprimento, ângulo }
for _, seg in { { 3.95, 9.35, 4.95, 45 }, { 8.75, 7.55, 9.36, -49.3 } } do
	local bar = apply(Instance.new("Frame"), {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(seg[1] / 14, seg[2] / 14),
		Size = UDim2.fromScale((seg[3] + 1.2) / 14, 2.4 / 14),
		Rotation = seg[4],
		BackgroundColor3 = COLOR.text,
		BorderSizePixel = 0,
	}, doneCheck)
	round(bar, PILL)
end

local percentLabel = makeLabel(bubbleContent, {
	Name = "Percent",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(BUBBLE, BUBBLE),
	FontFace = FONT.bold,
	TextSize = 10,
	TextXAlignment = Enum.TextXAlignment.Center,
	TextTruncate = Enum.TextTruncate.None,
	Text = "0",
	Visible = false,
})
-- ícone central opcional (activity.icon, ou CONFIG.icons.active no modo "active")
local centerRef = makeIcon(bubbleContent, "", { Size = UDim2.fromOffset(14, 14), Visible = false }, nil)

-- ilha --------------------------------------------------------------------
local island = apply(Instance.new("Frame"), {
	Name = "Island",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, CONFIG.topOffset),
	Size = SIZE_COLLAPSED,
	BackgroundColor3 = COLOR.bg,
	BorderSizePixel = 0,
	ClipsDescendants = true,
	Active = true, -- sem isso o clique "vaza" para o jogo (ex.: ativa ferramenta)
	ZIndex = 2,
}, gui)
local corner = round(island, UDim.new(0, COLLAPSED.Y / 2))
local islandStroke = apply(Instance.new("UIStroke"), {
	Color = COLOR.text,
	Transparency = STROKE_T,
	Thickness = 1,
	ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
}, island)
local scale = apply(Instance.new("UIScale"), { Scale = 1 }, island)

-- vista compacta: logo + nome ---------------------------------------
local compact = apply(Instance.new("CanvasGroup"), {
	Name = "Compact",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0),
	Size = SIZE_COLLAPSED,
	BackgroundTransparency = 1,
	ZIndex = 2,
}, island)
local compactRow = apply(Instance.new("Frame"), {
	Name = "Row",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
}, compact)
apply(Instance.new("UIListLayout"), {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 7),
}, compactRow)
makeIcon(compactRow, CONFIG.icons.logo, {
	LayoutOrder = 1,
	Size = UDim2.fromOffset(16, 16),
	ImageColor3 = COLOR.accent,
}, nil)
local compactName = makeLabel(compactRow, {
	Name = "Name",
	LayoutOrder = 2,
	AutomaticSize = Enum.AutomaticSize.X,
	Size = UDim2.fromOffset(0, 16),
	FontFace = FONT.bold,
	TextTruncate = Enum.TextTruncate.None,
	Text = CONFIG.name,
})

-- por cima de tudo enquanto recolhida; escondido quando expandida
local hit = apply(Instance.new("TextButton"), {
	Name = "Hit",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	AutoButtonColor = false,
	Text = "",
	ZIndex = 5,
}, island)

-- vista expandida ---------------------------------------------------
-- Altura máxima fixa: a ilha recorta o que ainda não cabe enquanto cresce.
local expandedGroup = apply(Instance.new("CanvasGroup"), {
	Name = "Expanded",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0),
	Size = UDim2.fromOffset(W, OPEN_H),
	BackgroundTransparency = 1,
	GroupTransparency = 1,
	Visible = false,
	ZIndex = 3,
}, island)

-- criado antes dos textos: os labels não capturam input, o clique chega aqui
local header = apply(Instance.new("TextButton"), {
	Name = "Header",
	Size = UDim2.fromOffset(W, Y_BAR - 6),
	BackgroundTransparency = 1,
	AutoButtonColor = false,
	Text = "",
}, expandedGroup)
makeTile(
	expandedGroup,
	UDim2.fromOffset(PAD, Y_HEADER),
	TILE_L,
	CONFIG.icons.logo,
	COLOR.accent,
	COLOR.accent,
	0.82
)
local titleLabel = makeLabel(expandedGroup, {
	Name = "Title",
	Position = UDim2.fromOffset(PAD + TILE_L + 10, Y_HEADER),
	Size = UDim2.fromOffset(W - PAD * 2 - TILE_L - 10 - 56, 16),
	FontFace = FONT.bold,
	TextSize = 14,
	Text = CONFIG.name,
})
local statusLabel = makeLabel(expandedGroup, {
	Name = "Status",
	Position = UDim2.fromOffset(PAD + TILE_L + 10, Y_HEADER + 17),
	Size = UDim2.fromOffset(W - PAD * 2 - TILE_L - 10 - 56, 15),
	TextSize = 11,
	TextColor3 = COLOR.subtext,
	Text = "Pronto",
})
local expandedPercent = makeLabel(expandedGroup, {
	Name = "Percent",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromOffset(W - PAD, Y_HEADER + 7),
	Size = UDim2.fromOffset(52, 18),
	FontFace = FONT.semibold,
	TextColor3 = COLOR.accent,
	TextXAlignment = Enum.TextXAlignment.Right,
	Text = "0%",
	Visible = false,
})
local bigTrack = apply(Instance.new("Frame"), {
	Name = "Track",
	Position = UDim2.fromOffset(PAD, Y_BAR),
	Size = UDim2.fromOffset(W - PAD * 2, 6),
	BackgroundColor3 = COLOR.track,
	BorderSizePixel = 0,
}, expandedGroup)
round(bigTrack, PILL)
local bigFill = apply(Instance.new("Frame"), {
	Name = "Fill",
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = COLOR.accent,
	BorderSizePixel = 0,
}, bigTrack)
round(bigFill, PILL)

-- toggle ------------------------------------------------------------
makeTile(
	expandedGroup,
	UDim2.fromOffset(PAD, Y_TOGGLE + (ROW_H - TILE_S) / 2),
	TILE_S,
	CONFIG.icons.toggle,
	COLOR.text,
	COLOR.control,
	0
)
makeLabel(expandedGroup, {
	Name = "ToggleLabel",
	Position = UDim2.fromOffset(TEXT_X, Y_TOGGLE),
	Size = UDim2.fromOffset(W - TEXT_X - SWITCH_W - PAD - 8, ROW_H),
	Text = CONFIG.toggleLabel,
})
local switch = apply(Instance.new("TextButton"), {
	Name = "Toggle",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromOffset(W - PAD, Y_TOGGLE + (ROW_H - SWITCH_H) / 2),
	Size = UDim2.fromOffset(SWITCH_W, SWITCH_H),
	BackgroundColor3 = COLOR.track,
	BorderSizePixel = 0,
	AutoButtonColor = false,
	Text = "",
}, expandedGroup)
round(switch, PILL)
local knob = apply(Instance.new("Frame"), {
	Name = "Knob",
	Position = UDim2.fromOffset(2, 2),
	Size = UDim2.fromOffset(KNOB, KNOB),
	BackgroundColor3 = COLOR.text,
	BorderSizePixel = 0,
}, switch)
round(knob, PILL)

-- vidro líquido: toggle e slider ---------------------------------------
-- Os callbacks passam por glassHooks porque setToggle/touch só existem mais abaixo.
local glassHooks: { toggle: ((boolean) -> ())?, slide: ((number) -> ())? } = {}
local glassToggle: any = nil
local glassSlider: any = nil

local function glassOptions(extra: { [string]: any }): { [string]: any }
	local merged: { [string]: any } = {}
	for key, value in CONFIG.glass do
		merged[key] = value
	end
	for key, value in extra do
		merged[key] = value
	end
	return merged
end

if LiquidGlass ~= nil then
	switch.Visible = false -- o switch plano fica só como reserva (sem módulo)
	local okToggle, resultToggle = pcall(function()
		return LiquidGlass.Toggle(
			expandedGroup,
			glassOptions({
				name = "GlassToggle",
				trackSize = Vector2.new(SWITCH_W, SWITCH_H),
				knobSize = Vector2.new(34, 30),
				anchorPoint = Vector2.new(1, 0),
				position = UDim2.fromOffset(W - PAD, Y_TOGGLE + (ROW_H - SWITCH_H) / 2),
				value = CONFIG.defaultToggle,
				onColor = COLOR.on,
				offColor = COLOR.track,
				backdropColor = COLOR.bg,
				onChanged = function(value: boolean)
					local hook = glassHooks.toggle
					if hook then
						hook(value)
					end
				end,
			})
		)
	end)
	if okToggle then
		glassToggle = resultToggle
	else
		switch.Visible = true -- falhou: volta ao switch plano
		warn("[TraxOS] LiquidGlass.Toggle falhou:", resultToggle)
	end

	makeTile(
		expandedGroup,
		UDim2.fromOffset(PAD, Y_SLIDER + (ROW_H - TILE_S) / 2),
		TILE_S,
		CONFIG.icons.slider,
		COLOR.text,
		COLOR.control,
		0
	)
	makeLabel(expandedGroup, {
		Name = "SliderLabel",
		Position = UDim2.fromOffset(TEXT_X, Y_SLIDER),
		Size = UDim2.fromOffset(W - TEXT_X - SLIDER_LEN - PAD - 8, ROW_H),
		Text = CONFIG.sliderLabel,
	})
	local okSlider, resultSlider = pcall(function()
		return LiquidGlass.Slider(
			expandedGroup,
			glassOptions({
				name = "GlassSlider",
				length = SLIDER_LEN,
				thumbSize = Vector2.new(SLIDER_THUMB + 6, SLIDER_THUMB),
				anchorPoint = Vector2.new(1, 0.5),
				position = UDim2.fromOffset(W - PAD, Y_SLIDER + ROW_H / 2),
				value = clamp01(CONFIG.defaultSlider),
				min = 0,
				max = 1,
				railColor = COLOR.track,
				fillColor = COLOR.accent,
				backdropColor = COLOR.bg,
				onChanged = function(value: number)
					local hook = glassHooks.slide
					if hook then
						hook(value)
					end
				end,
			})
		)
	end)
	if okSlider then
		glassSlider = resultSlider
	else
		warn("[TraxOS] LiquidGlass.Slider falhou:", resultSlider)
	end
end

-- dropdown ----------------------------------------------------------
makeTile(
	expandedGroup,
	UDim2.fromOffset(PAD, Y_DROP + (ROW_H - TILE_S) / 2),
	TILE_S,
	CONFIG.icons.dropdown,
	COLOR.text,
	COLOR.control,
	0
)
makeLabel(expandedGroup, {
	Name = "DropdownLabel",
	Position = UDim2.fromOffset(TEXT_X, Y_DROP),
	Size = UDim2.fromOffset(W - TEXT_X - DROP_W - PAD - 8, ROW_H),
	Text = CONFIG.dropdownLabel,
})
local dropdownButton = apply(Instance.new("TextButton"), {
	Name = "Dropdown",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromOffset(W - PAD, Y_DROP + (ROW_H - DROP_H) / 2),
	Size = UDim2.fromOffset(DROP_W, DROP_H),
	BackgroundColor3 = COLOR.control,
	BorderSizePixel = 0,
	AutoButtonColor = false,
	Text = "",
}, expandedGroup)
round(dropdownButton, UDim.new(0, 9))
local dropdownText = makeLabel(dropdownButton, {
	Name = "Value",
	Position = UDim2.fromOffset(10, 0),
	Size = UDim2.new(1, -32, 1, 0),
	TextSize = 12,
	Text = "",
})

-- dois traços a ±45° formam o "v"; posição em escala porque Offset é inteiro
local chevron = apply(Instance.new("Frame"), {
	Name = "Chevron",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(1, -14, 0.5, 0),
	Size = UDim2.fromOffset(12, 9),
	BackgroundTransparency = 1,
}, dropdownButton)
for _, arm in { { x = 3.5 / 12, rotation = 45 }, { x = 8.5 / 12, rotation = -45 } } do
	local bar = apply(Instance.new("Frame"), {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(arm.x, 0.5),
		Size = UDim2.fromOffset(7, 2),
		Rotation = arm.rotation,
		BackgroundColor3 = COLOR.subtext,
		BorderSizePixel = 0,
	}, chevron)
	round(bar, UDim.new(0, 1))
end

local optionsPanel = apply(Instance.new("CanvasGroup"), {
	Name = "Options",
	Position = UDim2.fromOffset(PAD, OPTIONS_Y),
	Size = UDim2.fromOffset(W - PAD * 2, #CONFIG.options * OPT_H),
	BackgroundColor3 = COLOR.panel,
	BorderSizePixel = 0,
	GroupTransparency = 1,
	Visible = false,
}, expandedGroup)
round(optionsPanel, UDim.new(0, 12))

local optionRows: { OptionRow } = {}
for index, name in CONFIG.options do
	local button = apply(Instance.new("TextButton"), {
		Name = "Option" .. index,
		Position = UDim2.fromOffset(0, (index - 1) * OPT_H),
		Size = UDim2.fromOffset(W - PAD * 2, OPT_H),
		BackgroundColor3 = COLOR.text,
		BackgroundTransparency = 1, -- só acende no hover
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
	}, optionsPanel)
	local text = makeLabel(button, {
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -40, 1, 0),
		Text = name,
	})
	local dot = apply(Instance.new("Frame"), {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(7, 7),
		BackgroundColor3 = COLOR.accent,
		BorderSizePixel = 0,
	}, button)
	round(dot, PILL)
	table.insert(optionRows, { button = button, label = text, dot = dot })
end

---------------------------------------------------------------- estado
local expanded = false
local dropdownOpen = false
local shownExpanded = false -- último estado desenhado: decide Back (abrir) vs Quint (redimensionar)
local toggled = CONFIG.defaultToggle
local selected = math.clamp(math.floor(CONFIG.defaultOption), 1, #CONFIG.options)
local lastTouch = os.clock()
local renderToken = 0
local alive = true
local connections: { RBXScriptConnection } = {}

local activity: Activity? = nil
local activityToken = 0
local shownKind: ActivityKind? = nil
local progressTarget, progressShown = 0, 0

-- bolinha: 0 = fundida na ilha, 1 = totalmente solta
local bubbleA, bubbleFrom, bubbleTo = 0, 0, 0
local bubbleStart, bubbleDur = 0, 1
local bubbleBusy = false
local bubbleGoal = 0

local function touch()
	lastTouch = os.clock()
end

local function track(connection: RBXScriptConnection)
	table.insert(connections, connection)
end

---------------------------------------------------------------- bolinha: desgrudar / reabsorver
local function updateProgressVisuals(alpha: number)
	local angle = alpha * 360
	rightGradient.Rotation = math.clamp(angle, 0, 180)
	leftGradient.Rotation = math.clamp(angle, 180, 360)
	bigFill.Size = UDim2.fromScale(alpha, 1)
end

-- Geometria a cada quadro. A borda da frente sai rápido e a de trás atrasa,
-- então a cápsula estica; o pescoço afina até soltar; depois relaxa em círculo.
local function layoutBubble(a: number)
	if a <= 0.001 then
		bubble.Visible = false
		neck.Visible = false
		bubbleHit.Visible = false
		islandStroke.Transparency = STROKE_T
		return
	end

	local lead = outBack(clamp01(a), LEAD_BACK)
	local trail = outBack(clamp01((a - TRAIL_DELAY) / (1 - TRAIL_DELAY)), TRAIL_BACK)
	local right = XR + TRAVEL * lead
	local left = XR - BUBBLE + TRAVEL * trail
	local width = right - left
	-- "squash & stretch": esticou na horizontal, achata um pouco na vertical
	local height = BUBBLE * math.clamp(1 / math.sqrt(math.max(width / BUBBLE, 0.01)), 0.82, 1.03)
	local stageH = COLLAPSED.Y

	bubble.Visible = true
	bubble.Position = UDim2.fromScale(left / STAGE_W, (stageH - height) / (2 * stageH))
	bubble.Size = UDim2.fromScale(width / STAGE_W, height / stageH)

	-- pescoço: do centro da ponta da ilha ao centro da ponta esquerda da cápsula
	local x1 = XR - BUBBLE / 2
	local x2 = left + height / 2
	local length = x2 - x1
	local neckH = 0
	if length > 0 then
		neckH = 0.9 * BUBBLE * math.clamp(1 - (length / TRAVEL) ^ 2, 0, 1) ^ 0.9
	end
	if neckH > 0.5 then
		neck.Visible = true
		neck.Position = UDim2.fromScale(x1 / STAGE_W, (stageH - neckH) / (2 * stageH))
		neck.Size = UDim2.fromScale(length / STAGE_W, neckH / stageH)
	else
		neck.Visible = false
	end

	-- o conteúdo só aparece quando a bolinha já está quase solta
	bubbleContent.GroupTransparency = 1 - clamp01((a - 0.7) / 0.3)
	bubbleHit.Visible = a > 0.9

	-- contornos somem durante o desgrude (senão o traço da ilha cortaria a bolinha)
	local outline = 1 - clamp01(a / 0.12) * clamp01((0.98 - a) / 0.18)
	local transparency = 1 - (1 - STROKE_T) * outline
	islandStroke.Transparency = transparency
	bubbleStroke.Transparency = transparency
end

local function animateBubble(goal: number, delay: number, duration: number)
	bubbleFrom = bubbleA
	bubbleTo = goal
	bubbleStart = os.clock() + delay
	bubbleDur = duration * math.max(0.35, math.abs(goal - bubbleA))
	bubbleBusy = true
end

-- A bolinha só existe com a ilha fechada e uma atividade em andamento.
-- openDelay: ao fechar a ilha, começa a soltar enquanto ela ainda encolhe.
local function syncBubble(openDelay: number)
	local goal = if (not expanded) and activity ~= nil then 1 else 0
	if goal == bubbleGoal then
		return
	end
	bubbleGoal = goal
	if goal == 1 then
		animateBubble(1, openDelay, DETACH_TIME)
	else
		animateBubble(0, 0, ABSORB_TIME)
	end
end

---------------------------------------------------------------- atividade
local function statusText(): string
	local current = activity
	if current == nil then
		return "Pronto"
	end
	if current.label then
		return current.label
	end
	if current.kind == "progress" then
		return "Carregando"
	elseif current.kind == "active" then
		return "Ativo"
	elseif current.kind == "loading" then
		return "Processando"
	end
	return "Concluído"
end

local function renderStatus()
	statusLabel.Text = statusText()
	local percent = math.floor(progressTarget * 100 + 0.5)
	local current = activity
	expandedPercent.Visible = current ~= nil and current.kind == "progress"
	expandedPercent.Text = string.format("%d%%", percent)
	percentLabel.Text = tostring(math.min(99, percent)) -- 100% vira o check
end

local function renderActivity()
	local current = activity
	if current == nil then
		return -- mantém o visual: a bolinha está sendo reabsorvida e some com o fade
	end
	local kind = current.kind
	local iconName = current.icon or (if kind == "active" then CONFIG.icons.active else "")
	local wantIcon = iconName ~= "" and (kind == "progress" or kind == "active")
	local iconReady = wantIcon and resolveIcon(iconName) ~= nil

	ringHolder.Visible = kind == "progress" or kind == "loading"
	rightClip.Visible = kind == "progress"
	leftClip.Visible = kind == "progress"
	spinCircle.Visible = kind == "loading"
	percentLabel.Visible = kind == "progress" and not wantIcon
	activeGroup.Visible = kind == "active"
	activeDot.Visible = kind == "active" and not iconReady
	doneGroup.Visible = kind == "done"

	if wantIcon then
		centerRef.name = iconName
		centerRef.image.ImageColor3 = if kind == "active" then COLOR.on else COLOR.text
		refreshIcon(centerRef)
	else
		centerRef.image.Visible = false
	end

	if kind == "done" and shownKind ~= "done" then
		doneDisc.Size = UDim2.fromOffset(0, 0)
		play(doneDisc, POP, { Size = UDim2.fromOffset(26, 26) })
	end
	shownKind = kind
end

local function endActivity()
	activityToken += 1
	activity = nil
	progressTarget, progressShown = 0, 0
	updateProgressVisuals(0)
	renderStatus()
	syncBubble(0)
end

local function setActivity(kind: ActivityKind?, options: ActivityOptions?)
	if kind == nil then
		endActivity()
		return
	end
	activityToken += 1
	activity = { kind = kind, icon = options and options.icon, label = options and options.label }
	if kind ~= "progress" and kind ~= "done" then
		progressTarget, progressShown = 0, 0
		updateProgressVisuals(0)
	end
	renderActivity()
	renderStatus()
	syncBubble(0)
end

-- mostra "concluído" e recolhe a bolinha sozinha
local function finishActivity()
	setActivity("done", nil)
	local token = activityToken
	task.delay(DONE_HOLD, function()
		if alive and token == activityToken then
			endActivity()
		end
	end)
end

local function setProgress(alpha: number): boolean
	if alpha ~= alpha then -- NaN: ignora em vez de pintar lixo
		return false
	end
	local value = math.clamp(alpha, 0, 1)
	local current = activity
	if current == nil or current.kind ~= "progress" then
		if value >= 1 then
			return true -- nada em andamento: não abre a bolinha só para concluir
		end
		progressTarget, progressShown = value, value
		updateProgressVisuals(value)
		setActivity("progress", nil)
	else
		progressTarget = value
		renderStatus()
	end
	if value >= 1 then
		finishActivity()
	end
	return true
end

---------------------------------------------------------------- render
local function renderToggle(animate: boolean)
	local knobPosition = UDim2.fromOffset(if toggled then SWITCH_W - KNOB - 2 else 2, 2)
	local color = if toggled then COLOR.on else COLOR.track
	if glassToggle then
		glassToggle:Set(toggled, not animate) -- silencioso: não redispara onChanged
	end
	if animate then
		play(knob, SNAP, { Position = knobPosition })
		play(switch, FAST, { BackgroundColor3 = color })
	else
		knob.Position = knobPosition
		switch.BackgroundColor3 = color
	end
end

local function renderSelection()
	dropdownText.Text = CONFIG.options[selected]
	for index, row in optionRows do
		local isSelected = index == selected
		row.dot.Visible = isSelected
		row.label.TextColor3 = if isSelected then COLOR.text else COLOR.subtext
	end
end

local function render()
	renderToken += 1
	local token = renderToken
	local wasExpanded = shownExpanded

	local size: UDim2
	local radius: number
	local info: TweenInfo
	if expanded then
		size = if dropdownOpen then SIZE_OPEN else SIZE_EXPANDED
		radius = EXPANDED_RADIUS
		info = if shownExpanded then RESIZE else EXPAND
	else
		size, radius, info = SIZE_COLLAPSED, COLLAPSED.Y / 2, COLLAPSE
	end
	shownExpanded = expanded

	play(island, info, { Size = size })
	play(corner, info, { CornerRadius = UDim.new(0, radius) })
	play(scale, FAST, { Scale = 1 })
	hit.Visible = not expanded

	if expanded then
		expandedGroup.Visible = true
		play(compact, FAST, { GroupTransparency = 1 })
		play(expandedGroup, FADE_IN, { GroupTransparency = 0 })
	else
		play(expandedGroup, FAST, { GroupTransparency = 1 })
		play(compact, FADE_IN, { GroupTransparency = 0 })
	end

	local showOptions = expanded and dropdownOpen
	play(chevron, FAST, { Rotation = if showOptions then 180 else 0 })
	play(dropdownButton, FAST, { BackgroundColor3 = if showOptions then COLOR.controlActive else COLOR.control })
	if showOptions then
		optionsPanel.Visible = true
		play(optionsPanel, FAST, { GroupTransparency = 0 })
	else
		play(optionsPanel, FAST, { GroupTransparency = 1 })
	end

	-- esconde só depois do fade; invisível, o card não intercepta cliques da pílula.
	-- O token descarta o callback se outro render começou nesse meio tempo.
	task.delay(FAST.Time, function()
		if token ~= renderToken then
			return
		end
		expandedGroup.Visible = expanded
		optionsPanel.Visible = expanded and dropdownOpen
	end)

	syncBubble(if wasExpanded then DETACH_DELAY else 0)
end

---------------------------------------------------------------- ações
local function setExpanded(value: boolean)
	if value == expanded then
		return
	end
	expanded = value
	if not value then
		dropdownOpen = false
	end
	touch()
	render()
end

local function setDropdownOpen(value: boolean)
	if not expanded or value == dropdownOpen then
		return
	end
	dropdownOpen = value
	touch()
	render()
end

local function setName(text: string)
	titleLabel.Text = text
	compactName.Text = text
end

local function setToggle(value: boolean)
	if value == toggled then
		return
	end
	toggled = value
	touch()
	renderToggle(true)
	local callback = CONFIG.onToggle
	if callback then
		task.spawn(callback, toggled) -- erro no callback do usuário não derruba a UI
	end
end

local function selectOption(index: number): boolean
	if index ~= math.floor(index) or index < 1 or index > #CONFIG.options then
		return false
	end
	local changed = index ~= selected
	selected = index
	renderSelection()
	setDropdownOpen(false)
	touch()
	local callback = CONFIG.onSelect
	if changed and callback then
		task.spawn(callback, CONFIG.options[index], index)
	end
	return true
end

local function setSlider(value: number)
	if glassSlider then
		glassSlider:Set(clamp01(value), false)
	end
end

glassHooks.toggle = function(value: boolean)
	setToggle(value)
end
glassHooks.slide = function(value: number)
	touch()
	local callback = CONFIG.onSlide
	if callback then
		task.spawn(callback, value)
	end
end

local function destroy()
	alive = false
	if glassToggle then
		glassToggle:Destroy()
	end
	if glassSlider then
		glassSlider:Destroy()
	end
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	gui:Destroy()
end

---------------------------------------------------------------- eventos
local function pressScale(target: number)
	play(scale, FAST, { Scale = target })
end

-- Activated cobre mouse, toque e gamepad
track(hit.Activated:Connect(function()
	setExpanded(true)
end))
track(bubbleHit.Activated:Connect(function()
	setExpanded(true)
end))
track(hit.MouseButton1Down:Connect(function()
	pressScale(0.95)
end))
track(hit.MouseButton1Up:Connect(function()
	pressScale(1)
end))
track(hit.MouseLeave:Connect(function()
	pressScale(1)
end))
track(header.Activated:Connect(function()
	setExpanded(false)
end))
track(switch.Activated:Connect(function()
	setToggle(not toggled)
end))
track(dropdownButton.Activated:Connect(function()
	setDropdownOpen(not dropdownOpen)
end))
track(island.MouseMoved:Connect(function()
	touch() -- lendo/pairando o mouse sobre a ilha não conta como inatividade
end))

for index, row in optionRows do
	track(row.button.Activated:Connect(function()
		selectOption(index)
	end))
	track(row.button.MouseEnter:Connect(function()
		play(row.button, FAST, { BackgroundTransparency = 0.92 })
	end))
	track(row.button.MouseLeave:Connect(function()
		play(row.button, FAST, { BackgroundTransparency = 1 })
	end))
end

-- um único laço por quadro cuida da bolinha, do anel e dos efeitos
track(RunService.RenderStepped:Connect(function(dt: number)
	local now = os.clock()

	if bubbleBusy then
		local u = math.clamp((now - bubbleStart) / bubbleDur, 0, 1)
		if bubbleTo < bubbleFrom then
			u = 0.5 - 0.5 * math.cos(math.pi * u) -- reabsorver: começa devagar, fecha rápido
		end
		bubbleA = bubbleFrom + (bubbleTo - bubbleFrom) * u
		layoutBubble(bubbleA)
		if now - bubbleStart >= bubbleDur then
			bubbleBusy = false
			bubbleA = bubbleTo
			layoutBubble(bubbleA)
		end
	end

	if progressShown ~= progressTarget then
		progressShown += (progressTarget - progressShown) * (1 - math.exp(-dt * 12))
		if math.abs(progressTarget - progressShown) < 0.0005 then
			progressShown = progressTarget
		end
		updateProgressVisuals(progressShown)
	end

	local current = activity
	if bubbleA > 0.7 and current ~= nil then
		if current.kind == "loading" then
			spinGradient.Rotation = (now * 320) % 360
		elseif current.kind == "active" then
			local p = (now % 1.6) / 1.6
			pulseRing.Size = UDim2.fromScale(0.62 + 0.36 * p, 0.62 + 0.36 * p)
			pulseStroke.Transparency = 0.25 + 0.75 * p
		end
	end
end))

-- um único laço leve em vez de um task.delay por interação
task.spawn(function()
	while alive do
		task.wait(0.25)
		local idle = CONFIG.idleCollapseSeconds
		if alive and expanded and not dropdownOpen and idle > 0 and os.clock() - lastTouch >= idle then
			setExpanded(false)
		end
	end
end)

---------------------------------------------------------------- start
renderSelection()
renderToggle(false)
renderStatus()
gui.Parent = guiParent

-- biblioteca de ícones: baixa em segundo plano; a UI já está funcionando
task.spawn(function()
	local source = fetchSource(ICONS_URL)
	if source then
		local env: any = getfenv()
		local compile: any = env.loadstring or loadstring
		local ok, lib = pcall(function()
			local chunk = compile(source)
			return chunk()
		end)
		if ok and type(lib) == "table" then
			iconLib = lib
			pcall(function()
				lib.SetIconsType(CONFIG.iconSet)
			end)
		end
	end
	iconsTried = true
	if not alive then
		return
	end
	for _, ref in iconRefs do
		refreshIcon(ref)
	end
	renderActivity()
end)

-- API para o resto do script. Para usar de outros scripts: transforme este
-- arquivo em ModuleScript, remova o DEMO e termine com `return api`.
local api = {
	setProgress = setProgress, -- 0..1: abre a bolinha em modo progress; 1 conclui
	setActivity = setActivity, -- "progress" | "active" | "loading" | "done" | nil (encerra)
	finishActivity = finishActivity,
	endActivity = endActivity,
	setName = setName,
	setToggle = setToggle,
	setSlider = setSlider, -- 0..1 (só com o módulo LiquidGlass)
	selectOption = selectOption,
	expand = function()
		setExpanded(true)
	end,
	collapse = function()
		setExpanded(false)
	end,
	destroy = destroy,
}

---------------------------------------------------------------- DEMO (apague este bloco)
task.spawn(function()
	task.wait(1.5)
	while alive do
		for step = 0, 20 do
			if not alive then
				return
			end
			api.setProgress(step / 20)
			task.wait(0.4)
		end
		task.wait(2.2) -- "concluído" aparece e a bolinha é reabsorvida
		api.setActivity("active", { label = "Modo ativo" })
		task.wait(4)
		api.setActivity("loading", { label = "Sincronizando" })
		task.wait(4)
		api.endActivity()
		task.wait(1.5)
	end
end)
