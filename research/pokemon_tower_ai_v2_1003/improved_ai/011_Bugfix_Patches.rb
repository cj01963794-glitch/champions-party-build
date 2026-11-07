# Battle-related bug fixes


class Battle::AI::AITrainer
  alias remove_flags_best_traniner set_up_skill_flags
  def set_up_skill_flags
    remove_flags_best_traniner
    if best_skill?
      @skill_flags.delete("ReserveLastPokemon")
    end
  end
end

# AI compute takes a lot of time, so slow animated battler frame stepping only
# while battle speedup is active.
class DeluxeBitmapWrapper
  alias _tower_speedup_aware_update update
  def update
    return false if self.disposed?
    return false if $PokemonSystem.animated_sprites > 0
    return false if @speed <= 0
    timer = System.uptime
    delay = ((@speed / 2.0) * Settings::ANIMATION_FRAME_DELAY).round / 1000.0
    if defined?($GameSpeed) && $GameSpeed && $GameSpeed > 0 &&
       defined?(SPEEDUP_STAGES) && SPEEDUP_STAGES[$GameSpeed]
      delay *= SPEEDUP_STAGES[$GameSpeed] / 1.5
    end
    return if timer - @last_uptime < delay
    (@reversed) ? @frame_idx -= 1 : @frame_idx += 1
    @frame_idx = 0 if @frame_idx >= @total_frames
    @frame_idx = @total_frames - 1 if @frame_idx < 0
    @last_uptime = timer
  end
end

class Battle::Battler
  OGERPON_TERA_MASKS = [
    :TEALMASK,
    :WELLSPRINGMASK,
    :HEARTHFLAMEMASK,
    :CORNERSTONEMASK
  ] unless const_defined?(:OGERPON_TERA_MASKS)

  alias tower_ogerpon_mask_hasTera? hasTera?
  def hasTera?(check_available = true)
    return tower_ogerpon_mask_hasTera?(check_available) if !isSpecies?(:OGERPON) ||
                                                            !OGERPON_TERA_MASKS.include?(@item_id)
    return false if shadowPokemon?
    return false if wild? && @battle.wildBattleMode != :tera
    return false if @battle.raidBattle? && @battle.raidRules[:style] != :Tera
    return false if @pokemon.hasTerastalForm? && @effects[PBEffects::Transform]
    return false if @effects[PBEffects::TransformPokemon]&.hasTerastalForm?
    return false if !getActiveState.nil?
    # Mask Ogerpon should be allowed to Tera even though DBK's generic
    # Dynamax eligibility says it can Dynamax without checking Max Mushroom.
    return false if hasEligibleAction?(:mega, :primal, :zmove, :ultra, :style, :zodiac)
    side  = idxOwnSide
    owner = @battle.pbGetOwnerIndexFromBattlerIndex(@index)
    return false if check_available && @battle.terastallize[side][owner] == -2
    return !tera_type.nil?
  end
end

# Priority recalculation can happen after Mega Evolution changes abilities; clear
# Prankster's per-move marker before rebuilding priority-derived state.
class Battle
  alias tower_prankster_recalc_pbCalculatePriority pbCalculatePriority
  def pbCalculatePriority(fullCalc = false, indexArray = nil)
    if fullCalc
      @battlers.each { |b| b.effects[PBEffects::Prankster] = false if b }
    else
      @priority.each do |entry|
        next if !entry
        next if indexArray && !indexArray.include?(entry[0].index)
        entry[0].effects[PBEffects::Prankster] = false
      end
    end
    tower_prankster_recalc_pbCalculatePriority(fullCalc, indexArray)
  end
end

class Battle::Move
  # drdooms charm bugfix and also drought water move bugfix
  def pbCalcDamageMultipliers(user, target, numTargets, type, baseDmg, multipliers)
    args = [user, target, numTargets, type, baseDmg]
    pbCalcDamageMults_Global(*args, multipliers)
    pbCalcDamageMults_Abilities(*args, multipliers)
    pbCalcDamageMults_Items(*args, multipliers)
    if user.effects[PBEffects::ParentalBond] == 1
      multipliers[:power_multiplier] /= (Settings::MECHANICS_GENERATION >= 7) ? 4 : 2
    end
    pbCalcDamageMults_Other(*args, multipliers)
    pbCalcDamageMults_Field(*args, multipliers)
    pbCalcDamageMults_Badges(*args, multipliers)
    multipliers[:final_damage_multiplier] *= 0.75 if numTargets > 1
    pbCalcDamageMults_Weather(*args, multipliers)
    pbCalcDamageMults_Random(*args, multipliers)
    pbCalcDamageMults_Type(*args, multipliers)
    pbCalcDamageMults_Status(*args, multipliers)
    pbCalcDamageMults_Screens(*args, multipliers)
    if target.effects[PBEffects::Minimize] && tramplesMinimize?
      multipliers[:final_damage_multiplier] *= 2
    end
    if defined?(PBEffects::GlaiveRush) && target.effects[PBEffects::GlaiveRush] > 0
      multipliers[:final_damage_multiplier] *= 2 
    end
    multipliers[:power_multiplier] = pbBaseDamageMultiplier(multipliers[:power_multiplier], user, target)
    multipliers[:final_damage_multiplier] = pbModifyDamage(multipliers[:final_damage_multiplier], user, target)
    # Adds 25% more damage to STAB Bonus.
    has_stab = user.tera? ? (user.pbPreTeraTypes.include?(type) || user.typeTeraBoosted?(type)) : user.pbHasType?(type)
    if type && has_stab && $player.activeCharm?(:STABCHARM) && user.pbOwnedByPlayer?
      multipliers[:final_damage_multiplier] *= 1.25
    end
	# Resistor Charm
    if Effectiveness.super_effective?(target.damageState.typeMod) && $player.activeCharm?(:RESISTORCHARM) && target.pbOwnedByPlayer?
      multipliers[:final_damage_multiplier] *= 0.75
    end
  end

  #-----------------------------------------------------------------------------
  # Aliased to allow Z-Moves to partially hit through Protect.
  #-----------------------------------------------------------------------------
  alias zmove_pbCalcDamageMultipliers pbCalcDamageMultipliers
  def pbCalcDamageMultipliers(user, target, numTargets, type, baseDmg, multipliers)
    zmove_pbCalcDamageMultipliers(user, target, numTargets, type, baseDmg, multipliers)
    multipliers[:final_damage_multiplier] /= 4 if zMove? && target.isProtected?(user, self)
  end

  #-----------------------------------------------------------------------------
  # Aliased to allow Dynamax moves to partially hit through Protect.
  #-----------------------------------------------------------------------------
  alias dynamax_pbCalcDamageMultipliers pbCalcDamageMultipliers
  def pbCalcDamageMultipliers(user, target, numTargets, type, baseDmg, multipliers)
    dynamax_pbCalcDamageMultipliers(user, target, numTargets, type, baseDmg, multipliers)
    multipliers[:final_damage_multiplier] /= 4 if dynamaxMove? && target.isProtected?(user, self)
  end

  alias piercingdrill_pbCalcDamageMultipliers pbCalcDamageMultipliers
  def pbCalcDamageMultipliers(user, target, numTargets, type, baseDmg, multipliers)
    piercingdrill_pbCalcDamageMultipliers(user, target, numTargets, type, baseDmg, multipliers)
    if contactMove? && (user.hasActiveAbility?(:UNSEENFIST) || user.hasActiveAbility?(:PIERCINGDRILL)) &&
       target.isProtected?(user, self)
      PBDebug.log("[PIERCINGDRILL] #{user.pbThis} pierces Protect with #{name}, applying 1/4 damage")
      multipliers[:final_damage_multiplier] /= 4
    end
  end
end

class Battle::Move::DoublePowerIfTargetNotActed
  def pbBaseDamage(baseDmg, user, target)
    choice = @battle.choices[target.index][0]
    if choice == :None || choice == :SwitchOut ||
       ([:UseMove, :Shift].include?(choice) && !target.movedThisRound?)
      baseDmg *= 2
    end
    return baseDmg
  end
end

# Fix: EOR Eject Pack recalls first, then pbEORSwitch picks a replacement.
# This means pbFindBattler can't exclude the recalled mon (HP set to 0 by
# pbAbilitiesOnSwitchOut), so it becomes a valid reserve and can replace itself.
# Override to use the same full inline switch that non-EOR Eject Pack already does.
Battle::ItemEffects::OnStatLoss.add(:EJECTPACK,
  proc { |item, battler, move_user, battle|
    next false if battler.effects[PBEffects::SkyDrop] >= 0 ||
                  battler.inTwoTurnAttack?("TwoTurnAttackInvulnerableInSkyTargetCannotAct")
    next false if battle.pbAllFainted?(battler.idxOpposingSide)
    next false if battler.wild?
    next false if !battle.pbCanSwitchOut?(battler.index)
    next false if !battle.pbCanChooseNonActive?(battler.index)
    battle.pbCommonAnimation("UseItem", battler)
    battle.pbDisplay(_INTL("\\j[{1},은,는] \\j[{2},으로,로] 인해 교체되었다!", battler.pbThis, battler.itemName))
    battler.pbConsumeItem(true, false)
    newPkmn = battle.pbGetReplacementPokemonIndex(battler.index)   # Owner chooses
    next false if newPkmn < 0
    battle.pbRecallAndReplace(battler.index, newPkmn)
    battle.pbClearChoice(battler.index)
    battle.moldBreaker = false if move_user && battler.index == move_user.index
    battle.pbOnBattlerEnteringBattle(battler.index)
    next true
  }
)

# Fix: Sunsteel Strike / Moongeist Beam / Photon Geyser and their G-Max/Z-Move
# subclasses crash when targets[0] is nil (e.g. attacking an already-fainted slot).
class Battle::Move::IgnoreTargetAbility < Battle::Move
  def pbOnStartUse(user, targets)
    target = targets[0]
    return if !target
    @battle.moldBreaker = false if @battle.moldBreaker && target.hasActiveItem?(:ABILITYSHIELD)
  end
end

class Battle::Move::CategoryDependsOnHigherDamageIgnoreTargetAbility < Battle::Move::IgnoreTargetAbility
  def pbOnStartUse(user, targets)
    # Preserve Photon Geyser's category calculation while applying the nil-safe handler above.
    max_stage = Battle::Battler::STAT_STAGE_MAXIMUM
    stage_mul = Battle::Battler::STAT_STAGE_MULTIPLIERS
    stage_div = Battle::Battler::STAT_STAGE_DIVISORS
    atk_stage = user.stages[:ATTACK] + max_stage
    real_atk = (user.attack.to_f * stage_mul[atk_stage] / stage_div[atk_stage]).floor
    spatk_stage = user.stages[:SPECIAL_ATTACK] + max_stage
    real_spatk = (user.spatk.to_f * stage_mul[spatk_stage] / stage_div[spatk_stage]).floor
    @calcCategory = (real_atk > real_spatk) ? 0 : 1
    super
  end
end

class Battle::Move::MultiStatUpMove
  def pbOnStartUse(user, targets)
    @tower_multistat_boost_applied = false
  end

  def pbAdditionalEffect(user, target)
    if damagingMove?
      return if @tower_multistat_boost_applied
      @tower_multistat_boost_applied = true
    end
    showAnim = true
    (@statUp.length / 2).times do |i|
      next if !user.pbCanRaiseStatStage?(@statUp[i * 2], user, self)
      if user.pbRaiseStatStage(@statUp[i * 2], @statUp[(i * 2) + 1], user, showAnim)
        showAnim = false
      end
    end
  end
end

Battle::AI::Handlers::MoveFailureCheck.add("CantSelectConsecutiveTurns",
  proc { |move, user, ai, battle|
    next true if user.effects[PBEffects::SuccessiveMove] && user.effects[PBEffects::SuccessiveMove] == @id 
    next false
  }
)
