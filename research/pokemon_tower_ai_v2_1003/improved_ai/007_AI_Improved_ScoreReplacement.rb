#===============================================================================
# ScoreReplacement Handlers
# Simple handlers that work with raw Pokemon data.
#===============================================================================

class Battle::AI
  SLOW_PIVOT_FUNCTION_CODES = [
    "SwitchOutUserStatusMove",
    "SwitchOutUserDamagingMove",
    "SwitchOutUserPassOnEffects",
    "LowerTargetAtkSpAtk1SwitchOutUser",
    "StartHailWeatherSwitchOutUser",
    "SwitchOutUserStartHailWeather"
  ].freeze
  PIVOT_FUNCTION_CODES = (SLOW_PIVOT_FUNCTION_CODES + ["UserMakeSubstituteSwitchOut"]).freeze

  HAZARD_CLEAR_FUNCTION_CODES = [
    "RemoveUserBindingAndEntryHazards",
    "RemoveUserBindingAndEntryHazardsPoisonTarget",
    "LowerTargetEvasion1RemoveSideEffects",
    "RaiseUserAtkSpd1RemoveHazardsSubstitutes",
    "SwapSideEffects"
  ].freeze

  SWITCH_IN_SIM_MAX_TURNS = 4
  SWITCH_IN_WORST_CASE_DAMAGE_RATIO = 0.9
  RESERVE_TERA_ITEMS = [
    :TERAPIECE,
    :WELLSPRINGMASK,
    :HEARTHFLAMEMASK,
    :CORNERSTONEMASK,
    :TEALMASK
  ].freeze

  def priority_move_blocked_against?(user, target, move_data)
    return false if _move_priority(move_data[:move], user) <= 0
    return false unless target.opposes?(user)
    return true if @battle.field.terrain == :Psychic && target.affectedByTerrain?

    each_same_side_battler(target.side) do |b, _i|
      return true if b.has_active_ability?([:DAZZLING, :QUEENLYMAJESTY, :ARMORTAIL])
    end
    false
  end

  def damaging_move_acts_before?(attacker, attacker_move, defender, defender_move)
    return false if priority_move_blocked_against?(attacker, defender, attacker_move)
    return true if priority_move_blocked_against?(defender, attacker, defender_move)
    attacker_priority = _move_priority(attacker_move[:move], attacker)
    defender_priority = _move_priority(defender_move[:move], defender)
    return true if attacker_priority > defender_priority
    return false if attacker_priority < defender_priority
    attacker.faster_than?(defender)
  end

  def battler_can_ko_before_move?(battler, target, target_move)
    moves = damage_moves(battler, target)
    return false unless moves
    moves.values.any? do |move_data|
      move_data[:dmg].to_i >= target.hp.to_i &&
        damaging_move_acts_before?(battler, move_data, target, target_move)
    end
  end

  def best_foe_move_against_current(foe_battler, current_battler)
    foe_moves = damage_moves(foe_battler, current_battler)
    planned = tera_foe_damage_entry(foe_battler, current_battler, foe_moves, 0)
    return planned if planned
    best_move = _select_best_damage_move(foe_moves, foe_battler, current_battler)
    return best_move unless best_move

    best_move_wins = !priority_move_blocked_against?(foe_battler, current_battler, best_move) &&
      best_move[:dmg].to_i >= current_battler.hp.to_i &&
      !battler_can_ko_before_move?(current_battler, foe_battler, best_move)
    return best_move if best_move_wins

    winning_lethal_moves = foe_moves.values.select do |move_data|
      !priority_move_blocked_against?(foe_battler, current_battler, move_data) &&
        move_data[:dmg].to_i >= current_battler.hp.to_i &&
        !battler_can_ko_before_move?(current_battler, foe_battler, move_data)
    end
    return best_move if winning_lethal_moves.empty?

    winning_lethal_moves.max_by do |move_data|
      [_move_priority(move_data[:move], foe_battler), move_data[:dmg].to_i]
    end
  end

  def credible_switch_in_foe_move(foe_battler, original_target, foe_vs_current, foe_vs_reserve)
    return foe_vs_current || foe_vs_reserve unless foe_battler && original_target
    return foe_vs_current || foe_vs_reserve unless foe_vs_current && foe_vs_reserve
    return foe_vs_current if foe_vs_current[:key] == foe_vs_reserve[:key]

    current_dmg = damage_moves(foe_battler, original_target)
    reserve_move_vs_current = current_dmg&.[](foe_vs_reserve[:key])
    return foe_vs_current unless reserve_move_vs_current
    return foe_vs_current if priority_move_blocked_against?(
      foe_battler, original_target, reserve_move_vs_current
    )
    return foe_vs_current if battler_can_ko_before_move?(
      original_target, foe_battler, reserve_move_vs_current
    )

    current_best_dmg = foe_vs_current[:dmg].to_i
    reserve_move_dmg = reserve_move_vs_current[:dmg].to_i
    return foe_vs_current if current_best_dmg <= 0

    similar_damage = reserve_move_dmg >= (current_best_dmg * SWITCH_IN_WORST_CASE_DAMAGE_RATIO).ceil
    lethal_damage = reserve_move_dmg >= original_target.hp.to_i
    (similar_damage || lethal_damage) ? foe_vs_reserve : foe_vs_current
  end

  def replacement_1v1_results_key(idxBattler, pkmn)
    battler = @battle.battlers[idxBattler]
    party = @battle.pbParty(idxBattler)
    party_index = party.index(pkmn)
    foe_snapshot = @battle.allOtherSideBattlers(idxBattler).map do |foe|
      [foe.index, foe.pokemon&.personalID, foe.pokemonIndex, foe.turnCount, foe.fainted?]
    end
    [
      idxBattler,
      @battle.command_phase,
      battler.pokemon&.personalID,
      battler.pokemonIndex,
      party_index,
      pkmn.personalID,
      foe_snapshot
    ]
  end

  def replacement_1v1_results(idxBattler, pkmn)
    key = replacement_1v1_results_key(idxBattler, pkmn)
    @_replacement_1v1_results ||= {}
    @_replacement_1v1_results[key] ||= build_replacement_1v1_results(idxBattler, pkmn)
  end

  def replacement_1v1_result_for_foe(idxBattler, pkmn, foe_battler)
    foe_index = foe_battler.is_a?(Integer) ? foe_battler : foe_battler.index
    foe_results = replacement_1v1_results(idxBattler, pkmn)&.[](foe_index)
    return nil unless foe_results
    return foe_results if foe_battler.is_a?(Integer)
    return nil if foe_results[:foe_personal_id] != foe_battler.pokemon&.personalID
    foe_results
  end

  def replacement_move_survives?(foe_results, move_id, status_move: false)
    return false unless foe_results
    if status_move
      cached = foe_results[:status_move_survival]&.dig(move_id)
      return cached.is_a?(Hash) ? cached[:success] == true : cached == true
    end

    foe_results[:damaging_move_results]&.any? do |move_result|
      next false if move_result[:move_id] != move_id
      result = move_result[:result]
      result && result.user_succeeded && !result.user_fainted
    end
  end

  def reserve_can_terastallize_after_switch?(idxBattler, pkmn)
    return false unless pkmn
    return false if $game_switches[Settings::NO_TERASTALLIZE]
    return false unless pkmn.respond_to?(:terastal_able?) && pkmn.terastal_able?
    return false if pkmn.respond_to?(:tera?) && pkmn.tera?
    return false unless RESERVE_TERA_ITEMS.include?(pkmn.item_id)
    return false unless @battle.pbHasTeraOrb?(idxBattler)
    return false if @battle.pbOwnedByPlayer?(idxBattler) && !$player.tera_charged?

    battler = @battle.battlers[idxBattler]
    side = battler ? battler.idxOwnSide : (idxBattler & 1)
    owner = @battle.pbGetOwnerIndexFromBattlerIndex(idxBattler)
    @battle.terastallize[side][owner] == -1
  rescue StandardError
    false
  end

  def replacement_result_better?(result, best_result)
    return false unless result
    return true unless best_result
    return true if result.user_wins? && !best_result.user_wins?
    if result.user_wins? && best_result.user_wins?
      return (result.user_hp || 0) > (best_result.user_hp || 0)
    end
    # This was previously implicit because a double KO leaves the target at
    # 0 HP. Preserve that ordering explicitly: win > double KO > other result.
    if result.double_ko? && !best_result.user_wins? && !best_result.double_ko?
      return true
    end
    if best_result.double_ko? && !result.user_wins? && !result.double_ko?
      return false
    end
    if !result.user_wins? && !best_result.user_wins?
      return (result.target_hp || 0) < (best_result.target_hp || 0)
    end
    false
  end

  def successful_user_pivot_result?(result, idxBattler)
    result &&
      result.terminated_by_switch &&
      result.switch_type == :live_switch &&
      result.switch_battler_index == idxBattler &&
      result.user_succeeded &&
      !result.user_fainted
  end

  def successful_setup_baton_pass_result?(result, idxBattler)
    successful_user_pivot_result?(result, idxBattler) &&
      result.turns >= 2 &&
      result.turn_log&.first&.dig(:user_succeeded) == true
  end

  def build_pivot_damage_replacement_results(idxBattler, pkmn, foe_battler, pivot_result, pivot_move)
    party = @battle.pbParty(idxBattler)
    party_index = party.index(pkmn)
    return nil unless party_index

    pre_switch = { idxBattler => party_index }
    base_scenario = SimulationScenario.switch(pre_switch)
    reserve_dmg = damage_profile(idxBattler, foe_battler.index, base_scenario) || {}
    reserve_candidates = reserve_dmg.values.sort_by { |md| -md[:dmg] }
    foe_dmg = damage_profile(foe_battler.index, idxBattler, base_scenario) || {}
    foe_vs_reserve = _select_best_damage_move(
      foe_dmg, foe_battler, target_for_damage_selection(idxBattler, base_scenario)
    )
    foe_vs_reserve_action = simulation_action_for_move_data(foe_vs_reserve)

    foe_vs_current = best_foe_move_against_current(foe_battler, @user) unless @user.fainted?
    foe_results = {
      voluntary_switch: !pivot_result.target_got_action,
      reserve_candidates: reserve_candidates, tera_reserve_candidates: [],
      best_result: nil, best_result_tera: false,
      entry_user_fainted: false, entry_foe_fainted: false,
      entry_user_hp: nil, entry_foe_hp: nil
    }

    md = reserve_candidates.first
    move_action = simulation_action_for_move_data(md) if md

    # Let the actual pivot move perform the switch in the simulation.
    # This preserves damage, passed effects, the pending foe action and EOR.
    sim = prepare_sim_for_scenario(SimulationScenario.current)
    pivot_choice = [idxBattler, party_index, false]
    sim.instance_variable_set(:@_sim_pivot_replacement, pivot_choice)
    begin
      result = simulate_battle(
        idxBattler, foe_battler.index,
        [pivot_move.id, move_action],
        [simulation_action_for_move_data(foe_vs_current), foe_vs_reserve_action],
        max_turns: move_action ? Battle::AI::SWITCH_IN_SIM_MAX_TURNS + 1 : 1,
        lock_user_first_action: true, sim: sim
      )
    ensure
      sim.instance_variable_set(:@_sim_pivot_replacement, nil)
    end
    return nil unless pivot_choice[2] && sim.battlers[idxBattler].pokemon&.personalID == pkmn.personalID

    entry_turn = result.turn_log.shift
    foe_results[:entry_user_hp] = entry_turn&.dig(:user_hp_after) || result.user_hp
    foe_results[:entry_foe_hp] = entry_turn&.dig(:target_hp_after) || result.target_hp
    foe_results[:entry_user_fainted] = foe_results[:entry_user_hp].to_i <= 0
    foe_results[:entry_foe_fainted] = foe_results[:entry_foe_hp].to_i <= 0
    foe_results[:reserve_candidates] = [] if foe_results[:entry_foe_fainted]
    result.user_initial_hp = pkmn.hp
    result.user_entry_hp = foe_results[:entry_user_hp]
    result.target_entry_hp = foe_results[:entry_foe_hp]
    result.turns = [result.turns - 1, 0].max
    result.user_ko_turn = [result.user_ko_turn - 1, 0].max if result.user_ko_turn
    result.target_ko_turn = [result.target_ko_turn - 1, 0].max if result.target_ko_turn
    result.user_got_action = result.turn_log.any? { |turn| turn[:user_acted] }
    result.target_got_action = result.turn_log.any? { |turn| turn[:target_acted] }
    result.user_succeeded = result.turn_log.any? { |turn| turn[:user_succeeded] }
    result.target_succeeded = result.turn_log.any? { |turn| turn[:target_succeeded] }

    foe_results[:best_result] = result
    foe_results
  end

  def build_replacement_1v1_results(idxBattler, pkmn)
    party = @battle.pbParty(idxBattler)
    party_index = party.index(pkmn)
    return {} unless party_index

    pre_switch = { idxBattler => party_index }
    all_results = {}

    each_foe_battler(@user.side) do |b, _i|
      voluntary_switch = @battle.command_phase || (!b.movedThisRound? && b.turnCount > 0)
      foe_vs_current = best_foe_move_against_current(b, @user) unless @user.fainted?
      foe_vs_current_action = foe_vs_current ? simulation_action_for_move_data(foe_vs_current) : nil

      foe_vs_reserve = best_damage_move_with_switch(b.index, idxBattler, pre_switch)
      foe_vs_reserve_action = foe_vs_reserve ? simulation_action_for_move_data(foe_vs_reserve) : foe_vs_current_action
      foe_switch_in = if voluntary_switch && !foe_vs_current
        nil
      else
        credible_switch_in_foe_move(b, @user, foe_vs_current, foe_vs_reserve)
      end
      foe_switch_in_action = foe_switch_in ? simulation_action_for_move_data(foe_switch_in) : foe_vs_current_action

      foe_results = {
        foe_index: b.index,
        foe_personal_id: b.pokemon&.personalID,
        foe_vs_current: foe_vs_current,
        foe_vs_reserve: foe_vs_reserve,
        foe_switch_in: foe_switch_in,
        foe_switch_in_action: foe_switch_in_action,
        voluntary_switch: voluntary_switch,
        reserve_candidates: [],
        tera_reserve_candidates: [],
        damaging_move_results: [],
        status_move_survival: {},
        best_result: nil,
        best_move_action: nil,
        best_result_tera: false,
        entry_user_fainted: false,
        entry_foe_fainted: false,
        entry_user_hp: nil,
        entry_foe_hp: nil
      }
      all_results[b.index] = foe_results

      base_scenario = if voluntary_switch && foe_switch_in_action
        SimulationScenario.voluntary_switch(pre_switch, b.index, foe_switch_in_action)
      else
        SimulationScenario.switch(pre_switch)
      end
      entry_sim = prepare_sim_for_scenario(base_scenario)
      entry_user = entry_sim.battlers[idxBattler]
      entry_foe = entry_sim.battlers[b.index]
      foe_results[:entry_user_fainted] = entry_user&.fainted? || false
      foe_results[:entry_foe_fainted] = entry_foe&.fainted? || false
      foe_results[:entry_user_hp] = entry_user&.hp
      foe_results[:entry_foe_hp] = entry_foe&.hp

      reserve_dmg = damage_profile(idxBattler, b.index, base_scenario) || {}
      reserve_candidates = reserve_dmg.values.sort_by { |md| -md[:dmg] }
      foe_results[:reserve_candidates] = reserve_candidates.map(&:dup)

      scenario_candidates = [
        {
          scenario: base_scenario,
          candidates: reserve_candidates,
          tera: false
        }
      ]
      if reserve_can_terastallize_after_switch?(idxBattler, pkmn)
        tera_scenario = base_scenario.with_form_change(idxBattler, :tera)
        tera_reserve_dmg = damage_profile(idxBattler, b.index, tera_scenario) || {}
        tera_candidates = tera_reserve_dmg.values.sort_by { |md| -md[:dmg] }
        foe_results[:tera_reserve_candidates] = tera_candidates.map(&:dup)
        scenario_candidates << {
          scenario: tera_scenario,
          candidates: tera_candidates,
          tera: true
        }
      end

      if !foe_vs_reserve_action && scenario_candidates.all? { |candidate| candidate[:candidates].empty? }
        foe_results[:skip_scoring] = true
        next
      end

      # Only precompute the top damaging line for replacement scoring.
      # Other moves are simulated on-demand by explicit callers that need them.
      scenario_candidates.each do |scenario_candidate|
        md = scenario_candidate[:candidates].first
        next unless md
        move_action = simulation_action_for_move_data(md)
        next unless move_action

        sim = prepare_sim_for_scenario(scenario_candidate[:scenario])
        result = simulate_battle(
          idxBattler, b.index,
          [move_action], [foe_vs_reserve_action],
          scenario: scenario_candidate[:scenario],
          max_turns: Battle::AI::SWITCH_IN_SIM_MAX_TURNS,
          sim: sim
        )

        foe_results[:damaging_move_results] << {
          move_id: md[:move]&.id,
          action: move_action,
          move_data: md.dup,
          result: result,
          tera: scenario_candidate[:tera]
        }

        if replacement_result_better?(result, foe_results[:best_result])
          foe_results[:best_result] = result
          foe_results[:best_move_action] = move_action
          foe_results[:best_result_tera] = scenario_candidate[:tera]
        end
      end
    end

    all_results
  end

  def score_replacement_1v1_results(pkmn, foe_battler, foe_results, damage_only: false)
    return 0 unless foe_results
    return 0 if foe_results[:skip_scoring] || foe_results[:skipped_reason]

    if foe_results[:reserve_candidates].empty? && foe_results[:tera_reserve_candidates].empty?
      if foe_results[:entry_user_fainted]
        if foe_results[:entry_foe_fainted]
          PBDebug.log_score_change(0, "#{pkmn.name} vs #{foe_battler.name}: trades on switch-in")
          return 0
        end
        PBDebug.log_score_change(-50, "#{pkmn.name} vs #{foe_battler.name}: dies on entry")
        return -50
      end
      if foe_results[:entry_foe_fainted]
        hp = foe_results[:entry_user_hp] || pkmn.hp
        hp_pct = hp.to_f / [pkmn.totalhp, 1].max
        bonus = 10 + (hp_pct * 10).round
        PBDebug.log_score_change(bonus,
          "#{pkmn.name} vs #{foe_battler.name}: wins on switch-in (foe fainted to end-of-round damage, #{(hp_pct * 100).round}% remaining)")
        return bonus
      end
      if !damage_only && pkmn.moves.any? { |m| m.status_move? && reserve_status_move_succeeds?(@user.index, pkmn, foe_battler, m.id) }
        PBDebug.log_score_change(0, "#{pkmn.name} vs #{foe_battler.name}: no damaging moves, but can act with status")
        return 0
      end
      reason = damage_only ? "has no damaging follow-up" : "dies before using a status move"
      PBDebug.log_score_change(-50, "#{pkmn.name} vs #{foe_battler.name}: #{reason}")
      return -50
    end

    best_result = foe_results[:best_result]
    died_on_entry = best_result.nil? ||
                    (best_result.user_fainted && !best_result.user_succeeded && !best_result.double_ko?)
    if died_on_entry
      PBDebug.log_score_change(-50, "#{pkmn.name} vs #{foe_battler.name}: dies on entry")
      return -50
    end

    # --- Extract HP data from scenario snapshots.
    first_turn = best_result.turn_log&.first
    initial_hp = best_result.user_initial_hp || pkmn.hp
    entry_hp = best_result.user_entry_hp || (first_turn ? first_turn[:user_hp_before] : initial_hp)
    entry_hp_pct = entry_hp.to_f / [pkmn.totalhp, 1].max
    foe_start_hp = best_result.target_entry_hp || (first_turn ? first_turn[:target_hp_before] : foe_battler.hp)
    voluntary = foe_results[:voluntary_switch]
    tera_note = foe_results[:best_result_tera] ? " with Tera" : ""

    # How much HP we're "spending" by sending this pkmn in (relative to its max)
    hp_invested_pct = initial_hp.to_f / [pkmn.totalhp, 1].max

    # --- Switch-in fragility penalty (voluntary switches only) ---
    # Heavy free-turn damage makes the switch-in risky
    # Concave integer curve: 0 at <=30%, ~20 at 70%, and 30 at 100%.
    # This makes fragile switch-ins score lower than bulky alternatives,
    # so they're only chosen when nothing healthier is available.
    fragility_penalty = 0
    if voluntary
      total_hp = [pkmn.totalhp, 1].max
      entry_damage = [initial_hp - entry_hp, 0].max
      switch_in_damage_pct = ((entry_damage * 100) + (total_hp / 2)) / total_hp
      if switch_in_damage_pct > 30
        excess_damage_pct = (switch_in_damage_pct - 30).clamp(0, 70)
        curve_value = excess_damage_pct * (250 - excess_damage_pct)
        fragility_penalty = ((curve_value + 210) / 420).clamp(0, 30)
        PBDebug.log_score_change(-fragility_penalty,
          "#{pkmn.name} vs #{foe_battler.name}: risky entry (took #{switch_in_damage_pct}% on switch-in, #{(entry_hp_pct * 100).round}% HP remaining)")
      end
    end

    if best_result.double_ko?
      # Both sides fainted. Score the trade by the percentage of max HP each
      # side committed, matching the old implicit net-HP behavior while keeping
      # it separate from the no-KO wall logic below.
      dmg_dealt = foe_start_hp - (best_result.target_hp || 0)
      dmg_dealt_pct = dmg_dealt.to_f / [foe_battler.totalhp, 1].max
      hp_lost = initial_hp - (best_result.user_hp || 0)
      hp_lost_pct = hp_lost.to_f / [pkmn.totalhp, 1].max
      net_trade = dmg_dealt_pct - hp_lost_pct
      bonus = (net_trade * 15).round.clamp(-10, 10) - fragility_penalty
      ko_turn = [best_result.target_ko_turn, best_result.user_ko_turn].compact.max
      turn_note = ko_turn ? " on turn #{ko_turn}" : ""
      PBDebug.log_score_change(bonus + fragility_penalty,
        "#{pkmn.name}#{tera_note} vs #{foe_battler.name}: double KO trade#{turn_note} " \
        "(foe HP invested #{(dmg_dealt_pct * 100).round}%, user HP invested #{(hp_lost_pct * 100).round}%)")
      return bonus

    elsif best_result.user_wins?
      u_turns = best_result.target_ko_turn || 999
      f_turns = best_result.user_ko_turn || 999
      turn_adv = f_turns - u_turns
      bonus = 5 + [turn_adv * 5, 10].min
      bonus += 10 if best_result.user_can_ohko?
      hp_pct = best_result.user_hp.to_f / [pkmn.totalhp, 1].max
      bonus = hp_pct >= 0.25 ? bonus + (hp_pct * 10).round : bonus - ((1 - hp_pct) * 10).round
      bonus -= fragility_penalty
      PBDebug.log_score_change(bonus + fragility_penalty, "#{pkmn.name}#{tera_note} vs #{foe_battler.name}: wins (KO turn #{u_turns}, #{(hp_pct * 100).round}% remaining)")
      return bonus

    elsif best_result.target_wins?
      # --- Trade-value-aware loss scoring ---
      dmg_dealt_pct = 0.0
      if best_result.target_hp && foe_battler.totalhp > 0
        dmg_dealt = foe_start_hp - best_result.target_hp
        dmg_dealt_pct = dmg_dealt.to_f / foe_battler.totalhp
      end
      trade_ratio = hp_invested_pct > 0 ? dmg_dealt_pct / hp_invested_pct : 0.0
      f_turns = best_result.user_ko_turn || 999

      if trade_ratio >= 1.0
        # Excellent trade: dealt more %HP to foe than we had
        penalty = (5 - [f_turns - 1, 3].min).clamp(0, 5)
      elsif trade_ratio >= 0.6
        # Decent trade
        penalty = (15 - (trade_ratio * 15).round).clamp(5, 15)
        penalty -= [f_turns - 2, 2].min if f_turns > 2
      else
        # Bad trade
        penalty = 15
        penalty += best_result.target_can_ohko? ? [15 - (trade_ratio * 20).round, 0].max : 0
        penalty += ((1.0 - trade_ratio) * 10).round
        penalty -= f_turns * 2 if f_turns > 2
        penalty = penalty.clamp(15, 40)
      end

      penalty += fragility_penalty
      PBDebug.log_score_change(-penalty,
        "#{pkmn.name}#{tera_note} vs #{foe_battler.name}: loses (KO'd turn #{f_turns}, dealt #{(dmg_dealt_pct * 100).round}%, trade ratio #{(trade_ratio * 100).round}%)")
      return -penalty

    else
      # --- No KO: net HP trade (signed) ---
      dmg_dealt_pct = 0.0
      hp_lost_pct = 0.0
      if best_result.target_hp && foe_battler.totalhp > 0
        dmg_dealt = foe_start_hp - best_result.target_hp
        dmg_dealt_pct = dmg_dealt.to_f / foe_battler.totalhp
      end
      if best_result.user_hp && pkmn.totalhp > 0
        hp_lost = initial_hp - best_result.user_hp
        hp_lost_pct = hp_lost.to_f / pkmn.totalhp
      end
      net_trade = dmg_dealt_pct - hp_lost_pct
      bonus = (net_trade * 15).round.clamp(-10, 10) - fragility_penalty
      
      # walls foe
      bonus += best_result.turn_log.length * 5 if best_result.turn_log.length > 2
      PBDebug.log_score_change(bonus + fragility_penalty,
        "#{pkmn.name}#{tera_note} vs #{foe_battler.name}: no KO (dealt #{(dmg_dealt_pct * 100).round}%, lost #{(hp_lost_pct * 100).round}%)")
      return bonus
    end
  end

  def side_hazard_clear_bonus(side)
    bonus = 0
    bonus += 20 if side.effects[PBEffects::StealthRock]
    bonus += 12 * side.effects[PBEffects::Spikes]
    bonus += 10 * side.effects[PBEffects::ToxicSpikes]
    bonus += 12 if side.effects[PBEffects::StickyWeb]
    bonus
  end

  def reserve_has_followup_switch_option?(idxBattler, reserve_party_index)
    @battle.eachInTeamFromBattlerIndex(idxBattler) do |_pkmn, i|
      next if i == reserve_party_index
      return true if @battle.pbCanSwitchIn?(idxBattler, i)
    end
    false
  end

  # The low-threat shortcut in reserve_status_move_succeeds? establishes that
  # the reserve survives long enough to act, but doesn't establish that the
  # target can receive the intended status. Check that separately on a battle
  # snapshot where the reserve is the actual move user.
  def reserve_status_condition_applicable?(idxBattler, pkmn, target_battler, pkmn_move)
    function_code = safe_function_code(pkmn_move)
    status_function_codes = [
      "BurnTarget",
      "ParalyzeTarget",
      "ParalyzeTargetIfNotTypeImmune",
      "PoisonTarget",
      "BadPoisonTarget",
      "SleepTargetNextTurn"
    ]
    return true unless status_function_codes.include?(function_code)

    party_index = @battle.pbParty(idxBattler).index(pkmn)
    return false unless party_index

    sim = prepare_sim_for_scenario(SimulationScenario.switch(idxBattler => party_index))
    user = sim.battlers[idxBattler]
    target = sim.battlers[target_battler.index]
    move = user&.moves&.find { |candidate| candidate&.id == pkmn_move.id }
    return false unless user && target && move

    case function_code
    when "BurnTarget"
      target.pbCanBurn?(user, false, move)
    when "ParalyzeTarget", "ParalyzeTargetIfNotTypeImmune"
      if function_code == "ParalyzeTargetIfNotTypeImmune"
        move_type = move.pbCalcType(user)
        type_mod = move.pbCalcTypeMod(move_type, user, target)
        return false if Effectiveness.ineffective?(type_mod)
      end
      target.pbCanParalyze?(user, false, move)
    when "PoisonTarget", "BadPoisonTarget"
      target.pbCanPoison?(user, false, move)
    when "SleepTargetNextTurn"
      target.effects[PBEffects::Yawn] == 0 && target.pbCanSleep?(user, false, move)
    end
  end

  def reserve_slow_pivot_bonus(idxBattler, pkmn, foe_battler, pre_switch, voluntary_switch: @battle.command_phase)
    party = @battle.pbParty(idxBattler)
    reserve_party_index = party.index(pkmn)
    return 0 unless reserve_party_index
    return 0 unless reserve_has_followup_switch_option?(idxBattler, reserve_party_index)

    pivot_moves = pkmn.moves.select do |m|
      m.is_a?(Pokemon::Move) && SLOW_PIVOT_FUNCTION_CODES.include?(safe_function_code(m))
    end
    return 0 if pivot_moves.empty?

    cached_foe_results = replacement_1v1_result_for_foe(idxBattler, pkmn, foe_battler)
    foe_vs_reserve = cached_foe_results ? cached_foe_results[:foe_vs_reserve] :
      best_damage_move_with_switch(foe_battler.index, idxBattler, pre_switch)
    foe_vs_reserve_action = foe_vs_reserve ? simulation_action_for_move_data(foe_vs_reserve) : nil
    return 0 unless foe_vs_reserve_action

    foe_vs_current = if cached_foe_results
      cached_foe_results[:foe_vs_current]
    elsif !@user.fainted?
      best_foe_move_against_current(foe_battler, @user)
    end
    foe_vs_current_action = foe_vs_current ? simulation_action_for_move_data(foe_vs_current) : nil
    foe_switch_in_action = if cached_foe_results
      cached_foe_results[:foe_switch_in_action]
    elsif voluntary_switch && !foe_vs_current
      nil
    else
      foe_switch_in = credible_switch_in_foe_move(foe_battler, @user, foe_vs_current, foe_vs_reserve)
      foe_switch_in ? simulation_action_for_move_data(foe_switch_in) : foe_vs_current_action
    end

    best_bonus = 0
    pivot_scenario = nil

    pivot_moves.each do |move|
      move_data = GameData::Move.get(move.id)
      damaging_pivot = move_data.category != 2
      next if !voluntary_switch && !damaging_pivot

      damaging_result = cached_foe_results&.dig(:damaging_move_results)&.find do |move_result|
        move_result[:move_id] == move.id
      end
      result = damaging_result ? damaging_result[:result] : nil
      if !result
        pivot_scenario ||= if voluntary_switch && foe_switch_in_action
          SimulationScenario.voluntary_switch(pre_switch, foe_battler.index, foe_switch_in_action)
        else
          SimulationScenario.switch(pre_switch)
        end
        result = simulate_battle(
          idxBattler, foe_battler.index,
          [move.id], [foe_vs_reserve_action],
          scenario: pivot_scenario, max_turns: 1
        )
      end
      next unless result.terminated_by_switch &&
                  result.switch_type == :live_switch &&
                  result.switch_battler_index == idxBattler
      next unless result.user_succeeded && !result.user_fainted
      next unless result.target_got_action

      if voluntary_switch
        hp_pct = result.user_hp.to_f / [pkmn.totalhp, 1].max
        bonus = 15 + (damaging_pivot ? 2 : 0) + (hp_pct * 5).round
        log_detail = "voluntary, #{(hp_pct * 100).round}% HP remaining"
      else
        turn = result.turn_log&.first
        target_hp_before = turn&.dig(:target_hp_before).to_i
        target_hp_after = turn&.dig(:target_hp_after) || target_hp_before
        damage = [target_hp_before - target_hp_after, 0].max
        damage_pct = target_hp_before > 0 ? damage.to_f / target_hp_before : 0.0
        damage_bonus = (damage_pct * 8).round.clamp(0, 8)
        bonus = 2 + damage_bonus
        log_detail = "non-voluntary entry, dealt #{(damage_pct * 100).round}% current HP"
      end

      if bonus > best_bonus
        best_bonus = bonus
        PBDebug.log_ai("[slow_pivot] #{pkmn.name} can slow pivot with #{move.name} vs #{foe_battler.name} " \
                       "(#{log_detail}, +#{bonus})")
      end
    end

    best_bonus
  end

  def extreme_evoboost_baton_pass_candidate?(idxBattler, pkmn)
    return false unless pkmn&.able?
    return false unless pkmn.species == :EEVEE && pkmn.item_id == :EEVIUMZ
    party_index = @battle.pbParty(idxBattler).index(pkmn)
    return false unless party_index && @battle.pbCanSwitchIn?(idxBattler, party_index)
    return false unless zmove_available_for_battler_index?(idxBattler)

    last_resort = pkmn.moves.find { |move| move&.id == :LASTRESORT && move.pp > 0 }
    baton_pass = pkmn.moves.find { |move| move&.id == :BATONPASS && move.pp > 0 }
    last_resort && baton_pass
  end

  def reserve_extreme_evoboost_baton_pass_result(idxBattler, pkmn, foe_battler)
    return nil unless extreme_evoboost_baton_pass_candidate?(idxBattler, pkmn)

    party_index = @battle.pbParty(idxBattler).index(pkmn)
    foe_results = replacement_1v1_result_for_foe(idxBattler, pkmn, foe_battler)
    return nil unless party_index && foe_results

    foe_vs_reserve_action = simulation_action_for_move_data(foe_results[:foe_vs_reserve])
    foe_switch_in_action = foe_results[:foe_switch_in_action]
    scenario = if foe_results[:voluntary_switch] && foe_switch_in_action
      SimulationScenario.voluntary_switch(
        { idxBattler => party_index }, foe_battler.index, foe_switch_in_action
      )
    else
      SimulationScenario.switch(idxBattler => party_index)
    end

    cache_key = [
      :extreme_evoboost_baton_pass,
      idxBattler,
      pkmn.personalID,
      foe_battler.index,
      foe_battler.pokemon&.personalID,
      @battle.turnCount,
      scenario.cache_key,
      foe_vs_reserve_action
    ]
    cache = (@_ai_dmg_cache ||= {})
    return cache[cache_key] if cache.key?(cache_key)

    cache[cache_key] = simulate_battle(
      idxBattler, foe_battler.index,
      [:EXTREMEEVOBOOST, :BATONPASS],
      foe_vs_reserve_action ? [foe_vs_reserve_action] : [],
      scenario: scenario,
      max_turns: 2,
      lock_user_actions: true
    )
  end

end

module Battle::AI::Handlers
  PivotReplacement = HandlerHash.new

  def self.score_pivot_replacement(idxBattler, pivot_results, pivot_move, battle, user_ai)
    best_score = nil
    battle.pbParty(idxBattler).each_with_index do |pkmn, i|
      next if !pkmn || !battle.pbCanSwitchIn?(idxBattler, i)
      score = score_pivot_replacement_candidate(
        idxBattler, pkmn, pivot_results, pivot_move, 100, battle, user_ai
      )
      best_score = score if score && (!best_score || score > best_score)
    end
    best_score
  end

  def self.score_pivot_replacement_candidate(idxBattler, pkmn, pivot_results, pivot_move, score, battle, user_ai)
    PivotReplacement.each do |_id, score_proc|
      score = score_proc.call(idxBattler, pkmn, pivot_results, pivot_move, score, battle, user_ai)
      return nil unless score
    end
    score
  end
end

Battle::AI::Handlers::PivotReplacement.add(:damage_only_matchup,
  proc { |idxBattler, pkmn, pivot_results, pivot_move, score, battle, ai|
    pivot_results.each do |foe, result|
      foe_results = ai.build_pivot_damage_replacement_results(
        idxBattler, pkmn, foe, result, pivot_move
      )
      if !foe_results
        score = nil
        break
      end
      score += ai.score_replacement_1v1_results(
        pkmn, foe, foe_results, damage_only: true
      )
    end
    next score
  }
)

Battle::AI::Handlers::ScoreReplacement.add(:entry_hazards,
  proc { |idxBattler, pkmn, score, battle, ai|
    prev_score = score
    entry_hazard_damage = ai.calculate_entry_hazard_damage(pkmn, idxBattler & 1)
    if entry_hazard_damage >= pkmn.hp
      score -= 50   # pkmn will just faint
    end
    PBDebug.log_score_change(score - prev_score, "#{pkmn.name}: entry hazard damage #{entry_hazard_damage}")
    next score
  }
)

Battle::AI::Handlers::ScoreReplacement.add(:toxics_spikes_and_sticky_web,
  proc { |idxBattler, pkmn, score, battle, ai|
    if !pkmn.hasItem?(:HEAVYDUTYBOOTS) && !ai.pokemon_airborne?(pkmn)
      # Toxic Spikes
      if ai.user.pbOwnSide.effects[PBEffects::ToxicSpikes] > 0
        if ai.pokemon_can_be_poisoned?(pkmn)
          score -= 10
        elsif pkmn.types.include?(:POISON)
          score += 10
        end
      end
    end
    next score
  }
)

#===============================================================================
# 1v1 Matchup Evaluation via Battle Simulation
# Simulates the reserve switching in and fighting each foe.
# - Voluntary switch (command phase): foe gets a free attack during switch-in
# - Faint replacement / pivot (attack phase): entry effects only, no free hit
#===============================================================================
Battle::AI::Handlers::ScoreReplacement.add(:one_v_one_matchup,
  proc { |idxBattler, pkmn, score, battle, ai|
    cached_results = ai.replacement_1v1_results(idxBattler, pkmn)
    next score if !cached_results || cached_results.empty?

    ai.each_foe_battler(ai.user.side) do |b, _i|
      score += ai.score_replacement_1v1_results(pkmn, b, cached_results[b.index])
    end

    if pkmn.item_id == :FOCUSSASH && pkmn.hp == pkmn.totalhp
      sash_broken = cached_results.any? do |_foe_index, foe_results|
        entry_hp = foe_results && foe_results[:entry_user_hp]
        !entry_hp.nil? && entry_hp < pkmn.totalhp
      end
      if sash_broken
        score -= 5
        PBDebug.log_score_change(-5, "#{pkmn.name}: Focus Sash broken on entry")
      end
    end
    next score
  }
)

Battle::AI::Handlers::ScoreReplacement.add(:extreme_evoboost_baton_pass,
  proc { |idxBattler, pkmn, score, battle, ai|
    next score unless ai.extreme_evoboost_baton_pass_candidate?(idxBattler, pkmn)

    checked_foe = false
    completed_sequence = true
    ai.each_foe_battler(ai.user.side) do |foe, _i|
      checked_foe = true
      result = ai.reserve_extreme_evoboost_baton_pass_result(idxBattler, pkmn, foe)
      if !ai.successful_setup_baton_pass_result?(result, idxBattler)
        completed_sequence = false
        break
      end
    end
    next score unless checked_foe && completed_sequence

    score += 100
    PBDebug.log_score_change(100,
      "#{pkmn.name}: can switch in, use Extreme Evoboost, and Baton Pass")
    next score
  }
)

Battle::AI::Handlers::ScoreReplacement.add(:safe_setup_reserve,
  proc { |idxBattler, pkmn, score, battle, ai|
    next score if pkmn.hp <= 0
    setup_moves = pkmn.moves.select do |m|
      next false unless m.is_a?(Pokemon::Move)
      next false if ai.safe_function_code(m) == "CurseTargetOrLowerUserSpd1RaiseUserAtkDef1" &&
                    pkmn.types.include?(:GHOST)
      ai.move_is_setup?(m)
    end
    next score if setup_moves.empty?

    cached_results = ai.replacement_1v1_results(idxBattler, pkmn)
    next score if !cached_results || cached_results.empty?

    max_foe_dmg = 0
    checked_foe = false
    unknown_damage = false
    ai.each_foe_battler(ai.user.side) do |b, _i|
      foe_results = cached_results[b.index]
      if !foe_results || foe_results[:skipped_reason]
        unknown_damage = true
        break
      end
      checked_foe = true
      foe_vs_reserve = foe_results[:foe_vs_reserve]
      max_foe_dmg = [max_foe_dmg, foe_vs_reserve ? foe_vs_reserve[:dmg].to_i : 0].max
    end
    next score if unknown_damage || !checked_foe
    next score unless max_foe_dmg * 10 < pkmn.hp * 3

    bonus = 10
    score += bonus
    setup_names = setup_moves.map(&:name).join("/")
    PBDebug.log_score_change(bonus,
      "#{pkmn.name}: safe setup reserve (#{setup_names}; max foe damage #{max_foe_dmg}/#{pkmn.hp} HP)")
    next score
  }
)

Battle::AI::Handlers::ScoreReplacement.add(:trick_room_setter_with_ace,
  proc { |idxBattler, pkmn, score, battle, ai|
    next score if battle.field.effects[PBEffects::TrickRoom] > 0
    trick_room = pkmn.moves.find do |m|
      m.is_a?(Pokemon::Move) && ai.safe_function_code(m) == "StartSlowerBattlersActFirst"
    end
    next score unless trick_room

    foe_speeds = []
    ai.each_foe_battler(ai.user.side) { |b, _i| foe_speeds << b.pbSpeed }
    next score if foe_speeds.empty?

    slowest_foe_speed = foe_speeds.min
    party = battle.pbParty(idxBattler)
    ace_names = []
    party.each_with_index do |reserve, i|
      next if !reserve || !battle.pbCanSwitchIn?(idxBattler, i)
      next if reserve.ev[:ATTACK] <= 100 && reserve.ev[:SPECIAL_ATTACK] <= 100
      next if reserve.speed >= slowest_foe_speed
      ace_names << reserve.name
    end
    next score if ace_names.empty?

    succeeds = true
    ai.each_foe_battler(ai.user.side) do |b, _i|
      if !ai.reserve_status_move_succeeds?(idxBattler, pkmn, b, trick_room.id)
        succeeds = false
        break
      end
    end
    next score unless succeeds

    bonus = 25
    score += bonus
    PBDebug.log_score_change(bonus,
      "#{pkmn.name}: can set Trick Room for ace reserve #{ace_names.join('/')}")
    next score
  }
)

Battle::AI::Handlers::ScoreReplacement.add(:shed_tail_followup,
  proc { |idxBattler, pkmn, score, battle, ai|
    shed_tail = pkmn.moves.find do |m|
      m.is_a?(Pokemon::Move) && ai.safe_function_code(m) == "UserMakeSubstituteSwitchOut"
    end
    next score unless shed_tail

    succeeds = false
    ai.each_foe_battler(ai.user.side) do |b, _i|
      if ai.reserve_status_move_succeeds?(idxBattler, pkmn, b, shed_tail.id)
        succeeds = true
        break
      end
    end
    if succeeds
      score += 20
      PBDebug.log_score_change(20, "#{pkmn.name}: Shed Tail follow-up")
    end
    next score
  }
)

Battle::AI::Handlers::ScoreReplacement.add(:slow_pivot_followup,
  proc { |idxBattler, pkmn, score, battle, ai|
    party = battle.pbParty(idxBattler)
    party_index = party.index(pkmn)
    next score unless party_index

    pre_switch = { idxBattler => party_index }

    ai.each_foe_battler(ai.user.side) do |b, _i|
      voluntary_switch = battle.command_phase || (!b.movedThisRound? && b.turnCount > 0)
      slow_pivot_bonus = ai.reserve_slow_pivot_bonus(
        idxBattler, pkmn, b, pre_switch, voluntary_switch: voluntary_switch
      )
      next if slow_pivot_bonus <= 0

      score += slow_pivot_bonus
      PBDebug.log_score_change(slow_pivot_bonus, "#{pkmn.name} vs #{b.name}: safe slow pivot option")
    end
    next score
  }
)

Battle::AI::Handlers::ScoreReplacement.add(:hazard_clearing,
  proc { |idxBattler, pkmn, score, battle, ai|
    own_side = ai.user.pbOwnSide
    hazard_bonus = ai.side_hazard_clear_bonus(own_side)
    next score if hazard_bonus <= 0

    if battle.pbAbleNonActiveCount(idxBattler & 1) == 0
      hazard_bonus = (hazard_bonus * 0.5).round
    end
    next score if hazard_bonus <= 0

    clear_moves = pkmn.moves.select do |m|
      m.is_a?(Pokemon::Move) && Battle::AI::HAZARD_CLEAR_FUNCTION_CODES.include?(ai.safe_function_code(m))
    end
    next score if clear_moves.empty?

    cached_results = ai.replacement_1v1_results(idxBattler, pkmn)
    next score if !cached_results || cached_results.empty?

    best_bonus = 0
    clear_moves.each do |m|
      move_survives = cached_results.any? do |foe_index, foe_results|
        if m.status_move?
          ai.reserve_status_move_succeeds?(idxBattler, pkmn, battle.battlers[foe_index], m.id)
        else
          ai.replacement_move_survives?(foe_results, m.id)
        end
      end
      next unless move_survives

      bonus = hazard_bonus
      bonus += 3 if !m.status_move?
      if ai.safe_function_code(m) == "LowerTargetEvasion1RemoveSideEffects"
        foe_has_hazards = false
        ai.each_foe_battler(ai.user.side) do |b, _i|
          if ai.side_hazard_clear_bonus(b.pbOwnSide) > 0
            foe_has_hazards = true
            break
          end
        end
        bonus -= 8 if foe_has_hazards
      end
      next if bonus <= best_bonus

      best_bonus = bonus
      PBDebug.log_ai("[hazard_clear] #{pkmn.name} values #{m.name} for hazard removal (+#{bonus})")
    end

    if best_bonus > 0
      score += best_bonus
      PBDebug.log_score_change(best_bonus, "#{pkmn.name}: can clear entry hazards")
    end
    next score
  }
)

Battle::AI::Handlers::ScoreReplacement.add(:wish_healing,
  proc { |idxBattler, pkmn, score, battle, ai|
    position = battle.positions[idxBattler]
    if position.effects[PBEffects::Wish] > 0
      amt = position.effects[PBEffects::WishAmount]
      if pkmn.totalhp - pkmn.hp > amt * 2 / 3
        score += 20 * [pkmn.totalhp - pkmn.hp, amt].min / pkmn.totalhp
      end
    end
    next score
  }
)

Battle::AI::Handlers::ScoreReplacement.add(:perish_song_fading,
  proc { |idxBattler, pkmn, score, battle, ai|
    score += 20 if ai.user.effects[PBEffects::PerishSong] == 1
    next score
  }
)

Battle::AI::Handlers::ScoreReplacement.add(:utility_switch_in,
  proc { |idxBattler, pkmn, score, battle, ai|
    foe_total_boosts = 0
    foe_has_screens = false
    foe_has_status_moves = false
    foe_has_boosted_target = false
    foe_has_physical_target = false

    ai.each_foe_battler(ai.user.side) do |b, _i|
      foe_positive_boosts = ai.total_positive_boosts(b)
      foe_total_boosts += foe_positive_boosts
      foe_has_boosted_target ||= foe_positive_boosts >= 2
      foe_side = b.pbOwnSide
      foe_has_screens = true if foe_side.effects[PBEffects::Reflect] > 0 ||
                                 foe_side.effects[PBEffects::LightScreen] > 0 ||
                                 foe_side.effects[PBEffects::AuroraVeil] > 0
      status_count = 0
      ai.known_foe_moves(b).each { |m| status_count += 1 if m.statusMove? }
      foe_has_status_moves = true if status_count >= 2

      visible_moves = ai.known_foe_moves(b)
      has_physical = visible_moves.any? { |m| m.physicalMove? }
      foe_has_physical_target ||= has_physical && !b.has_active_ability?(:GUTS)
    end

    succeeds_move = proc { |m_id|
      s_val = true
      ai.each_foe_battler(ai.user.side) do |fb, _|
        if !ai.reserve_status_move_succeeds?(idxBattler, pkmn, fb, m_id)
          s_val = false
          break
        end
      end
      s_val
    }

    status_condition_applies = proc { |move|
      s_val = true
      ai.each_foe_battler(ai.user.side) do |fb, _|
        if !ai.reserve_status_condition_applicable?(idxBattler, pkmn, fb, move)
          s_val = false
          break
        end
      end
      s_val
    }

    pkmn.moves.each do |m|
      next unless m.status_move?
      next unless succeeds_move.call(m.id)
      next unless status_condition_applies.call(m)

      case m.function_code
      when "BurnTarget"
        next unless foe_has_physical_target
        score += 12
        PBDebug.log_score_change(12, "Utility: #{m.name} vs physical foe")
        break
      when "ParalyzeTarget", "ParalyzeTargetIfNotTypeImmune"
        bonus = 8
        bonus += 4 if foe_has_boosted_target
        score += bonus
        PBDebug.log_score_change(bonus, "Utility: #{m.name}")
        break
      when "PoisonTarget", "BadPoisonTarget"
        bonus = 8
        bonus += 4 if foe_has_boosted_target
        score += bonus
        PBDebug.log_score_change(bonus, "Utility: #{m.name}")
        break
      when "SleepTargetNextTurn"
        bonus = 5
        bonus += 5 if foe_has_boosted_target
        score += bonus
        PBDebug.log_score_change(bonus, "Utility: #{m.name}")
        break
      end
    end

    # Unaware vs boosted foe
    if foe_total_boosts >= 2 && pkmn.hasAbility?(:UNAWARE)
      bonus = 25 + (foe_total_boosts * 3)
      score += bonus
      PBDebug.log_score_change(bonus, "Utility: Unaware vs +#{foe_total_boosts} boosts")
    end

    # Haze / Clear Smog vs boosted foe
    if foe_total_boosts >= 2
      pkmn.moves.each do |m|
        if ["ResetAllBattlersStatStages", "ResetTargetStatStages"].include?(m.function_code)
          next unless succeeds_move.call(m.id)
          bonus = 20 + (foe_total_boosts * 2)
          score += bonus
          PBDebug.log_score_change(bonus, "Utility: #{m.name} vs +#{foe_total_boosts} boosts")
          break
        end
      end
    end

    # Whirlwind / Roar / Dragon Tail vs boosted foe
    if foe_total_boosts >= 2
      pkmn.moves.each do |m|
        if ["SwitchOutTargetStatusMove", "SwitchOutTargetDamagingMove"].include?(m.function_code)
          next unless succeeds_move.call(m.id)
          bonus = 20 + (foe_total_boosts * 2)
          ai.each_foe_battler(ai.user.side) do |b, _|
            foe_side = b.pbOwnSide
            bonus += 5 if foe_side.effects[PBEffects::StealthRock]
            bonus += 3 * foe_side.effects[PBEffects::Spikes]
            break
          end
          score += bonus
          PBDebug.log_score_change(bonus, "Utility: #{m.name} (phaze) vs +#{foe_total_boosts} boosts")
          break
        end
      end
    end

    # Taunt/Encore vs status-heavy foe
    if foe_has_status_moves
      pkmn.moves.each do |m|
        if m.function_code == "DisableTargetStatusMoves" || m.function_code == "DisableTargetUsingDifferentMove"
          next unless succeeds_move.call(m.id)
          score += 10
          PBDebug.log_score_change(10, "Utility: Taunt vs status-heavy foe")
          break
        end
      end
    end

    # Encore can punish a foe that has already committed turns to boosting
    if foe_has_boosted_target
      pkmn.moves.each do |m|
        next unless m.function_code == "DisableTargetUsingDifferentMove"
        next unless succeeds_move.call(m.id)
        score += 5
        PBDebug.log_score_change(5, "Utility: Encore vs boosted foe")
        break
      end
    end

    # Brick Break vs screens
    if foe_has_screens
      pkmn.moves.each do |m|
        if m.function_code == "RemoveScreens"
          next unless succeeds_move.call(m.id)
          score += 10
          PBDebug.log_score_change(10, "Utility: Brick Break vs screens")
          break
        end
      end
    end

    #start Tailwind
    pkmn.moves.each do |m|
      if m.function_code == "StartUserSideDoubleSpeed"
        next unless succeeds_move.call(m.id)
        score += 10
        PBDebug.log_score_change(10, "Utility: #{m.name} to support the team")
        break
      end
    end

    #start own screen
    pkmn.moves.each do |m|
      if ["StartWeakenDamageAgainstUserSideIfHail", "StartWeakenPhysicalDamageAgainstUserSide", "StartWeakenSpecialDamageAgainstUserSide"].include?(m.function_code)
        next unless succeeds_move.call(m.id)
        score += 20
        PBDebug.log_score_change(20, "Utility: #{m.name} to set up screens")
        break
      end
    end
    next score
  }
)

Battle::AI::Handlers::ScoreReplacement.add(:intimidate_switch_in,
  proc { |idxBattler, pkmn, score, battle, ai|
    next score unless pkmn.hasAbility?(:INTIMIDATE)
    ai.each_foe_battler(ai.user.side) do |b, _i|
      next if b.has_active_ability?(Battle::AI::INTIMIDATE_IMMUNE)
      next if battle.moldBreaker
      next if b.stages[:ATTACK] <= -6
      phys_count = 0
      ai.known_foe_moves(b).each do |m|
        next unless m&.damagingMove?
        phys_count += 1 if m.physicalMove?
      end
      next if phys_count == 0
      phys_ratio = phys_count.to_f / 4
      bonus = (10 * phys_ratio).round
      bonus = (bonus * 0.5).round if b.stages[:ATTACK] < 0
      if bonus > 0
        score += bonus
        PBDebug.log_score_change(bonus, "#{pkmn.name}: Intimidate vs #{b.name} (#{phys_count} phys moves)")
      end
    end
    next score
  }
)
