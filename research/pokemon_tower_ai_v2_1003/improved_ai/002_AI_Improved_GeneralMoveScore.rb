#===============================================================================
# 0. Override: Choice Item scoring — exempt Trick/Switcheroo entirely
#===============================================================================
Battle::AI::Handlers::GeneralMoveScore.add(:good_move_for_choice_item,
  proc { |score, move, user, ai, battle|
    next score if move.move.powerMove?
    next score if !ai.trainer.medium_skill?
    next score if !user.has_active_item?([:CHOICEBAND, :CHOICESPECS, :CHOICESCARF]) &&
                  !user.has_active_ability?(:GORILLATACTICS)
    # Trick/Switcheroo removes the Choice item — no penalty
    next score if move.function_code == "UserTargetSwapItems"
    old_score = score
    if move.statusMove?
      score -= 25
      PBDebug.log_score_change(score - old_score, "don't want to be Choiced into a status move")
      next score
    end
    move_type = move.rough_type
    GameData::Type.each do |type_data|
      score -= 8 if type_data.immunities.include?(move_type)
    end
    if move.accuracy > 0
      score -= (0.2 * (100 - move.accuracy)).to_i
    end
    PBDebug.log_score_change(score - old_score, "move is less suitable to be Choiced into")
    next score
  }
)

COUNTER_MOVE_FUNCTION_CODES = [
  "CounterPhysicalDamage",
  "CounterSpecialDamage",
  "CounterDamagePlusHalf"
].freeze

Battle::AI::Handlers::GeneralMoveScore.add(:counter_move_sim_failure,
  proc { |score, move, user, ai, battle|
    next score unless COUNTER_MOVE_FUNCTION_CODES.include?(ai.safe_function_code(move))
    next score if user.wild?

    summary = ai.matchup_summary
    failed_result = false
    summary[:foes].each_value do |foe_entry|
      result = foe_entry[:move_results_by_id]&.dig(move.id) ||
               foe_entry[:move_results]&.dig(move.id)
      next unless result
      next if result.user_succeeded

      failed_result = true
      break
    end

    if failed_result
      PBDebug.log_score_change(Battle::AI::MOVE_FAIL_SCORE - score,
        "#{move.name} simulation failed in a matchup")
      next Battle::AI::MOVE_FAIL_SCORE
    end

    next score
  }
)

Battle::AI::Handlers::GeneralMoveScore.add(:smart_setup_move_final,
  proc { |score, move, user, ai, battle|
    next score unless ai.trainer.high_skill?
    next score if user.wild?
    original_score = score

    real_move = move.move
    fc = ai.safe_function_code(move) || ""
    # Ghost Curse sacrifices HP to curse — not a setup move
    next score if fc == "CurseTargetOrLowerUserSpd1RaiseUserAtkDef1" && user.has_type?(:GHOST)

    stat_up = (real_move.respond_to?(:statUp) && real_move.statUp) ? real_move.statUp : []
    is_effective_statup = false
    stat_up.each_with_index do |stat, idx|
      next if idx.odd?
      if ai.stat_raise_worthwhile?(user, stat, true) || stat == :SPEED
        is_effective_statup = true
      end
    end

    next score unless is_effective_statup

    is_status = move.statusMove?
    # Skip damaging moves whose stat boost is a non-guaranteed secondary effect
    if move.damagingMove? && (real_move.addlEffect != 100 && real_move.addlEffect != 0)
      PBDebug.log_ai("[smart_setup] Skipped #{move.name}: damaging boost isn't guaranteed. addlEffect=#{real_move.addlEffect}")
      next score
    end

    battler = user.battler
    next score unless battler

    speed_stage_gain = 0
    boosted_stats = []
    (stat_up.length / 2).times do |i|
      stat_id = stat_up[i * 2]
      stages  = stat_up[i * 2 + 1]
      boosted_stats << stat_id
      speed_stage_gain += stages if stat_id == :SPEED
    end
    if speed_stage_gain > 0 && battler.stages[:SPEED] >= 2
      speed_penalty = (boosted_stats.uniq == [:SPEED]) ? 40 : 0
      score -= speed_penalty
      PBDebug.log_score_change(-speed_penalty,
        "Setup speed penalty: Speed stage already #{battler.stages[:SPEED]}.")
    elsif speed_stage_gain > 0
      foe_is_faster = false
      ai.each_foe_battler(user.side) do |foe, _i|
        if foe.rough_stat(:SPEED) > user.rough_stat(:SPEED)
          foe_is_faster = true
          break
        end
      end
      speed_bonus = foe_is_faster ? 10 : 5
      score += speed_bonus
      PBDebug.log_score_change(speed_bonus,
        "Setup speed bonus: #{foe_is_faster ? 'foe is faster' : 'user is at least as fast'}.")
    end

    # -----------------------------------------------------------------------
    # Phazing check (status setup moves only): skip if foe has a phazing
    # move that won't fail against the AI's battler.
    # -----------------------------------------------------------------------
    if is_status && ai.foe_has_effective_phazing?(user, ["SwitchOutTargetStatusMove", "SwitchOutTargetDamagingMove"])
      PBDebug.log_ai("[smart_setup] Skipped: foe has effective phazing move.")
      next Battle::AI::MOVE_USELESS_SCORE
    end

    # -----------------------------------------------------------------------
    # Per-foe 1v1 comparison: current vs boosted (using actual simulation)
    # -----------------------------------------------------------------------
    summary = ai.matchup_summary
    total_bonus = 0
    setup_is_status_zmove = is_status && real_move.respond_to?(:status_zmove) && real_move.status_zmove
    setup_move_index = if setup_is_status_zmove
      battler.moves.index { |candidate| candidate&.id == move.id }
    end
    setup_move_action = if setup_is_status_zmove
      { move_id: move.id, move_index: setup_move_index, status_zmove: true }
    else
      move.id
    end
    baton_pass_move = battler.moves.find do |candidate|
      candidate && candidate.pp > 0 && ai.safe_function_code(candidate) == "SwitchOutUserPassOnEffects"
    end
    baton_pass_move = nil unless battle.pbCanChooseNonActive?(user.index)

    ai.each_foe_battler(user.side) do |b, _i|
      foe_entry = summary[:foes][b.index]
      next unless foe_entry

      # Unaware ignores all stat stage changes — setup is wasted
      if b.has_active_ability?(:UNAWARE)
        foe_bonus = is_status ? -100 : 0
        PBDebug.log_ai("[smart_setup] vs #{b.name}: foe has Unaware → #{foe_bonus}")
        total_bonus += foe_bonus
        next
      end

      foe_best_move = foe_entry[:best_move]
      next unless foe_best_move

      foe_actions = foe_entry[:damage_actions] || []
      next if foe_actions.empty?

      if baton_pass_move
        boosted_result = ai.simulate_battle(
          user.index, b.index,
          [setup_move_action, baton_pass_move.id],
          foe_actions,
          max_turns: 2,
          lock_user_actions: true
        )
        completed_sequence = ai.successful_setup_baton_pass_result?(boosted_result, user.index)
        foe_bonus = completed_sequence ? 20 : -60
        PBDebug.log_ai(
          "[smart_setup] vs #{b.name}: setup -> Baton Pass " \
          "#{completed_sequence ? 'succeeded' : 'failed'} => #{foe_bonus}"
        )
        total_bonus += foe_bonus
        next
      end

      # A status Z-Move consumes the user's Z-Move before the damaging follow-up.
      user_best = ai.best_damage_move(user, b, !setup_is_status_zmove)
      next unless user_best

      user_best_action = ai.simulation_action_for_move_data(user_best)
      next unless user_best_action

      # Current: user attacks with best move, foe attacks with best move
      current_result = foe_entry[:sim_result]
      next unless current_result

      # Boosted: user uses setup move first, then best attack; foe keeps attacking
      boosted_result = ai.simulate_battle(
        user.index, b.index,
        [setup_move_action, user_best_action],
        foe_actions,
        max_turns: 5,
        lock_user_first_action: true
      )

      # --- Score comparison ---
      cur_wins = current_result.user_wins?
      bst_wins = boosted_result.user_wins?
      foe_bonus = 0

      if !cur_wins && bst_wins
        # Boost flips losing → winning
        foe_bonus = 50
      elsif cur_wins && !bst_wins
        # Boost makes winning → losing
        foe_bonus = -60
      elsif cur_wins && bst_wins
        # Both win — compare turns to KO and remaining HP
        cur_turns = current_result.target_ko_turn || 999
        bst_turns = boosted_result.target_ko_turn || 999
        # Boosted takes longer due to setup turn, but should deal more damage per hit
        # Score based on HP remaining after winning
        cur_hp_pct = current_result.user_hp.to_f / [user.totalhp, 1].max
        bst_hp_pct = boosted_result.user_hp.to_f / [user.totalhp, 1].max
        hp_saved = bst_hp_pct - cur_hp_pct
        # Base value: you win AND end up boosted for future matchups
        base = [cur_turns * 3, 15].min + 20
        if hp_saved > -0.25
          foe_bonus = base + ((hp_saved + 0.25) * 40).round.clamp(0, 10)
        elsif hp_saved >= -0.5
          foe_bonus = base
        else
          foe_bonus = [base + (hp_saved * 30).round, 0].max
        end
      else
        foe_bonus = -60
      end

      cur_turns = current_result.target_ko_turn || 999
      bst_turns = boosted_result.target_ko_turn || 999
      PBDebug.log_ai("[smart_setup] vs #{b.name}: cur=#{cur_wins ? 'W' : 'L'}(#{cur_turns}T) " \
                     "bst=#{bst_wins ? 'W' : 'L'}(#{bst_turns}T) hpsaved = #{hp_saved}→ #{foe_bonus}")
      total_bonus += foe_bonus
    end

    if move.id == :RAPIDSPIN
      side = user.pbOwnSide
      has_clearable_hazard = side.effects[PBEffects::StealthRock] ||
                             side.effects[PBEffects::Spikes] > 0 ||
                             side.effects[PBEffects::ToxicSpikes] > 0 ||
                             side.effects[PBEffects::StickyWeb] ||
                             (defined?(PBEffects::Steelsurge) && side.effects[PBEffects::Steelsurge])
      total_bonus = [total_bonus, original_score - score].max if has_clearable_hazard
    end
    score += total_bonus
    PBDebug.log_score_change(total_bonus, "Setup simulation: 1v1 comparison.")

    next score
  }
)

#===============================================================================
# 8. Boost accuracy setup for very inaccurate moves
#===============================================================================
Battle::AI::Handlers::GeneralMoveScore.add(:boost_accuracy_setup_for_low_accuracy_moves,
  proc { |score, move, user, ai, battle|
    next score unless ai.trainer.high_skill?
    next score if user.wild?

    stat_up = (move.move.respond_to?(:statUp) && move.move.statUp) ? move.move.statUp : []
    accuracy_gain = 0
    (stat_up.length / 2).times do |i|
      accuracy_gain += stat_up[i * 2 + 1].to_i if stat_up[i * 2] == :ACCURACY
    end
    next score if accuracy_gain <= 0
    next score unless user.battler&.pbCanRaiseStatStage?(:ACCURACY, user.battler, move.move)

    stage = user.stages[:ACCURACY].clamp(-Battle::Battler::STAT_STAGE_MAXIMUM,
                                         Battle::Battler::STAT_STAGE_MAXIMUM)
    stage_index = stage + Battle::Battler::STAT_STAGE_MAXIMUM
    stage_mul = Battle::Battler::ACC_EVA_STAGE_MULTIPLIERS[stage_index]
    stage_div = Battle::Battler::ACC_EVA_STAGE_DIVISORS[stage_index]

    low_accuracy_move = nil
    low_accuracy_value = 100
    user.battler.moves.each do |known_move|
      next if !known_move || known_move.accuracy == 0 || known_move.is_a?(Battle::Move::OHKO)

      effective_accuracy = (known_move.accuracy * stage_mul.to_f / stage_div).floor
      next if effective_accuracy > 60
      next if effective_accuracy >= low_accuracy_value

      low_accuracy_move = known_move
      low_accuracy_value = effective_accuracy
    end
    next score unless low_accuracy_move

    score += 30
    PBDebug.log_score_change(30,
      "#{move.name}: improves #{low_accuracy_move.name}'s low accuracy (#{low_accuracy_value}%).")
    next score
  }
)

#===============================================================================
# 9. Prevent redundant hazard/screen setup and spike stacking penalty
#===============================================================================
Battle::AI::Handlers::GeneralMoveScore.add(:prevent_redundant_effects,
  proc { |score, move, user, ai, battle|
    penalty = 0
    case ai.safe_function_code(move)
    when "AddStealthRocksToFoeSide"
      penalty = -200 if user.pbOpposingSide.effects[PBEffects::StealthRock]
    when "AddSpikesToFoeSide"
      existing = user.pbOpposingSide.effects[PBEffects::Spikes]
      if existing >= 3
        penalty = -200
      elsif existing >= 1
        # Stacking penalty: -30 for 2nd layer, -60 for 3rd layer attempt
        penalty = -(20 + (existing - 1) * 20)
      end
    when "AddToxicSpikesToFoeSide"
      existing = user.pbOpposingSide.effects[PBEffects::ToxicSpikes]
      if existing >= 2
        penalty = -200
      elsif existing >= 1
        penalty = - 30  # 2nd layer of Toxic Spikes is significantly less useful
      end
    when "AddStickyWebToFoeSide"
      penalty = -200 if user.pbOpposingSide.effects[PBEffects::StickyWeb]
    when "UserSideDamageReduction" # Reflect, Light Screen, Aurora Veil
      is_reflect     = (move.id == :REFLECT)
      is_lightscreen = (move.id == :LIGHTSCREEN)
      is_aurora      = (move.id == :AURORAVEIL)

      own_side = user.pbOwnSide
      penalty = -200 if is_reflect     && own_side.effects[PBEffects::Reflect] > 0
      penalty = -200 if is_lightscreen && own_side.effects[PBEffects::LightScreen] > 0
      penalty = -200 if is_aurora      && own_side.effects[PBEffects::AuroraVeil] > 0
    end

    if penalty != 0
      score += penalty
      PBDebug.log_score_change(penalty, "9. Hazard stack penalty / redundant setup prevention.")
    end
    next score
  }
)

#===============================================================================
# 10. Penalize hazard setup when foe can boost
# A boosted foe is an immediate threat — spending a turn on hazards wastes tempo.
#===============================================================================
HAZARD_FUNCTION_CODES = [
  "AddStealthRocksToFoeSide", "AddSpikesToFoeSide",
  "AddToxicSpikesToFoeSide", "AddStickyWebToFoeSide"
].freeze

Battle::AI::Handlers::GeneralMoveScore.add(:penalize_hazards_vs_boosted_foe,
  proc { |score, move, user, ai, battle|
    next score unless HAZARD_FUNCTION_CODES.include?(ai.safe_function_code(move))

    if ai.foe_has_setup_move?(user)
      score -= 80
      PBDebug.log_score_change(-80, "Hazard vs foe with setup move(s).")
    end
    next score
  }
)

Battle::AI::Handlers::GeneralMoveScore.add(:penalize_hazards_vs_hazard_clearer,
  proc { |score, move, user, ai, battle|
    next score unless HAZARD_FUNCTION_CODES.include?(ai.safe_function_code(move))

    clearer = nil
    clear_move = nil
    ai.each_foe_battler(user.side) do |b, _i|
      clear_move = ai.known_foe_moves(b).find do |m|
        next false if m.pp == 0 && m.total_pp > 0
        Battle::AI::HAZARD_CLEAR_FUNCTION_CODES.include?(ai.safe_function_code(m))
      end
      if clear_move
        clearer = b
        break
      end
    end

    if clearer
      score -= 30
      PBDebug.log_score_change(
        -30,
        "Hazard discouraged: #{clearer.name} knows #{clear_move.name}."
      )
    end
    next score
  }
)

#===============================================================================
# 15. General status move base score boost
#===============================================================================
Battle::AI::Handlers::GeneralMoveScore.add(:boost_general_status_moves,
  proc { |score, move, user, ai, battle|
    next score if !ai.trainer.high_skill?

    if move.statusMove? &&
       !ai.safe_function_code(move)&.start_with?("ProtectUserEvenFromDynamaxMoves")
      score += 5
      PBDebug.log_score_change(5, "5. General Status Move Boost.")
    end
    next score
  }
)

#===============================================================================
# 16. Penalize pure stat-drop status moves
#===============================================================================
Battle::AI::Handlers::GeneralMoveScore.add(:penalize_status_stat_drops,
  proc { |score, move, user, ai, battle|
    next score unless move.statusMove?
    stat_down = move.move.respond_to?(:statDown) ? move.move.statDown : nil
    next score if !stat_down || stat_down.empty?
    fc = ai.safe_function_code(move) || ""
    next score if fc == "LowerTargetEvasion1RemoveSideEffects"
    if fc == "CurseTargetOrLowerUserSpd1RaiseUserAtkDef1" &&
       (user.has_type?(:GHOST) ||
        (move.rough_type == :GHOST && user.has_active_ability?([:LIBERO, :PROTEAN])))
      next score
    end
    target_data = move.pbTarget(user.battler)
    next score unless target_data&.targets_foe

    score -= 30
    PBDebug.log_score_change(-30, "Status stat-drop move penalty.")
    next score
  }
)


#===============================================================================
# 17. Preserve Speed on fully invested users
#===============================================================================
Battle::AI::Handlers::GeneralMoveScore.add(:max_speed_investment_self_speed_drop,
  proc { |score, move, user, ai, battle|
    pokemon = user.pokemon
    next score if !pokemon || pokemon.ev[:SPEED] < 150
    next score if user.has_active_ability?(:CONTRARY)

    function_code = ai.safe_function_code(move) || ""
    next score if !function_code.include?("LowerUser")
    if function_code == "CurseTargetOrLowerUserSpd1RaiseUserAtkDef1" &&
       (user.has_type?(:GHOST) ||
        (move.rough_type == :GHOST && user.has_active_ability?([:LIBERO, :PROTEAN])))
      next score
    end

    stat_down = move.move.respond_to?(:statDown) ? move.move.statDown : nil
    next score if !stat_down || stat_down.empty?

    speed_drop = 0
    stat_down.each_slice(2) do |stat, stages|
      speed_drop += stages.to_i if stat == :SPEED
    end
    next score if speed_drop <= 0

    speed_drop *= 2 if user.has_active_ability?(:SIMPLE)
    speed_drop = [speed_drop, user.stages[:SPEED] + Battle::Battler::STAT_STAGE_MAXIMUM].min
    next score if speed_drop <= 0

    penalty = 10 * speed_drop
    score -= penalty
    PBDebug.log_score_change(-penalty,
      "Max Speed investment: preserve Speed instead of lowering it by #{speed_drop} stage(s).")
    next score
  }
)

#===============================================================================
# [NEW] Tactical Substitute usage AI
#===============================================================================
Battle::AI::Handlers::GeneralMoveScore.add(:tactical_substitute,
  proc { |score, move, user, ai, battle|
    # Skip if not Substitute
    next score unless move.id == :SUBSTITUTE
    next score if user.wild?

    battler = user.battler
    next score unless battler

    # Don't use if Substitute is already active
    next Battle::AI::MOVE_FAIL_SCORE if battler.effects[PBEffects::Substitute] > 0

    # -------------------------------------------------------------------------
    # Phazing check: Substitute doesn't block phazing moves
    # -------------------------------------------------------------------------
    if ai.foe_has_effective_phazing?(user)
      PBDebug.log_ai("[tactical_substitute] Skipped: foe has effective phazing move.")
      next Battle::AI::MOVE_FAIL_SCORE
    end

    # -------------------------------------------------------------------------
    # B. Foe threat analysis — reject if any foe can break the Substitute in one hit
    # -------------------------------------------------------------------------
    sub_break_threshold = battler.totalhp / 4.0
    threatened = false
    ai.each_foe_battler(user.side) do |b, _i|
      best_dmg = ai.best_damage_move(b, user)&.dig(:dmg) || 0
      PBDebug.log_ai(
        "[tactical_substitute] Threat check vs #{b.name}: best_dmg=#{best_dmg}, " \
        "sub_threshold=#{sub_break_threshold}"
      )
      if best_dmg >= sub_break_threshold
        threatened = true
        PBDebug.log_ai("[tactical_substitute] Rejected: #{b.name} can break Substitute in one hit.")
        break
      end
    end

    # Substitute is counterproductive when foe can break it in one hit
    next Battle::AI::MOVE_USELESS_SCORE if threatened

    # -------------------------------------------------------------------------
    # C. Evaluate plans behind Substitute
    # -------------------------------------------------------------------------

    future_value = 0

    # 1) Substitute value increases if user has setup moves
    if ai.battler_has_setup_move?(user)
      future_value += 20
    end

    # 2) Value increases if foe has status moves (Substitute blocks them)
    foe_has_status = false
    ai.each_foe_battler(user.side) do |b, _i|
      ai.known_foe_moves(b).each do |m|
        foe_has_status = true if m.statusMove?
      end
      break if foe_has_status
    end
    future_value += 15 if foe_has_status

    score += future_value
    PBDebug.log_score_change(
      future_value,
      "Tactical Substitute (HP=#{(battler.hp * 100 / battler.totalhp)}%)."
    )

    next score
  }
)


#===============================================================================
# [NEW] Setup boost: when all foes are unable to act
#===============================================================================
Battle::AI::Handlers::GeneralMoveScore.add(:boost_setup_when_foe_helpless,
  proc { |score, move, user, ai, battle|
    next score unless ai.trainer.high_skill?
    next score unless move.statusMove?
    next score unless ai.move_is_setup?(move, user)

    any_foe_can_act = false
    ai.each_foe_battler(user.side) do |b, i|
      if b.can_attack?
        any_foe_can_act = true
        break
      end
    end

    unless any_foe_can_act
      score += 10
      PBDebug.log_score_change(10, "Setup boost: no foe can attack this turn.")
    end

    next score
  }
)

#===============================================================================
# [NEW] Smart recovery usage (Recover, Roost, etc.)
#===============================================================================
Battle::AI::Handlers::GeneralMoveScore.add(:smart_recovery,
  proc { |score, move, user, ai, battle|
    next score unless ai.trainer.high_skill?
    next score if user.wild?
    
    healing_codes = [
      "HealUserHalfOfTotalHP",
      "HealUserHalfOfTotalHPLoseFlyingTypeThisTurn",
      "HealUserDependingOnWeather",
    ]
    next score unless healing_codes.include?(ai.safe_function_code(move))

    battler = user.battler
    next score unless battler
    hp_ratio = battler.hp.to_f / battler.totalhp

    # Check if foe can 2HKO — recovery is futile
    summary = ai.matchup_summary
    max_foe_dmg = summary[:max_foe_dmg]
    foe_damage_ratio = max_foe_dmg.to_f / [1, battler.totalhp].max
    PBDebug.log_ai("[smart_recovery] max foe dmg = #{max_foe_dmg} (#{(100.0 * foe_damage_ratio).round(1)}% totalhp, reward threshold 50%, fail threshold 60%)")

    if max_foe_dmg >= battler.totalhp * 0.6
      score -= 60
      PBDebug.log_score_change(-60, "Recovery futile: foe can 2HKO (#{(100 * max_foe_dmg / battler.totalhp).to_i}% per hit).")
      next score
    end

    if hp_ratio > 0.70
      penalty = (10 + (20 * (hp_ratio - 0.70) / 0.30)).to_i.clamp(15, 35)
      score -= penalty
      PBDebug.log_score_change(-penalty, "Smart recovery penalty at #{(hp_ratio * 100).to_i}% HP.")
    end

    next score if foe_damage_ratio > 0.50

    score += 20

    next score
  }
)

#===============================================================================
# [NEW] Smart Protect/Detect stalling
#===============================================================================
Battle::AI::Handlers::GeneralMoveScore.add(:smart_protect,
  proc { |score, move, user, ai, battle|
    next score unless ai.trainer.high_skill?
    protect_codes = [
      "ProtectUser",
      "ProtectUserBanefulBunker",
      "ProtectUserFromDamagingMovesKingsShield",
      "ProtectUserFromTargetingMovesSpikyShield"
    ]
    next score unless protect_codes.include?(ai.safe_function_code(move))

    battler = user.battler
    next score unless battler

    # Consecutive Protect — exponentially less likely to succeed
    if battler.effects[PBEffects::ProtectRate] > 1
      rate = battler.effects[PBEffects::ProtectRate]
      penalty = rate * 100
      score -= penalty
      PBDebug.log_score_change(-penalty, "Protect likely to fail (consecutive, rate=#{rate}).")
      next score
    end

    stall_value = 0

    # Residual damage on foe
    ai.each_foe_battler(user.side) do |b, i|
      stall_value += 10 if b.status == :POISON && b.statusCount > 0  # Toxic
      stall_value += 8  if b.status == :BURN
      stall_value += 5  if b.status == :POISON && b.statusCount == 0

      # Foe has setup moves — Protect gives them a free turn to boost
      if ai.battler_has_setup_move?(b)
        stall_value -= 15
        PBDebug.log_ai("[smart_protect] Foe #{b.name} has setup moves → -15 stall value.")
      end
    end

    # Speed Boost synergy
    stall_value += 12 if user.has_active_ability?(:SPEEDBOOST)

    # Leftovers/Black Sludge recovery
    stall_value += 5 if user.has_active_item?(:LEFTOVERS) || user.has_active_item?(:BLACKSLUDGE)

    # Wish incoming (Wish is a position effect, not a battler effect)
    position = battle.positions[battler.index]
    stall_value += 10 if position && position.effects[PBEffects::Wish] > 0

    if stall_value > 0
      score += stall_value
      PBDebug.log_score_change(stall_value, "Protect stall value.")
    else
      score -= 40
      PBDebug.log_score_change(-40, "Protect has no stall value.")
    end

    next score
  }
)

#===============================================================================
# [NEW] Smart Rest usage
#===============================================================================
Battle::AI::Handlers::GeneralMoveScore.add(:smart_rest,
  proc { |score, move, user, ai, battle|
    next score unless ai.trainer.high_skill?
    next score unless ai.safe_function_code(move) == "HealUserFullyAndFallAsleep"

    battler = user.battler
    next score unless battler

    hp_ratio = battler.hp.to_f / battler.totalhp

    # Not worth using above 50% HP
    next Battle::AI::MOVE_USELESS_SCORE if hp_ratio > 0.50

    # Already asleep
    next Battle::AI::MOVE_FAIL_SCORE if battler.status == :SLEEP

    # Chesto/Lum Berry allows instant wake
    if user.has_active_item?([:CHESTOBERRY, :LUMBERRY])
      score += 20
      PBDebug.log_score_change(20, "Rest: has Chesto/Lum Berry for instant wake.")
    end

    # Early Bird shortens sleep duration
    if user.has_active_ability?(:EARLYBIRD)
      score += 15
      PBDebug.log_score_change(15, "Rest: Early Bird shortens sleep.")
    end

    # Penalize if foe can set up while user sleeps
    if ai.foe_has_setup_move?(user) && !user.has_active_ability?(:UNAWARE)
      score -= 40
      PBDebug.log_score_change(-40, "Rest: foe has setup potential while user sleeps.")
    end

    next score
  }
)

Battle::AI::Handlers::GeneralMoveScore.add(:boost_pivot_moves,
  proc { |score, move, user, ai, battle|
    next score if !ai.trainer.high_skill?
    next score if !battle.pbCanChooseNonActive?(user.battler.index)

    is_pivot = Battle::AI::PIVOT_FUNCTION_CODES.include?(ai.safe_function_code(move))
    next score unless is_pivot

    score += 5  
    score += 5 if user.has_active_ability?(:REGENERATOR) && user.hp <= user.totalhp * 0.75
    score += 10 if user.battler.effects[PBEffects::Yawn] == 1 && user.battler.pbCanSleepYawn?
    next score
  }
)

#===============================================================================
# [NEW] Status Move Survival / Fail Check (Global)
#===============================================================================
Battle::AI::Handlers::GeneralMoveScore.add(:status_survival_check_global,
  proc { |score, move, user, ai, battle|
    next score if move.damagingMove?
    next score if user.wild?

    summary = ai.matchup_summary
    all_failed = true
    missed_followup_action = false
    has_foes = false

    ai.each_foe_battler(user.side) do |b, _i|
      has_foes = true
      foe_entry = summary[:foes][b.index]
      next unless foe_entry

      succeeds = ai.current_status_move_succeeds?(b, move)
      if succeeds == true
        all_failed = false
        missed_followup_action = true if ai.current_status_move_missed_followup_action?(b, move)
      end
    end

    if has_foes && all_failed
      score -= 100
      PBDebug.log_score_change(-100, "Global survival: status move fails or user KO'd before acting vs all foes")
    elsif missed_followup_action
      score -= 30
      PBDebug.log_score_change(-30, "Global survival: user can't act on the following turn")
    end

    next score
  }
)
