defmodule FunSheepWeb.SheepMascot do
  @moduledoc """
  Sheep mascot component with multiple emotional states.

  The sheep's appearance changes based on the student's study behavior,
  streak status, and test proximity. Wool level reflects streak length.

  ## States
  - `:studying` — Sheep with glasses, reading (default active state)
  - `:encouraging` — Sheep waving a flag, cheering
  - `:celebrating` — Sheep jumping with joy
  - `:worried` — Sheep pacing nervously (test close + low readiness)
  - `:sleeping` — Sheep curled up with zzz (inactive 24h+)
  - `:sheared` — Sheep with no wool (streak broken)
  - `:fluffy` — Extra fluffy wool (long streak)
  - `:golden_fleece` — Glowing golden sheep (100% readiness)
  - `:shepherd` — Sheep with crook (study guide mode)
  - `:flash_card` — Sheep flipping cards (quick test mode)
  """

  use Phoenix.Component
  import Phoenix.HTML, only: [raw: 1]

  attr :state, :atom, default: :studying
  attr :size, :string, default: "md"
  attr :message, :string, default: nil
  attr :class, :string, default: ""
  attr :wool_level, :integer, default: 3
  attr :animate, :boolean, default: true

  def sheep(assigns) do
    size_class = size_to_class(assigns.size)
    assigns = assign(assigns, :size_class, size_class)

    ~H"""
    <div class={"inline-flex flex-col items-center gap-1 #{@class}"}>
      <div class={[
        @size_class,
        @animate && state_animation(@state)
      ]}>
        {raw(sheep_svg(@state, @wool_level))}
      </div>
      <div :if={@message} class="max-w-[200px] text-center">
        <div class="bg-white rounded-2xl shadow-md border border-gray-100 px-3 py-2 text-xs font-medium text-gray-700 relative">
          <div class="absolute -top-1.5 left-1/2 -translate-x-1/2 w-3 h-3 bg-white border-l border-t border-gray-100 rotate-45">
          </div>
          {@message}
        </div>
      </div>
    </div>
    """
  end

  @doc "Renders a small inline sheep emoji-style for use in text."
  attr :state, :atom, default: :studying
  attr :class, :string, default: ""

  def sheep_inline(assigns) do
    ~H"""
    <span class={"inline-block w-6 h-6 #{@class}"}>
      {raw(sheep_svg(@state, 3))}
    </span>
    """
  end

  # ── Size mapping ──────────────────────────────────────────────────────────

  defp size_to_class("xs"), do: "w-8 h-8"
  defp size_to_class("sm"), do: "w-12 h-12"
  defp size_to_class("md"), do: "w-20 h-20"
  defp size_to_class("lg"), do: "w-32 h-32"
  defp size_to_class("xl"), do: "w-48 h-48"
  defp size_to_class("2xl"), do: "w-64 h-64"
  defp size_to_class(_), do: "w-20 h-20"

  # ── Animation classes per state ───────────────────────────────────────────

  defp state_animation(:celebrating), do: "animate-bounce"
  defp state_animation(:sleeping), do: "animate-pulse"
  defp state_animation(:worried), do: "animate-[wiggle_0.5s_ease-in-out_infinite]"
  defp state_animation(:sheared), do: "animate-[shiver_0.3s_ease-in-out_infinite]"
  defp state_animation(:golden_fleece), do: "animate-[glow_2s_ease-in-out_infinite]"
  defp state_animation(_), do: nil

  # ── SVG rendering per state ───────────────────────────────────────────────

  defp sheep_svg(:studying, wool_level) do
    wool_color = wool_color(wool_level)

    ~s"""
    <svg viewBox="0 0 120 120" fill="none" xmlns="http://www.w3.org/2000/svg">
      <!-- Body wool -->
      <ellipse cx="60" cy="68" rx="#{32 + wool_level}" ry="#{28 + wool_level}" fill="#{wool_color}" />
      <circle cx="42" cy="52" r="#{8 + div(wool_level, 2)}" fill="#{wool_color}" />
      <circle cx="60" cy="45" r="#{10 + div(wool_level, 2)}" fill="#{wool_color}" />
      <circle cx="78" cy="52" r="#{8 + div(wool_level, 2)}" fill="#{wool_color}" />
      <circle cx="48" cy="82" r="#{6 + div(wool_level, 3)}" fill="#{wool_color}" />
      <circle cx="72" cy="82" r="#{6 + div(wool_level, 3)}" fill="#{wool_color}" />
      <!-- Head -->
      <ellipse cx="60" cy="38" rx="16" ry="14" fill="#2D2D2D" />
      <!-- Ears -->
      <ellipse cx="42" cy="32" rx="6" ry="4" fill="#2D2D2D" transform="rotate(-20 42 32)" />
      <ellipse cx="78" cy="32" rx="6" ry="4" fill="#2D2D2D" transform="rotate(20 78 32)" />
      <ellipse cx="42" cy="32" rx="4" ry="2.5" fill="#FFB5B5" transform="rotate(-20 42 32)" />
      <ellipse cx="78" cy="32" rx="4" ry="2.5" fill="#FFB5B5" transform="rotate(20 78 32)" />
      <!-- Eyes (with glasses) -->
      <circle cx="53" cy="36" r="5" fill="none" stroke="#8B6914" stroke-width="1.5" />
      <circle cx="67" cy="36" r="5" fill="none" stroke="#8B6914" stroke-width="1.5" />
      <line x1="58" y1="36" x2="62" y2="36" stroke="#8B6914" stroke-width="1.5" />
      <circle cx="53" cy="36" r="2" fill="white" />
      <circle cx="53" cy="36" r="1" fill="#2D2D2D" />
      <circle cx="67" cy="36" r="2" fill="white" />
      <circle cx="67" cy="36" r="1" fill="#2D2D2D" />
      <!-- Nose -->
      <ellipse cx="60" cy="42" rx="2" ry="1.5" fill="#FFB5B5" />
      <!-- Legs -->
      <rect x="47" y="90" width="5" height="14" rx="2.5" fill="#2D2D2D" />
      <rect x="68" y="90" width="5" height="14" rx="2.5" fill="#2D2D2D" />
      <!-- Book -->
      <rect x="72" y="58" width="18" height="14" rx="2" fill="#4CD964" />
      <rect x="72" y="58" width="9" height="14" rx="1" fill="#3DBF55" />
      <line x1="76" y1="62" x2="86" y2="62" stroke="white" stroke-width="1" />
      <line x1="76" y1="65" x2="84" y2="65" stroke="white" stroke-width="1" />
      <line x1="76" y1="68" x2="82" y2="68" stroke="white" stroke-width="1" />
    </svg>
    """
  end

  defp sheep_svg(:encouraging, wool_level) do
    wool_color = wool_color(wool_level)

    ~s"""
    <svg viewBox="0 0 120 120" fill="none" xmlns="http://www.w3.org/2000/svg">
      <!-- Body wool -->
      <ellipse cx="60" cy="68" rx="#{32 + wool_level}" ry="#{28 + wool_level}" fill="#{wool_color}" />
      <circle cx="42" cy="52" r="#{8 + div(wool_level, 2)}" fill="#{wool_color}" />
      <circle cx="60" cy="45" r="#{10 + div(wool_level, 2)}" fill="#{wool_color}" />
      <circle cx="78" cy="52" r="#{8 + div(wool_level, 2)}" fill="#{wool_color}" />
      <!-- Head -->
      <ellipse cx="60" cy="38" rx="16" ry="14" fill="#2D2D2D" />
      <!-- Ears -->
      <ellipse cx="42" cy="32" rx="6" ry="4" fill="#2D2D2D" transform="rotate(-20 42 32)" />
      <ellipse cx="78" cy="32" rx="6" ry="4" fill="#2D2D2D" transform="rotate(20 78 32)" />
      <ellipse cx="42" cy="32" rx="4" ry="2.5" fill="#FFB5B5" transform="rotate(-20 42 32)" />
      <ellipse cx="78" cy="32" rx="4" ry="2.5" fill="#FFB5B5" transform="rotate(20 78 32)" />
      <!-- Eyes (happy, arched) -->
      <path d="M50 36 Q53 33 56 36" stroke="#2D2D2D" stroke-width="2" fill="none" stroke-linecap="round" />
      <path d="M64 36 Q67 33 70 36" stroke="#2D2D2D" stroke-width="2" fill="none" stroke-linecap="round" />
      <!-- Smile -->
      <path d="M55 43 Q60 47 65 43" stroke="#FFB5B5" stroke-width="1.5" fill="none" stroke-linecap="round" />
      <!-- Flag -->
      <line x1="84" y1="30" x2="84" y2="62" stroke="#8B6914" stroke-width="2" />
      <polygon points="84,30 100,37 84,44" fill="#4CD964" />
      <!-- Legs -->
      <rect x="47" y="90" width="5" height="14" rx="2.5" fill="#2D2D2D" />
      <rect x="68" y="90" width="5" height="14" rx="2.5" fill="#2D2D2D" />
    </svg>
    """
  end

  defp sheep_svg(:celebrating, wool_level) do
    wool_color = wool_color(wool_level)

    ~s"""
    <svg viewBox="0 0 120 120" fill="none" xmlns="http://www.w3.org/2000/svg">
      <!-- Confetti -->
      <circle cx="25" cy="20" r="3" fill="#FF6B6B" />
      <circle cx="95" cy="15" r="2" fill="#4CD964" />
      <rect x="15" y="35" width="4" height="4" fill="#FFCC00" transform="rotate(30 15 35)" />
      <rect x="100" y="30" width="3" height="3" fill="#007AFF" transform="rotate(45 100 30)" />
      <circle cx="30" cy="10" r="2" fill="#CE82FF" />
      <!-- Body wool (jumping up) -->
      <ellipse cx="60" cy="58" rx="#{32 + wool_level}" ry="#{28 + wool_level}" fill="#{wool_color}" />
      <circle cx="42" cy="42" r="#{8 + div(wool_level, 2)}" fill="#{wool_color}" />
      <circle cx="60" cy="35" r="#{10 + div(wool_level, 2)}" fill="#{wool_color}" />
      <circle cx="78" cy="42" r="#{8 + div(wool_level, 2)}" fill="#{wool_color}" />
      <!-- Head -->
      <ellipse cx="60" cy="28" rx="16" ry="14" fill="#2D2D2D" />
      <!-- Ears -->
      <ellipse cx="42" cy="22" rx="6" ry="4" fill="#2D2D2D" transform="rotate(-20 42 22)" />
      <ellipse cx="78" cy="22" rx="6" ry="4" fill="#2D2D2D" transform="rotate(20 78 22)" />
      <ellipse cx="42" cy="22" rx="4" ry="2.5" fill="#FFB5B5" transform="rotate(-20 42 22)" />
      <ellipse cx="78" cy="22" rx="4" ry="2.5" fill="#FFB5B5" transform="rotate(20 78 22)" />
      <!-- Eyes (stars!) -->
      <text x="49" y="30" font-size="10" fill="#FFCC00">★</text>
      <text x="63" y="30" font-size="10" fill="#FFCC00">★</text>
      <!-- Big smile -->
      <path d="M52 35 Q60 42 68 35" stroke="#FFB5B5" stroke-width="2" fill="none" stroke-linecap="round" />
      <!-- Legs (spread, jumping) -->
      <rect x="42" y="82" width="5" height="12" rx="2.5" fill="#2D2D2D" transform="rotate(-15 42 82)" />
      <rect x="73" y="82" width="5" height="12" rx="2.5" fill="#2D2D2D" transform="rotate(15 73 82)" />
      <!-- Shadow on ground -->
      <ellipse cx="60" cy="108" rx="20" ry="4" fill="#E0E0E0" opacity="0.5" />
    </svg>
    """
  end

  defp sheep_svg(:worried, wool_level) do
    wool_color = wool_color(wool_level)

    ~s"""
    <svg viewBox="0 0 120 120" fill="none" xmlns="http://www.w3.org/2000/svg">
      <!-- Body wool -->
      <ellipse cx="60" cy="68" rx="#{32 + wool_level}" ry="#{28 + wool_level}" fill="#{wool_color}" />
      <circle cx="42" cy="52" r="#{8 + div(wool_level, 2)}" fill="#{wool_color}" />
      <circle cx="60" cy="45" r="#{10 + div(wool_level, 2)}" fill="#{wool_color}" />
      <circle cx="78" cy="52" r="#{8 + div(wool_level, 2)}" fill="#{wool_color}" />
      <!-- Head -->
      <ellipse cx="60" cy="38" rx="16" ry="14" fill="#2D2D2D" />
      <!-- Ears (droopy) -->
      <ellipse cx="42" cy="35" rx="6" ry="4" fill="#2D2D2D" transform="rotate(-35 42 35)" />
      <ellipse cx="78" cy="35" rx="6" ry="4" fill="#2D2D2D" transform="rotate(35 78 35)" />
      <ellipse cx="42" cy="35" rx="4" ry="2.5" fill="#FFB5B5" transform="rotate(-35 42 35)" />
      <ellipse cx="78" cy="35" rx="4" ry="2.5" fill="#FFB5B5" transform="rotate(35 78 35)" />
      <!-- Eyes (worried, wide) -->
      <circle cx="53" cy="35" r="3" fill="white" />
      <circle cx="53" cy="36" r="1.5" fill="#2D2D2D" />
      <circle cx="67" cy="35" r="3" fill="white" />
      <circle cx="67" cy="36" r="1.5" fill="#2D2D2D" />
      <!-- Worried eyebrows -->
      <line x1="49" y1="30" x2="56" y2="32" stroke="#2D2D2D" stroke-width="1.5" stroke-linecap="round" />
      <line x1="71" y1="30" x2="64" y2="32" stroke="#2D2D2D" stroke-width="1.5" stroke-linecap="round" />
      <!-- Wavy mouth -->
      <path d="M54 44 Q57 42 60 44 Q63 46 66 44" stroke="#FFB5B5" stroke-width="1.5" fill="none" stroke-linecap="round" />
      <!-- Sweat drop -->
      <ellipse cx="75" cy="30" rx="2" ry="3" fill="#87CEEB" />
      <!-- Legs -->
      <rect x="47" y="90" width="5" height="14" rx="2.5" fill="#2D2D2D" />
      <rect x="68" y="90" width="5" height="14" rx="2.5" fill="#2D2D2D" />
    </svg>
    """
  end

  defp sheep_svg(:sleeping, _wool_level) do
    ~s"""
    <svg viewBox="0 0 120 120" fill="none" xmlns="http://www.w3.org/2000/svg">
      <!-- Body wool (curled up) -->
      <ellipse cx="60" cy="75" rx="35" ry="22" fill="#F5F0E8" />
      <circle cx="42" cy="62" r="9" fill="#F5F0E8" />
      <circle cx="60" cy="56" r="11" fill="#F5F0E8" />
      <circle cx="78" cy="62" r="9" fill="#F5F0E8" />
      <circle cx="48" cy="88" r="7" fill="#F5F0E8" />
      <circle cx="72" cy="88" r="7" fill="#F5F0E8" />
      <!-- Head (resting) -->
      <ellipse cx="55" cy="52" rx="16" ry="13" fill="#2D2D2D" />
      <!-- Ears (relaxed) -->
      <ellipse cx="40" cy="46" rx="6" ry="3.5" fill="#2D2D2D" transform="rotate(-10 40 46)" />
      <ellipse cx="40" cy="46" rx="4" ry="2" fill="#FFB5B5" transform="rotate(-10 40 46)" />
      <!-- Closed eyes -->
      <path d="M48 51 Q51 49 54 51" stroke="white" stroke-width="1.5" fill="none" stroke-linecap="round" />
      <path d="M58 51 Q61 49 64 51" stroke="white" stroke-width="1.5" fill="none" stroke-linecap="round" />
      <!-- Peaceful smile -->
      <path d="M52 56 Q55 58 58 56" stroke="#FFB5B5" stroke-width="1" fill="none" stroke-linecap="round" />
      <!-- Zzz -->
      <text x="72" y="38" font-size="14" fill="#8E8E93" font-weight="bold" opacity="0.8">Z</text>
      <text x="82" y="28" font-size="10" fill="#8E8E93" font-weight="bold" opacity="0.6">z</text>
      <text x="88" y="20" font-size="8" fill="#8E8E93" font-weight="bold" opacity="0.4">z</text>
    </svg>
    """
  end

  defp sheep_svg(:sheared, _wool_level) do
    ~s"""
    <svg viewBox="0 0 120 120" fill="none" xmlns="http://www.w3.org/2000/svg">
      <!-- Body (no wool, just skin) -->
      <ellipse cx="60" cy="68" rx="28" ry="24" fill="#FFD4B8" />
      <!-- Goosebumps -->
      <circle cx="48" cy="60" r="1" fill="#F0C4A0" />
      <circle cx="55" cy="72" r="1" fill="#F0C4A0" />
      <circle cx="65" cy="65" r="1" fill="#F0C4A0" />
      <circle cx="72" cy="75" r="1" fill="#F0C4A0" />
      <circle cx="52" cy="78" r="1" fill="#F0C4A0" />
      <!-- Tiny tuft on top -->
      <circle cx="60" cy="45" r="5" fill="#F5F0E8" />
      <!-- Head -->
      <ellipse cx="60" cy="38" rx="16" ry="14" fill="#2D2D2D" />
      <!-- Ears (droopy) -->
      <ellipse cx="42" cy="36" rx="6" ry="4" fill="#2D2D2D" transform="rotate(-40 42 36)" />
      <ellipse cx="78" cy="36" rx="6" ry="4" fill="#2D2D2D" transform="rotate(40 78 36)" />
      <ellipse cx="42" cy="36" rx="4" ry="2.5" fill="#FFB5B5" transform="rotate(-40 42 36)" />
      <ellipse cx="78" cy="36" rx="4" ry="2.5" fill="#FFB5B5" transform="rotate(40 78 36)" />
      <!-- Eyes (sad) -->
      <circle cx="53" cy="36" r="2.5" fill="white" />
      <circle cx="53" cy="37" r="1.2" fill="#2D2D2D" />
      <circle cx="67" cy="36" r="2.5" fill="white" />
      <circle cx="67" cy="37" r="1.2" fill="#2D2D2D" />
      <!-- Sad eyebrows -->
      <line x1="49" y1="31" x2="56" y2="33" stroke="#2D2D2D" stroke-width="1.5" stroke-linecap="round" />
      <line x1="71" y1="31" x2="64" y2="33" stroke="#2D2D2D" stroke-width="1.5" stroke-linecap="round" />
      <!-- Frown -->
      <path d="M55 44 Q60 41 65 44" stroke="#FFB5B5" stroke-width="1.5" fill="none" stroke-linecap="round" />
      <!-- Shivering lines -->
      <path d="M30 58 L28 62 L32 60" stroke="#87CEEB" stroke-width="1" opacity="0.6" />
      <path d="M90 58 L92 62 L88 60" stroke="#87CEEB" stroke-width="1" opacity="0.6" />
      <!-- Legs (skinny) -->
      <rect x="48" y="88" width="4" height="14" rx="2" fill="#2D2D2D" />
      <rect x="68" y="88" width="4" height="14" rx="2" fill="#2D2D2D" />
    </svg>
    """
  end

  defp sheep_svg(:fluffy, _wool_level) do
    ~s"""
    <svg viewBox="0 0 120 120" fill="none" xmlns="http://www.w3.org/2000/svg">
      <!-- Extra fluffy body -->
      <ellipse cx="60" cy="68" rx="42" ry="36" fill="#FAFAF5" />
      <circle cx="35" cy="50" r="14" fill="#FAFAF5" />
      <circle cx="60" cy="40" r="16" fill="#FAFAF5" />
      <circle cx="85" cy="50" r="14" fill="#FAFAF5" />
      <circle cx="38" cy="85" r="12" fill="#FAFAF5" />
      <circle cx="82" cy="85" r="12" fill="#FAFAF5" />
      <circle cx="60" cy="90" r="10" fill="#FAFAF5" />
      <!-- Extra puff clouds -->
      <circle cx="30" cy="65" r="8" fill="#F5F0E8" />
      <circle cx="90" cy="65" r="8" fill="#F5F0E8" />
      <circle cx="50" cy="42" r="8" fill="#F5F0E8" />
      <circle cx="70" cy="42" r="8" fill="#F5F0E8" />
      <!-- Head (peeking out) -->
      <ellipse cx="60" cy="33" rx="14" ry="12" fill="#2D2D2D" />
      <!-- Ears -->
      <ellipse cx="44" cy="27" rx="5" ry="3.5" fill="#2D2D2D" transform="rotate(-20 44 27)" />
      <ellipse cx="76" cy="27" rx="5" ry="3.5" fill="#2D2D2D" transform="rotate(20 76 27)" />
      <ellipse cx="44" cy="27" rx="3.5" ry="2" fill="#FFB5B5" transform="rotate(-20 44 27)" />
      <ellipse cx="76" cy="27" rx="3.5" ry="2" fill="#FFB5B5" transform="rotate(20 76 27)" />
      <!-- Happy eyes -->
      <path d="M53 32 Q56 29 59 32" stroke="white" stroke-width="2" fill="none" stroke-linecap="round" />
      <path d="M61 32 Q64 29 67 32" stroke="white" stroke-width="2" fill="none" stroke-linecap="round" />
      <!-- Happy blush -->
      <circle cx="50" cy="35" r="3" fill="#FFB5B5" opacity="0.4" />
      <circle cx="70" cy="35" r="3" fill="#FFB5B5" opacity="0.4" />
      <!-- Smile -->
      <path d="M55 37 Q60 41 65 37" stroke="#FFB5B5" stroke-width="1.5" fill="none" stroke-linecap="round" />
      <!-- Legs (barely visible under wool) -->
      <rect x="48" y="98" width="5" height="8" rx="2.5" fill="#2D2D2D" />
      <rect x="67" y="98" width="5" height="8" rx="2.5" fill="#2D2D2D" />
    </svg>
    """
  end

  defp sheep_svg(:golden_fleece, _wool_level) do
    ~s"""
    <svg viewBox="0 0 120 120" fill="none" xmlns="http://www.w3.org/2000/svg">
      <!-- Glow effect -->
      <ellipse cx="60" cy="65" rx="50" ry="45" fill="#FFCC00" opacity="0.15" />
      <!-- Golden body -->
      <ellipse cx="60" cy="68" rx="38" ry="32" fill="#FFD700" />
      <circle cx="38" cy="50" r="12" fill="#FFD700" />
      <circle cx="60" cy="42" r="14" fill="#FFD700" />
      <circle cx="82" cy="50" r="12" fill="#FFD700" />
      <circle cx="42" cy="85" r="10" fill="#FFD700" />
      <circle cx="78" cy="85" r="10" fill="#FFD700" />
      <!-- Sparkles -->
      <text x="25" y="40" font-size="10" fill="#FFCC00">✦</text>
      <text x="88" y="45" font-size="8" fill="#FFCC00">✦</text>
      <text x="50" y="20" font-size="6" fill="#FFCC00">✦</text>
      <text x="75" y="25" font-size="7" fill="#FFCC00">✦</text>
      <!-- Crown -->
      <polygon points="50,18 53,10 57,16 60,8 63,16 67,10 70,18" fill="#FFCC00" stroke="#DAA520" stroke-width="1" />
      <!-- Head -->
      <ellipse cx="60" cy="35" rx="16" ry="14" fill="#2D2D2D" />
      <!-- Ears -->
      <ellipse cx="42" cy="29" rx="6" ry="4" fill="#2D2D2D" transform="rotate(-20 42 29)" />
      <ellipse cx="78" cy="29" rx="6" ry="4" fill="#2D2D2D" transform="rotate(20 78 29)" />
      <ellipse cx="42" cy="29" rx="4" ry="2.5" fill="#FFB5B5" transform="rotate(-20 42 29)" />
      <ellipse cx="78" cy="29" rx="4" ry="2.5" fill="#FFB5B5" transform="rotate(20 78 29)" />
      <!-- Star eyes -->
      <text x="49" y="37" font-size="9" fill="#FFCC00">★</text>
      <text x="63" y="37" font-size="9" fill="#FFCC00">★</text>
      <!-- Big smile -->
      <path d="M52 42 Q60 48 68 42" stroke="#FFB5B5" stroke-width="2" fill="none" stroke-linecap="round" />
      <!-- Legs -->
      <rect x="47" y="94" width="5" height="12" rx="2.5" fill="#2D2D2D" />
      <rect x="68" y="94" width="5" height="12" rx="2.5" fill="#2D2D2D" />
    </svg>
    """
  end

  defp sheep_svg(:shepherd, wool_level) do
    wool_color = wool_color(wool_level)

    ~s"""
    <svg viewBox="0 0 120 120" fill="none" xmlns="http://www.w3.org/2000/svg">
      <!-- Body wool -->
      <ellipse cx="60" cy="68" rx="#{32 + wool_level}" ry="#{28 + wool_level}" fill="#{wool_color}" />
      <circle cx="42" cy="52" r="#{8 + div(wool_level, 2)}" fill="#{wool_color}" />
      <circle cx="60" cy="45" r="#{10 + div(wool_level, 2)}" fill="#{wool_color}" />
      <circle cx="78" cy="52" r="#{8 + div(wool_level, 2)}" fill="#{wool_color}" />
      <!-- Head -->
      <ellipse cx="60" cy="38" rx="16" ry="14" fill="#2D2D2D" />
      <!-- Ears -->
      <ellipse cx="42" cy="32" rx="6" ry="4" fill="#2D2D2D" transform="rotate(-20 42 32)" />
      <ellipse cx="78" cy="32" rx="6" ry="4" fill="#2D2D2D" transform="rotate(20 78 32)" />
      <ellipse cx="42" cy="32" rx="4" ry="2.5" fill="#FFB5B5" transform="rotate(-20 42 32)" />
      <ellipse cx="78" cy="32" rx="4" ry="2.5" fill="#FFB5B5" transform="rotate(20 78 32)" />
      <!-- Eyes (wise, focused) -->
      <circle cx="53" cy="36" r="2" fill="white" />
      <circle cx="53" cy="36" r="1" fill="#2D2D2D" />
      <circle cx="67" cy="36" r="2" fill="white" />
      <circle cx="67" cy="36" r="1" fill="#2D2D2D" />
      <!-- Determined look -->
      <line x1="49" y1="32" x2="57" y2="33" stroke="#2D2D2D" stroke-width="1.5" stroke-linecap="round" />
      <line x1="71" y1="32" x2="63" y2="33" stroke="#2D2D2D" stroke-width="1.5" stroke-linecap="round" />
      <!-- Smile -->
      <path d="M56 43 Q60 45 64 43" stroke="#FFB5B5" stroke-width="1" fill="none" stroke-linecap="round" />
      <!-- Shepherd's crook -->
      <line x1="88" y1="25" x2="88" y2="100" stroke="#8B6914" stroke-width="3" stroke-linecap="round" />
      <path d="M88 25 Q88 15 80 15 Q72 15 72 22" stroke="#8B6914" stroke-width="3" fill="none" stroke-linecap="round" />
      <!-- Legs -->
      <rect x="47" y="90" width="5" height="14" rx="2.5" fill="#2D2D2D" />
      <rect x="68" y="90" width="5" height="14" rx="2.5" fill="#2D2D2D" />
    </svg>
    """
  end

  defp sheep_svg(:flash_card, wool_level) do
    wool_color = wool_color(wool_level)

    ~s"""
    <svg viewBox="0 0 120 120" fill="none" xmlns="http://www.w3.org/2000/svg">
      <!-- Body wool -->
      <ellipse cx="60" cy="68" rx="#{32 + wool_level}" ry="#{28 + wool_level}" fill="#{wool_color}" />
      <circle cx="42" cy="52" r="#{8 + div(wool_level, 2)}" fill="#{wool_color}" />
      <circle cx="60" cy="45" r="#{10 + div(wool_level, 2)}" fill="#{wool_color}" />
      <circle cx="78" cy="52" r="#{8 + div(wool_level, 2)}" fill="#{wool_color}" />
      <!-- Head -->
      <ellipse cx="60" cy="38" rx="16" ry="14" fill="#2D2D2D" />
      <!-- Ears -->
      <ellipse cx="42" cy="32" rx="6" ry="4" fill="#2D2D2D" transform="rotate(-20 42 32)" />
      <ellipse cx="78" cy="32" rx="6" ry="4" fill="#2D2D2D" transform="rotate(20 78 32)" />
      <ellipse cx="42" cy="32" rx="4" ry="2.5" fill="#FFB5B5" transform="rotate(-20 42 32)" />
      <ellipse cx="78" cy="32" rx="4" ry="2.5" fill="#FFB5B5" transform="rotate(20 78 32)" />
      <!-- Eyes (focused) -->
      <circle cx="53" cy="36" r="2" fill="white" />
      <circle cx="53" cy="36" r="1" fill="#2D2D2D" />
      <circle cx="67" cy="36" r="2" fill="white" />
      <circle cx="67" cy="36" r="1" fill="#2D2D2D" />
      <!-- Smile -->
      <path d="M56 43 Q60 45 64 43" stroke="#FFB5B5" stroke-width="1" fill="none" stroke-linecap="round" />
      <!-- Flash cards (fanned) -->
      <rect x="18" y="55" width="22" height="16" rx="3" fill="#FF6B6B" transform="rotate(-15 18 55)" />
      <rect x="14" y="52" width="22" height="16" rx="3" fill="#4CD964" transform="rotate(-5 14 52)" />
      <rect x="12" y="50" width="22" height="16" rx="3" fill="white" stroke="#E5E5EA" stroke-width="1" />
      <text x="17" y="61" font-size="8" fill="#2D2D2D" font-weight="bold">?</text>
      <!-- Legs -->
      <rect x="47" y="90" width="5" height="14" rx="2.5" fill="#2D2D2D" />
      <rect x="68" y="90" width="5" height="14" rx="2.5" fill="#2D2D2D" />
    </svg>
    """
  end

  # Fallback for any unknown state
  defp sheep_svg(_state, wool_level), do: sheep_svg(:studying, wool_level)

  # ── Wool color based on level ─────────────────────────────────────────────

  defp wool_color(level) when level <= 2, do: "#E8E0D4"
  defp wool_color(level) when level <= 4, do: "#F0E8DC"
  defp wool_color(level) when level <= 6, do: "#F5F0E8"
  defp wool_color(level) when level <= 8, do: "#FAFAF5"
  defp wool_color(_level), do: "#FFFFFF"
end
