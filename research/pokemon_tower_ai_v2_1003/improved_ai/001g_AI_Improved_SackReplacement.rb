#===============================================================================
# Sack Replacement Gate
#===============================================================================

class Battle::AI
  def pbChooseSackReplacement
    idxParty, score = choose_sack_replacement_pokemon(@user.index)
    return false if idxParty < 0
    return false unless @battle.pbRegisterSwitch(@user.index, idxParty)
    @_last_replacement_score = score
    PBDebug.log_ai("=> sack switch with #{@battle.pbParty(@user.index)[idxParty].name} (score #{score})")
    register_fresh_switch_score(@user.index, idxParty, score: 999)
    true
  end

  def choose_sack_replacement_pokemon(idxBattler)
    return [-1, 0] unless sack_replacement_gate_active?(idxBattler)
    candidates = sack_replacement_cached_candidates(idxBattler)
    return [-1, 0] if !candidates || candidates.empty?

    party = @battle.pbParty(idxBattler)
    median_foe_speed = sack_seen_foe_speed_median(idxBattler)
    return [-1, 0] if !median_foe_speed
    candidates.sort_by { |_i, score| score }.first(3).each do |idxParty, score|
      pkmn = party[idxParty]
      next if !pkmn
      traits = 0
      traits += 1 if sack_effective_speed(pkmn) < median_foe_speed && !sack_has_priority_move?(pkmn)
      traits += 1 if pkmn.hp < pkmn.totalhp * 0.4
      traits += 1 if !party_back_three?(party, idxParty)
      next if traits < 2
      PBDebug.log_ai("   => sack gate chose #{pkmn.name}: #{traits}/3 traits, replacement score #{score}")
      return [idxParty, score]
    end
    [-1, 0]
  end

  def sack_replacement_cached_candidates(idxBattler)
    party = @battle.pbParty(idxBattler)
    reserves = []
    party.each_with_index do |_pkmn, i|
      next if !@battle.pbCanSwitchIn?(idxBattler, i)
      next if sack_ally_already_switching_to?(idxBattler, i)
      reserves.push([i, 100])
      break if @trainer.has_skill_flag?("UsePokemonInOrder") && reserves.length > 0
    end
    return nil if reserves.empty?
    battler = @battle.battlers[idxBattler]
    key = [
      idxBattler, false, @battle.command_phase,
      battler.pokemon&.personalID, battler.pokemonIndex,
      reserves.map { |reserve| reserve[0] }
    ]
    @_replacement_score_cache && @_replacement_score_cache[key]&.map(&:dup)
  end

  def sack_ally_already_switching_to?(idxBattler, idxParty)
    @battle.allSameSideBattlers(idxBattler).any? do |b|
      @battle.choices[b.index][0] == :SwitchOut &&
        @battle.choices[b.index][1] == idxParty
    end
  end

  def sack_replacement_gate_active?(idxBattler)
    battler = @battle.battlers[idxBattler]
    party = @battle.pbParty(idxBattler)
    if battler&.fainted?
      PBDebug.log_ai("[sack_gate] inactive: current switch is a faint replacement")
      return false
    end
    fresh = (@_fresh_switch_scores || {})[idxBattler]
    if fresh && battler && battler.turnCount == 0 &&
       battler.pokemon&.personalID == fresh[:personal_id] &&
       current_foe_personal_ids(idxBattler) == fresh[:foe_ids]
      PBDebug.log_ai("[sack_gate] inactive: #{battler.name} is a fresh replacement and the foe did not change")
      return false
    end
    if !battler || !party_back_three?(party, battler.pokemonIndex)
      PBDebug.log_ai("[sack_gate] inactive: current is not back-3 ace")
      return false
    end
    foes = @battle.allOtherSideBattlers(idxBattler)
    if foes.empty?
      PBDebug.log_ai("[sack_gate] inactive: no foes")
      return false
    end
    median_foe_speed = sack_seen_foe_speed_median(idxBattler)
    if !median_foe_speed
      PBDebug.log_ai("[sack_gate] inactive: no seen non-fainted foes")
      return false
    end
    if battler.pbSpeed <= median_foe_speed
      PBDebug.log_ai("[sack_gate] inactive: #{battler.name} speed #{battler.pbSpeed} <= median foe speed #{median_foe_speed.round(1)}")
      return false
    end
    active = foes.any? { |foe| sack_foe_must_attack?(foe) }
    PBDebug.log_ai("[sack_gate] #{active ? 'foe must attack' : 'foe doesnt need to attack'}: #{battler.name} speed #{battler.pbSpeed}, median foe speed #{median_foe_speed.round(1)}")
    active
  end

  def sack_seen_foe_speed_median(idxBattler)
    active_indexes = @battle.allOtherSideBattlers(idxBattler).map(&:pokemonIndex)
    speeds = []
    @battle.pbOpposingParty(idxBattler).each_with_index do |pkmn, i|
      next if !pkmn || pkmn.fainted?
      next unless active_indexes.include?(i) || @battle.ai_fog_acted?(pkmn)
      speeds << sack_effective_speed(pkmn)
    end
    return nil if speeds.empty?
    sack_median(speeds)
  end

  def sack_median(values)
    sorted = values.sort
    mid = sorted.length / 2
    return sorted[mid] if sorted.length.odd?
    (sorted[mid - 1] + sorted[mid]) / 2.0
  end

  def sack_foe_must_attack?(foe)
    return true if foe.effects[PBEffects::ChoiceBand]
    return true if foe.effects[PBEffects::Taunt] > 0
    dmg_data = damage_moves(@user, foe)
    dmg_data && dmg_data.values.any? { |data| data[:dmg].to_i > foe.hp * 0.7 }
  end

  def sack_effective_speed(pkmn)
    speed = pkmn.speed
    speed /= (Settings::MECHANICS_GENERATION >= 7) ? 2 : 4 if pkmn.status == :PARALYSIS
    [speed, 1].max
  end

  def sack_has_priority_move?(pkmn)
    Array(pkmn.moves).any? { |m| m && GameData::Move.get(m.id).priority > 0 }
  end

  def party_back_three?(party, idxParty)
    idxParty && idxParty >= [party.length - 3, 0].max
  end
end
