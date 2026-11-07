#===============================================================================
# PP balance
#===============================================================================

module PokemonChampionsPPRules
  MAX_TOTAL_PP = 20

  BASE_5_PROTECT_MOVES = [
    :PROTECT,
    :DETECT,
    :SPIKYSHIELD,
    :KINGSSHIELD,
    :BANEFULBUNKER,
    :OBSTRUCT,
    :SILKTRAP,
    :BURNINGBULWARK
  ].freeze

  BASE_12_PROTECT_EXCEPTIONS = [
    :ENDURE,
    :QUICKGUARD,
    :WIDEGUARD,
    :CRAFTYSHIELD,
    :MATBLOCK
  ].freeze

  def self.effective_base_pp(move_id, raw_pp)
    return 5 if BASE_5_PROTECT_MOVES.include?(move_id)
    return 12 if BASE_12_PROTECT_EXCEPTIONS.include?(move_id)
    return raw_pp if raw_pp <= 0
    return [raw_pp, MAX_TOTAL_PP].min
  end

  def self.total_pp_with_pp_max(base_pp, ppup)
    return base_pp if base_pp <= 0
    max_bonus = case base_pp
                when 0..5   then 3
                when 6..10  then 2
                when 11..15 then 1
                else 0
                end
    return [base_pp + (max_bonus * ppup.to_i / 3), MAX_TOTAL_PP].min
  end
end

module GameData
  class Move
    def total_pp
      return PokemonChampionsPPRules.effective_base_pp(@id, @total_pp)
    end
  end
end

class Pokemon::Move
  def pp
    @pp = @pp.clamp(0, total_pp)
    return @pp
  end

  def total_pp
    base_pp = GameData::Move.get(@id).total_pp
    return PokemonChampionsPPRules.total_pp_with_pp_max(base_pp, @ppup)
  end
  alias totalpp total_pp
end

#===============================================================================
# Salt Cure
#===============================================================================
class Battle
  # redefine gen 9 pack plugin override
  def pbEOREffectDamage(priority)
    paldea_pbEOREffectDamage(priority)
    priority.each do |battler|
      next if battler.effects[PBEffects::Splinters] == 0 || !battler.takesIndirectDamage?
      pbCommonAnimation("Splinters", battler)
      battlerTypes = battler.pbTypes(true)
      splinterType = battler.effects[PBEffects::SplintersType] || :QMARKS
      effectiveness = [1, Effectiveness.calculate(splinterType, *battlerTypes)].max
      damage = ((((2.0 * battler.level / 5) + 2).floor * 25 * battler.attack / battler.defense).floor / 50).floor + 2
      damage *= effectiveness.to_f / Effectiveness::NORMAL_EFFECTIVE
      battler.pbTakeEffectDamage(damage) { |hp_lost|
        pbDisplay(_INTL("\\j[{1},은,는] 떠다니는 돌에 의해 데미지를 받았다!", battler.pbThis))
      }
    end
    priority.each do |battler|
      next if !battler.effects[PBEffects::SaltCure] || !battler.takesIndirectDamage?
      pbCommonAnimation("SaltCure", battler)
      # change salt cure damage
      fraction = (battler.pbHasType?(:STEEL) || battler.pbHasType?(:WATER)) ? 8 : 16
      battler.pbTakeEffectDamage(battler.totalhp / fraction) { |hp_lost|
        pbDisplay(_INTL("\\j[{1},은,는] 소금에 절여지고 있다!", battler.pbThis))
      }
    end
  end
end

module BattlerPokemonChampionsFix
  # cap to 3 turns of sleep
  def pbSleepDuration(duration = -1)
    duration = 2 + @battle.pbRandom(2) if duration <= 0
    duration = (duration / 2).floor if hasActiveAbility?(:EARLYBIRD)
    return duration
  end

  # cap to 3 turns of freeze
  def pbFreeze(msg = nil)
    pbInflictStatus(:FROZEN, 3, msg)
  end

  def pbTryUseMove(choice, move, specialUsage, skipAccuracyCheck)
    # Check whether it's possible for self to use the given move
    # NOTE: Encore has already changed the move being used, no need to have a
    #       check for it here.
    if !pbCanChooseMove?(move, false, true, specialUsage)
      @lastMoveFailed = true
      return false
    end
    # Check whether it's possible for self to do anything at all
    if @effects[PBEffects::SkyDrop] >= 0   # Intentionally no message here
      PBDebug.log("[Move failed] #{pbThis} can't use #{move.name} because of being Sky Dropped")
      return false
    end
    if @effects[PBEffects::HyperBeam] > 0   # Intentionally before Truant
      PBDebug.log("[Move failed] #{pbThis} is recharging after using #{move.name}")
      @battle.pbDisplay(_INTL("\\j[{1},은,는] 휴식이 필요하다!", pbThis))
      @effects[PBEffects::Truant] = !@effects[PBEffects::Truant] if hasActiveAbility?(:TRUANT)
      return false
    end
    if choice[1] == -2   # Battle Palace
      PBDebug.log("[Move failed] #{pbThis} can't act in the Battle Palace somehow")
      @battle.pbDisplay(_INTL("\\j[{1},은,는] 싸우기 힘들어 보인다!", pbThis))
      return false
    end
    # Skip checking all applied effects that could make self fail doing something
    return true if skipAccuracyCheck
    # Check status problems and continue their effects/cure them
    case @status
    when :SLEEP
      self.statusCount -= 1
      if @statusCount <= 0
        pbCureStatus
      else
        pbContinueStatus
        if !move.usableWhenAsleep?   # Snore/Sleep Talk
          PBDebug.log("[Move failed] #{pbThis} is asleep")
          @lastMoveFailed = true
          return false
        end
      end
    when :FROZEN
      self.statusCount -= 1
      if !move.thawsUser?
        if @battle.pbRandom(100) < 25 || @statusCount <= 0
          pbCureStatus
        else
          pbContinueStatus
          PBDebug.log("[Move failed] #{pbThis} is frozen")
          @lastMoveFailed = true
          return false
        end
      end
    end
    # Obedience check
    return false if !pbObedienceCheck?(choice)
    # Truant
    if hasActiveAbility?(:TRUANT)
      @effects[PBEffects::Truant] = !@effects[PBEffects::Truant]
      if !@effects[PBEffects::Truant]   # True means loafing, but was just inverted
        @battle.pbShowAbilitySplash(self)
        @battle.pbDisplay(_INTL("\\j[{1},은,는] 고개를 저었다!", pbThis))
        @lastMoveFailed = true
        @battle.pbHideAbilitySplash(self)
        PBDebug.log("[Move failed] #{pbThis} can't act because of #{abilityName}")
        return false
      end
    end
    # Flinching
    if @effects[PBEffects::Flinch]
      @battle.pbDisplay(_INTL("\\j[{1},은,는] 풀이 죽어 움직일 수 없다!", pbThis))
      PBDebug.log("[Move failed] #{pbThis} flinched")
      if abilityActive?
        Battle::AbilityEffects.triggerOnFlinch(self.ability, self, @battle)
      end
      @lastMoveFailed = true
      return false
    end
    # Confusion
    if @effects[PBEffects::Confusion] > 0
      @effects[PBEffects::Confusion] -= 1
      if @effects[PBEffects::Confusion] <= 0
        pbCureConfusion
        @battle.pbDisplay(_INTL("\\j[{1},은,는] 혼란에서 벗어났다!", pbThis))
      else
        @battle.pbCommonAnimation("Confusion", self)
        @battle.pbDisplay(_INTL("\\j[{1},은,는] 혼란에 빠졌다!", pbThis))
        threshold = (Settings::MECHANICS_GENERATION >= 7) ? 33 : 50   # % chance
        if @battle.pbRandom(100) < threshold
          pbConfusionDamage(_INTL("It hurt itself in its confusion!"))
          PBDebug.log("[Move failed] #{pbThis} hurt itself in its confusion")
          @lastMoveFailed = true
          return false
        end
      end
    end
    # Paralysis
    if @status == :PARALYSIS && @battle.pbRandom(100) < 13
      pbContinueStatus
      PBDebug.log("[Move failed] #{pbThis} is paralyzed")
      @lastMoveFailed = true
      return false
    end
    # Infatuation
    if @effects[PBEffects::Attract] >= 0
      @battle.pbCommonAnimation("Attract", self)
      @battle.pbDisplay(_INTL("\\j[{1},은,는] {2}에게 헤롱헤롱하다!", pbThis,
                              @battle.battlers[@effects[PBEffects::Attract]].pbThis(true)))
      if @battle.pbRandom(100) < 50
        @battle.pbDisplay(_INTL("\\j[{1},은,는] 사랑에 빠져있다!", pbThis))
        PBDebug.log("[Move failed] #{pbThis} is immobilized by love")
        @lastMoveFailed = true
        return false
      end
    end
    return true
  end
end

Battle::Battler.prepend(BattlerPokemonChampionsFix)
