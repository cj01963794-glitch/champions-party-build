#===============================================================================
# Battle Simulation: Run actual battle phases on deep copies.
#===============================================================================

class Battle::AI
  class SimulationScenario
    attr_reader :pre_switch, :entry_attack, :form_changes

    def initialize(pre_switch: {}, entry_attack: nil, form_changes: {})
      @pre_switch = pre_switch || {}
      @entry_attack = entry_attack
      @form_changes = form_changes || {}
    end

    def self.current; new; end
    def self.switch(pre_switch); new(pre_switch: pre_switch); end

    def self.voluntary_switch(pre_switch, target_index, foe_move_action)
      new(
        pre_switch: pre_switch,
        entry_attack: {
          target_index: target_index,
          foe_move_action: foe_move_action
        }
      )
    end

    def current?
      @pre_switch.empty? && !@entry_attack && @form_changes.empty?
    end

    def cache_key
      [
        @pre_switch.to_a.sort_by { |idx, _party_idx| idx },
        @entry_attack,
        @form_changes.to_a.sort_by { |idx, _mechanic| idx }
      ]
    end

    def with_form_change(idxBattler, mechanic)
      self.class.new(
        pre_switch: @pre_switch,
        entry_attack: @entry_attack,
        form_changes: @form_changes.merge(idxBattler => mechanic)
      )
    end

    def form_change_for(idxBattler)
      @form_changes[idxBattler]
    end
  end

  #=============================================================================
  # SimulationResult: Output from battle simulation.
  #=============================================================================
  class SimulationResult
    attr_accessor :turns, :turn_log
    attr_accessor :user_fainted, :target_fainted
    attr_accessor :user_hp, :target_hp
    attr_accessor :user_initial_hp, :target_initial_hp
    attr_accessor :user_entry_hp, :target_entry_hp
    attr_accessor :user_ko_turn, :target_ko_turn
    attr_accessor :user_got_action, :target_got_action
    attr_accessor :user_succeeded, :target_succeeded
    attr_accessor :terminated_by_switch, :switch_type, :switch_battler_index

    def initialize
      @turns = 0
      @turn_log = []
      @user_fainted = false
      @target_fainted = false
      @user_initial_hp = nil
      @target_initial_hp = nil
      @user_entry_hp = nil
      @target_entry_hp = nil
      @user_ko_turn = nil
      @target_ko_turn = nil
      @user_got_action = false
      @target_got_action = false
      @user_succeeded  = false
      @target_succeeded = false
      @terminated_by_switch = false
      @switch_type = nil
      @switch_battler_index = nil
    end

    def user_wins?;       @target_fainted && !@user_fainted; end
    def target_wins?;     @user_fainted && !@target_fainted; end
    def double_ko?;       @user_fainted && @target_fainted; end
    def user_can_ohko?;   @target_fainted && @target_ko_turn == 1; end
    def target_can_ohko?; @user_fainted && @user_ko_turn == 1; end
  end

  def resolve_sim_action_move(battler, action)
    return nil unless battler

    if action.is_a?(Hash)
      if action[:dynamax]
        max_move_id = action[:move_id]
        base_move_id = action[:base_move_id]
        return nil unless max_move_id && base_move_id

        if battler.respond_to?(:baseMoves) && !battler.baseMoves.empty?
          battler.baseMoves.each_with_index do |base_move, idx|
            next if !base_move || base_move.id != base_move_id
            move = battler.moves[idx] || base_move
            return move
          end
        end

        move = battler.moves.find { |candidate| candidate&.id == base_move_id }
        return move if move
        return battler.moves.find { |candidate| candidate&.id == max_move_id }
      end

      base_id = action[:move_id]
      return nil unless base_id
      move_idx = action[:move_index]
      move = nil
      if move_idx.is_a?(Integer) && move_idx >= 0
        candidate = battler.moves[move_idx]
        move = candidate if candidate&.id == base_id
      end
      if !move
        move_idx = nil
        move = battler.moves.find { |m| m.id == base_id }
      end
      if !move && battler.respond_to?(:baseMoves) && !battler.baseMoves.empty?
        battler.baseMoves.each_with_index do |base_move, idx|
          next if !base_move || base_move.id != base_id
          move = battler.moves[idx] || base_move
          move_idx = idx
          break
        end
      end
      return nil unless move
      move_idx ||= battler.moves.index(move) || 0
      if action[:status_zmove]
        return nil unless move.statusMove? && move.respond_to?(:make_zmove)
        zmove = move.make_zmove(base_id, battler.battle)
        return nil unless zmove&.respond_to?(:status_zmove) && zmove.status_zmove
        zmove.specialUseZMove = true if zmove.respond_to?(:specialUseZMove=)
        zmove.pp = [1, move.pp].min
        zmove.total_pp = 1
        zmove.instance_variable_set(:@_sim_move_index, move_idx)
        return zmove
      end
      return move unless action[:zmove]

      zmove = move.convert_zmove(battler, battler.battle, move_idx, true)
      zmove.instance_variable_set(:@_sim_move_index, move_idx) if zmove
      return zmove
    end

    return nil unless action.is_a?(Symbol)
    move = battler.moves.find { |m| m.id == action }
    return move if move

    action_data = GameData::Move.try_get(action)
    if action_data&.zMove?
      item_data = GameData::Item.try_get(battler.item_id) if battler.respond_to?(:item_id)
      pkmn =
        if battler.respond_to?(:visiblePokemon)
          battler.visiblePokemon
        else
          battler.pokemon
        end
      battler.moves.each_with_index do |base_move, idx|
        next if !base_move
        if item_data && pkmn && base_move.get_compatible_zmove(item_data, pkmn) == action
          zmove = base_move.make_zmove(action, battler.battle)
          zmove.specialUseZMove = true if zmove.respond_to?(:specialUseZMove=)
          zmove.instance_variable_set(:@_sim_move_index, idx)
          return zmove
        end
        zmove = base_move.convert_zmove(battler, battler.battle, idx, true)
        return zmove if zmove&.id == action
      end
      if battler.respond_to?(:baseMoves) && !battler.baseMoves.empty?
        battler.baseMoves.each_with_index do |base_move, idx|
          next if !base_move
          if item_data && pkmn && base_move.get_compatible_zmove(item_data, pkmn) == action
            zmove = base_move.make_zmove(action, battler.battle)
            zmove.specialUseZMove = true if zmove.respond_to?(:specialUseZMove=)
            zmove.instance_variable_set(:@_sim_move_index, idx)
            return zmove
          end
          zmove = base_move.convert_zmove(battler, battler.battle, idx, true)
          return zmove if zmove&.id == action
        end
      end
    end

    if battler.respond_to?(:baseMoves) && !battler.baseMoves.empty?
      battler.baseMoves.each_with_index do |base_move, idx|
        next if !base_move
        next if base_move.id != action
        return battler.moves[idx]
      end
    end

    return nil if !action_data || !action_data.dynamaxMove?
    dynahash = GameData::Move.get_generic_dynamax_moves
    battler.moves.each do |candidate|
      next if !candidate
      next if candidate.get_compatible_dynamax_move(battler, dynahash) != action
      PBDebug.log_ai("[AI SIM] Resolved reverted Dynamax move #{action} to base move #{candidate.id} for #{battler.pbThis}")
      return candidate
    end
    nil
  end

  def sim_action_label(battler, action)
    return "None" if action.nil?
    if action.is_a?(Hash)
      move_id = action[:move_id]
      move_name = GameData::Move.try_get(move_id)&.name || move_id
      return "Z-#{move_name}" if action[:status_zmove]
      return action[:zmove] ? "#{move_name} (Z-Move)" : move_name.to_s
    end
    if action.is_a?(Array) && action[0] == :switch
      party_idx = action[1]
      pkmn = battler ? battler.battle.pbParty(battler.index)[party_idx] : nil
      return "Switch -> #{pkmn ? pkmn.name : party_idx}"
    end
    if action.is_a?(Symbol)
      move = battler&.moves&.find { |m| m&.id == action }
      move_name = move&.name || GameData::Move.try_get(action)&.name || action
      return move_name.to_s
    end
    action.to_s
  end

  def sim_actions_label(battler, actions)
    return "[]" if !actions || actions.empty?
    actions.map { |action| sim_action_label(battler, action) }.join(" -> ")
  end

  def log_simulation_actions(user_index, target_index, user, target, user_actions, target_actions, max_turns, scenario)
    scenario_label = if scenario&.entry_attack
      entry_action = sim_action_label(target, scenario.entry_attack[:foe_move_action])
      "entry=#{entry_action}"
    elsif scenario&.pre_switch && !scenario.pre_switch.empty?
      "entry=None"
    else
      "entry=current"
    end
    PBDebug.log_ai(
      "[AI SIM] Start #{user&.pbThis || user_index} vs #{target&.pbThis || target_index} " \
      "(max #{max_turns} turns, #{scenario_label}); " \
      "#{user&.pbThis || user_index}: #{sim_actions_label(user, user_actions)}; " \
      "#{target&.pbThis || target_index}: #{sim_actions_label(target, target_actions)}"
    )
  end

  def log_simulation_exit(user_index, target_index, user, target, reason, context = {})
    context ||= {}
    detail = context.map { |key, value| "#{key}=#{value}" }.join(", ")
    msg = "[AI SIM] Exit #{user&.pbThis || user_index} vs #{target&.pbThis || target_index}: #{reason}"
    msg += " (#{detail})" if detail.length > 0
    PBDebug.log_ai(msg)
  end

  #-----------------------------------------------------------------------------
  # Simulate a full battle with action sequences.
  #
  # user_index, target_index: battler indices
  # user_actions, target_actions: Arrays of actions, each action is either:
  #   - Symbol (move ID)       → use that move
  #   - [:switch, party_index] → switch to that party member
  # options:
  #   :max_turns (default 10)
  #   :lock_user_first_action - Prevent priority/recovery interception from
  #     replacing the user's explicitly requested action on turn 1.
  #   :lock_user_actions - Prevent interception from replacing any requested
  #     user action in the sequence.
  #   :pre_switch - Hash { battler_index => party_index }
  #     Applies switch-in effects (hazards, Intimidate, weather, etc.)
  #     before the turn loop starts, without giving the opponent an action.
  #     Used for faint replacements and pivot switch-ins.
  #-----------------------------------------------------------------------------
  def simulate_battle(user_index, target_index, user_actions, target_actions, options = {})
    max_turns, scenario, sim = prepare_simulation_battle(options)
    result = initialize_simulation_result(user_index, target_index, sim, scenario, options[:heal_user_full])

    interception = options[:interception] || build_sim_interception_data(
      user_index, target_index, max_turns, sim,
      scenario: scenario,
      preserve_provided_sim: options.key?(:sim) && scenario.current?
    )

    user = sim.battlers[user_index]
    target = sim.battlers[target_index]
    exit_reason = nil
    exit_context = {}
    log_simulation_actions(user_index, target_index, user, target, user_actions, target_actions, max_turns, scenario)
    sim_turn_base = sim.instance_variable_get(:@turnCount).to_i

    (1..max_turns).each do |turn|
      exit_reason, exit_context = simulation_pre_turn_exit(user, target, turn)
      break if exit_reason

      sim_turn_count = begin_sim_turn(sim, sim_turn_base, turn, result)
      user_action, user_move, user_locked = resolve_sim_turn_action(user, user_actions, turn)
      unless user_move
        exit_reason = :no_user_move
        exit_context = { turn: turn, action: user_action.inspect, moves: user.moves.compact.map(&:id).inspect }
        break
      end
      _target_action, target_move, target_locked = resolve_sim_turn_action(target, target_actions, turn)
      stop_after_turn = sim_damaging_zmove_action?(user_move)
      user_interception_locked = user_locked ||
                                 options[:lock_user_actions] ||
                                 (turn == 1 && options[:lock_user_first_action])

      user_move = apply_sim_interceptions(
        user, target, user_move, target_move, interception[:user_priority_moves],
        interception[:user_recovery_move], interception[:user_max_foe_dmg],
        user_interception_locked, turn, turn > 1 || options[:sim]
      )
      stop_after_turn ||= sim_damaging_zmove_action?(user_move)

      if target_move
        target_locked ||= turn == 1 && sim_turn_base == @battle.turnCount &&
                          tera_foe_opening?(user_index, target_index, user)
        target_move = apply_sim_interceptions(
          target, user, target_move, user_move, interception[:target_priority_moves],
          interception[:target_recovery_move], interception[:target_max_foe_dmg],
          target_locked, turn, true
        )
        stop_after_turn ||= sim_damaging_zmove_action?(target_move)
      end
      assign_sim_choices(sim, user_index, target_index, user, target, user_move, target_move)

      outcome = run_sim_turn_phases(sim, user_index, target_index, sim_turn_count)
      user, target = outcome[:user], outcome[:target]
      record_sim_turn_result(result, outcome, user_index, target_index, turn)
      exit_reason, exit_context = simulation_post_turn_exit(
        result, sim, outcome[:switch_event], stop_after_turn, turn, user_index, target_index
      )
      break if exit_reason
    end
    exit_reason ||= :max_turns
    exit_context = { turns: result.turns } if exit_reason == :max_turns
    log_simulation_exit(user_index, target_index, user, target, exit_reason, exit_context)
    finalize_simulation_result(result, user, target)
  end

  def prepare_simulation_battle(options)
    max_turns = options.fetch(:max_turns, 10)
    scenario = options[:scenario]
    scenario = scenario_from_switch_options(options[:pre_switch], options) if !scenario && options[:pre_switch]
    scenario ||= SimulationScenario.current
    [max_turns, scenario, options[:sim] || prepare_sim_for_scenario(scenario)]
  end

  def initialize_simulation_result(user_index, target_index, sim, scenario, heal_user_full)
    result = SimulationResult.new
    result.user_initial_hp = scenario_initial_hp(user_index, scenario)
    result.target_initial_hp = scenario_initial_hp(target_index, scenario)
    result.user_entry_hp = sim.battlers[user_index]&.hp
    result.target_entry_hp = sim.battlers[target_index]&.hp
    if heal_user_full
      sim_user = sim.battlers[user_index]
      sim_user.hp = sim_user.totalhp
      result.user_entry_hp = sim_user.hp
    end
    result
  end

  def simulation_pre_turn_exit(user, target, turn)
    return nil unless user.fainted? || target.fainted?
    [:fainted, { turn: turn, user: user.fainted?, target: target.fainted? }]
  end

  def begin_sim_turn(sim, sim_turn_base, turn, result)
    result.turns = turn
    sim_turn_count = sim_turn_base + turn - 1
    sim.instance_variable_set(:@turnCount, sim_turn_count)
    sim_turn_count
  end

  def resolve_sim_turn_action(battler, actions, turn)
    action_idx = actions.empty? ? nil : [turn - 1, actions.length - 1].min
    action = action_idx ? actions[action_idx] : nil
    move = resolve_sim_action_move(battler, action)
    multi_turn = battler.usingMultiTurnAttack?
    move = locked_sim_action_move(battler, move) if multi_turn
    locked = multi_turn || battler.effects[PBEffects::ChoiceBand]
    [action, move, locked]
  end

  def sim_damaging_zmove_action?(move)
    move.respond_to?(:zMove?) && move.zMove? && move.damagingMove?
  end

  def tera_foe_opening?(user_index, target_index, sim_user)
    return false unless @user && @user.index == user_index
    return false unless sim_user&.pokemon&.personalID == @user.battler.pokemon&.personalID
    !tera_foe_actions(@battlers[target_index]).nil?
  end

  def apply_sim_interceptions(actor, foe, move, foe_move, priority_moves, recovery_move, max_foe_dmg, locked, turn, allow_recovery)
    priority_intercepted = false
    if !locked && priority_interception_needed?(actor, foe, move, foe_move)
      priority_moves.each do |pm|
        next unless pm[:dmg] >= foe.hp
        pri_move = resolve_sim_action_move(actor, pm[:action])
        next unless pri_move
        PBDebug.log_ai("[AI SIM] KO priority interception proc: #{actor.pbThis} swaps #{move.name} -> #{pri_move.name} against #{foe.pbThis} on turn #{turn} (predicted #{pm[:dmg]} >= #{foe.hp} HP)")
        move = pri_move
        priority_intercepted = true
        break
      end
    end
    if !locked && !priority_intercepted && recovery_move && allow_recovery &&
       max_foe_dmg < actor.totalhp * 0.4 && actor.hp < actor.totalhp * 0.6
      rec_move = resolve_sim_action_move(actor, recovery_move)
      if rec_move && actor.pbCanChooseMove?(rec_move, false, false)
        PBDebug.log_ai("[AI SIM] Recovery interception: #{actor.pbThis} swaps #{move.name} -> #{rec_move.name} on turn #{turn} (foe dmg #{max_foe_dmg} < 40% totalhp, HP #{actor.hp}/#{actor.totalhp} < 60%)")
        move = rec_move
      end
    end
    move
  end

  def sim_choice_move_index(battler, move)
    stored_index = move&.instance_variable_get(:@_sim_move_index)
    if stored_index.is_a?(Integer) && stored_index >= 0 && stored_index < battler.moves.length
      return stored_index
    end
    battler.moves.index(move) ||
      battler.moves.index { |candidate| candidate&.id == move&.id } ||
      0
  end

  def assign_sim_choices(sim, user_index, target_index, user, target, user_move, target_move)
    PBDebug.log_ai("AI SIM: User #{user.pbThis} locked into a multi-turn attack") if $DEBUG && user.usingMultiTurnAttack?
    sim.choices[user_index] = [:UseMove, sim_choice_move_index(user, user_move), user_move, target_index, 0]
    PBDebug.log_ai("AI SIM: Target #{target.pbThis} locked into a multi-turn attack") if $DEBUG && target.usingMultiTurnAttack?
    sim.choices[target_index] = target_move ? [:UseMove, sim_choice_move_index(target, target_move), target_move, user_index, 0] : [:None]
  end

  def run_sim_turn_phases(sim, user_index, target_index, sim_turn_count)
    user, target = sim.battlers[user_index], sim.battlers[target_index]
    outcome = { user_hp_before: user.hp, target_hp_before: target.hp }
    switch_event = catch(SIM_SWITCH_TRIGGERED) do
      sim.pbAttackPhase
      false
    end
    user, target = sim.battlers[user_index], sim.battlers[target_index]
    user_action_turn = user.instance_variable_get(:@_sim_action_turn)
    target_action_turn = target.instance_variable_get(:@_sim_action_turn)
    user_succeeded_on_action = user.instance_variable_get(:@_sim_action_succeeded)
    target_succeeded_on_action = target.instance_variable_get(:@_sim_action_succeeded)
    outcome[:user_acted] = (user_action_turn == sim_turn_count) || (user.lastRoundMoved == sim_turn_count)
    outcome[:target_acted] = (target_action_turn == sim_turn_count) || (target.lastRoundMoved == sim_turn_count)
    outcome[:user_failed] = outcome[:user_acted] && !user_succeeded_on_action.nil? ? !user_succeeded_on_action : user.lastMoveFailed
    outcome[:target_failed] = outcome[:target_acted] && !target_succeeded_on_action.nil? ? !target_succeeded_on_action : target.lastMoveFailed
    unless switch_event
      switch_event = catch(SIM_SWITCH_TRIGGERED) do
        sim.pbEndOfRoundPhase
        false
      end
      user, target = sim.battlers[user_index], sim.battlers[target_index]
    end
    outcome.merge(user: user, target: target, switch_event: switch_event)
  end

  def record_sim_turn_result(result, outcome, user_index, target_index, turn)
    switch_event = outcome[:switch_event]
    if switch_event && switch_event[:reason] == :live_switch
      if switch_event[:battler_index] == user_index
        outcome[:user_acted] = true
        outcome[:user_failed] = false
      elsif switch_event[:battler_index] == target_index
        outcome[:target_acted] = true
        outcome[:target_failed] = false
      end
    end
    result.user_got_action ||= outcome[:user_acted]
    result.target_got_action ||= outcome[:target_acted]
    result.user_succeeded ||= outcome[:user_acted] && !outcome[:user_failed]
    result.target_succeeded ||= outcome[:target_acted] && !outcome[:target_failed]
    result.turn_log << {
      turn: turn,
      user_hp_before: outcome[:user_hp_before],
      target_hp_before: outcome[:target_hp_before],
      user_hp_after: outcome[:user].hp,
      target_hp_after: outcome[:target].hp,
      user_acted: outcome[:user_acted],
      user_succeeded: outcome[:user_acted] && !outcome[:user_failed],
      target_acted: outcome[:target_acted],
      target_succeeded: outcome[:target_acted] && !outcome[:target_failed]
    }
  end

  def simulation_post_turn_exit(result, sim, switch_event, stop_after_turn, turn, user_index, target_index)
    if switch_event
      idx = switch_event[:battler_index]
      if idx == user_index || idx == target_index
        result.terminated_by_switch = true
        result.switch_type = switch_event[:reason]
        result.switch_battler_index = idx
        return [:switch_event, { turn: turn, type: switch_event[:reason], battler: idx }]
      end
    end
    return [:battle_decision, { turn: turn, decision: sim.decision }] if sim.decision > 0
    return [:stop_after_turn, { turn: turn }] if stop_after_turn
    nil
  end

  def finalize_simulation_result(result, user, target)
    result.user_fainted = user.fainted?
    result.target_fainted = target.fainted?
    result.user_hp = user.hp
    result.target_hp = target.hp
    result.user_ko_turn = result.turns if user.fainted?
    result.target_ko_turn = result.turns if target.fainted?
    result
  end

  def build_sim_interception_data(user_index, target_index, max_turns, sim, options = {})
    data = {
      user_priority_moves: [],
      target_priority_moves: [],
      user_recovery_move: nil,
      target_recovery_move: nil,
      user_max_foe_dmg: 0,
      target_max_foe_dmg: 0
    }
    return data if max_turns <= 1

    scenario = options[:scenario]
    unless options[:preserve_provided_sim]
      user_dmg = damage_profile(user_index, target_index, scenario || SimulationScenario.current)
      target_dmg = damage_profile(target_index, user_index, scenario || SimulationScenario.current)
      add_interception_damage(data[:user_priority_moves], user_dmg, data, :target_max_foe_dmg)
      add_interception_damage(data[:target_priority_moves], target_dmg, data, :user_max_foe_dmg)
    end

    recovery_codes = [
      "HealUserHalfOfTotalHP",
      "HealUserHalfOfTotalHPLoseFlyingTypeThisTurn",
      "HealUserDependingOnWeather",
    ]
    data[:user_recovery_move] = first_recovery_move_id(sim.battlers[user_index], recovery_codes)
    data[:target_recovery_move] = first_recovery_move_id(sim.battlers[target_index], recovery_codes)
    data
  end

  def add_interception_damage(priority_moves, dmg_data, data, max_key)
    dmg_data&.each_value do |entry|
      data[max_key] = entry[:dmg] if entry[:dmg] > data[max_key]
      next unless entry[:move].priority > 0
      priority_moves << {
        action: entry[:action],
        dmg: entry[:dmg],
        pri: entry[:move].priority,
        zmove: entry[:zmove]
      }
    end
  end

  def priority_interception_needed?(user, target, user_move, target_move)
    return false unless user && target && user_move && target_move

    user_priority = move_priority_for_sim(user_move, user)
    target_priority = move_priority_for_sim(target_move, target)
    return true if user_priority < target_priority
    return false if user_priority > target_priority

    user_speed = user.pbSpeed
    target_speed = target.pbSpeed
    return true if user_speed == target_speed

    trick_room = user.battle.field.effects[PBEffects::TrickRoom] > 0
    trick_room ? user_speed > target_speed : user_speed < target_speed
  rescue StandardError
    true
  end

  def move_priority_for_sim(move, battler)
    return move.pbPriority(battler) if move.respond_to?(:pbPriority)
    return move.priority if move.respond_to?(:priority)
    0
  rescue StandardError
    0
  end

  def first_recovery_move_id(battler, recovery_codes)
    return nil unless battler
    battler.moves.each do |m|
      next unless m && recovery_codes.include?(m.function_code)
      next unless battler.pbCanChooseMove?(m, false, false)
      return m.id
    end
    nil
  end

  def locked_sim_action_move(battler, fallback_move = nil)
    return fallback_move unless battler&.usingMultiTurnAttack?
    current_move = battler.respond_to?(:currentMove) ? battler.currentMove : nil
    resolve_sim_action_move(battler, current_move) || fallback_move
  end

  #-----------------------------------------------------------------------------
  # Apply assumed form changes (Mega/Dynamax/Tera) to a sim battler after
  # switch-in. Only one mechanic applies per battler (mutually exclusive).
  #-----------------------------------------------------------------------------
  def apply_sim_form_changes(sim, battler_index, mechanic = nil)
    battler = sim.battlers[battler_index]
    return unless battler && battler.pokemon && !battler.fainted?
    # Mega Evolution
    if (mechanic.nil? || mechanic == :mega) && sim.pbCanMegaEvolve?(battler_index)
      old_ability = battler.ability_id
      battler.pokemon.makeMega
      battler.form_update(true)
      trigger_simulated_form_ability_change(battler, old_ability)
      return
    end
    # Dynamax
    if (mechanic.nil? || mechanic == :dynamax) && sim.pbCanDynamax?(battler_index)
      battler.effects[PBEffects::Dynamax] = Settings::DYNAMAX_TURNS
      battler.makeDynamax
      battler.display_dynamax_moves
      return
    end
    # Tera for Terapagos / Ogerpon (form-changing tera species)
    if ((mechanic == :tera) || (mechanic.nil? && [:TERAPAGOS, :OGERPON].include?(battler.species))) &&
       sim.pbCanTerastallize?(battler_index)
      old_ability = battler.ability_id
      battler.pokemon.terastallized = true
      battler.form_update(true)
      battler.pbUpdate(true)
      if battler.respond_to?(:tera_form?) && battler.tera_form?
        trigger_simulated_form_ability_change(battler, old_ability)
      end
    end
  end

  def scenario_from_switch_options(pre_switch, options = {})
    scenario = if options[:voluntary_switch] && options[:foe_move_id]
      SimulationScenario.voluntary_switch(
        pre_switch,
        options[:target_index],
        options[:foe_move_id]
      )
    else
      SimulationScenario.switch(pre_switch)
    end
    form_change = options[:form_change]
    if form_change
      idx = form_change.is_a?(Hash) ? form_change[:index] : form_change[0]
      mechanic = form_change.is_a?(Hash) ? form_change[:mechanic] : form_change[1]
      scenario = scenario.with_form_change(idx, mechanic) if idx && mechanic
    end
    scenario
  end

  def scenario_initial_hp(battler_index, scenario)
    party_idx = scenario&.pre_switch&.[](battler_index)
    if party_idx
      return @battle.pbParty(battler_index)[party_idx]&.hp
    end
    @battle.battlers[battler_index]&.hp
  end

  def prepare_sim_for_scenario(scenario)
    sim = create_battle_copy
    apply_scenario_to_sim(sim, scenario || SimulationScenario.current)
    sim
  end

  def apply_scenario_to_sim(sim, scenario)
    return sim if !scenario || scenario.current?
    switching_idx = scenario.pre_switch.keys.first
    foe_mega_indices = switching_idx ? predicted_scoring_copy_megas(switching_idx, sim)
      .select { |b| b.opposes?(switching_idx) }.map(&:index) : []
    foe_mega_indices.each do |idx|
      sim.pbRegisterMegaEvolution(idx) if sim.pbCanMegaEvolve?(idx)
    end
    scenario.pre_switch.each do |battler_idx, party_idx|
      entry_attack = scenario.entry_attack
      if entry_attack && entry_attack[:foe_move_action]
        target_idx = entry_attack[:target_index]
        user_idx = battler_idx
        atk = sim.battlers[target_idx]
        foe_move = resolve_sim_action_move(atk, entry_attack[:foe_move_action])
        if foe_move
          sim.choices[target_idx] = [:UseMove, atk.moves.index(foe_move) || 0, foe_move, user_idx, 0]
        else
          sim.choices[target_idx] = [:None]
        end
        sim.choices[user_idx] = [:SwitchOut, party_idx, nil, -1]

        sim.instance_variable_set(:@turnCount, @battle.turnCount)
        switch_event = catch(SIM_SWITCH_TRIGGERED) do
          sim.pbAttackPhase
          sim.pbEndOfRoundPhase
          sim.instance_variable_set(:@turnCount, sim.turnCount + 1)
          false
        end
        if switch_event
          sim.instance_variable_set(:@_sim_switch_event, switch_event)
          PBDebug.log_ai("[AI SIM] Voluntary switch follow-up interrupted by #{switch_event[:reason]} switch for battler #{switch_event[:battler_index]}")
        end
      else
        switch_event = catch(SIM_SWITCH_TRIGGERED) do
          sim.pbRecallAndReplace(battler_idx, party_idx)
          sim.pbOnBattlerEnteringBattle(battler_idx)
          sim.instance_variable_set(:@turnCount, sim.turnCount + 1) if @battle.endOfRound
          false
        end
        if switch_event
          sim.instance_variable_set(:@_sim_switch_event, switch_event)
          PBDebug.log_ai("[AI SIM] Switch-in setup interrupted by #{switch_event[:reason]} switch for battler #{switch_event[:battler_index]}")
        end
      end

      apply_sim_form_changes(sim, battler_idx, scenario.form_change_for(battler_idx))
    end
    foe_mega_indices.each do |idx|
      sim.pbMegaEvolve(idx) if sim.pbRegisteredMegaEvolution?(idx)
    end
    sim
  end

end
