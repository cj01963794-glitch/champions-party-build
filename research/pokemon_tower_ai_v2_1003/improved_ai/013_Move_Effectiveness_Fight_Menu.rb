#===============================================================================
# Fight menu effectiveness labels
#===============================================================================
# Shows type effectiveness directly on each move button during player move
# selection, instead of requiring the separate Move Info UI panel.
#===============================================================================

class Battle::Scene::FightMenu < Battle::Scene::MenuBase
  EFFECTIVENESS_BASE_NORMAL     = Color.new(248, 248, 248)
  EFFECTIVENESS_SHADOW_NORMAL   = Color.new(32, 32, 32)
  EFFECTIVENESS_BASE_GOOD       = Color.new(72, 216, 96)
  EFFECTIVENESS_SHADOW_GOOD     = Color.new(16, 96, 48)
  EFFECTIVENESS_BASE_BAD        = Color.new(248, 104, 80)
  EFFECTIVENESS_SHADOW_BAD      = Color.new(120, 48, 40)
  EFFECTIVENESS_BASE_IMMUNE     = Color.new(168, 168, 168)
  EFFECTIVENESS_SHADOW_IMMUNE   = Color.new(56, 56, 56)
  EFFECTIVENESS_BASE_UNKNOWN    = Color.new(248, 224, 96)
  EFFECTIVENESS_SHADOW_UNKNOWN  = Color.new(112, 88, 24)
  EFFECTIVENESS_FONT_SIZE       = 16

  alias tower_lite_refreshButtonNames refreshButtonNames
  def refreshButtonNames
    tower_lite_refreshButtonNames
    tower_lite_draw_move_effectiveness_labels
  end

  def tower_lite_draw_move_effectiveness_labels
    return if !defined?(USE_GRAPHICS) || !USE_GRAPHICS
    return if !@overlay || !@battler
    moves = @battler.moves
    targets = tower_lite_effectiveness_targets
    return if targets.empty?
    text_pos = []
    @buttons.each_with_index do |button, i|
      next if !@visibility["button_#{i}"]
      move = moves[i]
      next if !move || !move.damagingMove?
      label, base, shadow = tower_lite_effectiveness_label(move, targets)
      next if !label
      text_pos.push([label, button.x - self.x + button.src_rect.width - 20,
                     button.y - self.y + 28, :center, base, shadow, :outline])
    end
    old_size = @overlay.bitmap.font.size
    @overlay.bitmap.font.size = EFFECTIVENESS_FONT_SIZE
    pbDrawTextPositions(@overlay.bitmap, text_pos)
    @overlay.bitmap.font.size = old_size
  end

  def tower_lite_effectiveness_targets
    battle = @battler.battle rescue nil
    return [] if !battle
    targets = battle.allOtherSideBattlers(@battler.index) rescue []
    targets = targets.select { |b| b && !b.fainted? }
    targets = targets.reverse if targets.length > 1
    return targets
  end

  def tower_lite_effectiveness_label(move, targets)
    type = move.display_type(@battler)
    labels = []
    values = []
    targets.each do |target|
      if tower_lite_unknown_effectiveness_target?(target)
        labels.push("?")
        next
      end
      value = tower_lite_effectiveness_value(move, type, target)
      labels.push(tower_lite_effectiveness_text(value))
      values.push(value)
    end
    return nil if labels.empty?
    label = labels.uniq.join("/")
    value_for_color = values.max || Effectiveness::NORMAL_EFFECTIVE_MULTIPLIER
    base, shadow = tower_lite_effectiveness_colors(value_for_color, labels.include?("?"))
    return label, base, shadow
  end

  def tower_lite_effectiveness_value(move, type, target)
    return move.pbCalcTypeMod(type, @battler, target)
  rescue
    return Effectiveness.calculate(type, *target.pbTypes(true))
  end

  def tower_lite_unknown_effectiveness_target?(target)
    return true if target.celestial?
    return false if !defined?(Settings::SHOW_TYPE_EFFECTIVENESS_FOR_NEW_SPECIES)
    return false if Settings::SHOW_TYPE_EFFECTIVENESS_FOR_NEW_SPECIES
    poke = target.displayPokemon
    return false if !target.battle.internalBattle
    return false if target.pbOwnedByPlayer?
    return false if $player.pokedex.owned?(poke.species)
    return $player.pokedex.battled_count(poke.species) == 0
  end

  def tower_lite_effectiveness_text(value)
    return "0x" if Effectiveness.ineffective?(value)
    ratio = value.to_f
    return "4x"  if ratio >= 4
    return "2x"  if ratio >= 2
    return "1x"  if ratio >= 1
    return "1/4" if ratio <= 0.25
    return "1/2"
  end

  def tower_lite_effectiveness_colors(value, unknown)
    return EFFECTIVENESS_BASE_UNKNOWN, EFFECTIVENESS_SHADOW_UNKNOWN if unknown
    return EFFECTIVENESS_BASE_IMMUNE, EFFECTIVENESS_SHADOW_IMMUNE if Effectiveness.ineffective?(value)
    return EFFECTIVENESS_BASE_GOOD, EFFECTIVENESS_SHADOW_GOOD if Effectiveness.super_effective?(value)
    return EFFECTIVENESS_BASE_BAD, EFFECTIVENESS_SHADOW_BAD if Effectiveness.not_very_effective?(value)
    return EFFECTIVENESS_BASE_NORMAL, EFFECTIVENESS_SHADOW_NORMAL
  end
end
