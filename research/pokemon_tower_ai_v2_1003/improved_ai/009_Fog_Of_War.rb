class Battle
  AI_FOG_PLACEHOLDER_ITEM = :AIFOGDUMMY
  # These items stay visible from the start even while the default fog hides
  # everything else.
  AI_FOG_VISIBLE_ITEMS = [
    :LIGHTCLAY,
    :LEFTOVERS,
    :BLACKSLUDGE,
    :LOADEDDICE,
    :MAXMUSHROOM,
    :TERAPIECE
  ].freeze

  alias fog_of_war_initialize initialize

  def initialize(scene, p1, p2, player, opponent)
    fog_of_war_initialize(scene, p1, p2, player, opponent)
    @ai_item_fog_of_war = false
    @player_item_hidden = Array.new(@party1.length) do |i|
      pkmn = @party1[i]
      next false if !pkmn || !pkmn.item_id
      ai_fog_item_hidden?(pkmn)
    end
    @ai_fog_hidden_move_index = {}
    @party1.each_with_index do |pkmn, i|
      next if !pkmn
      PBDebug.log_ai("[fog_of_war:init] party index #{i} pokemon=#{pkmn.name} item=#{pkmn.item_id.inspect} hidden=#{@player_item_hidden[i]}")
    end
  end

  def ai_item_fog_of_war?
    return @ai_item_fog_of_war || false
  end

  def set_ai_item_fog_of_war(value)
    @ai_item_fog_of_war = value
  end

  def player_item_hidden?(party_index)
    return false if !party_index || party_index < 0 || party_index >= @player_item_hidden.length
    return @player_item_hidden[party_index]
  end

  def reveal_player_item(party_index, reason = nil)
    return if !party_index || party_index < 0 || party_index >= @player_item_hidden.length
    log_msg = "[fog_of_war:reveal] party index #{party_index} hidden_before=#{@player_item_hidden[party_index]}"
    log_msg += " reason=#{reason}" if reason
    PBDebug.log_ai(log_msg)
    @player_item_hidden[party_index] = false
  end

  def player_item_hidden_for_battler?(battler)
    return false if !battler
    return false if !battler.pbOwnedByPlayer?
    return player_item_hidden?(battler.pokemonIndex)
  end

  def ai_fog_item_hidden?(pkmn)
    item_data = GameData::Item.try_get(pkmn.item_id)
    return false if !item_data
    return false if item_data.has_flag?("MegaStone")
    if !item_data.has_flag?("ZCrystal") &&
       item_data.unlosable?(pkmn.species, pkmn.ability_id)
      return false
    end
    return false if AI_FOG_VISIBLE_ITEMS.include?(item_data.id)
    return true
  end

  def ai_fog_acted_ids
    @_foe_acted_ids ||= {}
    return @_foe_acted_ids
  end

  def ai_fog_pokemon_from(obj)
    return nil if !obj
    return obj.pokemon if obj.respond_to?(:pokemon)
    return obj if obj.respond_to?(:personalID)
    return nil
  end

  def mark_ai_fog_acted(battler)
    pkmn = ai_fog_pokemon_from(battler)
    return if !battler || !battler.pbOwnedByPlayer? || !pkmn
    ai_fog_acted_ids[pkmn.personalID] = true
  end

  def ai_fog_acted?(battler_or_pkmn)
    pkmn = ai_fog_pokemon_from(battler_or_pkmn)
    return false if !pkmn
    return ai_fog_acted_ids[pkmn.personalID] || false
  end

  def ai_fog_hidden_move_index_for(battler)
    pkmn = ai_fog_pokemon_from(battler)
    return nil if !pkmn
    key = pkmn.personalID
    hidden_index = @ai_fog_hidden_move_index[key]
    return nil if hidden_index == :none
    return hidden_index if !hidden_index.nil?
    all_moves = battler.moves.compact
    foe_types = battler.pbTypes(true)
    protected_moves = []
    foe_types.each do |type|
      best = all_moves.select { |move| move.type == type && move.damagingMove? }
                      .max_by { |move| move.power }
      protected_moves << best if best
    end
    remaining_indexes = []
    battler.moves.each_with_index do |move, idx|
      next if !move
      next if protected_moves.include?(move)
      remaining_indexes << idx
    end
    if remaining_indexes.length > 0 && pbRandom(100) < 50
      hidden_index = remaining_indexes[pbRandom(remaining_indexes.length)]
      @ai_fog_hidden_move_index[key] = hidden_index
      return hidden_index
    end
    @ai_fog_hidden_move_index[key] = :none
    return nil
  end

  def ai_fog_known_moves_for(battler)
    all_moves = battler.moves.compact
    return all_moves if ai_fog_acted?(battler)
    hidden_index = ai_fog_hidden_move_index_for(battler)
    return all_moves if hidden_index.nil?
    hidden_move = battler.moves[hidden_index]
    return all_moves if !hidden_move
    return all_moves - [hidden_move]
  end

  def ai_fog_check_choice_scarf_reveals
    return if ai_item_fog_of_war?
    return if !@priority || @priority.empty?
    @priority.each do |entry|
      battler = entry[0]
      next if !battler || battler.fainted?
      next if !battler.pbOwnedByPlayer?
      next if !player_item_hidden_for_battler?(battler)
      next if battler.item_id != :CHOICESCARF
      next if @choices[battler.index][0] != :UseMove
      bracket = @priority.select do |other|
        next false if !other[0] || other[0].fainted?
        next false if ![:UseMove].include?(@choices[other[0].index][0])
        other[5] == entry[5] && other[4] == entry[4]
      end
      next if bracket.length <= 1
      actual_index = bracket.index(entry)
      scarf_speed = entry[1]
      hidden_before = @player_item_hidden[battler.pokemonIndex]
      original_item_id = battler.item_id
      begin
        @player_item_hidden[battler.pokemonIndex] = false
        battler.item = nil
        scarfless_speed = battler.pbSpeed
      ensure
        battler.item = original_item_id
        @player_item_hidden[battler.pokemonIndex] = hidden_before
      end
      PBDebug.log_ai("[fog_of_war:priority] #{battler.name} speed with scarf=#{scarf_speed} speed without scarf=#{scarfless_speed}")
      next if scarf_speed == scarfless_speed
      alt_order = bracket.sort do |a, b|
        speed_a = (a.equal?(entry)) ? scarfless_speed : a[1]
        speed_b = (b.equal?(entry)) ? scarfless_speed : b[1]
        if @priorityTrickRoom
          (speed_a == speed_b) ? b[6] <=> a[6] : speed_a <=> speed_b
        else
          (speed_a == speed_b) ? b[6] <=> a[6] : speed_b <=> speed_a
        end
      end
      reveal_player_item(battler.pokemonIndex, "PriorityCalc(ChoiceScarf)") if alt_order.index(entry) != actual_index
    end
  end

  alias fog_of_war_pbCalculatePriority pbCalculatePriority
  def pbCalculatePriority(fullCalc = false, indexArray = nil)
    ret = fog_of_war_pbCalculatePriority(fullCalc, indexArray)
    ai_fog_check_choice_scarf_reveals
    return ret
  end

end

Battle::AI::Handlers::ItemRanking.add(:AIFOGDUMMY,
  proc { |item, score, battler, ai|
    next 6
  }
)

class Battle::AI
  def with_item_fog_of_war
    old_value = @battle.ai_item_fog_of_war?
    @battle.set_ai_item_fog_of_war(true)
    return yield
  ensure
    @battle.set_ai_item_fog_of_war(old_value)
  end

  alias fog_of_war_pbDefaultChooseEnemyCommand pbDefaultChooseEnemyCommand
  def pbDefaultChooseEnemyCommand(idxBattler)
    return with_item_fog_of_war { fog_of_war_pbDefaultChooseEnemyCommand(idxBattler) }
  end

  alias fog_of_war_pbDefaultChooseNewEnemy pbDefaultChooseNewEnemy
  def pbDefaultChooseNewEnemy(idxBattler)
    return with_item_fog_of_war { fog_of_war_pbDefaultChooseNewEnemy(idxBattler) }
  end
end

class Battle::Battler
  alias fog_of_war_pbProcessTurn pbProcessTurn
  def pbProcessTurn(choice, tryFlee = true)
    ret = fog_of_war_pbProcessTurn(choice, tryFlee)
    if choice[0] == :UseMove && pbOwnedByPlayer?
      @battle.mark_ai_fog_acted(self)
    end
    return ret
  end

  alias fog_of_war_item_id item_id
  def item_id
    if @battle.ai_item_fog_of_war? && @battle.player_item_hidden_for_battler?(self)
      return nil if !fog_of_war_item_id
      return Battle::AI_FOG_PLACEHOLDER_ITEM
    end
    return fog_of_war_item_id
  end

  alias fog_of_war_item item
  def item
    if @battle.ai_item_fog_of_war? && @battle.player_item_hidden_for_battler?(self)
      return nil if !fog_of_war_item
      return GameData::Item.try_get(Battle::AI_FOG_PLACEHOLDER_ITEM)
    end
    return fog_of_war_item
  end

  alias fog_of_war_hasActiveItem? hasActiveItem?
  def hasActiveItem?(check_item, ignore_fainted = false)
    if @battle.ai_item_fog_of_war? && @battle.player_item_hidden_for_battler?(self)
      return false
    end
    return fog_of_war_hasActiveItem?(check_item, ignore_fainted)
  end
end

class Battle::Move
  alias fog_of_war_pbInflictHPDamage pbInflictHPDamage
  def pbInflictHPDamage(target)
    item_before_damage = target&.item_id
    fog_of_war_pbInflictHPDamage(target)
    return if !target
    return if target.damageState.substitute
    return if target.damageState.hpLost <= 0
    return if !specialMove?
    return if !target.pbOwnedByPlayer?
    return if item_before_damage != :ASSAULTVEST
    target.battle.reveal_player_item(target.pokemonIndex, "InflictHPDamage(AssaultVest)")
  end
end

class Battle::AI::AIBattler
  def hidden_item_from_ai?
    return false if !@ai.user
    return false if !battler.pbOwnedByPlayer?
    return false if !opposes?(@ai.user)
    return @ai.battle.player_item_hidden?(battler.pokemonIndex)
  end

  def item_id
    if hidden_item_from_ai?
      return nil if !battler.item_id
      return Battle::AI_FOG_PLACEHOLDER_ITEM
    end
    return battler.item_id
  end

  def item
    if hidden_item_from_ai?
      return nil if !battler.item
      return GameData::Item.try_get(Battle::AI_FOG_PLACEHOLDER_ITEM)
    end
    return battler.item
  end

  def has_active_item?(item)
    if hidden_item_from_ai?
      return false
    end
    return battler.hasActiveItem?(item)
  end

  def rough_stat(stat)
    return battler.pbSpeed if stat == :SPEED && @ai.trainer.high_skill? && !hidden_item_from_ai?
    stage_mul = Battle::Battler::STAT_STAGE_MULTIPLIERS
    stage_div = Battle::Battler::STAT_STAGE_DIVISORS
    if [:ACCURACY, :EVASION].include?(stat)
      stage_mul = Battle::Battler::ACC_EVA_STAGE_MULTIPLIERS
      stage_div = Battle::Battler::ACC_EVA_STAGE_DIVISORS
    end
    stage = battler.stages[stat] + Battle::Battler::STAT_STAGE_MAXIMUM
    value = base_stat(stat)
    return (value.to_f * stage_mul[stage] / stage_div[stage]).floor
  end
end

class Battle::AI
  def known_foe_moves(foe_ai_battler)
    visible_moves = @battle.ai_fog_known_moves_for(foe_ai_battler)
    return visible_moves
  end
end

module Battle::ItemEffects
  class << self
    alias fog_of_war_trigger trigger
    alias fog_of_war_triggerOnMissingTarget triggerOnMissingTarget
    alias fog_of_war_triggerAccuracyCalcFromUser triggerAccuracyCalcFromUser
    alias fog_of_war_triggerAccuracyCalcFromTarget triggerAccuracyCalcFromTarget
    alias fog_of_war_triggerDamageCalcFromUser triggerDamageCalcFromUser
    alias fog_of_war_triggerDamageCalcFromTarget triggerDamageCalcFromTarget
    alias fog_of_war_triggerPriorityBracketUse triggerPriorityBracketUse
    alias fog_of_war_triggerOnBeingHit triggerOnBeingHit
    alias fog_of_war_triggerAfterMoveUseFromTarget triggerAfterMoveUseFromTarget
    alias fog_of_war_triggerAfterMoveUseFromUser triggerAfterMoveUseFromUser
    alias fog_of_war_triggerEndOfRoundHealing triggerEndOfRoundHealing
    alias fog_of_war_triggerEndOfRoundEffect triggerEndOfRoundEffect
    alias fog_of_war_triggerOnSwitchIn triggerOnSwitchIn
  end

  # These are trigger-based reveals for non-consumables and other effects that
  # are already public once the battle message/animation resolves.
  FOG_OF_WAR_REVEALABLE_TRIGGERS = [
    WeightCalc,
    HPHeal,
    OnStatLoss,
    StatusCure,
    PriorityBracketChange,
    PriorityBracketUse,
    OnMissingTarget,
    AccuracyCalcFromUser,
    AccuracyCalcFromTarget,
    DamageCalcFromUser,
    DamageCalcFromTarget,
    CriticalCalcFromUser,
    CriticalCalcFromTarget,
    OnBeingHit,
    OnBeingHitPositiveBerry,
    AfterMoveUseFromTarget,
    AfterMoveUseFromUser,
    OnEndOfUsingMove,
    OnEndOfUsingMoveStatRestore,
    WeatherExtender,
    TerrainExtender,
    TerrainStatBoost,
    EndOfRoundHealing,
    EndOfRoundEffect,
    CertainSwitching,
    TrappingByTarget,
    OnSwitchIn,
    OnIntimidated,
  ].freeze

  def self.trigger(hash, *args, ret: false)
    new_ret = fog_of_war_trigger(hash, *args, ret: ret)
    if FOG_OF_WAR_REVEALABLE_TRIGGERS.include?(hash) &&
       fog_of_war_generic_trigger_changed?(hash, ret, new_ret)
      fog_of_war_reveal_item(hash, args)
    end
    return (!new_ret.nil?) ? new_ret : ret
  end

  def self.triggerOnMissingTarget(item, user, target, move, hit_num, battle)
    old_user = fog_of_war_battler_snapshot(user)
    fog_of_war_triggerOnMissingTarget(item, user, target, move, hit_num, battle)
    if fog_of_war_battler_changed?(old_user, fog_of_war_battler_snapshot(user))
      fog_of_war_reveal_item(OnMissingTarget, [item, user, target, move, hit_num, battle])
    end
  end

  def self.triggerAccuracyCalcFromUser(item, mods, user, target, move, type)
    old_mods = mods.dup
    fog_of_war_triggerAccuracyCalcFromUser(item, mods, user, target, move, type)
    if mods != old_mods
      fog_of_war_reveal_item(AccuracyCalcFromUser, [item, mods, user, target, move, type])
    end
  end

  def self.triggerAccuracyCalcFromTarget(item, mods, user, target, move, type)
    old_mods = mods.dup
    fog_of_war_triggerAccuracyCalcFromTarget(item, mods, user, target, move, type)
    if mods != old_mods
      fog_of_war_reveal_item(AccuracyCalcFromTarget, [item, mods, user, target, move, type])
    end
  end

  def self.triggerDamageCalcFromUser(item, user, target, move, mults, power, type)
    old_mults = mults.dup
    fog_of_war_triggerDamageCalcFromUser(item, user, target, move, mults, power, type)
    if mults != old_mults
      fog_of_war_reveal_item(DamageCalcFromUser, [item, user, target, move, mults, power, type])
    end
  end

  def self.triggerDamageCalcFromTarget(item, user, target, move, mults, power, type)
    old_mults = mults.dup
    fog_of_war_triggerDamageCalcFromTarget(item, user, target, move, mults, power, type)
    if mults != old_mults
      fog_of_war_reveal_item(DamageCalcFromTarget, [item, user, target, move, mults, power, type])
    end
  end

  def self.triggerPriorityBracketUse(item, battler, battle)
    fog_of_war_triggerPriorityBracketUse(item, battler, battle)
    fog_of_war_reveal_item(PriorityBracketUse, [item, battler, battle])
  end

  def self.triggerOnBeingHit(item, user, target, move, battle)
    old_user = fog_of_war_battler_snapshot(user)
    old_target = fog_of_war_battler_snapshot(target)
    fog_of_war_triggerOnBeingHit(item, user, target, move, battle)
    if fog_of_war_battler_changed?(old_user, fog_of_war_battler_snapshot(user)) ||
       fog_of_war_battler_changed?(old_target, fog_of_war_battler_snapshot(target))
      fog_of_war_reveal_item(OnBeingHit, [item, user, target, move, battle])
    end
  end

  def self.triggerAfterMoveUseFromTarget(item, battler, user, move, switched_battlers, battle)
    old_battler = fog_of_war_battler_snapshot(battler)
    old_user = fog_of_war_battler_snapshot(user)
    old_switched = switched_battlers.dup
    fog_of_war_triggerAfterMoveUseFromTarget(item, battler, user, move, switched_battlers, battle)
    if fog_of_war_battler_changed?(old_battler, fog_of_war_battler_snapshot(battler)) ||
       fog_of_war_battler_changed?(old_user, fog_of_war_battler_snapshot(user)) ||
       switched_battlers != old_switched
      fog_of_war_reveal_item(AfterMoveUseFromTarget, [item, battler, user, move, switched_battlers, battle])
    end
  end

  def self.triggerAfterMoveUseFromUser(item, user, targets, move, num_hits, battle)
    old_user = fog_of_war_battler_snapshot(user)
    fog_of_war_triggerAfterMoveUseFromUser(item, user, targets, move, num_hits, battle)
    if fog_of_war_battler_changed?(old_user, fog_of_war_battler_snapshot(user))
      fog_of_war_reveal_item(AfterMoveUseFromUser, [item, user, targets, move, num_hits, battle])
    end
  end

  def self.triggerEndOfRoundHealing(item, battler, battle)
    old_hp = battler&.hp
    old_item = battler&.item_id
    fog_of_war_triggerEndOfRoundHealing(item, battler, battle)
    if battler && (battler.hp != old_hp || battler.item_id != old_item)
      fog_of_war_reveal_item(EndOfRoundHealing, [item, battler, battle])
    end
  end

  def self.triggerEndOfRoundEffect(item, battler, battle)
    old_hp = battler&.hp
    old_status = battler&.status
    old_status_count = battler&.statusCount
    old_item = battler&.item_id
    fog_of_war_triggerEndOfRoundEffect(item, battler, battle)
    if battler &&
       (battler.hp != old_hp ||
        battler.status != old_status ||
        battler.statusCount != old_status_count ||
        battler.item_id != old_item)
      fog_of_war_reveal_item(EndOfRoundEffect, [item, battler, battle])
    end
  end

  def self.triggerOnSwitchIn(item, battler, battle)
    old_battler = fog_of_war_battler_snapshot(battler)
    fog_of_war_triggerOnSwitchIn(item, battler, battle)
    if item == :AIRBALLOON ||
       fog_of_war_battler_changed?(old_battler, fog_of_war_battler_snapshot(battler))
      fog_of_war_reveal_item(OnSwitchIn, [item, battler, battle])
    end
  end

  def self.fog_of_war_generic_trigger_changed?(hash, ret, new_ret)
    effective_ret = (!new_ret.nil?) ? new_ret : ret
    case hash
    when SpeedCalc, WeightCalc, PriorityBracketChange, CriticalCalcFromUser,
         CriticalCalcFromTarget, WeatherExtender, TerrainExtender
      return effective_ret != ret
    when HPHeal, OnStatLoss, StatusCure, TerrainStatBoost,
         OnBeingHitPositiveBerry, OnEndOfUsingMove, OnEndOfUsingMoveStatRestore,
         CertainSwitching, OnIntimidated, CertainEscapeFromBattle
      return effective_ret != false
    end
    return true
  end

  def self.fog_of_war_battler_snapshot(battler)
    return nil if !battler
    stages = {}
    GameData::Stat.each_battle { |s| stages[s.id] = battler.stages[s.id] }
    return {
      pokemon_index: battler.pokemonIndex,
      personal_id: battler.pokemon&.personalID,
      hp: battler.hp,
      status: battler.status,
      status_count: battler.statusCount,
      item_id: battler.item_id,
      stages: stages,
      move_pp: battler.moves.map { |move| move&.pp },
      effects: {
        confusion: battler.effects[PBEffects::Confusion],
        attract: battler.effects[PBEffects::Attract],
        taunt: battler.effects[PBEffects::Taunt],
        encore: battler.effects[PBEffects::Encore],
        encore_move: battler.effects[PBEffects::EncoreMove],
        torment: battler.effects[PBEffects::Torment],
        disable: battler.effects[PBEffects::Disable],
        heal_block: battler.effects[PBEffects::HealBlock]
      }
    }
  end

  def self.fog_of_war_battler_changed?(old_snapshot, new_snapshot)
    return old_snapshot != new_snapshot
  end

  def self.fog_of_war_reveal_item(hash, args)
    item = GameData::Item.try_get(args[0])&.id
    return if !item || !hash[item]
    battler = fog_of_war_holder_from_trigger(hash, args)
    battle = args.find { |arg| arg.is_a?(Battle) } || battler&.battle
    return if !battler.is_a?(Battle::Battler)
    return if !battle || battle.ai_item_fog_of_war? || !battler.pbOwnedByPlayer?
    battle.reveal_player_item(battler.pokemonIndex, fog_of_war_trigger_name(hash))
  end

  def self.fog_of_war_trigger_name(hash)
    case hash
    when SpeedCalc then "SpeedCalc"
    when WeightCalc then "WeightCalc"
    when HPHeal then "HPHeal"
    when OnStatLoss then "OnStatLoss"
    when StatusCure then "StatusCure"
    when PriorityBracketChange then "PriorityBracketChange"
    when PriorityBracketUse then "PriorityBracketUse"
    when OnMissingTarget then "OnMissingTarget"
    when AccuracyCalcFromUser then "AccuracyCalcFromUser"
    when AccuracyCalcFromTarget then "AccuracyCalcFromTarget"
    when DamageCalcFromUser then "DamageCalcFromUser"
    when DamageCalcFromTarget then "DamageCalcFromTarget"
    when CriticalCalcFromUser then "CriticalCalcFromUser"
    when CriticalCalcFromTarget then "CriticalCalcFromTarget"
    when OnBeingHit then "OnBeingHit"
    when OnBeingHitPositiveBerry then "OnBeingHitPositiveBerry"
    when AfterMoveUseFromTarget then "AfterMoveUseFromTarget"
    when AfterMoveUseFromUser then "AfterMoveUseFromUser"
    when OnEndOfUsingMove then "OnEndOfUsingMove"
    when OnEndOfUsingMoveStatRestore then "OnEndOfUsingMoveStatRestore"
    when WeatherExtender then "WeatherExtender"
    when TerrainExtender then "TerrainExtender"
    when TerrainStatBoost then "TerrainStatBoost"
    when EndOfRoundHealing then "EndOfRoundHealing"
    when EndOfRoundEffect then "EndOfRoundEffect"
    when CertainSwitching then "CertainSwitching"
    when TrappingByTarget then "TrappingByTarget"
    when OnSwitchIn then "OnSwitchIn"
    when OnIntimidated then "OnIntimidated"
    when CertainEscapeFromBattle then "CertainEscapeFromBattle"
    else hash.class.name
    end
  end

  def self.fog_of_war_holder_from_trigger(hash, args)
    case hash
    when SpeedCalc, WeightCalc, HPHeal, OnStatLoss, StatusCure,
         PriorityBracketChange, PriorityBracketUse, OnBeingHitPositiveBerry,
         AfterMoveUseFromTarget, AfterMoveUseFromUser, OnEndOfUsingMove,
         OnEndOfUsingMoveStatRestore, TerrainStatBoost, EndOfRoundHealing, EndOfRoundEffect,
         CertainSwitching, OnSwitchIn, OnIntimidated, CertainEscapeFromBattle
      return args[1]
    when AccuracyCalcFromUser
      return args[2]
    when AccuracyCalcFromTarget
      return args[3]
    when WeatherExtender, TerrainExtender
      return args[3]
    when DamageCalcFromTarget, CriticalCalcFromTarget, OnBeingHit, TrappingByTarget
      return args[2]
    when DamageCalcFromUser, CriticalCalcFromUser, OnMissingTarget
      return args[1]
    end
    return args.find { |arg| arg.is_a?(Battle::Battler) }
  end
end
