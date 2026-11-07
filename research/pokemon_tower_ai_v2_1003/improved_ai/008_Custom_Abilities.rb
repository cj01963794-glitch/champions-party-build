#===============================================================================
# Custom Ability: EERIECHILL (섬뜩한냉기)
# - Ice-type moves are super effective against Fire and Ghost types
# Uses pbCalcTypeModSingle override so SE text/sound displays correctly
#===============================================================================

class Battle::Move
  alias eeriechill_pbCalcTypeModSingle pbCalcTypeModSingle
  def pbCalcTypeModSingle(moveType, defType, user, target)
    ret = eeriechill_pbCalcTypeModSingle(moveType, defType, user, target)
    if moveType == :ICE && user.hasActiveAbility?(:EERIECHILL)
      if defType == :FIRE || defType == :GHOST
        ret = Effectiveness::SUPER_EFFECTIVE_MULTIPLIER
      end
    end
    return ret
  end
end

# AI type effectiveness awareness for Eerie Chill
class Battle::AI::AIBattler
  alias eeriechill_effectiveness effectiveness_of_type_against_battler
  def effectiveness_of_type_against_battler(type, user = nil, move = nil)
    ret = eeriechill_effectiveness(type, user, move)
    if type == :ICE && user&.has_active_ability?(:EERIECHILL)
      pbTypes(true).each do |defend_type|
        if (defend_type == :FIRE || defend_type == :GHOST) &&
           !Effectiveness.super_effective_type?(type, defend_type)
          # Undo the original calc for this type and apply SE instead
          original = Effectiveness.calculate(type, defend_type)
          ret = ret / original * Effectiveness::SUPER_EFFECTIVE_MULTIPLIER
        end
      end
    end
    return ret
  end
end

#===============================================================================
# Custom Ability: IRONSKIN (아이언스킨)
# - Normal-type moves become Steel-type with 1.2x power boost
# (Same mechanic as Pixilate/Aerilate/Refrigerate/Galvanize)
#===============================================================================

Battle::AbilityEffects::ModifyMoveBaseType.add(:IRONSKIN,
  proc { |ability, user, move, type|
    next if type != :NORMAL || !GameData::Type.exists?(:STEEL)
    move.powerBoost = true
    next :STEEL
  }
)

Battle::AbilityEffects::DamageCalcFromUser.copy(:AERILATE, :IRONSKIN)

#===============================================================================
# Custom Ability: DRAGONIZE (드래고나이즈)
# - Normal-type moves become Dragon-type with 1.2x power boost
# (Same mechanic as Pixilate/Aerilate/Refrigerate/Galvanize)
#===============================================================================

Battle::AbilityEffects::ModifyMoveBaseType.add(:DRAGONIZE,
  proc { |ability, user, move, type|
    next if type != :NORMAL || !GameData::Type.exists?(:DRAGON)
    move.powerBoost = true
    next :DRAGON
  }
)

Battle::AbilityEffects::DamageCalcFromUser.copy(:AERILATE, :DRAGONIZE)

#===============================================================================
# Custom Ability: FIREMANE
# - Fire-type version of Transistor.
#===============================================================================

Battle::AbilityEffects::DamageCalcFromUser.add(:FIREMANE,
  proc { |ability, user, target, move, mults, power, type|
    mults[:attack_multiplier] *= 1.5 if type == :FIRE
  }
)

#===============================================================================
# Custom Ability: PULSEGUARD
# - Halves damage from contact moves, regardless of damage category.
# - Unlike Fluffy, it has no Fire-type weakness.
#===============================================================================

Battle::AbilityEffects::DamageCalcFromTarget.add(:PULSEGUARD,
  proc { |ability, user, target, move, mults, power, type|
    mults[:final_damage_multiplier] /= 2 if move.pbContactMove?(user)
  }
)

#===============================================================================
# Custom Ability: EELEVATE
# - Combines Levitate and Beast Boost.
#===============================================================================

Battle::AbilityEffects::OnEndOfUsingMove.copy(:BEASTBOOST, :EELEVATE)

#===============================================================================
# Custom Ability: GRUDGECANDLE (미움불꽃)
# - Absorbs Dark-type moves (immune) and raises Speed by 1 stage
#===============================================================================

#===============================================================================
# Good as Gold fix: Mycelium Might bypasses the immunity
#===============================================================================
Battle::AbilityEffects::MoveImmunity.add(:GOODASGOLD,
  proc { |ability, user, target, move, type, battle, show_message|
    next false if !move.statusMove?
    next false if user.index == target.index
    next false if user.hasActiveAbility?(:MYCELIUMMIGHT)
    if show_message
      battle.pbShowAbilitySplash(target)
      if Battle::Scene::USE_ABILITY_SPLASH
        battle.pbDisplay(_INTL("It doesn't affect {1}...", target.pbThis(true)))
      else
        battle.pbDisplay(_INTL("{1}'s {2} blocks {3}!",
           target.pbThis, target.abilityName, move.name))
      end
      battle.pbHideAbilitySplash(target)
    end
    next true
  }
)

#===============================================================================
# Custom Ability: SPICYSPRAY (스파이시스프레이)
# - 100% burn chance when hit by any damage move (not just contact)
#===============================================================================

Battle::AbilityEffects::OnBeingHit.add(:SPICYSPRAY,
  proc { |ability, user, target, move, battle|
    next if move.statusMove?
    battle.pbShowAbilitySplash(target)
    if user.pbCanBurn?(target, Battle::Scene::USE_ABILITY_SPLASH)
      msg = nil
      if !Battle::Scene::USE_ABILITY_SPLASH
        msg = _INTL("{1}의 \\j[{2},이,가] {3}에게 화상을 입혔다!", target.pbThis, target.abilityName, user.pbThis(true))
      end
      user.pbBurn(target, msg)
    end
    battle.pbHideAbilitySplash(target)
  }
)

#===============================================================================
# Custom Ability: PIERCINGDRILL (관통드릴)
# - Contact moves bypass Protect and deal 1/4 damage through it
# (Same mechanic as the reworked Unseen Fist below)
#===============================================================================

# Override isProtected? to remove the Unseen Fist early-return.
# The move still goes through Protect (handled by pbSuccessCheckAgainstTarget),
# but isProtected? now reports true so the 1/4 damage multiplier can detect it.
class Battle::Battler
  def contactBypassProtect?(move)
    return move.pbContactMove?(self) && (hasActiveAbility?(:UNSEENFIST) || hasActiveAbility?(:PIERCINGDRILL))
  end
end

# Kept as reference for the base engine pbSuccessCheckAgainstTarget implementation.
module BattleAIImproved_SuccessCheckAgainstTarget
  def pbSuccessCheckAgainstTarget(move, user, target, targets)
    show_message = move.pbShowFailMessages?(targets)
    typeMod = move.pbCalcTypeMod(move.calcType, user, target)
    target.damageState.typeMod = typeMod
    # Two-turn attacks can't fail here in the charging turn
    return true if user.effects[PBEffects::TwoTurnAttack]
    # Move-specific failures
    if move.pbFailsAgainstTarget?(user, target, show_message)
      PBDebug.log(sprintf("[Move failed] In function code %s's def pbFailsAgainstTarget?", move.function_code))
      return false
    end
    # Immunity to priority moves because of Psychic Terrain
    if @battle.field.terrain == :Psychic && target.affectedByTerrain? && target.opposes?(user) &&
        @battle.choices[user.index][4] > 0   # Move priority saved from pbCalculatePriority
      @battle.pbDisplay(_INTL("\\j[{1},이,가] 사이코 필드를 펼쳤다", target.pbThis)) if show_message
      return false
    end
    # Crafty Shield
    if target.pbOwnSide.effects[PBEffects::CraftyShield] && user.index != target.index &&
        move.statusMove? && !move.pbTarget(user).targets_all
      if show_message
        @battle.pbCommonAnimation("CraftyShield", target)
        @battle.pbDisplay(_INTL("트릭가드가 \\j[{1},을,를] 지켰다!", target.pbThis(true)))
      end
      target.damageState.protected = true
      @battle.successStates[user.index].protected = true
      return false
    end
    # Wide Guard
    if target.pbOwnSide.effects[PBEffects::WideGuard] && user.index != target.index &&
        move.pbTarget(user).num_targets > 1 &&
        (Settings::MECHANICS_GENERATION >= 7 || move.damagingMove?)
      if show_message
        @battle.pbCommonAnimation("WideGuard", target)
        @battle.pbDisplay(_INTL("와이드가드가 \\j[{1},을,를] 지켰다!", target.pbThis(true)))
      end
      target.damageState.protected = true
      @battle.successStates[user.index].protected = true
      return user.contactBypassProtect?(move) ? true : false
    end
    if move.canProtectAgainst?
      # Quick Guard
      if target.pbOwnSide.effects[PBEffects::QuickGuard] &&
          @battle.choices[user.index][4] > 0   # Move priority saved from pbCalculatePriority
        if show_message
          @battle.pbCommonAnimation("QuickGuard", target)
          @battle.pbDisplay(_INTL("패스트가드가 \\j[{1},을,를] 지켰다!", target.pbThis(true)))
        end
        target.damageState.protected = true
        @battle.successStates[user.index].protected = true
        return user.contactBypassProtect?(move) ? true : false
      end
      # Protect
      if target.effects[PBEffects::Protect]
        if show_message
          @battle.pbCommonAnimation("Protect", target)
          @battle.pbDisplay(_INTL("\\j[{1},은,는] 스스로를 지켰다!", target.pbThis))
        end
        target.damageState.protected = true
        @battle.successStates[user.index].protected = true
        return user.contactBypassProtect?(move) ? true : false
      end
      # King's Shield
      if target.effects[PBEffects::KingsShield] && move.damagingMove?
        if show_message
          @battle.pbCommonAnimation("KingsShield", target)
          @battle.pbDisplay(_INTL("\\j[{1},은,는] 스스로를 지켰다!", target.pbThis))
        end
        target.damageState.protected = true
        @battle.successStates[user.index].protected = true
        if move.pbContactMove?(user) && user.affectedByContactEffect? &&
            user.pbCanLowerStatStage?(:ATTACK, target)
          user.pbLowerStatStage(:ATTACK, (Settings::MECHANICS_GENERATION >= 8) ? 1 : 2, target)
        end
        return user.contactBypassProtect?(move) ? true : false
      end
      # Spiky Shield
      if target.effects[PBEffects::SpikyShield]
        if show_message
          @battle.pbCommonAnimation("SpikyShield", target)
          @battle.pbDisplay(_INTL("\\j[{1},은,는] 스스로를 지켰다!", target.pbThis))
        end
        target.damageState.protected = true 
        @battle.successStates[user.index].protected = true 
        if move.pbContactMove?(user) && user.affectedByContactEffect? && user.takesIndirectDamage?
          @battle.scene.pbDamageAnimation(user)
          user.pbReduceHP(user.totalhp / 8, false)
          @battle.pbDisplay(_INTL("\\j[{1},은,는] 데미지를 입었다!", user.pbThis))
          user.pbItemHPHealCheck
        end
        return user.contactBypassProtect?(move) ? true : false
      end
      # Baneful Bunker
      if target.effects[PBEffects::BanefulBunker]
        if show_message
          @battle.pbCommonAnimation("BanefulBunker", target)
          @battle.pbDisplay(_INTL("\\j[{1},은,는] 스스로를 지켰다!", target.pbThis))
        end
        target.damageState.protected = true 
        @battle.successStates[user.index].protected = true
        if move.pbContactMove?(user) && user.affectedByContactEffect? &&
            user.pbCanPoison?(target, false)
          user.pbPoison(target)
        end
        return user.contactBypassProtect?(move) ? true : false
      end
      # Obstruct
      if target.effects[PBEffects::Obstruct] && move.damagingMove?
        if show_message
          @battle.pbCommonAnimation("Obstruct", target)
          @battle.pbDisplay(_INTL("\\j[{1},은,는] 스스로를 지켰다!", target.pbThis))
        end
        target.damageState.protected = true 
        @battle.successStates[user.index].protected = true 
        if move.pbContactMove?(user) && user.affectedByContactEffect? &&
            user.pbCanLowerStatStage?(:DEFENSE, target)
          user.pbLowerStatStage(:DEFENSE, 2, target)
        end
        return user.contactBypassProtect?(move) ? true : false
      end
      # Mat Block
      if target.pbOwnSide.effects[PBEffects::MatBlock] && move.damagingMove?
        # NOTE: Confirmed no common animation for this effect.
        @battle.pbDisplay(_INTL("\\j[{1},은,는] 마룻바닥을 세워 같은 편을 지켰다!", move.name)) if show_message
        target.damageState.protected = true 
        @battle.successStates[user.index].protected = true 
      end
    end
    # Magic Coat/Magic Bounce
    if move.statusMove? && move.canMagicCoat? && !target.semiInvulnerable? && target.opposes?(user)
      if target.effects[PBEffects::MagicCoat]
        target.damageState.magicCoat = true
        target.effects[PBEffects::MagicCoat] = false
        return false
      end
      if target.hasActiveAbility?(:MAGICBOUNCE) && !@battle.moldBreaker &&
          !target.effects[PBEffects::MagicBounce]
        target.damageState.magicBounce = true
        target.effects[PBEffects::MagicBounce] = true
        return false
      end
    end
    # Immunity because of ability (intentionally before type immunity check)
    return false if move.pbImmunityByAbility(user, target, show_message)
    # Type immunity
    if move.pbDamagingMove? && Effectiveness.ineffective?(typeMod)
      PBDebug.log("[Target immune] #{target.pbThis}'s type immunity")
      @battle.pbDisplay(_INTL("It doesn't affect {1}...", target.pbThis(true))) if show_message
      return false
    end
    # Dark-type immunity to moves made faster by Prankster
    if Settings::MECHANICS_GENERATION >= 7 && user.effects[PBEffects::Prankster] &&
        target.pbHasType?(:DARK) && target.opposes?(user)
      PBDebug.log("[Target immune] #{target.pbThis} is Dark-type and immune to Prankster-boosted moves")
      @battle.pbDisplay(_INTL("It doesn't affect {1}...", target.pbThis(true))) if show_message
      return false
    end
    # Airborne-based immunity to Ground moves
    if move.damagingMove? && move.calcType == :GROUND &&
        target.airborne? && !move.hitsFlyingTargets?
      if target.hasActiveAbility?([:LEVITATE, :EELEVATE]) && !@battle.moldBreaker
        if show_message
          @battle.pbShowAbilitySplash(target)
          if Battle::Scene::USE_ABILITY_SPLASH
            @battle.pbDisplay(_INTL("\\j[{1},은,는] 공격을 피했다!", target.pbThis))
          else
            @battle.pbDisplay(_INTL("\\j[{1},은,는] \\j[{2},으로,로] 공격을 피했다!", target.pbThis, target.abilityName))
          end
          @battle.pbHideAbilitySplash(target)
        end
        return false
      end
      if target.hasActiveItem?(:AIRBALLOON)
        @battle.pbDisplay(_INTL("{1}의 \\j[{2},으로,로] 땅 타입 공격이 맞지 않는다!", target.pbThis, target.itemName)) if show_message
        return false
      end
      if target.effects[PBEffects::MagnetRise] > 0
        @battle.pbDisplay(_INTL("\\j[{1},은,는] 전자부유 상태라 땅 타입 공격이 맞지 않는다!", target.pbThis)) if show_message
        return false
      end
      if target.effects[PBEffects::Telekinesis] > 0
        @battle.pbDisplay(_INTL("\\j[{1},은,는] 텔레키네시스에 붙잡혀 땅 타입 공격이 맞지 않는다!", target.pbThis)) if show_message
        return false
      end
    end
    # Immunity to powder-based moves
    if move.powderMove?
      if target.pbHasType?(:GRASS) && Settings::MORE_TYPE_EFFECTS
        PBDebug.log("[Target immune] #{target.pbThis} is Grass-type and immune to powder-based moves")
        @battle.pbDisplay(_INTL("It doesn't affect {1}...", target.pbThis(true))) if show_message
        return false
      end
      if Settings::MECHANICS_GENERATION >= 6
        if target.hasActiveAbility?(:OVERCOAT) && !@battle.moldBreaker
          if show_message
            @battle.pbShowAbilitySplash(target)
            if Battle::Scene::USE_ABILITY_SPLASH
              @battle.pbDisplay(_INTL("It doesn't affect {1}...", target.pbThis(true)))
            else
              @battle.pbDisplay(_INTL("{1}의 \\j[{2},으로,로] 인해 효과가 없었다.", target.pbThis(true), target.abilityName))
            end
            @battle.pbHideAbilitySplash(target)
          end
          return false
        end
        if target.hasActiveItem?(:SAFETYGOGGLES)
          PBDebug.log("[Item triggered] #{target.pbThis} has Safety Goggles and is immune to powder-based moves")
          @battle.pbDisplay(_INTL("It doesn't affect {1}...", target.pbThis(true))) if show_message
          return false
        end
      end
    end
    # Substitute
    if target.effects[PBEffects::Substitute] > 0 && move.statusMove? &&
        !move.ignoresSubstitute?(user) && user.index != target.index
      PBDebug.log("[Target immune] #{target.pbThis} is protected by its Substitute")
      @battle.pbDisplay(_INTL("\\j[{1},은,는] 공격을 피했다!", target.pbThis(true))) if show_message
      return false
    end
    return true
  end
end
class Battle::Battler
  def isProtected?(user, move)
    return false if move.function_code == "IgnoreProtections"
    return true if @damageState.protected
    return true if pbOwnSide.effects[PBEffects::MatBlock]
    return true if pbOwnSide.effects[PBEffects::WideGuard] &&
                   GameData::Target.get(move.target).num_targets > 1
    [:Protect, :KingsShield, :SpikyShield, :BanefulBunker, :Obstruct,
     :SilkTrap, :BurningBulwark, :MaxGuard].each do |id|
      next if !PBEffects.const_defined?(id)
      return true if @effects[PBEffects.const_get(id)]
    end
    return false
  end

  # unseen fist no longer bypasses everything for protect in successcheck, so add this here
  alias pokemonchampions_affectedByContactEffect? affectedByContactEffect?
  def affectedByContactEffect?(showMsg = false)
    return true if self.hasActiveAbility?(:UNSEENFIST) || self.hasActiveAbility?(:PIERCINGDRILL)
    return pokemonchampions_affectedByContactEffect?
  end

  alias pokemonchampions_pbEffectsAfterMove pbEffectsAfterMove
  def pbEffectsAfterMove(user, targets, move, numHits)
    if move.damagingMove? && user.contactBypassProtect?(move)
      targets.each do |b|
        next if b.damageState.unaffected
        next if !b.isProtected?(user, move)
        @battle.pbDisplay(JosaProcessor.process(_INTL("\\j[{1},은,는] 완전히 막지 못하고 데미지를 입었다!", b.pbThis)))
      end
    end
    pokemonchampions_pbEffectsAfterMove(user, targets, move, numHits)
  end
end

#===============================================================================
# Custom Ability: MEGASOL (메가솔라)
# - When using moves, effectiveWeather returns :Sun for this battler.
#   Solar Beam charges instantly, Weather Ball becomes Fire-type with
#   doubled power + 1.5x sun bonus, fire moves 1.5x, water moves 0.5x.
# - Overrides all weathers including primal.
# - Only active during the user's own move execution.
#===============================================================================

class Battle::Battler
  alias megasol_pbUseMove pbUseMove
  def pbUseMove(choice, specialUsage = false)
    if hasActiveAbility?(:MEGASOL)
      @megasol_active = true
      begin
        return megasol_pbUseMove(choice, specialUsage)
      ensure
        @megasol_active = false
      end
    else
      return megasol_pbUseMove(choice, specialUsage)
    end
  end

  alias megasol_effectiveWeather effectiveWeather
  def effectiveWeather
    return :Sun if @megasol_active
    return megasol_effectiveWeather
  end
end

Battle::AbilityEffects::MoveImmunity.add(:GRUDGECANDLE,
  proc { |ability, user, target, move, type, battle, show_message|
    next target.pbMoveImmunityStatRaisingAbility(user, move, type,
       :DARK, :SPEED, 1, show_message)
  }
)
