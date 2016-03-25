package Game::Mechanics;

use strict;
use warnings;
use Util;

# INJECTIONNNN

package Game::StdLib::Character;

use POSIX ("ceil");

# Because weapon and fire share these
my $customize = sub {
  my ($attack, $self) = @_;
  # A weapon can customize!
  return unless my $dat = (ref $self->{Equipment}{Weapon})->Attack;
  @$attack{ keys %$dat } = values %$dat;
};

my $hitmiss = sub {
  my ($self, $target) = @_;
  my $weapon = $self->{Equipment}{Weapon};
  my $dext = int($self->affinity($weapon) * $self->{Dext}->value);
  my $accuracy = $weapon->accuracy;
  my $hit = $dext + $accuracy;
  my $dont = $target->ev;
  return $hit > $dont;
};

my $damage = sub {
  my ($self, $target) = @_;
  my $weapon = $self->{Equipment}{Weapon};

  my $pow = $weapon->power;
  my $str = int($self->affinity($weapon) * $self->{Str}->value);
  my $atk = $pow + $str;
  $atk /= 2 if $weapon->is("RangedWeapon");  # Because that's just silly
  my $def = $target->ac; 
  return $atk - $def; 
};

__PACKAGE__->classdat(
  Attacks  => {
    weapon => Game::Attack->new(
      Name      => "weapon",
      Range     => ["adj"],
      Lag       => "weapon",
      Check     => sub {
        my $self = shift;
        return STOP($self, "[subj] has no weapon!") unless my $weapon = $self->{Equipment}{Weapon};
      },
      HitMiss   => $hitmiss,
      Damage    => $damage,
      Customize => $customize
    ),
    fireweapon => Game::Attack->new(
      Name      => "fireweapon",
      Lag       => "weapon",
      Check     => sub {
        my $self = shift;
        return STOP($self, "[subj] has no weapon!") unless my $weapon = $self->{Equipment}{Weapon};
        return STOP($self, "Can't fire a non-projectile!") unless $weapon->is("RangedWeapon");
        if (my $ammo = $weapon->Ammo) {
          return STOP($self, "[subj] has no $ammo ammo!") unless $self->findinv($ammo);
        }
      },
      Range     => ["fire", sub { shift()->{Equipment}{Weapon}->Range } ],
      Draw      => sub { [shift()->{Equipment}{Weapon}->Projectile] },
      HitMiss   => $hitmiss,
      Damage    => $damage,
      Customize => $customize,
      After     => sub {
        my ($attack, $heap, $self) = @_;
        return unless my $ammo = $self->{Equipment}{Weapon}->Ammo;
        my ($nuke) = $self->findinv($ammo);
        $self->saymsg("[subj] has run out of $ammo ammo!") if !$nuke->destroy;
      }
    )
  }
);

# Step function to determine how a character class affects attacks/whatever
sub affinity {
  my ($self, $with) = @_;
  # TODO: as a fxn of level would be great too
  my $ratio;
  my $lvl = $self->{Level};
  if ($lvl <= 3) {
    $ratio = 0.6;
  } elsif ($lvl <= 6) {
    $ratio = 0.7;
  } elsif ($lvl <= 10) {
    $ratio = 0.9;
  } else {
    $ratio = 1;
  }
  $ratio /= 2 unless $with->Affinity eq "ANY" or $with->Affinity eq $self->Affinity;
  return $ratio;
}

# Derived stats
sub ac {
  my $self = shift;
  my $ac = 0;
  if (my $armour = $self->{Equipment}{Mask}) {
    $ac += $armour->power;
  }
  my $def = $self->{Def}->value;
  $ac += random($def / 2, $def);
  $ac += $self->{ACMod};
  return $ac;
}

sub ev {
  my $self = shift;
  my $ev = 0;
  if (my $armour = $self->{Equipment}{Mask}) {
    $ev += 0.5 * $armour->accuracy;
  }
  my $dodg = $self->{Dext}->value;
  $ev += random(0.2 * $dodg, 0.5 * $dodg);
  $ev += $self->{EVMod};
  return $ev;
}

# Out of depth
sub ood {
  my ($self, $z) = @_;
  return 0 unless defined $z;  # TODO we should always have depth really, but eh
  $z = 0 unless $z =~ m/^\d+$/;
  return ceil($z / CFG->{Scale}{DLvlRatio}) - $self->Rank;
}

package Game::StdLib::Character::Player;

# How much till next?
sub nextexp {
  my ($self, $lvl) = @_;
  if ($lvl) {
    return 0 if $lvl == 1;
    return $self->{XPCache}{$lvl} if $self->{XPCache}{$lvl};
    my $xp = $self->nextexp($lvl - 1);
    if ($lvl > 5) {
      $xp += int($self->ExpCurve * (2.0 ** $lvl));
    } elsif ($lvl >= 3) {
      $xp += int($self->ExpCurve * (3.0 ** $lvl)) + 10;
    } else {
      $xp += int($self->ExpCurve * (3.0 ** $lvl)) + 30;
    }
    $self->{XPCache}{$lvl} = $xp;
  } else {
    return $self->nextexp($self->{Level} + 1);
  }
}

42;
