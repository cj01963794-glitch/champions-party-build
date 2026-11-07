#===============================================================================
# [AI_Improved_Tera.rb] - Tera Scoring System
# Split from 001_AI_Improved_Core.rb for separation of concerns.
#===============================================================================

class Battle::AI
  # override: only one tera available per team.
  alias wants_to_terastallize_original wants_to_terastallize?
  def wants_to_terastallize?
      return true if @user.isSpecies?(:TERAPAGOS) || @user.isSpecies?(:OGERPON)
      return @user.get_total_tera_score >= 0
  end

  def store_tera_foe_actions(foe, opening_move, followup_move)
    foe_id = foe&.battler&.pokemon&.personalID
    return unless foe_id
    opening = simulation_action_for_move_data(opening_move)
    followup = simulation_action_for_move_data(followup_move)
    (@_tera_foe_actions ||= {})[foe_id] = opening ? [opening, followup] : []
    PBDebug.log_ai(
      "[Tera]   Foe action plan: " \
      "#{opening_move&.dig(:move)&.name || 'None'} -> " \
      "#{followup_move&.dig(:move)&.name || 'None'}"
    )
  end

  def tera_foe_actions(foe)
    return nil unless @_tera_foe_actions && @user && foe
    return nil unless @battle.pbRegisteredTerastallize?(@user.index) || @user.tera?
    @_tera_foe_actions[foe.battler.pokemon&.personalID]
  end

  def tera_foe_damage_entry(foe, target, profile, turn)
    return nil unless @user && target.respond_to?(:battler)
    return nil unless target.index == @user.index
    return nil unless target.battler.pokemon&.personalID == @user.battler.pokemon&.personalID
    damage_entry_for_action(profile, tera_foe_actions(foe)&.[](turn))
  end

  # Forced/wild Tera paths bypass wants_to_terastallize?.
  def ensure_registered_tera_foe_actions
    return unless @user && @battle.pbRegisteredTerastallize?(@user.index)
    return if @user.tera?

    each_foe_battler(@user.side) do |foe, _i|
      foe_id = foe.battler.pokemon&.personalID
      next if foe_id && @_tera_foe_actions&.key?(foe_id)
      @user.compute_tera_score_vs_foe(foe)
    end
  end

  #---------------------------------------------------------------------------
  # Evaluates a 1v1 simulated matchup between two battlers
  # returns { user_wins: bool, u_turns: int, f_turns: int }
  #---------------------------------------------------------------------------
  def one_v_one_result(user_c, foe_c, user_outspeeds)
    u_hp = user_c[:hp]
    u_dmg = user_c[:dmg] || 0
    f_hp = foe_c[:hp]
    f_dmg = foe_c[:dmg] || 0

    u_turns = projected_turns_to_ko(f_hp, u_dmg, user_c[:opening_dmg])
    f_turns = projected_turns_to_ko(u_hp, f_dmg, foe_c[:opening_dmg])

    if u_turns < f_turns
      user_wins = true
    elsif f_turns < u_turns
      user_wins = false
    else
      user_wins = user_outspeeds
    end

    { user_wins: user_wins, u_turns: u_turns, f_turns: f_turns }
  end

  def projected_turns_to_ko(hp, repeat_damage, opening_damage = nil)
    opening_damage = repeat_damage if opening_damage.nil?
    return 1 if opening_damage > 0 && opening_damage >= hp

    remaining_hp = hp - [opening_damage, 0].max
    return 999 if repeat_damage <= 0
    1 + (remaining_hp.to_f / repeat_damage).ceil
  end
end

class Battle::AI::AIBattler
  #=============================================================================
  # Scenario-based Tera scoring using predicted damage and 1v1 simulation
  #=============================================================================
  def get_total_tera_score
    tera_type = @battler.tera_type
    type_name = GameData::Type.get(tera_type).name
    PBDebug.log_ai("#{self.name} is considering Terastallizing into the #{type_name}-type...")
    @ai.instance_variable_set(:@_computing_tera_score, true)
    begin
      score = -10  # tera is a limited resource, needs justification
      PBDebug.log_ai("[Tera] Starting score: #{score} (base cost)")
      @ai.each_foe_battler(@side) do |b, _i|
        foe_score = compute_tera_score_vs_foe(b)
        if foe_score == :auto_tera
          PBDebug.log_ai("[Tera] Auto-tera condition met")
          return 0
        end
        PBDebug.log_ai("[Tera] vs #{b.name}: #{foe_score > 0 ? '+' : ''}#{foe_score}")
        score += foe_score
      end
      context = get_tera_context_bonus(tera_type)
      PBDebug.log_ai("[Tera] Context bonus: #{context > 0 ? '+' : ''}#{context}") if context != 0
      score += context
      PBDebug.log_ai("[Tera] Final score: #{score}")
      return score
    ensure
      @ai.instance_variable_set(:@_computing_tera_score, false)
    end
  end

  #---------------------------------------------------------------------------
  # Per-foe scenario scoring
  #---------------------------------------------------------------------------
  def compute_tera_score_vs_foe(foe)
    # --- Gather damage data WITHOUT tera ---
    user_dmg_no_tera = @ai.damage_moves(self, foe)
    foe_dmg_no_tera  = @ai.damage_moves(foe, self)

    best_user_no_tera = user_dmg_no_tera.values.max_by { |md| md[:dmg] }
    best_foe_no_tera  = @ai._select_best_damage_move(foe_dmg_no_tera, foe, self)

    u_dmg_no  = best_user_no_tera ? best_user_no_tera[:dmg] : 0
    f_dmg_no  = best_foe_no_tera  ? best_foe_no_tera[:dmg]  : 0
    foe_opening_action = @ai.simulation_action_for_move_data(best_foe_no_tera)

    # --- Temporarily simulate tera on self to get "with tera" damage ---
    prev_tera = @battler.pokemon.instance_variable_get(:@terastallized)
    prev_form = @battler.form
    begin
      @battler.pokemon.terastallized = true
      @battler.form = @battler.pokemon.form if @battler.form != @battler.pokemon.form
      @battler.pbUpdate(true)

      user_dmg_with_tera = @ai.damage_moves(self, foe)
      foe_dmg_with_tera  = @ai.damage_moves(foe, self)

      neutral_auto_tera_move = user_dmg_with_tera.values.any? do |tera_entry|
        move = tera_entry[:move]
        type = move.pbCalcType(@battler)
        !Effectiveness.resistant?(move.pbCalcTypeMod(type, @battler, foe.battler)) &&
          (@battler.typeTeraBoosted?(type) || move.id == :TERABLAST)
      end

      foe_tera_entry = @ai.damage_entry_for_action(foe_dmg_with_tera, foe_opening_action)
      if foe_tera_entry
        foe_tera_move = foe_tera_entry[:move]
        foe_tera_type = foe_tera_move.pbCalcType(foe.battler)
        foe_type_mod_with_tera = foe_tera_move.pbCalcTypeMod(
          foe_tera_type, foe.battler, @battler
        )
      end

      priority_tera_ohko = user_dmg_with_tera.values.any? do |tera_entry|
        no_tera_entry = user_dmg_no_tera[tera_entry[:key]]
        next false unless no_tera_entry && no_tera_entry[:dmg] < foe.hp
        next false unless tera_entry[:dmg] >= foe.hp
        @ai._move_priority(tera_entry[:move], @battler) > 0
      end
    ensure
      @battler.pokemon.terastallized = prev_tera
      @battler.form = prev_form
      @battler.pbUpdate(true)
    end

    best_user_with_tera = user_dmg_with_tera.values.max_by { |md| md[:dmg] }
    u_dmg_tera = best_user_with_tera ? best_user_with_tera[:dmg] : 0

    # The foe commits its pre-Tera choice on turn 1, then adapts to the revealed
    # Tera type. A Choice lock keeps it on the opening move instead.
    foe_opening_with_tera = @ai.damage_entry_for_action(foe_dmg_with_tera, foe_opening_action)
    # Existing move locks were already filtered by pbCanChooseMove?.
    new_choice_lock = !foe.effects[PBEffects::ChoiceBand] &&
                      (foe.has_active_item?([:CHOICEBAND, :CHOICESPECS, :CHOICESCARF]) ||
                       foe.has_active_ability?(:GORILLATACTICS))
    best_foe_with_tera = if new_choice_lock
      foe_opening_with_tera
    else
      repeatable = foe_dmg_with_tera.reject do |_key, data|
        @ai.first_turn_only_damage_move?(data[:move])
      end
      @ai._select_best_damage_move(repeatable, foe, self)
    end
    f_opening_dmg_tera = foe_opening_with_tera&.dig(:dmg) || 0
    f_dmg_tera = best_foe_with_tera&.dig(:dmg) || 0
    @ai.store_tera_foe_actions(foe, best_foe_no_tera, best_foe_with_tera)

    # --- Speed / priority ---
    user_speed = self.rough_stat(:SPEED)
    foe_speed  = foe.rough_stat(:SPEED)
    best_user_move_priority = best_user_no_tera ? best_user_no_tera[:move].priority : 0

    if priority_tera_ohko
      PBDebug.log_ai("[Tera]   Tera enables a priority OHKO -> auto tera")
      return :auto_tera
    end
    if foe_type_mod_with_tera && !Effectiveness.super_effective?(foe_type_mod_with_tera) &&
       neutral_auto_tera_move
      PBDebug.log_ai("[Tera]   Tera neutralizes the expected foe move and boosts an unresisted move -> auto tera")
      return :auto_tera
    end

    best_user_tera_priority = best_user_with_tera ? best_user_with_tera[:move].priority : 0
    user_priority = [best_user_move_priority, best_user_tera_priority].max
    foe_priority  = best_foe_no_tera ? best_foe_no_tera[:move].priority : 0

    if user_priority > foe_priority
      user_outspeeds = true
    elsif foe_priority > user_priority
      user_outspeeds = false
    else
      user_outspeeds = self.faster_than?(foe) || (!foe.faster_than?(self) && user_speed >= foe_speed)
    end

    PBDebug.log_ai("[Tera]   u_dmg=#{u_dmg_no}/#{u_dmg_tera} " \
                   "f_dmg=#{f_dmg_no}/#{f_opening_dmg_tera}->#{f_dmg_tera} " \
                   "spd=#{user_outspeeds ? 'user' : 'foe'} foe_hp=#{foe.hp} user_hp=#{self.hp}")

    # --- 1v1 simulation: compare with and without tera ---
    user_c = { battler: self, index: self.index, target: foe, target_index: foe.index,
               dmg: u_dmg_no, move: best_user_no_tera&.dig(:move), hp: self.hp }
    foe_c  = { battler: foe, index: foe.index, target: self, target_index: self.index,
               dmg: f_dmg_no, move: best_foe_no_tera&.dig(:move), hp: foe.hp }
    return simulate_1v1_tera_value(
      user_c, foe_c, user_outspeeds,
      user_c_tera: user_c.merge(dmg: u_dmg_tera, move: best_user_with_tera&.dig(:move)),
      foe_c_tera:  foe_c.merge(
        opening_dmg: f_opening_dmg_tera,
        dmg: f_dmg_tera,
        move: best_foe_with_tera&.dig(:move)
      )
    )
  end

  #---------------------------------------------------------------------------
  # Turns-to-KO comparison: with and without tera
  #---------------------------------------------------------------------------
  def simulate_1v1_tera_value(user_c, foe_c, user_outspeeds,
                              user_c_tera:, foe_c_tera:)
    r_no   = @ai.one_v_one_result(user_c, foe_c, user_outspeeds)
    r_tera = @ai.one_v_one_result(user_c_tera, foe_c_tera, user_outspeeds)

    win_no   = r_no[:user_wins]
    win_tera = r_tera[:user_wins]

    PBDebug.log_ai("[Tera]   1v1: u_turns=#{r_no[:u_turns]}/#{r_tera[:u_turns]} f_turns=#{r_no[:f_turns]}/#{r_tera[:f_turns]} " \
                   "win_no=#{win_no} win_tera=#{win_tera}")

    # Tera flips losing → winning
    if !win_no && win_tera
      PBDebug.log_ai("[Tera]   Scenario 3a: tera flips losing matchup → winning")
      return 60
    end

    # Tera makes winning → losing
    if win_no && !win_tera
      PBDebug.log_ai("[Tera]   Scenario 3b: tera makes winning → losing")
      return -40
    end

    # Wins both
    if win_no && win_tera
      turns_saved = r_no[:u_turns] - r_tera[:u_turns]
      survival_gained = r_tera[:f_turns] - r_no[:f_turns]
      bonus = 0
      if turns_saved > 0 || survival_gained > 0
        bonus = [[turns_saved * 10 + survival_gained * 5, 30].min, 10].max
        PBDebug.log_ai("[Tera]   Scenario 3c: wins both, saves #{turns_saved} turns / gains #{survival_gained} survival → +#{bonus}")
      else
        bonus = -5
        PBDebug.log_ai("[Tera]   Scenario 3d: wins both, no improvement → #{bonus}")
      end
      return bonus
    end

    # Loses both
    survival_gained = r_tera[:f_turns] - r_no[:f_turns]
    if survival_gained > 0
      bonus = [[survival_gained * 5, 15].min, 10].max
      PBDebug.log_ai("[Tera]   Scenario 3e: loses both, survives longer with tera → +#{bonus}")
      return bonus
    else
      PBDebug.log_ai("[Tera]   Scenario 3f: loses both, no improvement → -10")
      return -10
    end
  end

  #---------------------------------------------------------------------------
  # Non-damage context bonuses for tera type
  #---------------------------------------------------------------------------
  def get_tera_context_bonus(tera_type)
    bonus = 0
    case tera_type
    when :FLYING
      # Immune to Spikes, Toxic Spikes, Sticky Web
      if @battler.pbOwnSide.effects[PBEffects::Spikes] > 0 ||
         @battler.pbOwnSide.effects[PBEffects::ToxicSpikes] > 0 ||
         @battler.pbOwnSide.effects[PBEffects::StickyWeb]
        bonus += 10
      end
    when :POISON, :STEEL
      # Immune to poison/toxic
      if @battler.status == :NONE
        @ai.each_foe_battler(@side) do |b, _|
          b.battler.eachMove do |m|
            if [:TOXIC, :POISONPOWDER, :TOXICSPIKES, :BANEFULBUNKER].include?(m.id) ||
               m.function_code == "PoisonTarget" || m.function_code == "BadlyPoisonTarget"
              bonus += 5
              break
            end
          end
        end
      end
    when :FIRE
      # Immune to burn
      if @battler.status == :NONE
        @ai.each_foe_battler(@side) do |b, _|
          b.battler.eachMove do |m|
            if [:WILLOWISP, :SCALD, :STEAMERUPTION].include?(m.id) ||
               m.function_code == "BurnTarget"
              bonus += 5
              break
            end
          end
        end
      end
    when :ELECTRIC
      # Immune to paralysis
      if @battler.status == :NONE
        @ai.each_foe_battler(@side) do |b, _|
          b.battler.eachMove do |m|
            if [:THUNDERWAVE, :STUNSPORE, :GLARE, :NUZZLE].include?(m.id) ||
               m.function_code == "ParalyzeTarget"
              bonus += 5
              break
            end
          end
        end
      end
    when :GHOST
      # Escape trapping
      if @battler.effects[PBEffects::Trapping] > 0 ||
         @battler.effects[PBEffects::MeanLook] > 0
        bonus += 15
      end
    when :DARK
      # Prankster immunity
      @ai.each_foe_battler(@side) do |b, _|
        if b.has_active_ability?(:PRANKSTER)
          bonus += 10
          break
        end
      end
    when :GRASS
      # Leech Seed / powder immunity
      if @battler.effects[PBEffects::LeechSeed] >= 0
        bonus += 10
      end
      @ai.each_foe_battler(@side) do |b, _|
        b.battler.eachMove do |m|
          if [:LEECHSEED, :SLEEPPOWDER, :STUNSPORE, :POISONPOWDER, :SPORE].include?(m.id) ||
             m.flags&.include?("Powder")
            bonus += 5
            break
          end
        end
      end
    end
    bonus
  end
end
