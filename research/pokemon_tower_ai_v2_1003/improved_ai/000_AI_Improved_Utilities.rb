#===============================================================================
# [AI_Improved_Utilities.rb] - Shared AI helper methods and small score overrides
#===============================================================================

class Battle::AI
  # Returns the stat multiplier for a given stage (-6 to +6).
  def stat_stage_mult(stage)
    stage = stage.clamp(-6, 6)
    Battle::Battler::STAT_STAGE_MULTIPLIERS[stage + 6].to_f /
      Battle::Battler::STAT_STAGE_DIVISORS[stage + 6]
  end

  # Scale a stat-change score delta by additional effect chance for damaging
  # moves with < 100% effect probability (e.g. Moonblast's 30% SpA drop).
  def scale_by_additional_effect(score, result, label)
    return result unless @move.damagingMove? && @move.move.addlEffect > 0 && @move.move.addlEffect < 100
    delta = result - score
    return result if delta == 0
    chance = @move.move.addlEffect
    chance = [chance * 2, 100].min if @user.has_active_ability?(:SERENEGRACE)
    scaled_delta = (delta * chance / 100.0).round
    PBDebug.log("     [additional effect scaling] #{label}: #{delta} * #{chance}% = #{scaled_delta}")
    score + scaled_delta
  end

  alias_method :orig_get_score_for_target_stat_drop, :get_score_for_target_stat_drop
  def get_score_for_target_stat_drop(score, target, stat_changes, whole_effect = true,
                                     fixed_change = false, ignore_contrary = false)
    result = orig_get_score_for_target_stat_drop(score, target, stat_changes, whole_effect, fixed_change, ignore_contrary)
    scale_by_additional_effect(score, result, "stat drop")
  end

  alias_method :orig_get_score_for_target_stat_raise, :get_score_for_target_stat_raise
  def get_score_for_target_stat_raise(score, target, stat_changes, whole_effect = true,
                                      fixed_change = false, ignore_contrary = false)
    result = orig_get_score_for_target_stat_raise(score, target, stat_changes, whole_effect, fixed_change, ignore_contrary)
    scale_by_additional_effect(score, result, "stat raise")
  end

  def safe_function_code(move)
    return nil if !move || !move.respond_to?(:function_code)
    return move.function_code
  end

  def trick_room_ace_reserve_bonus(user, battle, min_turns = 2)
    trick_room_turns = battle.field.effects[PBEffects::TrickRoom]
    return 0 if trick_room_turns < min_turns

    foe_speeds = []
    battle.allOtherSideBattlers(user.battler).each do |foe|
      foe_speeds << foe.pbSpeed
    end
    return 0 if foe_speeds.empty?

    slowest_foe_speed = foe_speeds.min
    battle.pbParty(user.index).each_with_index do |pkmn, i|
      next if !pkmn || !battle.pbCanSwitchIn?(user.index, i)
      next if pkmn.ev[:ATTACK] <= 100 && pkmn.ev[:SPECIAL_ATTACK] <= 100
      next if pkmn.speed >= slowest_foe_speed
      return 20 * trick_room_turns
    end

    return 0
  end

  def move_is_setup?(move, battler = nil)
    return false if !move
    fc = safe_function_code(move) || ""
    return false if fc.empty?
    return false if fc == "CurseTargetOrLowerUserSpd1RaiseUserAtkDef1" &&
                    battler&.has_type?(:GHOST)

    return true if fc.match?(/RaiseUser(?:Side)?/)
    return true if fc == "UserAddStockpileRaiseDefSpDef1"

    return false unless move.respond_to?(:move) && move.move.respond_to?(:statUp)
    stat_up = move.move.statUp
    return false if !stat_up || stat_up.empty?
    return false if move.damagingMove? && (move.move.addlEffect != 100 && move.move.addlEffect != 0)

    stat_up.each_slice(2).any? do |stat, stages|
      next false if !stat || !stages || stages <= 0
      [:ATTACK, :DEFENSE, :SPECIAL_ATTACK, :SPECIAL_DEFENSE,
       :SPEED, :ACCURACY, :EVASION].include?(stat)
    end
  end

  def battler_has_setup_move?(battler)
    return false if !battler
    battler.check_for_move { |m| move_is_setup?(m, battler) }
  end

  def choice_move(choice)
    return nil if !choice
    choice[4] || @battle.battlers[@user.index]&.moves&.[](choice[0])
  end

  def move_priority_for_choice(choice)
    move = choice_move(choice)
    return 0 if !move
    return move.priority if move.respond_to?(:priority)
    return move.rough_priority(@user) if move.respond_to?(:rough_priority)
    0
  rescue StandardError
    0
  end

  def setup_move_for_foe(foe_ai)
    return nil if !foe_ai
    Array(known_foe_moves(foe_ai)).find do |m|
      next false unless move_is_setup?(m, foe_ai)
      foe_ai.battler.pbCanChooseMove?(m, false, false)
    end
  end

  def foe_has_setup_move?(user)
    any_foe_battler?(user.side) { |b, _i| battler_has_setup_move?(b) }
  end

  # Yields each foe battler and returns true if the block ever returns truthy.
  def any_foe_battler?(side)
    each_foe_battler(side) { |b, i| return true if yield(b, i) }
    false
  end

  # Returns true if any foe has an effective phazing move against the user.
  def foe_has_effective_phazing?(user, phaze_codes = ["SwitchOutTargetStatusMove"])
    sim_move = Battle::AI::AIMove.new(self)
    any_foe_battler?(user.side) do |b, _i|
      known_foe_moves(b).any? do |m|
        next false unless phaze_codes.include?(m.function_code)
        sim_move.set_up(m)
        !pbPredictMoveFailureAgainstTarget(sim_move, b, user)
      end
    end
  end

  # Sums positive stat stages on a battler. Returns integer >= 0.
  def total_positive_boosts(battler)
    total = 0
    GameData::Stat.each_battle { |s| total += battler.stages[s.id] if battler.stages[s.id] > 0 }
    total
  end

  # Override the base generic stat score hooks; custom handlers score these.
  def get_target_stat_raise_score_generic(score, target, stat_changes, desire_mult = 1)
    return score
  end

  def get_target_stat_drop_score_generic(score, target, stat_changes, desire_mult = 1)
    return score
  end
end
