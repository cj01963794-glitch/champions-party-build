#===============================================================================
# 2. GeneralMoveAgainstTargetScore Handlers
#===============================================================================

# overwrite existing :predicted_damage handler with a no-op since it's fully replaced by :one_v_one_move_score
Battle::AI::Handlers::GeneralMoveAgainstTargetScore.add(:predicted_damage,
  proc { |score, move, user, target, ai, battle|
    next score 
  }
)

#===============================================================================
# Unified 1v1 move scoring: damage scaling, OHKO bonus, weak-move penalty,
# and survival check (replaces :predicted_damage, :penalize_useless_moves,
# and :evade_knockout)
#===============================================================================
Battle::AI::Handlers::GeneralMoveAgainstTargetScore.add(:one_v_one_move_score,
  proc { |score, move, user, target, ai, battle|
    next score unless ai.trainer.has_skill_flag?("HPAware")
    next score if user.wild?

    # --- Foe threat data (shared by damaging and status paths) ---
    summary   = ai.matchup_summary
    foe_entry = summary[:foes][target.index]
    next score unless foe_entry

    # Status move survival/fail checks are handled globally in GeneralMoveScore.
    if !move.damagingMove?
      next score
    end

    # --- Damaging moves below ---
    user_dmg = ai.damage_entry_for_move(user, target, move)&.dig(:dmg) || 0

    # A) Base damage scaling: 0 to +20 based on damage relative to effective HP
    base = ([20.0 * user_dmg / target.hp, 20].min).to_i
    score += base
    PBDebug.log_score_change(base, "1v1: base damage (#{user_dmg}/#{target.hp})")

    # --- 1v1 simulation from matchup_summary cache ---
    result = foe_entry[:move_results_by_id]&.dig(move.id) ||
             foe_entry[:move_results]&.dig(move.id)
    next score unless result

    interrupted_by_live_switch = result.terminated_by_switch &&
                                 result.switch_type == :live_switch
    foe_pivoted_out = result.terminated_by_switch &&
                      result.switch_type == :live_switch &&
                      result.switch_battler_index == target.index &&
                      !result.user_fainted
    user_pivoted_out = ai.successful_user_pivot_result?(result, user.index)

    if result.target_can_ohko? && !result.user_got_action && !interrupted_by_live_switch
      score -= 100
      PBDebug.log_score_change(-100, "1v1: foe KOs before user acts")
      next score
    end
    next score if move.id == :RAPIDSPIN

    # setup moves
    stat_up = move.move.respond_to?(:statUp) && move.move.statUp && move.move.addlEffect != 100 ? move.move.statUp : []
    is_effective_statup = false
    stat_up.each_with_index do |stat, idx|
      next if idx.odd?
      if ai.stat_raise_worthwhile?(user, stat, true) || stat == :SPEED
        is_effective_statup = true
      end
    end
    next score if is_effective_statup # let statup handler handle move scoring.

    # Successful pivots are scored by the pivot follow-up handler instead of
    # treating the user as if it stayed in and lost the 1v1.
    next score if user_pivoted_out

    # Both battlers faint — value the trade by how much HP each side spent.
    # Keep the old implicit trade formula, but classify this as a KO trade
    # instead of allowing it to fall through to the generic loss branch.
    if result.double_ko?
      dmg_dealt_pct = 0.0
      if result.target_hp && target.totalhp > 0
        dmg_dealt = target.hp - result.target_hp
        dmg_dealt_pct = dmg_dealt.to_f / target.totalhp
      end
      user_hp_invested_pct = (user.hp - result.user_hp).to_f / [user.totalhp, 1].max
      hp_relief = if user_hp_invested_pct < 0.7
                    ((0.7 - user_hp_invested_pct) / 0.7) ** 1.5 * 20
                  else
                    0
                  end
      trade_penalty = 15 + ((1.0 - dmg_dealt_pct) * 40).round - hp_relief.round
      trade_penalty = trade_penalty.clamp(5, 50)
      score -= trade_penalty
      PBDebug.log_score_change(-trade_penalty,
        "1v1: double KO trade (dealt #{(dmg_dealt_pct * 100).round}% of foe's max HP, invested #{(user_hp_invested_pct * 100).round}% of user's max HP)")
      next score
    end

    # B) User loses the 1v1 — penalty scaled by trade value
    unless result.user_wins? || foe_pivoted_out
      dmg_dealt_pct = 0.0
      if result.target_hp && target.totalhp > 0
        dmg_dealt = target.hp - result.target_hp
        dmg_dealt_pct = dmg_dealt.to_f / target.totalhp
      end
      user_hp_pct = (user.hp - result.user_hp).to_f / [user.totalhp, 1].max

      # Base penalty + scale by damage not dealt + reduce when user HP is low
      # HP relief: zero above 70%, ramps steeply below
      hp_relief = user_hp_pct < 0.7 ? ((0.7 - user_hp_pct) / 0.7) ** 1.5 * 20 : 0
      loss_penalty = 15 + ((1.0 - dmg_dealt_pct) * 40).round - hp_relief.round
      loss_penalty = loss_penalty.clamp(5, 50)
      score -= loss_penalty
      PBDebug.log_score_change(-loss_penalty,
        "1v1: user loses (dealt #{(dmg_dealt_pct * 100).round}% to foe, user loses #{(user_hp_pct * 100).round}% HP)")
      next score
    end

    next score if foe_pivoted_out

    u_turns = result.target_ko_turn || 999

    # D) Positive sim bonus
    if result.user_can_ohko? 
      bonus = result.target_got_action ? 20 : 30
      score += bonus
      PBDebug.log_score_change(bonus, "1v1: can OHKO target#{result.target_got_action ? '' : ' (before target acts)'}")
    else
      bonus = (20.0 / u_turns).to_i.clamp(5, 20)
      score += bonus
      PBDebug.log_score_change(bonus, "1v1: user wins in #{u_turns} turns")
    end

    next score
  }
)

#===============================================================================
# Successful pivot follow-up scoring.
#===============================================================================
Battle::AI::Handlers::GeneralMoveScore.add(:pivot_replacement_followup,
  proc { |score, move, user, ai, battle|
    next score unless ai.trainer.has_skill_flag?("HPAware")
    next score if user.wild?
    next score unless battle.pbCanChooseNonActive?(user.battler.index)
    next score unless Battle::AI::PIVOT_FUNCTION_CODES.include?(ai.safe_function_code(move))

    target_data = move.pbTarget(user)
    foes = if target_data.num_targets == 1 && ai.target&.opposes?(user)
      [ai.target]
    else
      battle.allOtherSideBattlers(user.index).map { |b| ai.battlers[b.index] }
    end
    next score if foes.empty?

    pivot_results = foes.to_h do |foe|
      foe_entry = ai.matchup_summary[:foes][foe.index]
      result = if move.damagingMove?
        foe_entry&.dig(:move_results_by_id, move.id) || foe_entry&.dig(:move_results, move.id)
      else
        ai.current_status_move_sim_result(foe, move)
      end
      if !result
        foe_action = ai.simulation_action_for_move_data(ai.best_foe_move_against_current(foe, user))
        result = ai.simulate_battle(
          user.index, foe.index, [move.id], foe_action ? [foe_action] : [],
          max_turns: 1, lock_user_first_action: true
        )
      end
      [foe, result]
    end
    next score unless pivot_results.values.all? do |result|
      ai.successful_user_pivot_result?(result, user.index)
    end

    replacement_score = Battle::AI::Handlers.score_pivot_replacement(
      user.index, pivot_results, move, battle, ai
    )
    next score unless replacement_score

    bonus = replacement_score - 100
    score += bonus
    PBDebug.log_score_change(bonus,
      "Pivot follow-up: best damage-only replacement score #{replacement_score}")
    next score
  }
)

#===============================================================================
# Reward meaningful damage into a boosted foe.
#===============================================================================
Battle::AI::Handlers::GeneralMoveAgainstTargetScore.add(:meaningful_damage_to_boosted_foe,
  proc { |score, move, user, target, ai, battle|
    next score unless ai.trainer.has_skill_flag?("HPAware")
    next score if user.wild?
    next score unless move.damagingMove?
    next score unless ai.total_positive_boosts(target) > 0

    move_dmg = ai.damage_entry_for_move(user, target, move)&.dig(:dmg) || 0
    best_dmg = ai.best_damage_move(user, target)&.dig(:dmg) || 0
    next score if move_dmg * 5 < best_dmg * 4

    summary   = ai.matchup_summary
    foe_entry = summary[:foes][target.index]
    next score unless foe_entry

    result = foe_entry[:move_results_by_id]&.dig(move.id) ||
             foe_entry[:move_results]&.dig(move.id)
    next score unless result
    next score if result.terminated_by_switch &&
                  result.switch_type == :live_switch &&
                  result.switch_battler_index == target.index &&
                  !result.user_fainted

    first_turn = result.turn_log&.first
    next score unless first_turn

    second_turn = result.turn_log[1] || first_turn
    start_hp = first_turn[:target_hp_before].to_i
    after_hp = second_turn[:target_hp_after].to_i
    next score if start_hp <= 0 || target.totalhp <= 0

    damage_dealt = [start_hp - after_hp, 0].max
    current_hp_pct = damage_dealt.to_f / start_hp
    total_hp_pct = damage_dealt.to_f / target.totalhp
    next score if current_hp_pct < 0.60
    next score if total_hp_pct < 0.35

    rounds = [result.turn_log.length, 2].min
    bonus = 10 + ((current_hp_pct - 0.60) * 50).round
    score += bonus
    PBDebug.log_score_change(bonus,
      "Boosted foe trade: dealt #{(current_hp_pct * 100).round}% current HP " \
      "(#{(total_hp_pct * 100).round}% total HP) in first #{rounds} round(s).")

    next score
  }
)

#===============================================================================
# 6. Active pivot move boost (U-turn, Volt Switch, etc.)
#===============================================================================
Battle::AI::Handlers::GeneralMoveAgainstTargetScore.add(:slow_pivot_boost,
  proc { |score, move, user, target, ai, battle|
    next score if !ai.trainer.high_skill?
    next score if !battle.pbCanChooseNonActive?(user.battler.index)

    is_pivot = Battle::AI::PIVOT_FUNCTION_CODES.include?(ai.safe_function_code(move))
    next score unless is_pivot

    # Prefer if target is slower than a foe
    if !user.faster_than?(target)
      score += 5
      PBDebug.log_score_change(5, "6. Slow Pivot preference.")
    end

    next score
  }
)

#===============================================================================
# [NEW] reset enemy boosts
#===============================================================================
Battle::AI::Handlers::GeneralMoveAgainstTargetScore.add(:preemptive_phaze,
  proc { |score, move, user, target, ai, battle|
    next score unless ai.trainer.high_skill?
    phaze_codes = [
      "SwitchOutTargetStatusMove",
      "SwitchOutTargetDamagingMove"
    ]
    next score unless phaze_codes.include?(ai.safe_function_code(move))
    next score if ai.total_positive_boosts(target) >= 2

    score -= 20

    # Boost if target has set up
    if ai.foe_has_setup_move?(user)
      score += 30
      PBDebug.log_score_change(30, "Phaze to preemptively stop target's setup.")
    elsif !move.damagingMove?
      score -= 30
      PBDebug.log_score_change(-30, "phaze wastes one turn")
    end

    next score
  }
)

#===============================================================================
# [NEW] Knock Off — bonus for removing target's item
#===============================================================================
Battle::AI::Handlers::GeneralMoveAgainstTargetScore.add(:boost_knock_off,
  proc { |score, move, user, target, ai, battle|
    next score unless ai.safe_function_code(move) == "RemoveTargetItem"
    next score unless target.item && target.item_active?
    next score if target.battler.unlosableItem?(target.item)
    next score if target.effects[PBEffects::Substitute] > 0
    next score if target.has_active_ability?(:STICKYHOLD)

    # Base bonus for item removal
    score += 5
    PBDebug.log_score_change(5, "Knock Off: removing target's item.")

    # Extra bonus for high-value items
    high_value_items = [
      :LEFTOVERS, :EVIOLITE, :LIFEORB, :ASSAULTVEST, :ROCKYHELMET,
    ]
    if target.has_active_item?(high_value_items)
      score += 10
      PBDebug.log_score_change(10, "Knock Off: target has high-value item.")
    end

    next score
  }
)

#===============================================================================
# override ability and item triggers because its already done in simulations(and is not fun for game player)
#===============================================================================
Battle::AI::Handlers::GeneralMoveAgainstTargetScore.add(:trigger_target_ability_or_item_upon_hit,
  proc { |score, move, user, target, ai, battle|
    next score
  }
)

Battle::AI::Handlers::GeneralMoveAgainstTargetScore.add(:fixed_damage,
  proc { |score, move, user, target, ai, battle|
    next score unless ai.safe_function_code(move) == "FixedDamageHalfTargetHP"
    
    target_hp_ratio = target.hp.to_f / [target.totalhp, 1].max
    if target_hp_ratio > 0.8
      score += 20
      PBDebug.log_score_change(20, "Fixed damage bonus: target above 80% HP.")
    end
    next score
  }
)
